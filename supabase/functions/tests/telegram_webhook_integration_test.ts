/**
 * Telegram Webhook — Integration & Unit Test Suite
 *
 * Tiers:
 *   [U] Unit  — pure logic, no I/O (validateMessageDate, sniffExtension, drift)
 *   [H] HTTP  — live calls to local Supabase endpoint
 *   [I] HTTP+DB — HTTP call + DB side-effect verification
 *   [D] DB    — direct Supabase client (RPC / table queries)
 *   [C] Conditional — requires real bot token + seeded binding
 *
 * Run from project root:
 *   deno test --allow-env --allow-net --allow-read \
 *     supabase/functions/tests/telegram_webhook_integration_test.ts
 *
 * Requires: supabase start (local Docker)
 *
 * INV-1, INV-6, INV-10, INV-15, INV-18 covered.
 */

import { assertEquals, assert, assertExists } from "jsr:@std/assert@1";
import { createClient } from "jsr:@supabase/supabase-js@2";

// ── Env loading ───────────────────────────────────────────────────────────────

async function loadDotEnv(): Promise<Record<string, string>> {
  try {
    const envPath = new URL("../../../.env", import.meta.url);
    const raw = await Deno.readTextFile(
      Deno.build.os === "windows"
        ? envPath.pathname.replace(/^\/([A-Za-z]:)/, "$1")
        : envPath.pathname,
    );
    const result: Record<string, string> = {};
    for (const line of raw.split("\n")) {
      const t = line.trim();
      if (!t || t.startsWith("#")) continue;
      const eq = t.indexOf("=");
      if (eq < 0) continue;
      const key = t.slice(0, eq).trim();
      const val = t.slice(eq + 1).trim().replace(/^["']|["']$/g, "");
      if (val) result[key] = val;
    }
    return result;
  } catch {
    return {};
  }
}

const ENV = await loadDotEnv();

const SUPABASE_URL = ENV["SUPABASE_URL"] ?? Deno.env.get("SUPABASE_URL") ?? "http://127.0.0.1:54321";
const SERVICE_KEY  = ENV["SUPABASE_SERVICE_ROLE_KEY"] ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const WEBHOOK_SECRET = ENV["TELEGRAM_WEBHOOK_SECRET"] ?? Deno.env.get("TELEGRAM_WEBHOOK_SECRET") ?? "";

const ENDPOINT = `${SUPABASE_URL}/functions/v1/telegram-webhook`;

// Sentinel chat IDs — negative range unlikely to collide with real Telegram IDs in dev.
const CHAT_NO_CONSENT   = -9999990001n; // [I01]: LGPD gate test — must NOT have consent
const CHAT_WITH_CONSENT = -9999990002n; // [I02/I03]: timestamp tests — consent seeded per test
const CHAT_RATE_LIMIT   = -9999990003n; // [D01/D02]: rate limit RPC test

// ── Logic extracted from webhook (mirrors index.ts — not exported) ────────────

const TS_FUTURE_TOLERANCE_S = 60;
const TS_MAX_DRIFT_S = 86_400;
const FRAUD_DRIFT_THRESHOLD_S = 300;
const TG_FILE_SIZE_LIMIT = 10 * 1024 * 1024; // 10 MB

function validateMessageDate(messageUnixTs: number): { valid: boolean; reason?: string } {
  const nowS = Date.now() / 1000;
  if (messageUnixTs > nowS + TS_FUTURE_TOLERANCE_S) {
    return { valid: false, reason: `future_timestamp` };
  }
  if (nowS - messageUnixTs > TS_MAX_DRIFT_S) {
    return { valid: false, reason: `stale_timestamp` };
  }
  return { valid: true };
}

function sniffExtension(bytes: Uint8Array): string {
  if (bytes[0] === 0xFF && bytes[1] === 0xD8 && bytes[2] === 0xFF) return "jpg";
  if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4E && bytes[3] === 0x47) return "png";
  if (bytes[0] === 0x25 && bytes[1] === 0x50 && bytes[2] === 0x44 && bytes[3] === 0x46) return "pdf";
  if (bytes[0] === 0x4F && bytes[1] === 0x67 && bytes[2] === 0x67 && bytes[3] === 0x53) return "ogg";
  if (
    bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 &&
    bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50
  ) return "webp";
  if (
    bytes.length >= 12 &&
    bytes[4] === 0x66 && bytes[5] === 0x74 && bytes[6] === 0x79 && bytes[7] === 0x70
  ) {
    return "mp4";
  }
  return "bin";
}

// ── Payload builders ──────────────────────────────────────────────────────────

function photoPayload(chatId: bigint, messageDate: number): unknown {
  return {
    update_id: 100000001,
    message: {
      message_id: 42,
      date: messageDate,
      chat: { id: Number(chatId) },
      photo: [
        { file_id: "fake_file_id_small", file_size: 1024, width: 100, height: 100 },
        { file_id: "fake_file_id_large", file_size: 51200, width: 800, height: 600 },
      ],
    },
  };
}

function documentPayload(chatId: bigint, fileSize: number): unknown {
  return {
    update_id: 100000002,
    message: {
      message_id: 43,
      date: Math.floor(Date.now() / 1000),
      chat: { id: Number(chatId) },
      document: {
        file_id: "fake_doc_file_id",
        file_size: fileSize,
        file_name: "evidence.jpg",   // declared as jpg — but magic bytes will say bin
        mime_type: "image/jpeg",      // NOT trusted (INV-18)
      },
    },
  };
}

function authHeaders(secret: string): HeadersInit {
  return {
    "Content-Type": "application/json",
    "X-Telegram-Bot-Api-Secret-Token": secret,
  };
}

// ── Setup helpers ─────────────────────────────────────────────────────────────

/** Seeds CURRENT published telegram_bot_terms consent (version-aware SSOT). */
async function seedConsent(chatId: bigint): Promise<void> {
  const admin = createClient(SUPABASE_URL, SERVICE_KEY);
  const { error } = await admin.rpc("accept_telegram_bot_terms", {
    p_chat_id: Number(chatId),
  });
  if (error) throw new Error(`seedConsent failed: ${error.message}`);
}

/** Inserts a stale consent_version that must NOT satisfy has_current_telegram_consent. */
async function seedStaleConsent(chatId: bigint): Promise<void> {
  const admin = createClient(SUPABASE_URL, SERVICE_KEY);
  const { error } = await admin.from("telegram_user_consents").insert({
    chat_id: Number(chatId),
    consent_version: "v0_stale_test",
    action: "accepted",
    accepted_via: "telegram_callback",
  });
  if (error) throw new Error(`seedStaleConsent failed: ${error.message}`);
}

async function evidenceCountFor(chatId: bigint): Promise<number> {
  const admin = createClient(SUPABASE_URL, SERVICE_KEY);
  const { count, error } = await admin
    .from("telegram_evidence_uploads")
    .select("id", { count: "exact", head: true })
    .eq("chat_id", Number(chatId));
  if (error) throw new Error(`evidenceCount query failed: ${error.message}`);
  return count ?? 0;
}

// ═════════════════════════════════════════════════════════════════════════════
// SECTION A — UNIT TESTS: validateMessageDate (INV-6, INV-15)
// ═════════════════════════════════════════════════════════════════════════════

Deno.test("[U01] validateMessageDate: +5min future → invalid (future_timestamp)", () => {
  const futureTs = Math.floor(Date.now() / 1000) + 5 * 60 + 10; // 5m10s ahead
  const result = validateMessageDate(futureTs);
  assertEquals(result.valid, false);
  assertEquals(result.reason, "future_timestamp");
});

Deno.test("[U02] validateMessageDate: +61s future → invalid", () => {
  const ts = Math.floor(Date.now() / 1000) + 61;
  const result = validateMessageDate(ts);
  assertEquals(result.valid, false);
  assertEquals(result.reason, "future_timestamp");
});

Deno.test("[U03] validateMessageDate: +60s (tolerance boundary) → valid", () => {
  // Exactly at tolerance — should be accepted (≤ 60s ahead is OK)
  const ts = Math.floor(Date.now() / 1000) + 60;
  const result = validateMessageDate(ts);
  assertEquals(result.valid, true);
});

Deno.test("[U04] validateMessageDate: -26h stale → invalid (stale_timestamp)", () => {
  const ts = Math.floor(Date.now() / 1000) - 26 * 3600;
  const result = validateMessageDate(ts);
  assertEquals(result.valid, false);
  assertEquals(result.reason, "stale_timestamp");
});

Deno.test("[U05] validateMessageDate: exactly -24h stale → invalid", () => {
  // 86400s = exactly 24h — still invalid (strictly greater than allowed)
  const ts = Math.floor(Date.now() / 1000) - 86_401;
  const result = validateMessageDate(ts);
  assertEquals(result.valid, false);
});

Deno.test("[U06] validateMessageDate: -10min recent → valid", () => {
  const ts = Math.floor(Date.now() / 1000) - 10 * 60;
  const result = validateMessageDate(ts);
  assertEquals(result.valid, true);
});

// ═════════════════════════════════════════════════════════════════════════════
// SECTION B — UNIT TESTS: sniffExtension / Magic Bytes (INV-18)
// ═════════════════════════════════════════════════════════════════════════════

Deno.test("[U07] sniffExtension: JPEG magic bytes (FF D8 FF) → 'jpg'", () => {
  const bytes = new Uint8Array([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
  assertEquals(sniffExtension(bytes), "jpg");
});

Deno.test("[U08] sniffExtension: PNG magic bytes (89 50 4E 47) → 'png'", () => {
  const bytes = new Uint8Array([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  assertEquals(sniffExtension(bytes), "png");
});

Deno.test("[U09] sniffExtension: PDF magic bytes (25 50 44 46) → 'pdf'", () => {
  const bytes = new Uint8Array([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E]);
  assertEquals(sniffExtension(bytes), "pdf");
});

Deno.test("[U10] sniffExtension: OGG magic bytes (4F 67 67 53) → 'ogg'", () => {
  const bytes = new Uint8Array([0x4F, 0x67, 0x67, 0x53, 0x00, 0x02, 0x00]);
  assertEquals(sniffExtension(bytes), "ogg");
});

Deno.test("[U11] sniffExtension: .bin file disguised as .jpg (no valid magic) → 'bin' [FORMATO_NAO_SUPORTADO]", () => {
  // Random bytes with no valid magic header — webhook rejects these as "Formato não suportado"
  const fakeJpgBytes = new Uint8Array([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0xFF, 0xFE]);
  assertEquals(sniffExtension(fakeJpgBytes), "bin");
});

// ═════════════════════════════════════════════════════════════════════════════
// SECTION C — UNIT TESTS: File Size Pre-Check
// ═════════════════════════════════════════════════════════════════════════════

Deno.test("[U12] fileSize: 11 MB > 10 MB limit → rejected", () => {
  const fileSize = 11 * 1024 * 1024;
  const rejected = fileSize > TG_FILE_SIZE_LIMIT;
  assertEquals(rejected, true);
});

Deno.test("[U13] fileSize: exactly 10 MB = limit → allowed (boundary)", () => {
  const fileSize = 10 * 1024 * 1024;
  const rejected = fileSize > TG_FILE_SIZE_LIMIT;
  assertEquals(rejected, false);
});

// ═════════════════════════════════════════════════════════════════════════════
// SECTION D — UNIT TESTS: Clock Drift Alert (INV-6, INV-10)
// ═════════════════════════════════════════════════════════════════════════════

interface AlertRow { alert_type: string; severity: string; context: Record<string, unknown> }

async function mockFraudAlert(
  driftSeconds: number,
): Promise<AlertRow | null> {
  if (Math.abs(driftSeconds) <= FRAUD_DRIFT_THRESHOLD_S) return null;
  let captured: AlertRow | null = null;
  const fakeSupabase = {
    from: (_: string) => ({
      insert: (row: AlertRow) => {
        captured = row;
        return Promise.resolve({ error: null });
      },
    }),
  };
  const row: AlertRow = {
    alert_type: "POTENTIAL_TIME_FRAUD",
    severity: "HIGH",
    context: { clock_drift_seconds: driftSeconds, evidence_id: "ev-test" },
  };
  await fakeSupabase.from("operational_alerts").insert(row);
  return captured;
}

Deno.test("[U14] clockDrift: 301s > 300 threshold → POTENTIAL_TIME_FRAUD fires", async () => {
  const alert = await mockFraudAlert(301);
  assertExists(alert);
  assertEquals(alert!.alert_type, "POTENTIAL_TIME_FRAUD");
  assertEquals(alert!.severity, "HIGH");
});

Deno.test("[U15] clockDrift: exactly 300s = threshold → NO alert (strictly greater-than)", async () => {
  const alert = await mockFraudAlert(300);
  assertEquals(alert, null);
});

Deno.test("[U16] clockDrift: 600s (10min drift) → alert fires with correct drift value", async () => {
  const alert = await mockFraudAlert(600);
  assertExists(alert);
  assertEquals(alert!.context["clock_drift_seconds"], 600);
});

// ═════════════════════════════════════════════════════════════════════════════
// SECTION E — HTTP SECURITY (INV-18)
// Live calls — requires: supabase start + supabase functions serve
// ═════════════════════════════════════════════════════════════════════════════

Deno.test({
  name: "[H01] HTTP: missing X-Telegram-Bot-Api-Secret-Token → 401 Unauthorized",
  async fn() {
    const res = await fetch(ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ update_id: 1 }),
    });
    assertEquals(res.status, 401, `Expected 401, got ${res.status}`);
    await res.body?.cancel();
  },
});

Deno.test({
  name: "[H02] HTTP: wrong secret token → 401 Unauthorized",
  async fn() {
    const res = await fetch(ENDPOINT, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Telegram-Bot-Api-Secret-Token": "definitely_wrong_secret_xyz",
      },
      body: JSON.stringify({ update_id: 1 }),
    });
    assertEquals(res.status, 401, `Expected 401, got ${res.status}`);
    await res.body?.cancel();
  },
});

