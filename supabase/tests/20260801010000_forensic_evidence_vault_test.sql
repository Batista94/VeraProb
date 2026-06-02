-- =============================================================================
-- pgTAP Test: Forensic Evidence Vault
-- Migration: 20260801010000_forensic_evidence_vault.sql
-- Spec: .kiro/specs/forensic-evidence-snapshot/requirements.md (Req 1-13)
-- =============================================================================
-- Validates: function existence + security mode, grants (read-only tenants),
--   atomic seal, idempotency, immutability (UPDATE/DELETE), missing-rule reject,
--   orphan FK guard, hash verification, and cross-tenant isolation (seal + read).
--
-- Trusted write paths run as postgres (RLS bypass; auth.jwt() NULL -> the
-- in-RPC tenant guard permits the backend path). Cross-tenant cases run under
-- the authenticated role with a crafted request.jwt.claims org.
-- =============================================================================

BEGIN;
SELECT plan(34);

-- ── Seed tenants ──────────────────────────────────────────────────────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-0000000000a1', 'Org FEV A', 'Org FEV A SA', '00000000000434',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'fev-a@a.com', 'EXT_FEV_A', 'LOGISTICS', ARRAY['fev-a.com']),
  ('00000000-0000-0000-0000-0000000000a2', 'Org FEV B', 'Org FEV B SA', '00000000000515',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'fev-b@b.com', 'EXT_FEV_B', 'TRANSPORT', ARRAY['fev-b.com'])
ON CONFLICT (id) DO NOTHING;

-- ── Seed active SLA rule for contract aa (Org A) ─────────────────────────────
INSERT INTO public.contract_rule_sets (id, organization_id, contract_id)
VALUES ('00000000-0000-0000-0000-0000000000c1',
        '00000000-0000-0000-0000-0000000000a1',
        '00000000-0000-0000-0000-0000000000aa');

INSERT INTO public.contract_rule_versions
  (id, rule_set_id, rule_type, rule_config, rule_version, evaluation_order,
   active_from_utc, active_to_utc)
VALUES
  ('00000000-0000-0000-0000-0000000000d1',
   '00000000-0000-0000-0000-0000000000c1',
   'NO_SHOW_PENALTY', '{"penalty_amount_cents": 50000}'::jsonb, 2, 0,
   '2026-01-01T00:00:00Z', NULL);

-- ── 1-2. Function existence ──────────────────────────────────────────────────
SELECT has_function('public', 'seal_forensic_evidence',
  ARRAY['uuid','uuid','text','text','integer','timestamp with time zone','uuid','text'],
  '1: seal_forensic_evidence exists');
SELECT has_function('public', 'verify_forensic_evidence',
  ARRAY['uuid','uuid'], '2: verify_forensic_evidence exists');

-- ── 3-4. Security mode ───────────────────────────────────────────────────────
SELECT is(
  (SELECT prosecdef FROM pg_proc WHERE proname = 'seal_forensic_evidence'),
  true, '3/Req5: seal RPC is SECURITY DEFINER (Backend Authority)');
SELECT is(
  (SELECT prosecdef FROM pg_proc WHERE proname = 'verify_forensic_evidence'),
  false, '4/INV-2: verify RPC is SECURITY INVOKER (RLS-scoped)');

-- ── 5-8. Grants: authenticated = read-only ───────────────────────────────────
SELECT ok(
  has_table_privilege('authenticated', 'public.forensic_evidence_snapshots', 'SELECT'),
  '5/INV-DATA-API-GRANT: authenticated may SELECT');
SELECT ok(
  NOT has_table_privilege('authenticated', 'public.forensic_evidence_snapshots', 'INSERT'),
  '6/Req5: authenticated may NOT INSERT (RPC-only write path)');
SELECT ok(
  NOT has_table_privilege('authenticated', 'public.forensic_evidence_snapshots', 'UPDATE'),
  '7/INV-3: authenticated may NOT UPDATE');
SELECT ok(
  NOT has_table_privilege('authenticated', 'public.forensic_evidence_snapshots', 'DELETE'),
  '8/INV-3: authenticated may NOT DELETE');

-- ── 9-10. EXECUTE grants ─────────────────────────────────────────────────────
SELECT ok(
  has_function_privilege('authenticated',
    'public.seal_forensic_evidence(uuid, uuid, text, text, integer, timestamp with time zone, uuid, text)',
    'EXECUTE'),
  '9: authenticated may EXECUTE seal_forensic_evidence');
