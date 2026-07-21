# Phase 11 — Inventário 1:1 das Edge Functions (Etapa −1)

**Date:** 2026-07-21  
**Status:** Proposed (inventário contratual; **não** Accepted)  
**Commit baseline:** `4d4786516c5d2800aad8873e3633faa750f067bb`  
**collected_at:** `2026-07-21T19:34:21Z`  
**Branch de coleta:** `feat/roi-simulator-ui`  
**SSOT siblings:** [phase11_enterprise_pivot.md](phase11_enterprise_pivot.md), [phase11_threat_model.md](phase11_threat_model.md), [phase11_parity_checklist.md](phase11_parity_checklist.md), [ADR-010](../adr/010_exit_supabase.md), [ADR-011](../adr/011_auth_zero_trust.md), [ADR-012](../adr/012_rls_connection_lifecycle.md), [ADR-013](../adr/013_strangler_fig.md)

> **Destino candidato** neste documento é **candidatura** (ADR-013 §3), não fato Accepted. Cutover/decommission só após gates do [parity checklist](phase11_parity_checklist.md).

---

## 1. Critério de inclusão (Set A)

| Regra | Valor |
|-------|-------|
| Critério | Diretório filho imediato de `supabase/functions/` que contém `index.ts` |
| Exclusões | `shared/`, `tests/`, `node_modules/` (e quaisquer dirs sem `index.ts`) |
| Contagem | **22** funções |
| Fonte | filesystem no commit acima, `collected_at` UTC |

### Set A (22 nomes, ordenados)

`auditor-dispute-evidence`, `dispatch-carrier-notifications`, `dispatch-verdict-webhooks`, `dispute-portal-evidence`, `generate-org-secret`, `get-justification-upload-url`, `ingest-omnitracs`, `ingest-sascar`, `issue-impersonation-jwt`, `log-security-incident`, `notify-invite`, `notify-sla-breach`, `portal-finalize-upload`, `portal-submit-request`, `reveal-webhook-signing-secret`, `revoke-impersonation`, `revoke-user-sessions`, `secure-evidence-proxy`, `super-admin-proxy`, `telegram-webhook`, `verify-evidence-hash`, `verify-ledger-hmac`

---

## 2. Prova de completude

| Conjunto | Definição | Resultado |
|----------|-----------|-----------|
| **A** | Set A (critério §1) | 22 nomes |
| **B** | Mesmo critério reaplicado na coleta | 22 nomes idênticos |
| **A − B** | Funções em A ausentes em B | **∅ (vazio)** |
| **B − A** | Funções em B ausentes em A | **∅ (vazio)** |
| Unicidade | Sem duplicatas de nome de diretório | **OK** |

Inventário **completo** sob o critério declarado. Qualquer função Edge futura fora deste critério exige revisão deste artefato (ainda Proposed).

---

## 3. Divergências e config de gateway

### 3.1 Migrations (lift-and-shift)

| Fonte | Contagem |
|-------|----------|
| Plano histórico Phase 11 (texto “365 migrations”) | 365 |
| Contagem real `supabase/migrations/*.sql` na coleta | **377** |
| Divergência | **+12** — registrar; **não** inventar schema redesign. Lift-and-shift usa a contagem real no cutover de dados. |

### 3.2 `verify_jwt` em `supabase/config.toml`

| Função | `verify_jwt` |
|--------|--------------|
| `ingest-sascar` | **false** (API key de provider) |
| `super-admin-proxy` | **false** (HMAC INV-31 + AAL2 manual; parity INV-26) |
| `telegram-webhook` | **false** (secret Telegram, não JWT) |
| Demais 19 | **default true** (sem override) |

**FINDING (T-28 / PG-INGEST):** `ingest-omnitracs` autentica por **API key** (paridade de desenho com `ingest-sascar`) mas **não** tem `[functions.ingest-omnitracs] verify_jwt = false`. Gateway default pode interceptar Bearer de provider com 401 antes do handler. Remediação candidata: alinhar config **ou** documentar override de deploy — não tratar como Accepted.

### 3.3 Notas transversais (JWT P0)

| Tema | Fato |
|------|------|
| `getClaims` | Residual: logout/ban podem não refletir até `exp` (`jwt_auth_validator` / ADR-011) |
| Dual-path `dispatch-*` | Cron: Bearer `SUPABASE_SERVICE_ROLE_KEY` → `handleWithSecurity(..., requireAuth=false)`; kick tenant: JWT → `requireAuth=true` |
| Secrets runtime (`[edge_runtime.secrets]`) | `ENVIRONMENT`, `HMAC_SECRET_KEY_V1`, `TELEGRAM_WEBHOOK_SECRET` (+ por função `SUPABASE_*`, `RESEND_API_KEY`, `TELEGRAM_BOT_TOKEN`, `SENTRY_DSN`, `APP_ENV`) |

---

## 4. Matriz resumida (candidatura)

