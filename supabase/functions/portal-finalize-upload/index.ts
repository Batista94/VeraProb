/**
 * Edge Function: portal-finalize-upload — Phase 2 of carrier counter-evidence (Sprint A)
 *
 * **Purpose:** After the carrier PUTs bytes to the quarantine signed URL, this
 * verifies them server-side and, only on success, promotes the submission to
 * PENDING_AUDIT with a VERIFIED attachment. Nothing the carrier declared is
 * trusted — the server re-derives mime (magic bytes) and SHA-256 (INV-9).
 *
 * **Flow:**
 *   1. Validate token (submit scope, not revoked/expired) + submission ownership.
 *   2. Download quarantine bytes (service_role).
 *   3. Magic-byte sniff vs declared mime → mismatch ⇒ fail(MIME_MISMATCH) + 422.
 *   4. SHA-256(bytes) vs declared sha256Client → mismatch ⇒ fail(HASH_MISMATCH) + 422.
 *   5. Copy bytes to the production bucket at a path derived from SEALED fields.
 *   6. register_portal_evidence (atomic: VERIFIED attachment + PENDING_AUDIT + fact).
 *
 * **Security:**
 *   - No JWT. Token is the credential; failures → sovereigntyErrorResponse (INV-26).
 *   - Production path built from sealed org/queue/submission — never carrier input.
 *   - EXIF is NOT stripped here: SHA-256 seals the raw bytes (INV-9). On-serve
 *     stripping stays in dispute-portal-evidence.
 *
 * Request:  { token, submissionId }
 * Response: { status: "PENDING_AUDIT", attachmentId } | 422 on mismatch
 *
 * Council: Architect ✅ · Senior ✅ · QA-Security ✅ · Business ✅ · Lead ✅
 * Invariants: INV-1, INV-9, INV-18, INV-22, INV-26.
 */

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { sovereigntyErrorResponse } from "../shared/sovereignty_error_mapper.ts";
import { detectMime, isMimeConsistent, mimeExt } from "../shared/magic_bytes.ts";

const QUARANTINE_BUCKET = "dispute-evidence-portal";
const PRODUCTION_BUCKET = "dispute_evidence";
const MAX_BYTES = 10485760;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type Supabase = SupabaseClient;

interface TokenRow {
  id: string;
  organization_id: string;
  queue_entry_id: string;
  token_scope: string;
  expires_at_utc: string;
  revoked_at_utc: string | null;
}

interface SubmissionRow {
  id: string;
  organization_id: string;
  queue_entry_id: string;
  token_id: string;
  quarantine_storage_path: string;
  mime_type_declared: string;
  sha256_client: string;
  status: string;
  file_size_bytes_declared: number;
}

