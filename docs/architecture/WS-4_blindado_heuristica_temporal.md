# Implementation Plan — WS-4 Blindado: Heurística Temporal

## Problem Statement
A lógica de vínculo atual usa `Date.now()` (tempo de ingestão) para buscar execuções, ignora overlaps, não distingue evidências órfãs de vinculadas no feedback ao motorista, e não possui trilha de auditoria de discrepância de sinal. Isso causa falsos negativos em Zonas de Sombra (atraso de rede/GPS).

---

## Requirements
- **INV-6 / Dead Zone:** `message.date` (Unix timestamp do dispositivo) substitui `Date.now()` como âncora temporal.
- **Latest-Wins:** overlap de execuções → selecionar `window_start_utc` mais recente dentro da janela de 4h.
- **Retroactive Window:** janela de -10min antes do `window_start_utc` (foto tirada antes do Start oficial).
- **Feedback Diferencial:** vinculada → recibo + `execution_id`; órfã → apenas hash forense (sem ansiedade).
- **Proactive Orphan Flag:** `requires_manual_link = true` + alerta em `operational_alerts` (tipo `TELEGRAM_ORPHAN`).
- **Audit Trail:** coluna `telegram_message_date` gravada no `INSERT` para auditoria de discrepância vs `uploaded_at_utc`.
- **QA-Security:** rejeitar `message.date` futuro ou com atraso > 24h.
- **RPC dedicada:** `find_execution_for_telegram(p_org_id, p_driver_id, p_message_ts)` encapsula join + Latest-Wins.
- **Reconciliação:** tabela `telegram_evidence_links` separada para vínculos manuais posteriores (preserva imutabilidade de `telegram_evidence_uploads`).
- **operational_alerts:** estender `valid_alert_type` CHECK para incluir `'TELEGRAM_ORPHAN'`.

---

## Background & Schema
- **execution_states:** tem `organization_id`, `window_start_utc`, `window_end_utc`, `status`, `set_id` — sem `driver_id`.
- **contractual_service_executions:** tem `set_id`, `plan_declaration_id` — sem `driver_id`.
- **plan_declarations:** tem `id`, `organization_id` — sem `driver_id`.
- **telegram_evidence_uploads:** imutável por trigger; novas colunas (`telegram_message_date`, `requires_manual_link`) inseridas no `INSERT`.
- **operational_alerts:** CHECK constraint `valid_alert_type` precisa ser alterado para incluir `'TELEGRAM_ORPHAN'`.

---

## Proposed Solution Flow
1. **QA-Security Gate:** Validação de `message.date` (rejeita futuro ou > 24h de drift).
2. **RPC Call:** `find_execution_for_telegram` com janela `[msg_ts - 10min, msg_ts + 4h]`.
3. **Latest-Wins:** `ORDER BY window_start_utc DESC LIMIT 1`.
4. **Ingestion:** `INSERT` com as novas colunas forenses.
5. **Alerting:** Disparo de `TELEGRAM_ORPHAN` se o vínculo falhar.
6. **Feedback:** Resposta visual distinta no Telegram.

---

## Task Breakdown

### Task 1: Migration SQL — Estender schema para WS-4
- `ALTER TABLE telegram_evidence_uploads ADD COLUMN telegram_message_date TIMESTAMPTZ`.
- `ALTER TABLE telegram_evidence_uploads ADD COLUMN requires_manual_link BOOLEAN NOT NULL DEFAULT false`.
- Criar tabela `telegram_evidence_links` (append-only, imutável).
- Estender `CHECK valid_alert_type` em `operational_alerts`.
- Índices de performance para as novas flags.

### Task 2: RPC `find_execution_for_telegram`
- Encapsular busca temporal em função Postgres `SECURITY DEFINER`.
- Implementar a lógica de janela retroativa de 10min.

### Task 3: Refatorar Edge Function
- Implementar `validateMessageDate` com tolerância de 60s para futuro.
- Substituir busca inline pela chamada da nova RPC.
- Implementar o feedback diferencial (Inline Keyboard para `/help`).

### Task 4: Alertas e Auditoria
- Registro de `TELEGRAM_ORPHAN` em `operational_alerts`.
- Log estruturado com `correlationId` para auditoria INV-7.
