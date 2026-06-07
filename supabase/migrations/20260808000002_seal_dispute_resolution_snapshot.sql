-- Creates a forensic evidence snapshot linked to an EXISTING ledger entry.
-- Used exclusively by the DISPUTE_OVERTURNED arc: resolve_dispute_handler
-- appends the DISPUTE_OVERTURNED ledger fact first, then calls this RPC
-- to attach the immutable snapshot to that entry.
-- Unlike seal_forensic_evidence, this function performs NO ledger append
-- (INV-3: append-only). It freezes SLA rules and computes the integrity
-- hash identically, so verify_forensic_evidence works without modification.
CREATE OR REPLACE FUNCTION public.seal_dispute_resolution_snapshot(
  p_organization_id  UUID,
  p_ledger_entry_id  UUID,
  p_contract_id      UUID,
  p_set_id           TEXT,
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
  v_existing    public.forensic_evidence_snapshots;
  v_row         public.forensic_evidence_snapshots;
BEGIN
  -- Tenant guard (INV-1, INV-22).
  v_jwt_org := auth.jwt() -> 'app_metadata' ->> 'org_id';
  IF v_jwt_org IS NOT NULL AND v_jwt_org::uuid <> p_organization_id THEN
    RAISE EXCEPTION 'Cross-tenant seal rejected (INV-1/INV-22)'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Idempotency short-circuit (INV-11): replay returns existing snapshot
  -- without creating a second entry.
  SELECT * INTO v_existing
    FROM public.forensic_evidence_snapshots
   WHERE organization_id = p_organization_id
     AND idempotency_key = p_idempotency_key;
  IF FOUND THEN
    RETURN to_jsonb(v_existing);
  END IF;

  -- Backend Authority (Req 5.1/5.2): resolve rule set from DB only.
  SELECT id INTO v_rule_set_id
    FROM public.contract_rule_sets
   WHERE organization_id = p_organization_id
     AND contract_id = p_contract_id::text
   LIMIT 1;
  IF v_rule_set_id IS NULL THEN
    RAISE EXCEPTION 'No rule set for contract % (Req 5.3)', p_contract_id
      USING ERRCODE = 'P0002';
  END IF;

  -- Freeze rule versions active at verdict timestamp (INV-15).
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

  -- Build self-contained snapshot (Req 11, 12).
  -- Uses p_ledger_entry_id directly — no new ledger row is inserted.
  v_snapshot := jsonb_build_object(
    'schema_version',     1,
    'organization_id',    p_organization_id,
    'contract_id',        p_contract_id,
    'rule_set_id',        v_rule_set_id,
    'sla_rule_version',   v_max_version,
    'effective_from_utc', v_eff_from,
    'effective_to_utc',   v_eff_to,
    'verdict_type',       'DISPUTE_OVERTURNED',
    'set_id',             p_set_id,
    'plan_version',       p_plan_version,
    'occurred_at_utc',    p_occurred_at_utc,
    'ledger_entry_id',    p_ledger_entry_id,
    'rules',              v_rules
  );

  -- Integrity hash (INV-9) over JCS canonical form.
  v_hash := encode(
    extensions.digest(public.jsonb_canonical_text(v_snapshot), 'sha256'),
    'hex'
  );

  -- Persist into the vault. Same txn as the caller's ledger append
  -- (Supabase PostgREST uses implicit transactions per RPC call).
  INSERT INTO public.forensic_evidence_snapshots
    (organization_id, ledger_entry_id, contract_id, rule_set_id,
     sla_rule_version, effective_from_utc, effective_to_utc, snapshot,
     schema_version, integrity_hash, idempotency_key, sealed_by)
  VALUES
    (p_organization_id, p_ledger_entry_id, p_contract_id, v_rule_set_id,
     v_max_version, v_eff_from, v_eff_to, v_snapshot,
     1, v_hash, p_idempotency_key, p_sealed_by)
  RETURNING * INTO v_row;

  RETURN to_jsonb(v_row);

EXCEPTION
  WHEN unique_violation THEN
    -- Concurrent call with same idempotency key won the race. Return winner.
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

GRANT EXECUTE ON FUNCTION public.seal_dispute_resolution_snapshot(
  UUID, UUID, UUID, TEXT, INT, TIMESTAMPTZ, UUID, TEXT
) TO authenticated;

GRANT EXECUTE ON FUNCTION public.seal_dispute_resolution_snapshot(
  UUID, UUID, UUID, TEXT, INT, TIMESTAMPTZ, UUID, TEXT
) TO service_role;
