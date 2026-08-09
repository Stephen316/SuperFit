/** Extract the stable Garmin identifier used by webhook payloads. */
export function garminUserId(payload: Record<string, unknown>): string {
  const raw = payload.userId ?? payload.userAccessToken;
  const id = raw == null ? "" : String(raw).trim();
  if (!id) throw new Error("Garmin user-id response had no userId");
  return id;
}
