# Phase 11 — Parity Gates Checklist (Etapa −1)

**Date:** 2026-07-21  
**Status:** Proposed contract (gates ainda não executados para stack Go; Etapa −1 valida completude/testabilidade)  
**SSOT siblings:** [phase11_enterprise_pivot.md](phase11_enterprise_pivot.md), [phase11_threat_model.md](phase11_threat_model.md), [phase11_edge_functions_inventory.md](phase11_edge_functions_inventory.md), ADRs 010–013.

## Convenções

| Campo | Significado |
|-------|-------------|
| Bloqueante | Y = zero falha; impede fatia/cutover |
| Ambiente | `local-supabase` / `ci` / `staging-dual-run` / `drill` |
| Evidência futura | Seção deste arquivo `## Evidence Log` + artefato CI |
| Reviewer | Sempre distinto do Owner |
| Comando existente | Só se verificado no repo; senão: `SPEC:` + fase de implementação |

**Error budget:** nunca cobre bypass auth, tenant/pool bleed, principal híbrido, AAL2 reveal, revogação inválida, append-only, INV-26, INV-28.

### Roles accountability

| Role | Responsabilidade | Escalation |
|------|------------------|------------|
| Identity Owner | Auth/sessão/MFA | Security Owner → Lead Reviewer |
| Data Platform Owner | RLS/pool/roles | QA/Security → Lead |
| Ingest Owner | Ingest/HMAC | QA/Security → Lead |
| Evidence Owner | Evidence/hash/oracle | QA/Security → Lead |
| Webhook Owner | Webhooks/SSRF | Platform → Lead |
| Migration Owner | Strangler/dual-run/rollback | Architect → Lead |
| QA Owner | Execução/registro de gates | Lead Reviewer |
| Platform Owner | Perf/DR/backup/obs | Architect → Lead |
| SA Owner | SuperAdmin/impersonation | Security → Lead |

## Catálogo de gates

