# VeraProb — Roadmap Estratégico

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
| Bloco 8.1 - 8.7 | **CONCLUÍDOS** — UX, CI/CD, Env, Obs, Hardening, Performance, Disaster Recovery. ✅ |
| Banco de dev | Todas as migrations aplicadas — `20260325...` |

---

## Fases Pendentes (Próximas Etapas)

### [x] Phase 8 — Operational Hardening ✅

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

#### [x] 8.6 — Performance & Escala ✅
- Load testing (1.000 veículos) e benchmark do Evaluation Engine.
- Revisão de índices e avaliação de read replicas.

#### [x] 8.7 — Disaster Recovery ✅
- Runbook de restore e testes de backup (Supabase PITR).

#### [x] 8.8 — Auditoria de Integridade de Telemetria (Anti-Spoofing) ✅
- Detecção de Fake GPS e anomalias cinemáticas. (CONCLUÍDA 2026-03-19)

---

### [ ] Phase 9 — Technical Review & Refinement

**Objetivo:** Revisão profunda do código e ajustes finos antes da exposição externa.

#### [ ] 9.1 — Code Review Geral
- Auditoria de possíveis débitos técnicos acumulados nas Fases 6 a 8.
- Validação de tipagem e null-safety em Edge Functions.

#### [ ] 9.2 — UX Refactorings
- Polimento visual baseado nos feedbacks da Phase 8.1.
- Revisão de fluxos de erro e estados vazios (Empty States).

#### [ ] 9.3 — Business Rule Fine-tuning
- Ajustes finais no Evaluation Engine para casos de borda identificados no Load Testing.

---

## Fases Concluídas (Histórico Resumido)

- **Phase 8.8 — Auditoria de Integridade (Anti-Spoofing)** ✅: Detecção de Fake GPS e anomalias cinemáticas (INV-21).
- **Phase 8.7 — Disaster Recovery** ✅: Runbook de restore e PITR configurado.
- **Phase 8.6 — Performance & Escala** ✅: Benchmark de 1.000 VUs, scripts k6 de caos/estresse e otimização de índices.
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
[x] Phase 5, 6, 6.5, 7, 7.5, 8.1 - 8.8 COMPLETE ✅
─────────────────────────────────────────────────────
