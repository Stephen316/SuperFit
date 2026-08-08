import type { VercelRequest, VercelResponse } from '@vercel/node';
import { config, assertGarminConfigured, redirectUri } from '../../lib/config';
import { getStore } from '../../lib/store';
import { randomToken, pkceChallenge } from '../../lib/http';

/**
 * GET /garmin/authorize — step 1 of linking. The app opens this in a browser.
 * We stash a PKCE verifier under a random `state` and redirect to Garmin's
 * consent page; Garmin returns to /garmin/callback with the code.
 */
export default async function handler(_req: VercelRequest, res: VercelResponse) {
  try {
    assertGarminConfigured();
  } catch (e) {
    return res.status(500).send(String((e as Error).message));
  }

  const state = randomToken(16);
  const verifier = randomToken(48);
  await getStore().putPending(state, { verifier, createdAt: Date.now() });

  const url = new URL(config.garmin.authorizeUrl);
  url.searchParams.set('response_type', 'code');
  url.searchParams.set('client_id', config.garmin.clientId);
  url.searchParams.set('redirect_uri', redirectUri());
  url.searchParams.set('code_challenge', pkceChallenge(verifier));
  url.searchParams.set('code_challenge_method', 'S256');
  url.searchParams.set('state', state);
  if (config.garmin.scopes) url.searchParams.set('scope', config.garmin.scopes);

  res.redirect(302, url.toString());
}
