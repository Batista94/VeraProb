# Forensic Test Plan: 20260728000001_sla_template_audit_log

## Objetivo
Validar a tabela imutável `sla_template_audit_log`, que registra toda criação/edição
de modelos de SLA para governança retroativa (Bloco 3 — Meta-Audit). Garante isolamento
multi-tenant via RLS (`app_metadata.org_id`) e imutabilidade append-only.

## Invariantes Garantidas
- **INV-1:** Isolamento por `organization_id` (RLS ativa).
- **INV-2:** Identidade organizacional via `auth.jwt() -> 'app_metadata' ->> 'org_id'` (nunca `auth.uid()`).
- **INV-3:** Append-only — `UPDATE`/`DELETE` bloqueados por revogação de grant + trigger (`restrict_violation`).
- **INV-6:** `occurred_at_utc` é `TIMESTAMPTZ`.
- **INV-22:** Tenant-A nunca enxerga dados do Tenant-B.
- **INV-DATA-API-GRANT:** Grants explícitos (`SELECT`, `INSERT`) para `authenticated` e `service_role`.

## Cenários de Teste (pgTAP)

| # | Cenário | Asserção |
|---|---------|----------|
| P1 | Colunas obrigatórias existem | `has_column(...)` para `id`, `organization_id`, `template_snapshot`, `occurred_at_utc` |
| P2 | `occurred_at_utc` é TIMESTAMPTZ (INV-6) | `col_type_is(... 'timestamp with time zone')` |
| P3 | `template_snapshot` é JSONB | `col_type_is(... 'jsonb')` |
| P4 | `UPDATE` em registro existente | `throws_ok('23001')` — `restrict_violation` (INV-3) |
| P5 | `DELETE` em registro existente | `throws_ok('23001')` — `restrict_violation` (INV-3) |
| P5b | Estado da linha inalterado após UPDATE/DELETE bloqueados | `results_eq(ARRAY['CREATED'])` — prova imutabilidade real (INV-3) |
| P6 | org_a lê os próprios registros | `results_eq(ARRAY[1])` |
| P7 | org_b isolado de org_a | `results_eq(ARRAY[0])` (INV-22) |
| P8 | org_b insere registro para org_a | Erro RLS (`new row violates row-level security policy`) |
| P9 | org_b insere o próprio registro | `lives_ok(...)` |

## Verificação Dart (unit)
- `test/application/sla_audit/save_sla_template_handler_test.dart` (grupo Meta-Audit):
  - `CREATED` registrado ao criar (sem `existingId`).
  - `UPDATED` registrado ao atualizar (com `existingId`).
  - `templateSnapshot` contém `name` + `penalties`; `occurredAtUtc == clock.nowUtc()` (INV-6).
