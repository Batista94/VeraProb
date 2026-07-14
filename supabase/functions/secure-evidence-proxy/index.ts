/**
 * Edge Function: secure-evidence-proxy
 *
 * Serves evidence files from Supabase Storage with EXIF metadata stripped
 * from JPEG images. Non-JPEG files are served as-is.
 *
 * Security model:
 *   - JWT auth via handleWithSecurity (INV-1, INV-26)
 *   - Org-scoped: storage_path must belong to the JWT's org_id (INV-1)
 *   - EXIF stripping: GPS, device info removed from JPEG before serving (INV-18)
 *   - Original file in storage is NEVER modified (INV-9)
 *   - Error parity: all failures return 404 (INV-26)
 *
 * Request: GET ?evidence_id={uuid}
 * Response: Binary file with Content-Type, Content-Disposition headers
 */

import { handleWithSecurity, type SecurityContext } from "../shared/handle_with_security.ts";
import { serveEvidenceBytes } from "../shared/evidence_serve.ts";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { sovereigntyErrorResponse } from "../shared/sovereignty_error_mapper.ts";

const BUCKET = "telegram_evidence";

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

  return await handleWithSecurity(req, "secure-evidence-proxy", handler);
});

async function handler(
  ctx: SecurityContext,
  supabase: SupabaseClient,
  req: Request,
): Promise<Response> {
  // Parse evidence_id from query string
  const url = new URL(req.url);
  const evidenceId = url.searchParams.get("evidence_id");
  if (!evidenceId) return sovereigntyErrorResponse();

  // Lookup evidence record — org-scoped (INV-1)
  const { data: evidence, error } = await supabase
    .from("telegram_evidence_uploads")
    .select("storage_path, file_name, organization_id")
    .eq("id", evidenceId)
    .eq("organization_id", ctx.orgId!)
    .maybeSingle();

  // INV-26: not found OR wrong org → identical 404
  if (error || !evidence) return sovereigntyErrorResponse();

  return await serveEvidenceBytes({
    supabase,
    bucket: BUCKET,
    storagePath: evidence.storage_path as string,
    fileName: evidence.file_name as string | null,
  });
}
