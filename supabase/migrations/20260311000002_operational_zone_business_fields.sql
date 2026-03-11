-- Migration: Operational Zone — business identity fields + optional geofence
--
-- 1. Makes lat/lng/radius nullable — geofence is now an optional configuration,
--    not a required identity property. Zones without geofence are valid in the
--    MVP and will be matched by name/id only.
-- 2. Adds `type` (business classification) and `address` (human-readable location).

ALTER TABLE public.operational_zones
  ALTER COLUMN latitude     DROP NOT NULL,
  ALTER COLUMN longitude    DROP NOT NULL,
  ALTER COLUMN radius_meters DROP NOT NULL;

ALTER TABLE public.operational_zones
  ADD COLUMN IF NOT EXISTS type    TEXT NOT NULL DEFAULT 'garagem',
  ADD COLUMN IF NOT EXISTS address TEXT;
