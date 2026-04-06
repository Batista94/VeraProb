# VeraProb — MASTER ORCHESTRATOR

VeraProb is an **Automated SLA Compliance & Financial Protection Platform**. This file orchestrates the distributed intelligence stored in `.claude/`.

---

## 🏗️ SYSTEM OF RECORD (MANDATORY READING)

The Assistant MUST read these core files before any task:

1. **The Laws:** `.claude/rules/invariants.md` (25 Non-Negotiables).
2. **Execution:** `.claude/rules/protocol.md` (TDD, Task Lifecycle, and PO Approval).
3. **Performance:** `.claude/rules/performance.md` (Model selection: Sonnet for dev, Opus for Review).
4. **Tech Standards:** `.claude/rules/dart-flutter.md` and `security.md`.

---

## 🧠 THE COUNCIL OF PERSONAS

Intelligence is specialized. The Assistant MUST adopt the correct persona from `.claude/agents/` based on the context:

- **Architect (`architect.md`):** Domain design & Bounded Contexts.
- **Senior Engineer (`senior-engineer.md`):** SQL, Riverpod, Performance & TDD.
- **QA & Security (`qa-security.md`):** RLS, Tenant Isolation & Forensic Proof.
- **UX & Operations (`ux-operations.md`):** OCC screens & Cognitive Load.
- **Business Maverick (`business-maverick.md`):** ROI & Strategy.
- **Lead Reviewer (`lead-reviewer.md`):** The Gatekeeper. Run `/veraprob-pr-scanner`.

**Protocol:** If a task touches multiple areas, the Assistant must simulate a "Council Discussion" between these personas.

---

## 🛡️ FORENSIC DEVELOPMENT GUARDRAILS (PHASE 10.5)

These are the current active priorities that override any legacy patterns:

1. **Layer Isolation (C4):** UI (`features/`) must never import `domain/` or `infrastructure/`.
2. **Financial Precision:**
   - **Application Layer (DTOs):** Uses `int` (cents/bps).
   - **Domain Layer:** Uses `Money` value object.
   - **Rates:** All rates/multipliers are `int` (10000 = 100%). Formula: `(value * BPS) ~/ 10000`.
3. **Deterministic Time:** All timestamps MUST use `DateTime.now().toUtc()` on a single line.
4. **Tag Deprecation:** Use `// Physical Metric - Double Required` instead of `forensic-ignore`.

---

## 🛠️ ACTIVE COMMANDS (SKILLS)

Skills are located in `.claude/skills/`. Use them proactively:

- `/veraprob-pr-scanner` -> `bash scripts/pr_full_scanner.sh`
- `/hostile-defense-attorney` -> Audit for legal/financial loopholes.
- `/test-driven-development` -> Execute TDD cycle.

---

## 📍 LIVE STATUS: Phase 10.5 (The Forensic Truth)

**Current Objective:** Hardening Architecture & Layer Isolation (C4 Cleanup).
**Next Up:** Lote 5 (C4 Correction) & Infrastructure DB Sync.
