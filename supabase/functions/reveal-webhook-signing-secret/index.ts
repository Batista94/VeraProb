/**
 * reveal-webhook-signing-secret — Edge Function (Fase 10.7, P1).
 *
 * IAM (INV-1, INV-26, INV-28, INV-31):
 *   - Valida JWT via handleWithSecurity (requireAuth: true, sem AAL2 — Fase 11)
 *   - Valida role TENANT_ADMIN no app_metadata do JWT (→ 404 se não — INV-26)
 *   - org_id derivado exclusivamente do JWT claim (INV-1 — imutável pelo cliente)
 *   - Nenhum material de chave persiste em DB (INV-31). DB guarda só version/status.
 *
 * Actions:
 *   - "provision": cria a 1ª webhook_signing_keys active e retorna
 *                  { secret_hex, version } UMA ÚNICA VEZ. Se já existe chave
 *                  ativa → 409 ALREADY_PROVISIONED (reveal-once estrito;
 *                  perdeu a chave = rotaciona).
 *   - "rotate":    active → retiring (retiring_until = NOW()+30min), insere nova active (version+1),
 *                  recomputa, retorna UMA VEZ.
 *   - qualquer outro valor: negado (404 anti-oracle — INV-26).
 *
 * Audit: insere WEBHOOK_SECRET_REVEALED ou WEBHOOK_SECRET_ROTATED em system_audit_log.
 *
 * Feature-flag: REQUIRE_AAL2_TENANT_SECRET (default "false").
 * // TODO Fase 11: MFA Tenant — ligar o step-up AAL2 quando enrolment de tenant for entregue.
 */

// deno-lint-ignore no-import-prefix
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  handleWithSecurity,
  type SecurityContext,
} from "../shared/handle_with_security.ts";
import { sovereigntyErrorResponse } from "../shared/sovereignty_error_mapper.ts";
import { deriveOrgKeyHex } from "../shared/hmac_signer.ts";

// ── Types ─────────────────────────────────────────────────────────────────────

type Action = "provision" | "rotate";

interface RevealResponse {
  secret_hex: string;
  version: number;
}

// ── Entry point ───────────────────────────────────────────────────────────────

if (import.meta.main) {
  Deno.serve(async (req: Request) => {
    return await handleWithSecurity(
      req,
      "reveal-webhook-signing-secret",
      handleReveal,
      /* requireAuth */ true,
      /* requireSuperAdmin */ false,
      /* requireAAL2 */ false,
      // TODO Fase 11: substituir por `Deno.env.get("REQUIRE_AAL2_TENANT_SECRET") === "true"`
    );
  });
}

// ── Handler ───────────────────────────────────────────────────────────────────

/** Exportado para testes unitários (padrão dispatch-*). */
export async function handleReveal(
  ctx: SecurityContext,
  supabase: ReturnType<typeof createClient>,
  req: Request,
): Promise<Response> {
  // 1. Validate TENANT_ADMIN from verified SecurityContext (INV-1, INV-26).
  // Role comes from crypto-verified JWT claims via handleWithSecurity — never
  // re-decode the Bearer token here.
  if (ctx.role !== "TENANT_ADMIN") {
    console.error(
      `[reveal-webhook-signing-secret] RBAC violation: role=${ctx.role} user=${ctx.userId}`,
    );
    return sovereigntyErrorResponse(); // INV-26: indistinguível de 404
  }

  // 2. org_id do JWT (imutável — INV-1).
  const orgId = ctx.orgId;
  if (!orgId) return sovereigntyErrorResponse();

  // 3. Parse action.
  let action: Action;
  try {
    const body = await req.clone().json() as { action?: string };
    const raw = body?.action;
    if (raw !== "provision" && raw !== "rotate") {
      // "reveal" direto é negado explicitamente (plano: só nasce no provision/rotate).
      return sovereigntyErrorResponse();
    }
    action = raw;
  } catch {
    return sovereigntyErrorResponse();
  }

  // 4. Execute the action.
  if (action === "provision") {
    return await handleProvision(orgId, ctx.userId!, supabase);
  }
  return await handleRotate(orgId, ctx.userId!, supabase);
}

// ── Provision ─────────────────────────────────────────────────────────────────

