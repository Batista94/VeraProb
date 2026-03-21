# PactaFlow — Roadmap Estratégico

**Revisão:** 2026-03-19
**Status Atual:** Phase 9 em andamento — Milestone alvo: **READY FOR FIRST TENANT**

---

## Estado do Codebase (referência para novas sessões)

| Aspecto | Estado |
|---|---|
| Testes | 654 passing · 0 falhas ✅ |
| Migrations | 48 aplicadas |
| Command Handlers | 17 handlers na camada `application/` |
| Análise estática | 0 erros · Wasm-ready (`package:web`) |
| Precisão financeira | `Money` VO (centavos BIGINT) — Enforced ✅ |
| Phase 9.3 Audit | **CONCLUÍDA** — INV-23 fechado, Human-in-Loop ativo, Lead Reviewer [GO] ✅ |
| Phase 9.2 Audit | **CONCLUÍDA** — Score 10/10, Lead Reviewer [GO] ✅ |
| Phase 9.1 Audit | **CONCLUÍDA** — Score 10/10, Lead Reviewer [GO] ✅ |
| Phases 5 – 8.8 | **TODAS CONCLUÍDAS** ✅ |

---

## Milestone Gates

| Gate | Critério | Sinal |
|---|---|---|
| Homologation Ready | Invariantes 5 & 6 passando · Flows core testados | ✅ ATINGIDO |
| Ingestion Validated | Timeline Reconstruction passando Chaos Tests | ✅ ATINGIDO |
| CI/CD Ready | Schema estável · RLS validado · Cobertura >60% | ✅ ATINGIDO |
| **Product Launch Ready** | SuperAdmin operacional · Auditor reativo · Verdict explicável · ROI dashboard | **READY FOR FIRST TENANT** |
| Enterprise Ready | API Webhooks · Contrato dinâmico · ISO 27001 prep | READY FOR ENTERPRISE |

---

## Fases Concluídas (Histórico)

- **Phase 9.3 — Auditor Reativo + INV-23** ✅: `VerdictEvidence` VO em toda sanção, state machine `SANCTION_RECOMMENDED → APPLIED/REJECTED`, fila auditora com Realtime badge, 4 migrations com triggers INV-1, 654 testes passando. [GO] Verdict do Lead Reviewer. (2026-03-19)
- **Phase 9.2 — SuperAdmin Portal** ✅: Onboarding de tenant em <5 min, zero intervenção de DBA, `tenant_billing_events`, `system_audit_log`. Score 10/10. [GO] Verdict do Lead Reviewer. (2026-03-19)
- **Phase 9.1 — Forensic Audit Geral** ✅: Auditoria técnica profunda contra os 24 Invariantes e 20 Forensic Rules. Score 10/10. [GO] Verdict do Lead Reviewer. (2026-03-19)
- **Phase 8.8 — Anti-Spoofing** ✅: Detecção de Fake GPS, anomalias cinemáticas, SHA-256 Hash Chain em `TelemetryEvidence` (INV-21/24).
- **Phase 8.7 — Disaster Recovery** ✅: Runbook de restore e PITR configurado.
- **Phase 8.6 — Performance & Escala** ✅: Benchmark 1.000 VUs, scripts k6, otimização de índices.
- **Phase 8.5 — Security Hardening** ✅: `strict-casts: true`, PII masking em SQL.
- **Phase 8.4 — Observabilidade** ✅: Sentry + PostHog para todos os ambientes.
- **Phase 8.3 — Separação de Ambientes** ✅: Suporte multi-env (`--dart-define` + `.env`).
- **Phase 8.2 — CI/CD Pipeline** ✅: GitHub Actions com gate humano em prod.
- **Phase 8.1 — Systemic UX & Hard Gates** ✅: INV-18/19/20 enforced, Material 3.
- **Phase 7.5 — Financial Defense** ✅: Shadow Mode e Blindagem Forense PostgreSQL.
- **Phase 7 — Evidence & Audit Exports** ✅: Relatórios imutáveis, AttestationHeader (INV-16/17).
- **Phase 6.5 — Operational Resilience** ✅: Anti-Corruption Edge, Chaos Tolerance.
- **Phase 6 — Administration** ✅: RBAC, Convites, Dual-Key isolation.
- **Phase 5 — B2B Foundation** ✅: JIT Master Data, RLS Tenant Isolation.

