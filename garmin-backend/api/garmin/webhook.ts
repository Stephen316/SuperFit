import type { VercelRequest, VercelResponse } from '@vercel/node';
import { config } from '../../lib/config';
import { getStore } from '../../lib/store';
import { ingest } from '../../lib/transform';
import { str } from '../../lib/http';

/**
 * POST /garmin/webhook — Garmin pushes new summaries here on each sync. Register
 * the URL with a `?secret=` matching WEBHOOK_SECRET, since Garmin doesn't sign
 * pushes.
 *
 * Acknowledge with 200 even on a partial batch: a non-2xx tells Garmin to
 * redeliver the whole thing, so parsing failures are swallowed inside `ingest`
 * rather than surfaced as an error status.
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== 'POST') return res.status(405).end();
  if (config.webhookSecret && str(req.query.secret) !== config.webhookSecret) {
    return res.status(401).end();
  }

  try {
    await ingest(getStore(), req.body);
  } catch (e) {
    // Log for our own diagnosis, but still ack — see the note above.
    console.error('webhook ingest error', e);
  }
  res.status(200).json({ ok: true });
}
