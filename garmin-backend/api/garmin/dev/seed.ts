import type { VercelRequest, VercelResponse } from '@vercel/node';
import { config } from '../../../lib/config';
import { getStore } from '../../../lib/store';
import { randomToken, str, toGarminISO } from '../../../lib/http';
import { matchesConfiguredSecret } from '../../../lib/security';
import type { RecoveryDTO, WorkoutDTO } from '../../../lib/types';

/**
 * GET /garmin/dev/seed?token=…&redirect=1 — a stand-in for a real Garmin link,
 * gated behind DEV_SEED_ENABLED. It creates a session, fills ~28 days of
 * plausible HRV / resting HR / staged sleep plus a couple of runs, and (with
 * redirect=1) bounces to the app deep link so you can exercise the full path —
 * link, pull-to-refresh, recovery ring, sleep stages — with no Garmin account.
 *
 * Note: with the in-memory store this data lives only as long as the dev process
 * (`vercel dev`). For a deployed test, configure Upstash.
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (!config.devSeedEnabled) return res.status(404).end();
  if (!config.devSeedSecret) {
    return res.status(503).json({ error: 'DEV_SEED_SECRET is not configured' });
  }
  if (!matchesConfiguredSecret(config.devSeedSecret, str(req.query.secret))) {
    return res.status(401).end();
  }

  const store = getStore();
  const token = randomToken();
  const garminUserId = 'dev-user';
  const days = Math.min(Number(str(req.query.days) ?? 28) || 28, 120);

  await store.putSession(token, {
    garminUserId,
    accessToken: randomToken(),
    createdAt: Date.now(),
  });
  await store.linkUser(garminUserId, token);

  for (let i = 0; i < days; i++) {
    const day = new Date();
    day.setUTCDate(day.getUTCDate() - i);
    await store.putDaily(garminUserId, sampleDaily(day, i));
  }
  await store.putWorkout(garminUserId, sampleRun(2));
  await store.putWorkout(garminUserId, sampleRun(5));

  if (str(req.query.redirect) === '1') {
    return res.redirect(302, `${config.appRedirectScheme}?token=${encodeURIComponent(token)}`);
  }
  res.status(200).json({
    ok: true,
    sessionToken: token,
    seededDays: days,
    hint: `Link the app by opening ${config.appRedirectScheme}?token=${token} on the device, or re-call with &redirect=1.`,
  });
}

function sampleDaily(day: Date, i: number): RecoveryDTO {
  const date = day.toISOString().slice(0, 10);
  // Gentle waves so the values look like a real person's, not flat lines.
  const hrv = Math.round(48 + 8 * Math.sin(i / 3));
  const rhr = Math.round(54 + 3 * Math.sin(i / 5));
  const asleep = 430 + Math.round(30 * Math.sin(i / 2));
  const deep = Math.round(asleep * 0.2);
  const rem = Math.round(asleep * 0.25);
  const light = asleep - deep - rem;
  const awake = 24;
  const bed = new Date(day);
  bed.setUTCHours(23, 15, 0, 0);
  bed.setUTCDate(bed.getUTCDate() - 1);
  const wake = new Date(bed.getTime() + (asleep + awake) * 60_000);
  return {
    date,
    hrvSDNN: hrv,
    restingHeartRate: rhr,
    bodyBattery: Math.round(70 + 15 * Math.sin(i / 4)),
    sleep: {
      inBedMinutes: asleep + awake,
      asleepMinutes: asleep,
      deepMinutes: deep,
      remMinutes: rem,
      lightMinutes: light,
      bedtime: toGarminISO(bed),
      wakeTime: toGarminISO(wake),
    },
  };
}

function sampleRun(daysAgo: number): WorkoutDTO {
  const start = new Date();
  start.setUTCDate(start.getUTCDate() - daysAgo);
  start.setUTCHours(6, 14, 0, 0);
  return {
    id: `dev-run-${daysAgo}`,
    startTime: toGarminISO(start),
    durationSeconds: 2735,
    activityType: 'running',
    activeKilocalories: 612,
    distanceMeters: 8043.2,
    averageHeartRate: 148,
    maxHeartRate: 171,
    elevationGainMeters: 96,
    averageCadence: 172,
    averagePowerWatts: 268,
    aerobicTrainingEffect: 3.4,
    anaerobicTrainingEffect: 1.2,
  };
}