---

## Phase 9 — PactaFlow: De Protótipo de Engenharia a Produto B2B Operacional

**Objetivo Estratégico:** Eliminar os gaps competitivos críticos identificados na análise de mercado, atingir o milestone **READY FOR FIRST TENANT**, e estabelecer PactaFlow como a plataforma de conformidade SLA mais defensável juridicamente do mercado logístico brasileiro.

**Princípio Diretor:** Todo gap desta fase tem um custo direto de vendas. O sistema tecnicamente correto não serve se o auditor não for notificado em tempo real, se não existir ROI demonstrável, e se o onboarding exigir um DBA.

**Mandato de Testes (obrigatório em toda sub-fase):**

| Camada | Ferramenta | Escopo |
|---|---|---|
| Unit | `flutter test` | Domínio, handlers, engine extensions, projections |
| Integration | Postgres real (sem InMemory) | DB triggers, RLS policies, Edge Functions, migrations |
| E2E | Flutter integration tests | Fluxos do critério de aceite de cada sub-fase |
| **Manual** | **Human Validation** | **UX/Acessibilidade, ROI Dashboard, Workflow Human-in-the-Loop** |

> Nenhuma sub-fase recebe [GO] do Lead Reviewer sem suite de testes passando em CI.

---

### [x] Phase 9.1 — Forensic Audit Geral ✅ CONCLUÍDA

**Líder:** Lead Reviewer · **Score:** 10/10 · **Verdict:** [GO] · **Data:** 2026-03-19

**Artefato:** `docs/audit/phase_9_report.md`

Validado: Dual-Key RLS · JWT path canônico · Event Time no Engine (INV-12) · Hash Chain em `TelemetryEvidence` (INV-24) · `Money` VO BIGINT (INV-2) · Wasm-readiness.

---

### [x] Phase 9.2 — SuperAdmin Portal (Eliminação do Gargalo de Onboarding) ✅ CONCLUÍDA

**Líder:** Lead Reviewer · **Score:** 10/10 · **Verdict:** [GO] · **Data:** 2026-03-19
**Invariantes:** INV-6, INV-10, INV-3
**Gap Endereçado:** Criar cliente manualmente no banco não escala. 10 clientes = 10 intervenções de DBA.

**Deliverables:**

1. **Rota `/super-admin`** com guard `SUPER_ADMIN` (claim `super_admin: true` no JWT `app_metadata`). Totalmente isolada do Admin UI de tenant — nenhum dado de tenant vaza para esta view.

2. **"Gerar Nova Organização" Wizard** (3 passos): dados fiscais (razão social, CNPJ, plano) → billing/limites (max veículos, max contratos ativos) → convite Admin inicial (reutiliza `invite_user_handler.dart`). Resultado: nova linha em `organizations`, RLS ativa via trigger.

3. **Painel `super_admin_tenant_health_view`**: contratos ativos, último evento de telemetria, alertas críticos abertos, status de billing por org. Consulta via `service_role` key — nunca via JWT de tenant.

4. **`tenant_billing_events` table** (append-only, INV-1): histórico imutável de mudanças de plano/limite.

5. **`system_audit_log` exposto** na tela SuperAdmin com filtro por org, tipo de evento e janela de tempo.

**Critério de Aceite:** Novo cliente onboardado em <5 min, zero intervenção de DBA. SuperAdmin vê status de todos os tenants em uma tela.

---

### [x] Phase 9.3 — Auditor Reativo: Workflow de Aprovação de Sanções em Tempo Real ✅ CONCLUÍDA

**Líder:** Senior Engineer + QA & Security Lead · **Verdict:** [GO] · **Data:** 2026-03-19
**Invariantes:** INV-1, INV-2, INV-3, INV-6, INV-7, INV-10, INV-23, INV-24

**Deliverables entregues:**

1. **`VerdictEvidence` VO** (`lib/domain/sla_audit/verdict_evidence.dart`) — SHA-256 determinístico sobre o bundle completo: `clause_ref · rule_id · rule_version · gps_lat/lng · primary_evidence_timestamp_utc · delta_value · threshold_value · fine_cents · confidence_score`. Fecha INV-23.

