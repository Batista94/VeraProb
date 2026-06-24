# Plano de Testes — Dispute Evidence Storage Bucket

**Migração:** `supabase/migrations/20260813000002_dispute_evidence_storage_bucket.sql`
**Teste pgTAP:** `supabase/tests/20260813000002_dispute_evidence_storage_bucket_test.sql`
**Invariantes:** INV-2/INV-22 (RLS por org, isolamento folder-based), INV-3
(append-only / sem DELETE de cliente), INV-9 (blob é prova criptográfica).
**Risco:** Alto — blob de evidência. Falha = arquivo visível cross-tenant,
deletável pelo cliente ou mutável após selo.

## Objetivo

Garantir que o bucket privado `dispute_evidence` existe com a config correta
(privado, 10 MB, MIME allow-list espelhando `chk_evidence_mime` da mig 001),
que o RLS de storage isola por segmento `{org_id}` (INV-22), exige o segmento
`{queue_entry_id}` no INSERT (B4) e NÃO expõe DELETE/UPDATE ao cliente — blobs
são imutáveis e só a engine de ciclo-de-vida LGPD (`service_role`) apaga.

## Estratégia

RLS de `storage.objects` depende de `auth.jwt()` + role; não é exercitável
comportamentalmente no pgTAP local sem mockar sessão. Verificação é
**estrutural** via `storage.buckets` (config do bucket) e `pg_policies`
(existência + forma das policies: `qual`/`with_check` contêm os predicados de
isolamento). Comportamento end-to-end (cross-tenant, path traversal) coberto
manualmente e no E2E (linha "cross-tenant via Data API" do plano).

## Casos pgTAP (plan = 10)

**Config do bucket**
1. Bucket `dispute_evidence` existe.
2. Bucket é privado (`public = false`).
3. `file_size_limit` = 10 MB (10485760).
4. `allowed_mime_types` contém `image/jpeg` e `application/pdf` (paridade mig 001).

**Policies de storage (INV-2, INV-22)**
5. Policy SELECT `dispute_evidence_select` existe (cmd SELECT).
6. Policy INSERT `dispute_evidence_insert` existe (cmd INSERT).
7. `qual` da policy SELECT referencia `app_metadata` + `org_id` (gate de tenant).
8. `with_check` da policy INSERT exige `array_length` (segmento queue, B4).

**Sem mutação de cliente (INV-3, INV-9)**
9. ZERO policy DELETE `dispute_evidence%` (delete só via service_role/LGPD).
10. ZERO policy UPDATE `dispute_evidence%` (blob imutável após escrita).

## Notas

- Bucket é linha de dados em `storage.buckets`, não DDL de schema → `types.database.ts`
  não muda por esta migração.
- `ON CONFLICT (id) DO NOTHING` torna o seed do bucket idempotente (re-run seguro).
- DELETE/UPDATE de cliente ausentes por design: qualquer policy futura exige
  aprovação do Council + justificativa forense (anotado na migração).
