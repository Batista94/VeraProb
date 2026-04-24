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
 *   - download_original_evidence → storage proxy for telegram_evidence
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
  action: "list_tenant_health" | "get_audit_log" | "download_original_evidence";
  params?: AuditLogParams & { evidence_id?: string };
  ticket_id?: string;
  justification?: string;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

// Helper para decode robusto de Base64Url (evita exceptions do atob padrão para tokens com hifens/underscores)
function decodeBase64Url(str: string): string {
  const base64 = str.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64.padEnd(base64.length + ((4 - (base64.length % 4)) % 4), "=");
  return atob(padded);
}

// Helper MIME type mappings
function mimeFromExt(ext: string): string {
  const map: Record<string, string> = {
    jpg: "image/jpeg",
    jpeg: "image/jpeg",
    png: "image/png",
    pdf: "application/pdf",
    mp4: "video/mp4",
    webp: "image/webp",
    heic: "image/heic",
  };
  return map[ext] ?? "application/octet-stream";
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

  // ── Validação de Variáveis de Ambiente (Evita Crash Síncrono / Context Canceled) ──
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !supabaseAnonKey || !supabaseServiceKey) {
    console.error("[super-admin-proxy] Fatal: Missing essential Supabase environment variables.");
    return Response.json({ error: "Internal server error" }, { status: 500 });
  }

  // ── Auth: verify JWT and super_admin claim ──────────────────────────────────
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  }

  // Authenticated client to verify the caller's identity
  const authClient = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  let user;
  try {
    const { data: authData, error: authError } = await authClient.auth.getUser();
    if (authError || !authData.user) {
      return Response.json({ error: "Unauthorized" }, { status: 401 });
    }
    user = authData.user;
  } catch (err) {
    console.error("[super-admin-proxy] Auth verification error:", err);
    return Response.json({ error: "Internal server error" }, { status: 500 });
  }

  const isSuperAdmin = user.app_metadata?.super_admin === true;
  if (!isSuperAdmin) {
    return Response.json({ error: "Forbidden" }, { status: 403 });
  }

  // ── AAL2 enforcement (INV-6: SuperAdmin requires MFA) ─────────────────────
  const token = authHeader.replace("Bearer ", "");
  let jwtPayload: Record<string, unknown>;
  try {
    const payloadB64 = token.split(".")[1];
    if (!payloadB64) throw new Error("Missing JWT payload");
    jwtPayload = JSON.parse(decodeBase64Url(payloadB64));
  } catch (err) {
    console.error("[super-admin-proxy] JWT decode error:", err);
    return Response.json({ error: "Invalid token structure" }, { status: 401 });
  }

  const environment = Deno.env.get("ENVIRONMENT") ?? "production";
  const isLocal = environment === "development" || environment === "dev";

  if (!isLocal && jwtPayload.aal !== "aal2") {
    return Response.json(
      { error: "MFA verification required (AAL2)" },
      { status: 403 }
    );
  }

  // ── Service-role client initialization ─────────────────────────────────────
  const serviceClient = createClient(supabaseUrl, supabaseServiceKey);

  // ── Check MFA lockout (circuit breaker) ───────────────────────────────────
  try {
    const { data: lockoutData, error: lockoutError } = await serviceClient.rpc(
      "check_mfa_lockout",
      { p_user_id: user.id }
    );
    if (lockoutError) throw lockoutError;
    if (lockoutData?.is_locked === true) {
      return Response.json(
        { error: "Account temporarily locked due to failed MFA attempts" },
        { status: 429 }
      );
    }
  } catch (err) {
    console.error("[super-admin-proxy] Lockout check exception:", err);
    return Response.json({ error: "Internal server error" }, { status: 500 });
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

  const ipAddress =
    req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ??
    req.headers.get("x-real-ip") ??
    null;

  // ── Route action (Wrapped to guarantee INV-7 Audit Logging) ────────────────
  let responseToReturn: Response | null = null;
  let actionErrorMsg: string | null = null;
  let responseStatus = 200;

  try {
    if (body.action === "list_tenant_health") {
      const { data, error } = await serviceClient
        .from("super_admin_tenant_health_view")
        .select(
          "id, name, legal_name, plan_type, is_active, max_vehicles, max_active_contracts, active_contract_count, last_telemetry_at, open_critical_alert_count"
        );

      if (error) throw error;
      responseToReturn = Response.json({ data: data ?? [] }, { status: 200 });

    } else if (body.action === "get_audit_log") {
      const params: AuditLogParams = body.params ?? {};
      const limit = Math.min(params.limit ?? 100, 500);

      // Builder: Filters must be applied BEFORE order/limit (PostgrestTransformBuilder bug fix)
      let query = serviceClient
        .from("system_audit_log")
        .select("severity, event_type, occurred_at, organization_id, payload");

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

      // Após todos os filtros, aplicamos os transformadores
      query = query.order("occurred_at", { ascending: false }).limit(limit);

      const { data, error } = await query;
      if (error) throw error;
      responseToReturn = Response.json({ data: data ?? [] }, { status: 200 });

    } else if (body.action === "download_original_evidence") {
      const evidenceId = body.params?.evidence_id;
      if (!evidenceId) {
        responseStatus = 400;
        actionErrorMsg = "Missing evidence_id";
      } else {
        const { data: evidence, error: evError } = await serviceClient
          .from("telegram_evidence_uploads")
          .select("storage_path, file_name")
          .eq("id", evidenceId)
          .maybeSingle();

        if (evError || !evidence) {
          responseStatus = 404;
          actionErrorMsg = "Evidence not found";
        } else {
          const { data: fileData, error: dlError } = await serviceClient.storage
            .from("telegram_evidence")
            .download(evidence.storage_path);

          if (dlError || !fileData) {
            responseStatus = 404;
            actionErrorMsg = "File not found in storage";
          } else {
            const ext = evidence.file_name?.split(".").pop()?.toLowerCase() ?? "";
            const contentType = mimeFromExt(ext);

            responseToReturn = new Response(fileData, {
              status: 200,
              headers: {
                "Content-Type": contentType,
                "Content-Disposition": `attachment; filename="${evidence.file_name}"`,
                "Cache-Control": "no-store, no-cache, must-revalidate",
              },
            });
          }
        }
      }
    } else {
      responseStatus = 400;
      actionErrorMsg = "Unknown action";
    }
  } catch (err) {
    console.error(`[super-admin-proxy] Action execution error (${body.action}):`, err);
    responseStatus = 500;
    actionErrorMsg = "Internal server error";
  }

  // Se não montou um response de sucesso (devido a falhas da ação), retorna o erro padronizado.
  if (!responseToReturn) {
    responseToReturn = Response.json(
      { error: actionErrorMsg ?? "Unknown error" },
      { status: responseStatus }
    );
  }

  // ── Append to immutable access log (INV-7) ──────────────────────────────────
  // Este bloco agora SEMPRE é executado após o processamento da ação,
  // garantindo que não haja brechas (bypass) no registro de auditoria, mesmo em caso de falha.
  try {
    const { error } = await serviceClient
      .from("super_admin_access_log")
      .insert({
        caller_user_id: user.id,
        action: body.action,
        ticket_id: body.ticket_id ?? "NOT_PROVIDED",
        justification: body.justification ?? "",
        ip_address: ipAddress,
        request_params: body.params ?? null,
      });

    if (error) {
      console.error("[super-admin-proxy] Audit log insert failed (DB error):", error);
    }
  } catch (err) {
    console.error("[super-admin-proxy] Audit log insert exception:", err);
  }

  return responseToReturn;
});