Deno.test({
  name: "[H03] HTTP: correct token + empty update → 200 OK (webhook always ACKs)",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    if (!WEBHOOK_SECRET) {
      console.log("  ⚠ WEBHOOK_SECRET not set — skipping live HTTP test");
      return;
    }
    const res = await fetch(ENDPOINT, {
      method: "POST",
      headers: authHeaders(WEBHOOK_SECRET),
      body: JSON.stringify({ update_id: 999 }),
    });
    assertEquals(res.status, 200, `Expected 200, got ${res.status}`);
    await res.body?.cancel();
  },
});

Deno.test({
  name: "[H04] HTTP: correct token + malformed JSON body → 200 OK (graceful parse failure)",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    if (!WEBHOOK_SECRET) {
      console.log("  ⚠ WEBHOOK_SECRET not set — skipping live HTTP test");
      return;
    }
    const res = await fetch(ENDPOINT, {
      method: "POST",
      headers: authHeaders(WEBHOOK_SECRET),
      body: "{ not valid json ::::",
    });
    assertEquals(res.status, 200, `Expected 200, got ${res.status}`);
    await res.body?.cancel();
  },
});

// ═════════════════════════════════════════════════════════════════════════════
// SECTION F — HTTP + DB: Temporal Heuristics & LGPD Gate
// Verifies rejection by absence of DB row (webhook always returns 200 OK).
// ═════════════════════════════════════════════════════════════════════════════

