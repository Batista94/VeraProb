# SOP — Reason-Code Curation (Item 5.5)

**Status:** Active · **Owner:** Product (reason-code catalogue steward) ·
**Cadence:** Monthly · **Backlog item:** `REASON-CODE-CURATION` (recurring)

## Why this exists

The dispute reason-code catalogue (`public.dispute_reason_codes`) is a **closed,
global, industry-agnostic** taxonomy — clients cannot create codes in v1 (no
INSERT policy by design). Anything that does not fit a structured code lands in
the `OTHER` bucket as free text on `sanction_review_queue.rejection_reason`.
Left unattended, that bucket grows into untracked support debt: analytics cannot
answer "why are fines being inhibited?" and auditors face inconsistent prose.

Curation is the **feeder process** that keeps the closed catalogue alive: review
recurring `OTHER` text and promote it to a new global code via migration.

## Inputs

`public.v_reason_code_curation_candidates` — free text written under any
`OTHER`-**category** code (`OTHER`, `LEGACY_UNCLASSIFIED`, and any future
OTHER-bucket code), normalized (`lower(btrim())`) and ranked by
`occurrence_count`, with `first_seen_utc` / `last_seen_utc`.

| Surface | Scope |
|---------|-------|
| Tenant admin/auditor (`authenticated`) | own org's backlog only (inherited RLS) |
| Product owner (cross-org promotion) | full aggregate, run under `service_role` |

## Monthly process

1. **Pull the feed** (Product, under `service_role`):

   ```sql
   SELECT reason_code, normalized_text, sum(occurrence_count) AS total,
          min(first_seen_utc) AS first_seen, max(last_seen_utc) AS last_seen
   FROM public.v_reason_code_curation_candidates
   GROUP BY reason_code, normalized_text
   ORDER BY total DESC;
   ```

2. **Triage.** A candidate qualifies for promotion when it is recurring
   (≥ threshold, default **5** occurrences across ≥ 2 orgs) AND industry-agnostic
   (the *concept* survives a vertical change — transport wording stays in
   `label_pt` / `label_en`, never in `code`; B6).

3. **Assign category** from the fixed set: `OPERATIONAL`, `TECHNICAL`,
   `CONTRACTUAL`, `ENVIRONMENTAL`, `REGULATORY`, `OTHER`.

4. **Promote** — add the global code via an append-only migration (never edit a
   merged one), seeded exactly like the existing catalogue:

   ```sql
   INSERT INTO public.dispute_reason_codes
     (code, category, label_pt, label_en, applies_to, is_custom) VALUES
     ('NEW_AGNOSTIC_CODE', 'OPERATIONAL', '<pt>', '<en>', 'ALL', FALSE)
   ON CONFLICT (code, organization_id) DO NOTHING;
   ```

   Ship with its 1:1 test plan + pgTAP and regenerated `types.database.ts`, run
   the scanner, route through Council. Existing `OTHER` rows are **not**
   rewritten (append-only ledger discipline, INV-3) — the new code applies
   going forward; historical text stays auditable in place.

5. **Record the decision.** Append a row to the log below (promoted or rejected,
   with reason). This is the audit trail of catalogue evolution.

## Guardrails

- **No client-side codes.** Promotion is migration-only, Council-gated. Any
  future custom-code phase MUST force `organization_id IS NOT NULL` in its INSERT
  policy or org codes bleed globally (INV-22).
- **No retro-rewrite.** Never bulk-`UPDATE` `OTHER` rows to a new code — it
  mutates forensic history. Promote forward only (INV-3).
- **Agnostic codes only.** `code` is transport-neutral; vertical wording lives in
  labels (B6). Reject candidates that only make sense for one industry.

## Promotion log

| Date (UTC) | Candidate text (normalized) | Decision | New code / reason |
|-----------|------------------------------|----------|-------------------|
| _seed_ | — | — | _no promotions yet; first review pending_ |
