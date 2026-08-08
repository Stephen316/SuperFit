import type { VercelRequest, VercelResponse } from '@vercel/node';
import { getStore } from '../../lib/store';
import { bearer, parseRange } from '../../lib/http';

/**
 * GET /garmin/recovery?start=&end= — the HRV, resting HR, body battery and
 * staged sleep the app merges over Apple Health. Bearer session token.
 *
 * A 401 is meaningful: the app calls `unlink()` and drops the token when it sees
 * one, so return it only for a genuinely unusable token.
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  const token = bearer(req);
  if (!token) return res.status(401).json({ error: 'missing bearer token' });

  const session = await getStore().getSession(token);
  if (!session) return res.status(401).json({ error: 'unknown or revoked token' });

  const { start, end } = parseRange(req);
  const records = await getStore().getDailyRange(session.garminUserId, start, end);
  res.status(200).json(records);
}
