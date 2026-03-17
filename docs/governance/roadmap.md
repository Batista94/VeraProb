# PactaFlow — Roadmap Estratégico

---

## Estado do Codebase (referência para novas sessões)

| Aspecto | Estado |
|---------|--------|
| Testes | 438 passing · 0 falhas ✅ |
| Análise estática | 0 erros · 75 infos |
| Precisão financeira | `Money` (centavos BIGINT) — Enforced ✅ |
| Sprint 5.11 - 5.12 | **CONCLUÍDAS** — JIT Master Data, RLS, UTC. |
| Sprint 5.13 | **CONCLUÍDA** — Teto Financeiro, Carência (Grace Period) e Risk KPIs. ✅ |
| Phase 6 | **CONCLUÍDA** — Administration, RBAC, Invitations e Approval Workflow. ✅ |
| Bloco 8 | **CONCLUÍDO** — Asset Manager, `organization_id` isolation, tabbed CRUD. ✅ |
| Banco de dev | Todas as migrations aplicadas — `20260322...` |

## Fases Pendentes

### [x] Phase 5 — B2B Refactoring & Foundation (CONCLUÍDA) ✅
*   **Resultados:** JIT Master Data, RLS, Teto Financeiro, Carência e Evidence Locker validados.

---

### [ ] Phase 6 — Administration & Tenant Self-Service 🚀

#### BLOCOS 1 a 8 — CONCLUÍDOS ✅
*Arquivamento de tarefas concluídas para otimização de contexto.*

*   **1-3 Foundation:** RLS JWT Path unification, `Contractor` Aggregate, `RbacService` & guards.
*   **4-5 Management:** CRM de Organizações, Membros e Contractors. Fluxo de convite via token.
*   **6 Approval:** Workflow de aprovação de contratos com tokens de review público.
*   **7 Rule Studio:** Edição atômica de regras, versionamento, simulação de impacto e `gracePeriod`.
*   **8 Asset Manager:** `organization_id` em `drivers`, `routes`, `vehicles` (nova tabela). RLS tenant isolation. `VehiclesTab`, `RoutesTab`, `ResourceManagementScreen` tabbed CRUD. 438 passing.
*   **SQL:** Migrations 20260317... a 20260322... aplicadas e validadas.
*   **Testes:** 438 passing (100% Green).

#### BLOCO 9 — First Run Flow & Phase 6 Validation
- [ ] 9.1 Public Organization Self-Registration (`/register`)
- [ ] 9.2 First Run Wizard (Guided 5-step flow)
- [ ] 9.3 Automated Scenarios (Isolation, RBAC, Immutability)
- [ ] 9.4 Compliance Report: `docs/governance/compliance/phase6_compliance_report.md`
- [ ] 9.5 **UX Polish**: Add `semanticsLabel` to critical icons and implement premium transitions for the "Digital Judge" feel.
- **SQL:** `20260323000001_org_registration_rpc.sql`
 [ ] 9.4 Compliance Report: `docs/governance/compliance/phase6_compliance_report.md`
- **SQL:** `20260323000001_org_registration_rpc.sql`

---

### [ ] Phase 7 — Evidence & Audit Exports

**Por que depois de Phase 6:** Exportações são o produto que o cliente entrega ao seu próprio cliente
(empresa de transporte entregando relatório de SLA ao contratante). Só faz sentido gerar esse produto
quando a plataforma tem clientes reais com dados reais fluindo.

**Nota:** Fundação parcialmente implementada — `BillingCycleReport` domain entity completo com
agregação determinística e ID canônico. `BillingCycleReportsScreen` existe com estrutura UI.
Phase 7 completa e formaliza essa fundação.

**Objetivo:** Transformar os snapshots financeiros imutáveis em evidências acionáveis —
relatórios de conformidade, exports para controladoria e auditoria, dashboard executivo.

#### [ ] 7.1 — Design Specification
**Artefato:** `docs/architecture/11_evidence_audit_exports_design.md`

