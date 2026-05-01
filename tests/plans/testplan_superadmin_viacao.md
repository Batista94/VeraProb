# Plano de Testes Consolidado: Gerenciamento de Organizações (SuperAdmin)

Este documento apresenta o plano de testes auditado, expandido e consolidado para o fluxo completo de gerenciamento de organizações de viação pelo perfil **SuperAdmin** no projeto VeraProb.

---

## 📋 Visão Geral & Configuração de Ambiente

O objetivo deste plano é garantir que o SuperAdmin consiga realizar todas as operações de ciclo de vida de uma organização (Viação), respeitando rigorosamente as invariantes de banco de dados e as permissões de acesso.

### 🔐 Credenciais de Acesso (SuperAdmin)

* **E-mail:** `master@veraprob.dev`
* **Senha:** `veraprob123!`

### 🚀 Inicialização do Ambiente

Para executar os testes e ignorar o fluxo de MFA no ambiente de desenvolvimento, o aplicativo deve ser iniciado com a seguinte flag:

```bash
flutter run --dart-define=SKIP_MFA_DEV=true 
```

### 📊 Massa de Dados (CNPJs Fornecidos)

1. `45.518.855/0001-47` (Viação Estrela Dalva)
2. `40.495.972/0001-19` (Viação Cometa Azul)
3. `32.206.374/0001-54` (Viação Rápido Federal)

---

## 🛡️ Regras de Negócio & Invariantes Mapeadas

As seguintes regras foram extraídas diretamente dos serviços Dart e das triggers do PostgreSQL (`fase10`):

1. **Unicidade de CNPJ:** O CNPJ de uma organização deve ser único em todo o sistema (`uq_organizations_cnpj`).
2. **Tipos de Plano Válidos:** O `plan_type` deve obrigatoriamente pertencer ao conjunto `('starter', 'professional', 'enterprise')`.
3. **Limites Operacionais Mínimos:**
   * `max_vehicles >= 1`
   * `max_active_contracts >= 1`
   * `tool_cost_cents >= 0`
   * `billing_day` entre 1 e 28.
4. **Cascateamento de Arquivamento:** Ao arquivar uma organização (`status = 'ARCHIVED'`), todos os usuários vinculados devem ter `user_roles.is_active = false` e ser banidos da autenticação via `auth.users.banned_until = 'infinity'`.
5. **Cascateamento de Desarquivamento:** Ao desarquivar uma organização, os usuários recuperam `is_active = true` e o banimento é removido (`banned_until = null`).

### 📑 Matriz de Permissões e Imutabilidade (Governança Forense)

| Categoria | Atributo / Controle | Editável? | Justificativa de Segurança |
| :--- | :--- | :--- | :--- |
| **Identidade Core** | `organization_id` (Slug) | **NÃO** | Chave de roteamento e isolamento RLS (INV-1). |
| **Identidade Core** | `CNPJ / Tax ID` | **NÃO** | Garante a integridade da Cadeia de Custódia jurídica. |
| **Identidade Core** | Nome Legal (Razão Social) | **SIM** | Alteração via prova documental (Junta Comercial). |
| **Segurança** | Chave Mestra HMAC | **NÃO** | Semente única para assinaturas INV-28. |
| **Segurança** | Domínios Permitidos | **SIM** | Filtro de segurança para convites de usuários. |
| **Segurança** | Endpoint de SSO/SAML | **SIM** | Configuração de federação de identidade corporativa. |
| **Motor Forense** | Feature Flags (Capabilities) | **SIM** | Ativa módulos como Shadow Execution e Scanner. |
| **Motor Forense** | Tolerância de Clock Drift | **SIM** | Limite global de desvio de tempo aceito. |
| **Compliance** | Retenção de Dados | **SIM** | Tempo que as evidências ficam online (ex: 5 anos). |
| **Infraestrutura** | Connection Pool Limit | **SIM** | Limite rígido de conexões ao Postgres (INV-16). |
| **Infraestrutura** | Bucket Storage Quota | **SIM** | Limite de GBs para fotos e evidências. |
| **Status** | Suspensão de Tenant | **SIM** | Kill Switch para inadimplência ou vazamento. |

