/**
 * generate_org_secret — Per-Org HMAC Secret Generation (INV-28)
 *
 * POST /generate_org_secret
 * Body: { organization_id: string }
 * Auth: JWT with super_admin claim
 *
 * Generates a cryptographically secure 256-bit secret for an organization.
 * Only the SHA-256 hash is persisted in org_api_secrets.
 * The plain-text secret is returned ONCE in the response and never stored.
 *
 * Rotation: If an active secret exists, it is revoked (revoked_at = NOW())
 * and a new version is created.
 *
 * INV-28: Org Secret Isolation — each org has a unique HMAC secret.
 * INV-9:  Evidence Sealing — HMAC per tenant.
 * INV-3:  Append-only — old secrets are revoked, never deleted.
 */

import { createClient } from "jsr:@supabase/supabase-js@2";
import { handleWithSecurity, type SecurityContext } from "../shared/handle_with_security.ts";

Deno.serve(async (req) => {
  return await handleWithSecurity(req, "generate_org_secret", async (ctx: SecurityContext, supabase) => {
    // ── 1. Parse request body ────────────────────────────────────────────
    const body = await req.json();
    const organizationId = body.organization_id;

    if (!organizationId || typeof organizationId !== "string") {
      return new Response(
        JSON.stringify({ error: "organization_id is required" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // ── 2. Verify organization exists and is not DELETED ─────────────────
    const { data: org, error: orgError } = await supabase
      .from("organizations")
      .select("id, name, status")
      .eq("id", organizationId)
      .single();

    if (orgError || !org) {
      // INV-26: Error Parity — same 404 for not found and wrong org
      return new Response(
        JSON.stringify({ error: "Not found" }),
        { status: 404, headers: { "Content-Type": "application/json" } },
      );
    }

    if (org.status === "DELETED") {
      return new Response(
        JSON.stringify({ error: "Not found" }),
        { status: 404, headers: { "Content-Type": "application/json" } },
      );
    }

    // ── 3. Generate 256-bit cryptographic secret ─────────────────────────
    const secretBytes = new Uint8Array(32);
    crypto.getRandomValues(secretBytes);
    const plainTextSecret = Array.from(secretBytes)
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");

    // ── 4. Compute SHA-256 hash of the secret ───────────────────────────
    const encoder = new TextEncoder();
    const hashBuffer = await crypto.subtle.digest(
      "SHA-256",
      encoder.encode(plainTextSecret),
    );
    const secretHash = Array.from(new Uint8Array(hashBuffer))
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");

    // ── 5. Revoke existing active secret (if any) ───────────────────────
    const { data: existingSecret } = await supabase
      .from("org_api_secrets")
      .select("id, version")
      .eq("organization_id", organizationId)
      .is("revoked_at", null)
      .order("version", { ascending: false })
      .limit(1)
      .maybeSingle();

    const newVersion = existingSecret ? existingSecret.version + 1 : 1;

    if (existingSecret) {
      await supabase
        .from("org_api_secrets")
        .update({
          revoked_at: new Date().toISOString(),
          rotated_at: new Date().toISOString(),
        })
        .eq("id", existingSecret.id);
    }

    // ── 6. Insert new secret (hash only) ─────────────────────────────────
    const { error: insertError } = await supabase
      .from("org_api_secrets")
      .insert({
        organization_id: organizationId,
        secret_hash: secretHash,
        version: newVersion,
      });

    if (insertError) {
      console.error("Failed to insert org_api_secret:", insertError);
      return new Response(
        JSON.stringify({ error: "Failed to generate secret" }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    // ── 7. Audit log ─────────────────────────────────────────────────────
    await supabase.from("system_audit_log").insert({
      event_type: "SECRET_ROTATION",
      severity: "info",
      payload: {
        organization_id: organizationId,
        organization_name: org.name,
        new_version: newVersion,
        previous_version: existingSecret?.version ?? null,
      },
      source: "edge_function",
      organization_id: organizationId,
      organization_name: org.name,
      reason: existingSecret
        ? `Secret rotated from v${existingSecret.version} to v${newVersion}`
        : `Initial secret generated (v${newVersion})`,
      actor_type: "HUMAN",
    });

    // ── 8. Return plain-text secret ONCE ─────────────────────────────────
    return new Response(
      JSON.stringify({
        secret: plainTextSecret,
        version: newVersion,
        organization_id: organizationId,
        message: "Store this secret securely. It will NOT be shown again.",
      }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      },
    );
  });
});
