# Phase 11 — Parity Gates Checklist (Etapa −1)

**Date:** 2026-07-21
**Status:** Proposed contract (revisão H2 — A portável)
**Commit baseline:** `6e626a6f6314484e7c939e988ff34980351f257b`
**SSOT siblings:** [phase11_enterprise_pivot.md](phase11_enterprise_pivot.md), [phase11_threat_model.md](phase11_threat_model.md), [phase11_edge_functions_inventory.md](phase11_edge_functions_inventory.md), ADRs 010–013.

## Convenções

| Campo | Significado |
|-------|-------------|
| Bloqueante −1 | Impede PASS documental da Etapa −1 se contrato incompleto |
| Bloqueante piloto | Impede primeiro piloto mesmo com PASS −1 |
| Condicional B/C | Só aplica após gatilho + go/no-go B/C |
| Ambiente | `local-supabase` / `ci` / `staging-dual-run` / `drill` |
| Reviewer | Sempre distinto do Owner |

**Estados de gate (não confundir):**

| Estado | Significado |
|--------|-------------|
| `CONTRACT COMPLETE` | Contrato documental fechado na Etapa −1 |
| `NOT RUN` | Runtime ainda não executado / evidenciado |
| `PASS` / `FAIL` | Resultado runtime com evidência no Evidence Log |

**Error budget:** nunca cobre bypass auth, tenant bleed, principal híbrido, AAL2 reveal, revogação inválida, append-only, INV-26, INV-28.

### Roles accountability

| Role | Responsabilidade | Escalation |
|------|------------------|------------|
| Identity Owner | Auth/sessão/MFA/revogação | Security Owner → Lead |
| Data Platform Owner | RLS/pool/roles | QA/Security → Lead |
| Ingest Owner | Ingest/HMAC | QA/Security → Lead |
| Evidence Owner | Evidence/hash/oracle | QA/Security → Lead |
| Webhook Owner | Webhooks/SSRF | Platform → Lead |
| Migration Owner | Strangler/dual-run (B/C) | Architect → Lead |
| QA Owner | Execução/registro de gates | Lead Reviewer |
| Platform Owner | Perf/DR/backup | Architect → Lead |
| SA Owner | SuperAdmin/impersonation | Security → Lead |

## Catálogo de gates — A portável (prioridade)

