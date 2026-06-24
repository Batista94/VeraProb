/**
 * Edge Function: dispute-portal-evidence — Token-Gated Evidence File Serving (Item 5.3)
 *
 * **Purpose:** Serves evidence files from Supabase Storage to external parties
 * who possess a valid dispute portal token. No JWT required — the token IS
 * the authentication credential.
 *
 * **Flow:**
 *  1. External party GETs `?token={uuid}&attachment_id={uuid}`
 *  2. Validate token (exists, not expired, not revoked, access_count < max)
 *  3. Validate attachment belongs to token's queue_entry_id + organization_id
 *  4. Download raw bytes from `dispute_evidence` bucket (service_role)
 *  5. Strip EXIF from JPEG (reuse shared exif_stripper.ts)
 *  6. Serve bytes with no-cache headers
 *
 * **Security:**
 *  - NO JWT required (external access via token)
 *  - Token validated server-side via direct DB query (service_role)
 *  - Org-scoped: attachment must belong to token's org_id (INV-22)
 *  - DOES NOT increment access_count (read RPC already did that)
 *  - Error parity: all failures → sovereigntyErrorResponse (INV-26)
 *  - EXIF stripping: GPS, device info removed from JPEG (INV-18)
 *  - Cache-Control: no-store (evidence must not be cached by intermediaries)
 *
 * Council: Architect ✅ · Senior ✅ · QA-Security ✅ · Business ✅ · Lead ✅
 * Invariants: INV-1, INV-9, INV-18, INV-22, INV-26.
 */

import { createClient } from "jsr:@supabase/supabase-js@2";
import { stripExifFromJpeg } from "../shared/exif_stripper.ts";
import { sovereigntyErrorResponse } from "../shared/sovereignty_error_mapper.ts";

const BUCKET = "dispute_evidence";
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req: Request): Promise<Response> => {
  // CORS preflight
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

  // No JWT validation — authentication is via the portal token.
  // Initialize service_role client directly.
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
    // ── Parse query params ──────────────────────────────────────────────────
    const url = new URL(req.url);
    const tokenParam = url.searchParams.get("token");
    const attachmentId = url.searchParams.get("attachment_id");

    if (!tokenParam || !attachmentId) {
      return sovereigntyErrorResponse();
    }

    // UUID format guard (prevents Postgres cast errors leaking)
    if (!UUID_RE.test(tokenParam) || !UUID_RE.test(attachmentId)) {
      return sovereigntyErrorResponse();
    }

    // ── Validate token ──────────────────────────────────────────────────────
    const { data: tokenRow, error: tokenErr } = await supabase
      .from("dispute_portal_tokens")
      .select("id, organization_id, queue_entry_id, expires_at_utc, revoked_at_utc, access_count, max_access_count")
      .eq("token", tokenParam)
      .maybeSingle();

    // INV-26: not found → identical 404
    if (tokenErr || !tokenRow) {
      return sovereigntyErrorResponse();
    }

    // Expired?
    const now = new Date();
    if (now > new Date(tokenRow.expires_at_utc)) {
      return sovereigntyErrorResponse();
    }

    // Revoked?
    if (tokenRow.revoked_at_utc !== null) {
      return sovereigntyErrorResponse();
    }

    // Exhausted? (allow reads up to max — file serving doesn't increment)
    if (tokenRow.access_count > tokenRow.max_access_count) {
      return sovereigntyErrorResponse();
    }

    // ── Validate attachment belongs to token's scope (INV-22) ────────────────
    const { data: attachment, error: attachErr } = await supabase
      .from("dispute_evidence_attachments")
      .select("id, organization_id, queue_entry_id, storage_path, file_name, mime_type, deleted_at")
      .eq("id", attachmentId)
      .eq("organization_id", tokenRow.organization_id)
      .eq("queue_entry_id", tokenRow.queue_entry_id)
      .maybeSingle();

    if (attachErr || !attachment) {
      return sovereigntyErrorResponse();
    }

    // Soft-deleted evidence cannot be served.
    if (attachment.deleted_at !== null) {
      return sovereigntyErrorResponse();
    }

    // ── Download raw bytes from Storage (service_role) ──────────────────────
    const { data: fileData, error: dlError } = await supabase.storage
      .from(BUCKET)
      .download(attachment.storage_path);

    if (dlError || !fileData) {
      console.error(
        `[dispute-portal-evidence] Storage download failed for ${attachmentId}:`,
        dlError?.message ?? "no data",
      );
      return sovereigntyErrorResponse();
    }

    const bytes = new Uint8Array(await fileData.arrayBuffer());
    const contentType = mimeFromName(attachment.file_name ?? "unknown");

    // ── Strip EXIF from JPEG (INV-18) ───────────────────────────────────────
    let responseBytes: Uint8Array = bytes;
    const ext = (attachment.file_name ?? "").split(".").pop()?.toLowerCase() ?? "";
    if (ext === "jpg" || ext === "jpeg") {
      const stripped = stripExifFromJpeg(bytes);
      if (stripped) responseBytes = stripped;
    }

    // ── Serve with strict cache headers ─────────────────────────────────────
    return new Response(responseBytes, {
      status: 200,
      headers: {
        "Content-Type": contentType,
        "Content-Disposition": `inline; filename="${sanitizeFilename(attachment.file_name)}"`,
        "Cache-Control": "no-store, no-cache, must-revalidate",
        "Pragma": "no-cache",
        "X-Content-Type-Options": "nosniff",
        "X-Frame-Options": "DENY",
        "Content-Security-Policy": "default-src 'none'",
      },
    });
  } catch (error) {
    // INV-26: ALL errors → canonical 404
    console.error("[dispute-portal-evidence] Unexpected error:", error);
    return sovereigntyErrorResponse();
  }
}

/**
 * Maps file extension to MIME type.
 */
function mimeFromName(fileName: string): string {
  const ext = fileName.split(".").pop()?.toLowerCase() ?? "";
  const map: Record<string, string> = {
    jpg: "image/jpeg",
    jpeg: "image/jpeg",
    png: "image/png",
    pdf: "application/pdf",
    webp: "image/webp",
    heic: "image/heic",
    heif: "image/heif",
  };
  return map[ext] ?? "application/octet-stream";
}

/**
 * Sanitizes filename for Content-Disposition header (prevent header injection).
 */
function sanitizeFilename(name: string | null): string {
  if (!name) return "evidence";
  // Remove any characters that could break the header
  return name.replace(/[^\w.\-]/g, "_").substring(0, 255);
}
