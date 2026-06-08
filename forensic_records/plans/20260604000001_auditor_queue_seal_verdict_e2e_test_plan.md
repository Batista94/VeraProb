# Plano de Testes E2E/UAT Completo e Detalhado: Tribunal de Auditoria & Ciclo de Sanções (AuditorQueueScreen)

Este documento apresenta o plano de testes consolidados, estruturado com instruções específicas, seletores CSS/Playwright e comandos SQL (psql) exaustivos. Ele foi desenhado para ser executado e validado de forma autônoma por agentes automatizados utilizando ferramentas do Playwright (Navegador) e Postgres (psql).

---

## 📋 Visão Geral & Configuração de Ambiente

O objetivo deste plano é testar a reestruturação completa do ciclo de vida de sanções (incluindo o fluxo de resolução de disputas, fim das multas-fantasma na aba Concluídos e painel OCC read-only table-first com endDrawer).

### 🔐 Credenciais de Acesso (Inquilinos Isolados)

* **Inquilino A (Org Alpha):** `admin-a@veraprob.dev` / `123456` — Org ID `00000000-0000-0000-0000-000000000001`
* **Inquilino B (Org Beta):** `admin-b@veraprob.dev` / `123456` — Org ID `00000000-0000-0000-0000-000000000002`

### 🚀 Inicialização do Ambiente

O aplicativo Flutter e o Supabase local devem ser iniciados com as flags de desativação de MFA no ambiente de desenvolvimento:

```bash
# Terminal 1 - Subir Supabase Local
supabase start

# Terminal 2 - Executar App Web na porta de testes
flutter run -d chrome --web-port=50185 --dart-define=SKIP_MFA_DEV=true
```

URL Base do App: `http://localhost:50185`

---

## 🛡️ Regras de Negócio & Invariantes de Auditoria

Durante o teste, as seguintes invariantes do sistema VeraProb devem ser atestadas via psql e logs:
1. **INV-1 (FAIL-FAST):** Toda query do inquilino deve validar o claim `org_id` (JWT) no banco.
2. **INV-3 (MUTABILIDADE DO LEDGER):** A tabela `public.sla_audit_ledger_v2` é estritamente append-only. Qualquer operação de `UPDATE` ou `DELETE` deve ser rejeitada pelo banco.
3. **INV-6 (UTC MANDATORY):** Todos os timestamps salvos devem estar em UTC.
4. **INV-22 (ISOLAMENTO DE TENANT):** O Inquilino B jamais pode acessar qualquer dado (contratos, contratantes, logs, sanções) do Inquilino A.
5. **INV-26 (ANTI-ORACLE):** Tentativas de buscar um ID de outro tenant devem retornar `404 Not Found` puro, nunca `403 Access Denied`.

---

## 🛠️ Cenários de Teste (Jornada Playwright + psql)

### Grupo 1: Login & Cadastro de Recursos Core

#### CT01: Login e Validação de Sessão do Inquilino A
* **Objetivo:** Acessar a plataforma como Administrador do Inquilino A.
* **Passos Playwright:**
  1. Acessar a página `http://localhost:50185`.
  2. Aguardar o seletor `input[type="text"]` (com label "E-mail Corporativo") e preencher: `admin-a@veraprob.dev`.
  3. Localizar o input de senha (com label "Senha de Acesso") e preencher: `123456`.
  4. Clicar no botão `button:has-text("ACESSAR SISTEMA")`.
  5. Aguardar redirecionamento (a URL deve carregar o painel da organização).
* **O que validar (Playwright):**
  * Verificar que a tela contém o texto "Dashboard" ou "Fila Auditora" no menu lateral.
* **Validação SQL (psql):**
  ```sql
  SELECT email,
         raw_app_meta_data ->> 'org_id' AS org_claim
  FROM auth.users
  WHERE email = 'admin-a@veraprob.dev';
  -- Esperado: org_claim = '00000000-0000-0000-0000-000000000001'
  ```

---

#### CT02: Cadastro de Novo Contratante (Sucesso + Validação de Nome Duplicado)
* **Objetivo:** Adicionar um contratante válido e verificar que nomes duplicados na mesma organização são rejeitados com mensagem clara — sem dados fantasma no banco.

