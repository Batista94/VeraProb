# ADR 010: Exit Ramp Supabase — Avaliação de Self-Host Candidate

**Date:** 2026-07-21
**Status:** Proposed
**Context:** Phase 11 Etapa -1

> **Numeração:** O ID `010` é intencional. Os slots `002`–`009` permanecem
> reservados/não utilizados; não há ADRs intermediários a preencher nesta etapa.

## Context

VeraProb opera hoje sobre a stack gerenciada Supabase (PostgreSQL + Auth +
Edge Functions + Storage + Realtime) com frontend Flutter Wasm. A Phase 11
Etapa −1 exige uma **avaliação formal de saída / exit ramp**, sem consumar
migração, para decidir se a plataforma permanece no provedor gerenciado,
adota um modelo híbrido, ou avança para um candidato de self-host
(Go API + OpenAPI + PostgreSQL 16 + React) como direção recomendada sob
avaliação.

Documentos irmãos (Etapa −1):

- [Proposta canônica Phase 11](../proposals/phase11_enterprise_pivot.md)
- [Inventário Edge Functions](../proposals/phase11_edge_functions_inventory.md)
- [Threat model](../proposals/phase11_threat_model.md)
- [Parity checklist](../proposals/phase11_parity_checklist.md)
- [ADR 011 — Auth Zero-Trust](./011_auth_zero_trust.md)
- [ADR 012 — RLS / connection lifecycle](./012_rls_connection_lifecycle.md)
- [ADR 013 — Strangler Fig](./013_strangler_fig.md)
- [Riscos residuais JWT P0](../../../forensic_records/plans/20260721000000_jwt_p0_residual_risks.md)

### Motivadores

1. **Soberania forense e isolamento multi-tenant (INV-1, INV-2, INV-22):**
   reduzir dependência de comportamentos opacos do provedor em Auth, RLS e
   Data API, especialmente onde revogação pré-`exp` e AAL2 ainda têm
   lacunas residuais (ver plano JWT P0).
2. **Controle de superfície de autenticação:** o JWT P0 da stack atual é
   **baseline temporário**, não o desenho final de auth em Go; Etapa −1
   deve separar “o que é seguro o bastante agora” de “o que a plataforma
   precisa no steady-state enterprise” (ADR 011).
3. **Capacidade e previsibilidade operacional:** telemetria de alta
   frequência, Edge Functions e cotas gerenciadas podem tornar-se
   restrição de escala; a hipótese precisa ser **mensurada**, não
   assumida.
4. **Reversibilidade e exit ramp contratual:** sem ramp documentado,
   qualquer lock-in vira risco de negócio não quantificado.
5. **TCO e FTE de ops:** custo total (provedor + engenharia + plantão +
   dual-run) precisa de tabela formal 12/24 meses; valores desconhecidos
   entram como pendências, nunca como inventário fictício.

### Baseline mensurável (campos)

| Campo | Descrição | Valor atual | Status |
|-------|-----------|-------------|--------|
| `baseline_provider` | Provedor de plataforma | Supabase (gerenciado) | measured |
| `baseline_db_engine` | Motor / major | PostgreSQL (versão de produção a confirmar no ambiente) | pending |
| `baseline_auth` | IdP / sessão | Supabase Auth + JWT P0 validator | measured |
| `baseline_edge` | Runtime de funções | Supabase Edge Functions (Deno) | measured |
| `baseline_frontend` | Cliente principal | Flutter Wasm / CanvasKit | measured |
| `baseline_rpo_declared` | RPO declarado (contrato/SLA interno) | — | pending |
| `baseline_rto_declared` | RTO declarado (contrato/SLA interno) | — | pending |
| `baseline_p95_ingest_ms` | Latência p95 ingest privilegiado | — | pending |
| `baseline_error_budget_monthly` | Error budget mensal | — | pending |
| `baseline_tenant_count` | Tenants ativos em produção | — | pending |
| `baseline_monthly_platform_cost` | Custo mensal plataforma (invoice) | — | pending |
| `baseline_fte_ops` | FTE ops/plantão atribuído | — | pending |
| `baseline_secret_reveal_aal2` | AAL2 em `reveal-webhook-signing-secret` | Não exigido (risco residual) | measured |
| `baseline_pre_exp_revocation` | Revogação pré-`exp` via `getClaims` | Limitada / não garantida | measured |

