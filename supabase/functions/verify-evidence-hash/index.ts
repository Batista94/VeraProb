/**
 * Edge Function: verify-evidence-hash — DEPRECATED
 *
 * Orphan: no lib/ callers. SSOT is portal-finalize-upload + verify_evidence_hash RPC.
 * All non-OPTIONS responses use INV-26 opaque parity (no detail leak).
 */

import { sovereigntyErrorResponse } from "../shared/sovereignty_error_mapper.ts";

function handleRequest(req: Request): Response {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST",
        "Access-Control-Allow-Headers": "Authorization, Content-Type",
      },
    });
  }
  return sovereigntyErrorResponse();
}

if (import.meta.main) {
  Deno.serve((req: Request): Response => handleRequest(req));
}

/** Exported for unit tests — mirrors Deno.serve routing. */
export async function handler(
  _ctx: unknown,
  _supabase: unknown,
  req: Request,
): Promise<Response> {
  return handleRequest(req);
}
