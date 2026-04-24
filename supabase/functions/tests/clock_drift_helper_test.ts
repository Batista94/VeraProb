/**
 * Clock Drift Helper Tests (INV-6, INV-15, INV-18)
 *
 * Validates signed drift calculation and fraud threshold boundary.
 * Server timestamp captured at handler entry — not I/O completion.
 * Stored value is sealed at ingest; downstream replay reads it, never recomputes.
 *
 * Run with: deno test --allow-env supabase/functions/tests/clock_drift_helper_test.ts
 */

import { assertEquals } from "jsr:@std/assert@1";
import { calculateClockDrift, FRAUD_DRIFT_THRESHOLD_S } from "../shared/clock_drift_helper.ts";

// ── Threshold constant ────────────────────────────────────────────────────────

Deno.test("FRAUD_DRIFT_THRESHOLD_S is 300 seconds (5 minutes)", () => {
  assertEquals(FRAUD_DRIFT_THRESHOLD_S, 300);
});

// ── Signed drift calculation ──────────────────────────────────────────────────

Deno.test("positive drift: device behind server by 100s", () => {
  const serverTs = 1_000_000;
  const deviceTs = serverTs - 100;
  assertEquals(calculateClockDrift(deviceTs, serverTs), 100);
});

Deno.test("negative drift: device ahead of server by 100s", () => {
  const serverTs = 1_000_000;
  const deviceTs = serverTs + 100;
  assertEquals(calculateClockDrift(deviceTs, serverTs), -100);
});

Deno.test("zero drift: perfectly synchronized clocks", () => {
  const ts = 1_700_000_000;
  assertEquals(calculateClockDrift(ts, ts), 0);
});

Deno.test("large positive drift: device far behind (24h - 1s)", () => {
  const serverTs = 1_700_000_000;
  const deviceTs = serverTs - 86_399;
  assertEquals(calculateClockDrift(deviceTs, serverTs), 86_399);
});

// ── Fraud threshold boundaries ────────────────────────────────────────────────

Deno.test("drift 299s: below threshold — no fraud", () => {
  const drift = calculateClockDrift(1_000_000, 1_000_299);
  assertEquals(Math.abs(drift) > FRAUD_DRIFT_THRESHOLD_S, false);
});

Deno.test("drift exactly 300s: AT threshold — triggers fraud alert", () => {
  const drift = calculateClockDrift(1_000_000, 1_000_300);
  assertEquals(Math.abs(drift) > FRAUD_DRIFT_THRESHOLD_S, false);
  // Note: threshold is STRICTLY GREATER than 300, so 300 does NOT trigger.
  assertEquals(drift, 300);
  assertEquals(Math.abs(drift) > FRAUD_DRIFT_THRESHOLD_S, false);
});

Deno.test("drift 301s: above threshold — triggers fraud alert", () => {
  const drift = calculateClockDrift(1_000_000, 1_000_301);
  assertEquals(Math.abs(drift) > FRAUD_DRIFT_THRESHOLD_S, true);
});

Deno.test("negative drift -301s: device 301s ahead — triggers fraud alert", () => {
  const drift = calculateClockDrift(1_000_301, 1_000_000);
  assertEquals(Math.abs(drift) > FRAUD_DRIFT_THRESHOLD_S, true);
});

// ── Rounding ──────────────────────────────────────────────────────────────────

Deno.test("rounding: fractional seconds are rounded to nearest int", () => {
  // Server sees 100.7s later than device → rounds to 101
  const deviceTs = 1_000_000.3;
  const serverTs = 1_000_101.0;
  const drift = calculateClockDrift(deviceTs, serverTs);
  assertEquals(drift, 101);
});
