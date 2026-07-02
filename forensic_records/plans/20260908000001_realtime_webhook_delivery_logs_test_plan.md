# Test Plan: realtime_webhook_delivery_logs (Fase 10.7 — P4 gap fix)

## Migration Coverage

| Migration | pgTAP File | Status |
|-----------|-----------|--------|
| `20260908000001_realtime_webhook_delivery_logs.sql` | `20260908000001_realtime_webhook_delivery_logs_test.sql` | ✅ |

## Intent

`WebhookManagementScreen` promete "delivery logs em tempo real" via
`deliveryLogStreamProvider` (supabase `.stream(primaryKey: ['id'])`), mas
`webhook_delivery_logs` nunca foi adicionada à publicação `supabase_realtime`.
Sem membership, o `.stream()` entrega apenas o fetch inicial e nunca recebe
`postgres_changes` — a observabilidade degrada silenciosamente para um
snapshot estático (invisível a `flutter analyze` e aos pgTAP funcionais).

Esta migração publica a tabela na `supabase_realtime`, espelhando o padrão
comprovado de `dispute_evidence_attachments` (20260826000001): membership de
publicação apenas, sem DDL na tabela, portanto `types.database.ts` inalterado.

INV-22: o feed `postgres_changes` para `authenticated` é gated pelo RLS da
própria tabela ("Authenticated users can read their org webhook delivery
logs" — `organization_id = app_metadata.org_id`, 20260904000003). Tenant-A
nunca recebe eventos de Tenant-B.

## Test Scenarios (3 assertions)

| # | Category | Scenario | Assertion | INV |
|---|----------|----------|-----------|-----|
| P1 | Realtime | `webhook_delivery_logs` is a member of `supabase_realtime` | `is(count,1)` via `pg_publication_tables` | INV-16 |
| P2 | Idempotency | migration is re-runnable (single membership row, no dupe) | `is(count,1)` | append-only |
| P3 | Security | RLS still enabled on the published table (realtime stays RLS-gated) | `is(relrowsecurity,true)` | INV-22 |

## Council Sign-off

- Senior ✅ — Reuses the proven realtime publication idiom (20260826000001); no DDL on the table, idempotent ADD.
- QA-Security ✅ — Published table keeps org-scoped RLS; realtime `postgres_changes` is RLS-gated → no cross-tenant leak (INV-22).
- Lead Reviewer ✅ — Scoped, append-only, types unaffected.

## Run Command

```bash
make test-db
```