| Gate ID | Escopo | Risco coberto | Evidência exigida | Comando ou teste | Ambiente | Resultado esperado | Owner | Reviewer | Bloq. | Rollback | Fase exec | Seção evidência |
|---------|--------|---------------|-------------------|------------------|----------|--------------------|-------|----------|-------|----------|-----------|-----------------|
| PG-AUTH | Claims/assinatura | T-01,T-02,T-24 | Relatório contract+crypto | `SPEC:apps/api/auth/contract_test` (Etapa 2); baseline atual: `deno test` `jwt_auth_validator_test.ts` + `jwt_getclaims_integration_test.ts` | ci / local-supabase | 100% casos assinatura/claims fail-closed; hybrid reject | Identity Owner | QA/Security | Y | Flag auth→Supabase Auth | −1 define; 2 executa Go | Evidence Log / PG-AUTH |
| PG-SESSION | Lifecycle sessão | T-03 | Trace login→refresh→logout | `SPEC:session_lifecycle_test` (Etapa 2) | staging-dual-run | Sessão revogável; cookies flags corretas | Identity Owner | QA/Security | Y | Invalidar cookies; Auth legado | 2–3 | Evidence Log / PG-SESSION |
| PG-REVOCATION | Revogação pré-exp + global | T-04,T-05,T-27 | Prova acesso negado pós-revoke antes de exp | `SPEC:revocation_pre_exp_test` (Etapa 2); residual tracked JWT P0 | ci | 0 acessos válidos pós-revoke | Identity Owner | QA/Security | Y | Kill switch sessões; rotate keys | 2 | Evidence Log / PG-REVOCATION |
| PG-AAL2 | MFA/step-up + reveal | T-17,T-26 | aal1 deny em reveal | Baseline: `aal2_enforcement_pbt_test.ts`; `SPEC:reveal_requires_aal2` (Edge remediação + Go) | ci | Reveal/SA sensível exige AAL2 | Identity Owner | QA/Security | Y | Disable reveal route | −1/0 track; remediação contínua | Evidence Log / PG-AAL2 |
| PG-IMPERSONATION | Issue/TTL/audit/revoke | T-18 | Audit rows + revoke | `penetration_protocol_integration_test.ts` + `SPEC:impersonation_go` | local-supabase / ci | Sessão ≤TTL; revoke imediato; audit append-only | SA Owner | QA/Security | Y | revoke-impersonation / flag off | 2/6 | Evidence Log / PG-IMPERSONATION |
| PG-RLS | Policies fail-closed | T-08 | pgTAP suite verde + policy review | `make test-db` (baseline); `SPEC:pgtap_app_tenant_id` (Etapa 1) | local-supabase | Fail closed sem tenant; equivalência semântica | Data Platform Owner | QA/Security | Y | Reverter migration policy; stack antiga | 1 | Evidence Log / PG-RLS |
| PG-POOL-BLEED | Mesma conexão física | T-09 | Relatório A→B e B→A pool=1 | `SPEC:pool_bleed_redteam` (Etapa 1) | local-supabase | 0 linhas cross-tenant | Data Platform Owner | QA/Security | Y | Drain pool; rollback deploy API | 1 | Evidence Log / PG-POOL-BLEED |
| PG-CROSS-TENANT | Isolamento A/B | T-08,T-12 | Red Team matrix | `SPEC:cross_tenant_matrix` + pgTAP existentes | ci | INV-22 hold | Data Platform Owner | Lead Reviewer | Y | Flag fatia off | 1–4 | Evidence Log / PG-CROSS-TENANT |
| PG-INGEST | Spoof/replay/idempotency | T-10,T-25,T-28 | Cases neg/pos ingest | Shared `classify_integrity_test.ts`; `SPEC:ingest_go_parity` | ci / staging-dual-run | Spoof reject; replay idempotente | Ingest Owner | QA/Security | Y | Flag ingest→Edge | 2 | Evidence Log / PG-INGEST |
| PG-HMAC | Segredo por org INV-28 | T-11 | Verify fail on wrong org key | HMAC unit paths + `SPEC:org_hmac_isolation` | ci | Cross-org verify fail; no master in tenant path | Crypto Owner | QA/Security | Y | Rotate keys; disable verify route | 2 | Evidence Log / PG-HMAC |
| PG-EVIDENCE | Acesso/serve/upload | T-14 | Portal+JWT serve parity | `portal_*_unit_test.ts`; `SPEC:evidence_go` | ci | Path org-bound; EXIF strip | Evidence Owner | QA/Security | Y | Flag evidence→Edge | 2 | Evidence Log / PG-EVIDENCE |
| PG-HASH | Sealing integridade | T-14 | Hash mismatch reject | `magic_bytes_test.ts`; `SPEC:hash_seal_go` | ci | Mismatch→fail closed | Evidence Owner | QA/Security | Y | Quarantine path only | 2 | Evidence Log / PG-HASH |
| PG-MONEY | BIGINT/BPS | Finanças | Snapshot cents idênticos | `SPEC:money_bps_parity` quando fatia financeira | ci | Zero float drift | Domain Owner | Architect | Y | Freeze fatia financeira | 2–4 | Evidence Log / PG-MONEY |
| PG-UTC | TIMESTAMPTZ/UTC | INV-6 | Diff UTC canonical | Scanner UTC-BLOCK + `SPEC:utc_canonical` | ci | Zero bare local time | Platform Owner | Senior | Y | Revert commit | contínuo | Evidence Log / PG-UTC |
| PG-APPEND-ONLY | Ledger imutável | INV-3 | Tentativa UPDATE/DELETE negada | pgTAP ledger + `SPEC:append_only_go` | local-supabase | Deny mutação | Data Platform Owner | QA/Security | Y | Emergency read-only | 1–2 | Evidence Log / PG-APPEND-ONLY |
| PG-REPLAY | Replay byte-idêntico | INV-15 | Hash verdict idêntico | `SPEC:evaluation_replay` (pós-port engine) | ci | Byte-identical | Domain Owner | Architect | Y | Freeze engine deploy | 2–4 | Evidence Log / PG-REPLAY |
| PG-SNAPSHOT | Rastreabilidade | INV-21 | Snapshot ID presente | `SPEC:snapshot_trace` | ci | Todo verdict linka snapshot | Domain Owner | QA/Security | Y | Flag engine off | 2–4 | Evidence Log / PG-SNAPSHOT |
| PG-INV26 | 404 parity | T-12 | Wrong-org == missing | `headers_integrity_404_pbt_test.ts` + `SPEC:inv26_go` | ci | Status/body opacity parity | Evidence Owner | QA/Security | Y | Flag route off | 2 | Evidence Log / PG-INV26 |
| PG-WEBHOOK | Sign/replay/SSRF | T-13,T-15 | SSRF deny + HMAC verify | `dispatch_verdict_webhooks_unit_test.ts`; `SPEC:webhook_worker_go` | ci | Private IP blocked; replay rejected | Webhook Owner | QA/Security | Y | Pause outbox drain | 2/5 | Evidence Log / PG-WEBHOOK |
| PG-AUDIT | Audit append-only | T-16,T-19 | Rows de SA/reveal/break-glass | `security_incident_log_*`; `SPEC:audit_completeness` | ci | Campos mínimos presentes; sem secrets | Security Owner | QA/Security | Y | Alert-only mode | contínuo | Evidence Log / PG-AUDIT |
| PG-OBSERVABILITY | Detecção | T-16,T-20 | Dashboards/alerts wired | `SPEC:o11y_dual_run_dashboards` | staging-dual-run | Correlação request-id; redaction | Platform Owner | Lead | N | N/A (não bloqueia auth) | 2–4 | Evidence Log / PG-OBSERVABILITY |
| PG-PERFORMANCE | Latência | Capacidade | p95 vs baseline medido | Baseline: k6 JSON em `docs/governance/k6_*.json` + `SPEC:perf_compare` | staging-dual-run | Dentro de budget **medido** (pending_baseline até quote) | Platform Owner | Senior | Y* | Flag off se regredir além budget | 4 | Evidence Log / PG-PERFORMANCE |
| PG-CAPACITY | Exhaustion | T-21 | Rate limit hold | Chaos scripts existentes + `SPEC:capacity_limits` | staging-dual-run | 429 sem crash; no data loss | Platform Owner | QA/Security | Y | Shed load; flag off | 4 | Evidence Log / PG-CAPACITY |
| PG-BACKUP | Backup cifrado | T-23 | Job backup + encrypt proof | `SPEC:backup_job_proof` (Etapa 1+) | drill | Backup existe; acesso controlado | Platform Owner | Lead | Y | Manter backups Supabase até cutover | 1–cutover | Evidence Log / PG-BACKUP |
| PG-RESTORE | Restore testado | T-23 | Restore drill report | `SPEC:restore_drill` | drill | RPO/RTO ≤ objetivos **ainda pending_quote** | Platform Owner | Lead | Y | Stay on Supabase | 1–cutover | Evidence Log / PG-RESTORE |
| PG-DR | Continuity | Ops | Runbook + drill | `SPEC:dr_drill` | drill | Objetivos DR pending_quote | Platform Owner | Lead | Y | Stay on Supabase | cutover | Evidence Log / PG-DR |
| PG-ROLLBACK | <15 min | ADR-013 | Exercício cronometrado | `SPEC:rollback_drill_route_flag` | drill | Rollback ≤15 min comprovado | Migration Owner | Lead | Y | Executar procedimento | 2–cutover | Evidence Log / PG-ROLLBACK |
| PG-OPENAPI | Compat contrato | Breaking change | Diff OpenAPI | `SPEC:openapi_breaking_check` (Etapa 2/4) | ci | Zero break sem versionamento | API Owner | Architect | Y | Revert OpenAPI commit | 2–4 | Evidence Log / PG-OPENAPI |
| PG-DUAL-RUN | Shadow compare | T-22 | Divergence report | `SPEC:shadow_compare_canonical` | staging-dual-run | Divergência ≤ budget (pending_baseline); writes single-owner | Migration Owner | Architect | Y | Shadow off; primary=legado | 2–4 | Evidence Log / PG-DUAL-RUN |
| PG-DIVERGENCE | Error budget shadow | T-22 | Séries temporais | `SPEC:divergence_slo` | staging-dual-run | Sem violação gates binários; budget pending_baseline | Migration Owner | QA/Security | Y | Pause cutover fatia | 2–4 | Evidence Log / PG-DIVERGENCE |

