/**
 * canonical_json.ts — Deterministic JSON canonicalization for HMAC signing.
 *
 * **INV-9 (Evidence Sealing) & INV-15 (Deterministic):**
 * Produces byte-identical JSON strings across Dart (insert) and Deno (verification)
 * by:
 * 1. Recursively sorting all Map/Object keys alphabetically
 * 2. Normalizing Date values to ISO-8601 strings with 'Z' suffix
 * 3. Recursively processing arrays (each element normalized independently)
 *
 * **Why this exists:**
 * Dart's `jsonEncode` preserves Map insertion order. JavaScript's
 * `JSON.stringify` also preserves key insertion order (ES2015+). Without
 * explicit key sorting, the same logical payload would produce different
 * SHA-256 hashes on each side — breaking HMAC verification.
 *
 * **Parity with Dart:**
 * This function is the Deno equivalent of
 * `BasePostgresRepository._sortKeys()` in the Dart codebase.
 * Both produce identical output for the same input.
 *
 * Usage:
 * ```ts
 * import { canonicalJson } from "./canonical_json.ts";
 *
 * const payload = { z: 1, a: 2, nested: { m: 3, b: 4 } };
 * const json = canonicalJson(payload);
 * // => '{"a":2,"nested":{"b":4,"m":3},"z":1}'
 * ```
 */

// ── Type Guard ────────────────────────────────────────────────────────────────

/**
 * Checks if a value is a plain object (not array, not null, not Date).
 */
function isPlainObject(value: unknown): value is Record<string, unknown> {
  return value !== null &&
    typeof value === "object" &&
    !Array.isArray(value) &&
    !(value instanceof Date);
}

// ── Core Canonicalization ────────────────────────────────────────────────────

/**
 * Recursively sorts object keys and normalizes types for deterministic JSON.
 *
 * **Normalization rules (matching Dart `_sortKeys`):**
 * - `Date` → ISO-8601 string with 'Z' suffix (e.g., `"2026-04-11T00:00:00.000Z"`)
 * - `Record<string, unknown>` → keys sorted alphabetically, values recursively normalized
 * - `Array` → each element recursively normalized (order preserved)
 * - Primitives (null, string, number, boolean) → returned as-is
 *
 * @param obj — Any JSON-compatible value (typically the parsed request body)
 * @returns A new object/array/primitive with sorted keys and normalized types
 */
export function sortKeys(obj: unknown): unknown {
  if (obj === null) return null;

  // Type normalization: Date → ISO-8601 string (Z-suffix for UTC parity)
  if (obj instanceof Date) {
    const iso = obj.toISOString();
    // toISOString() always returns Z-suffix, but be explicit for clarity
    return iso.endsWith("Z") ? iso : `${iso}Z`;
  }

  // Recursive array: normalize each element
  if (Array.isArray(obj)) {
    return obj.map(sortKeys);
  }

  // Recursive object: sort keys + normalize values
  if (isPlainObject(obj)) {
    const sorted: Record<string, unknown> = {};
    const keys = Object.keys(obj).sort();
    for (const key of keys) {
      sorted[key] = sortKeys(obj[key]);
    }
    return sorted;
  }

  // Case base: primitives (string, number, boolean) pass through
  return obj;
}

/**
 * Produces a canonical JSON string from any JSON-compatible value.
 *
 * Keys are sorted alphabetically at every nesting level. Date objects are
 * normalized to ISO-8601 UTC strings. The output is byte-identical to
 * Dart's `jsonEncode(BasePostgresRepository.sortKeys(payload))` for the
 * same logical input.
 *
 * @param obj — Any JSON-compatible value
 * @returns Canonical JSON string suitable for SHA-256 hashing
 *
 * @example
 * ```ts
 * const payload = {
 *   organization_id: "org-123",
 *   device_id: "dev-456",
 *   events: [{ ts: new Date("2026-04-11T00:00:00Z"), type: "check_in" }],
 * };
 *
 * canonicalJson(payload);
 * // => '{"device_id":"dev-456","events":[{"ts":"2026-04-11T00:00:00.000Z","type":"check_in"}],"organization_id":"org-123"}'
 * ```
 */
export function canonicalJson(obj: unknown): string {
  return JSON.stringify(sortKeys(obj));
}