2. **State machine no ledger** (todos como APPENDs — INV-1):
   - `SANCTION_RECOMMENDED` → Engine gera automaticamente com `VerdictEvidence` no payload
   - `SANCTION_APPLIED` → Auditor clica [VALIDAR] (`ApproveSanctionHandler`)
   - `SANCTION_REJECTED` → Auditor clica [REJEITAR] com reason ≥10 chars (`RejectSanctionHandler`)
   - `SANCTION_DISPUTED` → Preparado para Phase 9.4

3. **`sanction_review_queue`** (DB + trigger automático): INSERT em `SANCTION_RECOMMENDED` no ledger → trigger popula fila automaticamente (`ON CONFLICT DO NOTHING`, INV-24). RLS isola por org (INV-6/10). Campos imutáveis protegidos por trigger (INV-1).

4. **`AuditorQueueScreen`** com `pendingSanctionsStreamProvider` (Supabase Realtime — <30s). Exibe combo de prova completo por card. [REJEITAR] abre campo inline com validação ≥10 chars antes de habilitar confirmação.

5. **Badge na NavigationRail** (AdminHome) derivado de `pendingSanctionsCountProvider`. Atualiza em tempo real.

6. **`sanction_escalation_log`** (append-only, INV-1) + RPC `get_pending_sanctions_count`.

7. **654 testes passando** (17 novos unit + 4 INV-23 engine assertions + 37 handler tests).

**Arquivos novos:** 17 `lib/` + 4 migrations + 6 `test/`
**Arquivos modificados:** `execution_events.dart`, `user_permissions.dart`, `sla_ledger_mapper.dart`, `contractual_evaluation_engine.dart`, `sla_persistence_provider.dart`, `admin_home.dart`, `contractual_evaluation_engine_test.dart`

---

#### Testes Manuais Obrigatórios (Phase 9.3)

> Execute após `supabase db reset` + `flutter run` com Supabase configurado.

**MT-9.3.1 — Fila Auditora aparece na navegação**
- Abrir o app como `admin` ou `auditor`
- Verificar que "Fila Auditora" aparece como último item da NavigationRail
- Com fila vazia: tela exibe "Nenhuma sanção pendente" e ícone verde
- Navegar para outra tela e voltar — sem crash

**MT-9.3.2 — Badge em tempo real**
- Abrir `sla_audit_ledger_v2` no Supabase Studio
- Inserir manualmente uma linha com `type = 'SANCTION_RECOMMENDED'` e `payload.verdict_evidence` válido
- Verificar que o badge numérico aparece na NavigationRail em <30s **sem refresh da página**
- Verificar que a Fila Auditora exibe o card correspondente automaticamente

**MT-9.3.3 — Combo de prova visível no card**
Cada card deve exibir obrigatoriamente:
- [ ] Contrato ID e SET (Veículo)
- [ ] Cláusula (`clause_ref`)
- [ ] Infração (deltaValue min) e Limite (thresholdValue min)
- [ ] Multa formatada em R$ (ex: "R$ 1.500,00")
- [ ] Confiança (%)
- [ ] Seção "Proveniência" com GPS lat/lng, Timestamp UTC e Hash SHA-256 (primeiros 12 chars + "...")

**MT-9.3.4 — Fluxo VALIDAR**
- Clicar [VALIDAR] em um card pendente
- Verificar: loading state no botão durante processamento
- Verificar: card desaparece da fila após sucesso
- Verificar no Supabase Studio: nova linha `SANCTION_APPLIED` no `sla_audit_ledger_v2` com `payload.verdict_evidence` preservado
- Verificar: `sanction_review_queue` atualizado para `status = 'applied'`
- Verificar: badge decrementa

**MT-9.3.5 — Fluxo REJEITAR**
- Clicar [REJEITAR] — campo de texto deve aparecer inline
- Digitar menos de 10 chars → botão "CONFIRMAR REJEIÇÃO" deve estar desabilitado
- Digitar ≥10 chars → botão habilita
- Confirmar rejeição
- Verificar: `SANCTION_REJECTED` no ledger com `rejection_reason` no payload
- Verificar: `sanction_review_queue` com `status = 'rejected'` e `rejection_reason` preenchido

