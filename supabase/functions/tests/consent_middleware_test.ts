/**
 * Consent Middleware Tests (INV-1, INV-22, INV-26)
 *
 * LGPD compliance: consent verification MUST fail-closed.
 * If we cannot confirm consent exists, processing is blocked.
 *
 * Run with: deno test --allow-env --allow-net supabase/functions/tests/consent_middleware_test.ts
 */

import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import {
  acceptTelegramTerms,
  checkConsent,
  formatTermsForTelegram,
  getActiveTelegramTerms,
  withdrawTelegramConsent,
  type ActiveTelegramTerms,
} from "../shared/consent_middleware.ts";

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

Deno.test("getActiveTelegramTerms returns null on RPC error (fail-closed)", async () => {
  const supabase = createMockSupabase({
    data: null,
    error: { message: "rpc failed" },
  });
  assertEquals(await getActiveTelegramTerms(supabase), null);
});

Deno.test("getActiveTelegramTerms returns null when body missing", async () => {
  const supabase = createMockSupabase({
    data: { id: "doc-1", version: "1.0", title: "T", body_markdown: "" },
    error: null,
  });
  assertEquals(await getActiveTelegramTerms(supabase), null);
});

Deno.test("getActiveTelegramTerms returns payload when valid", async () => {
  const row: ActiveTelegramTerms = {
    id: "doc-1",
    version: "1.0",
    title: "Termos Bot",
    body_markdown: "# Hello",
    content_sha256: "a".repeat(64),
    published_at_utc: "2026-01-01T00:00:00Z",
  };
  const supabase = createMockSupabase({ data: row, error: null });
  const terms = await getActiveTelegramTerms(supabase);
  assertEquals(terms?.id, "doc-1");
  assertEquals(terms?.version, "1.0");
});

Deno.test("acceptTelegramTerms returns false on error (T-02 adverse)", async () => {
  const supabase = createMockSupabase({
    data: null,
    error: { message: "Document not available", code: "P0002" },
  });
  assertEquals(await acceptTelegramTerms(supabase, 42, "doc-1"), false);
});

Deno.test("acceptTelegramTerms returns true when RPC succeeds", async () => {
  const supabase = createMockSupabase({ data: "uuid", error: null });
  assertEquals(await acceptTelegramTerms(supabase, 42), true);
});

Deno.test("withdrawTelegramConsent returns false on error (T-05 adverse)", async () => {
  const supabase = createMockSupabase({
    data: null,
    error: { message: "Document not available" },
  });
  assertEquals(await withdrawTelegramConsent(supabase, 42), false);
});

Deno.test("withdrawTelegramConsent returns true when RPC succeeds", async () => {
  const supabase = createMockSupabase({ data: "uuid", error: null });
  assertEquals(await withdrawTelegramConsent(supabase, 42), true);
});

Deno.test("formatTermsForTelegram includes title, version, escaped HTML", () => {
  const html = formatTermsForTelegram({
    id: "doc-1",
    version: "1.0",
    title: "Termos <Bot>",
    body_markdown: "## Seção\n**negrito** & mais",
    content_sha256: "a".repeat(64),
    published_at_utc: "2026-01-01T00:00:00Z",
  });
  assertStringIncludes(html, "Termos &lt;Bot&gt;");
  assertStringIncludes(html, "Versão 1.0");
  assertStringIncludes(html, "<b>negrito</b>");
  assertEquals(html.includes("<Bot>"), false);
});
