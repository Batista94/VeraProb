# 🛡️ Guia de Testes Manuais — VeraProb (Fase 9)

Este guia foi criado para que **qualquer pessoa**, mesmo sem conhecimento prévio do sistema, consiga validar se a **VeraProb** está pronta para operar. Siga os passos na ordem exata.

> **Nota:** Este guia cobre a validação humana de interface e comportamento. Não substitui os testes automatizados (unit/integration/e2e) nem o [GO] Verdict do Lead Reviewer, mas é pré-requisito para ambos.

---

## 🚀 Passo 0: Preparação do Ambiente

Antes de começar, precisamos "limpar a mesa" e ligar o motor.

1.  **Reset do Banco de Dados:** No seu terminal, execute:
    ```bash
    supabase db reset
    ```
    *Isso garante que não existam dados "sujos" de testes anteriores.*

2.  **Bootstrap dos usuários de teste:** O `db reset` cria as tabelas e as orgs de teste, mas **não cria os usuários** (por design — o schema de `auth.users` muda entre versões do Supabase CLI). Execute:
    ```bash
    node scripts/bootstrap_dev.mjs
    ```
    O script vai criar 3 usuários via Admin API e exibir as credenciais:

    | Usuário | Email | Senha | Rota após login |
    |---|---|---|---|
    | **SuperAdmin** | `master@veraprob.dev` | `veraprob123!` | `SuperAdminShell` (portal isolado) |
    | Admin Org Alpha | `admin-a@veraprob.dev` | `veraprob123!` | OCC / AdminHome |
    | Admin Org Beta | `admin-b@veraprob.dev` | `veraprob123!` | OCC / AdminHome |

    > **Por que isso é necessário?** O roteamento do app verifica o claim `super_admin: true` no JWT (injetado pelo `custom_access_token_hook`). Esse claim só existe se o usuário estiver na tabela `super_admin_users` — que o script popula. Sem isso, qualquer login vai para a tela do OCC, nunca para o SuperAdmin.

3.  **Iniciar o App:** No VS Code ou terminal, execute:
    ```bash
    flutter run -d chrome
    ```
    *O app carrega `.env` automaticamente via `flutter_dotenv`. Não use `--dart-define-from-file` — o arquivo `.env.development` não existe. Aguarde o navegador abrir na tela de Login.*

---

## 🏛️ Parte 1: Onboarding (Phase 9.2 — SuperAdmin)

*Objetivo: Criar uma nova empresa (Tenant) do zero sem tocar no banco de dados.*

### Passo 1.1: Login como Super-Herói
1.  Na tela de login, use as credenciais de **SuperAdmin** (veja seu `.env` ou use o usuário padrão do bootstrap).
2.  **O que observar:** Você deve ver uma aba ou menu chamado **"Super Admin"** que usuários comuns não veem.
3.  **Segurança (Idle Timeout):** Deixe a tela aberta sem mover o mouse ou clicar por 5 minutos (teste de paciência forense).
    - **Resultado Esperado (5 min):** Um alerta de inatividade ("Aviso de Inatividade") aparecerá solicitando confirmação.
    - **Resultado Esperado (7 min):** O sistema deve deslogar automaticamente a sessão do SuperAdmin (forçando `signOut`) e voltar para a tela de login. Faça login novamente para prosseguir.

### Passo 1.2: Criar uma Nova Organização
1.  Clique em **"Nova Organização"**.
2.  Preencha os dados (ex: Nome: `Logística ABC`, CNPJ: `12.345.678/0001-99`).
3.  No passo final, insira um e-mail para o **Admin da Organização** (ex: `admin@abc.com`).
4.  **Resultado Esperado:** O sistema deve exibir "Organização criada com sucesso".
5.  **Validação Técnica no Supabase Studio:** Abra o Studio e verifique as três tabelas abaixo:
    - **`organizations`**: deve conter uma linha para `Logística ABC`.
    - **`tenant_billing_events`**: deve conter uma linha com `event_type = 'ORG_CREATED'`. Verifique que a coluna **`organization_name`** está preenchida com `Logística ABC` (não pode ser nulo — rastreabilidade sem JOIN).
    - **`system_audit_log`**: deve conter uma linha com `event_type = 'ORGANIZATION_CREATED'` e `payload` com `legal_name`, `trade_name`, `cnpj`, `plan_type` e `super_admin_id` preenchidos.
