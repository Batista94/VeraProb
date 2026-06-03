# Plano de Testes UAT — 20260602000001_fix_rls_public_role_policies

**Migração:** `supabase/migrations/20260602000001_fix_rls_public_role_policies.sql`
**Invariantes de Segurança:** INV-1, INV-2, INV-3, INV-22, INV-26
**Risco:** Alto — Altera as políticas de RLS e regras de validação de INSERT em tabelas críticas voltadas a inquilinos (tenants).

---

## 📋 Visão Geral do Endurecimento

Este plano de testes de aceitação de usuário (UAT) valida o fechamento de brechas críticas de segurança relacionadas a políticas de Row-Level Security (RLS) associadas erroneamente ao escopo da role pública (`public`) ou com condições permissivas sempre verdadeiras (`USING(true)` ou `WITH CHECK(true)`). 

As correções implementadas visam garantir que:
1. **spatial_ref_sys (PostGIS):** Acesso de leitura revogado para as roles cliente (`anon` e `authenticated`) para mitigar enumeração de esquemas.
2. **Fim de Políticas "Always-True":** Remoção de políticas públicas permissivas sobre `idempotency_keys`, `telegram_chat_bindings`, `telegram_binding_tokens`, `justification_recomputation_signals` e `justification_submission_tokens`.
3. **Políticas Deny-All Restritivas:** Adição de barreiras `RESTRICTIVE` para impedir interações diretas de sessões autenticadas com as tabelas de uso exclusivo da API interna/bot (`telegram_pending_links` e `telegram_user_consents`).
4. **Isolamento de Escrita por Tenant (INV-1 & INV-22):** Substituição de permissões genéricas de inserção por regras restritas baseadas estritamente nas claims de organização do JWT de chamada.
5. **Sanidade dos Snapshots Financeiros:** Remoção de políticas obsoletas sempre verdadeiras em `contractual_financial_snapshot`.

---

## 🛠️ Pré-requisitos & Configuração de Ambiente

Antes de iniciar os testes manuais e de banco de dados, garanta a inicialização correta do ecossistema:

| Item | Comando / Ação | Estado Esperado |
|------|----------------|-----------------|
| Inicializar Supabase | `make setup` ou `supabase start` | Containers ativos e banco resetado com a migração aplicada |
| Aplicação Flutter | `make run` | Frontend rodando localmente no navegador |
| Massa de Dados Base | `supabase db reset` | Tabelas populadas através do `supabase/seed.sql` |

### 🔐 Credenciais de Teste (Inquilinos Isolados)

* **Inquilino A (Org Alpha):**
  * **E-mail:** `admin-a@veraprob.dev`
  * **Senha:** `veraprob123!`
  * **Org ID:** `00000000-0000-0000-0000-000000000001`
  * **JWT Claim Path:** `auth.jwt() ->> 'organization_id'` (ou via app_metadata)

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
4. **Checkpoint Visual:** Certifique-se de ser redirecionado com sucesso para o painel administrativo da **Org Alpha**. Nenhum erro visual ou de rede deve ser apresentado no console.

---

### Passo 2: Happy Path - Inserção de Dados Autenticados (UAT Funcional)

Para verificar que a nova política restrita de inserção não bloqueou as ações legítimas da aplicação Flutter:

1. No painel lateral, navegue até **"Fila Auditora"** (ou crie um evento que gere inserção em `sanction_review_queue` ou `shadow_verdicts`).
2. Execute a ação de selamento de veredito ou injeção de teste para gerar uma sanção:
   * Clique em **"Gerar Sanção de Teste"**.
3. Confirme que um card correspondente ao veredito foi gerado com sucesso.
4. **Validação no Banco de Dados:**
   Abra uma sessão no banco de dados e execute a consulta a seguir para garantir que o registro foi criado com o `organization_id` correto da Org Alpha:
   ```sql
   SELECT id, organization_id, contract_id, set_id 
   FROM public.sanction_review_queue 
   WHERE organization_id = '00000000-0000-0000-0000-000000000001'
   ORDER BY created_at DESC LIMIT 1;
   ```
   * **Resultado Esperado:** O registro inserido deve constar na tabela sob a propriedade da Org Alpha.

---

### Passo 3: Verificação de Banco de Dados e Ataques Adversários (UAT de Segurança)

Para simular e verificar as restrições e o isolamento a nível de banco de dados, execute as consultas manuais estruturadas como se fossem requisições vindo da API externa ou de um agente hostil.

Use o cliente SQL do Supabase Studio (`http://localhost:54323` por padrão) ou a ferramenta de sua escolha conectando com a role `authenticated`.

#### 🧪 Teste 3.1: Revogação de privilégios na tabela `spatial_ref_sys`
**Objetivo:** Garantir que usuários comuns não possam listar dados de referência espacial (PostGIS) diretamente por motivos de segurança.

