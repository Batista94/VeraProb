/**
 * Edge Function: notify-sla-breach — SLA Breach Escalation Notification (5.1, Q3)
 *
 * **Purpose:** Proves escalation to a human with authority. After
 * `flag_sla_breached_disputes()` writes a `DISPUTE_SLA_BREACHED` fact to the
 * ledger, this function sends a Resend email to all TENANT_ADMINs of the
 * affected organization. This is the platform's proof that it didn't merely
 * record the liability — it escalated to someone who can act.
 *
 * **Flow:**
 *  1. Invoked by pg_cron / pg_net (POST, service_role key in Authorization)
 *     or manually triggered by a backend admin.
 *  2. Queries ledger for `DISPUTE_SLA_BREACHED` facts.
 *  3. Checks `system_audit_log` for existing `SLA_BREACH_NOTIFICATION_SENT`
 *     entries to skip already-notified facts (idempotent).
 *  4. For each new fact: fetches org name + TENANT_ADMIN emails.
 *  5. Sends breach notification email via Resend.
 *  6. Logs notification to `system_audit_log` (append-only proof of escalation).
 *
 * **Idempotency:** The ledger (`sla_audit_ledger_v2`) is immutable (INV-3) —
 * we NEVER update it. Instead, we INSERT a `SLA_BREACH_NOTIFICATION_SENT` event
 * into `system_audit_log` with the breach fact's `id` in the payload. On
 * re-run, facts with a matching audit log entry are skipped.
 *
 * **Security:**
 *  - service_role-only: no JWT auth required (infrastructure-to-infrastructure).
 *    Protected by SUPABASE_SERVICE_ROLE_KEY in the Authorization header.
 *
 * **Failure model:** Email is a "plus" channel. If Resend is down, the ledger
 * fact still exists as proof of breach. Re-running the function will retry
 * un-notified facts. No data loss.
 *
 * Invariants: INV-1, INV-3 (ledger NEVER updated — separate audit log),
 *             INV-6 (UTC timestamps), INV-22 (per-org isolation).
 */

import { createClient } from "jsr:@supabase/supabase-js@2";
import { Resend } from "npm:resend@4";
import { signPayload } from "../shared/hmac_signer.ts";

const FROM_ADDRESS = "VeraProb <alertas@resend.dev>";
const NOTIFICATION_EVENT_TYPE = "SLA_BREACH_NOTIFICATION_SENT";

interface BreachedFact {
  id: string;
  organization_id: string;
  payload: {
    queue_entry_id: string;
    resolution_due_at: string;
    breached_at: string;
    disputed_by: string;
    disputed_at: string;
    days_overdue: number;
  };
  occurred_at_utc: string;
}

