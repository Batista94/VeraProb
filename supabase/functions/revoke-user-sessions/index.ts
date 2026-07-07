/**
 * revoke-user-sessions — Kill all active sessions for a target user (Stage F)
 *
 * POST /revoke-user-sessions
 * Body: { user_id: string }
 * Auth: Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>
 *       (server-to-server only — called from revoke_user_sessions RPC via pg_net)
 *
 * Calls auth.admin.signOut(userId, 'global') to invalidate all refresh tokens.
 * Writes SESSIONS_REVOKED to system_audit_log for the forensic trail.
 *
 * Invariants: INV-1 (org scoping done at RPC level), INV-21 (audit trail).
 */

// deno-lint-ignore no-import-prefix
import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req: Request) => {
  // ── Guard: only service-role callers (server-to-server via pg_net) ──────────
  const authHeader = req.headers.get("Authorization") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  if (!serviceKey || authHeader !== `Bearer ${serviceKey}`) {
    return new Response(
      JSON.stringify({ error: "Unauthorized" }),
      { status: 401, headers: { "Content-Type": "application/json" } },
    );
  }

  // ── Parse body ───────────────────────────────────────────────────────────────
  let userId: string;
  try {
    const body = await req.json();
    userId = body?.user_id;
    if (!userId || typeof userId !== "string") {
      return new Response(
        JSON.stringify({ error: "user_id is required" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }
  } catch {
    return new Response(
      JSON.stringify({ error: "Invalid JSON body" }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  }

  // ── Service-role client (auth.admin access) ──────────────────────────────────
  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    serviceKey,
    { auth: { persistSession: false } },
  );

  // ── Kill all sessions globally ───────────────────────────────────────────────
  const { error: signOutError } = await supabaseAdmin.auth.admin.signOut(
    userId,
    "global",
  );

  if (signOutError) {
    console.error("revoke-user-sessions: signOut failed", {
      user_id: userId,
      error: signOutError.message,
    });
    return new Response(
      JSON.stringify({ error: "Failed to revoke sessions" }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  // ── Audit log (INV-21, append-only) ─────────────────────────────────────────
  const { error: auditError } = await supabaseAdmin
    .from("system_audit_log")
    .insert({
      event_type: "SESSIONS_REVOKED",
      severity: "info",
      payload: { user_id: userId },
      source: "edge_function",
      occurred_at: new Date().toISOString(),
    });

  if (auditError) {
    // Log but do not fail — revocation already succeeded.
    console.error("revoke-user-sessions: audit insert failed", auditError.message);
  }

  return new Response(
    JSON.stringify({ status: "revoked", user_id: userId }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
});
