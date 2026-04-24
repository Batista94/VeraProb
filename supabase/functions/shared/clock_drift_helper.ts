/**
 * Clock Drift Helper (INV-6, INV-15, INV-18)
 *
 * Server timestamp MUST be captured at handler entry — not at I/O completion —
 * to minimize measurement noise from download/processing latency.
 * The computed value is sealed at ingest; replay reads clock_drift_seconds,
 * never recomputes (INV-15 deterministic replay).
 */

/** Signed drift in seconds: positive = device behind server, negative = device ahead. */
export function calculateClockDrift(
  messageUnixTs: number,
  serverUnixTs: number,
): number {
  return Math.round(serverUnixTs - messageUnixTs);
}

/** Threshold above which drift signals potential timestamp manipulation. */
export const FRAUD_DRIFT_THRESHOLD_S = 300; // 5 minutes
