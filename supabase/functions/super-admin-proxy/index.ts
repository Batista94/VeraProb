/**
 * Edge Function: super-admin-proxy
 *
 * Secure server-side proxy for SuperAdmin read operations.
 *
 * Security model (INV-3, INV-6, INV-14):
 *   - SUPABASE_SERVICE_ROLE_KEY is a Deno secret — it NEVER exists in the
 *     Flutter bundle. The client only sends its JWT.
 *   - JWT is validated server-side via auth.getUser() before any data access.
 *   - Caller must have app_metadata.super_admin === true (AAL check in guard).
 *   - Every invocation is appended to super_admin_access_log (INV-7).
 *
 * Supported actions:
 *   - list_tenant_health  → super_admin_tenant_health_view
 *   - get_audit_log       → system_audit_log (with optional filters)
 *
 * Setup:
 *   1. `supabase secrets set SUPABASE_SERVICE_ROLE_KEY=<key>`
 *   2. `supabase functions deploy super-admin-proxy`
 */

import { createClient } from "jsr:@supabase/supabase-js@2";

// ── Types ─────────────────────────────────────────────────────────────────────

interface AuditLogParams {
  organization_id?: string;
  severity?: string;
  from_date?: string;
  to_date?: string;
  limit?: number;
}

interface RequestBody {
  action: "list_tenant_health" | "get_audit_log";
  params?: AuditLogParams;
  ticket_id?: string;
  justification?: string;
}

// ── Handler ───────────────────────────────────────────────────────────────────

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

  // ── Auth: verify JWT and super_admin claim ──────────────────────────────────
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  }

  // Authenticated client to verify the caller's identity (uses anon key +
  // forwarded JWT — never grants cross-tenant access).
  const authClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: { user }, error: authError } = await authClient.auth.getUser();
  if (authError || !user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  }

  // Verify super_admin flag in app_metadata (set by DB trigger on user creation).
  const isSuperAdmin = user.app_metadata?.super_admin === true;
  if (!isSuperAdmin) {
    return Response.json({ error: "Forbidden" }, { status: 403 });
  }

  // ── Parse request body ─────────────────────────────────────────────────────
  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  if (!body.action) {
    return Response.json({ error: "Missing required field: action" }, { status: 400 });
  }

  // ── Service-role client (server-side only — never sent to client) ───────────
  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // ── Extract caller IP for audit log ────────────────────────────────────────
  const ipAddress =
    req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ??
    req.headers.get("x-real-ip") ??
    null;

  // ── Route action ───────────────────────────────────────────────────────────
  let rows: unknown[] = [];

  try {
    if (body.action === "list_tenant_health") {
      const { data, error } = await serviceClient
        .from("super_admin_tenant_health_view")
        .select(
          "id, name, legal_name, plan_type, is_active, max_vehicles, max_active_contracts, active_contract_count, last_telemetry_at, open_critical_alert_count",
        );

      if (error) throw error;
      rows = data ?? [];
    } else if (body.action === "get_audit_log") {
      const params: AuditLogParams = body.params ?? {};
      const limit = Math.min(params.limit ?? 100, 500);

      let query = serviceClient
        .from("system_audit_log")
        .select("severity, event_type, occurred_at, organization_id, payload")
        .order("occurred_at", { ascending: false })
        .limit(limit);

      if (params.organization_id) {
        query = query.eq("organization_id", params.organization_id);
      }
      if (params.severity) {
        query = query.eq("severity", params.severity);
      }
      if (params.from_date) {
        query = query.gte("occurred_at", params.from_date);
      }
      if (params.to_date) {
        query = query.lte("occurred_at", params.to_date);
      }

      const { data, error } = await query;
      if (error) throw error;
      rows = data ?? [];
    } else {
      return Response.json({ error: "Unknown action" }, { status: 400 });
    }
  } catch (err) {
    console.error("[super-admin-proxy] query error:", err);
    return Response.json({ error: "Internal server error" }, { status: 500 });
  }

  // ── Append to immutable access log (INV-7) ──────────────────────────────────
  // Fire-and-forget — log failure must never block data access.
  serviceClient
    .from("super_admin_access_log")
    .insert({
      caller_user_id: user.id,
      action: body.action,
      ticket_id: body.ticket_id ?? "NOT_PROVIDED",
      justification: body.justification ?? "",
      ip_address: ipAddress,
      request_params: body.params ?? null,
    })
    .then(({ error }) => {
      if (error) {
        console.error("[super-admin-proxy] audit log insert failed:", error);
      }
    });

  return Response.json({ data: rows }, { status: 200 });
});
