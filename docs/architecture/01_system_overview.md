# System Overview: PactaFlow Platform

PactaFlow is a B2B SaaS platform focused on Operational Determinism and Contractual Margin Protection for the corporate transportation and charter market. 

Unlike traditional fleet tracking (TMS) or B2C mobility apps, PactaFlow is singularly focused on converting raw physical telemetry into **verifiable contractual truth** and **immutable financial projections**.

## 🧠 Princípios Arquiteturais (O "Core")
1. **Determinismo Histórico:** O sistema garante que uma re-execução de telemetria contra um contrato do passado gere *exatamente* o mesmo resultado financeiro. Isso é feito via **Snapshots de Regras** imutáveis atrelados a cada plano.
2. **Ledger Forense Imutável:** A `sla_audit_ledger` é a única fonte de verdade. Projeções financeiras são efeitos colaterais (read models) derivados dos eventos no ledger.
3. **Isolamento de Inquilino (Deep Multi-tenancy):** O `organization_id` não é apenas um filtro de UI, é a chave de particionamento físico do banco (Hash Partitioning) e o limite de segurança no nível de Row-Level Security (RLS) e Canais Realtime.
4. **Explicabilidade (Traceability):** Cada centavo de penalidade gerado possui um rastro até a `rule_id` e `rule_version` específica que o originou.

## 🔄 Fluxo de Dados: Da Telemetria ao Ledger
`Telemetria Bruta → Normalização (Anti-Spoofing) → Evaluation Engine → SLA Audit Ledger → Projeção Financeira`

## 🚀 Stack & Tooling
- **Frontend:** Flutter Web (SDK ^3.10.8) - Framework de UI compilado para Web.
- **State Management:** Riverpod (^2.5.1) - Reatividade escalável e testável.
- **Backend-as-a-Service:** Supabase (^2.12.0) - Auth, PostgreSQL (Bancos), Realtime e Storage.
- **Observability:** Sentry (Error Tracking) e PostHog (Product Analytics/Feature Flags).
- **Core Libraries:** `fl_chart` (Gráficos), `flutter_map` (Geolocalização), `pdf`/`csv` (Exportação).
- **CI/CD:** GitHub Actions gerindo `flutter analyze`, `test` e deploy via `--dart-define`.

## 🔒 Padrão de Segurança (Hardened Multi-Tenancy)
- **Identity:** Supabase Auth com JWT Claims customizados.
- **RLS (Row Level Security):** Isolamento de inquilinos (Tenants) via `organization_id` injetado na sessão do banco. 
- **Audit Ledger:** Tabela imutável `system_audit_log` para persistência de eventos críticos.
- **Data Protection:** PII Masking em banco de dados e criptografia de campos sensíveis.

## 🕸️ Interoperabilidade Web
- **Browser-Specific:** Uso de `universal_html` e `web` para manipulação de DOM, cookies e downloads nativos.
- **Filesystem Simulation:** Fluxos de exportação de relatórios via `file_saver` para suporte a grandes volumes de dados no frontend.
- **Responsive Design:** Interface otimizada para Desktop Admin e Tablet Operacional.

## 📈 Lógica de Ambiente (Environment Isolation)
O sistema utiliza uma classe singleton `EnvironmentConfig` que resolve configurações baseado em:
1. **Compile-time Variables:** `--dart-define` injetados pelos workflows de CI/CD (Prod/Staging).
2. **Local Overrides:** Arquivo `.env` para agilidade no desenvolvimento local.
3. **Ambientes:** `dev` (debug), `staging` (testes em réplica prod), `prod` (live).

## 📡 Integração PostHog
Centralizada no `AnalyticsService`, a integração permite:
- **Telemetry Insights:** Rastreio de performance do Evaluation Engine.
- **User Personas:** Segmentação de comportamento por organização e cargo.
- **Feature Flags:** Habilitação gradual de módulos críticos (ex: Shadow Mode).

## ✅ Estado Atual (Fase 8 - Finalizada)
O sistema atingiu maturidade técnica de infraestrutura:
- **Anti-Spoofing:** Algoritmos de detecção de GPS falso ativos.
- **Disaster Recovery:** Políticas de backup PITR e Runbook de restore validados.
- **Performance:** Benchmark aprovado para carga de 1.000 veículos simultâneos (Database Indexing & Pruning).
- **Próximos Passos:** Revisão técnica de módulos críticos, refatoração de UX e ajustes finos de regras de negócio.