##### CT02-A: Cadastro bem-sucedido
* **Pré-condição:** Nenhum contratante com o nome `Viação Oeste Alfa S.A.` existe na Org A.
* **Passos Playwright:**
  1. No menu lateral, clicar no botão que possui a classe ou label contendo `"Administração"`.
  2. Localizar o grid de Administração e clicar no card **"Contratantes"**.
  3. Clicar no botão **"Novo Contratante"** (seletor: `button:has-text("Novo Contratante")`).
  4. No modal aberto, preencher:
     - **Nome da Empresa:** `Viação Oeste Alfa S.A.`
     - **CNPJ / Tax ID:** `91.101.494/0001-56` (CNPJ válido).
     - **Pessoa de Contato:** `Carlos Mendes`
     - **Email Primário:** `contato@alfaengenharia.com.br`
  5. Clicar no botão `button:has-text("Salvar")`.
* **O que validar (Playwright):**
  * Modal fecha imediatamente após o clique.
  * Contratante `Viação Oeste Alfa S.A.` aparece na tabela **sem necessidade de reload**.
* **Validação SQL (psql):**
  ```sql
  SELECT id, name, tax_id, organization_id
  FROM public.contractors
  WHERE organization_id = '00000000-0000-0000-0000-000000000001'
    AND name = 'Viação Oeste Alfa S.A.';
  -- Esperado: EXATAMENTE 1 linha (sem duplicatas por double-fire).
  -- organization_id = '00000000-0000-0000-0000-000000000001'.
  -- tax_id = '91.101.494/0001-56'.
  ```

##### CT02-B: Rejeição de nome duplicado na mesma organização
* **Pré-condição:** CT02-A concluído — `Viação Oeste Alfa S.A.` já existe na Org A.
* **Passos Playwright:**
  1. Clicar novamente em **"Novo Contratante"**.
  2. No modal, preencher o mesmo nome `Viação Oeste Alfa S.A.` com dados diferentes:
     - **CNPJ / Tax ID:** `07.526.557/0001-00` (CNPJ válido diferente).
     - **Pessoa de Contato:** `Ana Costa`
     - **Email Primário:** `ana@beta.com.br`
  3. Clicar em `button:has-text("Salvar")`.
* **O que validar (Playwright):**
  * Modal **permanece aberto** (não fecha).
  * Snackbar vermelho exibe a mensagem: `Já existe um contratante com este nome nesta organização.`
  * O botão **"Cancelar"** fecha o modal ao ser clicado.
* **Validação SQL (psql):**
  ```sql
  SELECT COUNT(*)
  FROM public.contractors
  WHERE organization_id = '00000000-0000-0000-0000-000000000001'
    AND name = 'Viação Oeste Alfa S.A.';
  -- Esperado: COUNT = 1 (o duplicado foi rejeitado, sem phantom rows).
  ```

---

#### CT03-A: Cadastro de Contrato Operacional
* **Objetivo:** Criar e ativar um contrato operacional.
* **Passos Playwright:**
  1. No Hub de Administração, clicar no card **"Contratos"**.
  2. Clicar no botão **"Novo Contrato"** (`button:has-text("Novo Contrato")`).
  3. Preencher o formulário:
     - **Nome do Contrato:** `Contrato de Concessão Leste - Lote 1`
     - **Entidade Contratante:** Clicar no TypeAhead/Campo e digitar `Viação Oeste Alfa S.A.`, depois selecionar a opção correspondente do dropdown.
     - **Início (Vigência):** Clicar no calendário e selecionar a data atual (ou hoje).
     - **Término (Vigência):** Clicar no calendário e selecionar uma data no ano seguinte.
     - **Teto Financeiro:** Preencher com `150.000,00`.
  4. Clicar no botão `button:has-text("ATIVAR CONTRATO")`.
* **O que validar (Playwright):**
  * A URL ou tela deve mudar para a visualização detalhada do contrato (`ContractDetailScreen`).
* **Validação SQL (psql):**
  ```sql
  SELECT id, name, organization_id, status, financial_ceiling_cents
  FROM public.contracts
  WHERE name = 'Contrato de Concessão Leste - Lote 1';
  -- Esperado: status = 'draft' (ou 'awaiting_contractor_acceptance' dependendo da política de workflow).
  -- financial_ceiling_cents = 15000000.
  ```

---