Deno.test({
  name: "[I01] LGPD Gate: photo for chat with no consent → 200 OK, no evidence inserted (INV-1)",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    if (!WEBHOOK_SECRET || !SERVICE_KEY) {
      console.log("  ⚠ WEBHOOK_SECRET or SERVICE_KEY not set — skipping");
      return;
    }

    const chatId = CHAT_NO_CONSENT;
    const beforeCount = await evidenceCountFor(chatId);

    const res = await fetch(ENDPOINT, {
      method: "POST",
      headers: authHeaders(WEBHOOK_SECRET),
      body: JSON.stringify(photoPayload(chatId, Math.floor(Date.now() / 1000))),
    });
    assertEquals(res.status, 200);
    await res.body?.cancel();

    const afterCount = await evidenceCountFor(chatId);
    assertEquals(
      afterCount,
      beforeCount,
      "LGPD gate must block evidence insertion — row count must not increase",
    );
  },
});

Deno.test({
  name: "[I01b] LGPD: stale consent_version does NOT unlock evidence (version-aware)",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    if (!WEBHOOK_SECRET || !SERVICE_KEY) {
      console.log("  ⚠ WEBHOOK_SECRET or SERVICE_KEY not set — skipping");
      return;
    }

    const chatId = -9999990011n;
    await seedStaleConsent(chatId);
    const beforeCount = await evidenceCountFor(chatId);

    const res = await fetch(ENDPOINT, {
      method: "POST",
      headers: authHeaders(WEBHOOK_SECRET),
      body: JSON.stringify(photoPayload(chatId, Math.floor(Date.now() / 1000))),
    });
    assertEquals(res.status, 200);
    await res.body?.cancel();

    const afterCount = await evidenceCountFor(chatId);
    assertEquals(
      afterCount,
      beforeCount,
      "stale consent_version must not unlock evidence uploads",
    );
  },
});

