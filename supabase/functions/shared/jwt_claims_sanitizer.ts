/**
 * JWT Claims Sanitizer — Strips sensitive fields from JWT payloads before
 * persisting to forensic logs.
 *
 * **Security Contract:**
 * - Only the following fields are preserved:
 *   - `sub` (user ID)
 *   - `aal` (authentication assurance level)
 *   - `role` (Supabase role)
 *   - `app_metadata.super_admin` (SuperAdmin flag)
 *   - `app_metadata.org_id` (organization ID)
 *
 * - ALL other fields are stripped, including:
 *   - `access_token`, `refresh_token` (credential leakage prevention)
 *   - `exp`, `iat`, `iss`, `aud` (unnecessary for forensic analysis)
 *   - Any custom claims not in the allowlist
 *
 * This ensures that forensic logs in `system_audit_log` contain enough
 * context for incident investigation without storing sensitive credentials.
 */

// ── Allowlists ───────────────────────────────────────────────────────────────

const ALLOWED_CLAIM_KEYS = ["sub", "aal", "role", "app_metadata"] as const;
const ALLOWED_APP_METADATA_KEYS = ["super_admin", "org_id"] as const;

// ── Public API ───────────────────────────────────────────────────────────────

/**
 * Sanitizes a JWT claims payload, preserving only the allowed fields.
 *
 * @param claims — Raw JWT payload (Record<string, unknown>)
 * @returns A new object containing only the allowed fields
 */
export function sanitizeJwtClaims(
  claims: Record<string, unknown>,
): Record<string, unknown> {
  const sanitized: Record<string, unknown> = {};

  for (const key of ALLOWED_CLAIM_KEYS) {
    if (key in claims) {
      if (key === "app_metadata") {
        const meta = claims[key];
        if (meta && typeof meta === "object" && !Array.isArray(meta)) {
          const sanitizedMeta: Record<string, unknown> = {};
          for (const metaKey of ALLOWED_APP_METADATA_KEYS) {
            if (metaKey in (meta as Record<string, unknown>)) {
              sanitizedMeta[metaKey] =
                (meta as Record<string, unknown>)[metaKey];
            }
          }
          sanitized[key] = sanitizedMeta;
        }
      } else {
        sanitized[key] = claims[key];
      }
    }
  }

  return sanitized;
}
