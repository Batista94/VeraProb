/**
 * Property-Based Tests for sanitizeJwtClaims
 *
 * Feature: superadmin-zero-trust-security, Property 9: Sanitização de claims JWT
 *
 * **Validates: Requirements 5.5**
 *
 * Tests that the JWT claims sanitizer preserves only the allowed fields
 * (sub, aal, role, app_metadata.{super_admin, org_id}) and strips everything
 * else — including access_token, refresh_token, and arbitrary custom claims.
 *
 * Run with: deno test --allow-env --allow-net supabase/functions/tests/jwt_claims_sanitizer_pbt_test.ts
 */

import { assertEquals, assert } from "jsr:@std/assert@1";
import fc from "fast-check";
import { sanitizeJwtClaims } from "../shared/jwt_claims_sanitizer.ts";

// ── Constants ────────────────────────────────────────────────────────────────

const ALLOWED_TOP_LEVEL_KEYS = ["sub", "aal", "role", "app_metadata"];
const ALLOWED_APP_METADATA_KEYS = ["super_admin", "org_id"];

// ── Generators ───────────────────────────────────────────────────────────────

/**
 * Generates a JWT-like payload with a mix of allowed and disallowed fields.
 */
const jwtPayloadArb = fc.record({
  // Allowed fields
  sub: fc.option(fc.uuid(), { nil: undefined }),
  aal: fc.option(fc.constantFrom("aal1", "aal2"), { nil: undefined }),
  role: fc.option(fc.constantFrom("authenticated", "anon", "service_role"), { nil: undefined }),
  app_metadata: fc.option(
    fc.record({
      super_admin: fc.option(fc.boolean(), { nil: undefined }),
      org_id: fc.option(fc.uuid(), { nil: undefined }),
      // Disallowed app_metadata fields
      provider: fc.option(fc.string(), { nil: undefined }),
      providers: fc.option(fc.array(fc.string()), { nil: undefined }),
      custom_field: fc.option(fc.string(), { nil: undefined }),
    }),
    { nil: undefined },
  ),
  // Disallowed top-level fields (should be stripped)
  access_token: fc.option(fc.string(), { nil: undefined }),
  refresh_token: fc.option(fc.string(), { nil: undefined }),
  exp: fc.option(fc.integer(), { nil: undefined }),
  iat: fc.option(fc.integer(), { nil: undefined }),
  iss: fc.option(fc.string(), { nil: undefined }),
  aud: fc.option(fc.string(), { nil: undefined }),
  session_id: fc.option(fc.uuid(), { nil: undefined }),
  email: fc.option(fc.string(), { nil: undefined }),
  phone: fc.option(fc.string(), { nil: undefined }),
}, { requiredKeys: [] });

/**
 * Generates a payload with completely arbitrary keys and values.
 */
const arbitraryPayloadArb = fc.dictionary(
  fc.string({ minLength: 1, maxLength: 20 }),
  fc.oneof(
    fc.string(),
    fc.integer(),
    fc.boolean(),
    fc.constant(null),
    fc.dictionary(fc.string({ minLength: 1, maxLength: 10 }), fc.string()),
  ),
);

// ── Property Tests ───────────────────────────────────────────────────────────

Deno.test("Property 9: Sanitized output only contains allowed top-level keys", () => {
  fc.assert(
    fc.property(jwtPayloadArb, (claims) => {
      // Remove undefined values to create a clean input
      const cleanClaims: Record<string, unknown> = {};
      for (const [k, v] of Object.entries(claims)) {
        if (v !== undefined) cleanClaims[k] = v;
      }

      const result = sanitizeJwtClaims(cleanClaims);
      const resultKeys = Object.keys(result);

      for (const key of resultKeys) {
        assert(
          ALLOWED_TOP_LEVEL_KEYS.includes(key),
          `Unexpected top-level key in sanitized output: "${key}"`,
        );
      }
    }),
    { numRuns: 200 },
  );
});

Deno.test("Property 9: app_metadata only contains allowed sub-keys", () => {
  fc.assert(
    fc.property(jwtPayloadArb, (claims) => {
      const cleanClaims: Record<string, unknown> = {};
      for (const [k, v] of Object.entries(claims)) {
        if (v !== undefined) cleanClaims[k] = v;
      }

      const result = sanitizeJwtClaims(cleanClaims);

      if (result.app_metadata) {
        const metaKeys = Object.keys(result.app_metadata as Record<string, unknown>);
        for (const key of metaKeys) {
          assert(
            ALLOWED_APP_METADATA_KEYS.includes(key),
            `Unexpected app_metadata key in sanitized output: "${key}"`,
          );
        }
      }
    }),
    { numRuns: 200 },
  );
});

Deno.test("Property 9: Allowed fields are preserved when present", () => {
  fc.assert(
    fc.property(jwtPayloadArb, (claims) => {
      const cleanClaims: Record<string, unknown> = {};
      for (const [k, v] of Object.entries(claims)) {
        if (v !== undefined) cleanClaims[k] = v;
      }

      const result = sanitizeJwtClaims(cleanClaims);

      // Check that allowed top-level fields are preserved
      for (const key of ["sub", "aal", "role"]) {
        if (key in cleanClaims) {
          assertEquals(
            result[key],
            cleanClaims[key],
            `Allowed field "${key}" was not preserved`,
          );
        }
      }

      // Check that allowed app_metadata fields are preserved
      if (cleanClaims.app_metadata && typeof cleanClaims.app_metadata === "object") {
        const inputMeta = cleanClaims.app_metadata as Record<string, unknown>;
        const outputMeta = result.app_metadata as Record<string, unknown> | undefined;

        if (outputMeta) {
          for (const key of ALLOWED_APP_METADATA_KEYS) {
            if (key in inputMeta) {
              assertEquals(
                outputMeta[key],
                inputMeta[key],
                `Allowed app_metadata field "${key}" was not preserved`,
              );
            }
          }
        }
      }
    }),
    { numRuns: 200 },
  );
});

Deno.test("Property 9: Disallowed fields are always stripped (arbitrary payloads)", () => {
  fc.assert(
    fc.property(arbitraryPayloadArb, (claims) => {
      const result = sanitizeJwtClaims(claims);
      const resultKeys = Object.keys(result);

      for (const key of resultKeys) {
        assert(
          ALLOWED_TOP_LEVEL_KEYS.includes(key),
          `Unexpected key "${key}" survived sanitization from arbitrary payload`,
        );
      }
    }),
    { numRuns: 200 },
  );
});

Deno.test("Property 9: access_token and refresh_token are never in output", () => {
  fc.assert(
    fc.property(
      fc.record({
        sub: fc.uuid(),
        aal: fc.constantFrom("aal1", "aal2"),
        role: fc.constant("authenticated"),
        access_token: fc.string({ minLength: 10 }),
        refresh_token: fc.string({ minLength: 10 }),
        app_metadata: fc.record({
          super_admin: fc.boolean(),
          org_id: fc.uuid(),
        }),
      }),
      (claims) => {
        const result = sanitizeJwtClaims(claims);
        assert(!("access_token" in result), "access_token should be stripped");
        assert(!("refresh_token" in result), "refresh_token should be stripped");
      },
    ),
    { numRuns: 200 },
  );
});
