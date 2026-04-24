/**
 * Consent Middleware Tests (INV-1, INV-22, INV-26)
 *
 * LGPD compliance: consent verification MUST fail-closed.
 * If we cannot confirm consent exists, processing is blocked.
 *
 * Run with: deno test --allow-env --allow-net supabase/functions/tests/consent_middleware_test.ts
 */

import { assertEquals } from "jsr:@std/assert@1";
import { checkConsent } from "../shared/consent_middleware.ts";

// ── Mock Supabase Client ─────────────────────────────────────────────────────

/**
 * Creates a mock SupabaseClient with a chainable .from().select().eq().maybeSingle() API.
 * Returns the configured result at the end of the chain.
 */
function createMockSupabase(result: { data: unknown; error: unknown }) {
  return {
    from: (_table: string) => ({
      select: (_columns: string) => ({
        eq: (_column: string, _value: unknown) => ({
          maybeSingle: () => Promise.resolve(result),
        }),
      }),
    }),
  } as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient;
}

// ── Tests ────────────────────────────────────────────────────────────────────

Deno.test("checkConsent returns true when consent exists", async () => {
  const supabase = createMockSupabase({
    data: { id: 1, chat_id: 42, consented_at: "2026-01-01T00:00:00Z" },
    error: null,
  });

  const result = await checkConsent(supabase, 42);
  assertEquals(result, true);
});

Deno.test("checkConsent returns false when no consent exists", async () => {
  const supabase = createMockSupabase({
    data: null,
    error: null,
  });

  const result = await checkConsent(supabase, 42);
  assertEquals(result, false);
});

Deno.test("checkConsent returns false on DB error (fail-closed for LGPD)", async () => {
  const supabase = createMockSupabase({
    data: null,
    error: { message: "connection refused", code: "PGRST301" },
  });

  // LGPD: if we cannot verify consent, we MUST NOT process.
  // The function must not throw — it returns false (fail-closed).
  const result = await checkConsent(supabase, 42);
  assertEquals(result, false);
});