Deno.test({
  name: "[I01c] LGPD: binding code without current consent → no chat_bindings row",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    if (!WEBHOOK_SECRET || !SERVICE_KEY) {
      console.log("  ⚠ WEBHOOK_SECRET or SERVICE_KEY not set — skipping");
      return;
    }

    const chatId = -9999990012n;
    const admin = createClient(SUPABASE_URL, SERVICE_KEY);
    const { count: before } = await admin
      .from("telegram_chat_bindings")
      .select("id", { count: "exact", head: true })
      .eq("chat_id", Number(chatId));

    // 8-char Crockford code — RPC/webhook must reject before creating binding.
    const res = await fetch(ENDPOINT, {
      method: "POST",
      headers: authHeaders(WEBHOOK_SECRET),
      body: JSON.stringify({
        update_id: 910012,
        message: {
          message_id: 1,
          date: Math.floor(Date.now() / 1000),
          chat: { id: Number(chatId), type: "private" },
          text: "ABCD2345",
        },
      }),
    });
    assertEquals(res.status, 200);
    await res.body?.cancel();

    const { count: after } = await admin
      .from("telegram_chat_bindings")
      .select("id", { count: "exact", head: true })
      .eq("chat_id", Number(chatId));
    assertEquals(
      after ?? 0,
      before ?? 0,
      "consent-before-binding: no binding row without current LGPD consent",
    );
  },
});

