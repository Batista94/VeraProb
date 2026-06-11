# Plano de Testes — verify_evidence_hash_rpc

**Migração:** `supabase/migrations/20260813000009_verify_evidence_hash_rpc.sql`
**Teste pgTAP:** `supabase/tests/20260813000009_verify_evidence_hash_rpc_test.sql`
**Invariantes:** INV-1 (escopo de org pela linha `(id, organization_id)`), INV-3
(fato `EVIDENCE_HASH_MISMATCH` append-only), INV-9 (selo SHA-256 re-verificado
server-side), INV-22 (isolamento de tenant), INV-26 (anti-oráculo: 42501 genérico
p/ wrong-org E not-found).
**Risco:** Alto — fecha ADD-2/B2. Sem isto, `verification_status` nunca sai de
`PENDING` e o bloqueio MISMATCH de `resolve_dispute` (008) é controle fantasma:
um hash declarado divergente dos bytes selaria um veredito.

## Objetivo

`verify_evidence_hash(attachment_id, org_id, computed_hash, verified_at)` é o
ponto onde a Edge Function `verify-evidence-hash` (service_role) entrega o
SHA-256 recalculado dos bytes baixados do storage. O RPC **não** recalcula digest
em PL/pgSQL (timeout sobre blobs <=10MB) — só **compara** contra o `sha256_hash`
selado e persiste o veredito:
- match → `verification_status='VERIFIED'`.
- divergência → `verification_status='MISMATCH'` + fato `EVIDENCE_HASH_MISMATCH`
  (declarado vs recalculado), que `resolve_dispute` bloqueia.

## Estratégia

`SECURITY DEFINER`, **grant exclusivo a `service_role`** (a Edge Function é infra
confiável; não há chamador `authenticated`). Escopo de tenant garantido pelo
predicado `(id, organization_id)` da linha, não por claim de JWT. Sessão de teste
via `SET LOCAL ROLE service_role`. Hashes selados em lowercase hex
(`chk_evidence_hash_format`); o RPC normaliza o recalculado com `lower()`.
`set_id` do fato vem da `sanction_review_queue` (a tabela de anexos não tem
`set_id`); `contract_id` NULL é intencional (fato de integridade, não financeiro).

## Casos pgTAP (plan = 16)

**Estrutura / grants (5)**
1. assinatura `(uuid, uuid, text, timestamptz)` existe.
2. é `SECURITY DEFINER`.
3. `service_role` pode EXECUTE.
4. `authenticated` NÃO pode EXECUTE.
5. `anon` NÃO pode EXECUTE.

**Verificação limpa (3)**
6. hash coincidente → retorna `VERIFIED`.
7. anexo vira `verification_status='VERIFIED'`.
8. nenhum fato `EVIDENCE_HASH_MISMATCH` emitido.

**Mismatch (D5d, B2) (5)**
9. hash divergente → retorna `MISMATCH`.
10. anexo vira `verification_status='MISMATCH'` (bloqueável por `resolve_dispute`).
11. exatamente um fato `EVIDENCE_HASH_MISMATCH` (INV-3).
12. payload sela `declared_hash` (armazenado) + `computed_hash` (recalculado).
13. `set_id` do fato herdado da queue (`set-verify`), não do anexo.

**Normalização / anti-oráculo (3)**
14. compare case-insensitive: armazenado lowercase, recalculado uppercase → `VERIFIED`.
15. wrong-org → 42501 (indistinguível de not-found).
16. attachment id inexistente → 42501 (mesma paridade opaca, INV-26).

## Notas

- Migração aditiva (novo RPC, sem `.sql` mergeado modificado). Depende do widening
  do CHECK do ledger em `20260813000007` (já permite `EVIDENCE_HASH_MISMATCH`).
- Correção vs. rascunho do plano: o rascunho lia `v_row.set_id`, mas
  `dispute_evidence_attachments` (001) não tem `set_id` — lido da queue.
- Re-verificação repetida pode gravar mais de um fato `MISMATCH` (sem índice
  único nesse tipo); aceitável — fato de integridade, não há requisito de
  idempotência. Fiel ao corpo do plano (council-remediado).
- Migração cria RPC exposta apenas a `service_role` (não Data API
  `authenticated`), mas `supabase/types.database.ts` é regenerado e commitado
  junto por convenção.
