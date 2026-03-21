/**
 * Edge Function: notify-invite
 *
 * Sends an invitation email via Resend when a new user is invited.
 *
 * Security:
 *   - Requires a valid Supabase JWT (authenticated caller).
 *   - RESEND_API_KEY stored in Supabase Secrets — never in client code.
 *
 * Failure model: email is a "plus" channel.
 *   The invitation link is always visible in the UI as a fallback (INV-24).
 *   Callers should invoke fire-and-forget (.catchError) — email failure
 *   must never block the invitation flow.
 *
 * Setup:
 *   1. `supabase secrets set RESEND_API_KEY=re_xxxx`
 *   2. Configure 'from' address below after verifying your domain in Resend.
 *   3. `supabase functions deploy notify-invite`
 *
 * Local testing (Inbucket on port 54324):
 *   `supabase functions serve notify-invite`
 */

import { Resend } from "npm:resend@4";
import { createClient } from "jsr:@supabase/supabase-js@2";

// ── Sender address ────────────────────────────────────────────────────────────
// Sem domínio verificado: use o endereço de teste do Resend (onboarding@resend.dev).
// Quando verificar um domínio próprio, substitua pelo endereço do seu domínio.
// Ex futuro: "VeraProb <convites@veraprob.app>"
const FROM_ADDRESS = "VeraProb <onboarding@resend.dev>";

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

  // ── Auth: require a valid Supabase session JWT ──────────────────────────────
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader) {
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: { user }, error: authError } = await supabase.auth.getUser();
  if (authError || !user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  }

  // ── Parse and validate body ─────────────────────────────────────────────────
  let email: string, inviteUrl: string, orgName: string;
  try {
    ({ email, inviteUrl, orgName } = await req.json());
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  if (!email || !inviteUrl || !orgName) {
    return Response.json(
      { error: "Missing required fields: email, inviteUrl, orgName" },
      { status: 400 },
    );
  }

  // ── Send via Resend ─────────────────────────────────────────────────────────
  const apiKey = Deno.env.get("RESEND_API_KEY");
  if (!apiKey) {
    console.warn("[notify-invite] RESEND_API_KEY not set — skipping send");
    return Response.json({ ok: true, skipped: true }, { status: 200 });
  }

  const resend = new Resend(apiKey);

  const { error: sendError } = await resend.emails.send({
    from: FROM_ADDRESS,
    to: [email],
    subject: `Você foi convidado para ${orgName} na VeraProb`,
    html: `
      <div style="font-family:sans-serif;max-width:480px;margin:auto;padding:24px;">
        <h2 style="color:#1E40AF;">Convite VeraProb</h2>
        <p>Olá,</p>
        <p>Você foi convidado para acessar a plataforma <strong>VeraProb</strong> como
           administrador de <strong>${orgName}</strong>.</p>
        <p style="margin:24px 0;">
          <a href="${inviteUrl}"
             style="background:#1E40AF;color:white;padding:12px 24px;
                    border-radius:6px;text-decoration:none;font-weight:bold;">
            Aceitar Convite e Definir Senha
          </a>
        </p>
        <p style="color:#6B7280;font-size:13px;">
          Este link é de uso único e expira em <strong>7 dias</strong>.
        </p>
        <hr style="border:none;border-top:1px solid #E5E7EB;margin:24px 0;">
        <p style="color:#9CA3AF;font-size:12px;">
          VeraProb — Plataforma de Auditoria SLA
        </p>
      </div>
    `,
  });

  if (sendError) {
    console.error("[notify-invite] Resend error:", sendError);
    return Response.json({ error: "Failed to send email" }, { status: 500 });
  }

  return Response.json({ ok: true }, { status: 200 });
});
