-- =============================================================================
-- VeraProb — Forensic Evidence Snapshot Vault
-- Spec: .kiro/specs/forensic-evidence-snapshot/requirements.md (Req 1-13)
-- =============================================================================
-- PURPOSE:
--   At verdict-seal time, freeze the ACTIVE SLA rule and cryptographically
--   attach it to the infraction so a future contract renegotiation can never
--   alter a historical verdict. Carrier contests a penalty months later -> the
--   vault mathematically proves which exact rule was in force.
--
-- BACKEND AUTHORITY (Req 5): public.seal_forensic_evidence() is the SOLE write
--   path. It IGNORES any client-supplied rule content and retrieves the active
--   SLA rule directly from contract_rule_sets / contract_rule_versions. Verdict
--   ledger append + snapshot + SHA-256 are committed in ONE transaction (Req 10).
--
-- IMMUTABILITY (Req 3, 9): BEFORE UPDATE/DELETE triggers reject all mutation
--   regardless of role (REVOKE alone does not stop service_role). Hard-block
--   rejection logging relies on the Postgres server log / pgAudit — a BEFORE
--   trigger that RAISEs aborts the txn and cannot persist an audit row in an
--   app table. Documented in the matching forensic test plan.
--
-- INVARIANTS: INV-1 (org filter), INV-2 (JWT RLS), INV-3 (append-only),
--   INV-6 (TIMESTAMPTZ), INV-9 (SHA-256 sealing), INV-15 (deterministic),
--   INV-21 (verdict -> snapshot id), INV-22 (tenant isolation),
--   INV-26 (404 parity via RLS), INV-DATA-API-GRANT.
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── 1. Vault Table ───────────────────────────────────────────────────────────
-- FK is composite (organization_id, ledger_entry_id) -> the partitioned ledger's
-- PK (organization_id, id). This both prevents orphaned snapshots (Req 10.5) and
-- binds every snapshot to its tenant. The ledger is append-only, so the verdict
-- it references can never be mutated either.

CREATE TABLE IF NOT EXISTS public.forensic_evidence_snapshots (
  id                 UUID        NOT NULL DEFAULT gen_random_uuid(),
  organization_id    UUID        NOT NULL REFERENCES public.organizations(id),
  ledger_entry_id    UUID        NOT NULL,                 -- the sealed verdict (Req 7.1)
  contract_id        UUID        NOT NULL,
  rule_set_id        UUID        NOT NULL,
  sla_rule_version   INT         NOT NULL,                 -- Req 7.3
  effective_from_utc TIMESTAMPTZ,                          -- Req 7.3 / 12.2
  effective_to_utc   TIMESTAMPTZ,
  snapshot           JSONB       NOT NULL,                 -- complete rule definition (Req 1.3, 12)
  schema_version     INT         NOT NULL DEFAULT 1,       -- forward-compat seam (Req 14.1)
  integrity_hash     TEXT        NOT NULL,                 -- SHA-256 hex of snapshot::text (Req 2)
  idempotency_key    TEXT        NOT NULL,                 -- replay safety (Req 6 / INV-11)
  sealed_by          UUID        NOT NULL,                 -- operator (Req 7.2)
  sealed_at_utc      TIMESTAMPTZ NOT NULL DEFAULT now(),   -- server-clock provenance (Req 7.4, INV-6)
  PRIMARY KEY (organization_id, id),
  CONSTRAINT fk_fes_ledger_entry
    FOREIGN KEY (organization_id, ledger_entry_id)
    REFERENCES public.sla_audit_ledger_v2 (organization_id, id),
  CONSTRAINT uq_fes_one_per_verdict
    UNIQUE (organization_id, ledger_entry_id),            -- Req 10.4: one snapshot per verdict
  CONSTRAINT uq_fes_idempotency
    UNIQUE (organization_id, idempotency_key)             -- INV-11: replay returns existing
);

COMMENT ON TABLE public.forensic_evidence_snapshots IS
  'Forensic Evidence Vault. Append-only, immutable cryptographic snapshot of the '
  'active SLA rule at verdict-seal time. Written exclusively by '
  'public.seal_forensic_evidence(). INV-3 immutable, INV-9 sealed, INV-22 isolated.';

