# Performance & Model Selection

## Agent Model Selection

**Haiku 4.5** (lightweight, high-frequency):
- Worker agents in multi-agent pipelines
- Simple code generation and formatting tasks
- Repetitive or templated operations

**Sonnet 4.6** (primary model — default for all dev work):
- Main development: Flutter, Riverpod, SQL migrations
- Orchestrating council persona workflows
- Complex feature implementation and debugging

**Opus 4.6** (deepest reasoning — use sparingly):
- `lead-reviewer` agent only (forensic PR audits, [GO]/[NO-GO] verdicts)
- Architectural decisions that affect Core/Module boundaries
- Security audits with RLS and financial verdict implications

## Context Window Management

Use `/compact` when:
- Context is approaching 70% full (visible in status bar)
- Starting a new independent task mid-session
- Switching from one module to another (e.g., domain → infrastructure)

Avoid large-scale work in last 20% of context:
- SQL migrations spanning multiple tables
- Refactors across `lib/domain/` and `lib/infrastructure/`
- Debugging cross-layer issues (engine → ledger → UI)

Low context-sensitivity tasks (safe near limit):
- Single-file widget edits
- Adding a new Riverpod provider
- Documentation updates
- Simple bug fixes in isolated files

## Supabase Free Tier Limits

Design every feature against these hard constraints:

| Resource | Limit | Mitigation |
|---|---|---|
| Concurrent DB connections | 60 | Use connection pooling; scope providers tightly |
| Realtime channels | Limited | Multiplex channels; avoid one-channel-per-record patterns |
| Edge Function invocations | 500K/month | Reserve for ingestion and verdict computation only |
| Storage | 1 GB | Use SHA-256 hashes as evidence references, not raw files |

- Riverpod providers MUST be scoped to the correct lifecycle — avoid global state for tenant-specific data
- If an SLA calculation becomes computationally expensive, propose denormalization via Read Model snapshots
- The verdict latency window (ingestion → Ledger entry) must remain optimized — the Judge cannot be slow

## Build & Compilation

WASM is the production build target:
- Zero `dart:html` or `dart:js` imports — use `dart:js_interop` and `package:web`
- Run `flutter build web --wasm` to validate before any PR

If build fails:
1. Check for `dart:html`/`dart:js` imports (automatic [NO-GO])
2. Verify all `Freezed` generated files are up to date (`dart run build_runner build`)
3. Fix incrementally — one error at a time
4. Re-run full build before marking resolved
