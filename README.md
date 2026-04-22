# VeraProb

VeraProb is a high-performance platform designed to eliminate friction between B2B contracts and operational execution. It acts as an automated, impartial "Digital Judge" that transforms raw telemetry into Verifiable Contractual Truth.

---

## Architecture & Data Pipeline

The platform follows a strict Event-Sourced logic across four core stages to ensure a forensic audit trail:

1. **Ingestion**: Raw telemetry (GPS, IoT, Check-ins) and **Forensic Evidence (Telegram Bot)** are received via secure Edge Functions.
2. **Normalization**: Noisy data is unified into Canonical Facts (Deterministic Snapshots).
3. **Evaluation**: Facts are replayed against SLA Rules by the Forensic Evaluation Engine.
4. **Verdict**: Financial impacts (penalties/approvals) are sealed into an Immutable Ledger (INV-7).

---

## Getting Started (Local Development)

VeraProb relies on the **Supabase CLI (Docker)** to replicate the production environment locally, ensuring RLS policies and Edge Functions work as expected.

### 1. Prerequisites

- **Flutter SDK** (>= 3.41.5)
- **Docker Desktop** (Active)
- **Supabase CLI** (`brew install supabase/tap/supabase`)
- **Node.js** (>= 18)

### 2. Setup Infrastructure

```bash
# Start local containers (PostgreSQL, Auth, Storage, Edge Functions)
supabase start

# Apply local migrations and seed data
supabase db reset

# Provision test users, drivers, and Telegram tokens
node scripts/bootstrap_dev.mjs
```

### 3. Setup Environment

Copy `.env.example` to `.env` and fill in the local keys obtained from `supabase status`:

```bash
cp .env.example .env
```

### 4. Run Application

```bash
flutter run -d chrome --web-renderer wasm
```

### 5. Test Credentials
For a list of pre-configured SuperAdmins, Org Admins, and Drivers, see:
👉 [Test Credentials Documentation](docs/governance/test_credentials.md)

---

## Testing & Quality

- **Unit/Integration Tests**: `flutter test`
- **Load & Stress Testing**: Scripts available in `scripts/load_test/` (using k6).
- **Forensic Scanning**: `bash scripts/pr_scanner.sh` (ensures compliance with INV-X).

### Project Structure (Clean Architecture)

- `lib/domain/`: Sovereign logic, Entities, and Repository Interfaces (Zero Infrastructure Dependencies).
- `lib/infrastructure/`: Supabase/Postgres implementations, External Adapters, and Data Mappers.
- `lib/application/`: Business use cases, Commands, Handlers, and Projections.
- `lib/state/`: Riverpod Providers and global state management.
- `lib/presentation/`: Flutter UI (Atomic Widgets, Features, and Screens).
- `lib/core/`: Shared utilities, Forensic Invariants, and Constants.

### Professional Standards
VeraProb adheres to strict Forensic Invariants to guarantee legal admissibility. For the complete list of 27 technical invariants and core protocols, refer to [CLAUDE.md](CLAUDE.md).