Campos `pending` bloqueiam promoção deste ADR para `Accepted` até
preenchimento com fonte e data.

## Alternatives Considered

### A) Permanecer em Supabase (gerenciado)

Manter Auth, Postgres, Edge e Storage no provedor atual; remediar apenas
riscos residuais P0/P1 (AAL2 no reveal; estratégia de revogação) sem
exit ramp estrutural.

- **Prós:** menor churn; aproveita RLS/Data API existentes; caminho curto
  para fechar gaps de segurança pontuais.
- **Contras:** lock-in; limites de introspecção/revogação de sessão;
  TCO e cotas ainda não baselineados; JWT P0 permanece baseline
  temporário sem destino claro.

### B) Híbrido (Postgres/Auth gerenciados + API própria)

Extrair gradualmente a superfície de aplicação (ingest, webhooks,
OCC APIs) para um serviço próprio, mantendo Postgres/Auth no Supabase
durante dual-run.

- **Prós:** reduz blast radius da migração; permite dual-run de auth
  (ver ADR 011); exit ramp incremental.
- **Contras:** dois planos de controle; risco de hybrid principal se
  claims/tenant não forem selados; custo operacional transitório
  (dual-run).

### C) Self-host candidate completo (Go API + OpenAPI + PG16 + React)

Candidato sob avaliação — **não** decisão aceita. Stack proposta para
estudo: API em Go com contrato OpenAPI, PostgreSQL 16 self-managed (ou
IaaS gerenciado não-Supabase), frontend React alinhado ao Design System
Industrial Dark, auth Zero-Trust conforme ADR 011.

- **Prós:** soberania de sessão/JWKS/revogação; contrato API estável;
  controle de RPO/RTO e capacity planning.
- **Contras:** FTE ops, hardening, migração de Flutter→React e de Edge
  Functions; risco de regressão forense se INVs não forem revalidados;
  TCO 12/24m ainda sem quotes.

## Decision

**Directions under evaluation (nenhuma Accepted):** (A) permanecer no
Supabase; (B) híbrido; (C) candidato self-host (Go API + OpenAPI +
PostgreSQL 16 + React). Exit ramp híbrido é o **caminho de transição
candidato** se, e somente se, os critérios go/no-go forem atendidos com
quotes e baselines medidas.

Esta seção **não** consome a migração e **não** elege C como default.
Não há compromisso de “vamos migrar”; há comparação obrigatória A/B/C
por quotes, baseline mensurável e gates de paridade de segurança
(incl. ADR 011). Se os critérios objetivos não justificarem a saída, a
decisão válida é **não migrar** (A ou B) e retornar ao first-tenant.

O JWT P0 da stack atual permanece **baseline temporário de autenticação**,
não o desenho final de auth em Go.

## TCO 12 / 24 meses (hipóteses — sem inventar valores)

> Qualquer célula sem fonte mensurada ou cotação formal permanece
> `pending_quote` / `assumption`. Promoção a `Accepted` exige fechar
> linhas de custo e FTE com `source` + `source_date`.

| cost_line | 12m_hypothesis | 24m_hypothesis | unit | method | source | source_date | confidence | status |
|-----------|----------------|----------------|------|--------|--------|-------------|------------|--------|
| platform_managed_supabase | — | — | BRL/year | invoice rollup | — | — | low | pending_quote |
| db_compute_storage_iops | — | — | BRL/year | capacity model × unit price | — | — | low | pending_quote |
| auth_provider_or_selfhost | — | — | BRL/year | vendor quote / self-host build | — | — | low | pending_quote |
| edge_or_api_runtime | — | — | BRL/year | traffic × compute | — | — | low | pending_quote |
| object_storage_egress | — | — | BRL/year | usage × egress tariff | — | — | low | pending_quote |
| observability_siem | — | — | BRL/year | seats + ingest GB | — | — | low | pending_quote |
| secrets_kms_hsm | — | — | BRL/year | key ops + vault | — | — | low | pending_quote |
| backup_dr_replication | — | — | BRL/year | RPO/RTO target × media | — | — | low | pending_quote |
| postgres_maintenance_patching | — | — | BRL/year | patch window × effort | — | — | low | pending_quote |
| incident_response_oncall | — | — | BRL/year | pager coverage model | — | — | low | pending_quote |
| fte_platform_engineering | — | — | FTE-year | effort model | — | — | low | pending_quote |
| fte_sre_oncall | — | — | FTE-year | pager coverage model | — | — | low | pending_quote |
| fte_security_authz | — | — | FTE-year | auth dual-run + audit | — | — | low | pending_quote |
| migration_oneoff_cutover | — | — | BRL | project estimate | — | — | low | pending_quote |
| dual_run_incremental_ops | — | — | BRL/year | dual-stack ops delta | — | — | low | pending_quote |
| training_runbooks | — | — | BRL | curriculum + drills | — | — | low | pending_quote |
| contingency_rollback_buffer | — | — | BRL | % of migration_oneoff | — | — | low | assumption |
| opportunity_cost_first_tenant_delay | — | — | BRL | roadmap delay vs first-tenant | — | — | low | pending_quote |

