# BusFlow 🧭
Plataforma de Determinismo Operacional e Proteção de Margem para Transporte Corporativo

BusFlow é uma plataforma soberana de auditoria contratual automatizada que transforma execução operacional em evidência determinística e projeção financeira imutável.

Diferente de sistemas tradicionais de monitoramento ou TMS, o BusFlow não apenas rastreia veículos — ele converte telemetria em verdade contratual verificável e impacto financeiro mensurável.

🎯 **Problema que Resolvemos**

Empresas de transporte corporativo e fretado enfrentam:
- Glosas técnicas recorrentes
- Disputas de faturamento
- Aumento do DSO (Days Sales Outstanding)
- Perda silenciosa de margem
- Dependência de conferência manual mensal

A maior sangria financeira não está no combustível ou manutenção. está na incerteza da execução contratual. O BusFlow resolve isso criando um pipeline determinístico:

Telemetria → Normalização Operacional → Avaliação Contratual (SLA Engine) → Ledger Forense Imutável → Projeção Financeira → Proteção de Receita

🧠 **O Que o BusFlow É (e o que NÃO é)**

**BusFlow NÃO é:**
- Sistema de rastreamento simples
- Aplicativo de passageiro
- ERP
- TMS convencional
- Dashboard operacional genérico

**BusFlow é:** Uma plataforma que transforma execução física em dinheiro protegido.

🏗 **Arquitetura**

### Princípios Fundamentais
- Domain-Driven Design (DDD)
- CQRS (Command Query Responsibility Segregation)
- Domain Sovereignty
- Infraestrutura como Adapter
- Append-only forensic logging
- Determinismo financeiro

### Camadas

1️⃣ **Domain Layer (Soberana)**
- Contém: `PlanDeclaration`, `ContractualServiceExecution`, `ContractualExecutionState`, `ExecutionStatus`, `Domain Events`, `Money` (Value Object financeiro).
- Nenhuma regra de negócio existe na UI.
- Nenhuma dependência de infraestrutura contamina o domínio.

2️⃣ **Application Layer**
- `ContractualEvaluationEngine`, `ContractualEvaluationSubscriber`, `SnapshotGenerator`, `FinancialClosingService`, Query Services (Impacto, Tendência).
- Responsável por orquestrar fluxo sem violar DDD.

3️⃣ **Infrastructure Layer**
- Repositórios in-memory (para testes)
- Adapters opcionais (Supabase, Postgres, etc.)
- Timezone handling (`America/Sao_Paulo`)
- Integração com telemetria
- Infraestrutura é detalhe de implementação.

4️⃣ **Admin Web (OCC + SLA)**
- Inclui: CommandCenter (mapa operacional), Console Forense, SLA Audit Screen, Financial Impact Dashboard, Financial Trend.

🛡 **SLA Audit Engine**

O coração do sistema. Detecta automaticamente:
- **EXECUTADO**
- **NO-SHOW**
- **EVIDENCE GAP**
- **PENDING**

Baseado em Geofence determinística, permanência mínima (dwell time), janela operacional e sweep automático de obrigações expiradas. Sem heurísticas subjetivas. Sem interpretação humana.

💰 **Camada Financeira**

### Money VO
Todos os cálculos financeiros utilizam `Money` (cents-based), eliminando problemas de floating point.

### Financial Impact Projection
Calcula Receita Total Contratada, Receita Protegida, Receita em Risco, Receita Perdida (com multa) e seus respectivos percentuais.

### Snapshot Financeiro Diário
- Baseado no dia operacional do Brasil (`America/Sao_Paulo`)
- Persistido em UTC
- Imutável / Idempotente
- Pronto para ambiente enterprise
- Snapshots não recalculam retroativamente, garantindo auditabilidade financeira.

🕒 **Estratégia Temporal**
- Armazenamento sempre em UTC
- Conversão para Brasil apenas na UI
- `statusLastUpdatedAtUtc` rastreia transições
- Dia operacional baseado em timezone explícito
- Sem uso de `DateTime.now()` direto nas regras ou `toLocal()`.

� **Command Center (Camada Operacional)**
Mapa em tempo real com Fleet Simulation, normalização de ruído, Situation Engine, alertas hierarquizados e Forensic Console Strip. O OCC não é o produto final; é a fonte de evidência para auditoria contratual.

🔌 **Telemetria**
Fluxo reativo via Riverpod: `Raw Telemetry` → `OperationalStateNormalizer` → `Evaluation Engine` → `ExecutionState Repository` → `Projections` → `UI`. Sem polling. Sem acoplamento. Reativo.

� **Persistência**
BusFlow é *persistence-agnostic*. Pode rodar em Supabase, PostgreSQL, SQLite, In-Memory ou qualquer adapter compatível. Infraestrutura não define o domínio.

🧪 **Testes**
Suíte rigorosa de automação de QA cobrindo de ponta-a-ponta:
- Cobertura de 100% no Core Engine e regras de SLA.
- Testes de **Event Replay** (Event Sourcing integrity).
- Testes de **Resiliência e Reconexão** Realtime.
- Testes de **Idempotência** e proteção contra "Poison Pills".
- Validação de imutabilidade via banco (Postgres Hardening).
- Execução: `flutter test`

🚀 **Como Executar (Admin Web)**
```bash
flutter run -d chrome -t lib/main.dart --web-port 8080
```

🔒 **Segurança**
- PIN Lock no Admin via Environment Variables.
- Forensic Ledger **Append-Only** (RLS Hardening).
- Snapshot Financeiro Imutável (Revoke Update/Delete).
- Segregação estrita entre comandos e consultas (CQRS).

📌 **Status do Projeto**
O BusFlow consolidou sua fundação Enterprise. O sistema possui um **SLA Engine determinístico**, persistência imutável em **PostgreSQL/Supabase** e um pipeline de telemetria com **Idempotência Funcional**. A infraestrutura está preparada para auditoria financeira profissional com 100% de rastreabilidade.

🧭 **Visão de Futuro**
- Painel de tendências históricas (Trends) e Analytics preditivo.
- Integração nativa com protocolos GTFS-Realtime e gateways IoT.
- Exportação de evidências forenses e relatórios fiscais.
- APIs B2B para integração direta com ERPs (SAP, Totvs, Oracle).
- Expansão do sistema de alertas via Webhooks.

📚 **Documentação & Governança do Repositório**

Todo o contexto arquitetural, regras de engenharia e histórico de governança residem duravelmente na pasta `docs/` dentro do próprio repositório. O acesso à documentação é estruturado da seguinte forma:

*   [`docs/architecture/`](./docs/architecture/)
    *   `01_system_overview.md`
    *   `02_event_pipeline.md`
    *   `03_multi_tenant_foundation.md`
    *   `04_contract_rules_engine.md`
    *   `05_occ_operational_model.md`
*   [`docs/governance/`](./docs/governance/)
    *   `lifecycle_framework.md` (Governança Ágil do Conselho de Engenharia)
*   [`docs/governance/compliance/`](./docs/governance/compliance/)
    *   Relatórios de Validação e Auditorias
*   [`docs/runbooks/`](./docs/runbooks/)
    *   Procedimentos Operacionais (ex: `operational_testing.md`)