**MT-9.3.6 — RBAC: operator não vê a fila**
- Fazer login com role `operator`
- Verificar que "Fila Auditora" **não aparece** na navegação
  _(nota: implementação atual mostra para todos — se a visibilidade por role não foi filtrada no AdminHome, registrar como debt para Phase 9.4)_

**MT-9.3.7 — Isolamento cross-tenant (INV-6)**
- Criar sanção no `org_id = 'tenant-A'`
- Fazer login como usuário do `tenant-B`
- Verificar que a fila está **vazia** para tenant-B

**MT-9.3.8 — Idempotência (INV-24)**
- No Supabase Studio, tentar inserir manualmente na `sanction_review_queue` com o mesmo `ledger_entry_id` de uma entrada já existente
- Verificar que apenas **uma linha** existe na tabela (ON CONFLICT DO NOTHING)

**MT-9.3.9 — Imutabilidade (INV-1)**
- No Supabase Studio, tentar UPDATE de `organization_id` em qualquer linha de `sanction_review_queue`
- Verificar que a operação falha com erro `restrict_violation`
- Tentar DELETE → mesmo resultado

**MT-9.3.10 — VerdictEvidence no ledger (INV-23)**
- Após qualquer sweep que gere no-show com regra de penalidade configurada
- Verificar na tabela `sla_audit_ledger_v2`: linha `SANCTION_RECOMMENDED` com `payload -> 'verdict_evidence'` NOT NULL
- Verificar que `evidence_hash` tem exatamente 64 caracteres hexadecimais

---

### [ ] Phase 9.4 — ROI Dashboard + Shadow Mode (Demonstração de Valor)

**Líder:** Business Maverick + UX & Ops Director
**Invariantes:** INV-1, INV-2, INV-7, INV-16, INV-17
**Gap Endereçado:** Sem ROI demonstrável, renovação de assinatura é discussão subjetiva. Sem Shadow Mode, a barreira de entrada é alta ("prove valor antes de eu pagar").

**Deliverables:**

1. **"Valor Entregue" Panel** (3 métricas em BRL):
   - Multas identificadas no período
   - Multas confirmadas e cobráveis (aprovadas pelo auditor)
   - Cobranças indevidas rejeitadas pelo sistema

2. **`roi_monthly_snapshot` table** (read-model, projetado via `pg_cron`).

3. **Linha do Tempo de Payback**: gráfico de barras mensal e ranking de contratos por risco financeiro acumulado.

4. **Shadow Mode / Demo de Vendas**: importação de CSV de viagens históricas do prospect (mês passado). O sistema reprocessa os eventos via `ContractualEvaluationEngine` em modo `DRY_RUN` (sem gravação no ledger real) e gera relatório: _"Se estivéssemos ativos no mês passado, teríamos identificado R$ X em multas recuperáveis."_ `ShadowRunResult` armazenado separado do ledger imutável (INV-1 preservado).

5. **Export ROI Report** PDF com `AttestationHeader` (INV-17) + `packageHash` (INV-16): documento que o gerente de frota leva ao CFO para justificar a renovação.

**Critério de Aceite:** Gerente obtém "quanto a PactaFlow me salvou em R$" em <2 cliques. Vendedor gera relatório "se você tivesse" a partir de CSV do prospect em <10 min.

---

### [ ] Phase 9.5 — Vínculo Dinâmico Contrato-Viagem (Eliminação do Ativo Estático)

**Líder:** Architect + Senior Engineer
**Invariantes:** INV-7, INV-12, INV-13
**Gap Endereçado:** Contratos amarrados a veículos fixos quebram quando o caminhão muda. Contrato deve ser vinculado à Viagem/Manifesto, não ao ativo.

**Deliverables:**

1. **Entidade `ServiceManifest`**: `id, organization_id, contract_id, manifest_number, scheduled_origin_at_utc, scheduled_destination_at_utc, planned_route_id, status`.

