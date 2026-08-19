import type { RecoveryDTO, WorkoutDTO } from './types';
import { ymd } from './http';

/** A linked Garmin account: the OAuth tokens plus the Garmin user id that
 *  webhook pushes are keyed on. */
export interface Session {
  garminUserId: string;
  accessToken: string;
  refreshToken?: string;
  createdAt: number;
}

/** An in-flight OAuth attempt, holding the PKCE verifier until the callback. */
export interface Pending {
  verifier: string;
  createdAt: number;
}

/**
 * Everything the handlers persist. Deliberately small and date-keyed so it maps
 * cleanly onto Redis hashes and onto the idempotent, upsert-by-date webhook the
 * Garmin contract requires.
 */
export interface Store {
  putPending(state: string, p: Pending): Promise<void>;
  takePending(state: string): Promise<Pending | null>;
  putSession(token: string, s: Session): Promise<void>;
  getSession(token: string): Promise<Session | null>;
  deleteSession(token: string): Promise<void>;
  linkUser(garminUserId: string, token: string): Promise<void>;
  getUserToken(garminUserId: string): Promise<string | null>;
  getDaily(userId: string, day: string): Promise<RecoveryDTO | null>;
  putDaily(userId: string, rec: RecoveryDTO): Promise<void>;
  getDailyRange(userId: string, start: Date, end: Date): Promise<RecoveryDTO[]>;
  putWorkout(userId: string, w: WorkoutDTO): Promise<void>;
  getWorkoutRange(userId: string, start: Date, end: Date): Promise<WorkoutDTO[]>;
}

const PENDING_TTL_S = 600;
const LEGACY_SCAN_PAGE_SIZE = 100;

function inDailyRange(day: string, start: Date, end: Date): boolean {
  return day >= ymd(start) && day <= ymd(end);
}

function inWorkoutRange(w: WorkoutDTO, start: Date, end: Date): boolean {
  const t = new Date(w.startTime).getTime();
  return t >= start.getTime() && t <= end.getTime();
}

/**
 * Process-memory store. Survives only within a single running process, so it is
 * for `vercel dev` and the seed test — never production, where each serverless
 * invocation is a fresh process. Configure Upstash to persist.
 */
class InMemoryStore implements Store {
  private pending = new Map<string, Pending>();
  private sessions = new Map<string, Session>();
  private users = new Map<string, string>();
  private daily = new Map<string, Map<string, RecoveryDTO>>();
  private workouts = new Map<string, Map<string, WorkoutDTO>>();

  private dailyOf(u: string) {
    return this.daily.get(u) ?? this.daily.set(u, new Map()).get(u)!;
  }
  private workoutsOf(u: string) {
    return this.workouts.get(u) ?? this.workouts.set(u, new Map()).get(u)!;
  }

  async putPending(state: string, p: Pending) {
    this.pending.set(state, p);
  }
  async takePending(state: string) {
    const p = this.pending.get(state) ?? null;
    this.pending.delete(state);
    if (p && Date.now() - p.createdAt > PENDING_TTL_S * 1000) return null;
    return p;
  }
  async putSession(token: string, s: Session) {
    this.sessions.set(token, s);
  }
  async getSession(token: string) {
    return this.sessions.get(token) ?? null;
  }
  async deleteSession(token: string) {
    this.sessions.delete(token);
  }
  async linkUser(garminUserId: string, token: string) {
    this.users.set(garminUserId, token);
  }
  async getUserToken(garminUserId: string) {
    return this.users.get(garminUserId) ?? null;
  }
  async getDaily(userId: string, day: string) {
    return this.dailyOf(userId).get(day) ?? null;
  }
  async putDaily(userId: string, rec: RecoveryDTO) {
    this.dailyOf(userId).set(rec.date, rec);
  }
  async getDailyRange(userId: string, start: Date, end: Date) {
    return [...this.dailyOf(userId).values()]
      .filter((r) => inDailyRange(r.date, start, end))
      .sort((a, b) => a.date.localeCompare(b.date));
  }
  async putWorkout(userId: string, w: WorkoutDTO) {
    this.workoutsOf(userId).set(w.id, w);
  }
  async getWorkoutRange(userId: string, start: Date, end: Date) {
    return [...this.workoutsOf(userId).values()]
      .filter((w) => inWorkoutRange(w, start, end))
      .sort((a, b) => a.startTime.localeCompare(b.startTime));
  }
}

