# Plano de Teste de Aceitação (UAT) Hardened — RBAC & Financial Guard
Este plano de testes foi revisado e corrigido com base no codebase real da VeraProb (Hardened Tier-1). Ele detalha os seletores, rotas, tabelas e lógicas exatas para validação de aceitação.

---

## Fase 0: Setup e Isolamento Base

### 1. Login (UI Playwright)
*   **Rota:** `/login` (Roteia para `AdminLockScreen`).
*   **Ações na UI:**
    *   Preencher o input de E-mail (`TextField` com rótulo exato: `"E-mail Corporativo"`) com: `admin-a@veraprob.dev`
    *   Preencher o input de Senha (`TextField` com rótulo exato: `"Senha de Acesso"`) com: `123456`
    *   Clicar no botão principal (`ElevatedButton` com texto exato: `"ACESSAR SISTEMA"`).
*   **Resultado esperado:** Redirecionamento bem-sucedido para `/admin/dashboard`.

### 2. Setup Financeiro (Postgres MCP / SQL Local)
*   **Ações DB:**
    *   Localizar o contrato ativo da Organização Alpha (Org A) na tabela `public.contracts`.
    *   *Nota:* O ID da Org A é `'00000000-0000-0000-0000-000000000001'` e o ID do contrato do bootstrap é `'00000000-0000-0000-0000-ca0000000001'`.
    *   Executar o seguinte comando SQL para definir um limite baixo (ex: 500 centavos = R$ 5,00) a fim de simular o estouro rapidamente:
        ```sql
        UPDATE public.contracts 
        SET monthly_penalty_cap_cents = 500 
        WHERE id = '00000000-0000-0000-0000-ca0000000001';
        ```
*   **Validação DB:**
        ```sql
        SELECT id, name, monthly_penalty_cap_cents 
        FROM public.contracts 
        WHERE id = '00000000-0000-0000-0000-ca0000000001';
        ```
*   **Popular Dados de Simulação (UI Playwright):**
    *   Na tela inicial (`/admin/dashboard`), clicar no botão com texto exato: `"SIMULAR OPERAÇÃO"` (Rótulo: `"SIMULAR OPERAÇÃO"`).
    *   Aguardar a notificação de confirmação ("Dados de teste inseridos.").

---

## Fase 1: Criação de Perfil e Fila Four-Eyes (RBAC)

### 1. Criar Perfil Customizado com Permissões Mistas (UI Playwright)
*   **Rota:** `/admin/hub/settings?tab=access` (Aba `"Acessos"`).
*   **Ações na UI:**
    *   Clicar no botão `"Novo"` (Tooltip exato: `"Novo Perfil de Acesso"`).
    *   Preencher o campo de texto `"Nome do Perfil"` com: `Auditor Financeiro Restrito`
    *   Na seção de permissões do módulo **SLA & Sanções**, clicar na checkbox `"Aprovar sanções"` (permite a ação `sla:approve`). 
        *   *Nota:* Como `sla:approve` é sensível, a UI exibirá imediatamente o banner: *"Este perfil inclui permissões sensíveis: a alteração exige aprovação de um segundo administrador."*
    *   Na seção **Financeiro**, ativar `"Ler financeiro"` (`financial:read`). Como esta permissão é escoplável, aparecerá a seção `"Restringir a recursos"`.
    *   Clicar na aba expansível `"Restringir a recursos — Sem restrição (todo o tenant)"` e marcar o checkbox de apenas um contrato específico (ex: o contrato de teste criado no setup).
    *   Rolar até o final e clicar no botão `"Salvar"` (dentro da barra de ações inferior ancorada).

### 2. Validação da Fila de Quatro Olhos (Four-Eyes)
*   **Tentativa de Auto-Aprovação (UI Playwright):**
    *   O sistema exibirá a seção `"Aprovações Pendentes (1)"`.
    *   Localizar a solicitação `"Novo perfil · Auditor Financeiro Restrito"`.
    *   Como a solicitação foi criada pela própria sessão logada, o sistema **bloqueia** a auto-aprovação na UI, exibindo apenas o texto: `"Aguardando outro administrador"` (sem botões de "Aprovar" ou "Rejeitar").
    *   *Nota técnica:* Caso o usuário tente invocar a RPC `approve_role_change` diretamente via rede/API, o banco de dados abortará a transação lançando o erro `P0001` com a mensagem: `"Self-approval is not permitted"`.
*   **Aprovação por Segundo Admin (UI Playwright):**
    *   Deslogar do sistema clicando no botão com tooltip `"Sair"`.
    *   Logar com outro administrador da mesma organização (se não houver um no seed, crie uma role de `TENANT_ADMIN` para um novo usuário de teste ou use queries do Postgres MCP para simular a chamada de outro `user_id`).
    *   Navegar novamente até a aba `"Acessos"`.
    *   Na seção `"Aprovações Pendentes (1)"`, clicar no botão `"Aprovar"`.
