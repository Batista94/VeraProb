/**
 * revoke_impersonation — Revoke an active impersonation session (Stage E)
 *
 * POST /revoke-impersonation
 * Body: { session_id, reason? }
 * Auth: JWT with super_admin claim
 *
 * Sets revoked_at on the impersonation session.
 * The JWT may still be technically valid until exp, but Edge Functions
 * check revoked_at before processing requests.
 */

import { handleWithSecurity, type SecurityContext } from "../shared/handle_with_security.ts";

Deno.serve(async (req) => {
  return await handleWithSecurity(req, "revoke_impersonation", async (ctx: SecurityContext, supabase) => {
    const body = await req.json();
    const { session_id, reason } = body;

    if (!session_id) {
      return new Response(
        JSON.stringify({ error: "session_id is required" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // ── 1. Find the session ──────────────────────────────────────────────
    const { data: session, error: findError } = await supabase
      .from("impersonation_sessions")
      .select("id, impersonator_user_id, target_org_id, revoked_at")
      .eq("id", session_id)
      .single();

    if (findError || !session) {
      return new Response(
        JSON.stringify({ error: "Session not found" }),
        { status: 404, headers: { "Content-Type": "application/json" } },
      );
    }

    if (session.revoked_at) {
      return new Response(
        JSON.stringify({ error: "Session already revoked" }),
        { status: 409, headers: { "Content-Type": "application/json" } },
      );
    }

    // ── 2. Revoke the session ────────────────────────────────────────────
    const { error: updateError } = await supabase
      .from("impersonation_sessions")
      .update({
        revoked_at: new Date().toISOString(),
        revocation_reason: reason || "Manual revocation by super_admin",
      })
      .eq("id", session_id);

    if (updateError) {
      console.error("Failed to revoke session:", updateError);
      return new Response(
        JSON.stringify({ error: "Failed to revoke session" }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    // ── 3. Audit log ─────────────────────────────────────────────────────
    await supabase.from("system_audit_log").insert({
      event_type: "IMPERSONATION_REVOKE",
      severity: "info",
      payload: {
        session_id: session_id,
        impersonator_id: session.impersonator_user_id,
        target_org_id: session.target_org_id,
      },
      source: "edge_function",
      organization_id: session.target_org_id,
      reason: reason || "Manual revocation",
      actor_type: "IMPERSONATOR",
      impersonator_id: session.impersonator_user_id,
    });

    return new Response(
      JSON.stringify({ status: "revoked", session_id }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  });
});
