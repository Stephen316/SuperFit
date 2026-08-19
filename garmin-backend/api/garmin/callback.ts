import type { VercelRequest, VercelResponse } from '@vercel/node';
import { config } from '../../lib/config';
import { getStore } from '../../lib/store';
import { exchangeCode } from '../../lib/oauth';
import { str, randomToken } from '../../lib/http';

/**
 * GET /garmin/callback — Garmin returns here with `code` and `state`. We finish
 * the OAuth exchange, mint the opaque session token the app stores in its
 * Keychain, and hand it back via the `superfit://garmin?token=…` deep link.
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  const code = str(req.query.code);
  const state = str(req.query.state);
  const error = str(req.query.error);
  if (error) return res.status(400).send(`Garmin authorization was declined: ${error}`);
  if (!code || !state) return res.status(400).send('Missing code or state.');

  const pending = await getStore().takePending(state);
  if (!pending) return res.status(400).send('Unknown or expired authorization state.');

  let tokens;
  try {
    tokens = await exchangeCode(code, pending.verifier);
  } catch (e) {
    return res.status(502).send(`Token exchange failed: ${(e as Error).message}`);
  }

  const store = getStore();
  const sessionToken = randomToken();
  await store.putSession(sessionToken, {
    garminUserId: tokens.garminUserId,
    accessToken: tokens.accessToken,
    refreshToken: tokens.refreshToken,
    createdAt: Date.now(),
  });
  await store.linkUser(tokens.garminUserId, sessionToken);

  res.redirect(302, `${config.appRedirectScheme}?token=${encodeURIComponent(sessionToken)}`);
}
