# Plano de Testes UAT — 20260602000001_fix_rls_public_role_policies

**Migração:** `supabase/migrations/20260602000001_fix_rls_public_role_policies.sql`
**Invariantes de Segurança:** INV-1, INV-2, INV-3, INV-22, INV-26
**Risco:** Alto — Altera políticas de RLS e regras de validação de INSERT em tabelas críticas voltadas a inquilinos (tenants).

> [!NOTE]
> **Revisão pós-execução (estado atual validado).** Este plano foi reconciliado com o comportamento real do banco. Duas premissas do plano original estavam incorretas e foram corrigidas aqui:
>
> 1. **`spatial_ref_sys` não é revogável por migração.** A tabela pertence a `supabase_admin`; a role de migração (`postgres`) não é superuser nem membro de `supabase_admin`, então o `REVOKE` é um **no-op** (emite `WARNING 01006`). A leitura por `anon`/`authenticated` **permanece** — o resultado esperado é **sucesso**, não `permission denied`. A tabela contém apenas dados geodésicos públicos (`srid`, `srtext`, `proj4text`), **sem `organization_id`**, logo não há vazamento de tenant (INV-22 intacto).
> 2. **Regressões posteriores foram fechadas em `20260804000001`.** As migrações `20260614000001` e `20260616000001` reintroduziram políticas always-true (`tpl_service_all`, `tsq_insert_service`) e um grant `anon`, reabrindo um vetor cross-tenant **anon** (CRÍTICO) em `telegram_pending_links`. A migração de re-endurecimento `20260804000001_reharden_rls_always_true_regressions.sql` corrige isso, com guard permanente `supabase/tests/inv22_always_true_policy_invariant_test.sql`. Os resultados esperados abaixo já refletem o estado pós-`20260804000001`.

---

## 📋 Visão Geral do Endurecimento

Este plano de aceitação (UAT) valida o fechamento de brechas de RLS associadas erroneamente ao escopo da role pública (`public`) ou com condições permissivas sempre verdadeiras (`USING(true)` / `WITH CHECK(true)`).

Garantias após `20260602000001` **+** `20260804000001`:

1. **`spatial_ref_sys` (PostGIS):** leitura **não** revogável via migração (no-op). Risco residual = enumeração de SRID público, sem dados de tenant. Mitigação efetiva é de plataforma (`supabase_admin`), rastreada à parte.
2. **Fim de políticas "always-true":** remoção das políticas públicas permissivas sobre `idempotency_keys`, `telegram_chat_bindings`, `telegram_binding_tokens`, `justification_recomputation_signals`, `justification_submission_tokens` e — via `20260804000001` — `tpl_service_all` (`telegram_pending_links`) e `tsq_insert_service` (`telegram_status_queries`).
3. **Políticas deny-all restritivas:** barreiras `RESTRICTIVE` impedem interações diretas de sessões `authenticated` **e** `anon` com tabelas de uso exclusivo da API interna/bot (`telegram_pending_links`, `telegram_user_consents`).
4. **Isolamento de escrita por tenant (INV-1 & INV-22):** permissões genéricas de inserção substituídas por regras restritas às claims de organização do JWT.
5. **Sanidade dos snapshots financeiros:** remoção de políticas obsoletas always-true em `contractual_financial_snapshot`.

---

## 🛠️ Pré-requisitos & Configuração de Ambiente

| Item | Comando / Ação | Estado Esperado |
|------|----------------|-----------------|
| Inicializar Supabase | `make setup` ou `supabase start` | Containers ativos, banco resetado com migrações aplicadas |
| Aplicar migrações | `supabase migration up` | Inclui `20260804000001` (re-endurecimento) |
| Aplicação Flutter | `make run` | Frontend rodando localmente no navegador |
| Massa de Dados Base | `supabase db reset` | Tabelas populadas via `supabase/seed.sql` |

### 🔐 Credenciais de Teste (Inquilinos Isolados)

* **Inquilino A (Org Alpha):**
  * **E-mail:** `admin-a@veraprob.dev`
  * **Senha:** `veraprob123!`
  * **Org ID:** `00000000-0000-0000-0000-000000000001`
  * **JWT Claim Path:** `auth.jwt() ->> 'organization_id'` (ou via `app_metadata`)

* **Inquilino B (Org Beta):**
  * **E-mail:** `admin-b@veraprob.dev`
  * **Senha:** `veraprob123!`
  * **Org ID:** `00000000-0000-0000-0000-000000000002`

---

## 🚀 Passo a Passo Completo do Fluxo UAT

### Passo 1: Login e Autenticação na Aplicação

1. Abra a aplicação VeraProb no navegador (`http://localhost:<porta>`).
2. Na tela de login, insira as credenciais do **Inquilino A**:
   * E-mail: `admin-a@veraprob.dev`
   * Senha: `veraprob123!`
