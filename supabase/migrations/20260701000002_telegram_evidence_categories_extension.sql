-- =============================================================================
-- Migration: Telegram Evidence Categories Extension
--
-- Extends the category CHECK constraint to include three auto-start trigger
-- categories: lacre, chk_saida, carregamento.
--
-- Physical Evidence Sovereignty Rule:
--   If a driver photographs a LACRE, CHECKLIST_SAIDA, or CARREGAMENTO, the
--   physical act of sealing/loading has occurred. The contract is started.
--   The bot auto-triggers start_transit_for_execution on these categories.
--
-- callback_data budget:
--   tg_tag:{UUID}:{key} = 7 + 36 + 1 + max(9) = 53 bytes < 64-byte Telegram limit.
--   Key "chk_saida" (9 chars) used instead of "checklist_saida" (14 chars).
--
-- INV-7:  Append-only table immutability unchanged.
-- INV-18: Category values constrained to known enum; driver input untrusted.
-- =============================================================================

SET client_min_messages TO 'WARNING';

ALTER TABLE public.telegram_evidence_categories
  DROP CONSTRAINT IF EXISTS chk_tec_category;

ALTER TABLE public.telegram_evidence_categories
  ADD CONSTRAINT chk_tec_category CHECK (
    category IN (
      'estado',
      'doc',
      'oper',
      'incidente',
      'outros',
      'lacre',
      'chk_saida',
      'carregamento'
    )
  );
