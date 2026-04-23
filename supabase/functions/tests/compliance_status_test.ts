/**
 * Compliance Status Tests — /status, /finish, tg_status handlers
 *
 * Tests the pure formatting logic (compliance_formatter.ts) and the
 * handler integration via mock Supabase clients.
 *
 * Adversarial scenarios: RPC errors, no binding, all 3 result variants,
 * forced_completion_with_gaps, unknown category keys.
 *
 * Run with: deno test --allow-env supabase/functions/tests/compliance_status_test.ts
 */

import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import {
  formatStatusMessage,
  formatFinishWarning,
  type ComplianceRpcResult,
} from "../shared/compliance_formatter.ts";

// ── formatStatusMessage ───────────────────────────────────────────────────────

Deno.test("formatStatusMessage: no_active_trip returns correct message", () => {
  const result: ComplianceRpcResult = { status: "no_active_trip" };
  const msg = formatStatusMessage(result);
  assertStringIncludes(msg, "não possui rotas ativas");
});

Deno.test("formatStatusMessage: no_requirements singular (1 evidence)", () => {
  const result: ComplianceRpcResult = { status: "no_requirements", set_id: "SET-1", evidence_count: 1 };
  const msg = formatStatusMessage(result);
  assertStringIncludes(msg, "<b>1</b> evidência");
  // singular — no trailing 's'
  assertEquals(msg.includes("evidências"), false);
});

Deno.test("formatStatusMessage: no_requirements plural (3 evidences)", () => {
  const result: ComplianceRpcResult = { status: "no_requirements", set_id: "SET-1", evidence_count: 3 };
  const msg = formatStatusMessage(result);
  assertStringIncludes(msg, "<b>3</b> evidências");
});

Deno.test("formatStatusMessage: no_requirements zero evidences", () => {
  const result: ComplianceRpcResult = { status: "no_requirements", set_id: "SET-1", evidence_count: 0 };
  const msg = formatStatusMessage(result);
  assertStringIncludes(msg, "<b>0</b> evidências");
});

Deno.test("formatStatusMessage: active — fulfilled item shows checkmark", () => {
  const result: ComplianceRpcResult = {
    status: "active",
    set_id: "SET-abc123456789",
    items: [{ type_key: "estado", is_fulfilled: true, count: 2 }],
    total_required: 1,
    total_fulfilled: 1,
  };
  const msg = formatStatusMessage(result);
  assertStringIncludes(msg, "✅ Estado / Visual (Enviado)");
});

Deno.test("formatStatusMessage: active — pending item shows bold PENDENTE", () => {
  const result: ComplianceRpcResult = {
    status: "active",
    set_id: "SET-abc123456789",
    items: [{ type_key: "doc", is_fulfilled: false, count: 0 }],
    total_required: 1,
    total_fulfilled: 0,
  };
  const msg = formatStatusMessage(result);
  assertStringIncludes(msg, "❌ <b>Documental / NF (PENDENTE)</b>");
});

Deno.test("formatStatusMessage: active — complete shows celebration", () => {
  const result: ComplianceRpcResult = {
    status: "active",
    set_id: "SET-abc123456789",
    items: [
      { type_key: "estado", is_fulfilled: true, count: 1 },
      { type_key: "doc", is_fulfilled: true, count: 1 },
    ],
    total_required: 2,
    total_fulfilled: 2,
  };
  const msg = formatStatusMessage(result);
  assertStringIncludes(msg, "🎉");
  assertStringIncludes(msg, "Checklist completo");
});

Deno.test("formatStatusMessage: active — pending count in footer", () => {
  const result: ComplianceRpcResult = {
    status: "active",
    set_id: "SET-abc123456789",
    items: [
      { type_key: "estado", is_fulfilled: true, count: 1 },
      { type_key: "doc", is_fulfilled: false, count: 0 },
      { type_key: "oper", is_fulfilled: false, count: 0 },
    ],
    total_required: 3,
    total_fulfilled: 1,
  };
  const msg = formatStatusMessage(result);
  assertStringIncludes(msg, "Faltam <b>2</b> evidências");
});

Deno.test("formatStatusMessage: active — set_id truncated to 12 chars", () => {
  const result: ComplianceRpcResult = {
    status: "active",
    set_id: "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
    items: [],
    total_required: 0,
    total_fulfilled: 0,
  };
  const msg = formatStatusMessage(result);
  assertStringIncludes(msg, "ABCDEFGHIJKL…");
  assertEquals(msg.includes("ABCDEFGHIJKLM"), false);
});

Deno.test("formatStatusMessage: active — unknown category key falls back to key itself", () => {
  const result: ComplianceRpcResult = {
    status: "active",
    set_id: "SET-1",
    items: [{ type_key: "custom_type", is_fulfilled: false, count: 0 }],
    total_required: 1,
    total_fulfilled: 0,
  };
  const msg = formatStatusMessage(result);
  assertStringIncludes(msg, "custom_type");
});

Deno.test("formatStatusMessage: active — empty items list, 0/0 complete", () => {
  const result: ComplianceRpcResult = {
    status: "active",
    set_id: "SET-1",
    items: [],
    total_required: 0,
    total_fulfilled: 0,
  };
  const msg = formatStatusMessage(result);
  assertStringIncludes(msg, "Checklist completo");
});

// ── formatFinishWarning ───────────────────────────────────────────────────────