| Gate ID | Escopo | Risco | Evidência exigida | Comando/teste | Ambiente | Resultado esperado | Owner | Reviewer | Bloq. −1 | Bloq. piloto | Estado H2 | Fase |
|---------|--------|-------|-------------------|---------------|----------|--------------------|-------|----------|----------|--------------|-----------|------|
| PG-AAL2 | MFA/step-up + reveal | T-17,T-26 | aal1 deny em reveal | `reveal_webhook_signing_secret_unit_test.ts`; `aal2_enforcement_pbt_test.ts` | ci | Reveal exige AAL2 | Identity Owner | QA/Security | Y (evidência) | — | **PASS** (Edge) | −1 |
| PG-REVOCATION | Revogação pré-exp + global | T-04,T-05,T-27,T-31,T-32 | Contrato ADR-011 + prova runtime Etapa 1 | `SPEC:revocation_pre_exp_test` (Etapa 1) | ci / local-supabase | 0 acessos válidos pós-revoke antes de exp (Edge **e** Data API/RLS); store down→deny; replay revoga família; rate limit; audit sem tokens; rollback emissor (se B/C) | Identity Owner | QA/Security | Contrato Y | **Y (`PASS` runtime)** | **CONTRACT COMPLETE** / runtime **NOT RUN** | −1 contract; 1 runtime |
| PG-AUTH | Claims/assinatura | T-01,T-02,T-24,T-32 | Relatório contract+crypto | `jwt_auth_validator_test.ts`; `jwt_getclaims_integration_test.ts` | ci | Fail-closed; hybrid reject | Identity Owner | QA/Security | Y | Y | Baseline measured; extend Etapa 1 | −1/1 |
| PG-SESSION | Lifecycle sessão | T-03 | Trace login→refresh→logout | `SPEC:session_lifecycle_test` (Etapa 1) | local-supabase | TTLs ADR-011; idle/absoluta | Identity Owner | QA/Security | N | Y | NOT RUN | 1 |
| PG-BACKUP | Dump diário off-site + Storage | T-23 | Job + encrypt proof + classificação Storage | `SPEC:backup_job_proof` (Etapa 1) | drill | Dump cifrado ≤24h; blobs piloto em cópia separada | Platform Owner | Lead | N | **Y** | NOT RUN | 1 |
| PG-RESTORE | Restore exercitado | T-23 | Restore drill report | `SPEC:restore_drill` | drill | Restore comprovado dentro de **24h** (RTO) | Platform Owner | Lead | N | **Y** | NOT RUN | 1 |
| PG-DR | Continuity pré-prod | T-23 / P-DR-01 | Runbook + drill | `SPEC:dr_drill` | drill | RPO/RTO **24h/24h, sem SLA**; `<5min/<4h` = prod **não aprovado** | Platform Owner | Lead | N | **Y** | Objective decided; runtime NOT RUN | 1 |
| PG-INGEST | Spoof/replay + config | T-10,T-25,T-28 | Cases + config parity | `classify_integrity_test.ts`; config check omnitracs | ci | Spoof reject; F-06 track | Ingest Owner | QA/Security | N | Prefer Y | Open (F-06) | pós-PASS −1 |
| PG-HMAC | Segredo por org | T-11 | Verify fail cross-org | HMAC unit paths | ci | INV-28 hold | Crypto Owner | QA/Security | Y | Y | Baseline | contínuo |
| PG-INV26 | 404 parity | T-12 | Wrong-org == missing | `headers_integrity_404_pbt_test.ts` | ci | Opacity parity | Evidence Owner | QA/Security | Y | Y | Baseline | contínuo |
| PG-AUDIT | Audit sem secrets | T-16,T-19 | Rows SA/reveal/revoke | `SPEC:audit_completeness` | ci | Sem tokens/cookies | Security Owner | QA/Security | Y | Y | CONTRACT + runtime Etapa 1 | −1/1 |
| PG-IMPERSONATION | Issue/TTL/actor/revoke | T-18 | Audit + revoke | `penetration_protocol_integration_test.ts` | local-supabase | ≤30m; sem refresh; actor | SA Owner | QA/Security | N | Y | Partial baseline | 1 |
| PG-RLS | Policies fail-closed | T-08 | pgTAP | `make test-db` | local-supabase | INV-2/22 | Data Platform Owner | QA/Security | Y | Y | Baseline | contínuo |
| PG-UTC | UTC | INV-6 | Scanner | UTC-BLOCK | ci | Zero bare local | Platform Owner | Senior | Y | Y | Baseline | contínuo |
| PG-APPEND-ONLY | Ledger | INV-3 | pgTAP | ledger tests | local-supabase | Deny mutação | Data Platform Owner | QA/Security | Y | Y | Baseline | contínuo |
| PG-EVIDENCE | Evidence paths | T-14 | Portal+JWT | `portal_*_unit_test.ts` | ci | Path org-bound | Evidence Owner | QA/Security | N | Y | Baseline | contínuo |
| PG-WEBHOOK | Sign/SSRF | T-13,T-15 | SSRF+HMAC | `dispatch_verdict_webhooks_unit_test.ts` | ci | Private IP blocked | Webhook Owner | QA/Security | N | Y | Baseline | contínuo |
| PG-CAPACITY | Exhaustion / rate limit | T-21 | Rate limit hold | Chaos + Auth limits registrados | staging | 429 sem oracle | Platform Owner | QA/Security | N | Y | NOT RUN | 1 |
| PG-OPENAPI | Contrato superfícies | Breaking | Diff OpenAPI | `SPEC:openapi_existing_surfaces` (Etapa 2) | ci | Zero break sem version | API Owner | Architect | N | N (Etapa 2) | NOT RUN | 2 |

