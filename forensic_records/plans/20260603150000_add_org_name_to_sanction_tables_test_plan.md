# Plano de Testes UAT — 20260603150000_add_org_name_to_sanction_tables

**Migração:** `supabase/migrations/20260603150000_add_org_name_to_sanction_tables.sql`
**Invariantes de Segurança:** INV-1, INV-3, INV-DB
**Risco:** Baixo — Adiciona colunas e triggers de conveniência operacional para auto-popular o nome da organização sem alterar a lógica de segurança de RLS.

---

## 📋 Visão Geral

Este plano de testes valida a inclusão da coluna `organization_name` nas tabelas `sanction_review_queue` e `sanction_escalation_log`, garantindo que:
1. A nova coluna seja criada corretamente.
2. Triggers `BEFORE INSERT` busquem de forma automatizada o nome da organização a partir da tabela `organizations` usando o `organization_id`.
3. Os registros existentes sejam populados retroativamente (backfill).
4. O trigger de segurança que impede atualizações em `sanction_escalation_log` continue funcionando após o backfill.

---

## 🚀 Passo a Passo do Fluxo UAT

### Passo 1: Execução dos Testes Automatizados (pgTAP)
1. Execute os testes unitários do banco de dados utilizando a ferramenta pgTAP integrada ao projeto:
   ```bash
   make test-db
   ```
2. **Resultado Esperado:** Todos os testes pgTAP devem passar, incluindo as novas asserções de validação de coluna, trigger e backfill contidas no arquivo `20260603150000_add_org_name_to_sanction_tables_test.sql`.

---

### Passo 2: Verificação de Comportamento dos Triggers no Banco de Dados
Para simular a inserção e testar manualmente a auto-população, execute a seguinte query no Supabase Studio:

```sql
BEGIN;

-- 1. Cria uma organização de teste
INSERT INTO public.organizations (id, name, cnpj)
VALUES (
  'd0000000-0000-0000-0000-00000000000d',
  'Empresa Teste Trigger S.A.',
  '99.999.999/0001-99'
);

-- 2. Insere na fila de sanções (sem preencher organization_name)
INSERT INTO public.sanction_review_queue (
  organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence
) VALUES (
  'd0000000-0000-0000-0000-00000000000d',
  gen_random_uuid(),
  'set_manual_test_1',
  'contract_manual_test_1',
  '{}'::jsonb
);

-- 3. Insere no log de escalações (sem preencher organization_name)
INSERT INTO public.sanction_escalation_log (
  organization_id, escalation_reason, old_risk_index, new_risk_index, is_resolved
) VALUES (
  'd0000000-0000-0000-0000-00000000000d',
  'Escalação de Teste Manual',
  2,
  8,
  false
);

-- 4. Valida se os nomes foram preenchidos de forma correta
SELECT organization_id, organization_name 
FROM public.sanction_review_queue 
WHERE set_id = 'set_manual_test_1';

SELECT organization_id, organization_name 
FROM public.sanction_escalation_log 
WHERE escalation_reason = 'Escalação de Teste Manual';

ROLLBACK;
```

**Resultado Esperado:** 
Ambas as consultas SELECT devem retornar `'Empresa Teste Trigger S.A.'` na coluna `organization_name`, comprovando que o trigger efetuou a busca com sucesso.

---

### Passo 3: Verificação de Immutabilidade
Garantir que a tabela `sanction_escalation_log` permaneça append-only (bloqueando UPDATEs normais):

```sql
BEGIN;

-- Tenta efetuar um UPDATE comum no log de escalação
UPDATE public.sanction_escalation_log
SET escalation_reason = 'Tentativa maliciosa de update'
WHERE organization_id = '00000000-0000-0000-0000-000000000001';

ROLLBACK;
```

**Resultado Esperado:** O banco de dados deve rejeitar o UPDATE com a mensagem de erro da trigger de immutabilidade (`trg_sel_no_update`).
