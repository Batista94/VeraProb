/**
 * Edge Function: verify-evidence-hash — Server-Side SHA-256 Re-Verification (B2, ADD-2)
 *
 * **Purpose:** Closes the cryptographic loop opened by `attach_dispute_evidence`.
 * The client computes SHA-256 at upload; this function downloads the stored bytes
 * via service_role, recomputes SHA-256 using `crypto.subtle.digest`, and calls
 * the `verify_evidence_hash` RPC (Migration 009) to seal the verdict.
 *
 * **Flow:**
 *  1. Authenticated caller POSTs { attachment_id, organization_id }
 *  2. Fetch the attachment row (org-scoped, storage_path lookup)
 *  3. Download raw bytes from `dispute_evidence` bucket (service_role)
 *  4. Recompute SHA-256 over the raw bytes
 *  5. Call `verify_evidence_hash` RPC → VERIFIED or MISMATCH + ledger fact
 *  6. Return the verification status to the caller
 *
 * **Security:**
 *  - Requires valid JWT (INV-1) — only authenticated TENANT_ADMIN/AUDITOR
 *  - Org-scoped: JWT org_id must match the attachment's organization_id (INV-22)
 *  - Storage download uses service_role (bucket is private, no client access)
 *  - RPC is service_role-only (REVOKED from authenticated/anon)
 *  - Error parity: all failures → sovereigntyErrorResponse (INV-26)
 *
 * **Trigger:** Called by the Dart client fire-and-forget after a successful
 * `attach_dispute_evidence`, or via a Storage webhook. Idempotent: re-calling
 * with an already-verified attachment simply re-seals the same status.
 *
 * Invariants: INV-1, INV-6, INV-9, INV-22, INV-26.
 */

import { handleWithSecurity, type SecurityContext } from "../shared/handle_with_security.ts";
import { sovereigntyErrorResponse } from "../shared/sovereignty_error_mapper.ts";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

const BUCKET = "dispute_evidence";

Deno.serve(async (req: Request): Promise<Response> => {
  // CORS preflight
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
    return sovereigntyErrorResponse();
  }

  return await handleWithSecurity(
    req,
    "verify-evidence-hash",
    handler,
  );
});

async function handler(
  ctx: SecurityContext,
  supabase: SupabaseClient,
  req: Request,
): Promise<Response> {
  // ── Parse request body ──────────────────────────────────────────────────────
  let body: { attachment_id: string; organization_id: string };
  try {
    body = await req.json();
  } catch {
    return sovereigntyErrorResponse();
  }

  const { attachment_id, organization_id } = body;

  // ── Input validation (INV-26: generic failures, no oracle) ──────────────────
  if (
    !attachment_id || typeof attachment_id !== "string" ||
    !organization_id || typeof organization_id !== "string"
  ) {
    return sovereigntyErrorResponse();
  }

  // UUID format guard (prevents Postgres cast errors leaking)
  const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (!UUID_RE.test(attachment_id) || !UUID_RE.test(organization_id)) {
    return sovereigntyErrorResponse();
  }

  // ── Org-scope enforcement (INV-1, INV-22) ───────────────────────────────────
  // The JWT's org_id must match the requested organization_id.
  if (ctx.orgId !== organization_id) {
    return sovereigntyErrorResponse();
  }

  // ── Fetch attachment row (storage_path lookup, org-scoped) ──────────────────
  const { data: attachment, error: fetchErr } = await supabase
    .from("dispute_evidence_attachments")
    .select("id, organization_id, storage_path, sha256_hash, verification_status, deleted_at")
    .eq("id", attachment_id)
    .eq("organization_id", organization_id)
    .maybeSingle();

  // INV-26: not found OR wrong org → identical 404
  if (fetchErr || !attachment) {
    return sovereigntyErrorResponse();
  }

  // Soft-deleted evidence cannot be re-verified (tampering defense).
  if (attachment.deleted_at !== null) {
    return sovereigntyErrorResponse();
  }

  // ── Download raw bytes from Storage (service_role) ──────────────────────────
  const { data: fileData, error: dlError } = await supabase.storage
    .from(BUCKET)
    .download(attachment.storage_path);

  if (dlError || !fileData) {
    console.error(
      `[verify-evidence-hash] Storage download failed for ${attachment_id}:`,
      dlError?.message ?? "no data",
    );
    return sovereigntyErrorResponse();
  }

  // ── Recompute SHA-256 over the raw bytes (INV-9) ────────────────────────────
  const arrayBuffer = await fileData.arrayBuffer();
  const hashBuffer = await crypto.subtle.digest("SHA-256", arrayBuffer);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  const computedHash = hashArray
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  // ── Call verify_evidence_hash RPC (Migration 009) ───────────────────────────
  // The RPC compares, seals verification_status, and (on mismatch) writes a
  // forensic EVIDENCE_HASH_MISMATCH fact to the ledger. INV-6: UTC timestamp.
  const verifiedAt = new Date().toISOString();

  const { data: rpcResult, error: rpcError } = await supabase.rpc(
    "verify_evidence_hash",
    {
      p_attachment_id: attachment_id,
      p_organization_id: organization_id,
      p_computed_hash: computedHash,
      p_verified_at: verifiedAt,
    },
  );

  if (rpcError) {
    console.error(
      `[verify-evidence-hash] RPC failed for ${attachment_id}:`,
      rpcError.message,
    );
    return sovereigntyErrorResponse();
  }

  // ── Success: return the verification status ─────────────────────────────────
  const status: string = rpcResult ?? "UNKNOWN";

  return new Response(
    JSON.stringify({
      attachment_id,
      verification_status: status,
      verified_at: verifiedAt,
    }),
    {
      status: 200,
      headers: { "Content-Type": "application/json" },
    },
  );
}
