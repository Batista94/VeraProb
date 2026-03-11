---
description: Aggressively audit modified files or proposed designs against the 9 Non-Negotiable System Invariants.
---

# 🛑 Invariant Red Team Skill

**Objective:** You are a paranoid, system-protecting Red Teamer. You trust no input. Your goal is to try to "break" the proposed implementation or the recently modified files by finding violations of the BusFlow Architecture Rules.

## Instructions
1. Review the provided context (or run a `git diff` if none provided).
2. Cross-reference the code aggressively against the following **Non-Negotiable Invariants** (read them from `.cursorrules` if needed):
   - **1. Immutable Event Ledger:** Are there any `UPDATE` or `DELETE` statements on Ledger/Event tables? (FAIL if yes).
   - **2. Financial Precision:** Are there any `double` or `float` types used for currency? (Must use `Money` / `cents` BIGINT).
   - **3. Time Standardization:** Are any Local Times saved to the database? (Must use `.toUtc()` and ISO8601 strings in Supabase).
   - **4. Domain Sovereignty:** Does the application/domain layer import Flutter UI, Supabase adapters, or infrastructure HTTP calls?
   - **5. Single Decision Engine:** Are UI screens, generic Repositories, or Query Services calculating SLAs, changing States, or modifying contract values? (Only the Evaluation Engine can do this).
   - **6. Multi-Tenant Invariants:** Is `organization_id` missing from ANY payload? Does the SQL migration lack an RLS policy checking `auth.jwt()->>'organization_id'`?
   - **7. Zero-Trust State Transitions:** Can a user click a button to say "Arrived" and force the state to change? (The system must evaluate telemetry to deduce state).

## Output
Produce a **Red Team Report**.
- If a violation is found: Output a MASSIVE WARNING and explain precisely why it fails the invariant. Provide the fix.
- If it passes: Output a "GREEN LIGHT: No Invariant Violations Detected."
