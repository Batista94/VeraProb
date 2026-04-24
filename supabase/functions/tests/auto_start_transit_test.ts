/**
 * Auto-Start Transit Tests — Task 3 (INV-6, Physical Evidence Sovereignty)
 *
 * Validates the auto-start-transit logic triggered when driver classifies evidence
 * as lacre, chk_saida, or carregamento.
 *
 * Physical Evidence Sovereignty: a photo of a lacre has contract sovereignty.
 * If he sealed it, transport started. FSM transition planned → inTransit.
 *
 * Run with: deno test --allow-env supabase/functions/tests/auto_start_transit_test.ts
 */

import { assertEquals } from "jsr:@std/assert@1";

// ── Constants (mirrors index.ts) ──────────────────────────────────────────────

const TRANSIT_TRIGGER_CATEGORIES = new Set(["lacre", "chk_saida", "carregamento"]);

// ── Simulation of tg_tag auto-start logic ─────────────────────────────────────

interface Evidence {
  linked_set_id: string | null;
}

type TransitRpcResult = { data: boolean | null; error: null } | { data: null; error: { message: string } };

async function handleCategoryAutoStart(
  supabase: {
    from: (table: string) => {
      select: (cols: string) => {
        eq: (col: string, val: string) => {
          eq: (col: string, val: string) => {
            maybeSingle: () => Promise<{ data: Evidence | null }>;
          };
        };
      };
    };
    rpc: (name: string, params: Record<string, string>) => Promise<TransitRpcResult>;
  },
  categoryKey: string,
  evidenceId: string,
  orgId: string,
): Promise<{ transitStarted: boolean; categoryError: boolean }> {
  if (!TRANSIT_TRIGGER_CATEGORIES.has(categoryKey)) {
    return { transitStarted: false, categoryError: false };
  }

  let transitStarted = false;
  try {
    const { data: evidenceRow } = await supabase
      .from("telegram_evidence_uploads")
      .select("linked_set_id")
      .eq("id", evidenceId)
      .eq("organization_id", orgId)
      .maybeSingle();

    const linkedSetId = evidenceRow?.linked_set_id ?? null;
    if (linkedSetId) {
      const { data: started } = await supabase.rpc("start_transit_for_execution", {
        p_org_id: orgId,
        p_set_id: linkedSetId,
      });
      transitStarted = started === true;
    }
  } catch (_e) {
    // Non-blocking: category save is already committed, transit failure logged only.
  }

  return { transitStarted, categoryError: false };
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function makeSupabaseWithEvidence(evidence: Evidence | null, rpcResult: boolean) {
  return {
    from: (_table: string) => ({
      select: (_cols: string) => ({
        eq: (_col: string, _val: string) => ({
          eq: (_col2: string, _val2: string) => ({
            maybeSingle: () => Promise.resolve({ data: evidence }),
          }),
        }),
      }),
    }),
    rpc: (_name: string, _params: Record<string, string>) =>
      Promise.resolve({ data: rpcResult, error: null }) as Promise<TransitRpcResult>,
  };
}

function makeSupabaseRpcThrows(evidence: Evidence | null) {
  return {
    from: (_table: string) => ({
      select: (_cols: string) => ({
        eq: (_col: string, _val: string) => ({
          eq: (_col2: string, _val2: string) => ({
            maybeSingle: () => Promise.resolve({ data: evidence }),
          }),
        }),
      }),
    }),
    rpc: (_name: string, _params: Record<string, string>) =>
      Promise.reject(new Error("RPC connection error")),
  };
}

const ORG_ID = "org-11111111-1111-1111-1111-111111111111";
const EV_ID = "ev-33333333-3333-3333-3333-333333333333";
const PLANNED_EVIDENCE: Evidence = { linked_set_id: "SET-abc-planned" };
const IN_TRANSIT_EVIDENCE: Evidence = { linked_set_id: "SET-abc-in-transit" };

// ── Tests ─────────────────────────────────────────────────────────────────────

Deno.test("lacre on planned execution → start_transit RPC called → transitStarted=true", async () => {
  const supabase = makeSupabaseWithEvidence(PLANNED_EVIDENCE, true);
  const { transitStarted } = await handleCategoryAutoStart(supabase, "lacre", EV_ID, ORG_ID);
  assertEquals(transitStarted, true);
});

Deno.test("chk_saida on planned execution → transitStarted=true", async () => {
  const supabase = makeSupabaseWithEvidence(PLANNED_EVIDENCE, true);
  const { transitStarted } = await handleCategoryAutoStart(supabase, "chk_saida", EV_ID, ORG_ID);
  assertEquals(transitStarted, true);
});

Deno.test("carregamento on planned execution → transitStarted=true", async () => {
  const supabase = makeSupabaseWithEvidence(PLANNED_EVIDENCE, true);
  const { transitStarted } = await handleCategoryAutoStart(supabase, "carregamento", EV_ID, ORG_ID);
  assertEquals(transitStarted, true);
});

Deno.test("lacre on inTransit execution → RPC returns true (idempotent, first-wins) → no error", async () => {
  // RPC start_transit_for_execution returns true for already-inTransit (idempotent)
  const supabase = makeSupabaseWithEvidence(IN_TRANSIT_EVIDENCE, true);
  const { transitStarted } = await handleCategoryAutoStart(supabase, "lacre", EV_ID, ORG_ID);
  assertEquals(transitStarted, true); // idempotent — no double transition in DB
});

Deno.test("estado category → NOT a trigger → transitStarted=false (non-trigger category)", async () => {
  const supabase = makeSupabaseWithEvidence(PLANNED_EVIDENCE, true);
  const { transitStarted } = await handleCategoryAutoStart(supabase, "estado", EV_ID, ORG_ID);
  assertEquals(transitStarted, false);
});

Deno.test("doc category → NOT a trigger → transitStarted=false", async () => {
  const supabase = makeSupabaseWithEvidence(PLANNED_EVIDENCE, true);
  const { transitStarted } = await handleCategoryAutoStart(supabase, "doc", EV_ID, ORG_ID);
  assertEquals(transitStarted, false);
});

Deno.test("lacre on orphan evidence (no linked_set_id) → no RPC call → transitStarted=false", async () => {
  const supabase = makeSupabaseWithEvidence({ linked_set_id: null }, true);
  const { transitStarted } = await handleCategoryAutoStart(supabase, "lacre", EV_ID, ORG_ID);
  assertEquals(transitStarted, false); // no set to start transit on
});

Deno.test("lacre RPC throws → category NOT failed (non-blocking), transitStarted=false", async () => {
  const supabase = makeSupabaseRpcThrows(PLANNED_EVIDENCE);
  // Must not throw — category save must never fail because of auto-start failure
  const { transitStarted, categoryError } = await handleCategoryAutoStart(
    supabase, "lacre", EV_ID, ORG_ID,
  );
  assertEquals(transitStarted, false); // transit failed silently
  assertEquals(categoryError, false); // category was saved (not affected)
});

// ── TRANSIT_TRIGGER_CATEGORIES set coverage ───────────────────────────────────

Deno.test("TRANSIT_TRIGGER_CATEGORIES contains exactly lacre, chk_saida, carregamento", () => {
  assertEquals(TRANSIT_TRIGGER_CATEGORIES.has("lacre"), true);
  assertEquals(TRANSIT_TRIGGER_CATEGORIES.has("chk_saida"), true);
  assertEquals(TRANSIT_TRIGGER_CATEGORIES.has("carregamento"), true);
  assertEquals(TRANSIT_TRIGGER_CATEGORIES.has("checklist_saida"), false); // key is chk_saida
  assertEquals(TRANSIT_TRIGGER_CATEGORIES.has("estado"), false);
  assertEquals(TRANSIT_TRIGGER_CATEGORIES.has("doc"), false);
  assertEquals(TRANSIT_TRIGGER_CATEGORIES.size, 3);
});