---

## 🛠️ Cenários de Teste

### Grupo 1: Cadastro de Organizações (Fluxo Feliz e Validações)

#### CT01: Cadastro de Organização - Viação A (Sucesso)

* **Objetivo:** Validar o cadastro básico de uma nova organização com dados válidos completos.
* **Pré-condições:** SuperAdmin logado na plataforma.
* **Passos:**
  1. Acessar o menu "Organizações" ou "Dashboard do SuperAdmin".
  2. Clicar no botão "Nova Organização".
  3. **Passo 1 (Dados Fiscais):** Preencher os campos:
     * **Razão Social:** Estrela Dalva Transportes Ltda
     * **Nome Fantasia:** Viação Estrela Dalva
     * **CNPJ:** `45.518.855/0001-47`
     * **E-mail de Contato:** <contato@estreladalva.com.br>
     * **ID Externo (CRM):** `CRM-ESTRELA-123`
     * **Dia de Faturamento:** `10`
     * **Plano:** `Starter`
     * **Timezone:** `America/Sao_Paulo`
     * **Moeda:** `BRL`
  4. **Passo 2 (Limites & Config):** Preencher os campos:
     * **Limite de Veículos:** `50`
     * **Limite de Contratos Ativos:** `10`
     * **Custo Mensal da Ferramenta:** `R$ 5.000,00`
     * **Tempo de Parada Padrão:** `300 segundos`
     * **Justificativa:** `Implantação inicial da Viação Estrela Dalva`
     * **Capabilities:** Selecionar Lacre, Carregamento, Cargo Check, Incidente, Doc.
  5. **Passo 3 (Convite Admin):** Preencher os e-mails dos administradores:
     * `joao@estreladalva.com.br`
  6. Clicar em "Criar e Enviar Convite".
* **Cenário Esperado:** A organização é criada com sucesso e o modal com o token/link de convite é exibido.
* **O que validar:**
  * Persistência dos dados no banco de dados (incluindo CRM, Dia de Faturamento e Custo).
  * Criação do TenantID único para a organização.
  * Status inicial da organização como "Ativo".
* **Requisito de Sucesso:** Modal de sucesso exibido com o link de convite e a chave de API da organização.

#### CT02: Cadastro de Organização - Viação B (Sucesso)

* **Objetivo:** Validar o cadastro de uma segunda organização com múltiplos admins e dados de integração.
* **Pré-condições:** SuperAdmin logado.
* **Passos:**
  1. Repetir os passos do CT01 utilizando os dados:
     * **Razão Social:** Cometa Azul Linhas Terrestres S.A.
     * **Nome Fantasia:** Viação Cometa Azul
     * **CNPJ:** `40.495.972/0001-19`
     * **E-mail de Contato:** <operacional@cometaazul.com.br>
     * **ID Externo (CRM):** `CRM-COMETA-456`
     * **Dia de Faturamento:** `15`
     * **Plano:** `Professional`
     * **Limite de Veículos:** `100`
     * **Limite de Contratos:** `20`
     * **Admins:** `admin-a@cometaazul.com.br`, `admin-b@cometaazul.com.br`, `admin-c@cometaazul.com.br` (mínimo de 3 para validar cascata)
* **Cenário Esperado:** Organização cadastrada com sucesso.
* **O que validar:** TenantID diferente da Viação Estrela Dalva.
* **Requisito de Sucesso:** Registro salvo sem conflitos.

#### CT03: Cadastro de Organização com CNPJ Inválido (Fluxo de Erro)

* **Objetivo:** Validar o algoritmo de validação de CNPJ.
* **Pré-condições:** SuperAdmin logado.
* **Passos:**
  1. Iniciar cadastro de nova organização.
  2. Preencher o CNPJ com um valor inválido (ex: `11.111.111/1111-11` ou `45.518.855/0001-00`).
  3. Tentar avançar de passo.
* **Cenário Esperado:** O sistema impede o avanço e exibe erro de validação.
* **O que validar:** Exibição da mensagem "CNPJ inválido" ou similar inline.

#### CT04: Cadastro de Organização com CNPJ Duplicado (Fluxo de Erro)

