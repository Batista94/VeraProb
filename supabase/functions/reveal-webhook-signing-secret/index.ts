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

import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  handleWithSecurity,
  type SecurityContext,
} from "../shared/handle_with_security.ts";
import { sovereigntyErrorResponse } from "../shared/sovereignty_error_mapper.ts";

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
  // 1. Validate TENANT_ADMIN role (INV-1, INV-26).
  // handleWithSecurity só valida JWT e org_id. Role TENANT_ADMIN deve ser
  // verificado manualmente aqui para preservar a semântica de 404 anti-oracle.
  const jwtPayload = await _extractJwtPayload(req);
  if (!jwtPayload) return sovereigntyErrorResponse();

  const appMeta = jwtPayload.app_metadata as Record<string, unknown> | undefined;
  const role = appMeta?.role as string | undefined;
  if (role !== "TENANT_ADMIN") {
    console.error(
      `[reveal-webhook-signing-secret] RBAC violation: role=${role} user=${ctx.userId}`,
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
    .insert({ organization_id: orgId, version: 1, status: "active" })
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
    .update({ status: "retiring", retiring_until: retiringUntil })
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
    })
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

// ── Crypto: derive secret hex ─────────────────────────────────────────────────

/**
 * Recomputa o hex do segredo derivado da org.
 *
 * INV-31: o master nunca sai do env. K_org_vN = HMAC-SHA256(master, orgId|N).
 * O `secret_hex` retornado são os bytes do ArrayBuffer intermediário
 * (ANTES do importKey final — `CryptoKey` não é exportável).
 *
 * Espelha a lógica de deriveOrgKey em hmac_signer.ts sem reimportar o módulo
 * (evitaria importar HMAC_SECRET_KEY_V* neste contexto de reveal).
 */
export async function deriveSecretHex(
  orgId: string,
  version: number,
): Promise<string> {
  const masterRaw = _getMasterKeyRaw();

  const masterKey = await crypto.subtle.importKey(
    "raw",
    masterRaw,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );

  // Deriva: HMAC-SHA256(master, "orgId|version")
  const derived = await crypto.subtle.sign(
    "HMAC",
    masterKey,
    new TextEncoder().encode(`${orgId}|${version}`),
  );

  // secret_hex = hex dos bytes derivados (o que o ERP usa como chave HMAC).
  return Array.from(new Uint8Array(derived))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/**
 * Lê o master key raw do env.
 *
 * PARIDADE OBRIGATÓRIA com hmac_signer.ts loadAllKeys(): o master raw são os
 * bytes UTF-8 do valor do env (TextEncoder), NUNCA hex-decode. Divergir aqui
 * faz o secret revelado não verificar as assinaturas do drain (bug Integridade).
 * Âncora idêntica a deriveOrgKey: version 1 se existir, senão a menor versão.
 *
 * INV-31: master nunca persiste em DB. Apenas disponível no env da edge fn.
 * Throw explícito se ausente — fail-fast antes de qualquer operação.
 */
function _getMasterKeyRaw(): Uint8Array {
  const found: { version: number; raw: Uint8Array }[] = [];
  let version = 1;
  while (true) {
    const keyStr = Deno.env.get(`HMAC_SECRET_KEY_V${version}`);
    if (!keyStr || keyStr.length === 0) break;
    found.push({ version, raw: new TextEncoder().encode(keyStr) });
    version++;
  }
  if (found.length === 0) {
    throw new Error("INV-31: HMAC_SECRET_KEY_V1 not configured in edge fn env");
  }
  const master = found.find((k) => k.version === 1) ?? found[0];
  return master.raw;
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
    });
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

/**
 * Extrai o payload JWT do header Authorization sem verificar assinatura.
 * handleWithSecurity já validou o token; aqui só extraímos claims para role check.
 */
function _extractJwtPayload(
  req: Request,
): Promise<Record<string, unknown> | null> {
  try {
    const auth = req.headers.get("Authorization") ?? "";
    const token = auth.replace(/^Bearer\s+/i, "").trim();
    if (!token) return Promise.resolve(null);

    const parts = token.split(".");
    if (parts.length !== 3) return Promise.resolve(null);

    const payloadB64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const jsonStr = decodeURIComponent(
      atob(payloadB64)
        .split("")
        .map((c) => `%${`00${c.charCodeAt(0).toString(16)}`.slice(-2)}`)
        .join(""),
    );
    return Promise.resolve(JSON.parse(jsonStr) as Record<string, unknown>);
  } catch {
    return Promise.resolve(null);
  }
}
