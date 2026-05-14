# VeraProb - Forensic Contract Governance

VeraProb is a high-performance platform designed to eliminate friction between B2B contracts and operational execution. It acts as an automated "Digital Judge" that transforms raw telemetry into Verifiable Contractual Truth, ensuring financial protection and forensic auditability.

---

## The Problem We Solve
1. **Revenue Leakage:** Capture of unplanned trips via **Shadow Executions**.
2. **Legal Fragility:** Replacing driver-vs-client disputes with a **Forensic PDF with Chain of Custody**.
3. **SLA Fraud:** Detection of **Clock Drift** and GPS spoofing.
4. **Penny Precision Gap:** Eliminating rounding errors using **INV-4/5 (Fixed-Point Math)** with BigInt.
5. **Evidence Poisoning:** Entropy scanning to detect malicious script injection in photos (Ratio > 0.60).
6. **Low Adoption:** Invisible, friction-free interface designed for field operators and drivers.

## Business Vision & ROI
- **Zero-Glosa objective:** Automated Proof of Delivery (POD) with forensic sealing accelerates cash flow.
- **90% Backoffice Reduction:** Automated reconciliation by exception eliminates manual photo checking.
- **Claims Shielding:** Irrefutable dossier forcing insurance payouts without contestation.
- **Civil Liability:** Systematic transfer of custody materialized at the moment of cryptographic sealing.

---

## Architecture & Data Pipeline
The platform follows a strict Event-Sourced logic:
1. **Ingestion:** Raw telemetry and Evidence (Telegram Bot) received via secure Edge Functions.
2. **Normalization:** Unification into Canonical Facts (Deterministic Snapshots).
3. **Evaluation:** Facts replayed against SLA Rules by the Forensic Evaluation Engine.
4. **Verdict:** Impacts sealed into an Immutable Ledger (INV-3).

## Tech Stack
- **Frontend:** Flutter (WASM), Riverpod, Industrial Deep Design.
- **Backend:** Supabase, PostgreSQL (PostGIS), Edge Functions.
- **Security:** SHA-256, HMAC per-org (INV-28), Magic Bytes Entropy.
- **Governance:** Sequential Thinking (MCP), Lead Reviewer AI, Forensic Scanner.

---

## Getting Started (Local Development)

### 1. Prerequisites
- **Flutter SDK** (3.41.9 Pinned)
- **Docker Desktop**
- **Supabase CLI**
- **Node.js** (>= 18)

### 2. Setup & Run
```bash
# Start infrastructure
supabase start
supabase db reset

# Provision test data
node scripts/dev/bootstrap_dev.mjs

# Setup environment
cp .env.example .env

# Run app
flutter run -d chrome --web-port=8080 --dart-define=SKIP_MFA_DEV=true
```

---

## 🏛️ Arquitetura & Governança (Tier 1)

O VeraProb é construído sob o rigor de **Enterprise Tier 1**, garantindo que o sistema seja determinístico, auditável e resiliente a falhas de ambiente.

### 1. Domain-Driven Design (DDD)
- **Domain Layer:** 100% agnóstica. Contém as 28 Invariantes Forenses e a lógica de "Verdade Contratual".
- **Application Layer:** Orquestra fluxos via *Command/Handlers* com suporte nativo a **Idempotência (INV-33)**.
- **Infrastructure:** Implementações desacopladas via *Ports & Adapters* (Postgres/Supabase).

### 2. Blindagem de Ambiente (Hermeticidade)
- **Docker-First Audit:** Todos os scanners de segurança e testes de regressão visual são executados em containers Linux isolados para garantir paridade total com o CI/CD.
- **Integrity Guard:** Vigilância binária que bloqueia commits com encoding inválido ou finais de linha Windows (CRLF).

---

## 🛠️ Guia de Sobrevivência (Como Rodar)

### 1. Setup do Ambiente de Auditoria
A "Fábrica" de testes precisa ser construída uma única vez (ou quando o `Dockerfile.test` mudar):
```bash
make build-test-env
```

### 2. Comandos de Fluxo Diário

| Ação | Comando | Descrição |
| :--- | :--- | :--- |
| **Ver o App** | `flutter run` | Desenvolvimento local com Hot Reload. |
| **Check Rápido** | `make check` | Valida integridade, segredos e padrões forenses (~30s). |
| **Veredito Final** | `make full-check` | Roda o `check` + todos os testes unitários e de banco. |
| **Regressão Visual** | `make goldens` | Gera/Valida capturas de tela em ambiente Linux. |

### 3. Padrões de Qualidade
> [!IMPORTANT]
> **Encoding & Line Endings:** Todos os arquivos DEVEM ser **UTF-8 (LF)**. O Integrity Guard impedirá o commit se detectar CRLF.
> **Por que LF no Windows?** Para garantir paridade total com o servidor Linux do GitHub Actions e com os scanners forenses dentro do Docker.

> [!IMPORTANT]
> **Hermetic Goldens** Sempre use `make goldens` para atualizar imagens de referência. Isso garante que os pixels sejam gerados em ambiente Linux, evitando falhas de divergência de renderização entre Windows e o CI (GitHub Actions).
> 1. **Nova UI:** Ao criar novos widgets com testes visuais.
> 2. **Mudança Intencional:** Após alterar cores, fontes ou layout de componentes existentes.
> 3. **Falha no CI:** Se o GitHub Actions reportar erro visual, mas você confirmou que a mudança está correta.

For the complete list of **28 Forensic Invariants**, refer to [CLAUDE.md](CLAUDE.md).