6.  **Validação Unicidade Fiscal:** Tente iniciar a criação de uma segunda organização (ex. `Transportadora Beta`) colocando estritamente o **mesmo CNPJ** da `Logística ABC`.
    - **Resultado Esperado:** O sistema rejeitará na hora da submissão com o aviso vermelho indicando que o CNPJ já possui uma organização vinculada.

### Passo 1.3: Aceitar Convite do Admin (via Email ou Link Manual)

*Objetivo: Verificar que o link de aceitação funciona. Email é canal complementar — o link no diálogo é o caminho principal.*

> ⚠️ **Nota sobre email em dev:** O `notify-invite` chama a API do Resend diretamente — **não usa o SMTP interno do Supabase**. Por isso o email **não aparece no Inbucket** (localhost:54324). Em dev, use sempre o link do diálogo. O email só chegará na caixa real se `RESEND_API_KEY` estiver configurada via `supabase secrets set` **e** a Edge Function estiver rodando (`supabase functions serve`).

> ⚠️ **Isolamento de sessão obrigatório:** `supabase_flutter` no Flutter Web armazena o token de autenticação no `localStorage` usando uma chave única por origem (`sb-*-auth-token`). Se o link de convite for aberto na **mesma janela ou em uma aba normal**, o login do Admin sobrescreve o token do SuperAdmin — derrubando a sessão do SuperAdmin imediatamente. **Isso é uma limitação arquitetural do `localStorage` no browser, não um bug do app.** A solução é sempre abrir o link do convite em uma **janela anônima/privada (Incognito)**, que possui um namespace de `localStorage` isolado.

**Fluxo principal (link manual — funciona sempre em dev):**
1.  No diálogo de sucesso (ainda aberto), localize o campo **"Link de convite do Admin"**.
2.  Clique no **ícone de cópia** (clipboard) ao lado do link.
    -   **Resultado Esperado:** SnackBar **"Link copiado!"** aparece na parte inferior.
3.  Abra uma **janela anônima/privada (Incognito)** no Chrome (`Ctrl+Shift+N`) e cole o link: formato `http://localhost:PORT/accept-invite?token=UUID`
    - **Nunca use uma aba normal** — isso derrubará a sessão do SuperAdmin na janela #1 (ver nota acima).
4.  Na tela **"Aceitar Convite"**, insira uma senha para `admin@abc.com` (ex: `Admin@abc123!`).
5.  Confirme. **Resultado Esperado:** O sistema aceita o envio, faz o login (signIn/signUp) automaticamente pelas cortinas e redireciona (faz reload da página) para a raiz `/`.
    - **Validação Bug (URL segura):** Repare na barra de endereços do navegador da janela incognito. A URL deve estar perfeitamente limpa (sem o `?token=...` antigo grudado nela).
