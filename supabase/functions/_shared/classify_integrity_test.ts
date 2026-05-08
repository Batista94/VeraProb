import { assertEquals } from "jsr:@std/assert";
import {
  classifyIntegrity,
  FUTURE_TIMESTAMP_TOLERANCE_MS,
  LATE_ARRIVAL_THRESHOLD_MS,
} from "./classify_integrity.ts";

// 200 km/h default org cap in cm/s (200 * 100 / 3.6)
const DEFAULT_MAX_CMS = 5556;

Deno.test("OK — normal telemetry within all thresholds", () => {
  const now = new Date();
  assertEquals(
    classifyIntegrity(
      new Date(now.getTime() - 30_000), // 30s ago
      now,
      -23.5, -46.6,
      1000,  // ~36 km/h
      10,    // quality within limit
      100,
      DEFAULT_MAX_CMS,
    ),
    "OK",
  );
});

Deno.test("NULL_ISLAND — short-circuits before speed/quality checks", () => {
  const now = new Date();
  // Speed and quality both anomalous — NULL_ISLAND must win (precedence test)
  assertEquals(
    classifyIntegrity(
      new Date(now.getTime() - 30_000),
      now,
      0.0, 0.0,
      DEFAULT_MAX_CMS + 1, // would be KINEMATIC_ANOMALY
      200,                  // would be LOW_ACCURACY
      100,
      DEFAULT_MAX_CMS,
    ),
    "NULL_ISLAND",
  );
});

Deno.test("FUTURE_TIMESTAMP — device_ts more than 5 min ahead of receivedAt", () => {
  const now = new Date();
  assertEquals(
    classifyIntegrity(
      new Date(now.getTime() + FUTURE_TIMESTAMP_TOLERANCE_MS + 1_000), // 6 min future
      now,
      -23.5, -46.6,
      null, null, null,
      DEFAULT_MAX_CMS,
    ),
    "FUTURE_TIMESTAMP",
  );
});

Deno.test("OK — device_ts exactly at 5 min boundary (exclusive: not FUTURE_TIMESTAMP)", () => {
  const now = new Date();
  // latencyMs = -FUTURE_TIMESTAMP_TOLERANCE_MS; condition is strictly < so this is OK
  assertEquals(
    classifyIntegrity(
      new Date(now.getTime() + FUTURE_TIMESTAMP_TOLERANCE_MS),
      now,
      -23.5, -46.6,
      null, null, null,
      DEFAULT_MAX_CMS,
    ),
    "OK",
  );
});

Deno.test("LATE_ARRIVAL — device_ts more than 4 h before receivedAt", () => {
  const now = new Date();
  assertEquals(
    classifyIntegrity(
      new Date(now.getTime() - LATE_ARRIVAL_THRESHOLD_MS - 1_000), // 4h + 1s
      now,
      -23.5, -46.6,
      null, null, null,
      DEFAULT_MAX_CMS,
    ),
    "LATE_ARRIVAL",
  );
});

Deno.test("KINEMATIC_ANOMALY — speed exceeds per-org threshold", () => {
  const orgCapCms = 3333; // 120 km/h org cap
  const now = new Date();
  assertEquals(
    classifyIntegrity(
      new Date(now.getTime() - 30_000),
      now,
      -23.5, -46.6,
      orgCapCms + 1, // one over
      null, null,
      orgCapCms,
    ),
    "KINEMATIC_ANOMALY",
  );
});

Deno.test("OK — speed exactly at threshold (strictly greater-than required, not >=)", () => {
  const orgCapCms = 3333;
  const now = new Date();
  assertEquals(
    classifyIntegrity(
      new Date(now.getTime() - 30_000),
      now,
      -23.5, -46.6,
      orgCapCms, // equal — must be OK
      null, null,
      orgCapCms,
    ),
    "OK",
  );
});

Deno.test("LOW_ACCURACY — quality metric exceeds max (Sascar: accuracyMeters > 100)", () => {
  const now = new Date();
  assertEquals(
    classifyIntegrity(
      new Date(now.getTime() - 30_000),
      now,
      -23.5, -46.6,
      1000,
      101,  // accuracyMeters = 101 > 100
      100,  // MAX_ACCURACY_METERS
      DEFAULT_MAX_CMS,
    ),
    "LOW_ACCURACY",
  );
});

Deno.test("OK — quality metric null (provider omits field; check skipped)", () => {
  const now = new Date();
  assertEquals(
    classifyIntegrity(
      new Date(now.getTime() - 30_000),
      now,
      -23.5, -46.6,
      1000,
      null, // omitted by provider
      100,
      DEFAULT_MAX_CMS,
    ),
    "OK",
  );
});

Deno.test("KINEMATIC_ANOMALY — takes precedence over LOW_ACCURACY", () => {
  const orgCapCms = 3333;
  const now = new Date();
  assertEquals(
    classifyIntegrity(
      new Date(now.getTime() - 30_000),
      now,
      -23.5, -46.6,
      orgCapCms + 1, // speed anomaly
      200,           // also low accuracy (HDOP > 5)
      5.0,
      orgCapCms,
    ),
    "KINEMATIC_ANOMALY",
  );
});
