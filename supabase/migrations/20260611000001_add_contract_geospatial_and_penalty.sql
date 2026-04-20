-- ============================================================
-- veraprob — Add geospatial and penalty multiplier to contracts
-- ============================================================
-- REASON:
--   The domain model (Contract aggregate) was updated to include
--   optional geographic coordinates for the contract's primary 
--   location and a mandatory penalty multiplier (BPS precision).
--   This migration aligns the DB schema with the infrastructure layer.
-- ============================================================

ALTER TABLE public.contracts
  ADD COLUMN IF NOT EXISTS latitude           DOUBLE PRECISION 
                                              CHECK (latitude BETWEEN -90 AND 90),
  ADD COLUMN IF NOT EXISTS longitude          DOUBLE PRECISION 
                                              CHECK (longitude BETWEEN -180 AND 180),
  ADD COLUMN IF NOT EXISTS penalty_multiplier DOUBLE PRECISION NOT NULL DEFAULT 1.0;

COMMENT ON COLUMN public.contracts.latitude IS 
  'Geographic latitude of the contract primary location. (Physical Metric)';
COMMENT ON COLUMN public.contracts.longitude IS 
  'Geographic longitude of the contract primary location. (Physical Metric)';
COMMENT ON COLUMN public.contracts.penalty_multiplier IS 
  'Multiplier applied to penalties (stored as double, handled as BPS in domain).';