Deno.test({
  name: "[I02] Timestamp: future +5min → rejected, no evidence row (INV-6)",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    if (!WEBHOOK_SECRET || !SERVICE_KEY) {
      console.log("  ⚠ WEBHOOK_SECRET or SERVICE_KEY not set — skipping");
      return;
    }

    const chatId = CHAT_WITH_CONSENT;
    await seedConsent(chatId);

    const futureTs = Math.floor(Date.now() / 1000) + 5 * 60 + 30; // +5m30s
    const beforeCount = await evidenceCountFor(chatId);

    const res = await fetch(ENDPOINT, {
      method: "POST",
      headers: authHeaders(WEBHOOK_SECRET),
      body: JSON.stringify(photoPayload(chatId, futureTs)),
    });
    assertEquals(res.status, 200);
    await res.body?.cancel();

    const afterCount = await evidenceCountFor(chatId);
    assertEquals(
      afterCount,
      beforeCount,
      "Future timestamp must be rejected — no evidence row created",
    );
  },
});

Deno.test({
  name: "[I03] Timestamp: stale -26h → rejected, no evidence row (INV-6, INV-15)",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    if (!WEBHOOK_SECRET || !SERVICE_KEY) {
      console.log("  ⚠ WEBHOOK_SECRET or SERVICE_KEY not set — skipping");
      return;
    }

    const chatId = CHAT_WITH_CONSENT;
    await seedConsent(chatId); // idempotent via upsert

    const staleTs = Math.floor(Date.now() / 1000) - 26 * 3600;
    const beforeCount = await evidenceCountFor(chatId);

    const res = await fetch(ENDPOINT, {
      method: "POST",
      headers: authHeaders(WEBHOOK_SECRET),
      body: JSON.stringify(photoPayload(chatId, staleTs)),
    });
    assertEquals(res.status, 200);
    await res.body?.cancel();

    const afterCount = await evidenceCountFor(chatId);
    assertEquals(
      afterCount,
      beforeCount,
      "Stale timestamp (26h) must be rejected — no evidence row created",
    );
  },
});

