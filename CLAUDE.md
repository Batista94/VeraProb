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
- **Supply Chain Security:** This is a **Pure Flutter/Dart** project. DO NOT introduce `package.json`, `node_modules`, or Node-based tooling to the root. This project is intentionally isolated from the Node.js/Axios supply chain vulnerabilities (e.g., Axios 1.14.1 / 0.30.4 Trojans).

---

## 📍 LIVE STATUS: Phase 9.8 (The Body)

**Current Objective:** Resilience & Operational Hub — Background Sync Resilience. [READY FOR FIRST TENANT](docs/governance/roadmap.md#milestone-gate-ready-for-first-tenant)

- **Done:** Phase 9.7 ✅ · 9.8.B ✅ · 9.8.C ✅ · 9.8.D (Hard Quota Enforcement) ✅ · 9.8.E (Global InfoTooltip) ✅ · 9.8.F (Searchable Entity Mapping) ✅ · 9.8.G (Heartbeat Monitor) ✅ · 9.8.H (Background Sync Resilience / LocalFactQueue) ✅ · 9.8.I (Late-Arrival Window Protocol) ✅
- **Tests:** 1372 passing · 18 skipped · 0 failures ✅
- **Next Up:**
  1. **9.8.J — Driver Defense Portal (MVP):** Portal for preventive justification submission linked to audit.

---

## 🛠️ Assistant Commands

- `/veraprob-pr-scanner` — Deterministic PR scanner: `bash scripts/pr_full_scanner.sh` (run before any code review)
- `/hostile-defense-attorney` — RLS and financial verdict auditor
- `/iot-chaos-simulator` — Chaos tests for EvaluationEngine
- `/test-driven-development` — TDD workflow

---

## Council Orchestration

Invoke specialized agents based on task context:

- Architect (DB/Schema) · Senior Engineer (Logic/Perf) · QA Security (RLS) · UX Ops (UI) · Business Maverick (ROI).
- **Lead Reviewer:** Mandatory for Every PR and all Nuclear changes.
