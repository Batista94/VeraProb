# 🌊 VeraProb

### The Immutable Verifier for B2B Compliance & Financial Protection

**VeraProb** is a high-performance platform designed to eliminate friction between B2B contracts and operational execution. It acts as an automated, impartial **"Digital Judge"** that transforms raw telemetry into **Verifiable Contractual Truth**.

---

## 🏛️ Architecture & Data Pipeline

The platform follows a strict **Event-Sourced** logic across four core stages to ensure a forensic audit trail:

1. **Ingestion:** Raw telemetry (GPS, IoT, Check-ins) is received via secure Edge Functions.
2. **Normalization:** Noisy data is unified into **Canonical Facts** (Deterministic Snapshots).
3. **Evaluation:** Facts are replayed against **SLA Rules** by the Forensic Evaluation Engine.
4. **Verdict:** Financial impacts (penalties/approvals) are sealed into an **Immutable Ledger** (INV-7).

---

## 🚀 Getting Started (Local Development)

VeraProb relies on the **Supabase CLI (Docker)** to replicate the production environment locally, ensuring RLS policies and Edge Functions work as expected.

### 1. Prerequisites

- **Flutter SDK** (>= 3.41.5)
- **Docker Desktop** (Active)
- **Supabase CLI** (`brew install supabase/tap/supabase`)

### 2. Setup Infrastructure

```bash
# Start local containers (PostgreSQL, Auth, Storage, Edge Functions)
supabase start

# Apply local migrations and seed data
supabase db reset
```

### 3. Setup Environment

Copy .env.example to .env and fill in the local keys obtained from supabase status:

```bash
cp .env.example .env
```

### 4. Run Application

```bash
flutter run -d chrome --web-renderer wasm
```

### 🛡️ Project Structure (Clean Architecture)

- **lib/domain/**: Sovereign logic, Entities, and Repository Interfaces (Zero Infrastructure Dependencies).
- **lib/infrastructure/**: Supabase/Postgres implementations, External Adapters, and Data Mappers.
- **lib/application/**: Business use cases, Commands, Handlers, and Projections.
- **lib/state/**: Riverpod Providers and global state management.
- **lib/presentation/**: Flutter UI (Atomic Widgets, Features, and Screens).
- **lib/core/**: Shared utilities, Forensic Invariants, and Constants.

### ⚖️ Forensic Compliance Standards

VeraProb adheres to the 25 Forensic Invariants to guarantee legal admissibility:

- **INV-9 (UTC Mastery):** All logic, persistence, and timestamps are strictly UTC-based.
- **INV-19 (Financial Shield):** Real-time monitoring with dynamic budget caps to protect operator margins.
- **INV-1 (Tenant Isolation):** Multi-tenant sovereignty enforced via PostgreSQL Row-Level Security (RLS).
- **INV-2 (Precision):** All financial operations handled in integer cents via Money Value Objects.
