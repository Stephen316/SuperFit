# SuperFit Garmin backend

The server SuperFit's Garmin integration talks to. It exists for one reason:
**Garmin Connect does not export HRV or staged sleep to Apple Health**, so the
only way those reach the app is to pull them from Garmin's Health API directly.
This backend holds the OAuth secret, receives Garmin's webhooks, and serves the
normalized JSON the app already knows how to read (`docs/GARMIN.md`).

Node + TypeScript, deployed as serverless functions (Vercel by default).

## What it implements

| Route | Purpose |
|---|---|
| `GET /garmin/authorize` | Start OAuth; redirects to Garmin, then back to the app deep link. |
| `GET /garmin/callback` | Finish OAuth, mint the app's session token. |
| `GET /garmin/recovery?start=&end=` | Daily HRV, resting HR, body battery, staged sleep. Bearer token. |
| `GET /garmin/workouts?start=&end=` | Activities for enrichment. Bearer token. |
| `POST /garmin/webhook?secret=` | Garmin pushes new summaries here; upserted by date. |
| `GET /garmin/dev/seed` | Test data, gated behind `DEV_SEED_ENABLED`. No Garmin needed. |

## Before you build: Garmin Health API access

This is the real gate. You need a **Garmin Health API** consumer key and secret
from [developer.garmin.com/health-api](https://developer.garmin.com/health-api).
It is an **approval-gated** program aimed at companies and researchers, not the
free Connect IQ SDK, and individual requests are sometimes declined. Confirm you
can get access before investing effort. Request scopes covering **daily/stress
summaries** (HRV) and **sleep summaries**.

When you register, set:

- **Callback URL** → `https://YOUR-BACKEND/garmin/callback`
- **Webhook URL** → `https://YOUR-BACKEND/garmin/webhook?secret=YOUR_WEBHOOK_SECRET`

## Deploy (Vercel)

```bash
cd garmin-backend
npm install
npx vercel            # first run links/creates the project
# set env vars (below), then:
npm run deploy        # vercel --prod
```

Set the environment variables from `.env.example` in the Vercel dashboard (or
`vercel env add`). At minimum: `PUBLIC_BASE_URL`, `GARMIN_CLIENT_ID`,
`GARMIN_CLIENT_SECRET`, `WEBHOOK_SECRET`, and the two `UPSTASH_REDIS_REST_*`
values.

### Persistence

Serverless functions are stateless, so production **requires** a datastore:
create a free [Upstash Redis](https://upstash.com) database and set
`UPSTASH_REDIS_REST_URL` / `UPSTASH_REDIS_REST_TOKEN`. Without them the server
falls back to an in-memory store that only survives within a single process —
fine for `vercel dev` and the seed test, useless in production.

## Point the app at it

In SuperFit → **Settings → Connected services**:

1. **Backend** → `https://YOUR-BACKEND` (https required).
2. **Connect Garmin** → completes OAuth in the browser and returns to the app.
3. Pull-to-refresh on **Today**. HRV feeds the Recovery ring's 30% HRV slice;
   sleep stages appear on the **Sleep** tab.

## Test the whole path without Garmin

You don't need Garmin approval to prove the app↔backend contract works:

```bash
cd garmin-backend
DEV_SEED_ENABLED=true npm run dev        # vercel dev, on http://localhost:3000
```

Point the app's Backend field at your machine (a tunnel such as `ngrok http 3000`
gives an https URL the app will accept), then open this on the device to link and
seed 28 days of realistic data in one step:

```
https://YOUR-TUNNEL/garmin/dev/seed?redirect=1
```

Pull-to-refresh and the Recovery ring, resting HR and sleep stages populate from
the seeded data. Or inspect the raw contract:

```bash
curl -H "Authorization: Bearer dev-token" \
  "https://YOUR-TUNNEL/garmin/recovery?start=2026-07-01T00:00:00Z&end=2026-08-08T00:00:00Z"
```

## Things worth verifying against your onboarding pack

The SuperFit-facing contract is pinned exactly, but the Garmin-facing details are
versioned by Garmin and can't be confirmed without Health API access. All are
env-driven or isolated to one file:

- **OAuth endpoints / scopes** — `GARMIN_AUTHORIZE_URL`, `GARMIN_TOKEN_URL`,
  `GARMIN_USER_ID_URL`, `GARMIN_SCOPES` in the environment (`lib/config.ts`).
- **Webhook payload field names** — the Garmin summary fields are mapped in
  `lib/transform.ts`; adjust there if your schema differs.

### If Garmin gave you OAuth 1.0a

Some Health API programs are provisioned for OAuth 1.0a (request token →
authorize → access token) rather than the OAuth 2.0 PKCE this implements. If so,
replace the body of `lib/oauth.ts` (`exchangeCode`) with the 1.0a signature
flow and adjust `api/garmin/authorize.ts` to fetch a request token first; the
rest of the server — sessions, storage, webhook, DTOs — is unaffected.

## Layout

```
api/garmin/         one serverless function per route
  dev/seed.ts       test-data seeder (gated)
lib/
  config.ts         env-driven configuration
  types.ts          the exact wire shapes SuperFit decodes
  http.ts           auth/date helpers (incl. the no-millis ISO rule)
  store.ts          Store interface + in-memory + Upstash
  oauth.ts          Garmin token exchange / refresh
  transform.ts      Garmin summaries → SuperFit DTOs (upsert by date)
```