| Função | Auth/gateway | Fatia ADR-013 | Destino candidato | AAL2 | Teste Deno dedicado |
|--------|--------------|---------------|-------------------|------|---------------------|
| `revoke-user-sessions` | service_role exact Bearer | 1 Auth | `apps/api` handler | N/A | ❌ |
| `issue-impersonation-jwt` | handleWithSecurity + SA + AAL2 | 1 (uso↔6) | `apps/api` handler | Yes | ❌ |
| `revoke-impersonation` | handleWithSecurity + SA | 1 (uso↔6) | `apps/api` handler | Yes | ❌ |
| `log-security-incident` | handleWithSecurity (qualquer JWT) | 1 ou 6 | `apps/api` handler | No | ✅ + PBT |
| `generate-org-secret` | handleWithSecurity SA+AAL2 | 2 | **deferred** (retirada) | Yes | ❌ |
| `verify-ledger-hmac` | handleWithSecurity JWT | 2 | `apps/api` handler | No | ❌ |
| `ingest-sascar` | provider API key; `verify_jwt=false` | 2 | `apps/api` handler | N/A | shared only |
| `ingest-omnitracs` | provider API key; **JWT gap** | 2 | `apps/api` handler | N/A | shared only |
| `secure-evidence-proxy` | handleWithSecurity JWT | 3 | storage service / `apps/api` | No | shared EXIF |
| `verify-evidence-hash` | stub 404 | 3 | **deferred** (stub) | N/A | ✅ stub |
| `get-justification-upload-url` | token + service_role | 3 | storage service | N/A | ❌ |
| `portal-finalize-upload` | portal token + service_role | 3 | storage / `apps/api` | N/A | ✅ |
| `portal-submit-request` | portal token + service_role | 3 | `apps/api` / storage | N/A | ✅ |
| `dispute-portal-evidence` | portal token + service_role | 3 | storage / `apps/api` | N/A | ❌ |
| `auditor-dispute-evidence` | handleWithSecurity; ADMIN/AUDITOR | 3–4 | `apps/api` / storage | No | ✅ |
| `notify-invite` | anon + `auth.getUser` | 5 | worker | No | ❌ |
| `notify-sla-breach` | service_role Bearer | 5 | worker | N/A | ✅ |
| `dispatch-carrier-notifications` | dual-path | 5 | worker | No | ✅ |
| `dispatch-verdict-webhooks` | dual-path | 5 | worker | No | ✅ |
| `telegram-webhook` | Telegram secret; `verify_jwt=false` | 5 | worker / `apps/api` | N/A | ✅ integration |
| `reveal-webhook-signing-secret` | handleWithSecurity; **AAL2=false** | 5–6 | `apps/api` handler | **No (P0)** | ✅ |
| `super-admin-proxy` | manual JWT+HMAC; `verify_jwt=false` | 6 | `apps/api` handler | Yes | ✅ integration |

---

## 5. Seções por função (22/22)

Campos obrigatórios do plano validado: `nome`, `responsabilidade`, `trigger`, `consumidores`, `autenticação/gateway`, `claims`, `roles`, `service_role`, `tabelas/views/RPCs`, `efeitos externos`, `dados sensíveis/secrets`, `invariantes`, `testes existentes`, `observabilidade`, `dependências`, `destino candidato` + justificativa, `ordem migração`, `risco`, `critério paridade`, `rollback`, `desligamento`.

### 5.1 `auditor-dispute-evidence`

| Campo | Valor |
|-------|-------|
| nome | `auditor-dispute-evidence` |
| responsabilidade | Serve contra-evidência de disputa com EXIF strip e RBAC; lookup org-scoped em `dispute_evidence_attachments`; download bucket `dispute_evidence`. |
| trigger | GET `?attachment_id=`; OPTIONS CORS |
| consumidores | Flutter UI via `EvidenceUrlService.auditorDisputeEvidenceUrl()` (cards tribunal) |
| autenticação/gateway | `handleWithSecurity` (JWT `getClaims`); gateway JWT default true |
| claims | `organization_id` + `app_metadata.role` |
| roles | `TENANT_ADMIN` ou `AUDITOR` |
| service_role | Sim — client interno via wrapper (reads/storage) |
| tabelas/views/RPCs | `dispute_evidence_attachments`; Storage `dispute_evidence` |
| efeitos externos | Storage download; EXIF strip JPEG |
| dados sensíveis/secrets | `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` |
| invariantes | INV-1, INV-9, INV-18, INV-26 |
| testes existentes | `tests/auditor_dispute_evidence_unit_test.ts`; shared `exif_stripper_test.ts` |
| observabilidade | Sentry via `handleWithSecurity` em erro infra; `X-Correlation-Id` |
| dependências | `shared/handle_with_security`, `evidence_serve`, `sovereignty_error_mapper` |
| destino candidato | `apps/api` handler **ou** storage service — candidatura: serve autenticado de blob org-bound |
| ordem migração | Fatia **3** Evidence (habilitação read pode estender à **4**) |
| risco | Leak de evidência cross-tenant / oracle INV-26 |
| critério paridade | PG-EVIDENCE, PG-INV26; byte/headers iguais ao Edge |
| rollback | Flag rota → Edge; manter bucket legado |
| desligamento | Após dual-run PASS + zero callers Flutter; marcar `decommissioned` no inventário |

### 5.2 `dispatch-carrier-notifications`

| Campo | Valor |
|-------|-------|
| nome | `dispatch-carrier-notifications` |
| responsabilidade | Drena `carrier_notification_outbox` via RPC; e-mail formal Resend com idempotência `X-Entity-Ref-ID` e backoff |
| trigger | POST (cron ou kick) |
| consumidores | Cron/worker service_role; sem invoke Flutter em `lib/` |
| autenticação/gateway | Dual-path: `isServiceRoleAuth` **ou** `handleWithSecurity` JWT |
| claims | Cron: nenhum; kick: JWT com `organization_id` |
| roles | Kick: tenant autenticado |
| service_role | Sim — auth cron + client/RPC |
| tabelas/views/RPCs | `drain_pending_carrier_notifications`, `carrier_notification_fail`; `carrier_notification_outbox` |
| efeitos externos | Resend `api.resend.com/emails`; links `portal.veraprob.com/disputa/{token}` |
| dados sensíveis/secrets | `SUPABASE_SERVICE_ROLE_KEY`, `RESEND_API_KEY` |
| invariantes | INV-3 (outbox); tom jurídico template |
| testes existentes | `tests/dispatch_carrier_notifications_unit_test.ts` |
| observabilidade | Logs de erro Resend; sem Sentry dedicado |
| dependências | `handle_with_security`, `service_role_auth` |
| destino candidato | **worker** — side-effect de e-mail/outbox (não handler síncrono OCC) |
| ordem migração | Fatia **5** Workers |
| risco | Dual-write outbox; spam; loss de idempotência |
| critério paridade | PG-WEBHOOK/notify: exatamente-um owner; Resend message-id auditável |
| rollback | Pausar worker novo; cron Edge retoma drain |
| desligamento | Outbox vazia estável + flag off Edge |

