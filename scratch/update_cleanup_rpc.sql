-- RPC de Limpeza corrigido para evitar violações de FK
CREATE OR REPLACE FUNCTION public.test_cleanup_forensic_data(p_org_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Disable append-only triggers, delete, re-enable — in reverse FK order.

  ALTER TABLE public.telegram_evidence_links  DISABLE TRIGGER USER;
  DELETE FROM public.telegram_evidence_links  WHERE organization_id = p_org_id;
  ALTER TABLE public.telegram_evidence_links  ENABLE TRIGGER USER;

  ALTER TABLE public.telegram_evidence_metadata DISABLE TRIGGER USER;
  DELETE FROM public.telegram_evidence_metadata WHERE organization_id = p_org_id;
  ALTER TABLE public.telegram_evidence_metadata ENABLE TRIGGER USER;

  ALTER TABLE public.telegram_evidence_categories DISABLE TRIGGER USER;
  DELETE FROM public.telegram_evidence_categories WHERE organization_id = p_org_id;
  ALTER TABLE public.telegram_evidence_categories ENABLE TRIGGER USER;

  ALTER TABLE public.telegram_evidence_uploads DISABLE TRIGGER USER;
  DELETE FROM public.telegram_evidence_uploads WHERE organization_id = p_org_id;
  ALTER TABLE public.telegram_evidence_uploads ENABLE TRIGGER USER;

  ALTER TABLE public.telegram_chat_bindings   DISABLE TRIGGER USER;
  DELETE FROM public.telegram_chat_bindings   WHERE organization_id = p_org_id;
  ALTER TABLE public.telegram_chat_bindings   ENABLE TRIGGER USER;

  ALTER TABLE public.telegram_binding_tokens  DISABLE TRIGGER USER;
  DELETE FROM public.telegram_binding_tokens  WHERE organization_id = p_org_id;
  ALTER TABLE public.telegram_binding_tokens  ENABLE TRIGGER USER;
END;
$$;

REVOKE ALL ON FUNCTION public.test_cleanup_forensic_data(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.test_cleanup_forensic_data(UUID) TO service_role;