\* PG-PERFORMANCE bloqueante para cutover da fatia somente após baseline medido; até lá status `pending_baseline` (bloqueia Accepted de budgets numéricos, não bloqueia existência do contrato −1).

## Evidence Log

> Preencher somente com artefatos reais. Na Etapa −1: **vazio por design** (contrato, não execução).

### PG-AUTH
_(vazio)_

### PG-SESSION
_(vazio)_

### PG-REVOCATION
_(vazio)_

### PG-AAL2
_(vazio)_

### PG-IMPERSONATION
_(vazio)_

### PG-RLS
_(vazio)_

### PG-POOL-BLEED
_(vazio)_

### PG-CROSS-TENANT
_(vazio)_

### PG-INGEST
_(vazio)_

### PG-HMAC
_(vazio)_

### PG-EVIDENCE
_(vazio)_

### PG-HASH
_(vazio)_

### PG-MONEY
_(vazio)_

### PG-UTC
_(vazio)_

### PG-APPEND-ONLY
_(vazio)_

### PG-REPLAY
_(vazio)_

### PG-SNAPSHOT
_(vazio)_

### PG-INV26
_(vazio)_

### PG-WEBHOOK
_(vazio)_

### PG-AUDIT
_(vazio)_

### PG-OBSERVABILITY
_(vazio)_

### PG-PERFORMANCE
_(vazio)_

### PG-CAPACITY
_(vazio)_

### PG-BACKUP
_(vazio)_

### PG-RESTORE
_(vazio)_

### PG-DR
_(vazio)_

### PG-ROLLBACK
_(vazio)_

### PG-OPENAPI
_(vazio)_

### PG-DUAL-RUN
_(vazio)_

### PG-DIVERGENCE
_(vazio)_

## Pendências quantitativas (bloqueiam Accepted de budgets, registradas)

| ID | Item | Owner | Prazo | Gate | Impacto |
|----|------|-------|-------|------|---------|
| P-PERF-01 | Baseline p95 dual-run | Platform Owner | 2026-08-15 | PG-PERFORMANCE | Sem limiar numérico até medição |
| P-DIV-01 | Divergence error budget | Migration Owner | 2026-08-15 | PG-DIVERGENCE | Shadow sem SLO numérico |
| P-DR-01 | RPO/RTO objetivos self-host | Platform Owner | 2026-08-30 | PG-RESTORE, PG-DR | Bloqueia go/no-go ADR-010 |

**Owner deste documento:** QA Owner  
**Reviewer:** Lead Reviewer
