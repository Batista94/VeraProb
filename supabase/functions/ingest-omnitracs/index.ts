/**
 * Edge Function: ingest-omnitracs
 *
 * Anti-Corruption Layer for Omnitracs GPS hardware.
 *
 * Pipeline identical to ingest-sascar; differs only in:
 *   - SOURCE_ADAPTER = "OMNITRACS_V2"
 *   - provider_name = "OMNITRACS" (for API key lookup)
 *   - OmnitracPayload schema (different field names from Sascar)
 *
 * See ingest-sascar/index.ts for full pipeline documentation.
 */

import { createClient } from "jsr:@supabase/supabase-js@2";
import * as Sentry from "npm:@sentry/deno@^8";
import { classifyIntegrity } from "../shared/classify_integrity.ts";
import { signPayload } from "../shared/hmac_signer.ts";
import { sha256Hex } from "../shared/sha256_hex.ts";

// ── Sentry init (no-op if SENTRY_DSN is not set) ───────────────────────────
Sentry.init({
  dsn: Deno.env.get("SENTRY_DSN") ?? "",
  environment: Deno.env.get("APP_ENV") ?? "dev",
  tracesSampleRate: 0.2,
});

// ── Types ──────────────────────────────────────────────────────────────────

/** Raw payload shape expected from Omnitracs hardware. */
interface OmnitracPayload {
  unitId: string; // hardware identifier (Omnitracs uses camelCase)
  utcTime: string; // ISO8601 UTC
  lat: number;
  lon: number;
  speedMph: number; // mph — converted to cm/s
  directionDeg?: number; // 0–359 degrees
  hdop?: number; // Horizontal Dilution of Precision (lower = better)
  gpsQuality?: number; // 0–3 scale; < 1 = unreliable
}

interface IngestResult {
  status: "accepted" | "duplicate" | "rejected";
  canonical_fact_id?: string;
  raw_payload_id?: string;
  integrity_flag?: string;
  reason?: string;
}

// ── Constants ──────────────────────────────────────────────────────────────

const SOURCE_ADAPTER = "OMNITRACS_V2";
const DEFAULT_MAX_SPEED_KMH = 200; // physics floor — overridden by org capabilities
const MAX_HDOP = 5.0;

// ── Main Handler ───────────────────────────────────────────────────────────

Deno.serve(async (req: Request): Promise<Response> => {
  return await Sentry.withScope(async () => {
    try {
      return await handleRequest(req);
    } catch (err) {
      Sentry.captureException(err);
      console.error("[ingest-omnitracs] Unhandled error:", err);
      return Response.json({ error: "Internal server error" }, { status: 500 });
    }
  });
});

