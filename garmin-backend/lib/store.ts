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
 * Upstash Redis (HTTP) store — the serverless-friendly default. Daily records
 * and workouts live in per-user hashes so a webhook can upsert one field and a
 * range read pulls the hash and filters in memory. `@upstash/redis` is imported
 * lazily so the in-memory path has no dependency on it.
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
    const r = await this.client();
    const raw = await r.hget(`daily:${userId}`, day);
    return raw ? (typeof raw === 'string' ? (JSON.parse(raw) as RecoveryDTO) : (raw as RecoveryDTO)) : null;
  }
  async putDaily(userId: string, rec: RecoveryDTO) {
    const r = await this.client();
    await r.hset(`daily:${userId}`, { [rec.date]: JSON.stringify(rec) });
  }
  async getDailyRange(userId: string, start: Date, end: Date) {
    const r = await this.client();
    const all = ((await r.hgetall(`daily:${userId}`)) ?? {}) as Record<string, unknown>;
    return Object.values(all)
      .map((v) => (typeof v === 'string' ? (JSON.parse(v) as RecoveryDTO) : (v as RecoveryDTO)))
      .filter((rec) => inDailyRange(rec.date, start, end))
      .sort((a, b) => a.date.localeCompare(b.date));
  }
  async putWorkout(userId: string, w: WorkoutDTO) {
    const r = await this.client();
    await r.hset(`wo:${userId}`, { [w.id]: JSON.stringify(w) });
  }
  async getWorkoutRange(userId: string, start: Date, end: Date) {
    const r = await this.client();
    const all = ((await r.hgetall(`wo:${userId}`)) ?? {}) as Record<string, unknown>;
    return Object.values(all)
      .map((v) => (typeof v === 'string' ? (JSON.parse(v) as WorkoutDTO) : (v as WorkoutDTO)))
      .filter((w) => inWorkoutRange(w, start, end))
      .sort((a, b) => a.startTime.localeCompare(b.startTime));
  }
}

let cached: Store | null = null;

/** One store per process. Upstash when configured, in-memory otherwise. */
export function getStore(): Store {
  if (!cached) {
    cached = process.env.UPSTASH_REDIS_REST_URL ? new UpstashStore() : new InMemoryStore();
  }
  return cached;
}