SELECT ok(
  has_function_privilege('authenticated',
    'public.verify_forensic_evidence(uuid, uuid)', 'EXECUTE'),
  '10: authenticated may EXECUTE verify_forensic_evidence');

-- ── 11-13. Happy-path seal ───────────────────────────────────────────────────
CREATE TEMP TABLE seal_out AS
SELECT public.seal_forensic_evidence(
  '00000000-0000-0000-0000-0000000000a1',
  '00000000-0000-0000-0000-0000000000aa',
  'set-1', 'NO_SHOW_PENALTY', 1, '2026-08-01T12:00:00Z',
  '00000000-0000-0000-0000-0000000000f1', 'idem-1'
) AS j;

SELECT is(
  length((SELECT j->>'integrity_hash' FROM seal_out)),
  64, '11/INV-9: integrity_hash is 64-hex SHA-256');

SELECT is(
  (SELECT count(*)::int FROM public.forensic_evidence_snapshots
   WHERE organization_id = '00000000-0000-0000-0000-0000000000a1'),
  1, '12: exactly one snapshot persisted');

SELECT is(
  (SELECT count(*)::int FROM public.sla_audit_ledger_v2
   WHERE contract_id = '00000000-0000-0000-0000-0000000000aa'
     AND type = 'NO_SHOW_PENALTY'),
  1, '13/INV-21: exactly one verdict ledger entry appended');

-- ── 14-16. Idempotency (same key) ────────────────────────────────────────────
CREATE TEMP TABLE seal_out2 AS
SELECT public.seal_forensic_evidence(
  '00000000-0000-0000-0000-0000000000a1',
  '00000000-0000-0000-0000-0000000000aa',
  'set-1', 'NO_SHOW_PENALTY', 1, '2026-08-01T12:00:00Z',
  '00000000-0000-0000-0000-0000000000f1', 'idem-1'
) AS j;

SELECT is(
  (SELECT j->>'id' FROM seal_out2),
  (SELECT j->>'id' FROM seal_out),
  '14/INV-11: replay returns the same snapshot id');
SELECT is(
  (SELECT count(*)::int FROM public.forensic_evidence_snapshots
   WHERE organization_id = '00000000-0000-0000-0000-0000000000a1'),
  1, '15/Req10.4: still exactly one snapshot');
SELECT is(
  (SELECT count(*)::int FROM public.sla_audit_ledger_v2
   WHERE contract_id = '00000000-0000-0000-0000-0000000000aa'
     AND type = 'NO_SHOW_PENALTY'),
  1, '16: replay appended NO second verdict');

-- ── 17-18. Immutability (Req 3, 9) ───────────────────────────────────────────
SELECT throws_ok(
  $$ UPDATE public.forensic_evidence_snapshots
       SET sealed_by = gen_random_uuid() $$,
  '23001', NULL, '17/INV-3: UPDATE rejected (restrict_violation)');
SELECT throws_ok(
  $$ DELETE FROM public.forensic_evidence_snapshots $$,
  '23001', NULL, '18/INV-3: DELETE rejected (restrict_violation)');

-- ── 19. Missing active rule (Req 5.3) ────────────────────────────────────────
SELECT throws_ok(
  $$ SELECT public.seal_forensic_evidence(
       '00000000-0000-0000-0000-0000000000a1',
       '00000000-0000-0000-0000-0000000000bb',
       'set-2', 'NO_SHOW_PENALTY', 1, '2026-08-01T12:00:00Z',
       '00000000-0000-0000-0000-0000000000f1', 'idem-2') $$,
  'P0002', NULL, '19/Req5.3: seal with no active rule rejected');

-- ── 20. Orphan guard (Req 10.5) ──────────────────────────────────────────────
SELECT throws_ok(
  $$ INSERT INTO public.forensic_evidence_snapshots
       (organization_id, ledger_entry_id, contract_id, rule_set_id,
        sla_rule_version, snapshot, integrity_hash, idempotency_key, sealed_by)
     VALUES ('00000000-0000-0000-0000-0000000000a1', gen_random_uuid(),
        '00000000-0000-0000-0000-0000000000aa',
        '00000000-0000-0000-0000-0000000000c1', 1, '{}'::jsonb,
        'deadbeef', 'idem-orphan',
        '00000000-0000-0000-0000-0000000000f1') $$,
  '23503', NULL, '20/Req10.5: snapshot without a verdict rejected (FK)');