### 5.3 `dispatch-verdict-webhooks`

| Campo | Valor |
|-------|-------|
| nome | `dispatch-verdict-webhooks` |
| responsabilidade | Drain dual-path de webhooks; anti-SSRF; cross-verify `fine_cents` vs ledger; HMAC per-org; POST HTTPS |
| trigger | POST |
| consumidores | GHA `.github/workflows/webhook-dispatch.yml`; Flutter `SupabaseWebhookDispatchKicker` |
| autenticação/gateway | Dual-path (service_role **ou** JWT + rate limit kick) |
| claims | Kick: JWT tenant; rate `webhook_endpoints.last_kick_at` (30s) |
| roles | Tenant autenticado no kick |
| service_role | Sim |
| tabelas/views/RPCs | `drain_pending_webhooks`, `webhook_delivery_fail`; `webhook_endpoints`, `webhook_delivery_logs`, `sla_audit_ledger_v2`, `system_audit_log` |
| efeitos externos | HTTPS outbound; audit `PAYLOAD_TAMPERED` |
| dados sensíveis/secrets | `SUPABASE_SERVICE_ROLE_KEY`, `HMAC_SECRET_KEY_V1` |
| invariantes | INV-3, INV-4, INV-15, INV-28, INV-31 |
| testes existentes | `tests/dispatch_verdict_webhooks_unit_test.ts`; Dart kicker test |
| observabilidade | `system_audit_log` critical; console SSRF DEAD |
| dependências | `handle_with_security`, `service_role_auth`, `canonical_json`, `hmac_signer` |
| destino candidato | **worker** — owner único de side-effect webhook |
| ordem migração | Fatia **5** |
| risco | SSRF, forge HMAC, dual delivery |
| critério paridade | PG-WEBHOOK, PG-HMAC, PG-MONEY |
| rollback | Pause outbox drain novo; workflow Edge |
| desligamento | Após shadow compare delivery logs |

### 5.4 `dispute-portal-evidence`

| Campo | Valor |
|-------|-------|
| nome | `dispute-portal-evidence` |
| responsabilidade | Serve evidência via **portal token** (sem JWT); ownership attachment; EXIF strip |
| trigger | GET `?token=&attachment_id=`; OPTIONS |
| consumidores | Portal carrier (anon); URL `{SUPABASE_URL}/functions/v1/dispute-portal-evidence?...` |
| autenticação/gateway | Portal token UUID + service_role client direto (não `handleWithSecurity`); gateway JWT default true |
| claims | Nenhum JWT; token `expires_at_utc` / `revoked_at_utc` / access caps |
| roles | N/A |
| service_role | Sim |
| tabelas/views/RPCs | `dispute_portal_tokens`, `dispute_evidence_attachments`; Storage `dispute_evidence` |
| efeitos externos | Storage download |
| dados sensíveis/secrets | `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` |
| invariantes | INV-1, INV-26 |
| testes existentes | **Nenhum** dedicado em `tests/` |
| observabilidade | `console.error` |
| dependências | `evidence_serve`, `sovereignty_error_mapper` |
| destino candidato | storage service / `apps/api` — candidatura portal path |
| ordem migração | Fatia **3** |
| risco | Token replay; oracle; gateway JWT vs portal |
| critério paridade | PG-EVIDENCE, PG-INV26 |
| rollback | Flag → Edge |
| desligamento | Zero hits portal + dual-run PASS |

### 5.5 `generate-org-secret`

| Campo | Valor |
|-------|-------|
| nome | `generate-org-secret` |
| responsabilidade | Gera secret HMAC 256-bit; persiste hash em `org_api_secrets`; revoga versão anterior; plaintext **uma vez** |
| trigger | POST `{ organization_id }` |
| consumidores | Flutter `GenerateOrgSecretHandler` (legado); **SSOT retired** → RPC `super_admin_create_organization` (`forensic_records/plans/20260706000010_auto_populate_org_api_secrets_test_plan.md`) |
| autenticação/gateway | `handleWithSecurity` requireAuth + requireSuperAdmin + requireAAL2 |
| claims | `super_admin=true`; org via `validateTenantId` |
| roles | SuperAdmin |
| service_role | Sim |
| tabelas/views/RPCs | `organizations`, `org_api_secrets`; `system_audit_log` (`SECRET_ROTATION`) |
| efeitos externos | Nenhum |
| dados sensíveis/secrets | `SUPABASE_*`; secret in-memory one-shot |
| invariantes | INV-3, INV-9, INV-22, INV-26, INV-28 |
| testes existentes | **Nenhum** dedicado Deno |
| observabilidade | Audit + `console.error` |
| dependências | `handle_with_security`, `tenant_id_validator`, `sovereignty_error_mapper` |
| destino candidato | **deferred** — função retirada no plano DB; não portar como superfície primária |
| ordem migração | Fatia **2** só se ainda houver caller; preferir RPC SSOT |
| risco | Dual SSOT (Edge vs RPC); secret leak |
| critério paridade | PG-HMAC; plaintext never re-read |
| rollback | Manter RPC SSOT; não reativar Edge sem Council |
| desligamento | Remover invoke Dart + deploy; documentar `decommissioned` |

### 5.6 `get-justification-upload-url`

