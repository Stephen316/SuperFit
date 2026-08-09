import type { VercelRequest, VercelResponse } from '@vercel/node';
import { config } from '../../lib/config';
import { getStore } from '../../lib/store';
import { ingest } from '../../lib/transform';
import { str } from '../../lib/http';
import { matchesConfiguredSecret } from '../../lib/security';

/**
 * POST /garmin/webhook — Garmin pushes new summaries here on each sync. Register
 * the URL with a `?secret=` matching WEBHOOK_SECRET, since Garmin doesn't sign
 * pushes.
 *
 * Parsing skips unsupported records, while storage failures return 503 so
 * Garmin can safely redeliver the idempotent upserts.
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== 'POST') return res.status(405).end();
  if (!config.webhookSecret) {
    return res.status(503).json({ error: 'WEBHOOK_SECRET is not configured' });
  }
  if (!matchesConfiguredSecret(config.webhookSecret, str(req.query.secret))) {
    return res.status(401).end();
  }

  try {
    await ingest(getStore(), req.body);
  } catch (e) {
    console.error('webhook ingest error', e);
    return res.status(503).json({ error: 'webhook storage failed; retry later' });
  }
  return res.status(200).json({ ok: true });
}
