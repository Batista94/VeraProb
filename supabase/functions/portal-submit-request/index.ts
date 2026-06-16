/**
 * Edge Function: portal-submit-request — Phase 1 of carrier counter-evidence (Sprint A)
 *
 * **Purpose:** A carrier (no JWT) requests permission to upload one piece of
 * counter-evidence for a disputed sanction. Returns a short-lived signed upload
 * URL pointing at a quarantine path. The bytes are NOT trusted until
 * portal-finalize-upload re-hashes them server-side (INV-9).
 *
 * **Flow:**
 *   1. Fail-fast input validation (UUID token, MIME whitelist, ≤10MB, 64-hex sha).
 *   2. create_portal_submission RPC (service_role): validates submit scope, the
 *      'disputed' state, and the per-token cap under an advisory lock; mints a
 *      QUARANTINE row + the quarantine path {token_id}/{uuid}.ext (no org_id).
 *   3. createSignedUploadUrl(quarantine bucket, single-use path). The upload
 *      token is one-shot for that exact path; the cap + finalize re-hash are the
 *      security boundary (the storage API fixes the upload-URL TTL).
 *
 * **Security:**
 *   - No JWT. The token IS the credential.
 *   - Scope/state/ownership failures → sovereigntyErrorResponse (404 parity, INV-26),
 *     indistinguishable from a non-existent token.
 *   - 80ms response floor closes the timing side-channel on token validity.
 *   - Best-effort 3 req/min/IP throttle (the hard guarantee is the DB per-token cap).
 *   - SUPABASE_SERVICE_ROLE_KEY is a Deno secret — never in the client bundle.
 *
 * Request (file path):     { token, fileName, mimeType, fileSizeBytes, sha256Client, justification, submitterReference? }
 * Request (file-optional):  { token, justification }  (no fileName/mimeType/sha256Client)
 * Response (file path):     { submissionId, signedUrl }
 * Response (file-optional): { justificationSubmissionId }
 *
 * Justification is mandatory (testimony, equal legal weight to the file). It is
 * validated defense-in-depth here (mirrors the DB CHECK + RPC) and stored RAW —
 * NEVER HTML-encoded at ingest (that would corrupt the combined seal, INV-9).
 * Escaping is a render/export concern.
 *
 * Council: Architect ✅ · Senior ✅ · QA-Security ✅ · Business ✅ · Lead ✅
 * Invariants: INV-1, INV-9, INV-18, INV-22, INV-26.
 */

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { sovereigntyErrorResponse } from "../shared/sovereignty_error_mapper.ts";

const QUARANTINE_BUCKET = "dispute-evidence-portal";
const MAX_BYTES = 10485760;
const RESPONSE_FLOOR_MS = 80;
const RATE_LIMIT = 3;
const RATE_WINDOW_MS = 60_000;
const JUSTIFICATION_MIN = 10;
const JUSTIFICATION_MAX = 4000;
// C0/C1 control chars except TAB (\x09) / LF (\x0A) / CR (\x0D).
const CONTROL_CHAR_RE = /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SHA256_RE = /^[a-f0-9]{64}$/;

/**
 * Defense-in-depth justification validation (mirrors the DB CHECK + RPC).
 * Uses code-point length ([...j].length), NOT .length, so multibyte/surrogate
 * characters are counted as the DB's char_length() counts them.
 */
function justificationInvalid(value: unknown): boolean {
  if (typeof value !== "string") return true;
  const codePoints = [...value].length;
  if (codePoints > JUSTIFICATION_MAX) return true;
  if ([...value.trim()].length < JUSTIFICATION_MIN) return true;
  if (CONTROL_CHAR_RE.test(value)) return true;
  return false;
}
const ALLOWED_MIME = new Set([
  "image/jpeg",
  "image/png",
  "application/pdf",
  "image/heic",
  "image/heif",
  "image/webp",
]);

// Best-effort in-memory throttle. Edge instances are ephemeral, so this is a
// soft DoS speed-bump only; the authoritative ceiling is the per-token cap.
const ipHits = new Map<string, number[]>();

function rateLimited(ip: string): boolean {
  const now = Date.now();
  const hits = (ipHits.get(ip) ?? []).filter((t) => now - t < RATE_WINDOW_MS);
  hits.push(now);
  ipHits.set(ip, hits);
  return hits.length > RATE_LIMIT;
}

async function withFloor(start: number, res: Response): Promise<Response> {
  const elapsed = Date.now() - start;
  if (elapsed < RESPONSE_FLOOR_MS) {
    await new Promise((r) => setTimeout(r, RESPONSE_FLOOR_MS - elapsed));
  }
  return res;
}