| Campo | Valor |
|-------|-------|
| nome | `get-justification-upload-url` |
| responsabilidade | Valida token driver; emite signed PUT URL (10 min) bucket `justification-evidence` |
| trigger | POST `{ token, fileName }`; OPTIONS |
| consumidores | Flutter `JustificationEvidenceStorageService` / driver anon |
| autenticação/gateway | Sem JWT (anon callable); service_role server-side |
| claims | Token ativo (`used_at_utc` null, não expirado) |
| roles | N/A |
| service_role | Sim |
| tabelas/views/RPCs | `justification_submission_tokens`; Storage `justification-evidence` |
| efeitos externos | Storage signed upload URL |
| dados sensíveis/secrets | `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` |
| invariantes | INV-3, INV-8; path prefix `organization_id/` |
| testes existentes | **Nenhum** dedicado Deno |
| observabilidade | `console.error` |
| dependências | `@supabase/supabase-js` apenas |
| destino candidato | **storage service** |
| ordem migração | Fatia **3** |
| risco | URL signed abuse; path escape |
| critério paridade | PG-EVIDENCE; TTL e prefix org |
| rollback | Flag → Edge |
| desligamento | Após storage Go PASS |

### 5.7 `ingest-omnitracs`

| Campo | Valor |
|-------|-------|
| nome | `ingest-omnitracs` |
| responsabilidade | Ingest ACL Omnitracs: API key → org; seal; classify; upsert `canonical_facts`; GPS transitions |
| trigger | POST JSON; OPTIONS |
| consumidores | Provider Omnitracs (Bearer API key) |
| autenticação/gateway | `provider_api_keys` (`OMNITRACS`); **gateway `verify_jwt` default true — FINDING gap vs sascar** |
| claims | Nenhum JWT; org via key hash |
| roles | N/A |
| service_role | Sim — writes |
| tabelas/views/RPCs | `provider_api_keys`, `organizations`, `ingestion_alerts`, `raw_telemetry_payloads`, `canonical_facts`; RPC `process_gps_for_execution_transitions` |
| efeitos externos | Sentry |
| dados sensíveis/secrets | `SUPABASE_*`, `SENTRY_DSN`, `APP_ENV`, `HMAC_SECRET_KEY_V1` |
| invariantes | INV-6, INV-14, INV-16, INV-17, INV-31 |
| testes existentes | Nenhum unit dedicado; shared `classify_integrity_test.ts` |
| observabilidade | Sentry + console |
| dependências | `classify_integrity`, `hmac_signer`, `sha256_hex` |
| destino candidato | `apps/api` handler (ingest) |
| ordem migração | Fatia **2** |
| risco | Spoof/replay; **config JWT mismatch** |
| critério paridade | PG-INGEST, PG-HMAC; config parity com sascar |
| rollback | Flag ingest → Edge |
| desligamento | Após dual-run ingest PASS |

### 5.8 `ingest-sascar`

| Campo | Valor |
|-------|-------|
| nome | `ingest-sascar` |
| responsabilidade | Pipeline análogo Omnitracs para Sascar (`SASCAR_V1`, snake_case) |
| trigger | POST; OPTIONS |
| consumidores | Provider Sascar GPS |
| autenticação/gateway | Provider API key; **`verify_jwt=false`** em `config.toml` |
| claims | Org via key hash (INV-17) |
| roles | N/A |
| service_role | Sim |
| tabelas/views/RPCs | Mesma família que omnitracs + `process_gps_for_execution_transitions` |
| efeitos externos | Sentry |
| dados sensíveis/secrets | Idem omnitracs |
| invariantes | INV-16, INV-17, INV-31; idempotency constraint |
| testes existentes | Shared `classify_integrity_test.ts`; Dart `postgres_autonomous_closer_test.dart` (HTTP) |
| observabilidade | Sentry + console |
| dependências | `classify_integrity`, `hmac_signer`, `sha256_hex` |
| destino candidato | `apps/api` handler |
| ordem migração | Fatia **2** |
| risco | Spoof/replay; schema drift vs omnitracs |
| critério paridade | PG-INGEST |
| rollback | Flag → Edge |
| desligamento | Após parity omnitracs+sascar |

### 5.9 `issue-impersonation-jwt`

| Campo | Valor |
|-------|-------|
| nome | `issue-impersonation-jwt` |
| responsabilidade | Cria `impersonation_sessions` (30 min, ticket/reason); metadata de sessão (não assina JWT free-tier) |
| trigger | POST `{ target_org_id, ticket_id, reason }` |
| consumidores | Flutter SuperAdmin `StartImpersonationHandler` |
| autenticação/gateway | `handleWithSecurity` requireAuth + SA + AAL2 |
| claims | `super_admin`; impersonator=`ctx.userId` |
| roles | SuperAdmin |
| service_role | Sim |
| tabelas/views/RPCs | `impersonation_sessions`, `organizations`; `system_audit_log` (`IMPERSONATION_START`) |
| efeitos externos | Nenhum |
| dados sensíveis/secrets | `SUPABASE_*` |
| invariantes | INV-1, INV-22, INV-26 |
| testes existentes | **Nenhum** dedicado Deno |
| observabilidade | Audit + console |
| dependências | `handle_with_security`, `tenant_id_validator`, `sovereignty_error_mapper` |
| destino candidato | `apps/api` handler (Auth; uso operacional amarra fatia 6) |
| ordem migração | Fatia **1** (gate SA na **6**) |
| risco | Impersonation abuse; TTL drift |
| critério paridade | PG-IMPERSONATION, PG-AAL2 |
| rollback | Disable issue route; revoke sessions |
| desligamento | Após ADR-011 Go sessions PASS |

### 5.10 `log-security-incident`

