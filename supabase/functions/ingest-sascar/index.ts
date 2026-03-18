/**
 * Edge Function: ingest-sascar
 *
 * Anti-Corruption Layer for Sascar GPS hardware.
 *
 * Pipeline:
 *   1. Authenticate via API key → resolve organization_id (INV-17: Zero-Trust Tenant Derivation)
 *   2. Seal raw payload with SHA-256 → INSERT raw_telemetry_payloads (INV-16)
 *   3. Parse + validate Sascar schema
 *   4. Classify integrity flag (chaos tolerance)
 *   5. INSERT canonical_facts (FK to raw payload — mandatory)
 *   6. Return {status, canonical_fact_id}
 *
 * Idempotency: ON CONFLICT DO NOTHING on canonical_facts
 * (UNIQUE: organization_id + device_id + gps_timestamp + source_adapter)
 */

import { createClient } from "jsr:@supabase/supabase-js@2";
import * as Sentry from "npm:@sentry/deno@^8";

// ── Sentry init (no-op if SENTRY_DSN is not set) ───────────────────────────
Sentry.init({
  dsn: Deno.env.get("SENTRY_DSN") ?? "",
  environment: Deno.env.get("APP_ENV") ?? "dev",
  tracesSampleRate: 0.2,
});

// ── Types ──────────────────────────────────────────────────────────────────

/** Raw payload shape expected from Sascar hardware. */
interface SascarPayload {
  device_serial: string; // hardware identifier
  event_time: string; // ISO8601 UTC or epoch ms (string)
  latitude: number;
  longitude: number;
  speed_kmh: number; // km/h — converted to cm/s in normalisation
  heading?: number; // 0–359 degrees
  accuracy_meters?: number;
  vehicle_id?: string; // optional provider-side mapping
}

/** Result shape returned to the caller. */
interface IngestResult {
  status: "accepted" | "duplicate" | "rejected";
  canonical_fact_id?: string;
  raw_payload_id?: string;
  integrity_flag?: string;
  reason?: string;
}

// ── Constants ──────────────────────────────────────────────────────────────

const SOURCE_ADAPTER = "SASCAR_V1";
const LATE_ARRIVAL_THRESHOLD_MS = 4 * 60 * 60 * 1000; // 4 hours
const FUTURE_TIMESTAMP_TOLERANCE_MS = 5 * 60 * 1000; // 5 minutes grace
const MAX_SPEED_CMS = 200 * 100 / 3.6; // 200 km/h in cm/s
const MAX_ACCURACY_METERS = 100;

// ── Helpers ────────────────────────────────────────────────────────────────

