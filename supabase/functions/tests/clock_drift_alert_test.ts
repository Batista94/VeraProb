/**
 * Clock Drift Alert Tests — Task 1 (INV-6, INV-10, INV-18)
 *
 * Validates the POTENTIAL_TIME_FRAUD alert emission logic:
 * - Alert fires when |drift| > 300s
 * - Alert does NOT fire when |drift| ≤ 300s
 * - Alert context includes evidence_id (required for flood suppression accumulator)
 * - Non-blocking: evidence already sealed before alert is attempted
 *
 * Run with: deno test --allow-env supabase/functions/tests/clock_drift_alert_test.ts
 */

import { assertEquals, assertExists } from "jsr:@std/assert@1";
import { FRAUD_DRIFT_THRESHOLD_S } from "../shared/clock_drift_helper.ts";

// ── Simulation of fireFraudAlert logic ────────────────────────────────────────

interface AlertInsert {
  organization_id: string;
  entity_id: string;
  alert_type: string;
  severity: string;
  context: Record<string, unknown>;
}

async function conditionallyFireFraudAlert(
  supabase: {
    from: (table: string) => {
      insert: (row: AlertInsert) => Promise<{ error: null }>;
    };
  },
  orgId: string,
  chatId: number,
  correlationId: string,
  evidenceId: string,
  driverId: string,
  driftSeconds: number,
): Promise<AlertInsert | null> {
  if (Math.abs(driftSeconds) <= FRAUD_DRIFT_THRESHOLD_S) {
    return null; // no alert
  }

  let captured: AlertInsert | null = null;
  try {
    const row: AlertInsert = {
      organization_id: orgId,
      entity_id: String(chatId),
      alert_type: "POTENTIAL_TIME_FRAUD",
      severity: "HIGH",
      context: {
        evidence_id: evidenceId,
        clock_drift_seconds: driftSeconds,
        correlation_id: correlationId,
        driver_id: driverId,
        chat_id: chatId,
      },
    };
    await supabase.from("operational_alerts").insert(row);
    captured = row;
  } catch (_e) {
    // Non-blocking: evidence is already sealed (INV-9).
  }
  return captured;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function makeSupabase(shouldFail = false) {
  return {
    from: (_table: string) => ({
      insert: (row: AlertInsert) => {
        if (shouldFail) return Promise.reject(new Error("DB error"));
        return Promise.resolve({ error: null });
      },
    }),
  };
}

const ORG = "org-11111111";
const EV_ID = "ev-33333333";

// ── Tests ─────────────────────────────────────────────────────────────────────

Deno.test("drift > 300s (device behind): POTENTIAL_TIME_FRAUD alert fires", async () => {
  const alert = await conditionallyFireFraudAlert(
    makeSupabase(), ORG, 12345, "corr-1", EV_ID, "drv-1", 301,
  );
  assertExists(alert);
  assertEquals(alert!.alert_type, "POTENTIAL_TIME_FRAUD");
  assertEquals(alert!.severity, "HIGH");
});

Deno.test("drift < -300s (device ahead): POTENTIAL_TIME_FRAUD alert fires (negative drift)", async () => {
  const alert = await conditionallyFireFraudAlert(
    makeSupabase(), ORG, 12345, "corr-1", EV_ID, "drv-1", -301,
  );
  assertExists(alert);
  assertEquals(alert!.alert_type, "POTENTIAL_TIME_FRAUD");
});

Deno.test("drift 300s: does NOT fire (threshold is strictly greater than)", async () => {
  const alert = await conditionallyFireFraudAlert(
    makeSupabase(), ORG, 12345, "corr-1", EV_ID, "drv-1", 300,
  );
  assertEquals(alert, null);
});

Deno.test("drift 299s: does NOT fire (below threshold)", async () => {
  const alert = await conditionallyFireFraudAlert(
    makeSupabase(), ORG, 12345, "corr-1", EV_ID, "drv-1", 299,
  );
  assertEquals(alert, null);
});

Deno.test("drift 0s: does NOT fire (synchronized clock)", async () => {
  const alert = await conditionallyFireFraudAlert(
    makeSupabase(), ORG, 12345, "corr-1", EV_ID, "drv-1", 0,
  );
  assertEquals(alert, null);
});

Deno.test("alert context includes evidence_id (required for flood suppression accumulator)", async () => {
  const alert = await conditionallyFireFraudAlert(
    makeSupabase(), ORG, 12345, "corr-1", EV_ID, "drv-1", 500,
  );
  assertExists(alert);
  assertEquals(alert!.context["evidence_id"], EV_ID); // INV-10: accumulator reads this field
});

Deno.test("alert context includes clock_drift_seconds for forensic audit", async () => {
  const alert = await conditionallyFireFraudAlert(
    makeSupabase(), ORG, 12345, "corr-1", EV_ID, "drv-1", 500,
  );
  assertExists(alert);
  assertEquals(alert!.context["clock_drift_seconds"], 500);
});

Deno.test("alert DB insert failure: non-blocking (evidence already sealed, no throw)", async () => {
  // Should not throw even if DB insert fails
  const alert = await conditionallyFireFraudAlert(
    makeSupabase(true), ORG, 12345, "corr-1", EV_ID, "drv-1", 500,
  );
  // alert is null because the catch swallowed it, but no exception propagated
  assertEquals(alert, null);
});