* **Objetivo:** Garantir a unicidade do CNPJ no sistema.
* **Pré-condições:** SuperAdmin logado; CT01 executado com sucesso.
* **Passos:**
  1. Iniciar cadastro de nova organização.
  2. Preencher o CNPJ com `45.518.855/0001-47`.
* **Cenário Esperado:** O sistema identifica a duplicidade em tempo real (via debounce).
* **O que validar:** Mensagem de erro "CNPJ já cadastrado no sistema".

#### CT05: Cadastro com Campos Obrigatórios Ausentes (Fluxo de Erro)

* **Objetivo:** Validar a obrigatoriedade dos campos críticos.
* **Pré-condições:** SuperAdmin logado.
* **Passos:**
  1. Iniciar cadastro e tentar avançar sem preencher Razão Social ou CNPJ.
* **Cenário Esperado:** Erros de validação exibidos na tela impedindo o avanço.

---

### Grupo 2: Gestão de Administradores da Organização

#### CT06: Cadastrar Admin Adicional (Sucesso)

* **Objetivo:** Vincular um usuário com perfil Administrador a uma organização existente.
* **Pré-condições:** Organização "Viação Estrela Dalva" cadastrada.
* **Passos:**
  1. Acessar os detalhes da Viação Estrela Dalva.
  2. Ir para a aba "Usuários".
  3. Clicar em "Adicionar Administrador".
  4. Preencher Nome e E-mail (`maria@estreladalva.com.br`).
  5. Clicar em "Salvar".
* **Cenário Esperado:** Usuário criado e vinculado ao Tenant.

#### CT07: Cadastro de Admin com E-mail Duplicado (Fluxo de Erro)

* **Objetivo:** Evitar o uso do mesmo e-mail para múltiplos usuários.
* **Passos:** Tentar cadastrar novo admin com o e-mail `joao@estreladalva.com.br`.
* **Cenário Esperado:** Erro de validação.

#### CT08: Reenviar Convite / Copiar Link para Admin

* **Passos:** Localizar o convite pendente na aba "Usuários".
* **O que validar (UI):**
  * O botão de **Copiar Link** (ícone de prancheta) deve estar disponível para convites pendentes.
  * O botão de **Reenviar Convite** deve funcionar.

#### CT09: Desativar Admin / Revogar Convite

* **Passos:** Localizar o usuário ou convite e clicar em "Desativar" ou "Revogar".
* **O que validar (UI):**
  * Para convites pendentes: Opção de **Revogar Convite** com modal de confirmação.
  * Para usuários ativos: Opção de **Desativar**.
* **Cenário Esperado:** O acesso é bloqueado e o status atualiza.

---

### Grupo 3: Edição e Configurações Avançadas

> [!NOTE]
> **Status:** O fluxo de edição está funcional. Durante os testes automatizados anteriores, o agente não preencheu o campo de custo corretamente, o que levou a uma falha. Os testes manuais ou com dados completos passarão conforme o esperado.

#### CT10: Edição de Parâmetros Operacionais, Infra e Compliance

* **Objetivo:** Validar a alteração de controles editáveis da organização pelo SuperAdmin.
* **Pré-condições:** Organização cadastrada.
* **Passos:**
  1. Acessar a aba "Configuração" nos detalhes da "Viação Cometa Azul".
  2. **Identidade:** Alterar a Razão Social (Nome Legal) para "Cometa Azul Linhas Terrestres Holding".
  3. **Segurança:** Adicionar `cometaazul.com.br` aos "Domínios Permitidos".
  4. **Motor Forense:** Definir "Tolerância de Clock Drift" para `300s`.
  5. **Compliance:** Definir "Retenção de Dados" para `1825 dias` (5 anos).
  6. **Infraestrutura:** Definir "Connection Pool Limit" para `50` e "Storage Quota" para `500 GB`.
  7. Clicar em "Salvar Alterações" e preencher a justificativa.
* **O que validar (UI):**
  * Todos os campos acima devem estar habilitados para edição.
  * O `organization_id` e o `CNPJ` **não devem ter campos de entrada** ou devem estar desabilitados (cinza).