/**
 * Upstash Redis (HTTP) store — the serverless-friendly default. Records live in
 * individual keys with sorted-set date indexes, so a range read scales with the
 * requested interval instead of the user's lifetime history.
 *
 * Earlier releases used per-user hashes. The first operation for each data type
 * migrates that hash idempotently, then removes it. A failed partial migration is
 * safe to retry because the destination keys and index members are stable.
 */
class UpstashStore implements Store {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  private clientPromise: Promise<any> | null = null;

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  private client(): Promise<any> {
    if (!this.clientPromise) {
      this.clientPromise = import('@upstash/redis').then((m) => m.Redis.fromEnv());
    }
    return this.clientPromise;
  }

  private dailyIndex(userId: string) {
    return `daily-index:${userId}`;
  }
  private dailyItem(userId: string, day: string) {
    return `daily-item:${userId}:${day}`;
  }
  private workoutIndex(userId: string) {
    return `wo-index:${userId}`;
  }
  private workoutItem(userId: string, id: string) {
    return `wo-item:${userId}:${id}`;
  }
  private migrationMarker(kind: 'daily' | 'wo', userId: string) {
    return `migrated:${kind}:${userId}`;
  }

  private async ensureDailyMigrated(userId: string): Promise<void> {
    const r = await this.client();
    const marker = this.migrationMarker('daily', userId);
    if (await r.get(marker)) return;

    const legacyKey = `daily:${userId}`;
    let cursor = '0';
    do {
      const [nextCursor, entries] = await r.hscan(legacyKey, cursor, {
        count: LEGACY_SCAN_PAGE_SIZE,
      }) as [string, unknown[]];
      if (entries.length) {
        const pipeline = r.pipeline();
        for (let index = 0; index + 1 < entries.length; index += 2) {
          const day = String(entries[index]);
          const value = entries[index + 1];
          const record = typeof value === 'string' ? value : JSON.stringify(value);
          pipeline.set(this.dailyItem(userId, day), record);
          pipeline.zadd(this.dailyIndex(userId), { score: dayScore(day), member: day });
        }
        await pipeline.exec();
      }
      cursor = nextCursor;
    } while (cursor !== '0');

    const completion = r.pipeline();
    completion.set(marker, '1');
    completion.del(legacyKey);
    await completion.exec();
  }

  private async ensureWorkoutsMigrated(userId: string): Promise<void> {
    const r = await this.client();
    const marker = this.migrationMarker('wo', userId);
    if (await r.get(marker)) return;

    const legacyKey = `wo:${userId}`;
    let cursor = '0';
    do {
      const [nextCursor, entries] = await r.hscan(legacyKey, cursor, {
        count: LEGACY_SCAN_PAGE_SIZE,
      }) as [string, unknown[]];
      if (entries.length) {
        const pipeline = r.pipeline();
        for (let index = 0; index + 1 < entries.length; index += 2) {
          const id = String(entries[index]);
          const value = entries[index + 1];
          const workout = typeof value === 'string'
            ? JSON.parse(value) as WorkoutDTO
            : value as WorkoutDTO;
          pipeline.set(this.workoutItem(userId, id), JSON.stringify(workout));
          pipeline.zadd(this.workoutIndex(userId), {
            score: new Date(workout.startTime).getTime(),
            member: id,
          });
        }
        await pipeline.exec();
      }
      cursor = nextCursor;
    } while (cursor !== '0');

    const completion = r.pipeline();
    completion.set(marker, '1');
    completion.del(legacyKey);
    await completion.exec();
  }