async function handleRequest(req: Request): Promise<Response> {
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

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // ── Step 1: Auth → organization_id (INV-17) ──────────────────────────────
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
    .eq("provider_name", "OMNITRACS")
    .maybeSingle();

  if (keyError || !keyRow) {
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  }

  const organizationId: string = keyRow.organization_id;

  // ── Step 1b: Load org capabilities for forensic thresholds (INV-14) ──────
  const { data: orgRow } = await supabase
    .from("organizations")
    .select("capabilities")
    .eq("id", organizationId)
    .maybeSingle();

  const maxSpeedKmh: number =
    (orgRow?.capabilities as Record<string, unknown> | null)
      ?.max_kinematic_speed_kmh as number ?? DEFAULT_MAX_SPEED_KMH;
  // Physical Metric - Double Required
  const maxSpeedCms: number = maxSpeedKmh * 100 / 3.6;

  // ── Step 2: Seal raw payload ─────────────────────────────────────────────
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

  // ── Step 3: Parse Omnitracs JSON ─────────────────────────────────────────
  let payload: OmnitracPayload;
  try {
    payload = JSON.parse(rawBodyText) as OmnitracPayload;
  } catch {
    return Response.json(
      { status: "rejected", reason: "Invalid JSON" } as IngestResult,
      { status: 422 },
    );
  }

  // C4: INV-6 — utcTime (device clock) REQUIRED. Missing → alert operator immediately.
  if (typeof payload.utcTime !== "string" || !payload.utcTime) {
    await supabase.from("ingestion_alerts").insert({
      organization_id: organizationId,
      device_serial: typeof payload.unitId === "string" ? payload.unitId : null,
      alert_type: "INGESTION_INTEGRITY_ERROR",
      detail: "utcTime absent — clock source unknown; INV-6 violation",
      created_at_utc: new Date().toISOString(),
    });
    return Response.json(
      { status: "rejected", reason: "missing_utcTime" } as IngestResult,
      { status: 422 },
    );
  }

  // Schema validation — remaining required fields
  if (
    typeof payload.unitId !== "string" ||
    !payload.unitId ||
    typeof payload.lat !== "number" ||
    typeof payload.lon !== "number" ||
    typeof payload.speedMph !== "number"
  ) {
    return Response.json(
      {
        status: "rejected",
        reason: "Missing required fields: unitId, lat, lon, speedMph",
      } as IngestResult,
      { status: 422 },
    );
  }

  if (
    payload.lat < -90 ||
    payload.lat > 90 ||
    payload.lon < -180 ||
    payload.lon > 180
  ) {
    return Response.json(
      { status: "rejected", reason: "Coordinates out of range" } as IngestResult,
      { status: 422 },
    );
  }

  const gpsTimestamp = new Date(payload.utcTime);
  if (isNaN(gpsTimestamp.getTime())) {
    return Response.json(
      {
        status: "rejected",
        reason: `Unparseable utcTime: ${payload.utcTime}`,
      } as IngestResult,
      { status: 422 },
    );
  }

  // Convert speed: mph → cm/s (integer, INV-2)
  // 1 mph = 44.704 cm/s
  const speedCms = Math.round(payload.speedMph * 44.704);
  const headingDegrees = payload.directionDeg !== undefined
    ? Math.round(payload.directionDeg) % 360
    : null;
  const hdop = payload.hdop ?? null;

  // ── Step 4: Classify integrity ───────────────────────────────────────────
  const integrityFlag = classifyIntegrity(
    gpsTimestamp,
    new Date(receivedAtUtc),
    payload.lat,
    payload.lon,
    speedCms,
    hdop,
    MAX_HDOP,
    maxSpeedCms,
  );

  // ── Step 5: INSERT raw_telemetry_payloads ────────────────────────────────
  const { data: rawRow, error: rawError } = await supabase
    .from("raw_telemetry_payloads")
    .insert({
      organization_id: organizationId,
      provider_name: "OMNITRACS",
      device_id: payload.unitId,
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

  // ── Step 6: INSERT canonical_facts (idempotent) ──────────────────────────
  const canonicalPayload = {
    organization_id: organizationId,
    raw_payload_id: rawPayloadId,
    asset_id: null,
    device_id: payload.unitId,
    gps_timestamp: gpsTimestamp.toISOString(),
    received_at_utc: receivedAtUtc,
    lat: payload.lat,
    lng: payload.lon,
    speed_cms: speedCms,
    heading_degrees: headingDegrees,
    accuracy_meters: null,
    source_adapter: SOURCE_ADAPTER,
    integrity_flag: integrityFlag,
  };
  const payloadHmac = await signPayload(canonicalPayload); // INV-31

  const { data: canonicalRow, error: canonicalError } = await supabase
    .from("canonical_facts")
    .upsert(
      { ...canonicalPayload, payload_hmac: payloadHmac },
      {
        onConflict: "organization_id,device_id,gps_timestamp,source_adapter",
        ignoreDuplicates: true,
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

  if (!canonicalRow) {
    return Response.json(
      {
        status: "duplicate",
        raw_payload_id: rawPayloadId,
        integrity_flag: integrityFlag,
      } as IngestResult,
      { status: 200 },
    );
  }

  // ── Kinematic alert (INV-18: fire-and-forget, non-blocking) ──────────────
  if (integrityFlag === "KINEMATIC_ANOMALY") {
    supabase.from("ingestion_alerts").insert({
      organization_id: organizationId,
      device_serial: payload.unitId,
      alert_type: "KINEMATIC_ANOMALY",
      detail: `speed_cms=${speedCms} exceeds ${Math.round(maxSpeedCms)} cm/s (${maxSpeedKmh} km/h cap). INV-18.`,
      created_at_utc: new Date().toISOString(),
    }).catch((e) => console.warn("[ingest-omnitracs] kinematic_alert:", e));
  }

  // C1: waitUntil — GPS transition RPC must complete even after response is sent.
  EdgeRuntime.waitUntil(
    supabase.rpc("process_gps_for_execution_transitions", {
      p_org_id: organizationId,
      p_device_serial: payload.unitId,
      p_lat: payload.lat,
      p_lng: payload.lon,
      p_device_ts: gpsTimestamp.toISOString(),
    }).catch((e) => console.warn("[ingest-omnitracs] gps_transition:", e)),
  );

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