-- ── 21. Hash verification (Req 8) ────────────────────────────────────────────
SELECT is(
  (SELECT public.verify_forensic_evidence(
     '00000000-0000-0000-0000-0000000000a1',
     (SELECT (j->>'ledger_entry_id')::uuid FROM seal_out)) ->> 'status'),
  'authentic', '21/Req8: untouched snapshot verifies authentic');

-- ── 22. Cross-tenant seal (INV-1/INV-22) ─────────────────────────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000000a2"}}';

SELECT throws_ok(
  $$ SELECT public.seal_forensic_evidence(
       '00000000-0000-0000-0000-0000000000a1',
       '00000000-0000-0000-0000-0000000000aa',
       'set-1', 'NO_SHOW_PENALTY', 1, '2026-08-01T12:00:00Z',
       '00000000-0000-0000-0000-0000000000f1', 'idem-evil') $$,
  '42501', NULL, '22/INV-1+22: cross-tenant seal rejected');

-- ── 23. Cross-tenant read (INV-22, 404 parity) ───────────────────────────────
SELECT is(
  (SELECT count(*)::int FROM public.forensic_evidence_snapshots),
  0, '23/INV-22: Org B sees zero of Org A snapshots (RLS)');

RESET ROLE;
-- Clear the forged tenant claim from test 22 (RESET ROLE does not touch GUCs).
-- The trusted backend path below must present a NULL jwt org so the in-RPC
-- tenant guard permits seals for org a1.
RESET request.jwt.claims;

-- ── 24-25. Tamper detection (Req 2.5 / 8.5) ──────────────────────────────────
-- Insider/superuser bypass: the immutability trigger is administratively
-- disabled, the sealed snapshot is mutated in place, the trigger re-enabled.
-- verify_forensic_evidence MUST still expose the forgery by recomputing the
-- SHA-256 over the stored snapshot and finding it no longer matches the sealed
-- hash. This is the last line of defense when the BEFORE-trigger is circumvented.

ALTER TABLE public.forensic_evidence_snapshots DISABLE TRIGGER trg_fes_no_update;
UPDATE public.forensic_evidence_snapshots
   SET snapshot = jsonb_set(snapshot, '{rules}', '[]'::jsonb)
 WHERE organization_id = '00000000-0000-0000-0000-0000000000a1';
ALTER TABLE public.forensic_evidence_snapshots ENABLE TRIGGER trg_fes_no_update;

SELECT is(
  (SELECT public.verify_forensic_evidence(
     '00000000-0000-0000-0000-0000000000a1',
     (SELECT (j->>'ledger_entry_id')::uuid FROM seal_out)) ->> 'status'),
  'tampered', '24/Req8.5: post-hoc snapshot mutation detected as tampered');

SELECT isnt(
  (SELECT public.verify_forensic_evidence(
     '00000000-0000-0000-0000-0000000000a1',
     (SELECT (j->>'ledger_entry_id')::uuid FROM seal_out)) ->> 'computed_hash'),
  (SELECT public.verify_forensic_evidence(
     '00000000-0000-0000-0000-0000000000a1',
     (SELECT (j->>'ledger_entry_id')::uuid FROM seal_out)) ->> 'stored_hash'),
  '25/Req2.5: recomputed hash diverges from the sealed hash');

-- ── 26-29. Rule-window boundary (Req 5.3 / 12.2) ─────────────────────────────
-- A rule set EXISTS for contract cc, but its single version is only active over
-- the half-open interval [2026-03-01, 2026-06-01). The seal resolves the active
-- rule with `active_from_utc <= occurred AND (active_to_utc IS NULL OR > occurred)`.
-- These cases pin the exact inclusive/exclusive boundary semantics (off-by-one
-- on the verdict timestamp would silently freeze the wrong — or no — rule).

INSERT INTO public.contract_rule_sets (id, organization_id, contract_id)
VALUES ('00000000-0000-0000-0000-0000000000c2',
        '00000000-0000-0000-0000-0000000000a1',
        '00000000-0000-0000-0000-0000000000cc');

INSERT INTO public.contract_rule_versions
  (id, rule_set_id, rule_type, rule_config, rule_version, evaluation_order,
   active_from_utc, active_to_utc)
VALUES
  ('00000000-0000-0000-0000-0000000000d2',
   '00000000-0000-0000-0000-0000000000c2',
   'NO_SHOW_PENALTY', '{"penalty_amount_cents": 50000}'::jsonb, 1, 0,
   '2026-03-01T00:00:00Z', '2026-06-01T00:00:00Z');