-- ── 2. Indexes (Req 6.3, 7.5) ────────────────────────────────────────────────
-- (organization_id, ledger_entry_id) and (organization_id, idempotency_key) are
-- already backed by the UNIQUE constraints above. PK supplies the org prefix.

CREATE INDEX IF NOT EXISTS idx_fes_org_contract
  ON public.forensic_evidence_snapshots (organization_id, contract_id);

CREATE INDEX IF NOT EXISTS idx_fes_org_sealed_at
  ON public.forensic_evidence_snapshots (organization_id, sealed_at_utc DESC);

-- ── 3. RLS (INV-2, INV-22, Req 4) ────────────────────────────────────────────
-- Read-only for tenants, scoped to their own org via the JWT app_metadata.org_id
-- claim (the path the custom_access_token_hook actually populates). 404-parity
-- (Req 4.3) follows: a cross-tenant lookup returns zero rows, which the repository
-- maps to ResourceNotFoundException (INV-26). NO insert/update/delete policy is
-- defined — the only write path is the SECURITY DEFINER RPC (Backend Authority).

ALTER TABLE public.forensic_evidence_snapshots ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Tenant Isolation: Read Evidence Vault"
  ON public.forensic_evidence_snapshots;
CREATE POLICY "Tenant Isolation: Read Evidence Vault"
  ON public.forensic_evidence_snapshots
  FOR SELECT
  TO authenticated
  USING (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

-- ── 4. Immutability (INV-3, Req 3, Req 9) ────────────────────────────────────

CREATE OR REPLACE FUNCTION public.prevent_evidence_vault_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION
    'forensic_evidence_snapshots is immutable (INV-3, Req 3/9). Operation: %, id: %',
    TG_OP,
    OLD.id
  USING ERRCODE = 'restrict_violation';
END;
$$;

DROP TRIGGER IF EXISTS trg_fes_no_update ON public.forensic_evidence_snapshots;
CREATE TRIGGER trg_fes_no_update
  BEFORE UPDATE ON public.forensic_evidence_snapshots
  FOR EACH ROW EXECUTE FUNCTION public.prevent_evidence_vault_mutation();

DROP TRIGGER IF EXISTS trg_fes_no_delete ON public.forensic_evidence_snapshots;
CREATE TRIGGER trg_fes_no_delete
  BEFORE DELETE ON public.forensic_evidence_snapshots
  FOR EACH ROW EXECUTE FUNCTION public.prevent_evidence_vault_mutation();

-- ── 5. Atomic Sealing RPC (Backend Authority — Req 5, 10, 13) ─────────────────
-- SECURITY DEFINER: the seal must atomically append the verdict ledger entry and
-- write the snapshot across the immutable vault in one txn. Tenant isolation on
-- this write path is enforced by the explicit in-function JWT guard below (RLS is
-- bypassed by DEFINER), mirroring seal_forensic_record(). search_path is pinned to
-- defeat search_path manipulation.

CREATE OR REPLACE FUNCTION public.seal_forensic_evidence(
  p_organization_id  UUID,
  p_contract_id      UUID,
  p_set_id           TEXT,
  p_verdict_type     TEXT,
  p_plan_version     INT,
  p_occurred_at_utc  TIMESTAMPTZ,
  p_sealed_by        UUID,
  p_idempotency_key  TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_jwt_org     TEXT;
  v_rule_set_id UUID;
  v_rules       JSONB;
  v_max_version INT;
  v_eff_from    TIMESTAMPTZ;
  v_eff_to      TIMESTAMPTZ;
  v_snapshot    JSONB;
  v_hash        TEXT;
  v_ledger_id   UUID;
  v_existing    public.forensic_evidence_snapshots;
  v_row         public.forensic_evidence_snapshots;
BEGIN
  -- 5a. Tenant guard (Req 4.4, INV-1 fail-fast). Authenticated callers cannot
  --     seal for another org; the trusted backend path (service_role, NULL jwt)
  --     is permitted.
  v_jwt_org := auth.jwt() -> 'app_metadata' ->> 'org_id';
  IF v_jwt_org IS NOT NULL AND v_jwt_org::uuid <> p_organization_id THEN
    RAISE EXCEPTION 'Cross-tenant seal rejected (INV-1/INV-22)'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- 5b. Idempotency short-circuit (Req 6, INV-11): replay returns the existing
  --     snapshot WITHOUT appending a second ledger entry.
  SELECT * INTO v_existing
    FROM public.forensic_evidence_snapshots
   WHERE organization_id = p_organization_id
     AND idempotency_key = p_idempotency_key;
  IF FOUND THEN
    RETURN to_jsonb(v_existing);
  END IF;

  -- 5c. Backend Authority (Req 5.1/5.2): resolve the rule set from the DB only.
  SELECT id INTO v_rule_set_id
    FROM public.contract_rule_sets
   WHERE organization_id = p_organization_id
     AND contract_id = p_contract_id::text
   LIMIT 1;
  IF v_rule_set_id IS NULL THEN
    RAISE EXCEPTION 'No rule set for contract % (Req 5.3)', p_contract_id
      USING ERRCODE = 'P0002';
  END IF;

  -- 5d. Freeze the rule versions active at the verdict timestamp, ordered
  --     deterministically (INV-15). jsonb_agg(... ORDER BY ...) is stable.
  SELECT
    jsonb_agg(
      jsonb_build_object(
        'rule_id',          rv.id,
        'rule_type',        rv.rule_type,
        'rule_config',      rv.rule_config,
        'rule_version',     rv.rule_version,
        'evaluation_order', rv.evaluation_order,
        'active_from_utc',  rv.active_from_utc,
        'active_to_utc',    rv.active_to_utc
      ) ORDER BY rv.evaluation_order
    ),
    max(rv.rule_version),
    min(rv.active_from_utc),
    max(rv.active_to_utc)
  INTO v_rules, v_max_version, v_eff_from, v_eff_to
  FROM public.contract_rule_versions rv
  WHERE rv.rule_set_id = v_rule_set_id
    AND rv.active_from_utc <= p_occurred_at_utc
    AND (rv.active_to_utc IS NULL OR rv.active_to_utc > p_occurred_at_utc);

  IF v_rules IS NULL THEN
    RAISE EXCEPTION 'No active SLA rule for contract % at % (Req 5.3, 13.1)',
      p_contract_id, p_occurred_at_utc
      USING ERRCODE = 'P0002';
  END IF;

  -- 5e. Append the verdict ledger entry (the seal). Captured id binds the snapshot.
  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id, plan_version,
     payload, occurred_at_utc)
  VALUES
    (p_organization_id, p_verdict_type, p_sealed_by::text, p_set_id, p_contract_id,
     p_plan_version,
     jsonb_build_object('forensic_seal', true, 'idempotency_key', p_idempotency_key),
     p_occurred_at_utc)
  RETURNING id INTO v_ledger_id;

  -- 5f. Canonical, self-contained snapshot (Req 11, 12). jsonb::text is the
  --     documented canonical serialization: byte-identical for identical content.
  v_snapshot := jsonb_build_object(
    'schema_version',     1,
    'organization_id',    p_organization_id,
    'contract_id',        p_contract_id,
    'rule_set_id',        v_rule_set_id,
    'sla_rule_version',   v_max_version,
    'effective_from_utc', v_eff_from,
    'effective_to_utc',   v_eff_to,
    'verdict_type',       p_verdict_type,
    'set_id',             p_set_id,
    'plan_version',       p_plan_version,
    'occurred_at_utc',    p_occurred_at_utc,
    'ledger_entry_id',    v_ledger_id,
    'rules',              v_rules
  );

  -- 5g. Integrity hash (Req 2.2, INV-9).
  v_hash := encode(extensions.digest(v_snapshot::text, 'sha256'), 'hex');

  -- 5h. Persist into the vault (same txn -> rolls back with the ledger on failure).
  INSERT INTO public.forensic_evidence_snapshots
    (organization_id, ledger_entry_id, contract_id, rule_set_id, sla_rule_version,
     effective_from_utc, effective_to_utc, snapshot, schema_version, integrity_hash,
     idempotency_key, sealed_by)
  VALUES
    (p_organization_id, v_ledger_id, p_contract_id, v_rule_set_id, v_max_version,
     v_eff_from, v_eff_to, v_snapshot, 1, v_hash,
     p_idempotency_key, p_sealed_by)
  RETURNING * INTO v_row;

  RETURN to_jsonb(v_row);

EXCEPTION
  WHEN unique_violation THEN
    -- Concurrent seal with the same idempotency key won the race and committed.
    -- The exception rolled back our ledger append (one block = one savepoint),
    -- so no orphan verdict is left behind. Return the persisted snapshot.
    SELECT * INTO v_existing
      FROM public.forensic_evidence_snapshots
     WHERE organization_id = p_organization_id
       AND idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN to_jsonb(v_existing);
    END IF;
    RAISE;
END;
$$;

COMMENT ON FUNCTION public.seal_forensic_evidence(
  UUID, UUID, TEXT, TEXT, INT, TIMESTAMPTZ, UUID, TEXT) IS
  'Backend Authority for the Forensic Evidence Vault. Atomically appends the '
  'verdict ledger entry, freezes the DB-resolved active SLA rule, computes the '
  'SHA-256 integrity hash and persists the snapshot in one transaction. '
  'Idempotent on (organization_id, idempotency_key). Req 5/10, INV-9/INV-15.';

-- ── 6. On-Read Verification RPC (Req 2.4/2.5, 8.2-8.5) ───────────────────────
-- DB is the canonical authority for the hash. Recomputes over the stored snapshot
-- and compares. SECURITY INVOKER so RLS scopes the lookup to the caller's tenant
-- (404-parity for cross-tenant / unknown verdicts -> empty result, Req 8.6).

CREATE OR REPLACE FUNCTION public.verify_forensic_evidence(
  p_organization_id UUID,
  p_ledger_entry_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions
AS $$
DECLARE
  v_row      public.forensic_evidence_snapshots;
  v_computed TEXT;
BEGIN
  SELECT * INTO v_row
    FROM public.forensic_evidence_snapshots
   WHERE organization_id = p_organization_id
     AND ledger_entry_id = p_ledger_entry_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Snapshot not found for verdict % (Req 8/INV-26)', p_ledger_entry_id
      USING ERRCODE = 'P0002';
  END IF;

  v_computed := encode(extensions.digest(v_row.snapshot::text, 'sha256'), 'hex');

  RETURN jsonb_build_object(
    'ledger_entry_id', v_row.ledger_entry_id,
    'stored_hash',     v_row.integrity_hash,
    'computed_hash',   v_computed,
    'status',          CASE WHEN v_computed = v_row.integrity_hash
                            THEN 'authentic' ELSE 'tampered' END,
    'snapshot',        v_row.snapshot
  );
END;
$$;

COMMENT ON FUNCTION public.verify_forensic_evidence(UUID, UUID) IS
  'On-read integrity verification. Recomputes SHA-256 over the stored snapshot '
  'and compares to integrity_hash. Returns status authentic|tampered. '
  'SECURITY INVOKER -> RLS-scoped to the caller tenant (Req 8, INV-26).';

-- ── 7. Data API Grants (INV-DATA-API-GRANT) ──────────────────────────────────
-- Authenticated tenants may only READ the vault; the sole write path is the
-- SECURITY DEFINER seal RPC. No INSERT/UPDATE/DELETE grant -> direct client
-- writes are impossible (Backend Authority, Req 5). service_role for backend ops.

GRANT SELECT ON TABLE public.forensic_evidence_snapshots TO authenticated;
-- Strip any inherited write privilege (schema default-privileges): the vault is
-- read-only for tenants; the sole write path is the DEFINER seal RPC (Req 5).
REVOKE INSERT, UPDATE, DELETE ON TABLE public.forensic_evidence_snapshots FROM authenticated;
GRANT ALL    ON TABLE public.forensic_evidence_snapshots TO service_role;

GRANT EXECUTE ON FUNCTION public.seal_forensic_evidence(
  UUID, UUID, TEXT, TEXT, INT, TIMESTAMPTZ, UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.verify_forensic_evidence(UUID, UUID)
  TO authenticated, service_role;