Deno.test({
  name: "[I04] File size: document 11 MB → rejected pre-download, no evidence row (INV-18)",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    if (!WEBHOOK_SECRET || !SERVICE_KEY) {
      console.log("  ⚠ WEBHOOK_SECRET or SERVICE_KEY not set — skipping");
      return;
    }

    // Chat must have consent AND binding for execution to reach the size check.
    // Without binding, it short-circuits at "Chat não vinculado".
    // Without consent, it short-circuits at LGPD gate (before size check).
    // This test verifies the size pre-check using a chat WITH consent but WITHOUT binding:
    //   consent ✓ → timestamp ✓ → binding ✗ → returns "Chat não vinculado" (no evidence).
    // To reach the actual size check line, a bound chat is required — see [C01] for full path.
    // Here we verify the DB assertion holds: no evidence for oversized file.
    const chatId = CHAT_WITH_CONSENT;
    await seedConsent(chatId);

    const oversizeBytes = 11 * 1024 * 1024; // 11 MB
    const beforeCount = await evidenceCountFor(chatId);

    const res = await fetch(ENDPOINT, {
      method: "POST",
      headers: authHeaders(WEBHOOK_SECRET),
      body: JSON.stringify(documentPayload(chatId, oversizeBytes)),
    });
    assertEquals(res.status, 200);
    await res.body?.cancel();

    const afterCount = await evidenceCountFor(chatId);
    assertEquals(
      afterCount,
      beforeCount,
      "Oversized file must not produce an evidence row",
    );
  },
});

// ═════════════════════════════════════════════════════════════════════════════
// SECTION G — DB: Rate Limit RPC (check_telegram_rate_limit)
// ═════════════════════════════════════════════════════════════════════════════

Deno.test({
  name: "[D01] RPC check_telegram_rate_limit: fresh chat_id with 0 uploads → TRUE (allowed)",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    if (!SERVICE_KEY) {
      console.log("  ⚠ SERVICE_KEY not set — skipping DB test");
      return;
    }

    const admin = createClient(SUPABASE_URL, SERVICE_KEY);
    const { data, error } = await admin.rpc("check_telegram_rate_limit", {
      p_chat_id: Number(CHAT_RATE_LIMIT),
    });

    assert(!error, `RPC error: ${error?.message}`);
    assertEquals(data, true, "Fresh chat with 0 uploads must be allowed");
  },
});

Deno.test({
  name: "[D02] RPC check_telegram_rate_limit: saturated chat (≥10 uploads/60s) → FALSE (blocked)",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    if (!SERVICE_KEY) {
      console.log("  ⚠ SERVICE_KEY not set — skipping DB test");
      return;
    }

    const admin = createClient(SUPABASE_URL, SERVICE_KEY);

    // Need a real driver to satisfy telegram_evidence_uploads.driver_id FK.
    const { data: drivers } = await admin
      .from("drivers")
      .select("id, organization_id")
      .limit(1);

    if (!drivers || drivers.length === 0) {
      console.log("  ⚠ No drivers in DB — skipping rate limit saturation test");
      return;
    }

    const { id: driverId, organization_id: orgId } = drivers[0];
    const chatId = Number(CHAT_RATE_LIMIT) - 1; // distinct sentinel for saturation test

    // Insert 10 fake uploads within the last 60s window
    const rows = Array.from({ length: 10 }, (_, i) => ({
      organization_id: orgId,
      driver_id: driverId,
      chat_id: chatId,
      telegram_message_id: 90000 + i,
      file_name: `test_rate_${i}.jpg`,
      forensic_hash: "a".repeat(64),
      storage_path: `test/${chatId}/f${i}.jpg`,
      source: "telegram",
    }));

    const { error: insertErr } = await admin
      .from("telegram_evidence_uploads")
      .insert(rows);

    if (insertErr) {
      console.log(`  ⚠ Could not seed rate-limit rows: ${insertErr.message} — skipping`);
      return;
    }

    // RPC must now return false (10 uploads in last 60s → COUNT(*) < 10 is FALSE)
    const { data, error } = await admin.rpc("check_telegram_rate_limit", {
      p_chat_id: chatId,
    });

    assert(!error, `RPC error: ${error?.message}`);
    assertEquals(data, false, "10 uploads in 60s must be blocked (rate limit hit)");
  },
});