-- 26. occurred == active_from -> inclusive -> seals.
SELECT lives_ok(
  $$ SELECT public.seal_forensic_evidence(
       '00000000-0000-0000-0000-0000000000a1',
       '00000000-0000-0000-0000-0000000000cc',
       'set-b', 'NO_SHOW_PENALTY', 1, '2026-03-01T00:00:00Z',
       '00000000-0000-0000-0000-0000000000f1', 'idem-b-from') $$,
  '26/Req12.2: occurred == active_from is inclusive (rule active)');

-- 27. occurred just before active_from -> excluded -> no active rule.
SELECT throws_ok(
  $$ SELECT public.seal_forensic_evidence(
       '00000000-0000-0000-0000-0000000000a1',
       '00000000-0000-0000-0000-0000000000cc',
       'set-b', 'NO_SHOW_PENALTY', 1, '2026-02-28T23:59:59Z',
       '00000000-0000-0000-0000-0000000000f1', 'idem-b-before') $$,
  'P0002', NULL, '27/Req5.3: occurred < active_from rejected (no active rule)');

-- 28. occurred just before active_to -> still inside the window -> seals.
SELECT lives_ok(
  $$ SELECT public.seal_forensic_evidence(
       '00000000-0000-0000-0000-0000000000a1',
       '00000000-0000-0000-0000-0000000000cc',
       'set-b', 'NO_SHOW_PENALTY', 1, '2026-05-31T23:59:59Z',
       '00000000-0000-0000-0000-0000000000f1', 'idem-b-in') $$,
  '28/Req12.2: occurred < active_to is inside the window (rule active)');

-- 29. occurred == active_to -> exclusive upper bound -> no active rule.
SELECT throws_ok(
  $$ SELECT public.seal_forensic_evidence(
       '00000000-0000-0000-0000-0000000000a1',
       '00000000-0000-0000-0000-0000000000cc',
       'set-b', 'NO_SHOW_PENALTY', 1, '2026-06-01T00:00:00Z',
       '00000000-0000-0000-0000-0000000000f1', 'idem-b-at-to') $$,
  'P0002', NULL, '29/Req12.2: occurred == active_to rejected (exclusive bound)');

-- 30. Canonical serializer sorts object keys lexicographically + strips whitespace
--     (JCS / Req 11). This is what makes the hash reproducible outside Postgres.
SELECT is(
  public.jsonb_canonical_text('{ "b": 2, "a": 1, "c": 3 }'::jsonb),
  '{"a":1,"b":2,"c":3}',
  '30/Req11: jsonb_canonical_text orders keys + drops whitespace');

-- 31. Recurses into nested objects and array elements (string scalars stay quoted).
SELECT is(
  public.jsonb_canonical_text('{"z":[{"y":1,"x":2}],"a":"v"}'::jsonb),
  '{"a":"v","z":[{"x":2,"y":1}]}',
  '31/Req11/INV-15: canonical form recurses into arrays + nested objects');

-- ── 32-34. SQL injection red-team (defense-in-depth) ─────────────────────────
-- The free-text params (p_set_id, p_verdict_type) are BOUND parameters, never
-- concatenated into a SQL string and never run through EXECUTE. A classic
-- injection payload must therefore land as INERT literal data, not execute. Were
-- the RPC building SQL by string interpolation, the embedded DROP would fire and
-- the vault table would vanish. This pins the structural defense with an
-- adversarial input rather than trusting it by inspection.

CREATE TEMP TABLE seal_inj AS
SELECT public.seal_forensic_evidence(
  '00000000-0000-0000-0000-0000000000a1',
  '00000000-0000-0000-0000-0000000000aa',
  'set-x''; DROP TABLE public.forensic_evidence_snapshots; --',
  'NO_SHOW_PENALTY', 1, '2026-08-01T12:00:00Z',
  '00000000-0000-0000-0000-0000000000f1', 'idem-sqli'
) AS j;

SELECT ok(
  (SELECT j IS NOT NULL FROM seal_inj),
  '32/SQLi: injection payload in p_set_id seals normally (bound param, not SQL)');

SELECT has_table(
  'public', 'forensic_evidence_snapshots',
  '33/SQLi: embedded DROP did NOT execute — vault table survives');

SELECT is(
  (SELECT j -> 'snapshot' ->> 'set_id' FROM seal_inj),
  'set-x''; DROP TABLE public.forensic_evidence_snapshots; --',
  '34/SQLi: payload stored verbatim as inert data (no interpretation)');

SELECT * FROM finish();
ROLLBACK;
