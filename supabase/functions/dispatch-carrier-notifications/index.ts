/**
 * Edge Function: dispatch-carrier-notifications (Fase 10.7 - P3)
 * 
 * Drains pending notifications from carrier_notification_outbox and sends them
 * via Resend API. Implements Idempotency (X-Entity-Ref-ID), dual-path backoff,
 * and immutable logging of the verdict communication.
 */

// deno-lint-ignore no-import-prefix
import { createClient } from "jsr:@supabase/supabase-js@2";
import { handleWithSecurity, type SecurityContext } from "../shared/handle_with_security.ts";

function isServiceRoleAuth(authHeader: string, secret: string | undefined): boolean {
  if (!secret) return false;
  const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
  if (token.length !== secret.length) return false;
  let diff = 0;
  for (let i = 0; i < token.length; i++) {
    diff |= token.charCodeAt(i) ^ secret.charCodeAt(i);
  }
  return diff === 0;
}

function formatFine(cents: string | number): string {
  const value = typeof cents === "string" ? parseInt(cents, 10) : cents;
  return new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(value / 100);
}

// A helper for testing injection
export const RESEND_API_URL = "https://api.resend.com/emails";

export async function handler(ctx: SecurityContext, supabase: ReturnType<typeof createClient>, req: Request): Promise<Response> {
  const authHeader = req.headers.get("Authorization") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const resendApiKey = Deno.env.get("RESEND_API_KEY");
  const isCron = isServiceRoleAuth(authHeader, serviceRoleKey);

  if (!isCron && !ctx.orgId) {
    return new Response(JSON.stringify({ error: "Unauthorized kick" }), { status: 401 });
  }

  if (!resendApiKey) {
    return new Response(JSON.stringify({ error: "RESEND_API_KEY missing" }), { status: 500 });
  }

  const queryOrgId = isCron ? null : ctx.orgId;

  // Drain logic via RPC
  // deno-lint-ignore no-explicit-any
  const { data: logs, error: drainErr } = await (supabase as any).rpc("drain_pending_carrier_notifications", {
    p_org_id: queryOrgId,
    p_limit: isCron ? 100 : 10
  });

  if (drainErr || !logs || logs.length === 0) {
    return new Response(JSON.stringify({ ok: true, processed: 0 }), { status: 200, headers: { "Content-Type": "application/json" } });
  }

  let processed = 0;

  for (const log of logs) {
    try {
      const { id, org_id_out, ledger_entry_id, carrier_email, event_type, verdict_outcome, fine_cents, portal_token } = log;
      const organization_id = org_id_out;

      const fineFormatted = formatFine(fine_cents);
      const portalUrl = portal_token ? `https://portal.veraprob.com/disputa/${portal_token}` : "Link indisponível";
      const nowUtc = new Date().toISOString();
      const occId = ledger_entry_id.substring(0, 8); // Short hash for presentation

      // Tom de Voz: Jurídico e Definitivo (INV-UX)
      const textBody = `NOTIFICAÇÃO FORMAL DE VEREDITO SELADO

Ocorrência: #VP-${occId}
Veredito: ${verdict_outcome}
Penalidade apurada: ${fineFormatted}
Data do selo (UTC): ${nowUtc}

O pacote de evidências imutável encontra-se disponível para consulta (somente leitura) em:
${portalUrl}

Este é um registro definitivo emitido pelo motor forense VeraProb. A ausência de manifestação no prazo do SLA não invalida o veredito ora comunicado.`;

      const htmlBody = `
      <div style="font-family: sans-serif; color: #1a1a1a; max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #e0e0e0; border-radius: 8px;">
        <h2 style="margin-top: 0; color: #0F172A; border-bottom: 2px solid #e2e8f0; padding-bottom: 10px;">NOTIFICAÇÃO FORMAL DE VEREDITO SELADO</h2>
        <p><strong>Ocorrência:</strong> #VP-${occId}</p>
        <p><strong>Veredito:</strong> ${verdict_outcome}</p>
        <p><strong>Penalidade apurada:</strong> <span style="color: #b91c1c; font-weight: bold;">${fineFormatted}</span></p>
        <p><strong>Data do selo (UTC):</strong> ${nowUtc}</p>
        <br/>
        <a href="${portalUrl}" style="display: inline-block; padding: 12px 24px; background-color: #0F172A; color: #ffffff; text-decoration: none; border-radius: 4px; font-weight: bold;">Consultar Pacote de Evidências</a>
        <br/><br/>
        <p style="font-size: 12px; color: #64748b; margin-top: 30px; border-top: 1px solid #e2e8f0; padding-top: 10px;">
          Este é um registro definitivo emitido pelo motor forense VeraProb. A ausência de manifestação no prazo do SLA não invalida o veredito ora comunicado.
        </p>
      </div>`;

      // Dispatch via Resend API
      // We inject X-Entity-Ref-ID for native idempotency tracking
      const resendPayload = {
        from: "VeraProb Veredito <veredito@notifications.veraprob.com>",
        to: [carrier_email],
        reply_to: "nao-responda@veraprob.com",
        subject: `NOTIFICAÇÃO FORMAL — Veredito Selado · Ocorrência #VP-${occId}`,
        headers: {
          "X-Entity-Ref-ID": ledger_entry_id,
          "X-VeraProb-Event-Id": id
        },
        tags: [
          { name: "event_type", value: event_type },
          { name: "organization_id", value: organization_id }
        ],
        text: textBody,
        html: htmlBody
      };

      const res = await fetch(RESEND_API_URL, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${resendApiKey}`,
          "Content-Type": "application/json"
        },
        body: JSON.stringify(resendPayload)
      });

      if (res.ok) {
        const result = await res.json();
        // deno-lint-ignore no-explicit-any
        await (supabase as any).from("carrier_notification_outbox")
          .update({ 
            status: 'SENT', 
            resend_message_id: result.id || 'sent-no-id', 
            sent_at: new Date().toISOString() 
          })
          .eq("id", id);
      } else {
        const text = await res.text();
        const errMessage = `HTTP_${res.status}: ${text.substring(0, 100)}`;
        // deno-lint-ignore no-explicit-any
        await (supabase as any).rpc("carrier_notification_fail", { p_notification_id: id, p_org_id: organization_id, p_error: errMessage });
      }
      processed++;
    // deno-lint-ignore no-explicit-any
    } catch (err: any) {
      // deno-lint-ignore no-explicit-any
      await (supabase as any).rpc("carrier_notification_fail", { p_notification_id: log.id, p_org_id: log.org_id_out, p_error: err.message.substring(0, 50) });
    }
  }

  return new Response(JSON.stringify({ ok: true, processed }), { status: 200, headers: { "Content-Type": "application/json" } });
}

if (import.meta.main) {
  Deno.serve(async (req) => {
    const authHeader = req.headers.get("Authorization") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const isCron = isServiceRoleAuth(authHeader, serviceRoleKey);

    if (isCron) {
      return await handleWithSecurity(req, "dispatch-carrier-notifications", handler, false);
    } else {
      return await handleWithSecurity(req, "dispatch-carrier-notifications", handler, true);
    }
  });
}
