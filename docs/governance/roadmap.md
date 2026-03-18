# PactaFlow — Roadmap Estratégico

---

## Estado do Codebase (referência para novas sessões)

| Aspecto | Estado |
|---------|--------|
| Testes | 568 passing · 0 falhas ✅ |
| Análise estática | 0 erros · 11 infos |
| Precisão financeira | `Money` (centavos BIGINT) — Enforced ✅ |
| Sprint 5.11 - 5.13 | **CONCLUÍDAS** — JIT Master Data, RLS, Teto Financeiro. ✅ |
| Phase 6 & 6.5 | **CONCLUÍDAS** — Admin, RBAC, Operational Resilience. ✅ |
| Phase 7 & 7.5 | **CONCLUÍDAS** — Audit Exports, Financial Defense. ✅ |
| Bloco 8.1 - 8.5 | **CONCLUÍDOS** — UX Hard Gates, CI/CD, Env, Obs, Hardening. ✅ |
| Banco de dev | Todas as migrations aplicadas — `20260325...` |

---

## Fases Pendentes (Próximas Etapas)

### [ ] Phase 8 — Operational Hardening

**Objetivo:** Preparar o fluxo sistêmico e a infraestrutura para produção real.

#### [x] 8.2 — CI/CD Pipeline ✅
- **Artefatos:** `.github/workflows/ci.yml` · `.github/workflows/deploy_staging.yml` · `.github/workflows/deploy_prod.yml`
- Automação de `flutter analyze`, `flutter test` e deploy para Staging/Prod com gate humano em prod.

#### [x] 8.4 — Observabilidade ✅
- Integração Sentry (Flutter + Edge Functions) e PostHog.
- Logging estruturado e alertas de performance/erro.

#### [x] 8.5 — Segurança (Hardening Final) ✅
- `strict-casts: true` e correção de tipos `dynamic`.
- Field-level masking para PII e remoção de políticas Public Read remanescentes.

#### [ ] 8.6 — Performance & Escala
- Load testing (1.000 veículos) e benchmark do Evaluation Engine.
- Revisão de índices e avaliação de read replicas.

#### [ ] 8.7 — Disaster Recovery
- Runbook de restore e testes de backup (Supabase PITR).

#### [ ] 8.8 — Auditoria de Integridade de Telemetria (Anti-Spoofing)
- Detecção de Fake GPS e anomalias cinemáticas.

---

### [ ] Trilha D — Lançamento

**Objetivo:** Go-to-market, documentação de produto e piloto controlado.

#### [ ] D1 — Documentação de Produto
- Landing page, guias de onboarding e integração.

#### [ ] D2 — Modelo Comercial
- Pricing, Termos de Uso (LGPD) e integração Stripe.

#### [ ] D3 — Piloto Beta Controlado
- Seleção de 2-3 clientes reais e monitoramento intensivo.

---

## Fases Concluídas (Histórico Resumido)

- **Phase 8.2 — CI/CD Pipeline** ✅: Workflows GitHub Actions (`ci.yml`, `deploy_staging.yml`, `deploy_prod.yml`) com gate humano em prod.
- **Phase 8.5 — Segurança (Hardening Final)** ✅: `strict-casts: true`, correção de `dynamic` e PII masking em SQL.
- **Phase 8.4 — Observabilidade** ✅: Integração Sentry e PostHog configurada para todos os ambientes.
- **Phase 8.3 — Separação de Ambientes** ✅: Suporte multi-env configurado (`--dart-define` + `.env`).
- **Phase 8.1 — Systemic UX & Hard Gates** ✅: Invariantes INV-18/19/20 e refatoração visual.
- **Phase 7.5 — Financial Defense** ✅: Shadow Mode e Blindagem Forense PostgreSQL.
- **Phase 7 — Evidence & Audit Exports** ✅: Relatórios imutáveis e Portal de Transparência.
- **Phase 6.5 — Operational Resilience** ✅: Anti-Corruption Edge e Chaos Tolerance.
- **Phase 6 — Administration** ✅: RBAC, Convites e Workflow de Aprovação.
- **Phase 5 — B2B Foundation** ✅: JIT Master Data e RLS Tenant Isolation.

---

## Visão Geral de Execução

─────────────────────────────────────────────────────
[x] Phase 5, 6, 6.5, 7, 7.5 ✅
─────────────────────────────────────────────────────
[x] Phase 8.1 - 8.5 COMPLETE ✅
─────────────────────────────────────────────────────
[ ] Phase 8.6 - 8.8 PENDING
─────────────────────────────────────────────────────