> [!WARNING]
> **Instrução Crítica:** No Supabase Studio, TODO o bloco SQL (desde `BEGIN` até `ROLLBACK`) deve ser executado **como uma única query** (selecionar todo o texto e clicar "Run"). Executar statements individualmente causa o reset do role na sessão entre execuções.
> Como alternativa, recomendo a execução via **`psql` CLI** para total controle da transação:
> ```bash
> psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -c "
> BEGIN;
> SET LOCAL ROLE authenticated;
> SET LOCAL request.jwt.claims = '{\"role\":\"authenticated\",\"sub\":\"00000000-0000-0000-0000-000000000002\",\"organization_id\":\"00000000-0000-0000-0000-000000000001\"}';
> SELECT * FROM public.spatial_ref_sys LIMIT 5;
> ROLLBACK;
> "
> ```

**Instruções de execução:**
```sql
-- Simula um usuário autenticado da aplicação (Selecione todo o bloco e clique em "Run")
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"00000000-0000-0000-0000-000000000002","organization_id":"00000000-0000-0000-0000-000000000001"}';

-- Tenta selecionar da tabela espacial
SELECT * FROM public.spatial_ref_sys LIMIT 5;
ROLLBACK;
```
* **Resultado Esperado:** O Postgres deve lançar um erro explícito de violação de privilégio:
  `ERROR:  permission denied for table spatial_ref_sys`
* **Validação Inversa:** Repita o teste definindo a role para `service_role`. A consulta deve funcionar normalmente para processos internos e de sistema.

---

#### 🧪 Teste 3.2: Tentativa de Ataque Cross-Tenant via Injeção de Escrita (INV-22)
**Objetivo:** Confirmar que a nova regra `WITH CHECK` impede o Inquilino A de injetar dados na conta do Inquilino B.

> [!WARNING]
> **Instrução Crítica:** Execute todo o bloco SQL a seguir de uma única vez no Supabase Studio para evitar reset de sessão e role.
> Ou via **`psql` CLI**:
> ```bash
> psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -c "
> BEGIN;
> SET LOCAL ROLE authenticated;
> SET LOCAL request.jwt.claims = '{\"role\":\"authenticated\",\"sub\":\"11111111-1111-1111-1111-111111111111\",\"organization_id\":\"00000000-0000-0000-0000-000000000001\"}';
> INSERT INTO public.sanction_review_queue (organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence) VALUES ('00000000-0000-0000-0000-000000000002', gen_random_uuid(), 'set_attack_01', 'contract_attack_01', '{\"status\": \"tampered\"}'::jsonb);
> ROLLBACK;
> "
> ```

**Instruções de execução:**
```sql
BEGIN;
-- Define a sessão simulada do Inquilino A
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"11111111-1111-1111-1111-111111111111","organization_id":"00000000-0000-0000-0000-000000000001"}';

-- Tenta inserir dados pertencentes ao Inquilino B (Org Beta: 00000000-0000-0000-0000-000000000002)
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
* **Resultado Esperado:** A tentativa de inserção cruzada deve ser sumariamente bloqueada com o erro:
  `ERROR:  new row violates row-level security policy for table "sanction_review_queue"`

---

#### 🧪 Teste 3.3: Bloqueio de Escrita em Tabelas Exclusivas do Bot (Restrições Deny-All)
**Objetivo:** Garantir que usuários comuns não possam criar ou alterar dados do fluxo interno do Telegram, como consentimentos de usuários e links pendentes de ativação.

> [!WARNING]
> **Instrução Crítica:** Execute todo o bloco SQL de uma vez só ou via `psql` CLI:
> ```bash
> psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -c "
> BEGIN;
> SET LOCAL ROLE authenticated;
> SET LOCAL request.jwt.claims = '{\"role\":\"authenticated\",\"sub\":\"11111111-1111-1111-1111-111111111111\",\"organization_id\":\"00000000-0000-0000-0000-000000000001\"}';
> INSERT INTO public.telegram_pending_links (short_id, organization_id, evidence_upload_id, execution_set_id, driver_id, expires_at_utc) VALUES ('ABCD1234', '00000000-0000-0000-0000-000000000001', gen_random_uuid(), 'set_attack_01', gen_random_uuid(), NOW() + INTERVAL '1 hour');
> ROLLBACK;
> "
> ```

**Instruções de execução:**
```sql
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"11111111-1111-1111-1111-111111111111","organization_id":"00000000-0000-0000-0000-000000000001"}';

