import { config, redirectUri } from './config';
import { shortHash } from './http';

export interface GarminTokens {
  accessToken: string;
  refreshToken?: string;
  garminUserId: string;
}

/**
 * Exchange an authorization code for tokens (OAuth 2.0 PKCE), then resolve the
 * Garmin user id that webhook pushes will be keyed on.
 *
 * Garmin's exact token response and user-id endpoint come from your onboarding
 * pack; the field access below reads the standard OAuth names and Garmin's
 * documented `userId`. If your program differs, this function is the one place
 * to adjust.
 */
export async function exchangeCode(code: string, verifier: string): Promise<GarminTokens> {
  const body = new URLSearchParams({
    grant_type: 'authorization_code',
    code,
    client_id: config.garmin.clientId,
    client_secret: config.garmin.clientSecret,
    code_verifier: verifier,
    redirect_uri: redirectUri(),
  });

  const resp = await fetch(config.garmin.tokenUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });
  if (!resp.ok) {
    throw new Error(`Garmin token exchange failed: ${resp.status} ${await safeText(resp)}`);
  }
  const json = (await resp.json()) as Record<string, unknown>;
  const accessToken = String(json.access_token ?? '');
  if (!accessToken) throw new Error('Garmin token response had no access_token');
  const refreshToken = json.refresh_token ? String(json.refresh_token) : undefined;

  const garminUserId = await fetchUserId(accessToken);
  return { accessToken, refreshToken, garminUserId };
}

/**
 * Refresh an expired access token. Called opportunistically before a backfill
 * pull; webhooks don't need it since Garmin pushes without our credentials.
 */
export async function refreshTokens(refreshToken: string): Promise<GarminTokens> {
  const body = new URLSearchParams({
    grant_type: 'refresh_token',
    refresh_token: refreshToken,
    client_id: config.garmin.clientId,
    client_secret: config.garmin.clientSecret,
  });
  const resp = await fetch(config.garmin.tokenUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });
  if (!resp.ok) throw new Error(`Garmin token refresh failed: ${resp.status} ${await safeText(resp)}`);
  const json = (await resp.json()) as Record<string, unknown>;
  const accessToken = String(json.access_token ?? '');
  const newRefresh = json.refresh_token ? String(json.refresh_token) : refreshToken;
  const garminUserId = await fetchUserId(accessToken);
  return { accessToken, refreshToken: newRefresh, garminUserId };
}

async function fetchUserId(accessToken: string): Promise<string> {
  if (!config.garmin.userIdUrl) return shortHash(accessToken);
  try {
    const resp = await fetch(config.garmin.userIdUrl, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    if (!resp.ok) return shortHash(accessToken);
    const json = (await resp.json()) as Record<string, unknown>;
    const id = json.userId ?? json.userAccessToken;
    return id ? String(id) : shortHash(accessToken);
  } catch {
    // Never fail linking over the id lookup — a hash keeps the account usable,
    // and webhooks that carry the real id will still resolve once it is stored.
    return shortHash(accessToken);
  }
}

async function safeText(resp: Response): Promise<string> {
  try {
    return (await resp.text()).slice(0, 500);
  } catch {
    return '';
  }
}
