-- ============================================================
-- PactaFlow — Financial Precision: contractual_value → BIGINT cents
-- ============================================================
-- REASON:
--   Storing monetary values as DOUBLE PRECISION violates the
--   non-negotiable financial invariant (see .cursorrules):
--   "Financial Precision: Money value object in integer cents
--    (BIGINT), NEVER double/float"
--
--   IEEE 754 floating-point cannot represent certain cent values
--   exactly (e.g., 0.1 + 0.2 ≠ 0.3), making financial totals
--   non-deterministic across accumulations. BIGINT cents avoids
--   this class of error entirely.
--
-- STRATEGY:
--   1. Add new BIGINT column (contractual_value_cents)
--   2. Backfill from existing DOUBLE PRECISION values
--      using ROUND to nearest integer cent
--   3. Set NOT NULL constraint
--   4. Drop old column
--
-- AFFECTED TABLES:
--   - public.contractual_service_executions
--   - public.execution_states
-- ============================================================

-- ── contractual_service_executions ───────────────────────────

ALTER TABLE public.contractual_service_executions
  ADD COLUMN contractual_value_cents BIGINT;

UPDATE public.contractual_service_executions
  SET contractual_value_cents = ROUND(contractual_value * 100)::BIGINT
  WHERE contractual_value_cents IS NULL;

ALTER TABLE public.contractual_service_executions
  ALTER COLUMN contractual_value_cents SET NOT NULL;

ALTER TABLE public.contractual_service_executions
  DROP COLUMN contractual_value;

COMMENT ON COLUMN public.contractual_service_executions.contractual_value_cents IS
  'Contractual value in integer cents (BIGINT). R$1.00 = 100. Never float.';

-- ── execution_states ─────────────────────────────────────────

ALTER TABLE public.execution_states
  ADD COLUMN contractual_value_cents BIGINT;

UPDATE public.execution_states
  SET contractual_value_cents = ROUND(contractual_value * 100)::BIGINT
  WHERE contractual_value_cents IS NULL;

ALTER TABLE public.execution_states
  ALTER COLUMN contractual_value_cents SET NOT NULL;

ALTER TABLE public.execution_states
  DROP COLUMN contractual_value;

COMMENT ON COLUMN public.execution_states.contractual_value_cents IS
  'Contractual value in integer cents (BIGINT). R$1.00 = 100. Never float.';
