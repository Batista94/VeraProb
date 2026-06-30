-- =============================================================================
-- Migration: Enqueue Verdict Webhooks Trigger
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
BEGIN
  -- We only fire for terminal verdict states (SEALED, REFUSED, DISPUTE_ACCEPTED, DISPUTE_OVERTURNED, DISPUTE_RETRACTED, SANCTION_ACKNOWLEDGED)
  IF NEW.fact_type IN ('VERDICT_SEALED', 'VERDICT_REFUSED', 'DISPUTE_ACCEPTED', 'DISPUTE_OVERTURNED', 'DISPUTE_RETRACTED', 'SANCTION_ACKNOWLEDGED') THEN
    
    -- Format payload (Minimal as per plan, edge function will expand cross-verify hashes)
    v_payload := jsonb_build_object(
      'schema_version', '1.0',
      'event_type', NEW.fact_type,
      'occurred_at', NEW.occurred_at,
      'organization_id', NEW.organization_id,
      'case', jsonb_build_object(
        'ledger_entry_id', NEW.id,
        'snapshot_id', NEW.snapshot_id
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
        NEW.fact_type,
        v_payload,
        'PENDING',
        NULL -- one-shot constraint will be updated by edge-fn
      );
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_enqueue_verdict_webhooks
  AFTER INSERT ON public.sla_audit_ledger_v2
  FOR EACH ROW EXECUTE FUNCTION public.enqueue_verdict_webhooks();
