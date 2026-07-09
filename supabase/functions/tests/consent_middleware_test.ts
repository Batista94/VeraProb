/**
 * Consent Middleware Tests (INV-1, INV-22, INV-26)
 *
 * LGPD compliance: consent verification MUST fail-closed.
 * If we cannot confirm consent exists, processing is blocked.
 *
 * Run with: deno test --allow-env --allow-net supabase/functions/tests/consent_middleware_test.ts
 */

import { assertEquals } from "jsr:@std/assert@1";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { checkConsent } from "../shared/consent_middleware.ts";

// ── Mock Supabase Client ─────────────────────────────────────────────────────

/**
 * Creates a mock SupabaseClient with rpc() returning the configured result.
 * Production checkConsent uses has_current_telegram_consent (version-aware).
 */
function createMockSupabase(result: { data: unknown; error: unknown }): SupabaseClient {
  return {
    rpc: (_fn: string, _args?: Record<string, unknown>) =>
      Promise.resolve(result),
  } as unknown as SupabaseClient;
}

// ── Tests ────────────────────────────────────────────────────────────────────

Deno.test("checkConsent returns true when consent exists", async () => {
  const supabase = createMockSupabase({
    data: true,
    error: null,
  });

  const result = await checkConsent(supabase, 42);
  assertEquals(result, true);
});

Deno.test("checkConsent returns false when no consent exists", async () => {
  const supabase = createMockSupabase({
    data: false,
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

Deno.test("checkConsent returns false when RPC returns non-boolean (fail-closed)", async () => {
  const supabase = createMockSupabase({
    data: { id: 1 },
    error: null,
  });

  const result = await checkConsent(supabase, 42);
  assertEquals(result, false);
});
