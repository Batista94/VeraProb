-- ============================================================
-- veraprob — Seed GTFS Routes
--
-- INV-2: Routes follow GTFS semantics (global shared reference).
-- Routes have NO INSERT policy for tenants, as they are managed
-- by system-level migrations. This migration pre-populates
-- the Dev Seeder routes for all existing active organizations
-- so that DevSeeder can reference them without encountering
-- 42501 insufficient_privilege.
-- ============================================================

INSERT INTO public.routes (
  organization_id,
  gtfs_route_id,
  short_name,
  long_name,
  agency_id
)
SELECT 
  id as organization_id,
  v.gtfs_route_id,
  v.short_name,
  v.long_name,
  v.agency_id
FROM public.organizations
CROSS JOIN (
  VALUES 
    ('809U-10', '809U', 'Cidade Universitária / Metrô Barra Funda', 'SPTRANS'),
    ('875C-10', '875C', 'Term. Lapa / Metrô Santa Cruz', 'SPTRANS'),
    ('917H-10', '917H', 'Term. Pirituba / Metrô Vila Mariana', 'SPTRANS'),
    ('701U-10', '701U', 'Cidade Universitária / Metrô Santana', 'SPTRANS')
) AS v(gtfs_route_id, short_name, long_name, agency_id)
WHERE status = 'ACTIVE'
ON CONFLICT (organization_id, gtfs_route_id) DO NOTHING;
