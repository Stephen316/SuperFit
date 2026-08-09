import type { VercelRequest } from '@vercel/node';
import { randomBytes, createHash } from 'node:crypto';

/** Vercel query values are `string | string[] | undefined`; take the first. */
export const str = (v: string | string[] | undefined): string | undefined =>
  Array.isArray(v) ? v[0] : v;

/** The session token from an `Authorization: Bearer …` header, if present. */
export function bearer(req: VercelRequest): string | undefined {
  const raw = req.headers['authorization'];
  const value = Array.isArray(raw) ? raw[0] : raw;
  const match = value ? /^Bearer\s+(.+)$/i.exec(value) : null;
  return match ? match[1] : undefined;
}

export const MAX_RANGE_DAYS = 366;

/**
 * The requested window, defaulting to 90 days and capped at one year. A bounded
 * interval keeps accidental or hostile requests from materialising a lifetime
 * of records, and validation turns malformed dates into a useful 400 response.
 */
export function parseRange(
  req: VercelRequest,
  now = Date.now(),
): { start: Date; end: Date } {
  const start = new Date(str(req.query.start) ?? new Date(now - 90 * 86_400_000).toISOString());
  const end = new Date(str(req.query.end) ?? new Date(now).toISOString());
  if (!Number.isFinite(start.getTime()) || !Number.isFinite(end.getTime())) {
    throw new RangeError('start and end must be valid ISO-8601 dates');
  }
  if (end < start) throw new RangeError('end must not be earlier than start');
  if (end.getTime() - start.getTime() > MAX_RANGE_DAYS * 86_400_000) {
    throw new RangeError(`date range must not exceed ${MAX_RANGE_DAYS} days`);
  }
  return { start, end };
}

/** yyyy-MM-dd in UTC. Garmin's calendar dates are already day strings; this is
 *  for deriving a day key from an epoch. */
export const ymd = (d: Date): string => d.toISOString().slice(0, 10);

/**
 * ISO8601 without milliseconds. Swift's `JSONDecoder.dateDecodingStrategy =
 * .iso8601` uses `.withInternetDateTime` only, so `2026-07-25T06:14:00.000Z`
 * throws and takes the entire array decode down with it. Every date on the wire
 * goes through here.
 */
export const toGarminISO = (d: Date): string => d.toISOString().replace(/\.\d{3}Z$/, 'Z');

/** Opaque URL-safe random token — session tokens and OAuth `state`. */
export const randomToken = (bytes = 32): string => randomBytes(bytes).toString('base64url');

/** PKCE S256 challenge for a verifier. */
export const pkceChallenge = (verifier: string): string =>
  createHash('sha256').update(verifier).digest('base64url');
