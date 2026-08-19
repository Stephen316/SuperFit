import assert from 'node:assert/strict';
import test from 'node:test';
import { garminUserId } from '../lib/garminIdentity.ts';
import { MAX_RANGE_DAYS, parseRange } from '../lib/http.ts';
import { matchesConfiguredSecret } from '../lib/security.ts';

function request(query = {}) {
  return { query };
}

test('shared-secret checks fail closed when server configuration is absent', () => {
  assert.equal(matchesConfiguredSecret('', undefined), false);
  assert.equal(matchesConfiguredSecret('', ''), false);
  assert.equal(matchesConfiguredSecret('expected', 'wrong'), false);
  assert.equal(matchesConfiguredSecret('expected', 'expected'), true);
});

test('Garmin identity must be the stable webhook identifier', () => {
  assert.equal(garminUserId({ userId: ' 12345 ' }), '12345');
  assert.equal(garminUserId({ userAccessToken: 'legacy-id' }), 'legacy-id');
  assert.throws(() => garminUserId({}), /no userId/);
});

test('date ranges reject malformed, reversed and unbounded requests', () => {
  const now = Date.parse('2026-08-09T12:00:00Z');
  const defaultRange = parseRange(request(), now);
  assert.equal(defaultRange.end.getTime(), now);
  assert.equal(defaultRange.end.getTime() - defaultRange.start.getTime(), 90 * 86_400_000);

  assert.throws(
    () => parseRange(request({ start: 'not-a-date' }), now),
    /valid ISO-8601/,
  );
  assert.throws(
    () => parseRange(request({ start: '2026-08-10', end: '2026-08-09' }), now),
    /earlier/,
  );
  assert.throws(
    () => parseRange(request({ start: '2024-01-01', end: '2026-01-01' }), now),
    new RegExp(`${MAX_RANGE_DAYS} days`),
  );
});
