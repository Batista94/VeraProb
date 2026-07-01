-- =============================================================================
-- Migration: Expand Webhook Payload (Replace Trigger)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.enqueue_verdict_webhooks()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_endpoint RECORD;
  v_payload JSONB;
  v_reason_code text;
BEGIN
  -- We only fire for terminal verdict states
  IF NEW.type IN ('VERDICT_SEALED', 'VERDICT_REFUSED', 'DISPUTE_ACCEPTED', 'DISPUTE_OVERTURNED', 'DISPUTE_RETRACTED', 'SANCTION_ACKNOWLEDGED') THEN
    
    -- reason_code is written TOP-LEVEL by approve_sanction; validate vs the catalogue.
    v_reason_code := NEW.payload->>'reason_code';
    IF v_reason_code IS NOT NULL THEN
      IF NOT EXISTS (SELECT 1 FROM public.dispute_reason_codes WHERE code = v_reason_code) THEN
        v_reason_code := NULL;
      END IF;
    END IF;

    -- Every field is sourced from where the real verdict RPCs actually write it:
    --   fine_cents       → verdict_evidence.fine_cents (SEALED, INV-15)
    --   reason_code      → top-level (approve_sanction)
    --   resolution_reason→ top-level (resolve_dispute)
    --   outcome          → derived from the ledger type (not a payload key)
    --   evidence hashes  → sealed dispute_evidence_attachments (INV-9), N per queue
    -- snapshot_id is intentionally omitted: it is not persisted in the ledger payload;
    -- ledger_entry_id is the forensic anchor the ERP correlates on.
    -- PII (placa, motorista, decided_by, *_user_id, actor_email) is never copied.
    v_payload := jsonb_build_object(
      'schema_version', '1.0',
      'event_type', NEW.type,
      'occurred_at', NEW.occurred_at_utc,
      'organization_id', NEW.organization_id,
      'case', jsonb_build_object(
        'ledger_entry_id', NEW.id,
        'queue_entry_id', NEW.payload->>'queue_entry_id'
      ),
      'evidence', jsonb_build_object(
        'attachment_hashes', COALESCE((
          SELECT jsonb_agg(d.sha256_hash ORDER BY d.sha256_hash)
          FROM public.dispute_evidence_attachments d
          WHERE d.organization_id = NEW.organization_id
            AND d.queue_entry_id = (NEW.payload->>'queue_entry_id')::uuid
            AND d.deleted_at IS NULL
        ), '[]'::jsonb)
      ),
      'verdict', jsonb_build_object(
        'outcome', CASE NEW.type
          WHEN 'VERDICT_SEALED'         THEN 'SEALED'
          WHEN 'VERDICT_REFUSED'        THEN 'REFUSED'
          WHEN 'DISPUTE_ACCEPTED'       THEN 'ACCEPTED'
          WHEN 'DISPUTE_OVERTURNED'     THEN 'OVERTURNED'
          WHEN 'DISPUTE_RETRACTED'      THEN 'RETRACTED'
          WHEN 'SANCTION_ACKNOWLEDGED'  THEN 'ACKNOWLEDGED'
        END,
        'reason_code', v_reason_code,
        'resolution_reason', NEW.payload->>'resolution_reason'
      ),
      'financial', jsonb_build_object(
        'fine_cents', COALESCE((NEW.payload->'verdict_evidence'->>'fine_cents')::bigint, 0),
        'currency', 'BRL'
      )
    );

    -- Fan-out: insert one delivery log per active endpoint of the org
    FOR v_endpoint IN 
      SELECT id FROM public.webhook_endpoints 
      WHERE organization_id = NEW.organization_id 
        AND is_active = true 
        AND deleted_at IS NULL
    LOOP
      INSERT INTO public.webhook_delivery_logs (
        organization_id,
        endpoint_id,
        ledger_entry_id,
        event_type,
        payload,
        status,
        signing_key_id
      ) VALUES (
        NEW.organization_id,
        v_endpoint.id,
        NEW.id,
        NEW.type,
        v_payload,
        'PENDING',
        NULL -- one-shot constraint will be updated by edge-fn via drain
      );
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;