Cobrir obrigatoriamente:
- **Billing Cycle Report:** completar implementação da `BillingCycleReportsScreen` (CSV export, período customizável, filtro por contrato)
- **Monthly Compliance Report:** aggregation pipeline usando `pg_cron` (job mensal por org/contrato)
- **PDF export:** layout de relatório para auditoria (cabeçalho, sumário executivo, detalhamento por SET)
- **Executive Dashboard:** KPIs agregados — taxa de compliance, receita protegida/em risco/perdida por período
- **Provenance chain:** relatório exportado referencia `snapshotIds` e `ledgerEntryIds` — rastreável ao evento original
- **Imutabilidade:** relatórios gerados são read-only — qualquer regeneração cria nova versão, nunca sobrescreve
- **Tenant scoping:** jobs `pg_cron` processam 1 `organization_id` por vez — sem cross-tenant analytics
- **Portal de Transparência do Contratante:** Dashboard executivo de acesso restrito ao contratante. KPIs: `Receita Protegida` vs `Multas Recuperadas`. Download autônomo de relatórios de conformidade e evidências sem intervenção do operador.
  - **Design:** Wireframe do dashboard externo e tokens de acesso por contratante.
  - **Review:** Garantir que contratante acesse apenas seus próprios contratos (Zero Trust).
  - **Implementation:** Criar rotas de apresentação e aggregators financeiros específicos.
  - **Validation:** Smoke test de login de contratante e exportação autônoma de CSV.

#### [ ] 7.2 — Council Review
Validar antes de implementar:
- Jobs de aggregation operam sobre snapshots imutáveis, não sobre o ledger bruto
- Export CSV/PDF derivado dos snapshots do período — replay produz o mesmo arquivo
- `pg_cron` jobs include `organization_id` explícito — sem scans globais
- Relatório exportado não pode ser alterado após gerado

#### [ ] 7.3 — Implementation
- **SQL:** `monthly_compliance_reports` table, `pg_cron` jobs de fechamento mensal, indexes
- **Domain:** `ComplianceReport` entity (se necessário além de `BillingCycleReport`)
- **Application:** `ReportGenerationService`, `CsvExportService`, `PdfExportService`
- **Infrastructure:** Repositórios para reports, integração `pg_cron`
- **Presentation:**
  - Completar `BillingCycleReportsScreen` (export CSV funcional, seleção de período)
  - Tela de relatórios mensais de compliance
  - Export PDF para auditoria
  - Executive Dashboard com KPIs por período
  - Portal de Transparência (Dashboard executivo + export autônomo)
    - **Design:** (Conforme especificado em 7.1)
    - **Review:** Validar consistência dos KPIs financeiros entre portal e admin.
    - **Implementation:** Implementar UI do dashboard de transparência.
    - **Validation:** Confirmar que download de evidências funciona via link direto do portal.

#### [ ] 7.4 — Validation

**Cenários automatizados:**
- Cenário 7.1: Relatório mensal produz totais idênticos à soma dos snapshots diários do período
- Cenário 7.2: Export CSV de Org A não contém nenhum dado de Org B
- Cenário 7.3: Regenerar relatório do mesmo período produz arquivo matematicamente idêntico (determinismo)
- Cenário 7.4: Relatório exportado contém `snapshotIds` rastreáveis ao ledger original
- Cenário 7.5: Job `pg_cron` não reprocessa snapshots já fechados

**⚠️ Testes Manuais Obrigatórios (verificação visual de outputs):**
> Downloads de arquivo e rendering de PDF/CSV não podem ser validados por `flutter test`.

- [ ] **Export CSV:** clicar em "Exportar CSV" → baixar arquivo → abrir em planilha → verificar que colunas, valores monetários (em reais, não centavos) e encoding (UTF-8 com BOM para Excel) estão corretos
- [ ] **Export PDF:** gerar relatório de auditoria → abrir PDF → verificar cabeçalho da org, período, totais financeiros e referência ao `snapshotId`
- [ ] **Determinismo visual:** gerar o mesmo relatório duas vezes → comparar arquivos — devem ser byte-a-byte idênticos (exceto timestamp de geração se houver)
- [ ] **Executive Dashboard:** navegar pelo dashboard com dados reais de ≥ 1 mês → verificar que KPIs de receita protegida/em risco/perdida batem com a soma dos snapshots no Supabase
- [ ] **Rastreabilidade:** clicar em um valor do relatório → verificar que o link/referência leva ao ledger entry original