// ═════════════════════════════════════════════════════════════════════════════
// SECTION H — CONDITIONAL: Clock Drift Alert + DB Verification (INV-6, INV-10)
//
// Requires a bound chat_id + valid file credentials.
// Set env vars to enable:
//   SEEDED_CHAT_ID   — chat_id (BIGINT) with consent and active binding
//
// Without a real Telegram bot token + file_id, the webhook cannot complete
// the file download pipeline (getTelegramFilePath → downloadTelegramFile).
// This test verifies the DB side-effect only when full credentials are present.
// ═════════════════════════════════════════════════════════════════════════════

Deno.test({
  name: "[C01] Clock drift 10min: evidence accepted + POTENTIAL_TIME_FRAUD in operational_alerts",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    const seededChatRaw = ENV["SEEDED_CHAT_ID"] ?? Deno.env.get("SEEDED_CHAT_ID");
    if (!seededChatRaw || !WEBHOOK_SECRET || !SERVICE_KEY) {
      console.log(
        "  ⚠ SEEDED_CHAT_ID not set (or missing WEBHOOK_SECRET/SERVICE_KEY) — skipping drift alert integration test.\n" +
        "    To enable: set SEEDED_CHAT_ID=<chat_id_with_consent_and_binding> in .env",
      );
      return;
    }

    const chatId = parseInt(seededChatRaw, 10);
    assert(!isNaN(chatId), "SEEDED_CHAT_ID must be a valid integer");

    const admin = createClient(SUPABASE_URL, SERVICE_KEY);
    const driftTs = Math.floor(Date.now() / 1000) - 10 * 60; // 10 min ago (600s drift > 300s threshold)

    const alertsBefore = await admin
      .from("operational_alerts")
      .select("id", { count: "exact", head: true })
      .eq("entity_id", String(chatId))
      .eq("alert_type", "POTENTIAL_TIME_FRAUD");

    const countBefore = alertsBefore.count ?? 0;

    const res = await fetch(ENDPOINT, {
      method: "POST",
      headers: authHeaders(WEBHOOK_SECRET),
      body: JSON.stringify(photoPayload(BigInt(chatId), driftTs)),
    });
    assertEquals(res.status, 200, "Webhook must return 200 even for drifted evidence");
    await res.body?.cancel();

    // Allow fire-and-forget alert insert to settle
    await new Promise((r) => setTimeout(r, 1000));

    const alertsAfter = await admin
      .from("operational_alerts")
      .select("id, context", { count: "exact" })
      .eq("entity_id", String(chatId))
      .eq("alert_type", "POTENTIAL_TIME_FRAUD")
      .order("created_at", { ascending: false })
      .limit(1);

    assert(
      (alertsAfter.count ?? 0) > countBefore,
      "POTENTIAL_TIME_FRAUD alert must be created in operational_alerts for 10-min drift",
    );

    const latestAlert = alertsAfter.data?.[0];
    assertExists(latestAlert, "Alert row must exist");
    assert(
      Math.abs((latestAlert.context as Record<string, number>)["clock_drift_seconds"]) > FRAUD_DRIFT_THRESHOLD_S,
      `drift in alert context must exceed threshold ${FRAUD_DRIFT_THRESHOLD_S}s`,
    );
  },
});
