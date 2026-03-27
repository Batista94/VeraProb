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

## ⚠️ CRITICAL SECURITY NOTES

- **MFA Bypass (INV-6):** SuperAdmin MFA check is **BYPASSED in `kDebugMode`** (Local Dev) to maintain compatibility with local Supabase CLI instances.
- **PROD REQUIREMENT:** MFA **MUST BE ENABLED** in Supabase Dashboard for Staging and Production environments. The bypass only functions during local development (`kDebugMode`).
- **Audit:** Any release to Staging requires full end-to-end verification of the TOTP enrollment and challenge flow.

---

## 📍 LIVE STATUS: Phase 9.7 (The Brain)

**Current Objective:** Core Forensic Intelligence — Finalizing Evidence Snapshots & Wizard. [READY FOR FIRST TENANT](docs/governance/roadmap.md#milestone-gate-ready-for-first-tenant)

- **Done:** Phase 9.5 ✅ · Phase 9.6 ✅ (Shield) · Kinematic Guard ✅ · GeoMath ✅
- **Tests:** 1048 passing (+6 new MFA tests) · 23 skipped · 0 failures ✅
- **Next Up:**
  1. **Visual Evidence Snapshots:** Mini-map generation in audit cards.
  2. **Wait for Final RLS Audit:** Verification of data isolation between tenants.

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
