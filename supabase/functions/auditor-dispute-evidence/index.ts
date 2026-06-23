/**
 * Edge Function: auditor-dispute-evidence
 *
 * Serves a dispute counter-evidence attachment (bucket `dispute_evidence`) to an
 * authenticated auditor for the Tribunal de Auditoria viewer, with EXIF metadata
 * stripped from JPEGs. Mirrors secure-evidence-proxy, but for ACTIVE-dispute
 * forensic material — so it adds an explicit RBAC gate on top of auth.
 *
 * Security model:
 *   - JWT auth via handleWithSecurity (INV-1, INV-26)
 *   - RBAC: role MUST be TENANT_ADMIN or AUDITOR (dispute evidence is not for
 *     operators) — checked in-handler from the validated JWT.
 *   - Org-scoped: the attachment row must belong to the JWT's org_id (INV-1/22).
 *   - Anti-oracle: not-found / wrong-org / wrong-role all return the SAME 404
 *     (sovereigntyErrorResponse) — no inference channel (INV-26).
 *   - EXIF stripping from JPEG before serving (INV-18); the stored original is
 *     NEVER modified (INV-9).
 *   - X-Content-SHA256 echoes the sealed server hash so the UI can verify (INV-9).
 *   - Cache-Control: no-store — dispute evidence is never cached (INV-22).
 *
 * Request: GET ?attachment_id={uuid}
 * Response: Binary file with Content-Type, Content-Disposition, X-Content-SHA256.
 */

import { handleWithSecurity, type SecurityContext } from "../shared/handle_with_security.ts";
import { stripExifFromJpeg } from "../shared/exif_stripper.ts";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { sovereigntyErrorResponse } from "../shared/sovereignty_error_mapper.ts";
import { validateJwtAuth } from "../shared/jwt_auth_validator.ts";

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
  // RBAC (INV-26 parity): dispute evidence is auditor-grade. A merely
  // authenticated operator must be indistinguishable from a not-found.
  const auth = await validateJwtAuth(req);
  if (!auth.ok) return sovereigntyErrorResponse();
  const appMeta = auth.jwtPayload.app_metadata as
    | Record<string, unknown>
    | undefined;
  const role = appMeta?.role;
  if (role !== "TENANT_ADMIN" && role !== "AUDITOR") {
    return sovereigntyErrorResponse();
  }

  const url = new URL(req.url);
  const attachmentId = url.searchParams.get("attachment_id");
  if (!attachmentId || !UUID_RE.test(attachmentId)) {
    return sovereigntyErrorResponse();
  }

  // Org-scoped lookup (INV-1/22). Wrong org → no row → identical 404 (INV-26).
  const { data: attachment, error } = await supabase
    .from("dispute_evidence_attachments")
    .select("storage_path, file_name, mime_type, sha256_hash, organization_id")
    .eq("id", attachmentId)
    .eq("organization_id", ctx.orgId!)
    .is("deleted_at", null)
    .maybeSingle();

  if (error || !attachment) return sovereigntyErrorResponse();

  const { data: fileData, error: dlError } = await supabase.storage
    .from(BUCKET)
    .download(attachment.storage_path as string);

  if (dlError || !fileData) return sovereigntyErrorResponse();

  const bytes = new Uint8Array(await fileData.arrayBuffer());
  const fileName = (attachment.file_name as string) ?? "evidence";
  const ext = fileName.split(".").pop()?.toLowerCase() ?? "";

  // Strip EXIF from JPEG only — other formats served as-is (INV-18).
  let responseBytes: Uint8Array = bytes;
  if (ext === "jpg" || ext === "jpeg") {
    const stripped = stripExifFromJpeg(bytes);
    if (stripped) responseBytes = stripped;
  }

  return new Response(responseBytes, {
    status: 200,
    headers: {
      "Content-Type": (attachment.mime_type as string) ?? mimeFromExt(ext),
      "Content-Disposition": `inline; filename="${fileName}"`,
      // INV-9: the UI re-checks this seal against the displayed bytes' source.
      "X-Content-SHA256": attachment.sha256_hash as string,
      // INV-22: dispute evidence must never be cached by any intermediary.
      "Cache-Control": "no-store, no-cache, must-revalidate",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

function mimeFromExt(ext: string): string {
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
