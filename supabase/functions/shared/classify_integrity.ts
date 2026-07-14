// Shared integrity classifier for GPS ingest functions.
// Used by ingest-sascar (qualityMetric=accuracyMeters, maxQualityMetric=100)
// and ingest-omnitracs (qualityMetric=hdop, maxQualityMetric=5.0).

export const LATE_ARRIVAL_THRESHOLD_MS = 4 * 60 * 60 * 1000; // 4 hours
export const FUTURE_TIMESTAMP_TOLERANCE_MS = 5 * 60 * 1000; // 5 minutes grace

export function classifyIntegrity(
  gpsTimestamp: Date,
  receivedAt: Date,
  lat: number,
  lng: number,
  speedCms: number | null,
  qualityMetric: number | null,
  maxQualityMetric: number | null,
  maxSpeedCms: number,
): string {
  if (lat === 0.0 && lng === 0.0) return "NULL_ISLAND";

  const latencyMs = receivedAt.getTime() - gpsTimestamp.getTime();

  if (latencyMs < -FUTURE_TIMESTAMP_TOLERANCE_MS) return "FUTURE_TIMESTAMP";
  if (latencyMs > LATE_ARRIVAL_THRESHOLD_MS) return "LATE_ARRIVAL";

  if (speedCms !== null && speedCms > maxSpeedCms) return "KINEMATIC_ANOMALY";

  if (
    qualityMetric !== null && maxQualityMetric !== null &&
    qualityMetric > maxQualityMetric
  ) {
    return "LOW_ACCURACY";
  }

  return "OK";
}