6.  Como a aba recarregou autenticada, você será redirecionado imediatamente para o painel principal do OCC da `Logística ABC`.
7.  Volte à **janela normal** onde o **SuperAdmin** ficou aberto (janela #1). Feche o diálogo do wizard clicando em **"Ver Tenants"**.
    - **Resultado Esperado:** O SuperAdmin permanece logado na janela #1 (pois o incognito tem localStorage isolado). Faça Logout manualmente clicando no ícone de Sair na barra lateral.
8.  Verifique a janela incognito (#2) do Admin. A responsividade está corrigida: se diminuir o tamanho da janela horizontalmente nas telas de configuração inicial ("Configuração 0/4 Zonas..."), os indicadores devem agora rolar lateralmente (horizontal scroll) em vez de exibir tela preta e amarela (Overflow).

**Validação do email (opcional — requer Edge Function rodando localmente):**
-   Em um terminal separado: `supabase functions serve notify-invite`
-   Use um email real seu como destinatário (ex: `seuemail@gmail.com`) no wizard.
-   O email chegará na sua caixa real vindo de `onboarding@resend.dev`.

**Em staging/produção (Resend automático):**
-   O email é disparado automaticamente. O fluxo do passo 3 em diante é idêntico.
-   **Segurança:** O link é de uso único (token consumido na aceitação). Após aceito, reuso retorna erro.

---

## 🕵️ Parte 2: O Auditor Reativo (Phase 9.3 — MT-9.3.1 e MT-9.3.2)

*Objetivo: Validar que o sistema detecta infrações e permite que um humano decida o destino financeiro.*

### Passo 2.1: Login como Auditor (MT-9.3.1)

> **Continuação do Passo 1.3:** Você já está logado como `admin@abc.com` na **janela incognito** (#2). Continue nessa janela — não é necessário fazer login novamente.

1.  Na janela incognito (OCC da `Logística ABC`), navegue pelo menu lateral.
2.  **O que observar:** O último item da lista deve ser **"Fila Auditora"**. Clique nele.
3.  **Resultado Esperado:** A tela deve mostrar "Nenhuma sanção pendente" com um ícone verde.
4.  Navegue para outra tela e volte para "Fila Auditora". **O app não deve travar ou dar erro.**

### Passo 2.2: O Badge em Tempo Real (MT-9.3.2)

Para testar a reatividade sem esperar um caminhão de verdade, vamos simular uma infração inserindo diretamente no banco:

> ⚠️ **Campos obrigatórios para o insert:** A tabela `sla_audit_ledger_v2` tem colunas `NOT NULL` sem valor padrão. Sem elas, o Studio rejeita o insert. Além disso, o trigger `trg_auto_enqueue_sanction` popula automaticamente a `sanction_review_queue` a partir de `payload -> 'verdict_evidence'` — portanto o payload **deve** conter a chave `verdict_evidence` na raiz.

**Antes de inserir, obtenha o `organization_id` da Logística ABC:**
- No Supabase Studio, abra a tabela `organizations`, filtre pelo nome `Logística ABC` e copie o valor da coluna `id` (UUID). Você vai precisar dele agora.

1.  Abra o **Supabase Studio** → Tabela `sla_audit_ledger_v2` → **Insert row**.
2.  Preencha os campos conforme abaixo:

    | Campo | Valor |
    |---|---|
    | `organization_id` | UUID copiado da `Logística ABC` (passo acima) |
    | `type` | `SANCTION_RECOMMENDED` |
    | `occurred_at_utc` | `now()` — clique no campo e escolha a data/hora atual |
    | `payload` | JSON completo abaixo |
    | `set_id` | `VEI-001` (texto livre — identifica o veículo) |
    | `operator_id` | deixar em branco (nullable) |

    **Payload (cole no campo `payload`):**
    ```json
    {
      "clause_ref": "VEL-01",
      "fine_cents": 150000,
      "verdict_evidence": {
        "rule_id": "rule-vel-01",
        "rule_version": "1.0",
        "gps_lat": -23.5505,
        "gps_lng": -46.6333,
        "primary_evidence_timestamp_utc": "2026-03-20T10:00:00Z",
        "delta_value": 15,
        "threshold_value": 80,
        "confidence_score": 0.97,
        "evidence_hash": "a3f1c2d4e5b6a7f8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2"
      }
    }
    ```

3.  Salve o insert. **Verifique imediatamente:** o Studio deve aceitar sem erro. Se aparecer erro `restrict_violation` em algum campo imutável, revise os campos preenchidos.

4.  **O que observar no App (sem dar F5):**
    - Um **badge numérico** (círculo vermelho com "1") deve aparecer no ícone da "Fila Auditora" em menos de 30 segundos.
    - Um novo card deve aparecer na lista automaticamente.

### Passo 2.3: Anatomia Completa da Prova (MT-9.3.3)
Olhe para o card que apareceu. Ele deve conter **todos** os campos abaixo:
- [ ] Contrato ID e SET (identificação do veículo/ativo)
- [ ] Cláusula infringida (ex: `VEL-01`)
- [ ] Valor da infração (`deltaValue`) e o limite contratual (`thresholdValue`) — ex: "15 min acima de 80 km/h"
- [ ] Multa formatada em reais (ex: **R$ 1.500,00**)
- [ ] Índice de confiança em % (ex: "97%")
- [ ] Seção **"Proveniência"** com:
    - Coordenadas GPS (lat/lng)
    - Horário em UTC
    - Hash SHA-256 abreviado (ex: `a3f1c2d4...` — primeiros 12 chars + "...")

> Se algum desses campos estiver ausente, a prova é incompleta e a sanção **não é juridicamente defensável** (viola INV-23).

---

## ⚖️ Parte 3: O Veredito Humano

### Passo 3.1: Validar / Aprovar (MT-9.3.4)
1.  No card, clique em **[VALIDAR]**.
2.  **O que observar durante o clique:**
    - O botão deve exibir um estado de carregamento (spinner ou desabilitar) enquanto processa.
3.  **Resultado Esperado após sucesso:**
    - O card **desaparece** da fila.
    - O badge numérico **decrementa** (ou some se era o único).
4.  **Validação no Banco de Dados (Supabase Studio):**
    - Tabela `sla_audit_ledger_v2`: nova linha com `type = 'SANCTION_APPLIED'` e o campo `payload -> 'verdict_evidence'` **preservado** (não pode ser nulo).
    - Tabela `sanction_review_queue`: o registro correspondente deve ter `status = 'applied'`.

### Passo 3.2: Rejeitar (Com Justificativa) (MT-9.3.5)
1.  Crie outra sanção fake (repita o Passo 2.2).
2.  Clique em **[REJEITAR]**.
3.  **O que observar:**
    - Um campo de texto deve aparecer **inline** (sem abrir nova tela).
    - Digite "Erro" (4 letras) → O botão **"CONFIRMAR REJEIÇÃO"** deve estar **desabilitado**.
    - Digite "Placa do veículo não confere com a imagem" (mais de 10 letras) → O botão **habilita**.
4.  Confirme a rejeição.
5.  **Resultado Esperado:**
    - O card desaparece da fila.
6.  **Validação no Banco de Dados:**
    - Tabela `sla_audit_ledger_v2`: nova linha `SANCTION_REJECTED` com `rejection_reason` no payload.
    - Tabela `sanction_review_queue`: `status = 'rejected'` e `rejection_reason` preenchido.

---

## 🔐 Parte 4: Controle de Acesso (MT-9.3.6)

*Objetivo: Verificar que roles sem permissão não veem a Fila Auditora.*

### Passo 4.1: Login como Operador

> ⚠️ **O bootstrap não cria usuário `operator` automaticamente.** Para executar este teste, crie um usuário operator manualmente:
> 1. No Supabase Studio → Auth → Users → **Add user** (email: `operator@abc.com`, senha: `Operator123!`).
> 2. Copie o `id` UUID do novo usuário.
> 3. Na tabela `user_roles`, insira: `user_id = <uuid copiado>`, `organization_id = <id da Logística ABC>`, `role = 'OPERATOR'`.
> 4. Não é necessário configurar `app_metadata` manualmente — o `custom_access_token_hook` injeta o `role` no JWT no próximo login.

1.  Faça logout e entre com `operator@abc.com` / `Operator123!`.
2.  Navegue pelo menu lateral.
3.  **Resultado Esperado:** O item **"Fila Auditora" não deve aparecer** na navegação.

> **Nota:** Se a visibilidade por role ainda não foi filtrada (debt registrado para Phase 9.4), documente o comportamento atual aqui para rastreabilidade.

---

## 🛡️ Parte 5: Defesa Forense (Testes de "Invasão")

*A VeraProb é um "Juiz Blindado". Vamos tentar quebrar as regras.*

### Passo 5.1: Isolamento Cross-Tenant (MT-9.3.7 — INV-6)

> ⚠️ **O Supabase Studio conecta como `service_role` — RLS não se aplica na visualização do Studio.** Este teste deve ser feito **dentro do app**, não observando o Studio. O Studio pode ser usado apenas para confirmar os dados no banco após o teste.

1.  Certifique-se de que existe pelo menos uma sanção fake na fila da `Logística ABC` (criada no Passo 2.2 ou 3.2). Verifique no app que ela está visível logado como `admin@abc.com`.
2.  Faça logout da `Logística ABC`.
3.  Faça login com o usuário **`admin-b@veraprob.dev`** (Admin da Org Beta — criado pelo bootstrap).
4.  Navegue para **"Fila Auditora"** no app.
5.  **Resultado Esperado (no app):** A "Fila Auditora" deve estar **vazia** para a Org Beta. A sanção da `Logística ABC` é invisível — RLS está funcionando.
6.  **Confirmação opcional no Studio:** Em `sanction_review_queue`, filtre por `organization_id = <id Org Beta>` — deve retornar zero linhas.

### Passo 5.2: Idempotência — Sem Duplicatas (MT-9.3.8 — INV-24)
1.  No Supabase Studio, abra a tabela `sanction_review_queue`.
2.  Copie o valor do campo `ledger_entry_id` de uma linha já existente.
3.  Tente **inserir manualmente** uma nova linha com o mesmo `ledger_entry_id`.
4.  **Resultado Esperado:** O banco deve ignorar silenciosamente (`ON CONFLICT DO NOTHING`) e a tabela deve ter apenas **uma linha** com aquele `ledger_entry_id`.

### Passo 5.3: Imutabilidade — Nada se Apaga ou Altera (MT-9.3.9 — INV-1)
1.  No Supabase Studio, abra a tabela `sanction_review_queue` e selecione qualquer linha.
2.  **Teste UPDATE:** Tente alterar o campo `organization_id` para qualquer outro valor.
    - **Resultado Esperado:** O banco deve retornar erro `restrict_violation`. **Campos imutáveis não se alteram.**
3.  **Teste DELETE:** Tente **apagar** a linha.
    - **Resultado Esperado:** O banco deve retornar erro de permissão ou `restrict_violation`. **Nada se apaga na VeraProb.**

### Passo 5.4: VerdictEvidence no Motor (MT-9.3.10 — INV-23)
1.  Execute um ciclo real de avaliação que gere uma sanção (ou use o dado inserido no Passo 2.2).
2.  No Supabase Studio, abra `sla_audit_ledger_v2` e filtre por `type = 'SANCTION_RECOMMENDED'`.
3.  **Validações obrigatórias:**
    - [ ] O campo `payload -> 'verdict_evidence'` **não é nulo**.
    - [ ] O campo `payload -> 'verdict_evidence' -> 'evidence_hash'` tem **exatamente 64 caracteres hexadecimais**.
    - [ ] Os campos `rule_id`, `rule_version`, `gps_lat`, `gps_lng` e `primary_evidence_timestamp_utc` estão presentes e preenchidos.

> Se o `evidence_hash` tiver menos de 64 chars ou `verdict_evidence` for nulo, a sanção viola INV-23 e **não pode ser aplicada**.

---

## 🔁 Parte 6: Stress Mode / Simular Operação (MT-9.2-SM)

*Objetivo: Verificar que o botão "Simular Operação" não gera mais o erro `TypeError: null is not a subtype of String` que existia antes da correção das colunas do `sla_audit_ledger_v2`.*

### Passo 6.1: Validar Simular Operação (MT-9.2-SM)
1.  Logado como `admin@abc.com` (janela incognito), localize o botão ou menu **"Simular Operação"** / **"Stress Mode"**.
2.  Clique em **"Simular Operação"**.
3.  **Resultado Esperado:**
    - Nenhuma tela vermelha de erro (Red Screen / Sentry error).
    - Nenhum `TypeError: null: type 'Null' is not a subtype of type 'String'` no terminal.
    - O app processa a simulação normalmente.
4.  **Verifique no terminal:** Não deve aparecer `[Sentry] Provider error in FutureProvider<AuditLogProjection>`.

---

## ✅ Conclusão

| Teste | Referência | Resultado |
|---|---|---|
| Fila Auditora na navegação (admin) | MT-9.3.1 | [ ] PASS / [ ] FAIL |
| Badge em tempo real (<30s) | MT-9.3.2 | [ ] PASS / [ ] FAIL |
| Anatomia completa do card (6 campos) | MT-9.3.3 | [ ] PASS / [ ] FAIL |
| Fluxo VALIDAR completo | MT-9.3.4 | [ ] PASS / [ ] FAIL |
| Fluxo REJEITAR com validação de texto | MT-9.3.5 | [ ] PASS / [ ] FAIL |
| Operator não vê a Fila Auditora | MT-9.3.6 | [ ] PASS / [ ] FAIL / [ ] DEBT |
| Isolamento cross-tenant no app (INV-6) | MT-9.3.7 | [ ] PASS / [ ] FAIL |
| Idempotência sem duplicatas (INV-24) | MT-9.3.8 | [ ] PASS / [ ] FAIL |
| Imutabilidade UPDATE+DELETE (INV-1) | MT-9.3.9 | [ ] PASS / [ ] FAIL |
| VerdictEvidence 64-char hash (INV-23) | MT-9.3.10 | [ ] PASS / [ ] FAIL |
| Simular Operação sem Red Screen | MT-9.2-SM | [ ] PASS / [ ] FAIL |
| organization_name em tenant_billing_events | Passo 1.2.5 | [ ] PASS / [ ] FAIL |
| ORGANIZATION_CREATED em system_audit_log | Passo 1.2.5 | [ ] PASS / [ ] FAIL |
| Link de convite copiável e funcional | Passo 1.3 | [ ] PASS / [ ] FAIL |
| Email de convite entregue (Inbucket/Resend) | Passo 1.3 | [ ] PASS / [ ] FAIL / [ ] SKIP (sem RESEND_API_KEY) |
| SuperAdmin onboarding <5 min | Phase 9.2 | [ ] PASS / [ ] FAIL |
| Validação Tenant Health Panel e DB Logs | Phase 9.2 | [ ] PASS / [ ] FAIL |

Se todos os itens acima estiverem marcados como **PASS** (ou **DEBT** com rastreabilidade documentada para MT-9.3.6), a **Phase 9.2 + 9.3** está validada para entrada em produção.