| Campo | Valor |
|-------|-------|
| nome | `log-security-incident` |
| responsabilidade | Recebe incidentes do `SuperAdminGuard`; sanitiza JWT snapshot; INSERT `system_audit_log`; sempre HTTP 200 |
| trigger | POST `{ event_type, metadata, jwt_claims_snapshot }` |
| consumidores | Flutter `SecurityIncidentProvider`, `SuperAdminGuard` |
| autenticação/gateway | `handleWithSecurity` requireAuth; **qualquer JWT**; AAL2 false |
| claims | Qualquer role; rate 5/min/IP |
| roles | Authenticated |
| service_role | Sim |
| tabelas/views/RPCs | `system_audit_log` |
| efeitos externos | Nenhum |
| dados sensíveis/secrets | `SUPABASE_*` |
| invariantes | INV-9, INV-26 |
| testes existentes | `log_security_incident_unit_test.ts`, `log_security_incident_auth_pbt_test.ts`, `security_incident_log_completeness_pbt_test.ts`; pipeline `penetration_protocol_integration_test.ts` |
| observabilidade | `console.error` on insert fail |
| dependências | `handle_with_security`, `jwt_claims_sanitizer` |
| destino candidato | `apps/api` handler (transversal Auth/SA) |
| ordem migração | Fatia **1** ou **6** (transversal) |
| risco | Flood audit; secret em snapshot |
| critério paridade | PG-AUDIT |
| rollback | Flag → Edge |
| desligamento | Após clients migrados |

### 5.11 `notify-invite`

| Campo | Valor |
|-------|-------|
| nome | `notify-invite` |
| responsabilidade | E-mail de convite via Resend; skip `@e2e.veraprob.dev`; fallback UI (INV-24) |
| trigger | POST `{ email, inviteUrl, orgName }`; OPTIONS |
| consumidores | Flutter `SupabaseAdminNotificationRepository`, `CreateOrganizationHandler` |
| autenticação/gateway | **anon client + `auth.getUser()`** (Bearer JWT); **não** `handleWithSecurity` |
| claims | User JWT válido |
| roles | **Nenhum check de role** (FINDING: RBAC fraco — qualquer autenticado pode disparar e-mail) |
| service_role | Não — `SUPABASE_ANON_KEY` + JWT user |
| tabelas/views/RPCs | Nenhuma escrita DB |
| efeitos externos | Resend (`npm:resend@4`) |
| dados sensíveis/secrets | `RESEND_API_KEY`, `SUPABASE_URL`, `SUPABASE_ANON_KEY` |
| invariantes | INV-24 |
| testes existentes | Nenhum Deno dedicado; Dart repo mocks invoke |
| observabilidade | `console.warn/error` |
| dependências | Nenhuma shared VeraProb |
| destino candidato | **worker** (notificação transacional) |
| ordem migração | Fatia **5** |
| risco | Abuse de e-mail; spoof invite |
| critério paridade | RBAC endurecido candidatado + PG-AUDIT opcional |
| rollback | Flag → Edge; UI fallback permanece |
| desligamento | Após worker + RBAC PASS |

### 5.12 `notify-sla-breach`

| Campo | Valor |
|-------|-------|
| nome | `notify-sla-breach` |
| responsabilidade | Lê facts `DISPUTE_SLA_BREACHED`; idempotência via audit; e-mail TENANT_ADMINs; log `SLA_BREACH_NOTIFICATION_SENT` |
| trigger | POST; OPTIONS |
| consumidores | Infra (pg_cron/pg_net comentado); sem Flutter |
| autenticação/gateway | Strict service_role Bearer |
| claims | Nenhum |
| roles | N/A |
| service_role | Sim — auth + `auth.admin.getUserById` |
| tabelas/views/RPCs | `sla_audit_ledger_v2`, `system_audit_log`, `organizations`, `user_roles` |
| efeitos externos | Resend; HMAC audit (`signPayload`) |
| dados sensíveis/secrets | `SUPABASE_SERVICE_ROLE_KEY`, `RESEND_API_KEY`, `HMAC_SECRET_KEY_V1` |
| invariantes | INV-1, INV-3, INV-6, INV-22, INV-31 |
| testes existentes | `tests/notify_sla_breach_unit_test.ts` |
| observabilidade | console per org/fact |
| dependências | `hmac_signer` |
| destino candidato | **worker** |
| ordem migração | Fatia **5** |
| risco | Duplicate notify; wrong-tenant e-mail |
| critério paridade | Idempotência audit + PG-UTC |
| rollback | Pause cron novo |
| desligamento | Após worker PASS |

### 5.13 `portal-finalize-upload`

| Campo | Valor |
|-------|-------|
| nome | `portal-finalize-upload` |
| responsabilidade | Fase 2 portal: quarantine → magic-byte + SHA-256 → copy produção → RPC `register_portal_evidence` |
| trigger | POST `{ token, submissionId }`; OPTIONS |
| consumidores | Portal via `SupabasePortalDisputeGateway`; deploy prod costuma `--no-verify-jwt` |
| autenticação/gateway | Portal token + service_role |
| claims | Token `token_scope=submit`; submission `QUARANTINE` |
| roles | N/A |
| service_role | Sim |
| tabelas/views/RPCs | `dispute_portal_tokens`, `portal_evidence_submissions`; `fail_portal_submission`, `register_portal_evidence`; Storage `dispute-evidence-portal`, `dispute_evidence` |
| efeitos externos | Storage download/upload/copy |
| dados sensíveis/secrets | `SUPABASE_*` |
| invariantes | INV-1, INV-9, INV-18, INV-22, INV-26 |
| testes existentes | `tests/portal_finalize_upload_unit_test.ts`; Dart gateway |
| observabilidade | `infra_error_guard` / correlation UUID |
| dependências | `sovereignty_error_mapper`, `infra_error_guard`, `magic_bytes` |
| destino candidato | storage service / `apps/api` |
| ordem migração | Fatia **3** |
| risco | Hash mismatch; quarantine leak |
| critério paridade | PG-HASH, PG-EVIDENCE |
| rollback | Flag → Edge |
| desligamento | Após sealing path Go PASS |

