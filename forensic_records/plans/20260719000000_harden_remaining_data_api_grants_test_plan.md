# Test Plan: 20260719000000 — Hardening Remaining Data API Grants

**Migration:** `supabase/migrations/20260719000000_harden_remaining_data_api_grants.sql`
**Invariants:** INV-DATA-API-GRANT (CI Block 13)
**Risk:** LOW — non-destructive privilege lockdown.

---

## Exploit Closed

| Vector | Before | After |
|--------|--------|-------|
| `anon`/`authenticated` Direct access to `pdf_dossier_logs` | Allowed all default actions | Limited to `SELECT` and `INSERT` for `authenticated` only |
| `anon`/`authenticated` Direct access to `shadow_mode_simulations` | Allowed all default actions | Limited to `SELECT` and `INSERT` for `authenticated` only |
| `anon`/`authenticated` Direct access to `telegram_status_queries` | Allowed all default actions | Limited to `SELECT` and `INSERT` for `authenticated` only |
| View SELECT privileges for standard views | Exposed to public/anon | Restrained to `authenticated` and `service_role` |

---

## pgTAP Tests

Unit tests are implemented in `supabase/tests/20260719000000_harden_remaining_data_api_grants_test.sql` and verify role privilege arrays.

---

## Rollback

```sql
-- Restore default privileges for client access if needed
GRANT ALL ON TABLE public.pdf_dossier_logs TO authenticated, anon;
GRANT ALL ON TABLE public.shadow_mode_simulations TO authenticated, anon;
GRANT ALL ON TABLE public.telegram_status_queries TO authenticated, anon;
GRANT SELECT ON public.contractors_view TO public, anon, authenticated;
GRANT SELECT ON public.invitations_view TO public, anon, authenticated;
GRANT SELECT ON public.v_roi_summary TO public, anon, authenticated;
```
