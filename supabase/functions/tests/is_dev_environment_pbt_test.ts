/**
 * Property-Based Tests for isDevEnvironment
 *
 * Feature: superadmin-zero-trust-security, Property 7: Validação estrita de ENVIRONMENT
 *
 * **Validates: Requirements 3.5**
 *
 * Tests that the isDevEnvironment function accepts ONLY "dev" or "development"
 * as valid values — case-sensitive, no trim. Rejects all other strings including
 * "DEV", "Dev", "dev-like", "development ", "DEVELOPMENT", etc.
 *
 * Run with: deno test --allow-env --allow-net supabase/functions/tests/is_dev_environment_pbt_test.ts
 */

import { assertEquals, assert } from "jsr:@std/assert@1";
import fc from "fast-check";
import { isDevEnvironment } from "../shared/handle_with_security.ts";

// ── Helpers ──────────────────────────────────────────────────────────────────

/**
 * Sets the ENVIRONMENT variable and calls isDevEnvironment.
 * Restores the original value after the call.
 */
function withEnvironment(value: string | undefined): boolean {
  const original = Deno.env.get("ENVIRONMENT");

  if (value === undefined) {
    Deno.env.delete("ENVIRONMENT");
  } else {
    Deno.env.set("ENVIRONMENT", value);
  }

  const result = isDevEnvironment();

  // Restore
  if (original === undefined) {
    Deno.env.delete("ENVIRONMENT");
  } else {
    Deno.env.set("ENVIRONMENT", original);
  }

  return result;
}

// ── Generators ───────────────────────────────────────────────────────────────

/**
 * Generates strings that are NOT exactly "dev" or "development".
 * Includes near-misses like "DEV", "Dev", "dev ", " dev", "dev-like", etc.
 */
const nonDevStringArb = fc.oneof(
  // Random strings
  fc.string().filter((s) => s !== "dev" && s !== "development"),
  // Near-miss variations
  fc.constantFrom(
    "DEV", "Dev", "dEv", "deV",
    "DEVELOPMENT", "Development", "dEVELOPMENT",
    "dev ", " dev", "dev\t", "\tdev",
    "development ", " development", "development\t",
    "dev-like", "dev-mode", "dev_mode",
    "development-local", "development_local",
    "staging", "production", "prod", "test",
    "local", "sandbox", "preview",
    "", "null", "undefined", "true", "false",
  ),
);

// ── Property Tests ───────────────────────────────────────────────────────────

Deno.test("Property 7: 'dev' always returns true", () => {
  fc.assert(
    fc.property(fc.constant("dev"), (env) => {
      assert(
        withEnvironment(env),
        `Expected "dev" to return true`,
      );
    }),
    { numRuns: 100 },
  );
});

Deno.test("Property 7: 'development' always returns true", () => {
  fc.assert(
    fc.property(fc.constant("development"), (env) => {
      assert(
        withEnvironment(env),
        `Expected "development" to return true`,
      );
    }),
    { numRuns: 100 },
  );
});

Deno.test("Property 7: Any string that is not exactly 'dev' or 'development' returns false", () => {
  fc.assert(
    fc.property(nonDevStringArb, (env) => {
      assertEquals(
        withEnvironment(env),
        false,
        `Expected "${env}" to return false (only "dev" and "development" are valid)`,
      );
    }),
    { numRuns: 200 },
  );
});

Deno.test("Property 7: Undefined ENVIRONMENT returns false", () => {
  assertEquals(
    withEnvironment(undefined),
    false,
    "Expected undefined ENVIRONMENT to return false",
  );
});

Deno.test("Property 7: Case variations of 'dev' are rejected (case-sensitive)", () => {
  fc.assert(
    fc.property(
      fc.stringOf(fc.constantFrom("d", "D", "e", "E", "v", "V"))
        .filter((s) => s.length === 3 && s !== "dev"),
      (env) => {
        assertEquals(
          withEnvironment(env),
          false,
          `Expected case variation "${env}" to be rejected`,
        );
      },
    ),
    { numRuns: 100 },
  );
});

Deno.test("Property 7: Strings with whitespace padding are rejected (no trim)", () => {
  fc.assert(
    fc.property(
      fc.constantFrom("dev", "development"),
      fc.oneof(
        fc.constant(" "),
        fc.constant("  "),
        fc.constant("\t"),
        fc.constant("\n"),
        fc.constant(" \t"),
      ),
      (validEnv, padding) => {
        // Prepend padding
        assertEquals(
          withEnvironment(padding + validEnv),
          false,
          `Expected "${padding + validEnv}" (leading whitespace) to be rejected`,
        );
        // Append padding
        assertEquals(
          withEnvironment(validEnv + padding),
          false,
          `Expected "${validEnv + padding}" (trailing whitespace) to be rejected`,
        );
      },
    ),
    { numRuns: 100 },
  );
});
