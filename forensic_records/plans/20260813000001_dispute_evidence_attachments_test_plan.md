# Plano de Testes — Dispute Evidence Attachments

**Migração:** `supabase/migrations/20260813000001_dispute_evidence_attachments.sql`
**Teste pgTAP:** `supabase/tests/20260813000001_dispute_evidence_attachments_test.sql`
**Invariantes:** INV-1 (org filter), INV-2/INV-22 (RLS por org), INV-3 (append-only),
INV-6 (TIMESTAMPTZ), INV-9 (selo SHA-256), INV-DB (zero-downtime), INV-DATA-API-GRANT.
**Risco:** Alto — material probatório. Falha = evidência adulterável, ressuscitável
ou visível cross-tenant; o "fim do Telegram operacional" perde valor forense.

## Objetivo

Garantir que a tabela de evidência criptográfica existe, sela os campos forenses,
bloqueia DELETE e ressurreição de soft-delete (B3), isola por tenant via RLS e
NÃO expõe caminho de INSERT direto ao cliente (B4: INSERT só via RPC).

## Casos pgTAP (plan = 22)

**Estrutura**
1. Tabela `dispute_evidence_attachments` existe.
2. `organization_id` existe (UUID).
3. `queue_entry_id` existe (UUID).
4. `verification_status` default `PENDING` (ADD-2).
5. `attached_at` é TIMESTAMPTZ (INV-6).
6. `hash_verified_at` é TIMESTAMPTZ (INV-6).

**Constraints**
7. `chk_evidence_mime` restringe o domínio MIME.
8. `chk_evidence_size` limita 1B–10MB.
9. `chk_evidence_hash_format` exige 64-hex minúsculo (INV-9).
10. `chk_evidence_verif` restringe `PENDING/VERIFIED/MISMATCH`.
11. `uq_dea_hash_per_queue` deduplica hash por (org, queue).

**RLS + políticas (INV-2, INV-22)**
12. RLS habilitada.
13. Política SELECT `dea_select_own_org` existe.
14. Política UPDATE `dea_update_own_org` existe.
15. ZERO política INSERT (B4: insert só via RPC SECURITY DEFINER).

**Triggers comportamentais (INV-9, INV-3, B3)**
16. Mutação de campo selado (`sha256_hash`) lança `23001` (restrict_violation).
17. DELETE físico lança `23001` (append-only).
18. Soft-delete (`SET deleted_at = NOW()`) é permitido.
19. Un-soft-delete (`SET deleted_at = NULL`) lança `23001` (B3: anti-ressurreição).

**Grants (INV-DATA-API-GRANT)**
20. `authenticated` tem SELECT.
21. `authenticated` tem UPDATE (soft-delete).
22. `authenticated` NÃO tem INSERT (caminho RPC-only, B4).

## Notas

- Sem `col_is_nullable` schema-qualified no pgTAP local; estrutura via
  `information_schema.columns` + `ok()` (padrão 20260729000001).
- Triggers verificados por `throws_ok(..., '23001', NULL, ...)` em subtransação
  (não aborta a transação externa do teste). SQLSTATE `23001` = `restrict_violation`.
- Ordem dos casos comportamentais é deliberada: falhas via `throws_ok` (linha
  intacta) antes do soft-delete real (`lives_ok`), e o anti-ressurreição por
  último (exige `deleted_at` já setado).