async function sha256Hex(buffer: ArrayBuffer): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", buffer);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function failSubmission(
  supabase: Supabase,
  submissionId: string,
  kind: "HASH_MISMATCH" | "MIME_MISMATCH" | "REJECTED",
  detail: string,
): Promise<void> {
  const { error } = await supabase.rpc("fail_portal_submission", {
    p_submission_id: submissionId,
    p_kind: kind,
    p_detail: detail,
  });
  if (error) console.error("[portal-finalize-upload] fail rpc error:", error.message);
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST",
        "Access-Control-Allow-Headers": "Authorization, Content-Type",
      },
    });
  }
  if (req.method !== "POST") return sovereigntyErrorResponse();

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const token = body.token;
  const submissionId = body.submissionId;
  if (
    typeof token !== "string" || !UUID_RE.test(token) ||
    typeof submissionId !== "string" || !UUID_RE.test(submissionId)
  ) {
    return sovereigntyErrorResponse();
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  try {
    // ── Validate token ────────────────────────────────────────────────────────
    const { data: tokData, error: tokErr } = await supabase
      .from("dispute_portal_tokens")
      .select("id, organization_id, queue_entry_id, token_scope, expires_at_utc, revoked_at_utc")
      .eq("token", token)
      .maybeSingle();
    const tok = tokData as TokenRow | null;
    if (tokErr || !tok || tok.token_scope !== "submit") return sovereigntyErrorResponse();
    if (tok.revoked_at_utc !== null) return sovereigntyErrorResponse();
    if (new Date() > new Date(tok.expires_at_utc)) return sovereigntyErrorResponse();

    // ── Validate submission ownership + state ──────────────────────────────────
    const { data: subData, error: subErr } = await supabase
      .from("portal_evidence_submissions")
      .select("id, organization_id, queue_entry_id, token_id, quarantine_storage_path, mime_type_declared, sha256_client, status, file_size_bytes_declared")
      .eq("id", submissionId)
      .maybeSingle();
    const sub = subData as SubmissionRow | null;
    if (subErr || !sub) return sovereigntyErrorResponse();
    if (sub.token_id !== tok.id || sub.status !== "QUARANTINE") return sovereigntyErrorResponse();

    // ── Download quarantine bytes ──────────────────────────────────────────────
    const { data: blob, error: dlErr } = await supabase.storage
      .from(QUARANTINE_BUCKET)
      .download(sub.quarantine_storage_path as string);
    if (dlErr || !blob) {
      console.error("[portal-finalize-upload] download error:", dlErr?.message);
      return sovereigntyErrorResponse();
    }
    const arrayBuffer = await blob.arrayBuffer();
    const bytes = new Uint8Array(arrayBuffer);

    if (bytes.length === 0 || bytes.length > MAX_BYTES) {
      await failSubmission(supabase, submissionId, "REJECTED", "size out of bounds");
      return Response.json({ error: "Unprocessable Entity" }, { status: 422 });
    }

    // ── Magic-byte sniff vs declared mime (INV-18) ─────────────────────────────
    const detected = detectMime(bytes);
    if (detected === null || !isMimeConsistent(sub.mime_type_declared as string, detected)) {
      await failSubmission(supabase, submissionId, "MIME_MISMATCH", `detected=${detected}`);
      return Response.json({ error: "Content type mismatch" }, { status: 422 });
    }

    // ── SHA-256 server-side vs declared (INV-9: the canonical seal) ────────────
    const serverHash = await sha256Hex(arrayBuffer);
    if (serverHash !== (sub.sha256_client as string)) {
      await failSubmission(supabase, submissionId, "HASH_MISMATCH", "server hash != declared");
      return Response.json({ error: "Hash mismatch" }, { status: 422 });
    }

    // ── Copy to production bucket at a path derived from SEALED fields ─────────
    const prodPath =
      `${sub.organization_id}/${sub.queue_entry_id}/${sub.id}.${mimeExt(detected)}`;
    const { error: upErr } = await supabase.storage
      .from(PRODUCTION_BUCKET)
      .upload(prodPath, bytes, { contentType: detected, upsert: false });
    // Idempotent replay: a prior finalize already copied the object — tolerate it.
    if (upErr && !/exists/i.test(upErr.message)) {
      console.error("[portal-finalize-upload] upload error:", upErr.message);
      return sovereigntyErrorResponse();
    }

    // ── Atomic registration ────────────────────────────────────────────────────
    const { data: attachmentId, error: regErr } = await supabase.rpc("register_portal_evidence", {
      p_submission_id: submissionId,
      p_sha256_server: serverHash,
      p_mime_type_detected: detected,
      p_file_size_bytes_actual: bytes.length,
    });
    if (regErr || !attachmentId) {
      console.error("[portal-finalize-upload] register error:", regErr?.message);
      return sovereigntyErrorResponse();
    }

    return Response.json({ status: "PENDING_AUDIT", attachmentId }, { status: 200 });
  } catch (e) {
    console.error("[portal-finalize-upload] unexpected:", e);
    return sovereigntyErrorResponse();
  }
});
