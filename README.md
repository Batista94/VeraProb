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
Cobertura de domínio, Engine, Snapshot, Query Services e Widget.
- Execução: `flutter test`
- Análise: `flutter analyze`

🚀 **Como Executar (Admin Web)**
```bash
flutter run -d chrome -t lib/main_admin.dart --web-port 8080
```

🔒 **Segurança**
- PIN Lock no Admin
- Forensic Ledger append-only
- Controle RBAC
- Segregação de comandos
- Event logging auditável

📌 **Status do Projeto**
Produto em evolução contínua com Engine funcional, Snapshot financeiro implementado, camada financeira endurecida e arquitetura soberana validada. **Não é MVP. É fundação de produto enterprise.**

🧭 **Visão de Futuro**
- Persistência real de snapshots
- Trend baseado em `statusLastUpdatedAtUtc`
- Integração GTFS / IoT real
- APIs B2B
- Relatórios financeiros exportáveis
- Integração com ERPs