#### CT03-B: Cadastro de Zonas Operacionais (Pré-condição para Plano Operacional)
* **Objetivo:** Cadastrar as zonas de Partida e Chegada necessárias para o plano.
* **Passos Playwright:**
  1. No Hub de Administração, clicar no card **"Zonas Operacionais"**.
  2. Clicar no botão **"Nova Zona Operacional"** (`button:has-text("Nova Zona Operacional")`).
  3. Preencher o formulário da primeira zona:
     - **Nome da Zona:** `Garagem Central`
     - **Endereço:** Digitar `Sao Paulo` e selecionar a primeira sugestão.
     - **Distância de Detecção:** `200` metros.
  4. Clicar no botão `button:has-text("Criar Zona")`.
  5. Clicar no botão **"Nova Zona Operacional"** novamente.
  6. Preencher o formulário da segunda zona:
     - **Nome da Zona:** `Cliente Leste`
     - **Endereço:** Digitar `Campinas` e selecionar a primeira sugestão.
     - **Distância de Detecção:** `200` metros.
  7. Clicar no botão `button:has-text("Criar Zona")`.
* **O que validar (Playwright):**
  * Ambas as zonas são listadas na tabela de Zonas Operacionais.
* **Validação SQL (psql):**
  ```sql
  SELECT COUNT(*)
  FROM public.operational_zones
  WHERE organization_id = '00000000-0000-0000-0000-000000000001'
    AND name IN ('Garagem Central', 'Cliente Leste');
  -- Esperado: COUNT = 2
  ```

---

#### CT04: Declaração de Plano Operacional
* **Objetivo:** Vincular regras de SLA e turnos operacionais ao contrato utilizando as zonas criadas.
* **Passos Playwright:**
  1. Na tela de detalhes do contrato (`ContractDetailScreen` de `Contrato de Concessão Leste - Lote 1`), clicar na aba **"Plano Operacional"**.
  2. Clicar no botão **"DECLARAR PLANO"**.
  3. No formulário do plano (passo 1: Zonas):
     - Selecionar **Zona de Partida** como `Garagem Central`.
     - Selecionar **Zona de Chegada** como `Cliente Leste`.
     - Clicar em **"Continuar"**.
  4. No passo 2 (Turno):
     - Definir horário de partida como `08:00`.
     - Definir horário de chegada como `09:00`.
     - Clicar em **"Continuar"**.
  5. No passo 3 (SLA & Penalidades):
     - Definir **Valor Base** como `1.500,00`.
     - Clicar em **"Continuar"**.
  6. No passo 4 (Revisão):
     - Clicar no botão **"Publicar SLA B2B"**.
  7. Clicar na aba **"Viagens Programadas"** (caso a UI não faça a transição automática).
* **O que validar (Playwright):**
  * O plano operacional versão 1 aparece como ativo na listagem do contrato.
  * A aba **"Viagens Programadas"** deve exibir o indicador de processamento (ex: "Processando malha horária do plano...") e, logo após o processamento assíncrono, listar os turnos (SETs) recém-projetados. **(Nota QA: Exigir `waitFor` ou estender o timeout do `expect` para lidar com a janela de até 10s de polling, evitando falha prematura do teste automatizado).**
* **Validação SQL (psql):**
  ```sql
  -- 1. Verifica a declaração do plano
  SELECT plan_version, rule_snapshot_jsonb
  FROM public.plan_declarations
  WHERE contract_id = (SELECT id::text FROM public.contracts WHERE name = 'Contrato de Concessão Leste - Lote 1' LIMIT 1)
  ORDER BY plan_version DESC
  LIMIT 1;
  -- Esperado: plan_version = 1, rule_snapshot_jsonb não nulo.

  -- 2. Verifica a geração assíncrona das viagens projetadas (SETs)
  SELECT COUNT(*) as qtd_viagens
  FROM public.contractual_service_executions cse
  JOIN public.plan_declarations pd ON pd.id = cse.plan_declaration_id
  WHERE pd.contract_id = (SELECT id::text FROM public.contracts WHERE name = 'Contrato de Concessão Leste - Lote 1' LIMIT 1);
  -- Esperado: qtd_viagens > 0 (garante que o Future.microtask inseriu as viagens corretamente)
  ```


---

### Grupo 2: Simulação e Fila Auditora

#### CT05: Simulação de Viagem e Ingestão de Telemetria
* **Objetivo:** Simular telemetria em excesso de velocidade e gerar infração (card pendente).
* **Passos Playwright:**
  1. No menu lateral, clicar em **"Fila Auditora"**.
  2. Clicar no botão **"Gerar Sanção de Teste"** (`button:has-text("Gerar Sanção de Teste")`).
  3. Aguardar 5 segundos (para permitir o processamento assíncrono via trigger de banco).