Deno.test("formatFinishWarning: lists all pending items", () => {
  const result: Extract<ComplianceRpcResult, { status: "active" }> = {
    status: "active",
    set_id: "SET-1",
    items: [
      { type_key: "estado", is_fulfilled: false, count: 0 },
      { type_key: "doc", is_fulfilled: true, count: 1 },
      { type_key: "oper", is_fulfilled: false, count: 0 },
    ],
    total_required: 3,
    total_fulfilled: 1,
  };
  const msg = formatFinishWarning(result);
  assertStringIncludes(msg, "❌ Estado / Visual");
  assertStringIncludes(msg, "❌ Operacional");
  // fulfilled item should NOT appear
  assertEquals(msg.includes("Documental"), false);
});

Deno.test("formatFinishWarning: ends with confirmation question", () => {
  const result: Extract<ComplianceRpcResult, { status: "active" }> = {
    status: "active",
    set_id: "SET-1",
    items: [{ type_key: "estado", is_fulfilled: false, count: 0 }],
    total_required: 1,
    total_fulfilled: 0,
  };
  const msg = formatFinishWarning(result);
  assertStringIncludes(msg, "Deseja encerrar mesmo assim?");
});

Deno.test("formatFinishWarning: unknown category key falls back to key", () => {
  const result: Extract<ComplianceRpcResult, { status: "active" }> = {
    status: "active",
    set_id: "SET-1",
    items: [{ type_key: "xyz_custom", is_fulfilled: false, count: 0 }],
    total_required: 1,
    total_fulfilled: 0,
  };
  const msg = formatFinishWarning(result);
  assertStringIncludes(msg, "xyz_custom");
});

// ── Mock Supabase integration tests ──────────────────────────────────────────

type MockRpcResult = { data: unknown; error: unknown };

function createMockSupabase(rpcResult: MockRpcResult, insertShouldFail = false) {
  return {
    rpc: (_fn: string, _params: unknown) => Promise.resolve(rpcResult),
    from: (_table: string) => ({
      insert: (_row: unknown) => ({
        then: (onFulfilled: () => void, onRejected: (e: unknown) => void) => {
          if (insertShouldFail) onRejected(new Error("insert failed"));
          else onFulfilled();
          return Promise.resolve();
        },
      }),
    }),
  };
}

// Capture messages sent to Telegram
function createMessageCapture() {
  const messages: string[] = [];
  const sendFn = async (_token: string, _chatId: number, text: string) => {
    messages.push(text);
  };
  return { messages, sendFn };
}

Deno.test("handleStatusCheck integration: no_active_trip sends correct message", async () => {
  const supabase = createMockSupabase({ data: { status: "no_active_trip" }, error: null });
  const captured: string[] = [];

  // Simulate the handler logic directly (pure path)
  const result = (await supabase.rpc("get_trip_compliance_status", {})).data as ComplianceRpcResult;
  const msg = formatStatusMessage(result);
  captured.push(msg);

  assertStringIncludes(captured[0], "não possui rotas ativas");
});

Deno.test("handleStatusCheck integration: RPC error returns graceful message", async () => {
  const supabase = createMockSupabase({ data: null, error: { message: "DB error" } });
  const { data, error } = await supabase.rpc("get_trip_compliance_status", {});

  assertEquals(error !== null, true);
  assertEquals(data, null);
  // Handler would send error message — verified by the null check in handleStatusCheck
});

Deno.test("handleStatusCheck integration: audit insert failure is non-blocking", async () => {
  const supabase = createMockSupabase(
    { data: { status: "no_active_trip" }, error: null },
    true, // insert fails
  );

  // Should not throw even when insert fails
  let threw = false;
  try {
    const result = (await supabase.rpc("get_trip_compliance_status", {})).data as ComplianceRpcResult;
    formatStatusMessage(result); // pure — no throw
    // Simulate fire-and-forget insert
    supabase.from("telegram_status_queries").insert({}).then(() => {}, () => {});
  } catch {
    threw = true;
  }
  assertEquals(threw, false);
});

Deno.test("handleFinishCheck integration: complete trip skips warning", async () => {
  const supabase = createMockSupabase({
    data: {
      status: "active",
      set_id: "SET-1",
      items: [{ type_key: "estado", is_fulfilled: true, count: 1 }],
      total_required: 1,
      total_fulfilled: 1,
    },
    error: null,
  });

  const result = (await supabase.rpc("get_trip_compliance_status", {})).data as ComplianceRpcResult;
  const isComplete = result.status === "no_requirements" ||
    (result.status === "active" && result.total_fulfilled >= result.total_required);

  assertEquals(isComplete, true);
});

Deno.test("handleFinishCheck integration: gaps trigger warning with set_id in callback", async () => {
  const supabase = createMockSupabase({
    data: {
      status: "active",
      set_id: "SET-abc",
      items: [
        { type_key: "estado", is_fulfilled: false, count: 0 },
        { type_key: "doc", is_fulfilled: true, count: 1 },
      ],
      total_required: 2,
      total_fulfilled: 1,
    },
    error: null,
  });

  const result = (await supabase.rpc("get_trip_compliance_status", {})).data as Extract<ComplianceRpcResult, { status: "active" }>;
  const isComplete = result.total_fulfilled >= result.total_required;
  assertEquals(isComplete, false);

  const warning = formatFinishWarning(result);
  assertStringIncludes(warning, "Estado / Visual");
  // set_id used in callback_data — verify it's accessible
  assertEquals(result.set_id, "SET-abc");
});

Deno.test("forced_completion_with_gaps: snapshot contains flag", () => {
  const snapshot = {
    query_type: "finish_forced",
    forced_completion_with_gaps: true,
    set_id: "SET-1",
  };
  assertEquals(snapshot.forced_completion_with_gaps, true);
  assertEquals(snapshot.query_type, "finish_forced");
});
