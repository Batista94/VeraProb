# Plano de Teste — Correção de Políticas RLS de Justificativas (20260728000002)

Certifica as novas políticas de RLS das tabelas `contractor_justifications` e `justification_evidence_uploads` para garantir o isolamento multi-inquilino e assegurar que administradores e operadores possam cadastrar contestações de multas localmente.

---

## 🛠️ Cenários de Teste

### Cenário 1: Inserção de Justificativa com Papel TENANT_ADMIN (Org Alpha)
* **Objetivo:** Garantir que o administrador da Org Alpha possa inserir registros em `contractor_justifications` e visualizar apenas os seus próprios dados.
* **Usuário:** `admin-a@veraprob.dev` (JWT Claim `organization_id` = `00000000-0000-0000-0000-000000000001`, `role` = `TENANT_ADMIN`).
* **Ações:**
  1. Efetuar o reset e setup do banco local.
  2. Logar como `admin-a@veraprob.dev`.
  3. Clicar no botão **"SIMULAR OPERAÇÃO"** no painel de controle.
* **Resultado Esperado:** O seed executa com sucesso (sem erro RLS 42501) e insere as justificativas para a organização Alpha.

### Cenário 2: Isolamento de Inquilino (Invariante INV-22)
* **Objetivo:** Garantir que o administrador da Org Beta não consiga ver ou inserir justificativas no contexto da Org Alpha.
* **Usuário:** `admin-b@veraprob.dev` (JWT Claim `organization_id` = `00000000-0000-0000-0000-000000000002`, `role` = `TENANT_ADMIN`).
* **Resultado Esperado:** Ao tentar acessar ou consultar as justificativas da Org Alpha, o banco retorna um resultado vazio ou erro de acesso (isolamento estrito RLS).

---

## 🔍 Execução dos Testes Automatizados

Podemos rodar os testes pgTap do banco de dados para validar que nenhuma vulnerabilidade ou vazamento de RLS ocorra.
```bash
make test-db
```