* **O que validar (Playwright):**
  * Na aba **"Pendentes"**, deve aparecer o card da infração **VEL-01**.
  * O card deve ter uma borda vermelha e exibir:
    - Rótulo **"VELOCIDADE REGISTRADA"** com o valor `88.5 km/h`.
    - Rótulo **"LIMITE CONTRATUAL"** com o valor `80.0 km/h`.
    - Rótulo **"EXCESSO"** com o valor `+8.5 km/h`.
    - Faixa de identidade com a placa `TST-0001` (ou similar) e o operador `Motorista Teste`.
* **Validação SQL (psql):**
  ```sql
  SELECT id, status, vehicle_plate, operator_name
  FROM public.sanction_review_queue
  WHERE organization_id = '00000000-0000-0000-0000-000000000001'
    AND status = 'pending'
  ORDER BY created_at DESC
  LIMIT 1;
  -- Esperado: status = 'pending'. Anotar o ID retornado como <QUEUE_ID>.
  ```

---

#### CT06: Veto de Recusa Curta (Validação de UI)
* **Objetivo:** Garantir que o auditor não consiga recusar uma sanção sem uma justificativa plausível (mínimo de 10 caracteres).
* **Passos Playwright:**
  1. No card do veredito pendente (**VEL-01**), clicar no botão **"RECUSAR VEREDITO"**.
  2. Localizar o campo de texto expandido `"Motivo da rejeição (mínimo 10 caracteres)"`.
  3. Digitar `Incorreto` (9 caracteres).
* **O que validar (Playwright):**
  * Verificar que o botão **"CONFIRMAR RECUSA"** (`button:has-text("CONFIRMAR RECUSA")`) permanece desabilitado (atributo `disabled`).

---

#### CT07: Solicitar Prova Forense (Disputa)
* **Objetivo:** Mudar o status de uma infração para disputado/aguardando evidência.
* **Passos Playwright:**
  1. No mesmo card de veredito pendente, clicar em **"SOLICITAR PROVA FORENSE"**.
* **O que validar (Playwright):**
  * O card deve desaparecer da aba **"Pendentes"**.
  * Clicar na aba **"Aguardando Evidência"** (`text=Aguardando Evidência`).
  * Verificar que o card aparece na lista com badge de cor âmbar escrito **"AGUARDANDO EVIDÊNCIA"**.
  * **Trava de Segurança (Q7):** Validar que os botões **"SELAR VEREDITO"** e **"RECUSAR VEREDITO"** não estão mais na árvore DOM deste card.
* **Validação SQL (psql):**
  ```sql
  SELECT status FROM public.sanction_review_queue WHERE id = '<QUEUE_ID>';
  -- Esperado: status = 'disputed'
  ```

---

### Grupo 3: Fluxo de Resolução de Disputas (Ajuste do FSM)

#### CT08: Resolução de Disputa - Cancelar Solicitação (Retract)
* **Objetivo:** Retrair uma disputa e fazê-la retornar para pendente de análise.
* **Passos Playwright:**
  1. Na aba **"Aguardando Evidência"**, localizar o card.
  2. Clicar no botão **"CANCELAR SOLICITAÇÃO"** (seletor: `button:has-text("CANCELAR SOLICITAÇÃO")`).
* **O que validar (Playwright):**
  * O card some da aba "Aguardando Evidência".
  * Clicar na aba **"Pendentes"**. O card VEL-01 deve constar na lista novamente com status de análise normal.
* **Validação SQL (psql):**
  ```sql
  -- 1. Verificar Fila de Revisão
  SELECT status, reviewed_at, rejection_reason
  FROM public.sanction_review_queue
  WHERE id = '<QUEUE_ID>';
  -- Esperado: status = 'pending', reviewed_at = NULL, rejection_reason = NULL.

  -- 2. Verificar Evento no Ledger
  SELECT type
  FROM public.sla_audit_ledger_v2
  WHERE organization_id = '00000000-0000-0000-0000-000000000001'
  ORDER BY occurred_at_utc DESC
  LIMIT 1;
  -- Esperado: type = 'DISPUTE_RETRACTED'
  ```

---

