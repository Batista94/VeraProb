# Registro de Aceite de Risco — `public.spatial_ref_sys` REVOKE no-op

**Tipo:** Accept-Risk / Auditoria de Trilha (governança).
**Severidade da trilha de auditoria:** ALTA — uma migração mergeada (`20260602000001`) implica mitigação que **nunca foi efetiva em produção**.
**Severidade do vetor real:** MÉDIA (Integridade/Disponibilidade) — fechada pelo controle interim `20260810000000`. Confidencialidade NENHUMA (INV-1/INV-22 não violados; sem dados de tenant).
**Invariantes:** INV-2, INV-14, INV-22, INV-DB. Protocolo: Regression-Ack (revisão do Conselho).
**Relacionados:** `20260810000000_guard_spatial_ref_sys_writes_test_plan.md`, `20260810000001_relocate_postgis_to_extensions_test_plan.md`.

---

## Achado

`public.spatial_ref_sys` (catálogo PostGIS, owner `supabase_admin`) tem `anon` e `authenticated` com `SELECT+INSERT+UPDATE+DELETE+TRUNCATE`, grantor = `supabase_admin`, `is_grantable=false`, RLS `false`. Três migrações tentaram revogar esses grants e **todas falharam silenciosamente** porque o papel de migração `postgres` é não-grantor/não-owner/não-superuser — `REVOKE` emite `WARNING 01006: no privileges could be revoked` e não altera nada.

| Timestamp | Arquivo | Tentativa | Resultado real |
|-----------|---------|-----------|----------------|
| `20260602000001` | `fix_rls_public_role_policies.sql:75-93` | `REVOKE … ON public.spatial_ref_sys FROM anon, authenticated` | **no-op silencioso** |
| `20260717000002` | `fix_anon_function_execute_revoke.sql` | REVOKE no mesmo catálogo | **no-op silencioso** |
| `20260804000001` | `reharden_rls_always_true_regressions.sql` | já **NÃO** emite REVOKE; documenta o no-op em §A (modelo correto) | n/a (correto) |

`20260804000001` é o modelo certo: documenta a impossibilidade e não emite statement inútil. As duas anteriores criam falsa garantia — problema de auditoria SOC2.

## Por que não emitimos um 4º REVOKE

Provado no-op no tier `postgres`. Repetir adiciona ruído de auditoria e nova falsa garantia. Os levers no tier `postgres` foram esgotados (RLS owner-only, REVOKE grantor-only, `ALTER EXTENSION … SET SCHEMA` → `0A000`).

## Risco aceito (temporário, com mitigação ativa)

Enquanto o PostGIS reside em `public`:

- **Vetor fechado AGORA** pelo controle interim `20260810000000` (trigger `BEFORE` role-scoped que bloqueia `anon`/`authenticated` com `42501`). Grants permanecem (não removíveis pelo `postgres`), mas a escrita é barrada antes de qualquer dano.
- **Leitura `anon`** do catálogo permanece (enumeração de SRID público). Sem `organization_id`, sem PII, sem linha de tenant → **sem violação de confidencialidade**. Idêntico em toda instalação PostGIS.

**Postura permanente (plano FREE):** o end-state correto continua sendo a relocação `public → extensions` (`20260810000001`), **executável self-serve** no plano FREE via Dashboard → Database → Extensions (disable→re-enable em `extensions`) — sem ticket/sem upgrade. Enquanto a janela de manutenção não for executada (ou se o diálogo do Dashboard não expuser o seletor de schema), o guard interim `20260810000000` é aceito como controle **durável**: confidencialidade NENHUMA + vetor de escrita fechado tornam o residual aceitável. O advisor permanece amarelo até a relocação.

## Remediação escolhida

1. **Interim (aplicado):** `20260810000000` guard trigger.
2. **Raiz (staged + ticket):** `20260810000001` relocação para `extensions`.
3. **Detecção CI (standing):** pgTAP afirma ausência de coluna de tenant + contagem `>= 8300` (detecta TRUNCATE pós-fato no próximo `make test-db`).

| Item | Status |
|------|--------|
| Plano Supabase | FREE — relocação self-serve via Dashboard (sem ticket) |
| Janela de relocação executada (data) | `<preencher ao executar>` |
| Relocação aplicada | `[ ]` pendente janela de manutenção |
| Advisor limpo (pós-reloc) | `[ ]` |
| Controle interim removido (auto via DROP) | `[ ]` |

## Assinatura do Conselho (Regression-Ack)

- **QA/Security:** Confidencialidade NENHUMA; Integridade/Disponibilidade MÉDIA fechada pelo interim; trilha de auditoria ALTA corrigida por este registro. Não emitir 4º REVOKE. **Aprovado.**
- **Architect:** PostGIS em `public` viola INV-14; relocação para `extensions` é o end-state correto e é **self-serve no plano FREE** (Dashboard → Extensions). Enquanto a janela não roda, o guard interim é controle durável aceitável (confidencialidade NENHUMA). **Aprovado.**

> Removendo este risco: executar a janela de relocação do Runbook (`20260810000001` test plan, Postura A) e aplicar `20260810000001` na mesma janela. Validar via `R.1–R.4` no plano `20260810000001`.