### 5.14 `portal-submit-request`

| Campo | Valor |
|-------|-------|
| nome | `portal-submit-request` |
| responsabilidade | Fase 1 portal: fail-fast; RPC create/justification-only; signed upload quarantine; floor 80ms + IP throttle |
| trigger | POST; OPTIONS |
| consumidores | Portal `SupabasePortalDisputeGateway`; `--no-verify-jwt` em prod |
| autenticação/gateway | Portal token + service_role |
| claims | UUID token; MIME whitelist |
| roles | N/A |
| service_role | Sim |
| tabelas/views/RPCs | `create_portal_submission`, `submit_portal_justification_only`; Storage signed URL |
| efeitos externos | Storage signing |
| dados sensíveis/secrets | `SUPABASE_*` |
| invariantes | INV-1, INV-9, INV-18, INV-22, INV-26 |
| testes existentes | `tests/portal_submit_request_unit_test.ts`; Dart submit evidence |
| observabilidade | `logBusinessRejection` / `logInfraError` |
| dependências | `sovereignty_error_mapper`, `infra_error_guard` |
| destino candidato | `apps/api` / storage |
| ordem migração | Fatia **3** |
| risco | Upload abuse; timing oracle |
| critério paridade | PG-EVIDENCE, PG-INV26 |
| rollback | Flag → Edge |
| desligamento | Par com finalize |

### 5.15 `reveal-webhook-signing-secret`

| Campo | Valor |
|-------|-------|
| nome | `reveal-webhook-signing-secret` |
| responsabilidade | Provision/rotate webhook signing keys; derive org secret hex reveal-once; audit `WEBHOOK_SECRET_*` |
| trigger | POST `{ action: "provision" \| "rotate" }` |
| consumidores | Flutter `SupabaseWebhookRepository._invokeReveal` |
| autenticação/gateway | `handleWithSecurity` requireAuth; **`requireAAL2=false` explícito** (TODO Fase 11 / `REQUIRE_AAL2_TENANT_SECRET`) |
| claims | `organization_id` do JWT |
| roles | `TENANT_ADMIN` |
| service_role | Sim |
| tabelas/views/RPCs | `webhook_signing_keys`; `system_audit_log` |
| efeitos externos | Nenhum (derive local) |
| dados sensíveis/secrets | `HMAC_SECRET_KEY_V1`, `SUPABASE_*` |
| invariantes | INV-1, INV-26, INV-28, INV-31 |
| testes existentes | `tests/reveal_webhook_signing_secret_unit_test.ts`; Dart webhook repo |
| observabilidade | `console.error` RBAC/audit |
| dependências | `handle_with_security`, `sovereignty_error_mapper`, `hmac_signer` |
| destino candidato | `apps/api` handler |
| ordem migração | Fatia **5–6** |
| risco | **P0:** reveal com sessão AAL1 (T-26 / PG-AAL2) |
| critério paridade | PG-AAL2 + PG-HMAC — aal1 deve deny |
| rollback | Disable reveal route |
| desligamento | Após remediação AAL2 + Go parity |

### 5.16 `revoke-impersonation`

| Campo | Valor |
|-------|-------|
| nome | `revoke-impersonation` |
| responsabilidade | Set `revoked_at` em `impersonation_sessions`; audit `IMPERSONATION_REVOKE` |
| trigger | POST `{ session_id, reason? }` |
| consumidores | Flutter `RevokeImpersonationHandler` |
| autenticação/gateway | `handleWithSecurity` requireAuth + requireSuperAdmin (AAL2 via path SA) |
| claims | `super_admin=true` |
| roles | SuperAdmin |
| service_role | Sim |
| tabelas/views/RPCs | `impersonation_sessions`, `system_audit_log` |
| efeitos externos | Nenhum |
| dados sensíveis/secrets | `SUPABASE_*` |
| invariantes | INV-22 (isolamento de sessão) |
| testes existentes | **Nenhum** dedicado Deno |
| observabilidade | Audit + console |
| dependências | `handle_with_security` |
| destino candidato | `apps/api` handler |
| ordem migração | Fatia **1** (uso↔**6**) |
| risco | Revoke falho deixa sessão viva |
| critério paridade | PG-IMPERSONATION, PG-REVOCATION |
| rollback | Flag → Edge |
| desligamento | Par com issue |

### 5.17 `revoke-user-sessions`

| Campo | Valor |
|-------|-------|
| nome | `revoke-user-sessions` |
| responsabilidade | `auth.admin.signOut(userId, 'global')`; audit `SESSIONS_REVOKED` |
| trigger | POST `{ user_id }` via pg_net (migration `20260910000002`) |
| consumidores | RPC DB → HTTP; não Flutter |
| autenticação/gateway | Exact Bearer service_role |
| claims | Nenhum |
| roles | N/A |
| service_role | Sim — auth + Admin API |
| tabelas/views/RPCs | `system_audit_log`; Supabase Auth admin |
| efeitos externos | Invalidação global de sessão Auth |
| dados sensíveis/secrets | `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL` |
| invariantes | INV-1 (org no RPC), INV-21 |
| testes existentes | **Nenhum** dedicado Deno |
| observabilidade | `console.error` |
| dependências | Nenhuma shared |
| destino candidato | `apps/api` handler (session revoke) |
| ordem migração | Fatia **1** |
| risco | Residual JWT P0 pré-exp com `getClaims` |
| critério paridade | PG-REVOCATION, PG-SESSION |
| rollback | Manter RPC→Edge até Go session store |
| desligamento | Após ADR-011 revoke PASS |

### 5.18 `secure-evidence-proxy`