#### CT09: Resolução de Disputa - Aceitar Justificativa (Accept)
* **Objetivo:** Resolver a disputa aceitando a evidência apresentada (inibindo a multa).
* **Passos Playwright:**
  1. Envie a infração do CT08 novamente para disputa clicando em **"SOLICITAR PROVA FORENSE"**.
  2. Vá para a aba **"Aguardando Evidência"**.
  3. Clicar no botão **"ACEITAR JUSTIFICATIVA"** (`button:has-text("ACEITAR JUSTIFICATIVA")`).
  4. No campo de texto expandido, digitar: `Evidência de trânsito em via alternativa aceita.`
  5. Clicar no botão **"CONFIRMAR ACEITE"** (`button:has-text("CONFIRMAR ACEITE")`).
* **O que validar (Playwright):**
  * O card some da aba "Aguardando Evidência".
* **Validação SQL (psql):**
  ```sql
  -- 1. Verificar Status na Fila
  SELECT status, rejection_reason, reviewed_at
  FROM public.sanction_review_queue
  WHERE id = '<QUEUE_ID>';
  -- Esperado: status = 'rejected', reviewed_at NOT NULL, rejection_reason = 'Evidência de trânsito em via alternativa aceita.'

  -- 2. Verificar Registro no Ledger
  SELECT type, payload
  FROM public.sla_audit_ledger_v2
  WHERE organization_id = '00000000-0000-0000-0000-000000000001'
  ORDER BY occurred_at_utc DESC
  LIMIT 1;
  -- Esperado: type = 'DISPUTE_ACCEPTED'
  -- payload deve conter a justificativa de resolução.
  ```

---

#### CT10: Resolução de Disputa - Recusar Justificativa (Overturn)
* **Objetivo:** Recusar a justificativa do motorista/contratante e aplicar a multa definitivamente (Gerando snapshot forense).
* **Passos Playwright:**
  1. *(Preparação)*: Na aba **"Pendentes"**, clique em **"Gerar Sanção de Teste"** para criar um novo card. Aguarde 3s.
  2. No novo card gerado, clique em **"SOLICITAR PROVA FORENSE"**.
  3. Vá para a aba **"Aguardando Evidência"**.
  4. Localize o novo card e anote o ID do banco correspondente (será o `<QUEUE_ID_2>`).
  5. Clicar no botão **"RECUSAR JUSTIFICATIVA"** (`button:has-text("RECUSAR JUSTIFICATIVA")`).
  6. No campo expandido, preencher: `Justificativa sem embasamento técnico forense.`
  7. Clicar no botão **"CONFIRMAR RECUSA"** (`button:has-text("CONFIRMAR RECUSA")`).
* **O que validar (Playwright):**
  * O card some da aba "Aguardando Evidência".
* **Validação SQL (psql):**
  ```sql
  -- 1. Verificar Fila
  SELECT status, rejection_reason, reviewed_at
  FROM public.sanction_review_queue
  WHERE id = '<QUEUE_ID_2>';
  -- Esperado: status = 'applied', reviewed_at NOT NULL.

  -- 2. Verificar Evento de Overturn no Ledger
  SELECT type, payload
  FROM public.sla_audit_ledger_v2
  WHERE organization_id = '00000000-0000-0000-0000-000000000001'
  ORDER BY occurred_at_utc DESC
  LIMIT 1;
  -- Esperado: type = 'DISPUTE_OVERTURNED'
  -- payload deve conter a chave "snapshot_id" correspondente ao snapshot forense.
  ```

---

### Grupo 4: Visibilidade e Logs ( OCC e Concluídos)

#### CT11: Aba "Concluídos" (Fim das Multas-Fantasma)
* **Objetivo:** Validar se as decisões tomadas no CT09 e CT10 são visíveis na lista de concluídos.
* **Passos Playwright:**
  1. Na Fila Auditora, clicar na aba **"Concluídos"** (anteriormente "Selados").
  2. Verificar a presença de ambos os cards de vereditos resolvidos.
* **O que validar (Playwright):**
  * No card resolvido via **Ramo 2 (CT09)**:
    - Deve exibir o badge vermelho **"VEREDITO RECUSADO"** (ícone de block).
    - Deve exibir a borda lateral vermelha atenuada.
    - Deve exibir o painel com o texto: `"MOTIVO DA RECUSA: Evidência de trânsito em via alternativa aceita."`.
  * No card resolvido via **Ramo 3 (CT10)**:
    - Deve exibir o badge cinza **"SELADO"** (ícone de cadeado).
    - Deve possuir a borda cinza.

---