export async function handler(
  req: Request,
  injectedSupabase?: any,
  injectedResend?: any
): Promise<Response> {
  // CORS preflight
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
    return new Response(
      JSON.stringify({ error: "Method not allowed" }),
      { status: 405, headers: { "Content-Type": "application/json" } },
    );
  }

  // ── Auth: require service_role key ──────────────────────────────────────────
  // This function is infra-to-infra (pg_cron → Edge Function). The service_role
  // key in the Authorization header authenticates the caller. No JWT needed.
  const authHeader = req.headers.get("Authorization") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!serviceRoleKey || !authHeader.includes(serviceRoleKey)) {
    return new Response(
      JSON.stringify({ error: "Unauthorized" }),
      { status: 401, headers: { "Content-Type": "application/json" } },
    );
  }

  const supabase = injectedSupabase || createClient(
    Deno.env.get("SUPABASE_URL")!,
    serviceRoleKey,
  );

  // ── Fetch ALL DISPUTE_SLA_BREACHED facts ────────────────────────────────────
  const { data: facts, error: fetchErr } = await supabase
    .from("sla_audit_ledger_v2")
    .select("id, organization_id, payload, occurred_at_utc")
    .eq("type", "DISPUTE_SLA_BREACHED")
    .order("occurred_at_utc", { ascending: true })
    .limit(100);

  if (fetchErr) {
    console.error("[notify-sla-breach] Ledger query failed:", fetchErr.message);
    return new Response(
      JSON.stringify({ error: "Internal error" }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  if (!facts || facts.length === 0) {
    return new Response(
      JSON.stringify({ ok: true, notified: 0 }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  }

  // ── Filter out already-notified facts via system_audit_log ──────────────────
  // Idempotency: we check if a SLA_BREACH_NOTIFICATION_SENT entry exists for
  // each fact's id. The system_audit_log is NOT immutable (unlike the ledger).
  const factIds = (facts as BreachedFact[]).map((f) => f.id);
  const { data: alreadySent } = await supabase
    .from("system_audit_log")
    .select("payload")
    .eq("event_type", NOTIFICATION_EVENT_TYPE)
    .in("payload->>ledger_fact_id", factIds);

  const sentFactIds = new Set<string>();
  if (alreadySent) {
    for (const entry of alreadySent) {
      const payload = entry.payload as { ledger_fact_id?: string } | null;
      if (payload?.ledger_fact_id) {
        sentFactIds.add(payload.ledger_fact_id);
      }
    }
  }

  const pendingFacts = (facts as BreachedFact[]).filter(
    (f) => !sentFactIds.has(f.id),
  );

  if (pendingFacts.length === 0) {
    return new Response(
      JSON.stringify({ ok: true, notified: 0, message: "All facts already notified" }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  }

  // ── Resend client ───────────────────────────────────────────────────────────
  const resendApiKey = Deno.env.get("RESEND_API_KEY");
  if (!resendApiKey) {
    console.warn("[notify-sla-breach] RESEND_API_KEY not set — skipping send");
    return new Response(
      JSON.stringify({ ok: true, skipped: true }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  }
  const resend = injectedResend || new Resend(resendApiKey);

  // ── Group pending facts by organization ─────────────────────────────────────
  const orgFactsMap = new Map<string, BreachedFact[]>();
  for (const fact of pendingFacts) {
    const existing = orgFactsMap.get(fact.organization_id) ?? [];
    existing.push(fact);
    orgFactsMap.set(fact.organization_id, existing);
  }

  let totalNotified = 0;
  const errors: string[] = [];

  for (const [orgId, orgFacts] of orgFactsMap) {
    // ── Fetch org name ──────────────────────────────────────────────────────
    const { data: org } = await supabase
      .from("organizations")
      .select("name")
      .eq("id", orgId)
      .maybeSingle();
    const orgName = org?.name ?? orgId;

    // ── Fetch TENANT_ADMIN emails via user_roles + auth admin API ────────────
    const { data: adminRoles } = await supabase
      .from("user_roles")
      .select("user_id")
      .eq("organization_id", orgId)
      .eq("role", "TENANT_ADMIN")
      .eq("is_active", true);

    if (!adminRoles || adminRoles.length === 0) {
      console.warn(`[notify-sla-breach] No active TENANT_ADMIN for org ${orgId}`);
      continue;
    }

    // Resolve emails from auth.users via admin API
    const adminEmails: string[] = [];
    for (const role of adminRoles) {
      const { data: userData } = await supabase.auth.admin.getUserById(
        role.user_id,
      );
      if (userData?.user?.email) {
        adminEmails.push(userData.user.email);
      }
    }

    if (adminEmails.length === 0) {
      console.warn(
        `[notify-sla-breach] No emails found for TENANT_ADMINs of org ${orgId}`,
      );
      continue;
    }

    // ── Build and send email ──────────────────────────────────────────────────
    const breachCount = orgFacts.length;
    const breachDetails = orgFacts
      .map((f) => {
        const p = f.payload;
        const daysOverdue = Math.floor(p.days_overdue ?? 0);
        return `<li>Disputa <code>${p.queue_entry_id}</code> — vencida há ${daysOverdue} dia(s)</li>`;
      })
      .join("\n");

    try {
      const { error: sendError } = await resend.emails.send({
        from: FROM_ADDRESS,
        to: adminEmails,
        subject: `⚠️ ${breachCount} disputa(s) com SLA vencido — ${orgName}`,
        html: `
          <div style="font-family:Inter,sans-serif;max-width:560px;margin:auto;padding:24px;">
            <h2 style="color:#DC2626;">⚠️ SLA de Disputa Vencido</h2>
            <p>Organização: <strong>${orgName}</strong></p>
            <p>${breachCount} disputa(s) ultrapassaram o prazo de resolução (SLA) sem decisão:</p>
            <ul style="line-height:1.8;">
              ${breachDetails}
            </ul>
            <p style="margin-top:16px;">
              Acesse o <strong>Painel de Auditoria</strong> na VeraProb para tomar as
              providências necessárias. A resolução de disputas dentro do SLA contratual
              é obrigação da organização contratante.
            </p>
            <hr style="border:none;border-top:1px solid #E5E7EB;margin:24px 0;">
            <p style="color:#9CA3AF;font-size:12px;">
              VeraProb — Plataforma de Auditoria SLA<br>
              Esta é uma notificação automática de escalonamento. Não responda a este e-mail.
            </p>
          </div>
        `,
      });

      if (sendError) {
        console.error(
          `[notify-sla-breach] Resend error for org ${orgId}:`,
          sendError,
        );
        errors.push(`org:${orgId}:send_failed`);
        continue;
      }
    } catch (e) {
      console.error(
        `[notify-sla-breach] Email send threw for org ${orgId}:`,
        e,
      );
      errors.push(`org:${orgId}:exception`);
      continue;
    }

    // ── Log notification to system_audit_log (proof of escalation) ────────────
    // One entry per fact = granular idempotency.
    const now = new Date().toISOString();
    for (const fact of orgFacts) {
      const { error: logErr } = await supabase
        .from("system_audit_log")
        .insert({
          event_type: NOTIFICATION_EVENT_TYPE,
          severity: "info",
          source: "edge_function",
          organization_id: orgId,
          organization_name: orgName,
          actor_type: "SYSTEM",
          payload: {
            ledger_fact_id: fact.id,
            queue_entry_id: fact.payload.queue_entry_id,
            notified_emails: adminEmails,
            sent_at: now,
            integrity_hash: await signPayload({ ledger_fact_id: fact.id, queue_entry_id: fact.payload.queue_entry_id, sent_at: now }), // INV-31
          },
        });

      if (logErr) {
        console.error(
          `[notify-sla-breach] Failed to log notification for fact ${fact.id}:`,
          logErr.message,
        );
        errors.push(`fact:${fact.id}:log_failed`);
      } else {
        totalNotified++;
      }
    }
  }

  return new Response(
    JSON.stringify({
      ok: errors.length === 0,
      notified: totalNotified,
      errors: errors.length > 0 ? errors : undefined,
    }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
}
if (import.meta.main) {
  Deno.serve(handler);
}
