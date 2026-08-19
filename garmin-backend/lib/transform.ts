import type { RecoveryDTO, SleepDTO, WorkoutDTO } from './types';
import type { Store } from './store';
import { toGarminISO } from './http';

/**
 * Turn a Garmin webhook batch into stored records.
 *
 * Garmin pushes objects grouped by summary type — `dailies`, `sleeps`, `hrv`,
 * `activities`. Each summary carries a `userId` and (for day summaries) a
 * `calendarDate`; several types land on the same date and are merged into one
 * `RecoveryDTO`.
 *
 * The field names below are Garmin Health API summary fields. They are the part
 * most worth VERIFYING against your onboarding spec — Garmin versions the
 * schema. Everything is defensive: an unrecognised or partial summary is
 * skipped, never thrown, because a 5xx makes Garmin redeliver the whole batch.
 */
export async function ingest(store: Store, payload: unknown): Promise<void> {
  const body = (payload ?? {}) as Record<string, unknown>;
  const dailies = asArray(body.dailies);
  const sleeps = asArray(body.sleeps ?? body.sleep);
  const hrv = asArray(body.hrv ?? body.hrvSummaries ?? body.hrvs);
  const activities = asArray(body.activities ?? body.activityDetails);

  for (const d of dailies) {
    const uid = userId(d);
    const date = calendarDate(d);
    if (uid && date) await mergeDaily(store, uid, date, fromDaily(d));
  }
  for (const s of sleeps) {
    const uid = userId(s);
    const date = calendarDate(s);
    const sleep = fromSleep(s);
    if (uid && date && sleep) await mergeDaily(store, uid, date, { sleep });
  }
  for (const h of hrv) {
    const uid = userId(h);
    const date = calendarDate(h);
    if (uid && date) await mergeDaily(store, uid, date, fromHrv(h));
  }
  for (const a of activities) {
    const uid = userId(a);
    const w = fromActivity(a);
    if (uid && w) await store.putWorkout(uid, w);
  }
}

/** Fill only the fields this summary provides, leaving the rest of the day intact. */
async function mergeDaily(
  store: Store,
  userId: string,
  date: string,
  patch: Partial<RecoveryDTO>,
): Promise<void> {
  const existing = (await store.getDaily(userId, date)) ?? { date };
  const merged: RecoveryDTO = { ...existing, ...patch, date };
  await store.putDaily(userId, merged);
}

// MARK: - Garmin summary → SuperFit fields

function fromDaily(d: Record<string, unknown>): Partial<RecoveryDTO> {
  return {
    restingHeartRate: num(d.restingHeartRateInBeatsPerMinute ?? d.restingHeartRate),
    bodyBattery: int(
      d.bodyBatteryMostRecentValue ?? d.bodyBatteryHighestValue ?? d.bodyBattery,
    ),
  };
}

function fromHrv(h: Record<string, unknown>): Partial<RecoveryDTO> {
  // Garmin's nightly HRV average, in milliseconds. The app treats it as the HRV
  // magnitude regardless of derivation (SDNN vs rMSSD); it is compared only
  // against the user's own baseline.
  return { hrvSDNN: num(h.lastNightAvg ?? h.hrvSummary ?? h.weeklyAvg) };
}

function fromSleep(s: Record<string, unknown>): SleepDTO | undefined {
  const deep = toMin(s.deepSleepDurationInSeconds);
  const rem = toMin(s.remSleepInSeconds ?? s.remSleepDurationInSeconds);
  const light = toMin(s.lightSleepDurationInSeconds);
  const awake = toMin(s.awakeDurationInSeconds);
  const asleep = s.durationInSeconds != null ? toMin(s.durationInSeconds) : deep + rem + light;
  if (asleep <= 0) return undefined; // a night with no measured sleep is absent, not zero
  const inBed = asleep + awake;

  const startSec = num(s.startTimeInSeconds);
  const bedtime = startSec != null ? toGarminISO(new Date(startSec * 1000)) : undefined;
  const wakeTime =
    startSec != null ? toGarminISO(new Date((startSec + inBed * 60) * 1000)) : undefined;

  return {
    inBedMinutes: inBed,
    asleepMinutes: asleep,
    deepMinutes: deep,
    remMinutes: rem,
    lightMinutes: light,
    bedtime,
    wakeTime,
  };
}

function fromActivity(a: Record<string, unknown>): WorkoutDTO | undefined {
  const id = String(a.summaryId ?? a.activityId ?? a.activityUuid ?? '');
  const startSec = num(a.startTimeInSeconds);
  if (!id || startSec == null) return undefined;
  return {
    id,
    startTime: toGarminISO(new Date(startSec * 1000)),
    durationSeconds: num(a.durationInSeconds) ?? 0,
    activityType: String(a.activityType ?? 'other').toLowerCase(),
    activeKilocalories: num(a.activeKilocalories),
    distanceMeters: num(a.distanceInMeters),
    averageHeartRate: num(a.averageHeartRateInBeatsPerMinute),
    maxHeartRate: num(a.maxHeartRateInBeatsPerMinute),
    elevationGainMeters: num(a.totalElevationGainInMeters),
    averageCadence: num(
      a.averageRunCadenceInStepsPerMinute ?? a.averageBikeCadenceInRoundsPerMinute,
    ),
    averagePowerWatts: num(a.averagePowerInWatts),
    aerobicTrainingEffect: num(a.aerobicTrainingEffect),
    anaerobicTrainingEffect: num(a.anaerobicTrainingEffect),
  };
}

// MARK: - Coercion helpers

function asArray(v: unknown): Record<string, unknown>[] {
  return Array.isArray(v) ? (v as Record<string, unknown>[]) : [];
}

function userId(x: Record<string, unknown>): string | null {
  const id = x.userId ?? x.userAccessToken;
  return id != null && String(id) ? String(id) : null;
}

function calendarDate(x: Record<string, unknown>): string | null {
  const d = x.calendarDate ?? x.summaryDate;
  return typeof d === 'string' && /^\d{4}-\d{2}-\d{2}/.test(d) ? d.slice(0, 10) : null;
}

/** A finite number, or undefined — nulls and NaN become "not measured". */
function num(v: unknown): number | undefined {
  const n = typeof v === 'number' ? v : typeof v === 'string' ? Number(v) : NaN;
  return Number.isFinite(n) ? n : undefined;
}

/** An integer, or undefined. Swift decodes bodyBattery and sleep minutes as Int. */
function int(v: unknown): number | undefined {
  const n = num(v);
  return n == null ? undefined : Math.round(n);
}

/** Seconds → whole minutes; missing counts as zero minutes for that stage. */
function toMin(v: unknown): number {
  return Math.round((num(v) ?? 0) / 60);
}
