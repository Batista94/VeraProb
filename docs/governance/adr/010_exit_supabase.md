# ADR 010: Exit Ramp Supabase — A portável (avaliação A/B/C)

**Date:** 2026-07-21
**Status:** Accepted
**Context:** Phase 11 Etapa −1 — revisão H2.1 (A portável)
**source_date (lista pública de preços):** 2026-07-21

> **Numeração:** O ID `010` é intencional. Os slots `002`–`009` permanecem
> reservados/não utilizados; não há ADRs intermediários a preencher nesta etapa.

### Decision record

| Campo | Valor |
|-------|-------|
| Status anterior | Proposed (revisão H2.1 — A portável) |
| Status atual | **Accepted** |
| Authority | Fundador |
| Confirmed | 2026-07-21 |
| Council | H2.1 PASS (Architect, Senior, QA/Security) + Lead PASS_DOCUMENTAL |
| Scope of acceptance | Direção A portável; B/C permanecem contratos condicionais de saída |
| Explicitly not authorized | Proposta canônica, roadmap, Etapa 0, commit, implementação |

## Context

VeraProb opera hoje sobre a stack gerenciada Supabase (PostgreSQL + Auth +
Edge Functions + Storage + Realtime) com frontend Flutter Wasm, em postura
**pré-revenue** (desembolso de plataforma atual **R$ 0**).

A Phase 11 Etapa −1 exige avaliação formal de saída / exit ramp **sem
consumar migração**. Nesta revisão H2, a direção proposta é **A portável**:
permanecer em Supabase/Flutter, corrigir portabilidade, revogação e
recuperação antes do primeiro piloto; B e C ficam como contratos
condicionais de saída, reabertos só por gatilhos objetivos.

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

1. **Soberania forense e isolamento multi-tenant (INV-1, INV-2, INV-22)**
   sem novo desembolso antes do piloto.
2. **Revogação pré-`exp` e DR exercitável** na stack atual (ADR 011 +
   gates PG-BACKUP/RESTORE/DR) antes de first-tenant.
3. **Exit ramp contratual** sem lock-in não quantificado: B/C documentados,
   não aprovados.
4. **TCO pré-revenue honesto:** lista pública USD + fórmulas; sem inventar
   invoice; sem tratar preço de lista como cotação comercial.

### Baseline mensurável (campos)

| Campo | Descrição | Valor atual | Status |
|-------|-----------|-------------|--------|
| `baseline_provider` | Provedor de plataforma | Supabase (gerenciado) | measured |
| `baseline_db_engine` | Motor / major | PostgreSQL (versão de produção a confirmar no ambiente) | pending (non-blocking para A) |
| `baseline_auth` | IdP / sessão | Supabase Auth + JWT P0 validator | measured |
| `baseline_edge` | Runtime de funções | Supabase Edge Functions (Deno) | measured |
| `baseline_frontend` | Cliente principal | Flutter Wasm / CanvasKit | measured |
| `baseline_rpo_declared` | RPO pré-prod | 24h (sem SLA) | decided (P-DR-01) |
| `baseline_rto_declared` | RTO pré-prod | 24h (sem SLA) | decided (P-DR-01) |
| `baseline_monthly_platform_cost` | Desembolso mensal plataforma | **R$ 0** (Free / pré-revenue) | measured |
| `baseline_secret_reveal_aal2` | AAL2 em reveal | Exigido (`REVEAL_REQUIRE_AAL2=true`) | measured (CLOSED) |
| `baseline_pre_exp_revocation` | Revogação pré-`exp` | Design CLOSED; runtime OPEN (`P-REV-IMPL-01`) | design_closed |
| `baseline_prod_rpo_rto_runbook` | Objetivo prod `<5min/<4h` | **Não aprovado** nesta fase | deferred |

## Alternatives Considered

### A) A portável — permanecer em Supabase + Flutter (direção proposta)

Manter Auth, Postgres, Edge e Storage no provedor atual; fechar portabilidade
de contratos, revogação server-side (registro PG) e DR pré-prod **antes do
primeiro piloto**; sem novo desembolso agora.

- **Prós:** zero cash out-of-pocket agora; caminho curto para piloto; RLS/Data
  API existentes; Flutter preservado; React fora do plano.
- **Contras:** lock-in residual; Free sem daily backup automático do
  provedor (exige dump off-site); cotas Free; revogação runtime ainda a
  implementar.

### B) Híbrido (Postgres/Auth gerenciados + API própria)

Extrair superfície de aplicação para serviço próprio, mantendo
Postgres/Auth no Supabase durante dual-run.

- **Prós:** exit ramp incremental; reduz blast radius.
- **Contras:** dois planos de controle; dual-run ops; risco de hybrid
  principal; desembolso + tempo do fundador maiores.

### C) Self-host candidate completo (Go API + OpenAPI + PG16 + React)

Candidato sob avaliação futura — **não** decisão. Stack de estudo: Go +
OpenAPI + PostgreSQL 16 + React.