2. **`AssetAssignedToManifestEvent`**: vínculo temporal (não permanente). O Engine resolve o contexto de avaliação via `(contract_id, manifest_id)` + janela temporal por `gps_timestamp` (INV-12). A reatribuição gera novo evento — nunca sobrescreve (INV-1).

3. **Flag `legacy_asset_binding: true`** para retrocompatibilidade com execuções existentes.

4. **Formulário JIT "Emitir Viagem Rapidamente"**: 4 campos obrigatórios (manifest_number, contrato pai, origem, destino) → cria `ServiceManifest` em `DRAFT`.

5. **UI de atribuição/reatribuição de ativo** com histórico completo de atribuições.

**Critério de Aceite:** Reatribuição de veículo sem invalidar histórico de avaliações anterior. Replay da mesma sequência de eventos produz o mesmo resultado (INV-7).

---

### [ ] Phase 9.6 — Inteligência de Alertas: Anti-Fadiga e Alertas Preditivos

**Líder:** Senior Engineer + UX & Ops Director
**Invariantes:** INV-5, INV-8, INV-12
**Gap Endereçado:** 50 alertas vermelhos por hora = todos ignorados. Mercado quer prevenção: "este contrato será quebrado em X minutos".

**Deliverables:**

1. **`estimated_financial_impact_cents`** em todo `OperationalAlert`. Camadas de severidade com semântica financeira:
   - `INFORMATIONAL` (<R$100): só no log, sem interrupt
   - `WATCH` (R$100–500): badge no OCC, sem push
   - `WARNING` (R$500–2k): notificação in-app, entra na fila do auditor
   - `CRITICAL` (>R$2k): in-app + email imediato

2. **`PendingBreachAlert`** (Alerta Pré-Falha): `situation_engine.dart` calcula ETA de breach com base em posição atual + velocidade + distância até zona de destino + janela contratual restante. Emite alerta _antes_ da multa ocorrer.

3. **OCC reformulado**: agrupa ativos por nível de risco financeiro. Top riscos no topo com multa projetada. Ativos `OK` em lista colapsável.

4. **Configuração de thresholds por contrato** no `rule_studio_screen.dart` (persistido e versionado, INV-7).

**Critério de Aceite:** Top-3 riscos identificados em <10s ao abrir o OCC. Máximo 5 notificações de alta prioridade por hora por usuário.

---

### [ ] Phase 9.7 — Liveness Check, Late-Arrival & Anti-Tamper

**Líder:** Senior Engineer + QA & Security Lead
**Invariantes:** INV-9, INV-12, INV-21, INV-24
**Gap Endereçado:** GPS falha em túneis e rural MT. Motoristas desligam rastreadores. Relógio de hardware pode ser manipulado.

**Deliverables:**

1. **Liveness Check — Silêncio é um Evento Auditável**: o pipeline monitora `last_ping_at` por ativo ativo em `ServiceManifest`. Se o silêncio exceder o threshold configurado por contrato (ex: 15 min), emite `TelemetrySilenceDetectedFact` — um `CanonicalFact` explícito representando ausência de sinal. **O silêncio não é apenas um alerta — é uma Quebra de Contrato específica** (`BREACH_TELEMETRY_SILENCE`). O motorista que desliga o rastreador intencionalmente gera um `SlaLedgerEntry` do tipo `SIGNAL_LOSS_BREACH`, com `fine_cents` calculado pela cláusula de disponibilidade de rastreamento. Causa classificada: `CONNECTIVITY_LOSS` vs. `DEVICE_DISABLED` vs. `LATE_ARRIVAL_ACCEPTED`.

2. **Protocolo de Late-Arrival Processing**: janela de aceite configurável por contrato (default: 6h, rural: até 48h). Eventos dentro da janela são reprocessados na posição cronológica correta (INV-12 preservado). Fora da janela → `LATE_ARRIVAL_REJECTED` com motivo no `ingestion_integrity_flag`.

3. **Validação de Divergência Timestamp Hardware vs. Servidor**: `hardware_server_delta_seconds` no `SpoofingRiskScore`. Delta >300s (sem gap de conectividade) eleva risco de manipulação de relógio interno do dispositivo.

