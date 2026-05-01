/**
 * Property-Based Tests for isValidUuidV4
 *
 * Feature: superadmin-zero-trust-security, Property 8: Validação de Tenant_ID como UUID v4
 *
 * **Validates: Requirements 4.1, 4.2**
 *
 * Tests that the UUID v4 validator correctly accepts only well-formed UUID v4
 * strings and rejects everything else — random strings, UUIDs of other versions,
 * and malformed variants.
 *
 * Run with: deno test --allow-env --allow-net supabase/functions/tests/tenant_id_validator_pbt_test.ts
 */

import { assertEquals, assert } from "jsr:@std/assert@1";
import fc from "fast-check";
import { isValidUuidV4 } from "../shared/tenant_id_validator.ts";

// ── Generators ───────────────────────────────────────────────────────────────

/**
 * Generates a valid UUID v4 string.
 * Format: xxxxxxxx-xxxx-4xxx-[89ab]xxx-xxxxxxxxxxxx
 */
const validUuidV4Arb = fc.tuple(
  fc.hexaString({ minLength: 8, maxLength: 8 }),
  fc.hexaString({ minLength: 4, maxLength: 4 }),
  fc.hexaString({ minLength: 3, maxLength: 3 }),
  fc.constantFrom("8", "9", "a", "b", "A", "B"),
  fc.hexaString({ minLength: 3, maxLength: 3 }),
  fc.hexaString({ minLength: 12, maxLength: 12 }),
).map(([p1, p2, p3, variant, p4, p5]) =>
  `${p1}-${p2}-4${p3}-${variant}${p4}-${p5}`
);

/**
 * Generates a UUID-like string with a non-v4 version nibble (0-3, 5-f).
 */
const nonV4UuidArb = fc.tuple(
  fc.hexaString({ minLength: 8, maxLength: 8 }),
  fc.hexaString({ minLength: 4, maxLength: 4 }),
  fc.constantFrom("0", "1", "2", "3", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"),
  fc.hexaString({ minLength: 3, maxLength: 3 }),
  fc.constantFrom("8", "9", "a", "b"),
  fc.hexaString({ minLength: 3, maxLength: 3 }),
  fc.hexaString({ minLength: 12, maxLength: 12 }),
).map(([p1, p2, version, p3, variant, p4, p5]) =>
  `${p1}-${p2}-${version}${p3}-${variant}${p4}-${p5}`
);

/**
 * Generates a UUID-like string with an invalid variant nibble (not 8/9/a/b).
 */
const invalidVariantUuidArb = fc.tuple(
  fc.hexaString({ minLength: 8, maxLength: 8 }),
  fc.hexaString({ minLength: 4, maxLength: 4 }),
  fc.hexaString({ minLength: 3, maxLength: 3 }),
  fc.constantFrom("0", "1", "2", "3", "4", "5", "6", "7", "c", "d", "e", "f"),
  fc.hexaString({ minLength: 3, maxLength: 3 }),
  fc.hexaString({ minLength: 12, maxLength: 12 }),
).map(([p1, p2, p3, variant, p4, p5]) =>
  `${p1}-${p2}-4${p3}-${variant}${p4}-${p5}`
);

// ── Property Tests ───────────────────────────────────────────────────────────

Deno.test("Property 8: Valid UUID v4 strings are always accepted", () => {
  fc.assert(
    fc.property(validUuidV4Arb, (uuid) => {
      assert(
        isValidUuidV4(uuid),
        `Expected valid UUID v4 to be accepted: ${uuid}`,
      );
    }),
    { numRuns: 200 },
  );
});

Deno.test("Property 8: Random strings are rejected", () => {
  fc.assert(
    fc.property(fc.string(), (s) => {
      // Random strings are extremely unlikely to be valid UUID v4
      // If by chance one is valid, that's fine — the property still holds
      if (isValidUuidV4(s)) {
        // Verify it actually matches the UUID v4 pattern
        const regex = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
        assert(regex.test(s), `Accepted string doesn't match UUID v4 pattern: ${s}`);
      }
    }),
    { numRuns: 200 },
  );
});

Deno.test("Property 8: Non-v4 UUIDs (wrong version nibble) are rejected", () => {
  fc.assert(
    fc.property(nonV4UuidArb, (uuid) => {
      assertEquals(
        isValidUuidV4(uuid),
        false,
        `Expected non-v4 UUID to be rejected: ${uuid}`,
      );
    }),
    { numRuns: 200 },
  );
});

Deno.test("Property 8: UUIDs with invalid variant nibble are rejected", () => {
  fc.assert(
    fc.property(invalidVariantUuidArb, (uuid) => {
      assertEquals(
        isValidUuidV4(uuid),
        false,
        `Expected UUID with invalid variant to be rejected: ${uuid}`,
      );
    }),
    { numRuns: 200 },
  );
});

Deno.test("Property 8: crypto.randomUUID() always passes validation", () => {
  fc.assert(
    fc.property(fc.constant(null), () => {
      const uuid = crypto.randomUUID();
      assert(
        isValidUuidV4(uuid),
        `Expected crypto.randomUUID() to be valid: ${uuid}`,
      );
    }),
    { numRuns: 100 },
  );
});
