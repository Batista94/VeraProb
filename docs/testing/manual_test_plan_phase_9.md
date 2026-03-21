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

### Passo 1.2: Criar uma Nova Organização
1.  Clique em **"Nova Organização"**.
2.  Preencha os dados (ex: Nome: `Logística ABC`, CNPJ: `12.345.678/0001-99`).
3.  No passo final, insira um e-mail para o **Admin da Organização** (ex: `admin@abc.com`).
4.  **Resultado Esperado:** O sistema deve exibir "Organização criada com sucesso".
5.  **Validação Técnica:** Abra o **Supabase Studio** e verifique se a tabela `organizations` agora tem uma linha para a `Logística ABC`.

### Passo 1.3: Aceitar Convite do Admin (via Email ou Link Manual)

*Objetivo: Verificar que o link de aceitação funciona. Email é canal complementar — o link no diálogo é o caminho principal.*

> ⚠️ **Nota sobre email em dev:** O `notify-invite` chama a API do Resend diretamente — **não usa o SMTP interno do Supabase**. Por isso o email **não aparece no Inbucket** (localhost:54324). Em dev, use sempre o link do diálogo. O email só chegará na caixa real se `RESEND_API_KEY` estiver configurada via `supabase secrets set` **e** a Edge Function estiver rodando (`supabase functions serve`).

**Fluxo principal (link manual — funciona sempre em dev):**
1.  No diálogo de sucesso (ainda aberto), localize o campo **"Link de convite do Admin"**.
2.  Clique no **ícone de cópia** (clipboard) ao lado do link.
    -   **Resultado Esperado:** SnackBar **"Link copiado!"** aparece na parte inferior.
3.  Abra o link em uma **nova aba**: formato `http://localhost:PORT/accept-invite?token=UUID`
4.  Na tela **"Aceitar Convite"**, insira uma senha para `admin@abc.com` (ex: `Admin@abc123!`).
5.  Confirme. **Resultado Esperado:** Sistema aceita e redireciona para a tela de login.
6.  Volte à aba principal. Feche o diálogo (clique **"Ver Tenants"**) e faça logout do SuperAdmin.
    -   **Validação Bug 1:** O app deve ir **direto para a tela de login**, sem exibir "Acesso Negado".
7.  Faça login com `admin@abc.com` e a senha definida no passo 4.
    -   **Resultado Esperado:** Login bem-sucedido, redirecionando para o OCC/AdminHome da `Logística ABC`.

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
1.  Saia do SuperAdmin e faça login com o usuário `admin@abc.com` que você criou.
2.  Navegue pelo menu lateral.
3.  **O que observar:** O último item da lista deve ser **"Fila Auditora"**. Clique nele.
4.  **Resultado Esperado:** A tela deve mostrar "Nenhuma sanção pendente" com um ícone verde.
5.  Navegue para outra tela e volte para "Fila Auditora". **O app não deve travar ou dar erro.**

### Passo 2.2: O Badge em Tempo Real (MT-9.3.2)
Para testar a reatividade sem esperar um caminhão de verdade, vamos simular uma infração:
1.  Abra o **Supabase Studio** → Tabela `sla_audit_ledger_v2`.
2.  Insira uma linha com `type = 'SANCTION_RECOMMENDED'`.
    *   **Payload Sugerido:**
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
3.  **O que observar no App (sem dar F5):**
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
1.  Faça logout e entre com um usuário de role `operator`.
2.  Navegue pelo menu lateral.
3.  **Resultado Esperado:** O item **"Fila Auditora" não deve aparecer** na navegação.

> **Nota:** Se a visibilidade por role ainda não foi filtrada (debt registrado para Phase 9.4), documente o comportamento atual aqui para rastreabilidade.

---

## 🛡️ Parte 5: Defesa Forense (Testes de "Invasão")

*A VeraProb é um "Juiz Blindado". Vamos tentar quebrar as regras.*

### Passo 5.1: Isolamento Cross-Tenant (MT-9.3.7 — INV-6)
1.  Crie uma sanção fake logado como usuário da `Logística ABC` (repita o Passo 2.2).
2.  Faça logout e entre como usuário de **outra organização** (crie uma segunda org no SuperAdmin se necessário).
3.  **Resultado Esperado:** A "Fila Auditora" deve estar **vazia** para o segundo tenant. A sanção da `Logística ABC` é invisível.

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

## ✅ Conclusão

| Teste | Referência | Resultado |
|---|---|---|
| Fila Auditora na navegação (admin) | MT-9.3.1 | [ ] PASS / [ ] FAIL |
| Badge em tempo real (<30s) | MT-9.3.2 | [ ] PASS / [ ] FAIL |
| Anatomia completa do card (6 campos) | MT-9.3.3 | [ ] PASS / [ ] FAIL |
| Fluxo VALIDAR completo | MT-9.3.4 | [ ] PASS / [ ] FAIL |
| Fluxo REJEITAR com validação de texto | MT-9.3.5 | [ ] PASS / [ ] FAIL |
| Operator não vê a Fila Auditora | MT-9.3.6 | [ ] PASS / [ ] FAIL / [ ] DEBT |
| Isolamento cross-tenant (INV-6) | MT-9.3.7 | [ ] PASS / [ ] FAIL |
| Idempotência sem duplicatas (INV-24) | MT-9.3.8 | [ ] PASS / [ ] FAIL |
| Imutabilidade UPDATE+DELETE (INV-1) | MT-9.3.9 | [ ] PASS / [ ] FAIL |
| VerdictEvidence 64-char hash (INV-23) | MT-9.3.10 | [ ] PASS / [ ] FAIL |
| Link de convite copiável e funcional | Passo 1.3 | [ ] PASS / [ ] FAIL |
| Email de convite entregue (Inbucket/Resend) | Passo 1.3 | [ ] PASS / [ ] FAIL / [ ] SKIP (sem RESEND_API_KEY) |
| SuperAdmin onboarding <5 min | Phase 9.2 | [ ] PASS / [ ] FAIL |

Se todos os itens acima estiverem marcados como **PASS** (ou **DEBT** com rastreabilidade documentada para MT-9.3.6), a **Phase 9.2 + 9.3** está validada para entrada em produção.