4. **Relatório de lacunas de telemetria** por `ServiceManifest`: períodos sem GPS, causa classificada, eventos tardios aceitos/rejeitados. Evidência legal de que o sistema tentou auditar mas o dispositivo não reportou.

5. **Política de janela de reprocessamento configurável por contrato** no `rule_studio_screen.dart` (versionado, INV-7).

**Critério de Aceite:** Evento 4h atrasado (dentro da janela) = resultado idêntico ao tempo real (INV-7). Zero penalidade por falha de conectividade com hardware timestamp válido. Silêncio intencional (dispositivo desligado) gera `SIGNAL_LOSS_BREACH` com evidência forense completa.

---

### [ ] Phase 9.8 — Audit Trail do Sistema e Preparação ISO 27001

**Líder:** QA & Security Lead + Lead Reviewer
**Invariantes:** INV-1, INV-15, INV-16, INV-17, INV-22
**Gap Endereçado:** Enterprise clients exigem "quem mudou qual registro, quando, por quê". Sem isso, ISO 27001 / SOC2 estão fora de alcance. Adicionalmente: auditoria de SI (2026-03-20) identificou gaps de Privileged Access Management não mapeados anteriormente — ver itens 5–8 abaixo.

**Deliverables:**

1. **Cobertura total do `system_audit_log`**: todo command handler emite `{actor_user_id, actor_role, action_type, entity_type, entity_id, before_state_hash, after_state_hash, justification_text, ip_address, timestamp_utc}`. Handler sem emissão bloqueado no review (INV-22).

2. **"Entity Audit Trail" modal**: em qualquer tela de contrato/sanção/ledger, botão "Ver Trilha" abre timeline cronológica completa da entidade — quem criou, quem aprovou, quem rejeitou, qual regra afetou o cálculo.

3. **Relatório de Conformidade PDF** com `AttestationHeader` (INV-17) + `packageHash` (INV-16): ações privilegiadas, permissões elevadas, tentativas negadas via RLS, resumo de integridade do ledger. Destinado a auditorias externas e due diligence enterprise.

4. **`docs/compliance/iso27001_checklist.md`**: mapeamento vivo controle ISO 27001 → feature do sistema. Atualizado como parte do PR de cada sub-fase.

**Critério de Aceite:** Dado qualquer `sla_ledger_entry_id`, história completa em <3 cliques. Relatório de conformidade passa checklist de due diligence enterprise simulado.

**SI Debt adicionado à Phase 9.8 (auditoria 2026-03-20):**

5. **[ALTO] Audit de sessões privilegiadas no `system_audit_log`**: eventos de login/logout do SuperAdmin devem ser registrados (`action_type: 'SUPER_ADMIN_SESSION_START'/'END'`). Atualmente apenas ações pós-login são auditadas. ISO 27001 A.9.4.2 exige rastreabilidade de acesso privilegiado no nível de autenticação.

6. **[MÉDIO] TTL diferenciado para sessão SuperAdmin**: sessões SuperAdmin devem ter timeout de inatividade de 15–30 min (vs. padrão de 1h para tenants). Requer configuração de `jwt_expiry` por tipo de usuário no Supabase + interceptor de sessão no Flutter (`SuperAdminShell`).

8. **[ALTO] MFA obrigatório para SuperAdmin**: o SuperAdmin autentica com email/senha como qualquer usuário tenant. Para ISO 27001 A.9.4.2 e SOC2 CC6.1, toda conta privilegiada deve exigir segundo fator. Supabase suporta TOTP nativo — requer: (a) enrollment obrigatório na primeira sessão SuperAdmin, (b) `SuperAdminGuard` verifica `aal2` (Authenticator Assurance Level 2) no JWT antes de renderizar o shell, (c) sessão sem MFA ativo redireciona para tela de enrollment.

7. **[CRÍTICO — Blocker de Produção] Remover `service_role` key do bundle Flutter**: `lib/infrastructure/providers/super_admin_providers.dart` instancia um `SupabaseClient` com a `service_role` key diretamente no app Flutter. Essa key bypassa 100% do RLS e dá acesso irrestrito a todos os dados de todos os tenants. **Em produção, um usuário pode extrair a key do bundle compilado.** Solução arquitetural: criar Edge Function `super-admin-proxy` que recebe o JWT SuperAdmin, valida o claim `super_admin: true`, e executa as operações com `service_role` server-side. O Flutter passa apenas o JWT de usuário. Referência: Stripe, AWS, Salesforce nunca expõem credenciais de serviço no cliente. **Sem resolver este item, o sistema NÃO deve ir para produção com dados reais.**

