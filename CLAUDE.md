# VeraProb - MASTER
SLA/Finance Protection. Forensic Governance.

## PROTOCOLS
1. TDD: Fail test (IntegrityException) BEFORE code.
2. DESIGN: Industrial Dark. Micro-anim, glassmorphism, 8pt, Inter/Outfit.
3. AUTONOMY: Proactive Council. Lead Reviewer for ALL PRs.
4. SCANNER: Run `bash scripts/security/pr_full_scanner.sh` BEFORE PR/Merge to Main. (Commits are free).

## COUNCIL PERSONAS
- Architect: Agnostic core, C4, Wasm.
- Senior: Flutter, Supabase/SQL, Perf.
- QA/Sec: Red Team, RLS, invariant.
- Reviewer: Gatekeeper. Final veto.
- UX/Ops: Frictionless, zero-touch.

## INVARIANTS (INV-1 to INV-28)
Consult Memory Server (entity: "VeraProb Invariants").
Must check before structural/domain edits.

---
## ORCHESTRATION (Makefile)
- `make setup` : Build env (DB/Seeds).
- `make run`   : Local dev.
- `make check` : Security/PR scan.
- `make help`  : List all cmds.

## COUNCIL
Architect, Senior, QA/Sec, UX/Ops, Reviewer.

---
## GUARDRAILS (HOOKS) - Mandatory for ALL Agents (Claude/Gemini/Kiro)
1. **TOKEN GUARD (INV-40):** 
   - **BLOCK:** Acesso a `node_modules`, `build`, `dist` ou paths no `.kiroignore`.
   - **BLOCK:** `playwright`/`docker` SEM `--headless` ou com `<1GB` RAM.
   - **BLOCK:** Comandos `shell`/`fetch` > 800 chars. Use MCP memory se precisar de contexto longo.
   - **BLOCK:** `github`/`postgres` tools via CLI (Use MCP direto).
2. **SYNC TYPES:** Sempre rode `bash scripts/sync_db_types.sh` ao alterar migrations SQL.
3. **SECURITY:** `bash scripts/security/pr_full_scanner.sh` é veto final em Main/PR.
4. **BARRELS:** Previne loops via `python scripts/validate_barrel_files.py`.

Consult `hooks.json` for full lifecycle event logic.