### Pendências econômicas (bloqueiam `Accepted`)

| ID | owner role | prazo | impacto | gate afetado | status |
|----|------------|-------|---------|--------------|--------|
| P-TCO-01 | Platform Owner (coleta) + Finance/CFO delegate (validação) | 2026-08-30 | Sem invoice rollup 12m não há comparação fair vs self-host | go/no-go cost; R-02 | pending |
| P-TCO-02 | Platform Engineering Lead | 2026-08-22 | Capacity model (ingest, storage, IOPS) sem medição | go/no-go capacity | pending |
| P-TCO-03 | SRE Lead | 2026-08-22 | FTE ops/plantão e custo de incident response não dimensionados | go/no-go cost + reliability | pending |
| P-TCO-04 | Security Lead | 2026-08-29 | Custo KMS/vault + SIEM para paridade forense | go/no-go security + cost | pending |
| P-TCO-05 | Engineering Manager | 2026-09-05 | Quote migração one-off + dual-run + buffer de rollback | go/no-go cost + reversibility | pending |
| P-TCO-06 | Product / Business Maverick | 2026-09-05 | Thresholds de custo (máx. delta 12/24m aceitável) e oportunidade first-tenant | go/no-go cost | pending |
| P-TCO-07 | SRE Lead | 2026-08-29 | RPO/RTO declarados + restore drill baseline | go/no-go reliability | pending |

**Nota:** thresholds numéricos de custo **não** são definidos neste ADR.
Qualquer promoção a `Accepted` sem quotes e thresholds preenchidos é
processo inválido.

## Critérios go / no-go (objetivos)

| Dimensão | Critério objetivo | Bloqueio se |
|----------|-------------------|-------------|
| **Security** | Paridade INV-1/2/22; AAL2 em reveal; revogação pré-`exp` com evidência; sem hybrid principal; gates `PG-AAL2` e `PG-REVOCATION` verdes (ADR 011) | Qualquer gap residual P0 sem owner/prazo |
| **Reliability** | Error budget e SLOs de ingest/OCC definidos e observados no baseline | `baseline_error_budget_monthly` pending |
| **Capacity** | Modelo de carga (tenants, eventos/s, storage) validado contra cotas atuais e alvo self-host | `baseline_tenant_count` / p95 pending |
| **RPO / RTO** | RPO/RTO declarados e testados (restore drill) no candidato ≥ baseline | `baseline_rpo_declared` / `baseline_rto_declared` pending |
| **Cost** | TCO 12/24m com quotes; delta vs baseline dentro de threshold aprovado pelo CFO | Todas as linhas `pending_quote` de custo/FTE; thresholds pending (P-TCO-06) |
| **Reversibility** | Exit ramp documentado com dual-run, feature flags e procedimento de rollback ≤ janela RTO | Ausência de runbook de rollback ou buffer P-TCO-05 |

**Go** somente se todas as dimensões acima estiverem `measured` ou
`pending_quote` resolvido com `confidence ≥ medium` e owners de decisão
assinarem a promoção de status (fora do escopo deste documento Proposed).

**No-go** (permanecer em A ou B) se security/reliability falharem, ou se
custo/reversibilidade permanecerem bloqueados após os prazos das
pendências.

## Riscos do self-host (candidato)

1. **Regressão forense:** perda de paridade RLS / security_invoker /
   partitions ao rehospedar PG16 (ADR 012).
2. **Ops maturity:** plantão, patching, backup, JWKS rotation e incidente
   Auth sem o envelope do provedor.