#### CT12: Auditoria OCC - Layout Read-Only Table-First
* **Objetivo:** Validar se a tela de log de auditoria operacional respeita o novo layout.
* **Passos Playwright:**
  1. No menu, clicar em **"Auditoria OCCS"** ou navegar para `/operational-audit`.
* **O que validar (Playwright):**
  * Validar que a tabela de log de auditoria ocupa 100% da largura visível da tela.
  * Validar que o botão flutuante verde (FAB) **"Nova Viagem"** foi removido.
  * Validar que a coluna do cabeçalho da tabela exibe `"Autor / Sistema"`.
  * Validar que a coluna `"HORA"` exibe valores formatados como `HH:mm:ss LOCAL`.

---

#### CT13: Auditoria OCC - endDrawer e Desseleção
* **Objetivo:** Validar a abertura e fechamento do painel lateral de logs.
* **Passos Playwright:**
  1. Na tabela de logs de auditoria, clicar em qualquer linha da tabela.
* **O que validar (Playwright):**
  * O painel lateral (endDrawer) se abre à direita da tela.
  * A linha da tabela correspondente ao item clicado deve estar destacada.
  * O painel lateral deve apresentar a dupla referência de hora: o horário local da operação e a linha contendo o label **"Timestamp UTC"**.
  * Clicar no botão **"X"** (ou fechar) no cabeçalho do drawer.
  * O painel lateral deve se fechar e a linha selecionada da tabela deve perder o destaque (deselect).

---

### Grupo 5: Segurança, RLS e Anti-Fraude

#### CT14: Detecção de Adulteração de Evidência (INV-9 / INV-21)
* **Objetivo:** Garantir o travamento preventivo do dossiê caso ocorra fraude na base de dados.
* **Passos Playwright:**
  1. Na aba **"Concluídos"** da Fila Auditora, localizar o card com o veredito aplicado (Ramo 3 - CT10).
  2. Clicar no botão **"Visualizar Evidência Forense"** do card.
  3. Confirmar que o modal se abre exibindo o selo verde **"Cópia Autenticada"**. Fechar o modal.
* **Ação SQL (psql - Simulação de Fraude de DBA):**
  ```sql
  -- 1. Buscar o ID do ledger correspondente ao veredito
  SELECT ledger_entry_id FROM public.sanction_review_queue
  WHERE id = '<COLOQUE_O_ID_DO_CARD_AQUI>';

  -- 2. Alterar o snapshot simulando invasão
  UPDATE public.forensic_evidence_snapshots
  SET snapshot = jsonb_set(snapshot, '{rules,0,rule_config,threshold_minutes}', '999')
  WHERE ledger_entry_id = '<COLOQUE_O_LEDGER_ENTRY_ID_BUSCADO>';
  ```
* **Passos Playwright (Validação de Bloqueio):**
  4. Na UI, clicar novamente no botão **"Visualizar Evidência Forense"** do mesmo card.
* **O que validar (Playwright):**
  * O modal não exibe mais as regras e parâmetros da evidência.
  * Um banner vermelho contendo o texto **"Divergência Crítica de Integridade"** deve estar visível.
  * O botão **"ESCALAR INCIDENTE"** deve aparecer.
  * Clicar em **"ESCALAR INCIDENTE"**.
  * Verificar a exibição do SnackBar informando sobre o escalonamento.
* **Validação SQL (psql):**
  ```sql
  SELECT status, details
  FROM public.sanction_escalation_logs
  ORDER BY created_at DESC
  LIMIT 1;
  -- Esperado: status = 'escalated'. details contendo o ID do ledger adulterado.
  ```

---

#### CT15: Isolamento de Tenant (Red Team - INV-22)
* **Objetivo:** Garantir que o Inquilino B não enxergue dados do Inquilino A.
* **Passos Playwright:**
  1. Realizar logout clicando no botão no topo direito da tela.
  2. Preencher no login:
     - E-mail: `admin-b@veraprob.dev`
     - Senha: `123456`
  3. Clicar em **"ACESSAR SISTEMA"**.
  4. Navegar até a **"Fila Auditora"**.
  5. Clicar na aba **"Concluídos"**.
* **O que validar (Playwright):**
  * A tabela/lista deve estar vazia (ou não conter as sanções geradas para o Inquilino A nos passos anteriores).