async function sha256Hex(input: string): Promise<string> {
  const encoded = new TextEncoder().encode(input);
  const hashBuffer = await crypto.subtle.digest("SHA-256", encoded);
  return Array.from(new Uint8Array(hashBuffer))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function classifyIntegrity(
  gpsTimestamp: Date,
  receivedAt: Date,
  lat: number,
  lng: number,
  speedCms: number | null,
  accuracyMeters: number | null,
): string {
  // Null Island — firmware default when satellite lock is lost
  if (lat === 0.0 && lng === 0.0) return "NULL_ISLAND";

  const latencyMs = receivedAt.getTime() - gpsTimestamp.getTime();

  // Future timestamp (device clock drift or spoofing)
  if (latencyMs < -FUTURE_TIMESTAMP_TOLERANCE_MS) return "FUTURE_TIMESTAMP";

  // Late arrival
  if (latencyMs > LATE_ARRIVAL_THRESHOLD_MS) return "LATE_ARRIVAL";

  // Kinematic anomaly — physically impossible speed
  if (speedCms !== null && speedCms > MAX_SPEED_CMS) return "KINEMATIC_ANOMALY";

  // Low accuracy
  if (accuracyMeters !== null && accuracyMeters > MAX_ACCURACY_METERS) {
    return "LOW_ACCURACY";
  }

  return "OK";
}

function parseSascarTimestamp(raw: string): Date | null {
  // Support both ISO8601 and epoch milliseconds
  const asNumber = Number(raw);
  if (!isNaN(asNumber) && raw.length >= 10) {
    return new Date(asNumber);
  }
  const parsed = new Date(raw);
  return isNaN(parsed.getTime()) ? null : parsed;
}

// ── Main Handler ───────────────────────────────────────────────────────────

Deno.serve(async (req: Request): Promise<Response> => {
  return await Sentry.withScope(async () => {
    try {
      return await handleRequest(req);
    } catch (err) {
      Sentry.captureException(err);
      console.error("[ingest-sascar] Unhandled error:", err);
      return Response.json({ error: "Internal server error" }, { status: 500 });
    }
  });
});

async function handleRequest(req: Request): Promise<Response> {
  // ── CORS preflight ──────────────────────────────────────────────────────
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST",
        "Access-Control-Allow-Headers": "Authorization, Content-Type",
      },
    });
  }

  if (req.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, { status: 405 });
  }

  // ── Supabase client (service role — bypasses RLS for writes) ────────────
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // ── Step 1: Authenticate API key → resolve organization_id (INV-17) ─────
  const authHeader = req.headers.get("Authorization") ?? "";
  const rawKey = authHeader.replace(/^Bearer\s+/i, "").trim();

  if (!rawKey) {
    return Response.json({ error: "Missing Authorization header" }, {
      status: 401,
    });
  }

  const keyHash = await sha256Hex(rawKey);

  const { data: keyRow, error: keyError } = await supabase
    .from("provider_api_keys")
    .select("organization_id")
    .eq("api_key_hash", keyHash)
    .eq("is_active", true)
    .eq("provider_name", "SASCAR")
    .maybeSingle();

  if (keyError || !keyRow) {
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  }

  const organizationId: string = keyRow.organization_id;

  // ── Step 2: Read raw body — seal BEFORE any parsing ─────────────────────
  let rawBodyText: string;
  try {
    rawBodyText = await req.text();
  } catch {
    return Response.json({ error: "Failed to read request body" }, {
      status: 400,
    });
  }

  const payloadHash = await sha256Hex(rawBodyText);
  const receivedAtUtc = new Date().toISOString();

  // ── Step 3: Parse Sascar JSON ────────────────────────────────────────────
  let payload: SascarPayload;
  try {
    payload = JSON.parse(rawBodyText) as SascarPayload;
  } catch {
    return Response.json(
      { status: "rejected", reason: "Invalid JSON" } as IngestResult,
      { status: 422 },
    );
  }

  // Schema validation — required fields
  if (
    typeof payload.device_serial !== "string" ||
    !payload.device_serial ||
    typeof payload.event_time !== "string" ||
    !payload.event_time ||
    typeof payload.latitude !== "number" ||
    typeof payload.longitude !== "number" ||
    typeof payload.speed_kmh !== "number"
  ) {
    return Response.json(
      {
        status: "rejected",
        reason:
          "Missing required fields: device_serial, event_time, latitude, longitude, speed_kmh",
      } as IngestResult,
      { status: 422 },
    );
  }

  // Coordinate range validation
  if (
    payload.latitude < -90 ||
    payload.latitude > 90 ||
    payload.longitude < -180 ||
    payload.longitude > 180
  ) {
    return Response.json(
      { status: "rejected", reason: "Coordinates out of range" } as IngestResult,
      { status: 422 },
    );
  }

  const gpsTimestamp = parseSascarTimestamp(payload.event_time);
  if (!gpsTimestamp) {
    return Response.json(
      {
        status: "rejected",
        reason: `Unparseable event_time: ${payload.event_time}`,
      } as IngestResult,
      { status: 422 },
    );
  }

  // Convert speed: km/h → cm/s (integer, INV-2)
  const speedCms = Math.round((payload.speed_kmh * 1000) / 36);
  const headingDegrees = payload.heading !== undefined
    ? Math.round(payload.heading) % 360
    : null;
  const accuracyMeters = payload.accuracy_meters ?? null;

  // ── Step 4: Classify integrity flag ─────────────────────────────────────
  const integrityFlag = classifyIntegrity(
    gpsTimestamp,
    new Date(receivedAtUtc),
    payload.latitude,
    payload.longitude,
    speedCms,
    accuracyMeters,
  );

  // ── Step 5: INSERT raw_telemetry_payloads (commit before canonical) ──────
  const { data: rawRow, error: rawError } = await supabase
    .from("raw_telemetry_payloads")
    .insert({
      organization_id: organizationId,
      provider_name: "SASCAR",
      device_id: payload.device_serial,
      received_at_utc: receivedAtUtc,
      raw_payload: JSON.parse(rawBodyText),
      payload_hash: payloadHash,
    })
    .select("id")
    .single();

  if (rawError || !rawRow) {
    console.error("raw_telemetry_payloads insert error:", rawError);
    return Response.json({ error: "Internal error storing raw payload" }, {
      status: 500,
    });
  }

  const rawPayloadId: string = rawRow.id;

  // ── Step 6: INSERT canonical_facts (ON CONFLICT = idempotent) ───────────
  const { data: canonicalRow, error: canonicalError } = await supabase
    .from("canonical_facts")
    .upsert(
      {
        organization_id: organizationId,
        raw_payload_id: rawPayloadId,
        asset_id: null, // asset mapping happens downstream via device_id lookup
        device_id: payload.device_serial,
        gps_timestamp: gpsTimestamp.toISOString(),
        received_at_utc: receivedAtUtc,
        lat: payload.latitude,
        lng: payload.longitude,
        speed_cms: speedCms,
        heading_degrees: headingDegrees,
        accuracy_meters: accuracyMeters,
        source_adapter: SOURCE_ADAPTER,
        integrity_flag: integrityFlag,
      },
      {
        onConflict: "organization_id,device_id,gps_timestamp,source_adapter",
        ignoreDuplicates: true, // idempotent — C3 chaos scenario
      },
    )
    .select("id")
    .maybeSingle();

  if (canonicalError) {
    console.error("canonical_facts insert error:", canonicalError);
    return Response.json({ error: "Internal error storing canonical fact" }, {
      status: 500,
    });
  }

  // If upsert returned no row, the event was a duplicate (absorbed silently)
  if (!canonicalRow) {
    return Response.json(
      {
        status: "duplicate",
        raw_payload_id: rawPayloadId,
        integrity_flag: integrityFlag,
      } as IngestResult,
      { status: 200 }, // 200 not 409 — idempotent, no information leakage
    );
  }

  // ── Step 7: Respond ──────────────────────────────────────────────────────
  return Response.json(
    {
      status: "accepted",
      canonical_fact_id: canonicalRow.id,
      raw_payload_id: rawPayloadId,
      integrity_flag: integrityFlag,
    } as IngestResult,
    { status: 200 },
  );
}
