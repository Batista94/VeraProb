/**
 * Sovereignty Error Mapper for Deno Edge Functions (INV-26: Error Parity).
 *
 * Security Contract:
 * - All sovereignty violations and resource-not-found errors produce
 *   byte-identical HTTP 404 responses: `{"error":"Not Found"}`.
 * - NO forensic details (org IDs, resource types, internal messages)
 *   are leaked to the external caller.
 * - Internal forensic data MUST be logged separately (Sentry/PostHog).
 *
 * Usage:
 * ```ts
 * try {
 *   await assertTenantMatches(payloadOrgId, sessionId, supabase);
 * } catch (err) {
 *   if (err instanceof SovereigntyViolationError) {
 *     Sentry.captureException(err); // Internal logging
 *     return sovereigntyErrorResponse();
 *   }
 *   throw err;
 * }
 * ```
 */

export const SOVEREIGNTY_STATUS = 404;
export const SOVEREIGNTY_BODY = JSON.stringify({ error: "Not Found" });

/**
 * Returns an indistinguishable HTTP 404 response.
 *
 * Use this for:
 * - SovereigntyViolationError (payload.org_id ≠ JWT.org_id)
 * - ResourceNotFoundError (real 404 or cross-org access attempt)
 * - Origin Ownership failures (INV-27)
 */
export function sovereigntyErrorResponse(): Response {
  return new Response(SOVEREIGNTY_BODY, {
    status: SOVEREIGNTY_STATUS,
    headers: { "Content-Type": "application/json" },
  });
}
