# VeraProb — Telegram Forensic Bot Testing

This document centralizes the instructions and credentials for testing the **Forensic Evidence Bot (WS-4)** locally.

## 1. Test Credentials

| Detail | Value |
| :--- | :--- |
| **Simulated Chat ID** | `908453789` |
| **Test Driver ID** | `00000000-0000-0000-0000-d00000000001` |
| **Binding Token** | `VERAPR22` |
| **Test Trip (8h)** | `TRIP-8H-TEST` |

## 2. Local Setup

1. **Serve the Edge Function:**

   ```bash
   supabase functions serve telegram-webhook --no-verify-jwt --env-file .env
   ```

2. **Environment Variables:**
   Ensure your `.env` has:
   - `TELEGRAM_BOT_TOKEN`: Your real bot token (or a dummy one for simulation).
   - `SUPABASE_URL`: <http://127.0.0.1:54321>
   - `SUPABASE_SERVICE_ROLE_KEY`: Your local service role key.

3. **Expose Localhost (Optional - for real Telegram Bot):**
   If you need to test with a real Telegram bot instead of simulated `curl` commands, expose your local server:

   ```bash
   npx localtunnel --port 54321
   ```

   *Copy the URL provided (e.g., `https://brave-goats-jump.loca.lt`) and set it as your webhook:*
   `https://api.telegram.org/bot<SEU_TELEGRAM_BOT_TOKEN>/setWebhook?url=<SUA_URL_LOCALTUNNEL>/functions/v1/telegram-webhook&secret_token=<SEU_WEBHOOK_SECRET>`

## 3. Simulation Commands (Webhook)

Use these `curl` commands to simulate Telegram messages being sent to your local function.

### A. Simulate Text Message (Binding Request)

**Bash:**

```bash
curl -X POST http://127.0.0.1:54321/functions/v1/telegram-webhook \
-H "Content-Type: application/json" \
-d '{
  "update_id": 1000,
  "message": {
    "message_id": 1,
    "from": { "id": 908453789, "first_name": "Test", "username": "test_driver" },
    "chat": { "id": 908453789, "type": "private" },
    "text": "/start VERAPR22"
  }
}'
```

**PowerShell:**

```powershell
$unixTime = [int][double]::Parse((Get-Date -UFormat %s))

curl -X POST http://127.0.0.1:54321/functions/v1/telegram-webhook `
-H "Content-Type: application/json" `
-H "X-Telegram-Bot-Api-Secret-Token: <SEU_WEBHOOK_SECRET>" `
-d "{\"update_id\": 1000, \"message\": {\"message_id\": 1, \"date\": $unixTime, \"from\": {\"id\": 908453789, \"first_name\": \"Test\", \"username\": \"test_driver\"}, \"chat\": {\"id\": 908453789, \"type\": \"private\"}, \"text\": \"/start VERAPR22\"}}"
```

### B. Simulate Photo Message (Evidence Ingestion)

**Bash:**

```bash
curl -X POST http://127.0.0.1:54321/functions/v1/telegram-webhook \
-H "Content-Type: application/json" \
-d '{
  "update_id": 1001,
  "message": {
    "message_id": 2,
    "from": { "id": 908453789, "first_name": "Test" },
    "chat": { "id": 908453789, "type": "private" },
    "photo": [
      { "file_id": "AgACAgEAAxkBAAIB", "file_unique_id": "unique1", "width": 800, "height": 600 }
    ],
    "caption": "Foto da blitz policial"
  }
}'
```

**PowerShell:**

```powershell
# Dica: Para gerar um timestamp válido no PowerShell e salvar em uma variável:
$unixTime = [int][double]::Parse((Get-Date -UFormat %s))

curl -X POST http://127.0.0.1:54321/functions/v1/telegram-webhook `
-H "Content-Type: application/json" `
-H "X-Telegram-Bot-Api-Secret-Token: <SEU_WEBHOOK_SECRET>" `
-d "{\"update_id\": 1001, \"message\": {\"message_id\": 2, \"date\": $unixTime, \"from\": {\"id\": 908453789}, \"chat\": {\"id\": 908453789}, \"photo\": [{\"file_id\": \"AgACAgEAAxkBAAIB\", \"file_unique_id\": \"unique1\", \"width\": 800, \"height\": 600}], \"caption\": \"Foto da blitz\"}}"
```

> [!TIP]
> O campo `"date"` é obrigatório para a **Heurística Temporal (WS-4)**. Se o timestamp for superior a 24h ou estiver no futuro, a evidência será rejeitada.

## 4. Automated Chaos & Resilience Suite

Para conformidade com as fases 10.3+ e os invariantes INV-1, INV-11 e INV-15, utilize a suite automatizada de load/chaos.

### A. Cenários Cobertos
1.  **SLA Race (INV-15)**: Chamadas simultâneas ao RPC `complete_execution`.
2.  **Shadow Recovery (INV-11)**: `SIGKILL` no container mid-request + Idempotência via retry do Telegram.
3.  **Multi-Tenant Scale (INV-1)**: 100 pings concorrentes em 10 organizações simultâneas.
4.  **Fluid FSM Auto-Link (Fase 10.3)**: Vinculação retroativa de evidências órfãs.

### B. Como Executar
Certifique-se que o Supabase está rodando (`supabase start`) e o banco está provisionado (`node scripts/dev/bootstrap_dev.mjs`).

```bash
# 1. Aplicar limites de stress (simula pressão de produção)
bash scripts/chaos/apply_stress_limits.sh

# 2. Rodar a suite completa
bash scripts/chaos/run_chaos_suite.sh
```

### C. Circunstâncias de Uso
- **Pre-Merge**: Obrigatório antes de qualquer merge para a `main` que altere o motor de ingestão ou FSM.
- **Mudança de Infra**: Após atualizações de CLI, Docker ou limites de recursos.
- **Auditoria Mensal**: Para garantir que a integridade forense (INV) continua sendo respeitada.

---

## 5. Verification

1. Check the `forensic_evidence` table in Supabase Dashboard.
2. Verify if the `chat_id` was correctly linked to the `driver_id` in the `drivers` table.
3. Check the logs in the terminal where `supabase functions serve` is running.
4. Revise os resultados em `docs/governance/k6_*_results.json`.
