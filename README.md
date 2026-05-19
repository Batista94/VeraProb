# VeraProb - Forensic Contract Governance

[![License: Proprietary](https://img.shields.io/badge/License-Proprietary-red.svg)](LICENSE)

[Português](#português) | [English](#english)

---

<a name="português"></a>
## Português

VeraProb é um estudo de engenharia focado em **Forensic Contract Governance**. O projeto explora a construção de sistemas de alta performance capazes de converter Telemetria bruta em verdade contratual, eliminando o atrito entre contratos B2B e execução operacional.

> [!WARNING]
> **Projeto Pessoal - Build to Learn**: Este repositório é estritamente um laboratório de aprendizado e experimentação técnica com rigor profissional. O código não foi auditado, não possui clientes ou ambiente de produção real, e **não deve ser utilizado em sistemas reais ou de produção**. Pode conter vulnerabilidades, bugs de implementação e comportamentos inesperados.

### Objetivos (Build to Learn)
Este repositório é um laboratório de aprendizado pessoal dedicado a exercitar o rigor de sistemas Enterprise em um contexto de desenvolvimento solo. O foco está na aplicação de arquiteturas amplamente utilizadas em cenários de alta criticidade:
- **Solo-Enterprise Rigor**: Aplicação de padrões de sistemas Tier 1 (DDD, Event Sourcing, WASM) em um fluxo individual.
- **Forensic Accuracy**: Garantia de que cada transação e estado seja auditável e matematicamente preciso (INV-4/5).
- **AI-Assisted Architecture**: Exploração de como a colaboração com agentes de IA pode sustentar padrões de Clean Code e complexidade controlada.

### Pilares de Engenharia
- **Domain-Driven Design (DDD)**: Camada de domínio agnóstica e isolada contendo a lógica de "Verdade Contratual".
- **Event-Sourced Logic**: Replay de fatos contra SLA Rules para gerar vereditos determinísticos.
- **Deterministic Snapshots**: Unificação de telemetria bruta em Canonical Facts.
- **Immutable Ledger**: Selagem de impactos financeiros em um registro imutável (INV-3).

### Stack Tecnológica
- **Frontend**: Flutter (WASM), Riverpod, Industrial Deep Design.
- **Backend**: Supabase, PostgreSQL (PostGIS), Edge Functions.
- **Segurança**: SHA-256, HMAC per-org (INV-28), Magic Bytes Entropy.
- **Governança**: Sequential Thinking (MCP), Lead Reviewer AI, Forensic Scanner.

### Execução Local

#### 1. Pré-requisitos
- **Flutter SDK** (3.41.9 Pinned)
- **Docker Desktop**
- **Supabase CLI**
- **Node.js** (>= 18)

#### 2. Setup
```bash
# Inicializar infraestrutura (Supabase)
supabase start
supabase db reset

# Preparar ambiente e dados (Makefile)
make setup
make env

# Construir ambiente de auditoria (Docker)
make build-test-env

# Executar aplicação
flutter run -d chrome --web-port=8080 --dart-define=SKIP_MFA_DEV=true
```

#### 3. Variáveis de Ambiente (Segurança)
Para cumprir a invariante de segurança **INV-2**, chaves e segredos nunca são mantidos no código-fonte:
- O comando `make env` gera o arquivo `.env` local (ignorado pelo Git).
- O arquivo `.env.example` contém os nomes das variáveis e chaves padrão para o stack local.
- **Credenciais de Teste**: O sistema utiliza credenciais determinísticas (`master@veraprob.dev`) exclusivamente para o bootstrap do ambiente local de desenvolvimento. Estas são credenciais públicas de teste e não possuem acesso a nenhum recurso real.
- **Testes de Integração**: O `PostgresTestConfig` carrega automaticamente as credenciais do `.env` durante a execução dos testes.

#### 4. Validação e Execução de Testes (`make full-check`)
O comando `make full-check` executa a verificação máxima do sistema (scans de segurança, testes unitários, de integração, E2E, caos e cobertura). Para que a suíte seja validada por completo sem ignorar (skip) testes dependentes de infraestrutura:
- **Supabase Local**: O stack de containers deve estar rodando (`supabase start`).
- **Edge Functions**: As funções devem estar servidas localmente em background (`supabase functions serve --env-file .env` ou via `make run`).
- **Provisionamento de Dados**: O Make executa automaticamente o `make setup` (`bootstrap_dev.mjs`) e injeta as credenciais do `.env` nos testes, garantindo que o usuário SuperAdmin (`master@veraprob.dev`) e os dados de telemetria estejam provisionados.

### Guia de Fluxo

| Ação | Comando | Descrição |
| :--- | :--- | :--- |
| **Ambiente** | `make build-test-env` | Constrói o container Linux de auditoria. |
| **Execução** | `flutter run` | Desenvolvimento local com Hot Reload. |
| **Check Forense** | `make check` | Valida integridade, segredos e padrões forenses. |
| **Full Check** | `make full-check` | Executa o check completo + testes unitários, E2E e de banco (requer Supabase local e Edge Functions ativas). |
| **Visual Regression** | `make goldens` | Gera/Valida capturas de tela em ambiente Linux. |

Para detalhes sobre as diretrizes de desenvolvimento e padrões de qualidade, consulte [CLAUDE.md](CLAUDE.md).

---

<a name="english"></a>
## English

VeraProb is an engineering study focused on **Forensic Contract Governance**. The project explores the construction of high-performance systems capable of converting Raw Telemetry into Verifiable Contractual Truth, eliminating friction between B2B contracts and operational execution.

> [!WARNING]
> **Personal Project - Build to Learn**: This repository is strictly a learning lab and senior-level technical experimentation ground. The code has not been audited, has no real clients or live production environment, and **must not be used in live or production systems**. It may contain vulnerabilities, implementation bugs, and unexpected behaviors.

### Objectives (Build to Learn)
This repository is a personal learning lab for exercising production-level rigor in solo projects. It focuses on proven architectural patterns for critical systems:
- **Solo-Enterprise Rigor**: Applying Tier 1 system patterns (DDD, Event Sourcing, WASM) in an individual workflow.
- **Forensic Accuracy**: Ensuring every transaction and state is auditable and mathematically precise (INV-4/5).
- **AI-Assisted Architecture**: Exploring how deep collaboration with AI agents can sustain Clean Code standards and controlled complexity.

### Engineering Pillars
- **Domain-Driven Design (DDD)**: Agnostic and isolated domain layer containing the "Contractual Truth" logic.
- **Event-Sourced Logic**: Fact replay against SLA Rules to generate deterministic verdicts.
- **Deterministic Snapshots**: Telemetry unification into Canonical Facts.
- **Immutable Ledger**: Sealing financial impacts into an immutable record (INV-3).

### Tech Stack
- **Frontend**: Flutter (WASM), Riverpod, Industrial Deep Design.
- **Backend**: Supabase, PostgreSQL (PostGIS), Edge Functions.
- **Security**: SHA-256, HMAC per-org (INV-28), Magic Bytes Entropy.
- **Governance**: Sequential Thinking (MCP), Lead Reviewer AI, Forensic Scanner.

### Local Execution

#### 1. Prerequisites
- **Flutter SDK** (3.41.9 Pinned)
- **Docker Desktop**
- **Supabase CLI**
- **Node.js** (>= 18)

#### 2. Setup
```bash
# Initialize infrastructure (Supabase)
supabase start
supabase db reset

# Prepare environment and data (Makefile)
make setup
make env

# Build audit environment (Docker)
make build-test-env

# Run application
flutter run -d chrome --web-port=8080 --dart-define=SKIP_MFA_DEV=true
```

#### 3. Environment Variables (Security)
To comply with the **INV-2** security invariant, keys and secrets are never kept in the source code:
- The `make env` command generates the local `.env` file (ignored by Git).
- The `.env.example` file contains the variable names and default keys for the local stack.
- **Test Credentials**: The system uses deterministic credentials (`master@veraprob.dev`) exclusively for local development environment bootstrap. These are public test credentials and have no access to any real resources.
- **Integration Tests**: `PostgresTestConfig` automatically loads credentials from `.env` during test execution.

#### 4. Test Validation and Execution (`make full-check`)
The `make full-check` command runs the ultimate validation suite (security scans, unit tests, integration, E2E, chaos, and coverage). To ensure the suite validates completely without skipping infrastructure-dependent tests:
- **Local Supabase**: The container stack must be active (`supabase start`).
- **Edge Functions**: Functions must be served locally in the background (`supabase functions serve --env-file .env` or via `make run`).
- **Data Provisioning**: Make automatically runs `make setup` (`bootstrap_dev.mjs`) and injects `.env` credentials into test runners, ensuring the SuperAdmin user (`master@veraprob.dev`) and telemetry seed data are properly provisioned.

### Workflow Guide

| Action | Command | Description |
| :--- | :--- | :--- |
| **Environment** | `make build-test-env` | Builds the Linux audit container. |
| **Run** | `flutter run` | Local development with Hot Reload. |
| **Forensic Check** | `make check` | Validates integrity, secrets, and forensic patterns. |
| **Full Check** | `make full-check` | Runs the full check + unit, E2E, and database tests (requires local Supabase and running Edge Functions). |
| **Visual Regression** | `make goldens` | Generates/Validates screenshots in Linux environment. |

For development guidelines and quality standards, refer to [CLAUDE.md](CLAUDE.md).