### PG-REVOCATION — critérios runtime para `PASS` (Etapa 1)

Todos obrigatórios antes do primeiro piloto:

1. Revogação individual e global **antes de `exp`**
2. Efeito em Edge **e** Data API/RLS
3. Indisponibilidade do registro → fail-closed
4. Concorrência/replay de refresh (família inteira revogada)
5. Mudanças de senha / role / tenant; ban; impersonação
6. Rate limiting anti-oracle
7. Auditoria append-only sem tokens/cookies
8. Rollback do emissor candidato (se dual-run B/C ativo)

Estado documental H2: **`CONTRACT COMPLETE`** (inclui wiring PostgREST/RLS
`app.session_is_live()` + Edge em ADR-011). Runtime: **`NOT RUN`**.

## Catálogo de gates — condicionais B/C (não bloqueiam A)

| Gate ID | Escopo | Nota | Estado |
|---------|--------|------|--------|
| PG-POOL-BLEED | Pool SET LOCAL | Só se API própria | Conditional / NOT RUN |
| PG-CROSS-TENANT | Matrix A/B self-host | Condicional | Conditional |
| PG-DUAL-RUN | Shadow compare | Condicional | Conditional |
| PG-DIVERGENCE | Error budget shadow | Condicional; pending_baseline | Conditional |
| PG-ROLLBACK | Rollback <15m fatia | Condicional cutover | Conditional |
| PG-PERFORMANCE | p95 dual-run | P-PERF-01 deferred | Conditional |
| PG-MONEY / PG-REPLAY / PG-SNAPSHOT / PG-HASH | Paridade engine | Contínuo / fatias | Baseline ou Conditional |

## Evidence Log

> Preencher com artefatos reais. Runtime vazio = `NOT RUN`, não “mitigado”.

### PG-AAL2

| Campo | Valor |
|-------|-------|
| Estado | PASS (Edge) |
| Evidência | `forensic_records/plans/20260721000000_jwt_p0_residual_risks.md` (CLOSED 2026-07-21); `supabase/functions/reveal-webhook-signing-secret/index.ts` (`REVEAL_REQUIRE_AAL2=true`); `supabase/functions/tests/reveal_webhook_signing_secret_unit_test.ts` |
| Reviewer | Pending Council H2 |

### PG-REVOCATION

| Campo | Valor |
|-------|-------|
| Contrato | **CONTRACT COMPLETE** (ADR-011 H2) |
| Runtime | **NOT RUN** (`P-REV-IMPL-01` OPEN) |
| Evidência runtime | _(vazio — Etapa 1)_ |

### PG-BACKUP / PG-RESTORE / PG-DR

| Campo | Valor |
|-------|-------|
| Objetivo | RPO/RTO 24h/24h pré-prod (P-DR-01) |
| Runtime | **NOT RUN** (bloqueia piloto) |
| Storage | Classificação + cópia separada obrigatória para blobs de piloto |

### Demais gates

_(runtime vazio por design na Etapa −1, exceto baselines já existentes no repo)_

## Pendências

| ID | Item | Status | Impacto |
|----|------|--------|---------|
| P-DR-01 | RPO/RTO 24h/24h | **resolved_objective** | Runtime PG-BACKUP/RESTORE/DR NOT RUN bloqueiam piloto |
| P-REV-IMPL-01 | Implementação revogação | OPEN | Bloqueia piloto + PG-REVOCATION PASS |
| P-TCO-01 | TCO A portável | resolved_for_A | — |
| P-TCO-02..07 | Quotes B/C | deferred_non_blocking_for_A | Obrigatórios antes de Approved B/C |
| P-PERF-01 | p95 dual-run | deferred (B/C) | Condicional |
| P-DIV-01 | Divergence budget | deferred (B/C) | Condicional |
| F-06 / T-28 | ingest-omnitracs verify_jwt | Open | Track pós-PASS −1 |

**Owner deste documento:** QA Owner
**Reviewer:** Lead Reviewer
