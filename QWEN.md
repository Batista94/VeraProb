# VeraProb — QWEN Context File

## Project Overview

**VeraProb** is a high-performance **B2B SLA Compliance & Financial Protection Platform** built with **Flutter/Dart**. It acts as an automated "Digital Judge" that transforms raw telemetry data (GPS, IoT, Check-ins) into **Verifiable Contractual Truth** through an event-sourced pipeline with forensic auditability.

### Core Pipeline

1. **Ingestion** — Raw telemetry received via secure Edge Functions
2. **Normalization** — Data unified into Canonical Facts (deterministic snapshots)
3. **Evaluation** — Facts replayed against SLA Rules by the Forensic Evaluation Engine
4. **Verdict** — Financial impacts sealed into an Immutable Ledger (INV-7)

### Architecture: Clean Architecture (C4 Model)

| Layer | Path | Responsibility |
|---|---|---|
| **Domain** | `lib/domain/` | Entities, value objects, repository interfaces. Zero infrastructure dependencies (INV-18: Domain Sovereignty) |
| **Application** | `lib/application/` | Use cases, commands, handlers, projections, adapters, ports |
| **Infrastructure** | `lib/infrastructure/` | Supabase/Postgres implementations, external adapters, data mappers, persistence |
| **State** | `lib/state/` | Riverpod providers and global state management |
| **Presentation** | `lib/presentation/` / `lib/features/` | Flutter UI with atomic widgets, feature screens |
| **Core** | `lib/core/` | Shared utilities, forensic invariants, constants, theme, config, time |

### Key Domain Bounded Contexts (`lib/domain/`)

- `admin/` — Administration
- `auth/` — Authentication & authorization
- `authority/` — Authority/access control
- `entities/` — Core business entities
- `sla_audit/` — SLA evaluation and verdict logic
- `stops/` — Stop/route management
- `super_admin/` — Super-admin functionality
- `assets/`, `enums/`, `services/`, `shared/`

---

## Technologies

- **Flutter SDK** >= 3.41.5 / **Dart** ^3.10.8
- **State Management:** Flutter Riverpod
- **Backend:** Supabase (PostgreSQL, Auth, Storage, Edge Functions)
- **Local DB:** Drift (SQLite) for offline LocalFactQueue
- **Maps:** flutter_map + latlong2
- **Charts:** fl_chart
- **Observability:** Sentry, PostHog
- **Localization:** intl, flutter_localizations (PT-BR)
- **Testing:** flutter_test, integration_test, mocktail, fake_async

---

## Building and Running

### Prerequisites

- Flutter SDK (>= 3.41.5)
- Docker Desktop (active)
- Supabase CLI

### Setup & Run

```bash
# 1. Start local Supabase infrastructure (Docker)
supabase start

# 2. Apply migrations and seed data
supabase db reset

# 3. Configure environment
cp .env.example .env
# (fill in keys from `supabase status`)

# 4. Run the app
flutter run -d chrome --web-renderer wasm
```

### Useful Commands

| Command | Description |
|---|---|
| `flutter run -d chrome --web-renderer wasm` | Run app in browser with WASM |
| `flutter analyze` | Static analysis (lints + type checking) |
| `flutter test` | Run unit/widget tests |
| `flutter test --coverage` | Run tests with coverage |
| `flutter test integration_test/` | Run integration tests |
| `dart run build_runner build` | Generate code (Drift, etc.) |
| `bash scripts/pr_scanner.sh` | Forensic PR scanner (run before merge) |
| `bash scripts/pr_full_scanner.sh` | Full PR scan (Ledger/RLS/Ingestion changes) |
| `supabase start` | Start local Supabase containers |
| `supabase db reset` | Reset DB with migrations + seed |
| `bash scripts/run_dev.ps1` | Run in dev mode (PowerShell) |
| `bash scripts/run_staging.ps1` | Run in staging mode (PowerShell) |

### Code Generation

```bash
dart run build_runner build --delete-conflicting-outputs
```

---

## Development Conventions

### Forensic Invariants (25 Non-Negotiables)

All code MUST respect the 25 invariants defined in `.claude/rules/invariants.md`. Key highlights:

- **INV-9 (UTC Everywhere):** ALL timestamps MUST use `DateTime.now().toUtc()` — never bare `DateTime.now()`. This is a **CRITICAL FAILURE** if violated.
- **INV-1 (Tenant Isolation):** Every query MUST filter by `organization_id`.
- **INV-7 (Immutable Ledger):** No `UPDATE`/`DELETE` on ledger entries.
- **INV-18 (Domain Sovereignty):** Core domain is pure Dart — no Supabase/infra imports.
- **INV-19 (Penny Precision):** All currency as `BIGINT` cents via `Money` value object.

### Financial Precision Rules

- **Application Layer (DTOs):** Uses `int` (cents/bps)
- **Domain Layer:** Uses `Money` value object
- **Rates:** All rates/multipliers are `int` (10000 = 100%). Formula: `(value * BPS) ~/ 10000`

### TDD Requirement

- ALL new domain/application logic MUST be test-driven (write failing test first)
- 100% unit test coverage for domain/application logic before UI implementation
- Use `mocktail` for mocking

### Linting & Code Quality

See `analysis_options.yaml`:

- `avoid_print: true` — Use structured logging instead
- `unawaited_futures: true` — No fire-and-forget async
- `prefer_const_constructors: true`
- `use_super_parameters: true`
- `always_declare_return_types: true`
- `exhaustive_cases: true`
- `no_logic_in_create_state: true`
- `use_build_context_synchronously: true`
- `avoid_unnecessary_containers: true`

### Layer Isolation (C4)

- UI (`features/`) must **never** import `domain/` or `infrastructure/` directly
- Domain layer has **zero** infrastructure dependencies

---

## Key Directories

| Directory | Purpose |
|---|---|
| `lib/` | All application source code (Clean Architecture layers) |
| `supabase/` | Supabase migrations, seed data, and config |
| `sql/` | Raw SQL scripts |
| `scripts/` | Automation scripts (PR scanner, coverage, bootstrap) |
| `test/` | Unit and widget tests |
| `integration_test/` | End-to-end integration tests |
| `docs/` | Documentation, governance, forensic manifesto |
| `.claude/` | AI agent rules, personas, skills, and worktrees |
| `assets/` | Static assets (fonts, etc.) |

---

## Slash Commands / Agent Personas

The project uses a **Council of Personas** system defined in `.claude/`:

| Persona | Role |
|---|---|
| **Architect** | Domain integrity, Bounded Contexts & C4 |
| **Senior Engineer** | Dart/Wasm, Riverpod, SQL & TDD |
| **QA & Security** | RLS, Tenant Isolation & Forensic Proof |
| **UX & Operations** | Material 3, OCC & Cognitive Load |
| **Business Maverick** | ROI, Strategy & Product Market Fit |
| **Lead Reviewer** | Gatekeeper — runs `/veraprob-pr-scanner` |

### Available Commands

- `/init` — Re-sync all rules and agents context
- `/council` — Invoke the Council of Personas
- `/audit` — Execute forensic audit (Invariants + PR Scanner)
- `/tdd` — Start a Test-Driven Development loop
- `/veraprob-pr-scanner` — Run full PR scan

---

## Current Status

**Phase:** 10.5 — The Forensic Truth (Hardening Architecture & Layer Isolation)
**Recent Milestone:** Phase 10.4 WS-5 (Telemetry Map-Sync) COMPLETED
**Next:** Lote 5 (C4 Correction) & Infrastructure DB Sync

---

## Important Files

| File | Purpose |
|---|---|
| `CLAUDE.md` | Master orchestrator — read before any task |
| `.claude/rules/invariants.md` | 25 non-negotiable forensic rules |
| `.claude/rules/protocol.md` | Execution & interaction protocol (TDD, task lifecycle) |
| `.claude/rules/performance.md` | Model selection guidance |
| `.claude/rules/dart-flutter.md` | Dart/Flutter technical standards |
| `.claude/rules/security.md` | Security standards |
| `analysis_options.yaml` | Dart analyzer configuration |
| `pubspec.yaml` | Project dependencies and configuration |
| `.cursorrules` | Editor-level rules and auto-initialization |