- **Compliance Report:** `docs/governance/compliance/phase7_compliance_report.md`

---

### [ ] Phase 8 — Operational Hardening

**Por que depois de Phase 7:** O hardening operacional prepara o produto para receber tráfego real.
Executá-lo antes de ter todas as features seria otimizar prematuramente —
testar performance e CI/CD de algo incompleto é trabalho dobrado.

**Objetivo:** Transformar o projeto de "dev pessoal" em infraestrutura operável.
Esta phase não adiciona features — garante que as existentes sejam confiáveis, monitoráveis,
seguras e recuperáveis em produção.

#### [ ] 8.1 — CI/CD Pipeline
**Artefatos:** `.github/workflows/ci.yml` · `.github/workflows/deploy.yml`

```
Pull Request →
  flutter analyze (zero erros)
  flutter test --no-pub (todos passing)
  flutter build web

Push main →
  todos os passos acima
  deploy automático → Staging (PactaFlow-staging no Supabase)

Tag vX.Y.Z →
  todos acima
  deploy → Production (aprovação manual obrigatória)
```

#### [ ] 8.2 — Separação de Ambientes
- 3 projetos Supabase: `PactaFlow-dev` · `PactaFlow-staging` · `PactaFlow-prod`
- Processo de promoção de migrations: dev → staging → prod (nunca pular)
- `--dart-define` injetados por ambiente no CI (sem `.env` em pipeline)
- Dados de teste **nunca** chegam em prod

#### [ ] 8.3 — Observabilidade
- Error tracking: Sentry (Flutter SDK + Supabase Edge Functions)
- Logging estruturado: JSON com `organization_id`, `user_id`, `correlation_id` em cada entrada
- Substituir todos os `print()` por logger estruturado (detectáveis via `avoid_print` já ativo)
- Alertas: notificação se ledger write > 2s ou taxa de erro > 1%

#### [ ] 8.4 — Segurança (Hardening Final)
- Remover políticas `Public Read` das tabelas críticas no RLS
- Adicionar `mutated_by_user_id` + `mutated_reason` nas tabelas mutáveis (`execution_states`, `operational_alerts`)
- **Type-safety pass:** habilitar `strict-casts: true` e corrigir ~80 erros de `dynamic` nos repositórios Postgres
- Field-level masking para PII (nome de motorista, placa onde exposto em queries de relatório)

**⚠️ Testes Manuais de Segurança (penetration test):**
> Estes testes são executados manualmente com DevTools do browser e ferramentas como Postman/curl.
> Não são automatizáveis dentro do `flutter test`.

- [ ] **JWT tampering:** modificar o `organization_id` no JWT decodificado (via DevTools ou jwt.io) → confirmar que Supabase RLS rejeita a query e retorna 0 rows (não erro 403, mas isolamento silencioso)
- [ ] **Cross-tenant read:** autenticado como usuário de Org A, fazer query REST direta na API Supabase para tabela `execution_states` sem filtro → confirmar que retorna apenas dados de Org A
- [ ] **RLS bypass attempt:** tentar acessar tabelas via Supabase REST API com `anon key` sem estar autenticado → confirmar que retorna 0 rows (RLS block)
- [ ] **Inspeção de rede:** abrir DevTools → aba Network → verificar que nenhuma chamada à API Supabase expõe `service_role key` ou dados de outras orgs no payload de resposta
- [ ] **`strict-casts` habilitado:** após corrigir os ~80 erros de `dynamic`, rodar `flutter analyze` e confirmar 0 erros com `strict-casts: true`