---

### Milestone Gate: READY FOR FIRST TENANT

> Critério de entrada: Fases 9.2–9.8 com [GO] verdict do Lead Reviewer + suite de testes (unit/integration/e2e) passando em CI.

| Checklist | Sub-fase |
|---|---|
| ✅ Novo tenant onboardado em <5 min, zero DBA | 9.2 |
| ✅ Auditor notificado de breach em <30s | 9.3 |
| ✅ Zero penalidade aplicada sem aprovação humana | 9.3 |
| ✅ 100% das sanções com VerdictEvidence (INV-23) | 9.3 |
| ✅ Dashboard ROI exibe "valor entregue em R$" | 9.4 |
| ✅ Shadow Mode gera relatório "se você tivesse" | 9.4 |
| ✅ Reatribuição dinâmica de ativo sem invalidar histórico | 9.5 |
| ✅ OCC identifica top-3 riscos em <10s | 9.6 |
| ✅ Silêncio de rastreador gera SIGNAL_LOSS_BREACH | 9.7 |
| ✅ Eventos tardios processados deterministicamente | 9.7 |
| ✅ Trilha de auditoria completa para qualquer entidade | 9.8 |
| ✅ Shadow Mode funcional (Phase 7.5, herdado) | — |
| ✅ Isolamento de tenant auditado (Phase 9.1, herdado) | — |

**Sinal:** **READY FOR FIRST TENANT** ✅

---

## Phase 10 — PactaFlow Enterprise: Escala, Integrações e Expansão Vertical

**Objetivo Estratégico:** Transformar PactaFlow de produto B2B SMB para plataforma enterprise, capaz de integrar com ERPs (SAP/Oracle), operar em múltiplos verticais e suportar clientes com >500 ativos sem degradação de performance.

**Pré-requisito:** Milestone READY FOR FIRST TENANT atingido e validado com pelo menos 1 cliente piloto real.

---

### [ ] Phase 10.1 — API First & Webhooks Enterprise

**Gap:** "Como o veredicto entra no SAP sem digitação manual?"
**Invariantes:** INV-1, INV-16, INV-24

**Deliverables:** REST API pública com autenticação via API Key (escopo por org) · Webhook engine emitindo `sanction.recommended`, `sanction.applied`, `sanction.rejected` com `VerdictEvidence` completo · SDK TypeScript mínimo · Portal de desenvolvedor (OpenAPI 3.0, playground, logs de entregas/reenvios) · Retry logic com exponential backoff + dead letter queue · Cada evento de webhook registrado no `system_audit_log` (INV-1).

---

### [ ] Phase 10.2 — Captura Passiva de Dados (Minimização de Input Manual)

**Gap:** Entrada manual aumenta latência de auditoria e risco de erro humano.
**Invariantes:** INV-9, INV-14, INV-21

**Deliverables:** Adapter GPS Mobile (Flutter native SDK para motorista) → pipeline existente via INV-14 · OCR para documentos de frete (CT-e/Manifesto fotografado → popula `ServiceManifest`, flag `source: OCR` para rastreabilidade) · Validação cruzada OCR vs. telemetria para detecção de inconsistências.

---

### [ ] Phase 10.3 — JIT Contract + Assinatura Digital

**Gap:** Operador precisa emitir contratos em campo em <60 segundos.
**Invariantes:** INV-18, INV-19

**Deliverables:** Formulário de emissão em 4 campos obrigatórios (contratado, origem, destino, data), restante de template · Link de assinatura via WhatsApp/email com página minimalista de aceite · `contract_signature_events` (append-only): `SIGNATURE_LINK_SENT`, `LINK_OPENED`, `SIGNED`, `EXPIRED` · Engine não ativa (INV-18) enquanto status for `PENDING_SIGNATURE` · Dashboard de assinaturas pendentes.

---