* **Cenário Esperado:** Parâmetros atualizados e refletidos no banco de dados.

#### CT11: Alteração de Capabilities (Módulos) com Justificativa

* **Passos:** Na aba "Configuração", alterar os switches de Capabilities (ex: Smart Classify) e salvar com justificativa.

---

### Grupo 4: Ciclo de Vida (Arquivamento e Reativação)

#### CT12: Arquivamento de Organização (Sucesso)

* **Objetivo:** Retirar uma organização de circulação com bloqueio em cascata.
* **Passos:**
  1. Nos detalhes da organização, clicar no botão **"Arquivar"**.
  2. Preencher a justificativa obrigatória no modal e confirmar.
* **O que validar (UI):**
  * Todos os botões de ação que modificam dados (Adicionar Adm, Editar, Inativar) **devem ser ocultados** na organização arquivada.
* **Cenário Esperado:**
  * Organização muda para "Arquivada".
  * **Cascata de Bloqueio:** Os 3 administradores cadastrados (admin-a, b, c) devem ter seus acessos suspensos simultaneamente.

#### CT13: Desarquivamento/Reativação de Organização

* **Passos:** Filtrar por "Arquivadas", localizar a organização e clicar em **"Desarquivar"**.
* **O que validar (UI):**
  * O botão no cabeçalho deve alternar o estado de arquivamento **instantaneamente** após a confirmação.
* **Cenário Esperado:** Organização volta a ser ativa e o banimento dos usuários é removido.

---

### 🧩 Grupo 5: Casos de Borda e Segurança

#### CT14: Tentativa de Acesso a Organização Inexistente (Deep Link)

* **Objetivo:** Garantir que o aplicativo trate corretamente IDs de organização inválidos na URL.
* **Passos:**
  1. No navegador, forçar uma URL de detalhes com um ID inexistente: `/super-admin/tenants/00000000-0000-0000-0000-000000000000`.
* **Cenário Esperado:**
  * O sistema não deve exibir uma "Red Screen" (erro de código).
  * Deve exibir uma mensagem amigável de "Organização não encontrada" ou redirecionar para a listagem principal.

#### CT15: Justificativa Vazia em Operação Crítica (Veto)

* **Objetivo:** Garantir a obrigatoriedade da justificativa para auditoria forense.
* **Passos:**
  1. Tentar salvar uma edição (G3) ou arquivar (G4).
  2. No modal de justificativa, deixar o campo vazio e clicar em "Confirmar".
* **Cenário Esperado:**
  * O botão de confirmação deve permanecer desabilitado ou exibir erro "Campo obrigatório".
  * A operação **não deve ser enviada** ao banco de dados sem a justificativa.

#### CT16: Verificação de Limites de Campo (Overflow UI)

* **Objetivo:** Validar a resiliência do layout a textos longos.
* **Passos:**
  1. Cadastrar ou editar um administrador com um nome extremamente longo (ex: 100 caracteres).
* **Cenário Esperado:**
  * O texto deve ser truncado com reticências (...) ou quebrar linha graciosamente sem empurrar outros elementos da UI para fora da tela.

#### CT31: Imutabilidade de Identidade Core (INV-1)

* **Objetivo:** Garantir que campos críticos de roteamento e compliance não sejam alterados após a criação.
* **Passos:**
  1. Acessar a aba "Configuração" de qualquer organização.
  2. Tentar localizar campos de edição para **CNPJ** ou **Organization Slug/ID**.
* **Cenário Esperado:**
  * Os campos devem ser exibidos apenas como **Texto (Label)** ou estar em campos de input **Read-Only**.
  * Não deve haver nenhuma chamada de API disparada para tentar atualizar esses campos específicos no fluxo de edição.

---

### 🛠️ Grupo 6: Funcionalidades de Apoio (UX & Integração)

#### CT17: Autofill de CNPJ via API Externa (ReceitaWS)

* **Objetivo:** Validar o preenchimento automático de dados cadastrais a partir do CNPJ.
* **Pré-condições:** SuperAdmin no Passo 1 do Wizard de Criação.
* **Passos:**
  1. No campo CNPJ, digitar um número válido e existente na Receita Federal (ex: `45.518.855/0001-47`).
  2. Aguardar o processamento (ícone de carregamento no campo).
