-- Migration: Operational Zone — add created_at column
--
-- The table was originally created with `created_at_utc` (migration 20260311000000).
-- Something in the Supabase layer (trigger, RLS policy, or view) references the bare
-- `created_at` column name, causing ERROR: 42703: column "created_at" does not exist
-- when inserting via the UI.
--
-- This migration adds the column idempotently. Safe to run multiple times.

ALTER TABLE public.operational_zones
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();
