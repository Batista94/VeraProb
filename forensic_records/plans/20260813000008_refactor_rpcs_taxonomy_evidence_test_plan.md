# Plano de Testes — refactor_rpcs_taxonomy_evidence

**Migração:** `supabase/migrations/20260813000008_refactor_rpcs_taxonomy_evidence.sql`
**Teste pgTAP:** `supabase/tests/20260813000008_refactor_rpcs_taxonomy_evidence_test.sql`
**Invariantes:** INV-1 (org claim do JWT), INV-3 (ledger append-only), INV-9
(evidência selada / MISMATCH), INV-10 (exceções tipadas), INV-15 (fato
determinístico embute `reason_code`/evidência), INV-22 (isolamento de tenant),
INV-23 (`disputed_by` NUNCA limpo na retração), INV-26 (anti-oráculo: 42501
genérico p/ wrong-org E not-found E taxonomia inválida).
**Risco:** Alto — reescreve os pontos de entrada de veredito (`resolve_dispute`,
`reject_sanction`) e o selo dual-control (`confirm_peer_review`). Falha =
overload antigo sem `reason_code` sobrevive (B1), veredito sela sobre evidência
adulterada (B2), ou o fork dual-control de 10.5 regride.

## Objetivo

B1: dropa as assinaturas antigas (`resolve_dispute` 8-param, `reject_sanction`
6-param) — sem overload não-protegido residual — e recria com taxonomia
estruturada (`p_reason_code`). B2: bloqueia resolução enquanto houver anexo
`verification_status='MISMATCH'`. Embute `reason_code` + ids/hashes de evidência
no fato terminal. **Preserva o fork dual-control verbatim de 10.5** e thread o
`reason_code` pelo `pending_peer_review` até o fato selado por `confirm_peer_review`.

## Estratégia

Estrutural (assinaturas/grants via `has_function`/`hasnt_function`/
`has_function_privilege`) + comportamental como `authenticated` com
`request.jwt.claims` setado (mesmo padrão de `20260812000003`). Limiar
dual-control da org = 100000 cents: `fine <= 100000` → terminal; `fine > 100000`
→ fork. Sela (`seal_dispute_resolution_snapshot`) exige fixtures de
`contract_rule_sets`/`_versions` — por isso o caminho de **overturn só é
afirmado no fork** (sem confirm), e o teste de `reason_code` no confirm usa um
fork de **DISPUTE_ACCEPT** (confirm de accept não sela).

## Casos pgTAP (plan = 25)

**B1 — Assinaturas (6)**
1. `resolve_dispute` 9-param existe.
2. `resolve_dispute` 8-param (antiga) foi dropada (`hasnt_function`).
3. `reject_sanction` 7-param existe.
4. `reject_sanction` 6-param (antiga) foi dropada.
5. `authenticated` pode EXECUTE o novo `resolve_dispute`.
6. `authenticated` pode EXECUTE o novo `reject_sanction`.

**Taxonomia (Q2 / D6 / D7) — 3** (todas lançam antes de mutar A)
7. accept com `reason_code` inexistente → 42501.
8. accept com `reason_code` INATIVO → 42501.
9. overturn com `reason_code` NULL → 42501.

**B2 — Evidência MISMATCH (D5e) — 1**
10. accept com anexo `MISMATCH` → 42501 (bloqueado).

**Accept terminal (D8) — 3**
11. accept abaixo do limiar com code válido → terminal (`lives_ok`).
12. fato `DISPUTE_ACCEPTED` embute `reason_code`.
13. fila vira `rejected` + `resolution_reason_code` carimbado.

**Dual-control preservado (B1 / D7b) — 2**
14. overturn acima do limiar ainda forka p/ peer review (`lives_ok`).
15. fork mantém `OVERTURN` + `peer_review_reason_code` (Senior F5).

**Confirm embute reason_code (D7c) — 3**
16. accept acima do limiar forka.
17. 2º auditor distinto confirma o fork DISPUTE_ACCEPT (`lives_ok`).
18. fato terminal `DISPUTE_ACCEPTED` embute `reason_code` + 2ª assinatura.

**Retração — proveniência (INV-23 / D9 / D10) — 3**
19. retract sem `reason_code` → sucesso (não é financeiramente efetivo).
20. fila volta a `pending` e `disputed_by` NUNCA é limpo (INV-23).
21. fato `DISPUTE_RETRACTED` registra `original_disputed_by` + `retracted_by_user_id`.

**reject_sanction taxonomia — 4**
22. reject com `reason_code` inexistente → 42501.
23. reject abaixo do limiar com code válido → terminal.
24. fila vira `rejected` + `rejection_reason_code` carimbado.
25. fato `VERDICT_REFUSED` embute `reason_code`.

## Notas

- **B1 dropa assinaturas usadas por testes commitados** (807/809/812001/812003).
  Esses testes referenciam o contrato antigo (sem `reason_code`), que deixou de
  existir por design. Atualizados para a nova assinatura no mesmo ciclo (mudança
  de teste, não de migração — migrações continuam append-only).
- `ignore-regression` no cabeçalho: refactor aditivo de RPC (DROP+CREATE OR
  REPLACE), nenhum `.sql` mergeado modificado; fork dual-control verbatim de
  `20260812000003`. Council-approved.
- Mensagem genérica `'... rejected.'` + 42501 idêntica p/ wrong-org, not-found e
  taxonomia inválida (anti-oráculo, INV-26 / H5).
- Migração altera RPCs expostas à Data API → `supabase/types.database.ts`
  regenerado e commitado junto.