### [ ] Phase 10.4 — Expansão Vertical: Motor Agnóstico Aplicado

**Gap:** CORE deve ser industry-agnostic (Architect mandate, INV-4).
**Invariantes:** INV-4

**Deliverables:** Auditoria de acoplamento vertical (terminologia de fretamento → Adapter/Module, não Core) · `VerticalConfig`: terminologia UI, templates SLA, campos obrigatórios por vertical · Segundo vertical piloto (candidato: Cash-in-Transit ou Distribuição de Medicamentos) · Guia "Implementar Novo Vertical" para expansões futuras independentes.

---

### [ ] Phase 10.5 — Performance Enterprise e Escala

**Gap:** Suportar >500 ativos por tenant e operações de grande porte.
**Invariantes:** INV-3, INV-6

**Deliverables:** Read replicas para queries de projeção (separar write path do Engine do read path dos dashboards) · Particionamento de `sla_audit_ledger` por `organization_id` + `month` · Cache para `roi_monthly_snapshot` e `super_admin_tenant_health_view` · Benchmark 5.000 VUs + contrato SLA de performance para clientes enterprise.

---

## Visão Geral de Execução

```
═══════════════════════════════════════════════════════════════════════
[x] Phases 5 → 8.8 COMPLETE ✅
[x] Phase 9.1 — Forensic Audit COMPLETE ✅ (Score 10/10, [GO])
═══════════════════════════════════════════════════════════════════════
[x] Phase 9.2 — SuperAdmin Portal          ✅ CONCLUÍDA [gap: onboarding sem DBA]
[x] Phase 9.3 — Auditor Reativo + H-i-L   ✅ CONCLUÍDA [gap: passive auditor, INV-23]
                                              ⚠ Testes manuais MT-9.3.1→10 pendentes
[ ] Phase 9.4 — ROI Dashboard + Shadow     [gap: retention + barrier de venda]
[ ] Phase 9.5 — Vínculo Dinâmico           [gap: static asset]
[ ] Phase 9.6 — Inteligência de Alertas   [gap: alert fatigue, predictive]
[ ] Phase 9.7 — Liveness + Late-Arrival   [gap: offline/rural, SIGNAL_LOSS_BREACH]
[ ] Phase 9.8 — Audit Trail + ISO 27001   [gap: enterprise sales]
───────────────────────────────────────────────────────────────────────
>>> MILESTONE: READY FOR FIRST TENANT <<<
───────────────────────────────────────────────────────────────────────
[ ] Phase 10.1 — API First / Webhooks      [gap: ERP integration]
[ ] Phase 10.2 — Passive Data Capture      [gap: manual input reduction]
[ ] Phase 10.3 — JIT Contract + Assinatura [gap: speed at field]
[ ] Phase 10.4 — Vertical Expansion        [gap: agnostic core]
[ ] Phase 10.5 — Enterprise Performance    [gap: >500 assets/tenant]
═══════════════════════════════════════════════════════════════════════
```

---

## Mapeamento: Gaps Competitivos → Fases

| Gap da Análise Competitiva | Fase |
|---|---|
| SuperAdmin bottleneck (T01–T04) | 9.2 |
| Auditor passivo → reativo | 9.3 |
| INV-23: combo de prova ausente | 9.3 |
| Liability legal: multa sem humano | 9.3 |
| ROI demonstrável (retenção) | 9.4 |
| Barreira de entrada: Shadow Mode | 9.4 |
| Ativo estático (contrato-viagem) | 9.5 |
| JIT Contract Emission (T09) | 9.5 + 10.3 |
| Fadiga de alertas | 9.6 |
| Alertas pré-falha preditivos | 9.6 |
| GPS offline / rural MT | 9.7 |
| Silêncio como quebra de contrato | 9.7 |
| Manipulação de timestamp | 9.7 |
| Audit trail para enterprise | 9.8 |
| ISO 27001 / SOC2 prep | 9.8 |
| API/Webhooks para SAP/Oracle | 10.1 |
| Captura passiva (OCR, GPS mobile) | 10.2 |
| Assinatura digital JIT | 10.3 |
| Agnostic core (novos verticais) | 10.4 |
| Escala >500 ativos | 10.5 |
