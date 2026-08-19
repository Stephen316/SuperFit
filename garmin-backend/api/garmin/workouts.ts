import type { VercelRequest, VercelResponse } from '@vercel/node';
import { getStore } from '../../lib/store';
import { bearer, parseRange } from '../../lib/http';

/**
 * GET /garmin/workouts?start=&end= — activities for enrichment. The app matches
 * these to HealthKit workouts on start time and fills in power/cadence/training
 * effect, importing whole only those with no HealthKit counterpart.
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  const token = bearer(req);
  if (!token) return res.status(401).json({ error: 'missing bearer token' });

  const session = await getStore().getSession(token);
  if (!session) return res.status(401).json({ error: 'unknown or revoked token' });

  let start: Date;
  let end: Date;
  try {
    ({ start, end } = parseRange(req));
  } catch (error) {
    return res.status(400).json({ error: (error as Error).message });
  }
  const workouts = await getStore().getWorkoutRange(session.garminUserId, start, end);
  return res.status(200).json(workouts);
}