- **Prós:** soberania de sessão/JWKS/revogação; RPO/RTO sob controle próprio.
- **Contras:** FTE ops, migração Flutter→React, dual-run, risco forense,
  TCO cash e econômico elevados no pré-revenue.

## Decision

**Direção Accepted:** **A portável**.

B e C **não** estão cancelados nem aprovados. Permanecem contratos
condicionais de saída. Cutover **não agendado**. Um gatilho objetivo
autoriza **nova análise**, nunca migração automática.

O JWT P0 da stack atual permanece **baseline temporário de autenticação**;
o desenho de revogação é ADR 011 (registro PostgreSQL), não “auth Go
agora”.

## Fontes de preço (lista pública — não cotação comercial)

| Item | Valor (USD) | Fonte | source_date | Notas |
|------|-------------|-------|-------------|-------|
| Free plan | $0 / mês | [supabase.com/pricing](https://supabase.com/pricing) | 2026-07-21 | Desembolso atual VeraProb = R$ 0 |
| Pro plan | from $25 / org / mês | idem | 2026-07-21 | Compute separado; ~$10 crédito compute |
| Team plan | from $599 / org / mês | idem | 2026-07-21 | SOC2/ISO; backups 14d |
| Enterprise | custom | idem | 2026-07-21 | Não usar como quote |
| Daily backups Free | não incluídos | [Backups docs](https://supabase.com/docs/guides/platform/backups) | 2026-07-21 | Usar `db dump` + off-site |
| Daily backups Pro | 7 dias | idem | 2026-07-21 | |
| Daily backups Team | 14 dias | idem | 2026-07-21 | |
| Daily backups Enterprise | até 30 dias | idem | 2026-07-21 | |
| PITR add-on | ~$100 / $200 / $400 (7/14/28d) | idem | 2026-07-21 | Lista pública aproximada |
| Storage objects no DB backup | **não incluídos** | idem | 2026-07-21 | Blobs exigem cópia separada |
| Câmbio USD→BRL | variável | — | — | **Não fixar FX**; converter só na reavaliação |
| Impostos / descontos / enterprise | excluídos | — | — | Lista ≠ cotação comercial |

## TCO — fórmulas (4 estágios × 3 faixas × 12/24 meses)

### Estágios operacionais

| # | Estágio | Variáveis típicas (não inventar volumes) |
|---|---------|------------------------------------------|
| 1 | Desenvolvimento atual | `T≈0` tenants pagantes; `E` baixo; Free |
| 2 | Primeiro piloto (1–3 tenants) | `T∈[1,3]`; `E`,`S`,`G` variáveis |
| 3 | Operação inicial | `T`,`E`,`S`,`R`,`G` medidos pós-piloto |
| 4 | Crescimento posterior | Escala; possível tier pago / B/C |

Faixas por estágio: **otimista / base / pessimista** — parametrizar
`T` (tenants), `E` (eventos), `S` (storage), `R` (retenção), `G` (egress)
sem preencher números fictícios de uso.

### Fórmulas

```text
TCO_cash(M) = plataforma + compute + banco + storage + egress
            + backup/DR + observabilidade + segurança/KMS
            + operação + incident_response + migração + dual_run

TCO_economic(M) = TCO_cash(M)
                + (H_build + H_ops + H_security + H_incident) × V_fundador
```

`V_fundador` é variável econômica aprovada **somente** quando houver decisão
de investimento; nesta fase o trabalho do fundador **não** gera desembolso
(`TCO_cash` atual de plataforma = R$ 0).

Horizontes: agregar `TCO_*(12)` e `TCO_*(24)` por alternativa A/B/C e por
faixa.

### Separação obrigatória de dimensões

| Dimensão | Conteúdo |
|----------|----------|
| Desembolso | Cash out-of-pocket (hoje R$ 0 em A/Free) |
| Tempo do fundador | Horas/FTE (pré-revenue accountable) |
| Custo projetado | USD lista pública × câmbio variável |
| Oportunidade | Atraso first-tenant / piloto se B/C agora |
| Risco | Lock-in, ops, compliance, regressão forense |

### Matriz resumida (qualitativa — sem inventar invoice)

| Alt | Estágio 1 cash | Estágio 2 cash | 12/24m nota | Tempo fundador | Risco dominante |
|-----|----------------|----------------|-------------|----------------|-----------------|
| **A** | $0 lista Free | Free ou Pro se cotas/backup exigirem (gatilho) | Menor cash pré-revenue; dump off-site obrigatório | Médio (revogação+DR) | Lock-in + Free limits |
| **B** | Plataforma + API própria + dual-run | Cresce com dual-run | Cash + ops dual-stack | Alto | Hybrid principal / drift |
| **C** | IaaS/PG + Go + (React futuro) + dual-run | Alto | Maior cash + FTE | Muito alto | Regressão forense / ops |

**Conclusão econômica desta revisão:** em pré-revenue, **A portável**
minimiza desembolso e risco de atraso do piloto; B/C só após gatilho +
quotes reais (P-TCO-02..07).

## P-DR-01 — Continuidade pré-produção

| Campo | Valor |
|-------|-------|
| RPO pré-prod | **24h** |
| RTO pré-prod | **24h** |
| SLA | **Nenhum** nesta fase |
| Backup mínimo | Dump lógico diário **cifrado** em localização **independente** do projeto Supabase |
| Storage objects | Classificar: descartáveis de dev podem ficar fora; qualquer objeto necessário ao piloto exige **cópia diária separada** (DB backup **não** restaura blobs) |
| Restore | Exercitado e evidenciado **antes do primeiro piloto** (`PG-RESTORE`) |
| Runbook `<5 min / <4h` | Objetivo de **produção não aprovado**; **não** editar o runbook nesta missão |

Gates: `PG-BACKUP`, `PG-RESTORE`, `PG-DR` permanecem `NOT RUN` até Etapa 1;
bloqueiam piloto, não confundem com decisão P-DR-01.

## Pendências econômicas

| ID | owner role | status | Nota |
|----|------------|--------|------|
| P-TCO-01 | Platform + Finance (fundador) | **resolved_for_A** | Decisão A sustentada por desembolso atual R$ 0 + **fórmulas** 4×3×12/24 + lista pública USD; células numéricas de volume (`T,E,S,R,G`) permanecem variáveis — **não** invoice medido |
| P-TCO-02 | Platform Engineering | deferred_non_blocking_for_A | Obrigatório antes de Approved B/C |
| P-TCO-03 | SRE / fundador | deferred_non_blocking_for_A | FTE ops B/C |
| P-TCO-04 | Security | deferred_non_blocking_for_A | KMS/SIEM paridade B/C |
| P-TCO-05 | Engineering Manager | deferred_non_blocking_for_A | Migração one-off + dual-run |
| P-TCO-06 | Product / Business Maverick | deferred_non_blocking_for_A | Thresholds custo B/C |
| P-TCO-07 | SRE | deferred_non_blocking_for_A | Quotes DR B/C; pré-prod A coberto por P-DR-01 |
| P-DR-01 | Platform Owner | **resolved_objective** | 24h/24h; runtime gates NOT RUN |

## Critérios go / no-go

### Para manter A portável (agora)

| Dimensão | Critério |
|----------|----------|
| Security design | ADR-011 design CLOSED; AAL2 CLOSED; `P-REV-IMPL-01` trackado |
| DR objective | P-DR-01 24h/24h declarado |
| Cost | Desembolso atual R$ 0; tier pago = gatilho |
| Scope | Sem Go/React produtivo; React fora do plano |

### Para aprovar B ou C (futuro)

Todas as dimensões Security / Reliability / Capacity / RPO-RTO / Cost /
Reversibility com P-TCO-02..07 resolvidos, dual-run gates e Council +
fundador. **Go** só então.

## Gatilhos objetivos (reabrir A/B/C)

Um gatilho autoriza **nova análise**, não migração automática:

1. Primeiro piloto
2. Primeiro cliente pagante
3. Ativação de tier pago
4. Requisito de compliance / residência
5. Primeiro SLA
6. Crescimento material de ingestão / storage
7. Mudança relevante de fatura
8. Revisão trimestral
9. Antes de ação irreversível

## Exit ramp (XR-*)

> Namespace `XR-*` — **não** reutilizar rótulos Etapa 0..4 da proposta
> canônica.

1. **XR-1 (concluído documentalmente):** ADRs 010–013 **Accepted** (fundador
   2026-07-21) + A portável + Council H2.1 PASS; implementação/Etapa 0
   **não** autorizadas neste registro.
2. **XR-2:** remediação na stack atual — `P-REV-IMPL-01`, backup/restore
   drills (Etapa 1 canônica).
3. **XR-3+:** dual-run / self-host **somente** após gatilho + go/no-go B/C.
4. **Aborto econômico:** ROI negativo ou gate crítico → permanecer em A e
   focar first-tenant.

## Owners

| Papel | Responsabilidade |
|-------|------------------|
| **Architect** | Direção A vs B/C; contratos condicionais |
| **QA/Security** | Paridade INV + PG-AAL2 / PG-REVOCATION |
| **Senior Engineer / Platform** | Baseline, capacity, portabilidade |
| **SRE / fundador** | RPO/RTO drills, dump off-site |
| **Finance / fundador** | Validação TCO_cash vs lista pública |
| **Lead Reviewer** | Promoção formal de status (futuro) |
| **Business Maverick** | ROI / no-go se complexidade sem impacto |

## Consequences

- **Positive:** direção clara sem desembolso; B/C documentados; TCO honesto
  (lista ≠ quote); DR pré-prod explícito; AAL2 fechado; revogação design
  fechada.
- **Negative:** Free exige disciplina de dump/Storage; runtime revogação e
  restore ainda bloqueiam piloto; lock-in permanece até gatilho.
- **Não-consequência:** este ADR **não** autoriza cutover, Go/React, nem
  implementação; status **Accepted** cobre a direção documental A portável.