-- Tenta inserir um link pendente com as colunas reais da tabela
INSERT INTO public.telegram_pending_links (
  short_id,
  organization_id,
  evidence_upload_id,
  execution_set_id,
  driver_id,
  expires_at_utc
) VALUES (
  'ABCD1234', -- short_id deve ter exatamente 8 caracteres
  '00000000-0000-0000-0000-000000000001',
  gen_random_uuid(),  -- gera UUID temporário para simular upload id (RLS rejeita antes de verificar a FK)
  'set_attack_01',
  gen_random_uuid(),
  NOW() + INTERVAL '1 hour'
);
ROLLBACK;
```
* **Resultado Esperado:** Bloqueado pela política `RESTRICTIVE` da tabela:
  `ERROR:  new row violates row-level security policy for table "telegram_pending_links"`

---

#### 🧪 Teste 3.4: Remoção de Políticas Antigas e "Always-True"
**Objetivo:** Auditar os metadados do Postgres para certificar que nenhuma política permissiva indesejada restou ativa nas tabelas auditadas.

**Instruções de execução:**
```sql
-- Busca por políticas que permitam acesso irrestrito para roles comuns (cast explicitos para tipos compatíveis)
SELECT tablename, policyname, roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND (qual = 'true' OR with_check = 'true')
  AND (roles::text[] && ARRAY['public','authenticated']::text[] OR roles::text = '{}')
  AND tablename IN (
    'idempotency_keys', 
    'telegram_chat_bindings', 
    'telegram_pending_links', 
    'telegram_user_consents', 
    'telegram_binding_tokens',
    'justification_recomputation_signals',
    'justification_submission_tokens',
    'contractual_financial_snapshot'
  );
```
* **Resultado Esperado:** A consulta deve retornar **EXATAMENTE 0 linhas**. Caso alguma linha seja retornada, significa que ainda existe uma política permissiva ativa que anula a segurança do RLS.

---

## 🤖 Automação de Testes pgTAP

Para execução determinística e validação contínua da cobertura desse endurecimento (em CI/CD e ambientes de desenvolvimento local):

Execute o script de automação:
```bash
make test-db
```

Os testes mapeados em [20260602000001_fix_rls_public_role_policies_test.sql](file:///C:/Users/wes_b/Projects/VeraProb/supabase/tests/20260602000001_fix_rls_public_role_policies_test.sql) verificam programmaticamente:
- A remoção de todas as 15 antigas políticas especificadas.
- Presença das 2 políticas restritivas do Telegram.
- Comando e restrições de papéis (`roles`) para as novas políticas de inserção.
- O isolamento comportamental de Tenants nas tabelas `sanction_review_queue` e `shadow_verdicts`.

---

## 📊 Matriz de Aceitação UAT

Use esta matriz para auditar e assinar o plano UAT:

| Cód | Validação UAT | Comportamento Esperado | Status |
|:---|:---|:---|:---:|
| **UAT-01** | Login com credenciais válidas do Inquilino A | Redirecionamento correto para o dashboard com sessão autenticada estabelecida | `[ ]` |
| **UAT-02** | Happy Path: Inserção de dados legítimos da Org Alpha | Dados salvos com `organization_id` da Org Alpha sem disparar RLS errors | `[ ]` |
| **UAT-03** | Blindagem: Consulta à tabela `spatial_ref_sys` por usuário comum | Acesso negado com erro de privilégio no Postgres | `[ ]` |
| **UAT-04** | Injeção Adversária: Escrita de dados cross-tenant (Org A -> Org B) | Bloqueio imediato pelo banco de dados com erro de RLS (INV-22) | `[ ]` |
| **UAT-05** | Acesso ao Bot: Tentativa de inserção em tabelas privadas do Telegram | Bloqueado preventivamente por políticas RESTRICTIVE | `[ ]` |
| **UAT-06** | Auditoria Interna: Consulta a políticas públicas sempre verdadeiras | Nenhuma regra vulnerável encontrada na lista de `pg_policies` | `[ ]` |
| **UAT-07** | Execução de Testes Automatizados da Camada de Dados | Sucesso em todos os testes contidos na suíte do pgTAP | `[ ]` |

---

## 🔄 Plano de Rollback

Caso o endurecimento de segurança cause efeitos colaterais severos em produção ou bloqueie fluxos legítimos do aplicativo Flutter:

1. **Ação Rápida:** Reverta temporariamente as políticas restaurando a migração anterior ou ajustando as regras sob council.
2. **Inspeção de Claims:** Se os erros de RLS persistirem para usuários legítimos, verifique se a claim do JWT correspondente ao inquilino está utilizando o caminho correto:
   * Mapeamento de claim em `sanction_review_queue`: `(auth.jwt() ->> 'organization_id')::uuid`
   * Mapeamento de claim em outras tabelas: `(auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid`
3. **Log de Diagnóstico:** Consulte os logs de auditoria do Postgres para correlacionar o `sub` e a claim do token JWT enviado na requisição com o `organization_id` do registro problemático.

