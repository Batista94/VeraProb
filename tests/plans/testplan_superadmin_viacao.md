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
     * **Admins:** `admin-a@cometaazul.com.br`, `admin-b@cometaazul.com.br`
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

#### CT10: Edição de Dados Cadastrais, CRM e Parâmetros Operacionais

* **Objetivo:** Validar a alteração de dados da organização pelo SuperAdmin.
* **Pré-condições:** Organização cadastrada.
* **Passos:**
  1. Acessar a aba "Configuração" nos detalhes da "Viação Cometa Azul".
  2. Localizar o novo agrupamento **"Identificação"** e preencher os novos campos: **Razão Social** e **Nome Fantasia** (se ausentes).
  3. Alterar o Nome Fantasia para "Viação Cometa Azul Express".
  4. Alterar o **ID Externo (CRM)** para `CRM-COMETA-789`.
  5. Alterar o **Dia de Faturamento** para `20`.
  6. Alterar o **Custo Mensal** para `R$ 7.000,00`.
  7. Alterar o limite de veículos para `150`.
  8. Clicar em "Salvar Alterações" e preencher a justificativa obrigatória.
* **O que validar (UI):**
  * Os novos campos Razão Social e Nome Fantasia devem estar editáveis.
  * **Persistência de Estado (Stale Fix):** Ao salvar e mudar de aba, ao retornar, os dados devem permanecer os recém-salvos **sem necessidade de dar F5**.
* **Cenário Esperado:** Dados atualizados com sucesso.

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
* **Cenário Esperado:** Organização muda para "Arquivada" e todos os admins da organização são bloqueados (`auth.users.banned_until = 'infinity'`).

#### CT13: Desarquivamento/Reativação de Organização

* **Passos:** Filtrar por "Arquivadas", localizar a organização e clicar em **"Desarquivar"**.
* **O que validar (UI):**
  * O botão no cabeçalho deve alternar o estado de arquivamento **instantaneamente** após a confirmação.
* **Cenário Esperado:** Organização volta a ser ativa e o banimento dos usuários é removido.

---

### 🚨 Grupo 5: Casos de Borda (Edge Cases) & Validação de Invariantes

#### CT14: Validação de Limites de Cota no Backend (Invariantes)

* **Passos:** Tentar salvar `max_vehicles = 0`, `billing_day = 31` ou `tool_cost_cents = -100` via formulário ou API.
* **Cenário Esperado:** Falha na validação com erro amigável na UI ou rejeição pelo banco.

#### CT15: Concorrência (Race Condition)

* **Passos:** Abrir o mesmo formulário de edição em duas abas e tentar salvar alterações conflitantes simultaneamente.
* **Cenário Esperado:** A segunda requisição falha informando que os dados estão desatualizados.

#### CT16: Bypass de URL/Permissão

* **Passos:** Logar como Admin Comum e tentar acessar `/super-admin/tenants` diretamente.
* **Cenário Esperado:** Redirecionamento para Unauthorized ou Home.

---

## 🏥 Sanity Tests (Testes de Sanidade)

1. **ST01: Health Check do Painel SuperAdmin** (Navegação sem erros 500).
2. **ST02: Listagem de Organizações** (Verificação de leitura do banco).

## 👥 UAT (User Acceptance Testing)

1. **UAT01: Jornada de Onboarding do Cliente** (SuperAdmin cadastra Org -> Cadastra Admin -> Admin recebe convite e define senha -> Acessa o sistema isolado).

---