3. Clique em **Entrar**.
4. **Checkpoint Visual:** redirecionamento ao painel da **Org Alpha**. Nenhum erro visual ou de rede no console.

---

### Passo 2: Happy Path — Inserção de Dados Autenticados (UAT Funcional)

Verifica que a política restrita de inserção não bloqueou ações legítimas da aplicação Flutter:

1. No painel lateral, navegue até **"Fila Auditora"**.
2. Clique em **"Gerar Sanção de Teste"** para gerar uma sanção.
3. Confirme que um card correspondente ao veredito foi gerado.
4. **Validação no Banco:**

   ```sql
   SELECT id, organization_id, contract_id, set_id
   FROM public.sanction_review_queue
   WHERE organization_id = '00000000-0000-0000-0000-000000000001'
   ORDER BY created_at DESC LIMIT 1;
   ```

   * **Resultado Esperado:** o registro inserido consta sob a propriedade da Org Alpha.

---

### Passo 3: Verificação de Banco e Ataques Adversários (UAT de Segurança)

Use o cliente SQL do Supabase Studio (`http://localhost:54323`) ou `psql`. Execute cada bloco **inteiro** (de `BEGIN` a `ROLLBACK`) de uma só vez — executar statements isolados reseta o role da sessão.

#### 🧪 Teste 3.1: `spatial_ref_sys` — leitura permanece (no-op de REVOKE)

**Objetivo:** documentar o comportamento real — a leitura **não** é bloqueada por esta migração.

```sql
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"00000000-0000-0000-0000-000000000002","organization_id":"00000000-0000-0000-0000-000000000001"}';

SELECT * FROM public.spatial_ref_sys LIMIT 5;
ROLLBACK;
```

* **Resultado Esperado:** a consulta **retorna linhas** (sucesso). O `REVOKE` da migração é um no-op porque `spatial_ref_sys` pertence a `supabase_admin` e a role `postgres` não pode revogar grants de outro concedente.
* **Por que é aceitável (INV-22):** a tabela só contém referência geodésica pública (`srid`, `auth_name`, `srtext`, `proj4text`) — **sem `organization_id`, sem dado de tenant**. Não há vazamento entre inquilinos.
* **Validação adicional (sem coluna de tenant):**

  ```sql
  SELECT count(*) FROM information_schema.columns
  WHERE table_schema='public' AND table_name='spatial_ref_sys' AND column_name='organization_id';
  -- Esperado: 0
  ```

---

#### 🧪 Teste 3.2: Ataque Cross-Tenant via Injeção de Escrita (INV-22)

**Objetivo:** confirmar que `WITH CHECK` impede o Inquilino A de injetar dados na conta do Inquilino B.

```sql
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"11111111-1111-1111-1111-111111111111","organization_id":"00000000-0000-0000-0000-000000000001"}';

INSERT INTO public.sanction_review_queue (
  organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence
) VALUES (
  '00000000-0000-0000-0000-000000000002', -- Org B ID
  gen_random_uuid(),
  'set_attack_01',
  'contract_attack_01',
  '{"status": "tampered"}'::jsonb
);
ROLLBACK;
```

* **Resultado Esperado:** bloqueado —
  `ERROR:  new row violates row-level security policy for table "sanction_review_queue"`

---

#### 🧪 Teste 3.3: Bloqueio de Escrita em Tabela Exclusiva do Bot (Deny-All)

**Objetivo:** garantir que `authenticated` **e** `anon` não escrevem em `telegram_pending_links`.

**3.3a — sessão `authenticated` (bloqueada por deny-all RESTRICTIVE):**

```sql
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"11111111-1111-1111-1111-111111111111","organization_id":"00000000-0000-0000-0000-000000000001"}';

INSERT INTO public.telegram_pending_links (
  short_id, organization_id, evidence_upload_id, execution_set_id, driver_id, expires_at_utc
) VALUES (
  'ABCD1234', '00000000-0000-0000-0000-000000000001',
  gen_random_uuid(), 'set_attack_01', gen_random_uuid(), NOW() + INTERVAL '1 hour'
);
ROLLBACK;
```

* **Resultado Esperado:**
  `ERROR:  new row violates row-level security policy for table "telegram_pending_links"`

**3.3b — sessão `anon` (vetor CRÍTICO fechado em `20260804000001`):**

```sql
BEGIN;
SET LOCAL ROLE anon;
SELECT * FROM public.telegram_pending_links LIMIT 1;
ROLLBACK;
```

* **Resultado Esperado:**
  `ERROR:  permission denied for table telegram_pending_links`
  (grant `anon` revogado + deny-all RESTRICTIVE para `anon`). Antes de `20260804000001`, esta consulta retornava linhas cross-tenant.

