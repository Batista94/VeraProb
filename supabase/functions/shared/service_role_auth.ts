/** Timing-safe compare of Authorization Bearer token to service_role secret. */
export function isServiceRoleAuth(
  authHeader: string,
  secret: string | undefined,
): boolean {
  if (!secret) return false;
  const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
  if (token.length !== secret.length) return false;
  let diff = 0;
  for (let i = 0; i < token.length; i++) {
    diff |= token.charCodeAt(i) ^ secret.charCodeAt(i);
  }
  return diff === 0;
}
