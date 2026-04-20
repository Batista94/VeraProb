-- Migration: Make quota columns nullable to support 'Enterprise' unlimited (Phase 9.8.D)
--
-- INV-19: Limits remain integers. NULL means unlimited.
--

ALTER TABLE public.organizations
  ALTER COLUMN max_vehicles DROP NOT NULL,
  ALTER COLUMN max_active_contracts DROP NOT NULL,
  -- Set defaults to NULL to match 'unlimited' logic if needed, 
  -- but current DEFAULTs are 50 and 10 and that's fine for Starter.
  ALTER COLUMN max_vehicles SET DEFAULT 50,
  ALTER COLUMN max_active_contracts SET DEFAULT 10;
