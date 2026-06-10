# Plano de Testes — 20260811000000_harden_client_role_grants

**Migração:** `supabase/migrations/20260811000000_harden_client_role_grants.sql`
**Invariantes:** INV-2, INV-3 (ledger append-only), INV-22 (isolamento de tenant), INV-DATA-API-GRANT (CI block #13). INV-DB: sem DDL destrutivo (apenas `REVOKE` de privilégios + `ALTER FUNCTION SET`).
**Risco:** Crítico mitigado — fecha vetor de destruição cross-tenant via `TRUNCATE` (não coberto por RLS) sobre o ledger forense e tabelas de tenant.
**pgTAP:** `supabase/tests/20260811000000_harden_client_role_grants_test.sql` (16 testes).

---

## Contexto — achado da varredura CIA (2026-06-09)

O `ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ...` legado da Supabase (grantor: `postgres`) concede automaticamente `arwdDxtm` (INSERT/SELECT/UPDATE/DELETE/**TRUNCATE**/REFERENCES/TRIGGER/MAINTAIN) a `anon` e `authenticated` em toda tabela criada por `postgres`. O endurecimento por-tabela foi aplicado apenas **parcialmente**, deixando expostas as tabelas mais sensíveis:

| Papel | Capacidade aberta (pré-migração) | Tabelas |
|-------|----------------------------------|---------|
| `anon` (não autenticado) | **TRUNCATE** | 30 tabelas incl. `contracts`, `vehicles`, `sla_audit_ledger_v2`(+p0..p3), `forensic_evidence_snapshots` |
| `authenticated` (qualquer usuário) | **TRUNCATE** | `forensic_evidence_snapshots`, `sla_audit_ledger_p0..p3` |
| `authenticated` | **DELETE/UPDATE** | `sla_audit_ledger_v2` (ledger append-only) |

**Por que crítico:** políticas RLS **não se aplicam a `TRUNCATE`**. Uma chave `anon` extraída poderia `TRUNCATE public.sla_audit_ledger_v2` / `TRUNCATE public.contracts` e destruir os dados de todos os tenants + o ledger forense imutável. Qualquer usuário Tenant-A logado poderia `TRUNCATE` evidências/ledger e apagar registros do Tenant-B. Viola INV-3, INV-22, disponibilidade.

**Executável no tier de migração:** todas as tabelas afetadas têm owner e grantor = `postgres` (verificado via `information_schema.role_table_grants.grantor`), logo os `REVOKE` surtem efeito — diferente do caso `spatial_ref_sys` (owner `supabase_admin`, REVOKE no-op silencioso).

## Escopo (Conservador — quebra ~zero)

1. **Futuro:** `ALTER DEFAULT PRIVILEGES … REVOKE` corta a herança do default inseguro para novas tabelas (apenas defaults do grantor `postgres`; tabelas de app são criadas por `postgres`).
2. **Universal:** `REVOKE TRUNCATE … FROM anon, authenticated` em todas as tabelas — nenhum papel de cliente jamais executa `TRUNCATE` (somente backend/`service_role`).
3. **Ledger + evidências:** `REVOKE UPDATE, DELETE, TRUNCATE` — papéis de cliente mantêm só SELECT/INSERT; escritas reais fluem por RPCs `SECURITY DEFINER` (owner `postgres`). INV-3 reforçado na camada de grant.
4. **anon defense-in-depth:** `REVOKE ALL` nas tabelas de tenant/negócio (nenhuma tem política RLS para `anon`; RLS já nega toda linha). Tabelas de fluxo público (`contract_review_tokens`, `justification_submission_tokens`, `telegram_binding_tokens`) e tabelas `telegram_*` gateadas por RLS ficam intactas.
5. **search_path:** `ALTER FUNCTION … SET search_path = public` em `auto_enqueue_sanction_recommended` e `create_execution_for_operator` (advisor `function_search_path_mutable`, CWE-426). Metadata-only → preserva determinismo de replay INV-15.

## Nota INV-DB

Os `REVOKE … TRUNCATE/DELETE/UPDATE` são revogações de **privilégio** (metadata de catálogo instantânea, sem scan, sem perda de dados) — **não** DML/DDL destrutivo. O scanner casa as palavras-chave `TRUNCATE`/`DELETE`, então cada linha recebe `-- INV-DB: zero-downtime-verified`. **Requer ack do Council (QA/Security)** na revisão, conforme a disciplina de Regression-Ack — não auto-ackar.

## Idempotência

`REVOKE` de privilégio ausente = no-op; `ALTER FUNCTION … SET` = last-write-wins. Seguro para re-rodar via `supabase db push`.

---

## Verificação (psql / Supabase Studio)

```sql
-- Vetor TRUNCATE fechado para papéis de cliente
SELECT has_table_privilege('anon','public.sla_audit_ledger_v2','TRUNCATE');        -- false
SELECT has_table_privilege('authenticated','public.forensic_evidence_snapshots','TRUNCATE'); -- false
SELECT has_table_privilege('anon','public.contracts','TRUNCATE');                  -- false

-- Ledger append-only imutável a papéis de cliente (INV-3)
SELECT has_table_privilege('authenticated','public.sla_audit_ledger_v2','DELETE'); -- false
SELECT has_table_privilege('authenticated','public.sla_audit_ledger_v2','UPDATE'); -- false

-- anon removido das tabelas de tenant
SELECT has_table_privilege('anon','public.contracts','SELECT');                    -- false

-- Fluxos públicos preservados (sem regressão)
SELECT has_table_privilege('anon','public.contract_review_tokens','SELECT');       -- true
SELECT has_table_privilege('anon','public.justification_submission_tokens','INSERT'); -- true

-- service_role intacto
SELECT has_table_privilege('service_role','public.sla_audit_ledger_v2','SELECT');  -- true

-- search_path fixado
SELECT proname, proconfig FROM pg_proc
 WHERE proname IN ('auto_enqueue_sanction_recommended','create_execution_for_operator'); -- {search_path=public}
```

## Rollback

`REVOKE` não tem caminho de rollback automático (não re-conceder privilégios inseguros). Em caso de quebra de fluxo legítimo, conceder explicitamente o privilégio mínimo necessário à tabela específica (padrão CI block #13), nunca restaurar o `ALTER DEFAULT PRIVILEGES` global.