async function handleProvision(
  orgId: string,
  userId: string,
  supabase: ReturnType<typeof createClient>,
): Promise<Response> {
  // Busca a chave ativa (service_role bypassa RLS).
  const existing = await _fetchActiveKey(orgId, supabase);

  // Reveal-once ESTRITO: chave ativa já existe → o material só nasceu no
  // provision/rotate original e NUNCA é re-exibido. Se perdeu, rotaciona.
  // 409 é seguro aqui: o caller já provou pertencer à org (INV-26 protege
  // cross-org, não o estado da própria org).
  if (existing) {
    return new Response(JSON.stringify({ error: "ALREADY_PROVISIONED" }), {
      status: 409,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Sem chave ativa: provisiona version 1.
  // ponytail: SELECT-then-INSERT race é aceitável aqui — o partial UNIQUE index
  // (WHERE status='active') é o guard real. Em corrida concorrente, um lado
  // ganha e o perdedor (23505) recebe 409 — o vencedor já viu o segredo.
  const { data: inserted, error: insErr } = await supabase
    .from("webhook_signing_keys")
    .insert(
      { organization_id: orgId, version: 1, status: "active" } as never,
    )
    .select("id, version")
    .maybeSingle();

  if (insErr) {
    const winner = await _fetchActiveKey(orgId, supabase);
    if (winner) {
      return new Response(JSON.stringify({ error: "ALREADY_PROVISIONED" }), {
        status: 409,
        headers: { "Content-Type": "application/json" },
      });
    }
    console.error("[reveal-webhook-signing-secret] provision insert failed");
    return sovereigntyErrorResponse();
  }

  const key = inserted as ActiveKey | null;
  if (!key) {
    console.error("[reveal-webhook-signing-secret] provision key fetch failed");
    return sovereigntyErrorResponse();
  }

  const secretHex = await deriveSecretHex(orgId, key.version as number);

  // Audit log WEBHOOK_SECRET_REVEALED (service_role, append-only).
  await _auditLog(supabase, orgId, userId, "WEBHOOK_SECRET_REVEALED", {
    key_version: key.version,
    action: "provision",
  });

  return _successResponse({ secret_hex: secretHex, version: key.version as number });
}

// ── Rotate ────────────────────────────────────────────────────────────────────

async function handleRotate(
  orgId: string,
  userId: string,
  supabase: ReturnType<typeof createClient>,
): Promise<Response> {
  // Busca a chave ativa atual.
  const currentKey = await _fetchActiveKey(orgId, supabase);

  if (!currentKey) {
    // Sem chave ativa: redireciona para provision semanticamente.
    return handleProvision(orgId, userId, supabase);
  }

  const currentVersion = currentKey.version as number;
  const newVersion = currentVersion + 1;

  // Grace period de 30 minutos para o drain assinar pendentes com a chave antiga.
  const retiringUntil = new Date(Date.now() + 30 * 60 * 1000).toISOString();

  // Transição: active → retiring.
  const { error: retireErr } = await supabase
    .from("webhook_signing_keys")
    .update(
      { status: "retiring", retiring_until: retiringUntil } as never,
    )
    .eq("id", currentKey.id);

  if (retireErr) {
    console.error(`[reveal-webhook-signing-secret] retire failed: ${retireErr.message}`);
    return sovereigntyErrorResponse();
  }

  // Insere nova active (version+1).
  const { data: newKey, error: insertErr } = await supabase
    .from("webhook_signing_keys")
    .insert({
      organization_id: orgId,
      version: newVersion,
      status: "active",
    } as never)
    .select("id, version")
    .single();

  if (insertErr || !newKey) {
    console.error(`[reveal-webhook-signing-secret] new key insert failed: ${insertErr?.message}`);
    return sovereigntyErrorResponse();
  }

  const secretHex = await deriveSecretHex(orgId, newVersion);

  await _auditLog(supabase, orgId, userId, "WEBHOOK_SECRET_ROTATED", {
    previous_version: currentVersion,
    new_version: newVersion,
    retiring_until: retiringUntil,
    action: "rotate",
  });

  return _successResponse({ secret_hex: secretHex, version: newVersion });
}

// ── Key lookup ────────────────────────────────────────────────────────────────

interface ActiveKey {
  id: string;
  version: number;
}

/** Retorna a chave `active` da org, ou null. service_role bypassa RLS. */
async function _fetchActiveKey(
  orgId: string,
  supabase: ReturnType<typeof createClient>,
): Promise<ActiveKey | null> {
  const { data } = await supabase
    .from("webhook_signing_keys")
    .select("id, version")
    .eq("organization_id", orgId)
    .eq("status", "active")
    .maybeSingle();
  return (data as ActiveKey | null) ?? null;
}

/**
 * Recomputa o hex do segredo derivado da org (INV-31).
 * Delegates to hmac_signer.deriveOrgKeyHex — single SSOT for K_org_vN.
 */
export async function deriveSecretHex(
  orgId: string,
  version: number,
): Promise<string> {
  return await deriveOrgKeyHex(orgId, version);
}

// ── Audit log ─────────────────────────────────────────────────────────────────

async function _auditLog(
  supabase: ReturnType<typeof createClient>,
  orgId: string,
  userId: string,
  eventType: string,
  payload: Record<string, unknown>,
): Promise<void> {
  try {
    await supabase.from("system_audit_log").insert({
      event_type: eventType,
      severity: "info",
      source: "edge_function",
      organization_id: orgId,
      payload: { user_id: userId, ...payload },
    } as never);
  } catch (e) {
    // Falha no audit nunca bloqueia o reveal (mas é logada).
    console.error(`[reveal-webhook-signing-secret] audit log failed: ${e}`);
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function _successResponse(data: RevealResponse): Response {
  return new Response(JSON.stringify(data), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}
