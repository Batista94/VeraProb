-- Migration: Explicit Data API Grants for Missing Tables and Views
-- Rule: INV-DATA-API-GRANT (Tables/views in public schema must explicitly grant API role access)

BEGIN;

-- 1. pdf_dossier_logs (Category A / Append-only)
REVOKE ALL ON TABLE public.pdf_dossier_logs FROM public, anon, authenticated;
GRANT SELECT, INSERT ON TABLE public.pdf_dossier_logs TO authenticated;
GRANT ALL ON TABLE public.pdf_dossier_logs TO service_role;

-- 2. shadow_mode_simulations (Category A / Append-only)
REVOKE ALL ON TABLE public.shadow_mode_simulations FROM public, anon, authenticated;
GRANT SELECT, INSERT ON TABLE public.shadow_mode_simulations TO authenticated;
GRANT ALL ON TABLE public.shadow_mode_simulations TO service_role;

-- 3. telegram_status_queries (Category A / Append-only)
REVOKE ALL ON TABLE public.telegram_status_queries FROM public, anon, authenticated;
GRANT SELECT, INSERT ON TABLE public.telegram_status_queries TO authenticated;
GRANT ALL ON TABLE public.telegram_status_queries TO service_role;

-- 4. contractors_view (PII Masking View)
REVOKE ALL ON public.contractors_view FROM public, anon, authenticated;
GRANT SELECT ON public.contractors_view TO authenticated;
GRANT SELECT ON public.contractors_view TO service_role;

-- 5. invitations_view (PII Masking View)
REVOKE ALL ON public.invitations_view FROM public, anon, authenticated;
GRANT SELECT ON public.invitations_view TO authenticated;
GRANT SELECT ON public.invitations_view TO service_role;

-- 6. v_roi_summary (ROI View)
REVOKE ALL ON public.v_roi_summary FROM public, anon, authenticated;
GRANT SELECT ON public.v_roi_summary TO authenticated;
GRANT SELECT ON public.v_roi_summary TO service_role;

COMMIT;
