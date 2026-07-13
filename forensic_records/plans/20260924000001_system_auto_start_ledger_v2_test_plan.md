# Plano de Testes — 20260924000001_system_auto_start_ledger_v2

**Migração:** `supabase/migrations/20260924000001_system_auto_start_ledger_v2.sql`
**pgTAP:** `supabase/tests/20260924000001_system_auto_start_ledger_v2_test.sql`
**CIA:** I — SSOT auto-start (INV-3)

## Bug

`process_gps_for_execution_transitions` gravava `SYSTEM_AUTO_START` em `sla_audit_ledger` (v1). A projection OCC lê só `sla_audit_ledger_v2` → evento invisível. ENUM não tinha o label.

## Escopo

1. `ALTER TYPE … ADD VALUE IF NOT EXISTS 'SYSTEM_AUTO_START'`.
2. INSERT em v2 com `v_contract_id::uuid` + actor_* no payload.
3. Sem INSERT em v1 no functiondef.
