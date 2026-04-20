/**
 * Edge Function: get-justification-upload-url
 *
 * Returns a pre-signed PUT URL for driver evidence uploads.
 *
 * Security model (PO-1, INV-3, INV-8):
 *   - Callable by `anon` role — no JWT required.
 *   - Token UUID 128-bit space prevents brute-force enumeration.
 *   - Token must be active (not expired, not yet used).
 *   - SUPABASE_SERVICE_ROLE_KEY is a Deno secret — never in the client bundle.
 *   - Storage path is prefixed by `organization_id` for tenant isolation.
 *
 * Request body: { token: string, fileName: string }
 * Response:     { url: string, storagePath: string }
 *
 * Setup:
 *   1. `supabase secrets set SUPABASE_SERVICE_ROLE_KEY=<key>`
 *   2. Create storage bucket `justification-evidence` in Supabase Dashboard.
 *   3. `supabase functions deploy get-justification-upload-url`
 */

import { createClient } from "jsr:@supabase/supabase-js@2";

const BUCKET = "justification-evidence";

// Signed URL expiry in seconds (10 minutes is ample for a single upload).
const SIGNED_URL_EXPIRY_SECONDS = 600;

Deno.serve(async (req: Request): Promise<Response> => {
  // ── CORS preflight ──────────────────────────────────────────────────────────
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

  // ── Parse body ──────────────────────────────────────────────────────────────
  let token: string, fileName: string;
  try {
    ({ token, fileName } = await req.json());
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  if (!token || typeof token !== "string") {
    return Response.json({ error: "Missing required field: token" }, { status: 400 });
  }
  if (!fileName || typeof fileName !== "string") {
    return Response.json({ error: "Missing required field: fileName" }, { status: 400 });
  }

  // Sanitize fileName: strip path traversal and leading slashes.
  const safeFileName = fileName.replace(/[/\\]/g, "_").replace(/^\.+/, "_");

  // ── Service-role client (server-side only) ──────────────────────────────────
  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // ── Validate token ──────────────────────────────────────────────────────────
  const { data: tokenRow, error: tokenError } = await serviceClient
    .from("justification_submission_tokens")
    .select("id, organization_id, contract_id, set_id, token, expires_at_utc, used_at_utc")
    .eq("token", token)
    .maybeSingle();

  if (tokenError) {
    console.error("[get-justification-upload-url] token lookup error:", tokenError);
    return Response.json({ error: "Internal server error" }, { status: 500 });
  }

  if (!tokenRow) {
    return Response.json({ error: "Token not found" }, { status: 404 });
  }

  if (tokenRow.used_at_utc !== null) {
    return Response.json({ error: "Token already used" }, { status: 409 });
  }

  const expiresAt = new Date(tokenRow.expires_at_utc);
  if (expiresAt <= new Date()) {
    return Response.json({ error: "Token expired" }, { status: 410 });
  }

  // ── Generate signed upload URL ──────────────────────────────────────────────
  // Path: {organization_id}/{token_id}/{safe_file_name}
  // Using token.id (not the raw token UUID) to keep paths unique per-token but
  // non-guessable without knowing the internal token row id.
  const storagePath = `${tokenRow.organization_id}/${tokenRow.id}/${safeFileName}`;

  const { data: signedData, error: signedError } = await serviceClient.storage
    .from(BUCKET)
    .createSignedUploadUrl(storagePath);

  if (signedError || !signedData) {
    console.error("[get-justification-upload-url] signed URL error:", signedError);
    return Response.json({ error: "Failed to generate upload URL" }, { status: 500 });
  }

  return Response.json(
    {
      url: signedData.signedUrl,
      storagePath,
    },
    { status: 200 },
  );
});