  async putPending(state: string, p: Pending) {
    const r = await this.client();
    await r.set(`pending:${state}`, JSON.stringify(p), { ex: PENDING_TTL_S });
  }
  async takePending(state: string) {
    const r = await this.client();
    const key = `pending:${state}`;
    const raw = await r.get(key);
    await r.del(key);
    return raw ? (typeof raw === 'string' ? (JSON.parse(raw) as Pending) : (raw as Pending)) : null;
  }
  async putSession(token: string, s: Session) {
    const r = await this.client();
    await r.set(`session:${token}`, JSON.stringify(s));
  }
  async getSession(token: string) {
    const r = await this.client();
    const raw = await r.get(`session:${token}`);
    return raw ? (typeof raw === 'string' ? (JSON.parse(raw) as Session) : (raw as Session)) : null;
  }
  async deleteSession(token: string) {
    const r = await this.client();
    await r.del(`session:${token}`);
  }
  async linkUser(garminUserId: string, token: string) {
    const r = await this.client();
    await r.set(`user:${garminUserId}`, token);
  }
  async getUserToken(garminUserId: string) {
    const r = await this.client();
    return (await r.get(`user:${garminUserId}`)) as string | null;
  }
  async getDaily(userId: string, day: string) {
    await this.ensureDailyMigrated(userId);
    const r = await this.client();
    const raw = await r.get(this.dailyItem(userId, day));
    return raw ? (typeof raw === 'string' ? (JSON.parse(raw) as RecoveryDTO) : (raw as RecoveryDTO)) : null;
  }
  async putDaily(userId: string, rec: RecoveryDTO) {
    await this.ensureDailyMigrated(userId);
    const r = await this.client();
    const pipeline = r.pipeline();
    pipeline.set(this.dailyItem(userId, rec.date), JSON.stringify(rec));
    pipeline.zadd(this.dailyIndex(userId), { score: dayScore(rec.date), member: rec.date });
    await pipeline.exec();
  }
  async getDailyRange(userId: string, start: Date, end: Date) {
    await this.ensureDailyMigrated(userId);
    const r = await this.client();
    const days = await r.zrange(this.dailyIndex(userId), dayScore(ymd(start)), dayScore(ymd(end)), {
      byScore: true,
    }) as string[];
    if (!days.length) return [];
    const values = await r.mget(...days.map((day) => this.dailyItem(userId, day))) as unknown[];
    return values
      .filter((value): value is NonNullable<typeof value> => value != null)
      .map((value) => typeof value === 'string'
        ? JSON.parse(value) as RecoveryDTO
        : value as RecoveryDTO)
      .sort((a, b) => a.date.localeCompare(b.date));
  }
  async putWorkout(userId: string, w: WorkoutDTO) {
    await this.ensureWorkoutsMigrated(userId);
    const r = await this.client();
    const pipeline = r.pipeline();
    pipeline.set(this.workoutItem(userId, w.id), JSON.stringify(w));
    pipeline.zadd(this.workoutIndex(userId), {
      score: new Date(w.startTime).getTime(),
      member: w.id,
    });
    await pipeline.exec();
  }
  async getWorkoutRange(userId: string, start: Date, end: Date) {
    await this.ensureWorkoutsMigrated(userId);
    const r = await this.client();
    const ids = await r.zrange(this.workoutIndex(userId), start.getTime(), end.getTime(), {
      byScore: true,
    }) as string[];
    if (!ids.length) return [];
    const values = await r.mget(...ids.map((id) => this.workoutItem(userId, id))) as unknown[];
    return values
      .filter((value): value is NonNullable<typeof value> => value != null)
      .map((value) => typeof value === 'string'
        ? JSON.parse(value) as WorkoutDTO
        : value as WorkoutDTO)
      .sort((a, b) => a.startTime.localeCompare(b.startTime));
  }
}

function dayScore(day: string): number {
  const value = Date.parse(`${day}T00:00:00Z`);
  if (!Number.isFinite(value)) throw new Error(`Invalid recovery date: ${day}`);
  return value;
}

let cached: Store | null = null;

/** One store per process. Upstash when configured, in-memory otherwise. */
export function getStore(): Store {
  if (!cached) {
    const production = process.env.VERCEL_ENV === 'production' || process.env.NODE_ENV === 'production';
    if (production && !process.env.UPSTASH_REDIS_REST_URL) {
      throw new Error('UPSTASH_REDIS_REST_URL is required in production');
    }
    cached = process.env.UPSTASH_REDIS_REST_URL ? new UpstashStore() : new InMemoryStore();
  }
  return cached;
}