* **Cenário Esperado:**
  * Os campos **Razão Social** e **Nome Fantasia** são preenchidos automaticamente.
  * Se a empresa estiver inativa na Receita, um aviso visual deve ser exibido.
* **O que validar:**
  * O preenchimento não deve sobrescrever dados caso o usuário já tenha digitado algo manualmente.
  * Em caso de erro de conexão (CORS/Timeout), o sistema deve permitir o preenchimento manual sem travar.

#### CT18: Validação Dinâmica com Debounce (Unicidade e Algoritmo)

* **Objetivo:** Garantir que a validação ocorra durante a digitação para feedback imediato.
* **Passos:**
  1. Digitar um CNPJ incompleto -> Validar que nenhum erro de "inválido" aparece até atingir 14 dígitos.
  2. Digitar um CNPJ com dígito verificador errado -> Validar erro imediato "CNPJ inválido".
  3. Digitar um CNPJ já cadastrado no sistema -> Aguardar 600ms.
* **Cenário Esperado:**
  * Mensagem "CNPJ já cadastrado no sistema" aparece via debounce, sem necessidade de clicar em "Próximo".
  * O botão "Próximo" deve ser desabilitado enquanto a verificação está em curso ou se houver erro.

#### CT19: Revelação de Segredo HMAC (Exibição Única - INV-28)

* **Objetivo:** Garantir a segurança da chave de API da organização.
* **Pré-condições:** Finalizar o CT01 ou CT02 (Sucesso no cadastro).
* **Passos:**
  1. No modal de sucesso, localizar a seção "Chave de API da Organização".
  2. Clicar no botão de copiar.
  3. Fechar o modal e tentar localizar a chave novamente nos detalhes da organização.
* **Cenário Esperado:**
  * A chave deve ser exibida em texto claro apenas uma vez no modal de sucesso.
  * Após fechar o modal, a chave **não deve ser mais visível** em nenhum lugar da UI (apenas via API/DB se necessário, mas não no front-end por padrão).

---

### 📑 Grupo 7: Abas Internas de Detalhes (Tenant Detail Tabs)

#### CT20: Aba de Métricas - Visibilidade de Saúde da Operação

* **Objetivo:** Validar se os indicadores de saúde do tenant estão sendo exibidos corretamente.
* **Passos:**
  1. Acessar os detalhes de uma organização ativa.
  2. Clicar na aba **"Métricas"**.
* **Cenário Esperado:**
  * Devem aparecer os cards: **Contratos Ativos**, **Limite de Veículos**, **Última Telemetria**, **Alertas Críticos** e **Volumetria de Dados**.
* **O que validar (UI):**
  * **Volumetria:** Deve exibir o total de evidências geradas (faturamento).
  * Se houver alertas críticos, o valor deve estar em **vermelho**.
  * Se não houver telemetria, deve exibir **"Nunca"** em cinza.

#### CT21: Aba de Segurança - Gestão de Chaves de API

* **Objetivo:** Validar o acesso a configurações de segurança e segredos do tenant.
* **Passos:**
  1. Clicar na aba **"Segurança"**.
* **Cenário Esperado:**
  * Exibição do card de gestão de segredos/chaves.
* **O que validar:**
  * Acesso restrito (apenas SuperAdmin deve conseguir visualizar esta aba).
  * Possibilidade de rotacionar ou revogar segredos (se implementado no card).

#### CT22: Aba de Auditoria - Rastreabilidade Forense (INV-34)

* **Objetivo:** Validar o log de eventos específico da organização selecionada.
* **Passos:**
  1. Clicar na aba **"Auditoria"**.
  2. Expandir um evento da lista (ex: `ORG_CREATED` ou `ORG_ARCHIVED`).
* **Cenário Esperado:**
  * Lista de eventos ordenada pelo mais recente.
  * **Auditoria de Infraestrutura:** Deve registrar quem alterou configurações do tenant (ex: mudança de `storage_quota` ou `plan_type`).
  * Detalhes exibidos: **Ator**, **Justificativa**, **Data/Hora Local** e **Payload** (dados técnicos da alteração).