// Exported for unit testing with an injected SupabaseClient. Production wiring
// (Deno.serve) lives behind the import.meta.main guard at the bottom of the file.
export async function handler(
  req: Request,
  injectedSupabase?: SupabaseClient,
): Promise<Response> {
  const start = Date.now();

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
    return withFloor(start, sovereigntyErrorResponse());
  }

  const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
  if (rateLimited(ip)) {
    return withFloor(start, Response.json({ error: "Too Many Requests" }, { status: 429 }));
  }

  // ── Parse + fail-fast validation (BEFORE touching the DB) ───────────────────
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return withFloor(start, Response.json({ error: "Invalid JSON body" }, { status: 400 }));
  }

  const token = body.token;
  const fileName = body.fileName;
  const mimeType = body.mimeType;
  const fileSizeBytes = body.fileSizeBytes;
  const sha256Client = body.sha256Client;
  const justification = body.justification;
  const submitterReference = body.submitterReference;

  if (typeof token !== "string" || !UUID_RE.test(token)) {
    return withFloor(start, sovereigntyErrorResponse());
  }
  // Justification is mandatory on BOTH paths (testimony). Generic 400 (no oracle).
  if (justificationInvalid(justification)) {
    return withFloor(start, Response.json({ error: "Invalid justification" }, { status: 400 }));
  }
  if (submitterReference !== undefined && typeof submitterReference !== "string") {
    return withFloor(start, Response.json({ error: "Invalid submitterReference" }, { status: 400 }));
  }

  // File-optional (anexo opcional): no file fields → justification-only contest.
  const hasFile = fileName !== undefined || mimeType !== undefined ||
    fileSizeBytes !== undefined || sha256Client !== undefined;

  const supabase = injectedSupabase ?? createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // ── File-optional branch: justification-only, no signed URL ─────────────────
  if (!hasFile) {
    try {
      const { data, error } = await supabase.rpc("submit_portal_justification_only", {
        p_token: token,
        p_justification: justification,
      });
      // 42501 and any failure → identical 404 (INV-26).
      if (error || !data) {
        if (error) console.error("[portal-submit-request] justification rpc error:", error.message);
        return withFloor(start, sovereigntyErrorResponse());
      }
      return withFloor(
        start,
        Response.json({ justificationSubmissionId: data as string }, { status: 200 }),
      );
    } catch (e) {
      console.error("[portal-submit-request] justification unexpected:", e);
      return withFloor(start, sovereigntyErrorResponse());
    }
  }

  // ── File path: validate file metadata before minting a quarantine row ───────
  if (typeof fileName !== "string" || fileName.length === 0 || fileName.length > 255) {
    return withFloor(start, Response.json({ error: "Invalid fileName" }, { status: 400 }));
  }
  if (typeof mimeType !== "string" || !ALLOWED_MIME.has(mimeType)) {
    return withFloor(start, Response.json({ error: "Unsupported media type" }, { status: 415 }));
  }
  if (typeof fileSizeBytes !== "number" || !Number.isInteger(fileSizeBytes) || fileSizeBytes <= 0) {
    return withFloor(start, Response.json({ error: "Invalid fileSizeBytes" }, { status: 400 }));
  }
  if (fileSizeBytes > MAX_BYTES) {
    return withFloor(start, Response.json({ error: "Payload Too Large" }, { status: 413 }));
  }
  if (typeof sha256Client !== "string" || !SHA256_RE.test(sha256Client)) {
    return withFloor(start, Response.json({ error: "Invalid sha256Client" }, { status: 400 }));
  }

  try {
    // ── Mint quarantine row (scope/state/cap enforced inside the RPC) ─────────
    const { data, error } = await supabase.rpc("create_portal_submission", {
      p_token: token,
      p_file_name: fileName,
      p_mime_type: mimeType,
      p_file_size_bytes: fileSizeBytes,
      p_sha256_client: sha256Client,
      p_justification: justification,
      p_submitter_ip: ip === "unknown" ? null : ip,
      p_correlation_id: typeof submitterReference === "string" ? submitterReference : null,
    });

    // 42501 (insufficient_privilege) and any failure → identical 404 (INV-26).
    if (error || !data || (Array.isArray(data) && data.length === 0)) {
      if (error) console.error("[portal-submit-request] rpc error:", error.message);
      return withFloor(start, sovereigntyErrorResponse());
    }

    const row = (Array.isArray(data) ? data[0] : data) as {
      submission_id: string;
      quarantine_path: string;
    };
    const submissionId: string = row.submission_id;
    const quarantinePath: string = row.quarantine_path;

    // ── Signed upload URL into the quarantine bucket ──────────────────────────
    const { data: signed, error: signErr } = await supabase.storage
      .from(QUARANTINE_BUCKET)
      .createSignedUploadUrl(quarantinePath, { upsert: false });

    if (signErr || !signed) {
      console.error("[portal-submit-request] signed url error:", signErr?.message);
      return withFloor(start, sovereigntyErrorResponse());
    }

    return withFloor(
      start,
      Response.json({ submissionId, signedUrl: signed.signedUrl }, { status: 200 }),
    );
  } catch (e) {
    console.error("[portal-submit-request] unexpected:", e);
    return withFloor(start, sovereigntyErrorResponse());
  }
}

if (import.meta.main) {
  Deno.serve(handler);
}
