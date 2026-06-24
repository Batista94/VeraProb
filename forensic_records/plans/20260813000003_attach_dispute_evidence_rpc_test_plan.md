# Plano de Testes — attach_dispute_evidence RPC

**Migração:** `supabase/migrations/20260813000003_attach_dispute_evidence_rpc.sql`
**Teste pgTAP:** `supabase/tests/20260813000003_attach_dispute_evidence_rpc_test.sql`
**Invariantes:** INV-1 (org_id em todo fluxo), INV-9 (selo/prova), INV-10
(IntegrityException via P0001), INV-22 (isolamento tenant), INV-26 (paridade
anti-oracle: toda falha → 42501).
**Risco:** Alto — único caminho de INSERT de metadata de evidência. Falha =
anexo cross-tenant, posse de queue não validada, ou corrida no limite-10 (TOCTOU).

## Objetivo

`attach_dispute_evidence` é o **único** caminho para inserir em
`dispute_evidence_attachments` (não há policy de INSERT direto, B4). Fecha:
- **B4** — posse da queue + match do path `{org}/{queue}/` + status `disputed`.
- **H2** — limite de 10 anexos sob `pg_advisory_xact_lock(org, queue)` (sem TOCTOU).
- **ADD-1** — um fato `DISPUTE_EVIDENCE_ATTACHED` no ledger por upload.

## Estratégia

Comportamental via mock de sessão JWT (`SET LOCAL request.jwt.claims` +
`SET LOCAL ROLE authenticated`), padrão do `resolve_dispute_rpc_test`. O
alargamento de `chk_ledger_type` para admitir `DISPUTE_EVIDENCE_ATTACHED` foi
**dobrado nesta própria migração 003** (padrão H1-safe: ADD superset NOT VALID →
VALIDATE → DROP antiga) — uma RPC que grava um tipo de ledger que o schema vivo
rejeita seria um deploy quebrado. A migração 007 (H1) alarga adicionalmente só
para os tipos de SLA-breach. Concorrência real do advisory lock (dois uploads
simultâneos) é coberta em teste de integração Dart (dois `SupabaseClient` +
`Future.wait`); `dblink` está bloqueado no Supabase local.

## Casos pgTAP (plan = 14)

**Estrutura / grants**
1. Função existe com assinatura `(uuid,uuid,text,text,text,bigint,text,uuid,timestamptz)`.
2. `SECURITY DEFINER` (`prosecdef = true`).
3. `authenticated` pode `EXECUTE`.
4. `anon` NÃO pode `EXECUTE`.
5. `service_role` NÃO pode `EXECUTE` (sem bypass via Data API).

**Caminho feliz (TENANT_ADMIN dono, Org ATT)**
6. INSERT de metadata executa (`lives_ok`).
7. Anexo nasce com `verification_status = 'PENDING'` (B2: re-verificação pendente).
8. Exatamente um fato `DISPUTE_EVIDENCE_ATTACHED` no ledger (ADD-1).

**Gates anti-oracle (toda falha → 42501; INV-26)**
9. Cross-tenant (JWT de outro org) → 42501 (INV-22, B4).
10. Papel errado (`OPERATOR`) → 42501 (RBAC server-side).
11. Spoof de `uploaded_by` (`sub` do JWT ≠ `p_uploaded_by`) → 42501 (bind de proveniência).
12. Path não vinculado a `{org}/{queue}/` → 42501 (B4 path bind).
13. Queue fora do estado `disputed` → 42501 (gate de estado).

**Limite (H2 / ADD-3)**
14. Queue saturada com 10 anexos → 11º rejeitado com P0001.

## Notas

- `contract_id` da queue é TEXT, mas o fato do ledger casta `v_queue.contract_id::uuid`
  (a coluna `contract_id` do `sla_audit_ledger_v2` é UUID — mig 20260310210000).
  Seeds usam `contract_id` em formato UUID para o cast funcionar (padrão de
  `resolve_dispute`/`dual_control`).
- A função grava o ledger type `DISPUTE_EVIDENCE_ATTACHED`, só admitido pelo
  `chk_ledger_type` após a migração 007 (alargamento H1, superset NOT VALID).
  Apply-time da 003 é seguro (corpo de função não executa no apply).
- RPC não muda DDL exposto à Data API → `types.database.ts` inalterado por esta migração.