| Campo | Valor |
|-------|-------|
| nome | `secure-evidence-proxy` |
| responsabilidade | Serve evidência Telegram por `evidence_id` org-scoped; EXIF strip; bucket `telegram_evidence` |
| trigger | GET `?evidence_id=`; OPTIONS |
| consumidores | Flutter OCC (`EvidenceUrlService`, cards/dossier) |
| autenticação/gateway | `handleWithSecurity` JWT tenant |
| claims | `organization_id` |
| roles | Sem gate extra no handler |
| service_role | Sim |
| tabelas/views/RPCs | `telegram_evidence_uploads`; Storage `telegram_evidence` |
| efeitos externos | Storage download |
| dados sensíveis/secrets | `SUPABASE_*` |
| invariantes | INV-1, INV-9, INV-18, INV-26 |
| testes existentes | Shared `exif_stripper_test.ts` apenas |
| observabilidade | Sentry via wrapper |
| dependências | `handle_with_security`, `evidence_serve`, `sovereignty_error_mapper` |
| destino candidato | storage service / `apps/api` |
| ordem migração | Fatia **3** |
| risco | Cross-tenant evidence; EXIF leak |
| critério paridade | PG-EVIDENCE, PG-INV26 |
| rollback | Flag → Edge |
| desligamento | Após OCC URLs migradas |

### 5.19 `super-admin-proxy`

| Campo | Valor |
|-------|-------|
| nome | `super-admin-proxy` |
| responsabilidade | Proxy SA: health, audit, evidence download, volume, schema integrity, CNPJ; HMAC INV-31; `super_admin_access_log` |
| trigger | POST `{ action, params?, ticket_id?, justification? }` + `x-timestamp`/`x-signature`; OPTIONS |
| consumidores | Flutter `SupabaseSuperAdminRepository`, `ReceitaWsCnpjService`; E2E security |
| autenticação/gateway | Manual `auth.getUser` + claim SA; **`verify_jwt=false`**; HMAC temporal; AAL2 (skip se `ENVIRONMENT=dev`) |
| claims | `app_metadata.super_admin === true`; MFA lockout `check_mfa_lockout` |
| roles | SuperAdmin |
| service_role | Sim |
| tabelas/views/RPCs | Views SA health/technical/volume; `system_audit_log`, `telegram_evidence_uploads`, `super_admin_access_log`; RPC `check_schema_integrity`; Storage; ReceitaWS |
| efeitos externos | ReceitaWS; Storage |
| dados sensíveis/secrets | `SUPABASE_*`, `HMAC_SECRET_KEY_V1`, `ENVIRONMENT` |
| invariantes | INV-3, INV-6, INV-7, INV-14, INV-26, INV-31 |
| testes existentes | `super_admin_proxy_integration_test.ts`; Dart SA repo + audit RLS; `jwt_auth_validator_test.ts` |
| observabilidade | `super_admin_access_log` por call |
| dependências | `sovereignty_error_mapper`, `hmac_signer`, `clock_drift_helper`, `mime` |
| destino candidato | `apps/api` handler (última fatia privilegiada) |
| ordem migração | Fatia **6** |
| risco | Service-role blast radius; CNPJ egress |
| critério paridade | PG-AAL2, PG-AUDIT, PG-INV26 |
| rollback | Flag → Edge imediato |
| desligamento | Após SA Go + audit completeness |

**Actions:** `list_tenant_health`, `get_audit_log`, `download_original_evidence`, `get_tenant_technical_health`, `get_evidence_volume`, `check_schema_integrity`, `lookup_cnpj`.

### 5.20 `telegram-webhook`

| Campo | Valor |
|-------|-------|
| nome | `telegram-webhook` |
| responsabilidade | Ingress Telegram: consent, evidência (foto/doc/voz), GPS, linking, compliance RPCs, alertas, teclado inline — maior superfície Edge |
| trigger | POST Update JSON; header `X-Telegram-Bot-Api-Secret-Token`; **`verify_jwt=false`** |
| consumidores | Telegram Bot API; chaos `crash_recovery.sh` |
| autenticação/gateway | Secret vs `TELEGRAM_WEBHOOK_SECRET`; service_role client |
| claims | Nenhum JWT; binding `telegram_chat_bindings` |
| roles | N/A |
| service_role | Sim |
| tabelas/views/RPCs | Família `telegram_*`, `operational_alerts`, `execution_states`, `operational_zones`, `drivers`, `organizations`, `sla_audit_ledger`; RPCs `find_execution_for_telegram`, `start_transit_for_execution`, `check_execution_compliance`, `get_trip_compliance_status`, `create_shadow_execution`, `check_telegram_rate_limit`, etc. |
| efeitos externos | Telegram Bot API; Storage `telegram_evidence` |
| dados sensíveis/secrets | `TELEGRAM_BOT_TOKEN`, `TELEGRAM_WEBHOOK_SECRET`, `SUPABASE_*`, `HMAC_SECRET_KEY_V1` |
| invariantes | INV-1, INV-6, INV-7, INV-10, INV-14, INV-15, INV-18 |
| testes existentes | `telegram_webhook_integration_test.ts`; shared consent/image/clock/compliance/transit; Dart geofence mirror |
| observabilidade | console + ledger/alert HMAC |
| dependências | `consent_middleware`, `exif_extractor`, `image_quality_validator`, `compliance_formatter`, `clock_drift_helper`, `hmac_signer`, `mime` |
| destino candidato | worker / `apps/api` ingress |
| ordem migração | Fatia **5** |
| risco | Spoof webhook; evidence forge; rate limit bypass |
| critério paridade | PG-EVIDENCE + webhook ingress tests |
| rollback | Repoint Telegram webhook URL → Edge |
| desligamento | Após dual-run message parity |

### 5.21 `verify-evidence-hash`

