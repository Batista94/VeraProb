/**
 * Edge Function: dispute-portal-evidence — Token-Gated Evidence File Serving
 * Serves dispute evidence via portal token (no JWT). EXIF strip via shared helper.
 */

import { createClient } from "jsr:@supabase/supabase-js@2";
import { serveEvidenceBytes } from "../shared/evidence_serve.ts";
import { sovereigntyErrorResponse } from "../shared/sovereignty_error_mapper.ts";

const BUCKET = "dispute_evidence";
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET",
        "Access-Control-Allow-Headers": "Content-Type",
      },
    });
  }

  if (req.method !== "GET") {
    return sovereigntyErrorResponse();
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  return await handlePortalEvidence(supabase, req);
});

async function handlePortalEvidence(
  supabase: ReturnType<typeof createClient>,
  req: Request,
): Promise<Response> {
  try {
    const url = new URL(req.url);
    const tokenParam = url.searchParams.get("token");
    const attachmentId = url.searchParams.get("attachment_id");

    if (!tokenParam || !attachmentId) {
      return sovereigntyErrorResponse();
    }
    if (!UUID_RE.test(tokenParam) || !UUID_RE.test(attachmentId)) {
      return sovereigntyErrorResponse();
    }

    const { data: tokenRow, error: tokenErr } = await supabase
      .from("dispute_portal_tokens")
      .select(
        "id, organization_id, queue_entry_id, expires_at_utc, revoked_at_utc, access_count, max_access_count",
      )
      .eq("token", tokenParam)
      .maybeSingle();

    if (tokenErr || !tokenRow) {
      return sovereigntyErrorResponse();
    }

    const now = new Date();
    if (now > new Date(tokenRow.expires_at_utc as string)) {
      return sovereigntyErrorResponse();
    }
    if (tokenRow.revoked_at_utc !== null) {
      return sovereigntyErrorResponse();
    }
    if (
      (tokenRow.access_count as number) > (tokenRow.max_access_count as number)
    ) {
      return sovereigntyErrorResponse();
    }

    const { data: attachment, error: attachErr } = await supabase
      .from("dispute_evidence_attachments")
      .select(
        "id, organization_id, queue_entry_id, storage_path, file_name, mime_type, deleted_at",
      )
      .eq("id", attachmentId)
      .eq("organization_id", tokenRow.organization_id)
      .eq("queue_entry_id", tokenRow.queue_entry_id)
      .maybeSingle();

    if (attachErr || !attachment || attachment.deleted_at !== null) {
      return sovereigntyErrorResponse();
    }

    const res = await serveEvidenceBytes({
      supabase,
      bucket: BUCKET,
      storagePath: attachment.storage_path as string,
      fileName: attachment.file_name as string | null,
      mimeType: attachment.mime_type as string | null,
    });

    if (res.status !== 200) return res;

    const headers = new Headers(res.headers);
    headers.set("Cache-Control", "no-store, no-cache, must-revalidate");
    headers.set("Pragma", "no-cache");
    headers.set("X-Frame-Options", "DENY");
    headers.set("Content-Security-Policy", "default-src 'none'");
    const fileName = sanitizeFilename(attachment.file_name as string | null);
    headers.set("Content-Disposition", `inline; filename="${fileName}"`);
    return new Response(res.body, { status: 200, headers });
  } catch (error) {
    console.error("[dispute-portal-evidence] Unexpected error:", error);
    return sovereigntyErrorResponse();
  }
}

function sanitizeFilename(name: string | null | undefined): string {
  if (!name) return "evidence";
  return name.replace(/["\\\r\n]/g, "_");
}
