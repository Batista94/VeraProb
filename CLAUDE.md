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

## 📍 LIVE STATUS: Phase 10.4 (The Polish & Differential)

**Current Objective:** OCC UX Polish — Ingestion Health & Alerts. [READY FOR FIRST TENANT](docs/governance/roadmap.md#milestone-gate-ready-for-first-tenant)

- **Done:** Phase 9.8 ✅ · 10.1 (Schema Lock) ✅ · 10.2 (WASM) ✅ · 10.3 (Shadow Mode) ✅ · 10.4.WS-1 ✅ · 10.4.WS-2 ✅ · 10.4.WS-3 ✅ · 10.4.WS-6 ✅
- **Tests:** 1571 passing · 18 skipped · 0 failures ✅
- **Next Up:**
  1. **10.4.WS-4 — Telegram Evidence Bot:** Deno Edge Function + Hot-linking to Verdict Cards.

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