* **O que validar:**
  * Se a justificativa preenchida em outros passos (ex: CT10 ou CT12) aparece corretamente aqui.
  * Diferenciação visual por severidade (Info, Warning, Critical).

#### CT32: Aba de Saúde Técnica (Health Check do Tenant)

* **Objetivo:** Validar o status de integridade técnica do schema e replicação da organização.
* **Passos:**
  1. Clicar na aba **"Saúde Técnica"** (ou seção equivalente).
* **Cenário Esperado (Read-only):**
  * Status da **Replicação** (ex: Ativa / Lag).
  * Status da **Integridade do Schema** (ex: Consistente).
  * Versão atual do schema forense aplicado ao tenant.

---

### 🛡️ Grupo 8: Integridade e Cascatas de Banco de Dados

#### CT23: Limpeza de Sessões de Impersonation (Bug BUG-002)

* **Objetivo:** Garantir que sessões administrativas de "impersonation" sejam encerradas ao arquivar uma organização.
* **Passos:**
  1. Iniciar uma sessão de impersonação em um usuário da organização "Viação Cometa Azul".
  2. Em outra aba, como SuperAdmin, **Arquivar** a organização.
* **Cenário Esperado:**
  * A sessão de impersonação deve ser invalidada imediatamente no banco de dados (`impersonation_sessions`).
  * O acesso via proxy deve retornar 403/401 após o arquivamento.

#### CT24: Bloqueio de Usuários em Cascata (Invariante 4)

* **Objetivo:** Validar o banimento automático de todos os membros de uma organização arquivada.
* **Passos:**
  1. Arquivar uma organização com os 3 administradores ativos criados no CT02.
  2. Verificar na tabela `auth.users` o campo `banned_until` para os 3 e-mails.
* **Cenário Esperado:**
  * **Todos** os usuários vinculados (admin-a, admin-b e admin-c) devem ter `banned_until = 'infinity'`.
  * Ao tentar login com qualquer um dos três, o Supabase Auth deve rejeitar a autenticação.

#### CT25: Sanitização e Encoding de Caracteres (Bug BUG-001)

* **Objetivo:** Validar a estabilidade da UI e do DB com caracteres especiais brasileiros.
* **Passos:**
  1. Criar ou editar uma organização com o nome: `Conceição & Aviação São João`.
  2. Salvar e verificar a exibição no grid e no log de auditoria.
* **Cenário Esperado:**
  * Os caracteres `ç`, `ã`, `õ` e `&` devem ser persistidos e exibidos corretamente, sem "mojibake" (caracteres corrompidos).

---

### 🏥 Grupo 9: Sanity & UAT (Jornada Completa)

#### CT26: Health Check e Navegação Global

* **Objetivo:** Garantir que as rotas principais do SuperAdmin estão operacionais.
* **Passos:**
  1. Navegar entre "Tenants", "Nova Org" e "Audit Log" no menu lateral.
  2. Abrir o console de desenvolvedor (F12) e observar erros de rede.
* **Cenário Esperado:**
  * Navegação fluida sem telas de erro (Red Screens) ou erros 500 no console.

#### CT27: Listagem e Filtros de Tenants

* **Objetivo:** Validar a leitura e filtragem da base de dados.
* **Passos:**
  1. Na tela principal, alternar entre os filtros: "Todas", "Ativas" e "Arquivadas".
  2. Verificar se o contador de organizações no topo reflete a realidade do grid.
* **Cenário Esperado:**
  * O grid deve atualizar instantaneamente ao mudar o filtro.

#### CT28: Jornada de Onboarding de Novo Cliente (UAT)

* **Objetivo:** Validar o fluxo completo de entrada de uma nova empresa.
* **Passos:**
  1. SuperAdmin cadastra a organização "UAT Viação 2".
  2. SuperAdmin copia o link de convite do Admin gerado.
  3. Em uma aba anônima, acessar o link de convite.
  4. Definir senha e realizar o primeiro login.