3. **Migração de cliente:** Flutter Wasm → React (candidato) implica
   revalidação UX OCC e goldens/hermeticidade.
4. **Dual-run Auth:** risco de hybrid principal se `organization_id` /
   SuperAdmin não forem estritamente separados (ADR 011).
5. **Subestimação de FTE:** linhas FTE estão `pending_quote` — decisão
   precoce cria dívida operacional.
6. **Custo de oportunidade:** atraso do first-tenant / Sandbox enquanto
   o pivot consome capacidade de engenharia.
7. **Riscos residuais herdados:** AAL2 em
   `reveal-webhook-signing-secret` e revogação pré-`exp` com `getClaims`
   (ver [plano JWT P0](../../../forensic_records/plans/20260721000000_jwt_p0_residual_risks.md))
   devem ser fechados ou explicitamente aceitos com owner antes de
   cutover.

## Exit ramp (proposta operacional)

> **Namespace:** passos abaixo usam IDs `XR-*` (exit-ramp). **Não** reutilizar
> os rótulos `Etapa 0..4` da proposta canônica (Specs IA → PG/RLS → OpenAPI/Go
> → React → CI). A sequência canônica de fase permanece em
> [phase11_enterprise_pivot.md](../proposals/phase11_enterprise_pivot.md) §3.

1. **XR-1 (Etapa −1 documental, atual):** ADRs Proposed + baseline + TCO
   pendências; Council PASS/REVISE do contrato.
2. **XR-2 (em paralelo à stack atual, pré-Etapa 1 de dados):** remediar P0
   Auth no Supabase (AAL2 reveal; desenho de revogação) **sem** mudar
   provedor — não é a “Etapa 0 Specs IA”.
3. **XR-3 (após PASS −1 + Etapas 0–2 canônicas):** dual-run de borda
   (OpenAPI/Go) contra Supabase; Auth conforme ADR 011; tenant conforme
   ADR 012; fatias conforme ADR 013.
4. **XR-4:** rehearsal de continuidade (backup/restore / replicação quando
   aplicável) com RPO/RTO **medidos** (não inventados).
5. **XR-5:** decisão go/no-go com TCO preenchido; só então promover ADRs
   para `Accepted` ou arquivar como `Rejected`/`Superseded`.
6. **Aborto econômico/técnico:** ROI negativo, threshold de custo excedido,
   ou gate crítico de segurança/reliability falho → **manter a stack
   atual** (alternativa A ou B) e **retornar o programa ao objetivo
   first-tenant**, sem penalizar a decisão de não migrar.
7. **Rollback operacional:** feature flags + tráfego shadow; abortar
   cutover se gates `PG-AAL2` / `PG-REVOCATION` ou error budget falharem.

## Owners

| Papel | Responsabilidade |
|-------|------------------|
| **Architect** | Recomendação técnica da direção (candidato vs híbrido vs stay) |
| **QA/Security** | Validação de paridade INV + gates `PG-AAL2` / `PG-REVOCATION` |
| **Senior Engineer / Platform** | Baseline mensurável, capacity model, dual-run técnico |
| **SRE Lead** | RPO/RTO drills, FTE ops, runbooks de rollback |
| **Finance / CFO delegate** | Quotes TCO 12/24m e thresholds de custo (validação financeira) |
| **Lead Reviewer / Engineering Council** | Decisão formal de promoção de status (futuro; não neste ADR) |
| **Business Maverick** | ROI / no-go se complexidade sem impacto financeiro claro; aceite de oportunidade |

## Consequences

- **Positive (se validado):** exit ramp explícito; TCO e FTE deixam de ser
  narrativa informal; JWT P0 fica marcado como temporário; candidato
  Go/OpenAPI/PG16/React pode ser comparado com critérios objetivos;
  aborto econômico é caminho válido, não falha de processo.
- **Negative / custo de processo:** Etapa −1 gera trabalho de medição e
  cotação antes de qualquer código de migração; thresholds de custo
  bloqueiam `Accepted` até P-TCO-* fecharem; dual-run tem custo
  incremental (`dual_run_incremental_ops`).
- **Security:** riscos residuais JWT P0 permanecem na stack atual até
  remediação; self-host não é atalho para ignorá-los.
- **Não-consequência:** este ADR **não** autoriza cutover, troca de
  frontend, nem desligamento do Supabase Auth.
