/**
 * Edge Function: auditor-dispute-evidence
 *
 * Serves dispute counter-evidence with EXIF strip + RBAC (TENANT_ADMIN/AUDITOR).
 */

import { handleWithSecurity, type SecurityContext } from "../shared/handle_with_security.ts";
import { serveEvidenceBytes } from "../shared/evidence_serve.ts";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { sovereigntyErrorResponse } from "../shared/sovereignty_error_mapper.ts";

const BUCKET = "dispute_evidence";
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET",
        "Access-Control-Allow-Headers": "Authorization",
      },
    });
  }

  if (req.method !== "GET") {
    return sovereigntyErrorResponse();
  }

  return await handleWithSecurity(req, "auditor-dispute-evidence", handler);
});

export async function handler(
  ctx: SecurityContext,
  supabase: SupabaseClient,
  req: Request,
): Promise<Response> {
  // Role from SecurityContext (handleWithSecurity already validated JWT).
  if (ctx.role !== "TENANT_ADMIN" && ctx.role !== "AUDITOR") {
    return sovereigntyErrorResponse();
  }

  const url = new URL(req.url);
  const attachmentId = url.searchParams.get("attachment_id");
  if (!attachmentId || !UUID_RE.test(attachmentId)) {
    return sovereigntyErrorResponse();
  }

  const { data: attachment, error } = await supabase
    .from("dispute_evidence_attachments")
    .select("storage_path, file_name, mime_type, sha256_hash, organization_id")
    .eq("id", attachmentId)
    .eq("organization_id", ctx.orgId!)
    .is("deleted_at", null)
    .maybeSingle();

  if (error || !attachment) return sovereigntyErrorResponse();

  const res = await serveEvidenceBytes({
    supabase,
    bucket: BUCKET,
    storagePath: attachment.storage_path as string,
    fileName: attachment.file_name as string | null,
    mimeType: attachment.mime_type as string | null,
  });

  if (res.status !== 200) return res;

  // Preserve dispute-specific cache + seal headers.
  const headers = new Headers(res.headers);
  headers.set("X-Content-SHA256", attachment.sha256_hash as string);
  headers.set("Cache-Control", "no-store, no-cache, must-revalidate");
  return new Response(res.body, { status: 200, headers });
}