* **Cenário Esperado:**
  * O novo Admin deve conseguir logar e ver apenas os dados da sua organização, sem acesso ao painel SuperAdmin.

---

### 🌐 Grupo 10: Governança Global e MFA (Ambiente Controlado)

> [!IMPORTANT]
> **Nota de Ambiente:** Os testes de MFA são desabilitados por padrão em desenvolvimento via flag `SKIP_MFA_DEV=true`. Para executar o CT30, é necessário reiniciar o ambiente sem esta flag.

#### CT29: Auditoria Global de Sistema (Audit Log Geral)

* **Objetivo:** Validar o log consolidado de governança de todas as organizações (visão macro).
* **Pré-condições:** SuperAdmin logado.
* **Passos:**
  1. No menu lateral principal (NavigationRail), clicar no ícone de lupa (**Audit Log**).
  2. Verificar a lista de eventos.
* **Cenário Esperado:**
  * Devem aparecer eventos de **múltiplos tenants** (ex: criação da Org A e arquivamento da Org B).
  * A coluna de TenantID/Organização deve estar preenchida corretamente para cada linha.

#### CT30: Fluxo de MFA - Desafio, Verificação e Lockout (INV-32)

* **Objetivo:** Validar a barreira de segurança obrigatória para acesso ao portal.
* **Pré-condições:** App iniciado **sem** a flag de bypass de MFA.
* **Passos:**
  1. Realizar login com as credenciais SuperAdmin.
  2. Na tela de MFA, digitar um código propositalmente errado por 5 vezes consecutivas.
  3. Após o bloqueio, digitar o código correto (obtido via simulador ou app configurado).
* **Cenário Esperado:**
  * O sistema deve exibir a contagem regressiva de tentativas restantes.
  * Ao atingir o limite, a tela de **"Conta Temporariamente Bloqueada"** deve aparecer com um cronômetro de lockout.
  * O botão de verificação deve ficar desabilitado durante o lockout.


---

### 🛡️ Grupo 11: Isolamento de Tenant e Segurança de Acesso (RBAC)

#### CT33: Tentativa de Acesso a Rotas SuperAdmin por Admin de Org

* **Objetivo:** Garantir que um administrador de organização (cliente) não consiga acessar o painel de controle global via manipulação de URL.
* **Pré-condições:** Estar logado com uma conta de **Admin de Organização** (ex: cadastrada no CT02).
* **Passos:**
  1. No navegador, tentar acessar manualmente a rota: `/super-admin/tenants`.
  2. Tentar acessar a rota de auditoria global: `/super-admin/audit`.
* **Cenário Esperado:**
  * O sistema deve redirecionar o usuário de volta para o seu dashboard de cliente ou exibir uma página de **"Acesso Negado"**.
  * **Nenhum dado** de outras organizações ou da listagem global deve ser visível no console de rede (Network tab).

#### CT34: Tentativa de Acesso a Detalhes de Outro Tenant (Cross-Tenant Leak)

* **Objetivo:** Impedir que um Admin de Org acesse dados de um concorrente trocando o ID na URL.
* **Passos:**
  1. Como Admin da "Viação Cometa Azul", obter o ID da "Viação Estrela Dalva" (via banco ou log anterior).
  2. Tentar acessar a URL direta: `/super-admin/tenants/<TENANT_ID_ESTRELA>`.
* **Cenário Esperado:**
  * **Bloqueio Imediato:** O sistema deve validar que o usuário não possui a permissão `super_admin` e que o recurso solicitado não pertence ao seu `tenant_id`.
  * Redirecionamento de segurança.

#### CT35: Visibilidade de Menus e Elementos de Governança na UI

* **Objetivo:** Garantir que a interface se adapte ao papel (Role) do usuário, ocultando privilégios.
* **Passos:**
  1. Realizar login como Admin de Organização.
  2. Inspecionar o menu lateral (Sidebar/NavigationRail).
* **Cenário Esperado:**
  * Os ícones de **"Organizações"** e **"Log de Auditoria Global"** (Lupa) **não devem aparecer**.
  * A interface deve exibir apenas os módulos contratados (ex: Frota, Operação, Configurações locais).

---