*   **Validação DB:**
    *   Verificar na tabela `public.tenant_roles` se o perfil foi gravado com `is_system = false`:
        ```sql
        SELECT id, name, is_system FROM public.tenant_roles WHERE name = 'Auditor Financeiro Restrito';
        ```
    *   Verificar as permissões e o escopo associados na tabela `public.tenant_role_permissions` (usando o `tenant_role_id` do select anterior):
        ```sql
        SELECT permission_key, scope FROM public.tenant_role_permissions WHERE tenant_role_id = '<id_da_role>';
        ```
        *   *Esperado:* A permissão `sla:approve` deve estar sem escopo (`scope IS NULL` ou vazio), e `financial:read` deve estar escopada para o contrato selecionado.

### 3. Atribuição de Perfil ao Usuário (UI Playwright)
*   **Rota:** `/admin/hub/settings?tab=users` (Aba `"Equipe"`).
*   **Ações na UI:**
    *   Localizar um usuário de teste (que não seja o administrador atual).
    *   Clicar no botão `ActionChip` `"Perfil"` (com ícone `+`).
    *   No modal/dialog `"Atribuir Perfil de Acesso"`, selecionar `"Auditor Financeiro Restrito"` no Dropdown com rótulo `"Perfil"`.
    *   Manter a validade como `"Permanente"` e clicar no botão `"Atribuir"`.
    *   *Nota:* Como a role possui a permissão sensível `sla:approve`, a atribuição não ocorre imediatamente. Ela gera uma nova solicitação `"Atribuir perfil · Auditor Financeiro Restrito"` no painel de aprovações pendentes (Fase 1.2).
    *   Aprovar esta atribuição usando a sessão do segundo administrador para que ela seja efetivada.
*   **Validação DB:**
    *   Confirmar que o vínculo foi gravado na tabela de junção `public.user_tenant_roles` (e **não** `tenant_user_roles`):
        ```sql
        SELECT user_id, tenant_role_id, organization_id, revoked_at 
        FROM public.user_tenant_roles 
        WHERE user_id = '<id_do_usuario_teste>' AND revoked_at IS NULL;
        ```

---

## Fase 2: Live-Check O(1) e Revogação

### 1. Sessão do Testador (UI Playwright - Browser 2 / Anônimo)
*   Abrir uma sessão de navegação separada (ou guia anônima) e efetuar login com o usuário de teste que acabou de receber o perfil.
*   Navegar até a tela do Tribunal de Auditoria (`/admin/dashboard` ou fila de auditoria). A fila deve carregar normalmente.

### 2. Revogação de Acesso em Tempo Real (UI Playwright - Browser 1)
*   Como o administrador principal, na aba `"Equipe"`, localizar o usuário de teste.
*   No chip de papel `"Auditor Financeiro Restrito"`, clicar no ícone de fechar (`x`) para remover o perfil.
*   Confirmar a remoção.
*   **Validação DB:**
    *   Confirmar no banco de dados que a coluna `revoked_at` foi preenchida na tabela `public.user_tenant_roles`:
        ```sql
        SELECT revoked_at 
        FROM public.user_tenant_roles 
        WHERE user_id = '<id_do_usuario_teste>' AND tenant_role_id = '<id_da_role>';
        ```

### 3. Validação da CIA (UI Playwright - Browser 2)
*   Na sessão do usuário de teste (Browser 2), tentar clicar no botão `"CONFIRMAR INFRAÇÃO"` de qualquer sanção na fila de auditoria.
*   *Nota:* O token JWT do usuário ainda não expirou (está ativo), mas ao enviar a requisição de mutação RPC, o motor do banco de dados intercepta a chamada.
*   **Resultado esperado (Borda do Banco):** A transação deve falhar e retornar o erro PostgreSQL `42501` (Permission Denied) imediatamente, pois a função internal `_rbac_live_check_permission('sla:approve')` é executada na raiz de `approve_sanction` e detecta que a associação foi revogada na tabela `public.user_tenant_roles`, prevenindo o vazamento por token obsoleto.

---

## Fase 3: Financial Guard e Reversão (Disputas)

