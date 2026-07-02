# Plano de Testes UAT — Webhook de Veredito Selado e Notificações (Fase 10.7)

Este plano descreve o fluxo de testes de aceitação do usuário (UAT) para validar de ponta a ponta o Webhook de Veredito Selado, o Painel de Gerenciamento do Tenant Admin (CRUD, logs e replay), o modal Reveal-Once para segredo de assinatura e as notificações Resend.

---

## 1. Pré-requisitos e Setup

Antes de iniciar os testes, garanta que o ambiente esteja configurado:
1. **Banco e Serviços Locais Ativos:**
   ```bash
   supabase start
   make setup
   ```
2. **Variáveis de Ambiente:**
   Certifique-se de que o arquivo `.env` possui as chaves necessárias (especialmente `RESEND_API_KEY` para o fluxo de e-mail e as credenciais do Supabase).
3. **Receptor de Webhooks:**
   Obtenha uma URL temporária no [webhook.site](https://webhook.site/) para atuar como o endpoint de integração do receptor (B2B/ERP).

---

## 2. Cenário de Teste E2E (Passo a Passo)

### Passo 1: Login e Acesso ao Painel do Tenant Admin
* **Ação:** Faça login no VeraProb com um usuário com a role `TENANT_ADMIN`.
* **Ação:** Navegue até o painel de **Configurações de Integração (Webhooks)**.
* **Resultado Esperado:** A tela apresenta a lista de endpoints cadastrados (inicialmente vazia) e o botão "Novo Endpoint".

### Passo 2: Provisionar Novo Endpoint e Obter Segredo (Reveal-Once)
* **Ação:** Clique em **"Novo Endpoint"** / **"Adicionar"**.
* **Ação:** Insira a URL obtida do `webhook.site` e salve.
* **Resultado Esperado:** O modal **"Segredo de Assinatura"** deve abrir sob regras de segurança rígidas (foco bloqueado, blur no segredo).
* **Ação:** Clique em **"Revelar"**, copie a chave secreta gerada (em formato hex) e marque o checkbox de confirmação de segurança. Clique em **"Concluir"**.
* **Resultado Esperado:**
  - O modal fecha e a chave é completamente limpa da memória (não pode ser revelada novamente sem rotação).
  - O endpoint aparece na lista de Master-Detail com status inicial `ACTIVE` ou sem logs ainda.

### Passo 3: Simular Ocorrência e Veredito (Trigger de Telemetria)
Para testar a emissão transacional do webhook e notificação:
* **Ação:** Execute o script de simulação ou RPC para fechar um veredito de sanção (ex: transição de estado na tabela `sla_audit_ledger_v2` para um status terminal).
  * *Alternativa rápida por SQL/RPC:*
    ```sql
    -- Simula a inserção de um veredito na ledger para a org do teste
    INSERT INTO public.sla_audit_ledger_v2 (
      organization_id, 
      case_key, 
      verdict_outcome, 
      fine_cents, 
      payload
    ) VALUES (
      'sua-org-uuid-aqui', 
      'VP-UAT-2026-001', 
      'SEALED', 
      150000, -- R$ 1.500,00
      '{"reason": "Excesso de velocidade na zona controlada"}'
    );
    ```
* **Resultado Esperado:**
  - O trigger transacional grava a entrega na outbox (`webhook_delivery_logs`) com status `PENDING`.
  - Uma notificação de e-mail é enfileirada em `carrier_notification_outbox` com status `PENDING`.

### Passo 4: Validação do Webhook no Receptor
* **Ação:** Acesse o painel do `webhook.site` e inspecione a requisição recebida.
* **Resultado Esperado:**
  - O payload JSON completo da violação deve estar disponível.
  - A requisição deve conter o cabeçalho `X-Veraprob-Signature`.
* **Ação (Verificação de Assinatura):** No seu terminal local, use o segredo copiado no Passo 2 para validar a integridade:
  ```bash
  echo -n '<PAYLOAD_RECEBIDO>' | openssl dgst -sha256 -hmac '<SEU_SEGREDO_HEX>'
  ```
  *O hash gerado deve bater exatamente com a assinatura recebida no header.*

### Passo 5: Logs de Entrega e Replay Manual (UI)
* **Ação:** No painel de Webhooks da aplicação, selecione o endpoint criado.
* **Resultado Esperado:** A lista de logs de entrega (Detail) deve apresentar o registro enviado com status `SUCCESS` (ou `FAILED` caso o receptor tenha retornado erro).
* **Ação (Simular Falha e Replay):**
  - Altere a URL do endpoint para um IP inválido ou porta fechada na UI.
  - Provoque um novo evento de sanção para gerar um log com status `FAILED` ou `DEAD`.
  - Expanda o log com falha na UI, verifique o log de erro exibido de forma segura (sem vazamentos/XSS).
  - Clique no botão **"Replay"**.
* **Resultado Esperado:** O botão fica desabilitado por no mínimo 3 segundos (debounce anti-DDoS). O status no backend é resetado para `PENDING` e a fila processa a tentativa de entrega novamente.

### Passo 6: Notificação por E-mail do Carrier (Resend)
* **Ação:** Acesse o e-mail cadastrado para a transportadora ou inspecione a tabela `carrier_notification_outbox`.
* **Resultado Esperado:**
  - E-mail formatado de forma jurídica entregue com sucesso contendo o link tokenizado do Portal de Disputa.
  - O campo `resend_message_id` deve estar preenchido na outbox e o status marcado como `SENT`.

---

## 3. Critérios de Aceitação (UAT Sign-off)

- [ ] **Provisionamento Seguro:** O segredo de assinatura só pôde ser visto uma única vez.
- [ ] **Garantia Transacional:** A inserção do veredito gerou simultaneamente os registros de webhook e e-mail na mesma transação.
- [ ] **Assinatura HMAC Válida:** O ERP do receptor consegue decodificar e validar a assinatura da mensagem recebida.
- [ ] **Logs em Tempo Real:** A listagem de logs reflete imediatamente o status das tentativas de envio.
- [ ] **Resiliência a Falhas:** Replay manual restaura logs mortos e os processa com backoff.
- [ ] **Mitigação de Abusos:** UI impede múltiplos cliques consecutivos no botão de replay e fecha o modal de segredo imediatamente se o aplicativo perder o foco do sistema operacional.