---

#### 🧪 Teste 3.4: Ausência de Políticas Always-True (Auditoria de Metadados)

**Objetivo:** certificar que nenhuma política permissiva always-true restou ativa nas tabelas auditadas.

```sql
SELECT tablename, policyname, roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND permissive = 'PERMISSIVE'
  AND (qual = 'true' OR with_check = 'true')
  AND (roles::text[] && ARRAY['public','authenticated','anon']::text[] OR roles::text = '{}')
  AND tablename IN (
    'idempotency_keys',
    'telegram_chat_bindings',
    'telegram_pending_links',
    'telegram_user_consents',
    'telegram_binding_tokens',
    'telegram_status_queries',
    'justification_recomputation_signals',
    'justification_submission_tokens',
    'contractual_financial_snapshot'
  );
```

* **Resultado Esperado:** **EXATAMENTE 0 linhas.** Qualquer linha indica política permissiva ativa anulando o RLS.
* **Nota:** na execução original retornava 1 linha (`tpl_service_all`, reintroduzida por `20260614000001`). Corrigido por `20260804000001`; o guard permanente `inv22_always_true_policy_invariant_test.sql` impede recorrência em CI.

---

#### 🧪 Teste 3.5: `tsq_insert_service` reescopado a `service_role`

**Objetivo:** confirmar que a política de INSERT de `telegram_status_queries` não está mais exposta a `public`.

```sql
SELECT roles::text
FROM pg_policies
WHERE schemaname='public' AND tablename='telegram_status_queries' AND policyname='tsq_insert_service';
```

* **Resultado Esperado:** `{service_role}`.

---

## 🤖 Automação de Testes pgTAP

Para validação determinística e contínua (CI/CD e local):

```bash
make test-db
```

Cobertura relevante:

* `20260602000001_fix_rls_public_role_policies_test.sql` — políticas removidas + deny-all + isolamento de INSERT por tenant (`sanction_review_queue`, `shadow_verdicts`).
* `20260804000001_reharden_rls_always_true_regressions_test.sql` — fechamento das regressões (`tpl_service_all` removida, `anon` revogado, `tsq_insert_service` em `service_role`).
* `inv22_always_true_policy_invariant_test.sql` — **guard permanente** (scan de `pg_policies` independente de timestamp) + ausência de coluna de tenant em `spatial_ref_sys`.

**Estado atual:** `Result: PASS` (410 testes).

---

## 📊 Matriz de Aceitação UAT

| Cód | Validação UAT | Comportamento Esperado | Status |
|:----|:--------------|:-----------------------|:------:|
| **UAT-01** | Login com credenciais válidas do Inquilino A | Redirecionamento ao dashboard com sessão autenticada | `[ ]` |
| **UAT-02** | Happy Path: inserção legítima da Org Alpha | Dados salvos com `organization_id` da Org Alpha, sem erro de RLS | `[ ]` |
| **UAT-03** | `spatial_ref_sys` por usuário comum | **Sucesso** (leitura não revogável; tabela sem dado de tenant) | `[ ]` |
| **UAT-04** | Injeção cross-tenant (Org A → Org B) | Bloqueio imediato por RLS (INV-22) | `[ ]` |
| **UAT-05** | Escrita do bot por `authenticated` em `telegram_pending_links` | Bloqueado por política RESTRICTIVE | `[ ]` |
| **UAT-06** | Leitura por `anon` em `telegram_pending_links` | `permission denied` (grant revogado em `20260804000001`) | `[ ]` |
| **UAT-07** | Auditoria de políticas always-true | 0 linhas | `[ ]` |
| **UAT-08** | `tsq_insert_service` reescopado | `{service_role}` | `[ ]` |
| **UAT-09** | Suíte pgTAP completa | `make test-db` → PASS (410) | `[ ]` |

---

## 🔄 Plano de Rollback

Caso o endurecimento bloqueie fluxos legítimos do aplicativo:

1. **Ação rápida:** criar nova migração forward restaurando a política específica (append-only; **nunca** editar migração merged) — porém isso reabre o vetor `anon` crítico e seria bloqueado pelo guard `inv22_always_true_policy_invariant_test.sql` + regra de scanner `ALWAYS-TRUE-RLS-POLICY`.
2. **Inspeção de claims:** se erros de RLS persistirem para usuários legítimos, verifique o caminho da claim do JWT:
   * `sanction_review_queue`: `(auth.jwt() ->> 'organization_id')::uuid`
   * Demais tabelas: `(auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid`
3. **Log de diagnóstico:** correlacione `sub` e claim do token com o `organization_id` do registro problemático.
