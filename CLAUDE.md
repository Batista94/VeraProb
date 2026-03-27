# VeraProb — CLAUDE.md

VeraProb is an **Automated SLA Compliance & Financial Protection Platform** (the "Digital Judge"): ingests telemetry, evaluates rules, and generates immutable financial verdicts.

**Stack:** Flutter Web (>= 3.41.5) · Supabase (PostgreSQL + RLS) · Riverpod
**Context:** [README.md](README.md)

---

## 🏗️ Technical Context

| Area | Rule / Path |
| :--- | :--- |
| **Standards** | [.claude/rules/invariants.md](.claude/rules/invariants.md) (THE LAW) |
| **Protocol** | [.claude/rules/protocol.md](.claude/rules/protocol.md) (Execution rules) |
| **Dart/Flutter** | [.claude/rules/dart-flutter.md](.claude/rules/dart-flutter.md) |
| **Security** | [.claude/rules/security.md](.claude/rules/security.md) |
| **Structure** | `lib/` (application, core, data, domain, features, infra, presentation, state) |
| **Council** | Agent personas are in `docs/council/` and `.claude/agents/`. |

---

## 📍 LIVE STATUS: Phase 9.6.A.2

**Current Objective:** Security & Data Foundation (The Shield) — [READY FOR FIRST TENANT](docs/governance/roadmap.md#milestone-gate-ready-for-first-tenant)

- **Done:** Phase 9.5 ✅ · Phase 9.6.A.1 ✅ (Edge Proxy — `service_role` removed from WASM bundle, `super-admin-proxy` Edge Function) · Phase 9.7 partial ✅
- **Tests:** 1062 passing · 23 skipped · 0 failures
- **Next Step:** **Phase 9.6.A.2 — MFA for SuperAdmin** (TOTP enforcement + JWT Circuit Breakers). Deploy `super-admin-proxy` first (see roadmap).
- **SECURITY BLOCKER:** Do NOT advance to UI-only phases (9.7 remaining, 9.8) until Phase 9.6 Security is sealed. See [`security.md`](.claude/rules/security.md).

---

## 🛠️ Assistant Commands

- `/veraprob-pr-scanner` — Forensic PR scanner (run before any code review)
- `/hostile-defense-attorney` — RLS and financial verdict auditor
- `/iot-chaos-simulator` — Chaos tests for EvaluationEngine
- `/test-driven-development` — TDD workflow

---

## Council Orchestration

Invoke specialized agents based on task context:

- Architect (DB/Schema) · Senior Engineer (Logic/Perf) · QA Security (RLS) · UX Ops (UI) · Business Maverick (ROI).
- **Lead Reviewer:** Mandatory for Every PR and all Nuclear changes.
