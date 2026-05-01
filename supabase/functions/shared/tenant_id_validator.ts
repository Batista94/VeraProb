/**
 * Tenant ID Validator — UUID v4 format validation and organization existence check.
 *
 * INV-26 (Error Parity): Invalid or non-existent tenant IDs result in
 * sovereigntyErrorResponse() — no information leakage about which orgs exist.
 *
 * **Validation Pipeline:**
 * 1. Format check: UUID v4 regex (fast, no DB call)
 * 2. Existence check: Query `organizations` table (only if format is valid)
 *
 * This two-step approach ensures that malformed UUIDs never trigger DB queries,
 * reducing attack surface and database load from enumeration attempts.
 */

// deno-lint-ignore no-explicit-any
type SupabaseClient = any;

// ── UUID v4 Regex ────────────────────────────────────────────────────────────

/**
 * Strict UUID v4 regex:
 * - 8-4-4-4-12 hex format
 * - Version nibble must be `4`
 * - Variant bits must be `8`, `9`, `a`, or `b`
 * - Case-insensitive
 */
const UUID_V4_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

// ── Types ────────────────────────────────────────────────────────────────────

export interface Organization {
  id: string;
  name: string;
  status: string;
}

export type ValidateTenantResult =
  | { valid: true; org: Organization }
  | { valid: false };

// ── Public API ───────────────────────────────────────────────────────────────

/**
 * Validates that a string is a well-formed UUID v4.
 *
 * Accepts both lowercase and uppercase hex digits.
 * Rejects UUIDs of other versions (v1, v3, v5, etc.) and malformed strings.
 *
 * @param value — The string to validate
 * @returns true if the string matches UUID v4 format
 */
export function isValidUuidV4(value: string): boolean {
  return UUID_V4_REGEX.test(value);
}

/**
 * Validates a tenant ID: checks UUID v4 format, then verifies the organization
 * exists and is not deleted in the `organizations` table.
 *
 * **Fail-Fast:** If the format check fails, no DB query is executed.
 *
 * @param tenantId — The tenant ID to validate
 * @param supabase — Supabase service_role client
 * @returns `{ valid: true, org }` if the tenant exists, `{ valid: false }` otherwise
 */
export async function validateTenantId(
  tenantId: string,
  supabase: SupabaseClient,
): Promise<ValidateTenantResult> {
  // Step 1: Format validation (no DB call)
  if (!isValidUuidV4(tenantId)) {
    return { valid: false };
  }

  // Step 2: Existence check in organizations table
  const { data: org, error } = await supabase
    .from("organizations")
    .select("id, name, status")
    .eq("id", tenantId)
    .single();

  if (error || !org || org.status === "DELETED") {
    return { valid: false };
  }

  return { valid: true, org: org as Organization };
}
