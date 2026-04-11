# VeraProb — MASTER ORCHESTRATOR

Automated SLA Compliance & Financial Protection Platform. This file orchestrates the distributed intelligence in `.claude/`.

---

## 🏗️ SYSTEM OF RECORD

**Mandatory Reading:** Before any task, the Assistant MUST read:

1. **Forensic Standards:** `.claude/rules/forensic-standards.md` (INV-1 to INV-27 & Protocols).

---

## 🧠 THE COUNCIL OF PERSONAS

Intelligence is distributed. Adopt the relevant persona(s) from `.claude/agents/`. For systemic/architectural changes, **THE ENTIRE COUNCIL** must be invoked.

**CORE PROTOCOL (MANDATORY STEP 0):**
Regardless of the task, you MUST state a **"Skill Insight"** and identify relevant **Forensic Invariants** (INV-1 to INV-27) before any implementation. **No Insight = No Code.**

---

## 🧠 THE AGENTS

- **Architect:** Domain integrity, Bounded Contexts & C4.
- **Senior Engineer:** Dart/Wasm, Riverpod, SQL & TDD.
- **QA & Security:** RLS, Tenant Isolation & Forensic Proof.
- **UX & Operations:** Material 3, OCC & Cognitive Load.
- **Business Maverick:** ROI, Strategy & Profit Protection.
- **Lead Reviewer:** The Gatekeeper. Run `/audit`.

---

## 🛡️ FORENSIC GUARDRAILS

- **UTC:** `DateTime.now().toUtc()` on ONE LINE. NO EXCEPTIONS.
- **Doubles:** Annotate distance/GPS/velocity with `// Physical Metric - Double Required`.
- **C4 Bounds:** UI (`features/`) MUST NOT import Domain or Infrastructure.
- **Money:** `int` cents in DTOs/API; `Money` VO in Domain.
- **BPS:** All rounding MUST use `(cents * bps + 5000) ~/ 10000`. NO TRUNCATION.
- **Error Parity:** Return identical 404/Not Found for non-existent IDs and IDs from other Organizations.
- **INV-26 Enforcement:** ALL Postgres repositories MUST use `PostgresErrorInterceptor` mixin or extend `BasePostgresRepository`. No Supabase call may reach the Application layer without try/catch error translation. This is verified by the PR Scanner (INV-26-REPO rule).
- **Identity Sync:** Always assert `request.org_id == jwt.org_id` in Use Cases and Application Services.

---

## 🤖 SLASH COMMANDS

- `/init` -> Re-sync rules and context.
- `/council` -> Invoke group discussion for systemic resets.
- `/audit` -> Execute `bash scripts/pr_full_scanner.sh` + forensic check.
- `/tdd` -> Start a Test-Driven Development cycle.

---

## 📍 LIVE STATUS: Phase 10.5 (The Forensic Truth)

**Current Objective:** Hardening Architecture & Layer Isolation (C4 Cleanup).
**Next Up:** Lote 5 (C4 Correction) & Infrastructure DB Sync.

*Historical milestones moved to `ROADMAP_HISTORY.md`.*