* **Validação SQL (psql - Simular RLS de API):**
  ```sql
  -- Tentar acessar dados da Org A usando credenciais/contexto da Org B
  BEGIN;
  SET LOCAL ROLE authenticated;
  SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"11111111-1111-1111-1111-111111111111","organization_id":"00000000-0000-0000-0000-000000000002"}';

  SELECT count(*) FROM public.sanction_review_queue
  WHERE organization_id = '00000000-0000-0000-0000-000000000001';
  -- Esperado: 0 linhas.
  COMMIT;
  ```

---

#### CT16: Anti-Oracle URL Direct Routing (INV-26)
* **Objetivo:** Garantir que buscas por IDs de outros tenants retornem 404 neutro.
* **Passos Playwright:**
  1. Mantendo-se logado como **Inquilino B**, acessar a URL de detalhes de um contratante do Inquilino A:
     `http://localhost:50185/#/admin/contractors/<CONTRATANTE_ID_ORG_A>`
* **O que validar (Playwright):**
  * O sistema deve redirecionar ou exibir uma mensagem neutra "Recurso não encontrado" ou redirecionar para a listagem local, sem apresentar tela de erro de permissão que exponha a existência do ID.

---

## 📊 Matriz de Aceitação UAT (Checklist para Agente Playwright)

| Cód | Ação Playwright / psql | Seletor HTML / Comando SQL | Esperado | Status |
|:----|:----------------------|:---------------------------|:---------|:------:|
| **UAT-01** | Login Inquilino A | `button:has-text("ACESSAR SISTEMA")` | Redirecionamento completo. | `[ ]` |
| **UAT-02** | Criar Contratante | CNPJ `91.101.494/0001-56` | Contratante exibido na tabela. | `[ ]` |
| **UAT-03-A** | Criar Contrato | `button:has-text("ATIVAR CONTRATO")` | Redirecionamento para detalhes do contrato. | `[ ]` |
| **UAT-03-B** | Criar Zonas Operacionais | `button:has-text("Criar Zona")` | Ambas as zonas são criadas com geofence no banco. | `[ ]` |
| **UAT-03-C** | Declarar Plano Operacional | `button:has-text("Publicar SLA B2B")` | Plano operacional criado vinculado ao contrato. | `[ ]` |
| **UAT-04** | Injetar Sanção | `button:has-text("Gerar Sanção de Teste")` | Card VEL-01 surge na aba Pendentes. | `[ ]` |
| **UAT-05** | Veto de justificativa curta | Input < 10 caracteres | Botão `CONFIRMAR RECUSA` fica desabilitado. | `[ ]` |
| **UAT-06** | Envio de Disputa | `button:has-text("SOLICITAR PROVA FORENSE")` | Card move para a aba "Aguardando Evidência". | `[ ]` |
| **UAT-07** | Cancelamento Disputa | `button:has-text("CANCELAR SOLICITAÇÃO")` | Card volta a Pendentes (status `pending`). | `[ ]` |
| **UAT-08** | Aceite de Disputa | `button:has-text("CONFIRMAR ACEITE")` | Card arquiva em Concluídos como `rejected`. | `[ ]` |
| **UAT-09** | Recusa de Disputa | `button:has-text("CONFIRMAR RECUSA")` | Card arquiva em Concluídos como `applied`. | `[ ]` |
| **UAT-10** | Visibilidade Concluídos | Aba `"Concluídos"` | Mostra cartões recusados (vermelho) e aplicados (cinza). | `[ ]` |
| **UAT-11** | Auditoria OCC | `/operational-audit` | Layout 100% width, sem FAB "Nova Viagem". | `[ ]` |
| **UAT-12** | endDrawer de logs | Clicar na linha da tabela | Drawer abre com duplo fuso de hora (Local/UTC). | `[ ]` |
| **UAT-13** | Anti-Fraude (INV-9) | SQL update snapshot | Modal bloqueia dados, mostra banner e Escalar. | `[ ]` |
| **UAT-14** | Isolamento RLS | Login Inquilino B | 0 dados do Inquilino A visíveis na UI. | `[ ]` |
| **UAT-15** | Anti-Oracle (INV-26) | Acesso direto a URL de outro tenant | Retorna 404 neutro. | `[ ]` |
| **UAT-16** | Índice Concluídos | `idx_srq_org_status_concluded_at` | Índice ativo no banco de dados. | `[ ]` |
| **UAT-17** | Constraint de Tipos | `chk_ledger_type` | Bloqueia inserts de tipos inválidos no ledger. | `[ ]` |