### 1. Estouro de Teto Financeiro (UI Playwright)
*   Logado como o administrador da Org Alpha, navegar para a Fila de Auditoria (`AuditorQueueScreen`).
*   Localizar as sanções atreladas ao contrato configurado na Fase 0 (limite de 500 centavos).
*   Aprovar uma sanção cujo valor seja maior que o limite configurado (ex: multa de R$ 25,00 = 2500 centavos).
*   **Validação Visual UI:**
    *   Abrir o card da sanção que foi aprovada/selada.
    *   A interface deve exibir uma badge ou estilo visual de aviso (`warning` / `VeraProbColors.warning`), indicando que o teto contratual foi atingido.
    *   O valor aplicado exibido no card de veredito final deve ser exatamente o teto de 500 centavos (ou zero se o espaço sob o teto já estava esgotado), em vez do valor original da multa.
*   **Validação DB (Postgres MCP):**
    *   Consultar a tabela de materialização acumuladora de multas:
        ```sql
        SELECT accrued_cents, cap_cents_snapshot, cap_reached_at_utc 
        FROM public.contract_penalty_monthly_accrual 
        WHERE contract_id = '00000000-0000-0000-0000-ca0000000001';
        ```
    *   *Esperado:* O valor de `accrued_cents` deve bater exatamente com o teto estabelecido no contrato (500 centavos), e o campo `cap_reached_at_utc` deve conter o timestamp UTC da infração que estourou o limite. Timestamps anteriores não devem ter sido alterados (garantindo append-only no histórico geral).

### 2. Teste de Reversão / Anulação de Multa em Disputa (UI Playwright)
*   Na fila de auditoria, mudar o filtro para a lane de disputa (Aba `"Disputadas"`).
*   Selecionar uma sanção atrelada ao mesmo contrato que já foi cobrada.
*   Clicar no botão `"ANULAR INFRAÇÃO"` (que insere a transação do tipo `DISPUTE_ACCEPTED` no livro razão).
*   **Validação DB (Postgres MCP):**
    *   Verificar se o registro de anulação causou o recálculo do acumulador através do trigger `trg_financial_guard_credit`:
        ```sql
        SELECT accrued_cents, cap_reached_at_utc 
        FROM public.contract_penalty_monthly_accrual 
        WHERE contract_id = '00000000-0000-0000-0000-ca0000000001';
        ```
    *   *Esperado:* O valor em `accrued_cents` deve ter sido reduzido (devolvendo espaço sob o teto), enquanto a coluna `cap_reached_at_utc` permanece inalterada (mantendo o registro histórico da quebra).
    *   Verificar a inserção de exatamente uma linha na tabela idempotente:
        ```sql
        SELECT credited_cents 
        FROM public.financial_guard_credits 
        WHERE organization_id = '00000000-0000-0000-0000-000000000001';
        ```

---

## Fase 4: Isolamento de Organização (Tenant Isolation RLS)

### 1. Login na Org B (UI Playwright)
*   Deslogar do sistema (clicando no botão `"Sair"`).
*   Efetuar login como administrador da Organização Beta (Org B):
    *   E-mail: `admin-b@veraprob.dev`
    *   Senha: `123456`

### 2. Verificação de Leakage (UI e DB)
*   **Na UI (Playwright):**
    *   Navegar até a aba `"Acessos"`. O papel `"Auditor Financeiro Restrito"` criado na Fase 1 para a Org Alpha **não** pode ser listado.
    *   Navegar até a aba `"Equipe"`. Os usuários da Org Alpha **não** podem ser exibidos.
*   **No DB (Postgres MCP):**
    *   Simular requisições HTTP utilizando o cabeçalho JWT correspondente à sessão do `admin-b` e garantir que qualquer requisição direta para as tabelas retorne estritamente os registros do tenant da Org Beta:
        ```sql
        -- Executar com a role/JWT de admin-b simulado
        SELECT * FROM public.tenant_roles WHERE name = 'Auditor Financeiro Restrito'; 
        -- Esperado: 0 linhas
        ```

---

## Fase 5: Clean Code e Bugs Visuais

### 1. Auditoria Visual e Renderização Geral Settings (UI Playwright Screenshots)
*   Navegar até `/admin/hub/settings` (aba `"Geral"`).
*   Tirar um screenshot da aba de configurações e garantir que o nome real do operador está renderizado (ex: `"Admin — Org Alpha"` ou o e-mail do operador), e não o fallback estático `"Operador"` ou `"Usuário"`.

### 2. Layout da Matriz de Permissões
*   Abrir o editor de perfis de acesso na aba `"Acessos"`.
*   Tirar screenshots com diferentes resoluções (simular tela menor/teclado virtual ativo).
*   **Critérios de aceitação UI/UX:**
    *   A lista de módulos e permissões deve possuir rolagem independente (`ListView` interno), impedindo erros de estouro de layout (`RenderFlex overflow`).
    *   O botão `"Salvar"` deve estar visível e fixado no rodapé (`bottomNavigationBar` da Scaffold) sem ser sobreposto por outros elementos ou ficar oculto sob o teclado virtual.
