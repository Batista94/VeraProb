# Plano de Teste — SLA Sandbox Simulation Engine (Phase 10.8)

- **Migração:** `supabase/migrations/20261001000002_sandbox_simulation_engine.sql`
- **pgTAP:** `supabase/tests/20261001000002_sandbox_simulation_engine_test.sql`
- **Invariantes:** INV-1, INV-2, INV-4, INV-5, INV-6, INV-15, INV-22, INV-26

## Escopo

RPC `simulate_sla_sandbox()`: claim check, contract validation, compute governance, ledger replay, override application, aggregate computation.

## Casos

| # | Caso | Resultado esperado |
|---|------|---------------------|
| 1 | Função existe | `has_function` ok |
| 2-3 | Claim mismatch: org B tenta simular contrato de org A | `no_data_found` (INV-26) |
| 4 | Contract not found | `no_data_found` (INV-26) |
| 5 | Period > 6 meses | `invalid_parameter_value` |
| 6 | Period end <= start | `invalid_parameter_value` |
| 7-10 | Simulação com 3 eventos penal: baseline + override multiplicador | session criada, delta correto, resultados corretos |
| 11-12 | Override não modifica regras sem match | `was_override_applied = false`, fine inalterado |
| 13-14 | Financial override: `monthly_penalty_cap_cents` | cap simulado aplicado, `simulated_cap_truncated = true` |
| 15 | Session quota (50 max) | `program_limit_exceeded` |
| 16 | RPC NÃO escreve em sla_audit_ledger_v2 | count inalterado pré/pós |
| 17 | Sessão sem eventos penal no período | session criada com baseline=0, sim=0, delta=0 |
| 18 | delta_bps computation | (baseline - sim) * 10000 / baseline |

## Verificação Manual

```bash
supabase db reset && make test-db
```
