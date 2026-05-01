# Council Protocol (VeraProb)
Collective Consciousness logic.

## 1. CONTEXT HIERARCHY
1. PERSONAS (.claude/agents/): Base logic & tone.
2. MANIFESTOS (.kiro/agents/): Active mission config.
3. DOGMA (Memory Server): Invariants INV-1 to INV-28.

## 2. CONSENSUS FLOW
Local work unrestricted. **Triple Verdict** mandatory for:
1. Merge to **main** / PR open.
2. Domain/Infra task finalization.
3. Fast-Track: UI/Doc skip Council (Scanner recommended).

**VERDICT CRITERIA:**
1.  **Deterministic Pass**: Sucesso no `scripts/security/pr_full_scanner.sh`.
2. Neural: `Lead Reviewer` approval (Invariants).
3. Security: `QA/Security` sign-off (RLS/Isolation).

## 3. ORCHESTRATION
Categorized `scripts/`: `dev/`, `security/`, `qa/`.
Master: `Makefile`.
- `make setup`: Environment build.
- `make check`: Security/Audit gate.

## 4. MISSION STATE
`specs/` is source of truth. Task must exist in `tasks.md`.
