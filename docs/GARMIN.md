# Garmin Health API Integration

SuperFit can pull HRV and detailed sleep data from Garmin that Apple Health doesn't expose. This document explains what backend infrastructure you need.

## Why a backend?

1. **OAuth secret is sensitive** — Garmin requires a consumer secret to exchange auth codes for tokens. This must never ship in the app binary (it's extractable via tools like strings, decompilers, etc.)
2. **Webhooks need a URL** — Garmin's Health API is push-based: they POST new data to a URL you register. An iPhone has no stable inbound address.

Solution: you deploy a small backend that holds the secret and receives the webhooks.

## Backend API contract

Your backend exposes two endpoints, both protected by a per-user session token.

### Authorization endpoint
**GET** `/garmin/authorize`

Redirects to Garmin's OAuth login. After the user authorizes, Garmin redirects to the callback URL you registered (e.g. `https://yourdomain.com/garmin/callback`) with an `authorizationCode`. Your backend:
1. Exchanges it for a refresh token (persistent; no expiry)
2. Mints a session token (opaque string, stored by the app in Keychain)
3. Redirects to `superfit://garmin?token={sessionToken}`

The browser on the phone receives the redirect and invokes the app via deep link. `ConnectedServicesView` extracts the token and saves it.

### Recovery data endpoint
**GET** `/garmin/recovery?start={ISO8601}&end={ISO8601}`

Returns an array of daily recovery metrics. Requires `Authorization: Bearer {sessionToken}` header.

**Response** (JSON):
```json
[
  {
    "date": "2026-07-25",
    "hrvSDNN": 45.2,
    "restingHeartRate": 62,
    "bodyBattery": 78,
    "sleep": {
      "inBedMinutes": 480,
      "asleepMinutes": 456,
      "deepMinutes": 90,
      "remMinutes": 120,
      "lightMinutes": 246
    }
  }
]
```

All fields are optional; any missing field is treated as "no data for that metric."

### Webhook endpoint
**POST** `/garmin/webhook`

Garmin sends new data here whenever the user syncs. The backend upserts it into its database, so the next call to `/garmin/recovery` returns the latest. No app integration needed (fire-and-forget from Garmin's perspective).

## Garmin setup

1. Go to [Garmin Health API dashboard](https://developer.garmin.com/health-api)
2. Register your backend app with Garmin:
   - Consumer name: "SuperFit"
   - Callback URL: `https://yourdomain.com/garmin/callback` (or your staging equivalent)
   - Request permissions: Daily stress (for HRV/rMSSD), sleep
3. Garmin assigns you a **consumer key** and **consumer secret**. Store the secret server-side in an env var (never commit it).
4. Register a webhook: tell Garmin to POST to `https://yourdomain.com/garmin/webhook` whenever data changes.

## App setup

No additional config needed — the app auto-detects at launch whether you have a backend. In `Settings → Connected services`:
1. Enter your backend URL (e.g. `https://api.yourdomain.com`)
2. Tap "Connect Garmin" — the app opens a browser to `/garmin/authorize`
3. Garmin's OAuth flow happens normally
4. Redirect to `superfit://garmin?token=...` auto-populates the session token in Keychain

From then on, every sync (`pull-to-refresh` on Today tab) calls `/garmin/recovery` and merges Garmin's HRV + sleep into the app's database. HealthKit data wins for activity/steps; Garmin wins for HRV/sleep (since Garmin Connect never exports those to Apple Health).

## Implementation notes

- **Idempotency**: `/garmin/recovery` queries are date-ranged (last 90 days by default) and called every time the app syncs. Your backend should upsert by date, not append, so repeated calls are safe.
- **Revocation**: if a user disconnects in Settings, the app deletes the session token locally. Your backend can stop serving that token immediately.
- **Minimal overhead**: the flow is read-only for the app. The only write is Garmin → backend (via webhook), which happens asynchronously.
- **No heartbeat required**: the app doesn't ping the backend unless it explicitly syncs. Garmin's webhook keeps data fresh on the backend without the app asking.

## Testing without Garmin

Before you have a real Garmin watch:
- Stub `/garmin/recovery` to return hardcoded sample data (date ranges 2 weeks back, realistic HRV ~40–60 ms, sleep 7–8 hours).
- The app's `RecoveryEngine` will compute the readiness score and display it. No Garmin device needed.

## Deployment checklist

- [ ] Backend URL is HTTPS (required for Keychain + OAuth)
- [ ] Consumer secret is in an env var, not hardcoded
- [ ] `/garmin/authorize` and `/garmin/recovery` are implemented
- [ ] Session tokens have a reasonable TTL (e.g. 1 year); refresh tokens are stored permanently
- [ ] Webhook endpoint is registered with Garmin and working
- [ ] Upsert logic is in place (don't duplicate rows on repeated syncs)
- [ ] Error responses include 401 (expired token) so the app knows to unlink