#### [ ] 8.5 — Performance & Escala
- Load test: 1.000 veículos simultâneos com telemetria contínua
- Benchmark `ContractualEvaluationEngine` (meta: < 100ms por vehicle state)
- Revisão de índices com base nas queries reais de staging
- Avaliar read replicas para queries de relatório (não competir com writes do ledger)

#### [ ] 8.6 — Disaster Recovery
- Documentar estratégia de backup (Supabase PITR — Point-in-Time Recovery)
- Runbook de restore com tempo estimado e responsável pela autorização
- Definir RPO/RTO para dados financeiros (meta: RPO ≤ 1h · RTO ≤ 4h)
- Testar restore em ambiente isolado ao menos 1× antes do lançamento

#### [ ] 8.7 — Auditoria de Integridade de Telemetria (Anti-Spoofing)
- **Detectar Fake GPS:** saltos lógicos de posição (velocidade física impossível entre dois pontos)
- **Detectar sinal manipulado:** baixo número de satélites + coordenadas fixas por longo período
- **Engine invalida evidências suspeitas com flag `TELEMETRY_INTEGRITY_VIOLATION` antes de emitir veredito**
  - **Design:** Algoritmo de detecção de anomalias cinemáticas e limite de satélites.
  - **Review:** Validar impacto de falso-positivos em áreas de sombra de GPS.
  - **Implementation:** Integrar engine de anti-spoofing no pipeline de avaliação.
  - **Validation:** Testar com datasets de spoofing conhecido e verificar flags no vederito.
- **Personas:** `qa_security`, `architect`

---

### [ ] Trilha D — Lançamento

**Por que "Trilha" e não "Phase":** Esta etapa não é técnica e não segue o ciclo
`Design → Review → Implementation → Validation`. É o conjunto de ações comerciais,
legais e de go-to-market necessárias para transformar o produto técnico em produto de mercado.

**Pré-requisito:** Phases 5, 6, 7 e 8 concluídas.

#### [ ] D1 — Documentação de Produto
- Landing page com proposta de valor (ledger imutável vs. TMS tradicionais)
- Guia de onboarding para novos clientes (do signup ao primeiro SLA auditado)
- Guia de integração de telemetria (como conectar GPS/IoT existente ao PactaFlow)
- Changelog público com versionamento semântico

#### [ ] D2 — Modelo Comercial
- Definir pricing: por veículo/mês · por organização · por execução auditada
- Contrato de prestação SaaS (termos de uso + SLA do próprio PactaFlow)
- Política de privacidade LGPD (obrigatório — plataforma processa dados de motoristas e operadores)
- Processo de cobrança: Stripe ou similar integrado ao ciclo de onboarding

#### [ ] D3 — Piloto Beta Controlado
> **Este é o maior teste manual do produto** — realizado por usuários reais, not pelo desenvolvedor.

- Selecionar 2–3 clientes reais com contratos de transporte ativos
- Monitoramento intensivo durante o piloto (Sentry + contato direto)
- Coleta estruturada de feedback a cada 2 semanas
- **Critério de saída do beta:** zero incidentes críticos em 30 dias corridos
- Ajustes de produto incorporados antes do lançamento

---

## Visão Geral de Execução

─────────────────────────────────────────────────────
[x] Phase 5 — B2B Refactoring (Sprints 5.11, 5.12, 5.13) ✅
─────────────────────────────────────────────────────
[ ] Phase 6 — Administration & Tenant Self-Service 🚀
      - Organização, RBAC, Contractors e Autogestão de Usuários.
─────────────────────────────────────────────────────
[ ] Phase 7 — Evidence & Audit Exports
─────────────────────────────────────────────────────
[ ] Phase 8 — Operational Hardening
─────────────────────────────────────────────────────

### Próximo passo: Phase 6 Activation
Foco em tornar o sistema multi-tenant autônomo.
1. [ ] Seed `user_roles` para o usuário de dev como `TENANT_ADMIN`.
2. [ ] CRUD de Organização e Gerenciamento de Membros.
3. [ ] Convites de usuários via token.
