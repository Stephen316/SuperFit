// All configuration in one place. Everything Garmin-specific is env-driven so
// the values from your Health API onboarding pack live in the environment, not
// in code, and can be corrected without a redeploy of logic.

const env = (key: string, fallback = ''): string => process.env[key] ?? fallback;

export const config = {
  /** e.g. https://api.yourdomain.com — no trailing slash. */
  publicBaseUrl: env('PUBLIC_BASE_URL'),
  /** The app's deep link. The redirect that hands the session token back. */
  appRedirectScheme: 'superfit://garmin',
  /** Guards POST /garmin/webhook; Garmin does not sign pushes. */
  webhookSecret: env('WEBHOOK_SECRET'),
  devSeedEnabled: env('DEV_SEED_ENABLED') === 'true',
  garmin: {
    clientId: env('GARMIN_CLIENT_ID'),
    clientSecret: env('GARMIN_CLIENT_SECRET'),
    // Defaults are Garmin's current OAuth 2.0 (PKCE) endpoints. VERIFY against
    // your onboarding docs — see README "If Garmin gave you OAuth 1.0a".
    authorizeUrl: env('GARMIN_AUTHORIZE_URL', 'https://connect.garmin.com/oauth2Confirm'),
    tokenUrl: env('GARMIN_TOKEN_URL', 'https://diauth.garmin.com/di-oauth2-service/oauth/token'),
    userIdUrl: env('GARMIN_USER_ID_URL', 'https://apis.garmin.com/wellness-api/rest/user/id'),
    apiBaseUrl: env('GARMIN_API_BASE_URL', 'https://apis.garmin.com'),
    scopes: env('GARMIN_SCOPES'),
  },
};

/** The redirect URI Garmin sends the auth code back to. Must be registered verbatim. */
export const redirectUri = (): string => `${config.publicBaseUrl}/garmin/callback`;

/** Fail loudly at the start of a link attempt if the OAuth essentials are missing. */
export function assertGarminConfigured(): void {
  const missing = ['PUBLIC_BASE_URL', 'GARMIN_CLIENT_ID', 'GARMIN_CLIENT_SECRET'].filter(
    (k) => !process.env[k],
  );
  if (missing.length) throw new Error(`Missing required env: ${missing.join(', ')}`);
}