| Campo | Valor |
|-------|-------|
| nome | `verify-evidence-hash` |
| responsabilidade | **Stub DEPRECATED**: non-OPTIONS → `sovereigntyErrorResponse()` (404 INV-26). SSOT: `portal-finalize-upload` + RPC `verify_evidence_hash` |
| trigger | Qualquer método → 404; OPTIONS → CORS |
| consumidores | Nenhum (`lib/` sem callers) |
| autenticação/gateway | Nenhuma |
| claims | N/A |
| roles | N/A |
| service_role | Não |
| tabelas/views/RPCs | Nenhuma |
| efeitos externos | Nenhum |
| dados sensíveis/secrets | Nenhum |
| invariantes | INV-26 |
| testes existentes | `tests/verify_evidence_hash_unit_test.ts` (confirma stub) |
| observabilidade | Nenhuma |
| dependências | `sovereignty_error_mapper` |
| destino candidato | **deferred** — não portar; remover após cutover |
| ordem migração | Fatia **3** (apenas cleanup) |
| risco | Caller legado reativado |
| critério paridade | Manter 404 opaco se rota existir |
| rollback | N/A (já morta) |
| desligamento | Remover dir + deploy; inventário `decommissioned` |

### 5.22 `verify-ledger-hmac`

| Campo | Valor |
|-------|-------|
| nome | `verify-ledger-hmac` |
| responsabilidade | Recomputa/verifica HMAC de payload canónico vs assinatura versionada; `{ valid, reason? }` sem vazar segredo |
| trigger | POST `{ canonical_payload, stored_signature }` |
| consumidores | Doc para `IntegrityVerificationService` — **sem invoke Dart encontrado** |
| autenticação/gateway | `handleWithSecurity` requireAuth (qualquer JWT) |
| claims | Tenant JWT |
| roles | Authenticated |
| service_role | Sim (wrapper); verify usa env keys |
| tabelas/views/RPCs | Nenhuma (stateless) |
| efeitos externos | Sentry opcional (`HMAC_VERIFICATION_FAILED`) |
| dados sensíveis/secrets | `HMAC_SECRET_KEY_V1`, `SUPABASE_*` |
| invariantes | INV-1, INV-26, INV-31-R |
| testes existentes | Nenhum dedicado; `hmac_signer` indireto |
| observabilidade | Sentry opcional |
| dependências | `hmac_signer`, `handle_with_security` |
| destino candidato | `apps/api` handler |
| ordem migração | Fatia **2** |
| risco | Cross-org verify se payload não amarrado à org do JWT |
| critério paridade | PG-HMAC |
| rollback | Flag → Edge |
| desligamento | Após Go crypto path + callers claros |

---

## 6. Findings (abertos — Status Proposed)

| ID | Finding | Severidade | Funções | Gate / ADR |
|----|---------|------------|---------|------------|
| F-01 | Gaps de teste Deno: sem unit dedicado em várias superfícies (portal evidence, ingest unit, impersonation, revoke-*, generate-org-secret, justification URL, verify-ledger-hmac, notify-invite, secure-evidence-proxy handler) | Alta (cobertura) | ver §4 | PG-* correspondentes |
| F-02 | `generate-org-secret` **retired** no plano DB mas diretório Edge + handler Dart ainda presentes | Média | `generate-org-secret` | PG-HMAC / cleanup |
| F-03 | `verify-evidence-hash` é stub 404 permanente | Baixa (dívida) | `verify-evidence-hash` | decommission |
| F-04 | AAL2 **não** exigido em `reveal-webhook-signing-secret` (`requireAAL2=false`) | **P0** | reveal | PG-AAL2, ADR-011, T-26 |
| F-05 | `notify-invite`: auth só `getUser`, **sem RBAC de role** | Média | notify-invite | endurecer na migração worker |
| F-06 | `ingest-omnitracs` sem `verify_jwt=false` (paridade sascar) | Alta (config) | ingest-omnitracs | PG-INGEST, T-28 |
| F-07 | Contagem migrations **377** ≠ 365 do texto histórico do plano | Info | lift-and-shift | ADR-010/013 |
| F-08 | Residual JWT P0: revogação pré-`exp` com `getClaims` | Alta | revoke-user-sessions / auth | PG-REVOCATION |

---

## 7. Infra transversal de testes (não 1:1)

`jwt_auth_validator_test.ts`, `jwt_getclaims_integration_test.ts`, `aal2_enforcement_pbt_test.ts`, `headers_integrity_404_pbt_test.ts`, `penetration_protocol_integration_test.ts`, `classify_integrity_test.ts`, `magic_bytes_test.ts`, `exif_*`, `consent_middleware_test.ts`, `clock_drift_*`, `tenant_id_*`, `shadow_execution_test.ts`.

---

## 8. Referências

| Artefato | Papel |
|----------|-------|
| [phase11_enterprise_pivot.md](phase11_enterprise_pivot.md) | Plano canônico Phase 11 |
| [phase11_threat_model.md](phase11_threat_model.md) | STRIDE / T-26 / T-28 |
| [phase11_parity_checklist.md](phase11_parity_checklist.md) | Gates PG-* |
| [ADR-010](../adr/010_exit_supabase.md) | Exit ramp / ROI |
| [ADR-011](../adr/011_auth_zero_trust.md) | AAL2 / sessão / impersonation |
| [ADR-012](../adr/012_rls_connection_lifecycle.md) | `SET LOCAL` / pool |
| [ADR-013](../adr/013_strangler_fig.md) | Ordem de fatias + mapeamento candidato |
| `supabase/config.toml` | Overrides `verify_jwt` |
| `supabase/functions/*/index.ts` | Fonte do Set A |

---

**Fim do inventário Proposed.** Nenhum destino, gate ou ADR neste arquivo está marcado Accepted.
