/**
 * Shared fail-closed check for endpoints protected by a configured query secret.
 * An absent server-side secret is a configuration error, never an instruction to
 * make the endpoint public.
 */
export function matchesConfiguredSecret(
  configured: string,
  supplied: string | undefined,
): boolean {
  return configured.length > 0 && supplied === configured;
}
