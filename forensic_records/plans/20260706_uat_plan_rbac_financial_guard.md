# Plano de Teste de Aceitação (UAT) - Execução via Agente de IA

> [!IMPORTANT]
> **Instrução ao Agente Testador:** Este plano foi desenhado para ser executado de forma autônoma. Você deve utilizar seu `MCP de Playwright` para iterar com a UI e seu `MCP de Postgres` para validar as regras sistêmicas de banco de dados e a tríade CIA. Siga os passos e seletores literalmente.

## Fase 0: Autenticação Inicial e Setup (População Mínima)

**Objetivo:** Autenticar-se no sistema e garantir que o ambiente possui os dados necessários para os testes (contratos, sanções na fila, limites configurados).

1. **Ação UI (Playwright - Login):**
   - Navegar até a página de Login.
   - Preencher o campo de E-mail com: `admin-a@veraprob.dev`
   - Preencher o campo de Senha com: `123456`
   - Clicar no botão de Entrar/Login.
2. **Ação UI (Playwright - População):** 
   - Na página inicial (Dashboard), localizar e clicar no botão com o rótulo exato: `"SIMULAR OPERAÇÃO"`.
   - Aguardar a conclusão do processo de população.
3. **Validação DB (Postgres MCP):**
   - Executar query: `SELECT * FROM tenant_roles WHERE is_system = true;` -> **Observar:** Validar se os papéis de sistema foram populados.
   - Executar query: `SELECT * FROM financial_guard_cap_columns;` -> **Observar:** Garantir que limites financeiros iniciais dos contratos foram criados.

## Fase 1: Teste a Fogo - Criação e Atribuição de Acessos (RBAC)

**Objetivo:** Validar a experiência (UI/UX) da criação de um papel e se a persistência no banco atende à tríade CIA.

### 1.1 Criar Papel Customizado
1. **Ação UI (Playwright):**
   - Navegar para o Hub de Configurações e clicar na aba `"Acessos & Perfis"`.
   - Clicar no botão `"Novo"` (Tooltip: `"Novo Perfil de Acesso"`).
   - Preencher o input `"Nome do Perfil"` com o valor exato: `Auditor Financeiro Restrito`.
   - Na lista de permissões, procurar pelo módulo `FINANCEIRO`.
   - Clicar na checkbox da permissão `Aprovar Sanções`.
   - Clicar no *ExpansionTile* `"Restringir a recursos — Sem restrição (todo o tenant)"` e selecionar apenas o primeiro contrato da lista (para testar o *ABAC-lite*).
   - Clicar em `"Salvar"`.
2. **Validação DB (Postgres MCP):**
   - Executar: `SELECT * FROM tenant_roles WHERE name = 'Auditor Financeiro Restrito';`
   - **Observar:** Pegar o `id` da role criada. Verificar se foi persistida.
   - Executar: `SELECT * FROM tenant_role_permissions WHERE role_id = '<id_da_role>';`
   - **Observar:** Verificar se as permissões e o escopo de contrato (array/json) estão corretos.

### 1.2 Atribuir Papel ao Usuário
1. **Ação UI (Playwright):**
   - Navegar para a aba `"Gestão de Equipe"`.
   - Localizar um usuário de teste (que não seja o administrador atual).
   - Na linha deste usuário, clicar no botão *ActionChip* `"Perfil"` (que possui o ícone `+`).
   - Selecionar o papel `Auditor Financeiro Restrito` e confirmar.
2. **Validação DB (Postgres MCP):**
   - Executar: `SELECT * FROM tenant_user_roles WHERE user_id = '<id_do_usuario_teste>';`
   - **Observar:** Confirmar que o `role_id` foi associado ao usuário.

## Fase 2: Validação da CIA e Revogação em Tempo Real (Live Check)

**Objetivo:** Garantir a Confidencialidade (acesso negado) e Disponibilidade imediata (queda/bloqueio imediato da sessão em caso de downgrade).

1. **Ação UI (Playwright - Browser 2 / Sessão 2):**
   - O agente deve abrir uma segunda instância do navegador e logar como o usuário teste (Auditor Financeiro Restrito).
   - Navegar para a aba do módulo Financeiro/Sanções. **Observar:** A página deve abrir normalmente.
