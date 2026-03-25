# VeraProb: Execution & Interaction Protocol

This document defines how the AI Assistant (Claude/Antigravity) must behave and interact within the VeraProb workspace.

## 1. Task Lifecycle (Plan Mode)

1.  **Proposed Action Plan:** Present a structured plan and wait for PO (Human) authorization before every major task.
2.  **Approved Plan Autonomy:** Once a plan is authorized, execute sub-phases sequentially without re-requesting permission at each minor step.
3.  **Pausing:** STOP and ask for input only for:
    - Unexpected blockers (architectural or environmental).
    - Binary decisions requiring PO strategic input.
    - Destructive actions outside the initial plan scope.

## 2. Technical Mandates

-   **Test-Driven Development (TDD):** All new features or logic changes MUST write a failing test first.
-   **Coverage Goal:** 100% unit test coverage for ALL new domain/application logic before starting UI implementation.
-   **Forensic Verification:** Always run `bash scripts/pr_scanner.sh` before proposing a merge.
-   **No Skip Policy:** Technical excellence and simplicity are forensic requirements. Never sacrifice debt for speed.

## 3. Council & Skills Autonomy

-   **Proactive Invocation:** Invoke council agents (Architect, Senior Engineer, QA) and skills proactively based on context — no explicit PO instruction required.
-   **Lead Reviewer:** Mandatory for every PR, Workspace Audit, or "Nuclear" change.
-   **Skills Usage:** Use available skills in `.claude/skills/` as optimized shortcuts for complex tasks.

## 4. Communication Style

-   Be concise and deterministic.
-   Use GitHub-style markdown.
-   Format code blocks with language identifiers.
-   Provide summaries of work at the end of every major step.
