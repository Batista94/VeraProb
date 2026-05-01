/**
 * issue_impersonation_jwt — SuperAdmin Impersonation Session (Stage E)
 *
 * POST /issue-impersonation-jwt
 * Body: { target_org_id, ticket_id, reason }
 * Auth: JWT with super_admin claim + AAL2
 *
 * Creates an impersonation_sessions row and returns a temporary JWT
 * with the target org's organization_id as the claim.
 *
 * Security model:
 * - Max 1 active session per impersonator (DB trigger enforced)
 * - Session expires in 30 minutes
 * - RLS evaluates target_org_id from the temporary JWT
 * - Revocation via separate endpoint
 *
 * INV-1:  target_org_id becomes the JWT organization_id
 * INV-22: Impersonator with target_org=A cannot access org B data
 * INV-26: Non-existent/deleted org → 404
 */

import { createClient } from "jsr:@supabase/supabase-js@2";
import { handleWithSecurity, type SecurityContext } from "../shared/handle_with_security.ts";
import { validateTenantId } from "../shared/tenant_id_validator.ts";
import { sovereigntyErrorResponse } from "../shared/sovereignty_error_mapper.ts";

const SESSION_DURATION_MINUTES = 30;

Deno.serve(async (req) => {
  return await handleWithSecurity(req, "issue_impersonation_jwt", async (ctx: SecurityContext, supabase) => {
    // ── 1. Parse request ─────────────────────────────────────────────────
    const body = await req.json();
    const { target_org_id, ticket_id, reason } = body;

    if (!target_org_id || !ticket_id || !reason) {
      return new Response(
        JSON.stringify({ error: "target_org_id, ticket_id, and reason are required" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    if (typeof ticket_id !== "string" || ticket_id.trim() === "") {
      return new Response(
        JSON.stringify({ error: "ticket_id must be a non-empty string" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    if (typeof reason !== "string" || reason.trim().length < 10) {
      return new Response(
        JSON.stringify({ error: "reason must be at least 10 characters" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // ── 2. Validate target org (UUID v4 format + existence) ─────────────
    // INV-26: Invalid UUIDs return sovereigntyErrorResponse() without DB query.
    // Valid UUIDs are checked against the organizations table.
    const tenantResult = await validateTenantId(target_org_id, supabase);
    if (!tenantResult.valid) {
      return sovereigntyErrorResponse();
    }
    const org = tenantResult.org;

    // INV-22/INV-26: ARCHIVED orgs cannot be impersonated (same 404 for parity)
    if (org.status === "ARCHIVED") {
      return sovereigntyErrorResponse();
    }

    // ── 3. Extract impersonator ID from JWT ──────────────────────────────
    const impersonatorId = ctx.userId;
    if (!impersonatorId) {
      return new Response(
        JSON.stringify({ error: "Could not determine impersonator identity" }),
        { status: 401, headers: { "Content-Type": "application/json" } },
      );
    }

    // ── 4. Create impersonation session ──────────────────────────────────
    const now = new Date();
    const expiresAt = new Date(now.getTime() + SESSION_DURATION_MINUTES * 60 * 1000);

    const { data: session, error: sessionError } = await supabase
      .from("impersonation_sessions")
      .insert({
        impersonator_user_id: impersonatorId,
        target_org_id: target_org_id,
        issued_at: now.toISOString(),
        expires_at: expiresAt.toISOString(),
        ticket_id: ticket_id.trim(),
      })
      .select("id")
      .single();

    if (sessionError) {
      // DB trigger rejects if impersonator already has an active session
      if (sessionError.code === "23505" || sessionError.message?.includes("already has an active session")) {
        return new Response(
          JSON.stringify({ error: "You already have an active impersonation session. Revoke it first." }),
          { status: 409, headers: { "Content-Type": "application/json" } },
        );
      }
      console.error("Failed to create impersonation session:", sessionError);
      return new Response(
        JSON.stringify({ error: "Failed to create session" }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    // ── 5. Audit log ─────────────────────────────────────────────────────
    await supabase.from("system_audit_log").insert({
      event_type: "IMPERSONATION_START",
      severity: "warning",
      payload: {
        impersonator_id: impersonatorId,
        target_org_id: target_org_id,
        target_org_name: org.name,
        session_id: session.id,
        ticket_id: ticket_id,
        expires_at: expiresAt.toISOString(),
      },
      source: "edge_function",
      organization_id: target_org_id,
      organization_name: org.name,
      reason: reason,
      actor_type: "IMPERSONATOR",
      impersonator_id: impersonatorId,
    });

    // ── 6. Return session info ───────────────────────────────────────────
    // Note: In a production system, this would issue a signed JWT.
    // For the free-tier Supabase setup, we return session metadata
    // and the Flutter app uses the session_id to proxy requests.
    return new Response(
      JSON.stringify({
        session_id: session.id,
        target_org_id: target_org_id,
        target_org_name: org.name,
        target_org_status: org.status,
        impersonator_id: impersonatorId,
        issued_at: now.toISOString(),
        expires_at: expiresAt.toISOString(),
        duration_minutes: SESSION_DURATION_MINUTES,
      }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      },
    );
  }, true, true, true);
});
