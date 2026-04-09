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

## 🧠 THE COUNCIL OF PERSONAS (CORE & SPECIALIZED)

Intelligence is distributed. For every task, adopt the relevant persona(s). For systemic, financial, or architectural changes, **THE ENTIRE COUNCIL MUST BE INVOKED** for a group verdict.

### Core Council (`.claude/agents/`)

- **Architect:** Domain integrity, Bounded Contexts & C4.
- **Senior Engineer:** Dart/Wasm, Riverpod, SQL & TDD.
- **QA & Security:** RLS, Tenant Isolation & Forensic Proof.
- **UX & Operations:** Material 3, OCC & Cognitive Load.
- **Business Maverick:** ROI, Strategy & Product Market Fit.
- **Lead Reviewer:** The Gatekeeper. Run `/veraprob-pr-scanner`.

### Specialized Counsel (`.claude/skills/`)

Invoke these proactively when their domain is touched. Skills in this directory are considered **Pre-Authorized** for internal use:

- **Hostile Defense Attorney:** Audit for legal/financial loopholes and repudability.
- **Ingestion Streaming Architect:** Low-latency telemetry & normalization logic.
- **IoT Chaos Simulator:** Verify resilience against hardware/GPS failure.
- **Prompt Injection Auditor:** Protect LLM-driven endpoints and summaries.
- **Strategic Duo:** `blue-ocean-strategy` & `product-strategy-session`.

**Protocol:**

1. **Mandatory Full Council:** For any migration affecting the Ledger, RLS policies, or Ingestion Engine.
2. **Standard Tasks:** Simulate a discussion between the 2-3 most relevant personas.
3. **No Consensus = No PR:** Conflicting personas must reach a "Forensic Compromise" before proposing changes.

---

## 🛡️ FORENSIC DEVELOPMENT GUARDRAILS (PHASE 10.5)

These are the current active priorities that override any legacy patterns:

1. **Layer Isolation (C4):** UI (`features/`) must never import `domain/` or `infrastructure/`.
2. **Financial Precision:**
   - **Application Layer (DTOs):** Uses `int` (cents/bps).
   - **Domain Layer:** Uses `Money` value object.
   - **Rates:** All rates/multipliers are `int` (10000 = 100%). Formula: `(value * BPS) ~/ 10000`.
3. **Deterministic Time:** All timestamps MUST use `DateTime.now().toUtc()` on a single line. NEVER use DateTime.now() without .toUtc(). Any occurrence is a CRITICAL FAILURE. Assistant MUST auto-fix this on sight in code, tests, or mocks. No exceptions.
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
**Recent Milestone:** Phase 10.4 WS-5 (Telemetry Map-Sync) COMPLETED ✅.
**Next Up:** Lote 5 (C4 Correction) & Infrastructure DB Sync.
