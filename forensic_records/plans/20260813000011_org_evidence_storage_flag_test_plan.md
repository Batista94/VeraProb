# Plano de Testes — org_evidence_storage_flag

**Migração:** `supabase/migrations/20260813000011_org_evidence_storage_flag.sql`
**Teste pgTAP:** `supabase/tests/20260813000011_org_evidence_storage_flag_test.sql`
**Invariantes:** INV-DB (ADD COLUMN com DEFAULT = instantâneo no PG11+; boolean
dispensa CHECK), INV-1 (coluna viaja na linha da org, escopo via RLS).
**Risco:** Baixo — uma única coluna booleana. Falha = gate de armazenamento não
materializa (org sem cota consome storage em silêncio) ou default errado
(`TRUE`) libera upload sem plano contratado.

## Objetivo

Adiciona `evidence_storage_enabled BOOLEAN NOT NULL DEFAULT FALSE` à
`organizations` (Componente 5.2). O default `FALSE` é **opt-in**: uma org nova
nunca consome cota de storage em silêncio; o painel de upload renderiza um gate
de plano claro até a flag ser ligada (out-of-band, por billing/suporte — nunca
pela UI do tenant). Sem grants novos: a coluna herda os grants existentes da
`organizations` (admin/auditor do tenant já fazem SELECT da própria org via RLS).

## Estratégia

Estrutural + comportamental, como `postgres` (superusuário) dentro de
`BEGIN/ROLLBACK`. RLS da `organizations` já coberto pela suíte própria da tabela
— aqui o foco é existência, tipo, nullability, default e legibilidade do flag
pelo tenant. Default verificado por inserção mínima (id, name, cnpj) e leitura.

## Casos pgTAP (plan = 6)

**Estrutura**
1. Coluna `evidence_storage_enabled` existe.
2. Tipo é `boolean` (`col_type_is`).
3. `NOT NULL` (`col_not_null`).

**Comportamento — default opt-in**
4. INSERT mínimo (sem a coluna) → flag = `FALSE` (default opt-in).
5. INSERT explícito `TRUE` → persiste `TRUE` (org com plano contratado).

**Legibilidade pelo tenant**
6. `authenticated` tem privilégio de SELECT na `organizations` (a flag é lida
   junto com a linha da org — sem grant novo).

## Notas

- ADD COLUMN com DEFAULT é instantâneo (PG11+); sem 3-passos pois boolean não
  precisa de CHECK NOT VALID → VALIDATE.
- DDL expõe nova coluna à Data API → `supabase/types.database.ts` regenerado e
  commitado junto (Row: `boolean`; Insert/Update: `boolean` opcional).
- A flag é somente-leitura pela trilha do tenant; a edição (billing/suporte) é
  fora do escopo deste pacote (5.2 entrega o gate, não o toggle).
