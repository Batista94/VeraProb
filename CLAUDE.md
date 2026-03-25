# VeraProb — CLAUDE.md

VeraProb is an **Automated SLA Compliance & Financial Protection Platform** that acts as an impartial, automated Judge: ingests real-world telemetry, evaluates against contractual rules, and generates immutable financial verdicts. The core engine is industry-agnostic (current focus: B2B Logistics/Charter).

**Stack:** Flutter Web (>= 3.41.5) · Supabase (PostgreSQL + RLS) · Riverpod
**Integrated Services (free/freemium):** Supabase · MapTiler · Sentry · PostHog · Resend

**Pipeline:** Ingestion (Adapters) → Normalization (Canonical Fact) → Timeline Reconstruction → EvaluationEngine → ImmutableLedger → FinancialSnapshots → QueryServices → OCC

---

## File Structure

```
lib/
  application/        # UseCases / Command Handlers
  core/               # Shared utilities, config, theme, validators
  data/               # Repository implementations (data layer)
  domain/             # Pure Dart entities, VOs, interfaces (no infra deps)
  features/           # UI modules (admin, super_admin, shared)
  infrastructure/     # Supabase/external service implementations
  presentation/       # Shell, routing, top-level providers
  state/              # Riverpod providers
docs/
  council/            # Persona files (architect, QA, lead_reviewer, etc.)
supabase/
  migrations/         # All schema changes via migration files only
```

---

## Current Phase

**Phase 9 — IN PROGRESS. Sub-phases 9.1–9.4 [GO]. Sub-phases 9.5–9.8 PENDING.**
**Gate `READY FOR CI/CD` — ACHIEVED.**
**Phase 10.1 (Schema Lock & Migration Freeze) — [GO].**
**Current Objective: complete Phase 9 (9.5 → 9.6 → 9.7 → 9.8) then Phase 10 (10.2 → 10.3 → 10.4 → 10.5).**
Next sub-phase: **9.5 — Vínculo Dinâmico & UX do Operador.**
Gate target: `READY FOR FIRST TENANT`.
See full roadmap: [docs/governance/roadmap.md](docs/governance/roadmap.md)

---

## Execution Protocol

- **Proposed Action Plan:** Present a plan and wait for PO authorization before every task.
- **Approved Plan Autonomy:** Once a plan is approved by the PO, execute sub-phases sequentially without re-requesting authorization at each step. Pause only for: unexpected blockers, binary decisions requiring PO input, or destructive actions outside plan scope.
- **Council & Skills Autonomy:** Invoke council agents and skills proactively based on context — no explicit PO instruction required.
- **Lead Reviewer Invocation:** Mandatory for every PR, Workspace Audit, or "Nuclear" change.
- **No Skip Policy:** Technical excellence over speed. Simplicity is a forensic requirement.

Council personas live in `docs/council/`. Lead Reviewer is the final arbiter.

---

## Council Orchestration

Agents live in `.claude/agents/`. Invoke proactively based on context:
- Architecture/DB/schema changes → architect
- Performance/Flutter/SLA logic → senior-engineer
- RLS/security/financial tables → qa-security-lead
- UI/UX/accessibility → ux-ops-director
- Roadmap/ROI/product decisions → business-maverick
- Every PR / Nuclear change → lead-reviewer (mandatory)

When in doubt, invoke all relevant agents before proposing a plan.

---

## Standards

| Rule File | Covers |
|---|---|
| [.claude/rules/invariants.md](.claude/rules/invariants.md) | The 25 Non-Negotiable Invariants (THE LAW) |
| [.claude/rules/dart-flutter.md](.claude/rules/dart-flutter.md) | Dart/Flutter coding standards, SOLID, DDD patterns |
| [.claude/rules/security.md](.claude/rules/security.md) | RLS, multi-tenancy, secrets, JWT claims |
| [.claude/rules/roadmap.md](.claude/rules/roadmap.md) | Milestones, gates, and phase definitions |

---

## Available Skills

- `/veraprob-pr-scanner` — Forensic PR scanner (run before any code review)
- `/hostile-defense-attorney` — RLS, schema, and financial verdict auditor
- `/ingestion-streaming-architect` — Event pipeline and idempotency gate
- `/iot-chaos-simulator` — Chaos tests for EvaluationEngine and telemetry
- `/systematic-debugging` — Structured debugging protocol
- `/test-driven-development` — TDD workflow

## Git Workflow

- Conventional commits: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`
- Never commit directly to `main`
- All PRs require Lead Reviewer [GO] verdict for core/RLS changes