2. **Ação UI (Playwright - Browser 1 / Admin da Org A):**
   - Voltar à tela de `"Gestão de Equipe"`.
   - Na linha do usuário teste, clicar no botão de apagar (`delete icon`) no *Chip* do papel `"Auditor Financeiro Restrito"`. Isso revoga o acesso.
3. **Ação UI (Playwright - Browser 2 / Sessão 2):**
   - Tentar realizar alguma ação na tela logada (ex: clicar em qualquer botão) ou atualizar a página.
   - **Observar (Confidencialidade):** O agente deve verificar se o usuário foi deslogado automaticamente OU se a UI ocultou imediatamente a visualização via `PermissionGate`, emitindo um alerta de "Acesso Negado".
4. **Validação DB (Postgres MCP):**
   - Executar: `SELECT * FROM auth.users WHERE id = '<id_do_usuario_teste>';` (Acessível via MCP apenas se admin DB). Verificar atualizações de versão de JWT ou tokens revogados (trigger edge function `revoke_sessions`).

## Fase 3: Proteção Financeira e Vereditos (Financial Guard)

**Objetivo:** Testar se o motor impede que sanções ultrapassem o teto de um contrato (Integridade Financeira).

1. **Ação UI (Playwright - Admin da Org A):**
   - Navegar para a aba da Fila de Auditoria (Auditor Queue).
   - Selecionar um item da fila (Sanção) cujo valor seja maior que o teto permitido (o Teto será visível no card superior do contrato).
   - Clicar em `"Aprovar Sanção"` ou botão de veredito equivalente.
2. **Validação UI (Playwright):**
   - O sistema deve processar. Abra os detalhes desta sanção.
   - **Observar:** No componente `SanctionVerdictCard` (na tela), deve haver um indicativo claro (badge/texto) de que o valor foi *"Limitado pelo Teto do Contrato"* (Cap aplicado). O valor final da sanção deve ser menor que o original, respeitando o cap.
3. **Validação DB (Postgres MCP):**
   - **Garantia de Append-Only (Integridade):** Consultar `financial_guard_reconcile` e `financial_guard_accrual_tables`.
   - `SELECT amount, capped_amount FROM financial_guard_accrual_tables WHERE sanction_id = '<id>';`
   - **Observar:** O `capped_amount` deve conter o valor exato cortado no teto contratual, e NENHUM UPDATE ou DELETE deve ter ocorrido em registros anteriores (verificar timestamps transacionais).

## Fase 4: Isolamento de Organização (Validação de Vazamento de Tenant)

**Objetivo:** Garantir que NENHUM dado da Organização A vaze para a Organização B (Confidencialidade estrita via Row Level Security - RLS).

1. **Ação UI (Playwright - Logout da Org A):**
   - No painel/layout principal (Admin Layout), localizar o botão de ícone de logout (geralmente uma porta com uma seta - `Icons.logout_rounded`).
   - Você pode localizá-lo pelo **Tooltip exato:** `"Sair"`.
   - Clicar no botão `"Sair"`.
   - Aguardar o redirecionamento para a tela de Login.
2. **Ação UI (Playwright - Login na Org B):**
   - Preencher o campo de E-mail com: `admin-b@veraprob.dev`
   - Preencher o campo de Senha com: `123456`
   - Clicar em Entrar/Login.
3. **Validação UI e DB (Playwright e Postgres MCP):**
   - Navegar para a aba `"Acessos & Perfis"`. **Observar:** O papel `"Auditor Financeiro Restrito"` criado na Fase 1 **NÃO PODE** estar visível para a Org B.
   - Navegar para `"Gestão de Equipe"`. **Observar:** O usuário de teste da Org A não deve aparecer na lista.
   - MCP Postgres: Realizar um select via Data API simulando a role autenticada da Org B. Confirmar que as querys retornam vazias para os IDs pertencentes à Org A, atestando o funcionamento das políticas de RLS.

## Fase 5: Clean Code e Bugs Visuais

- Durante todos os passos de UI, o agente deve capturar `screenshots` via Playwright de modais, de tabelas e da tela `"Acessos & Perfis"`.
- **Observar:** Verificar se não há bugs de sobreposição de elementos em telas menores (RenderFlex overflow) e garantir que as cores de contraste estão respeitando o Tema Dark (ex: sem textos brancos apagados sobre fundos claros).
