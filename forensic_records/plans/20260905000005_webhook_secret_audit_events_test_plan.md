# Test Plan — 20260905000005_webhook_secret_audit_events.sql

**Fase:** 10.7 — P1 Zero-Trust Provisioning (Reveal-Once)
**Migração:** `supabase/migrations/20260905000005_webhook_secret_audit_events.sql`
**pgTAP:** `supabase/tests/20260905000005_reveal_webhook_signing_secret_test.sql`

---

## Objetivo

Validar que a infra de auditoria para operações de segredo de webhook está correta:
índice forense no `system_audit_log`, isolamento RLS de `webhook_signing_keys`,
e que event_types `WEBHOOK_SECRET_REVEALED`/`WEBHOOK_SECRET_ROTATED` são inseríveis.

---

## Testes Cobertos (10 assertions)

| ID | Descrição | Invariante |
|---|---|---|
| CT01 | TENANT_ADMIN da org correta lê sua chave (RLS pass) | INV-1, INV-22 |
| CT02 | OPERATOR bloqueado por RLS (0 rows) | INV-22 |
| CT03 | TENANT_ADMIN de outra org → 0 rows (cross-org isolation) | INV-22 |
| CT04 | `WEBHOOK_SECRET_REVEALED` inserível via service_role | INV-28 |
| CT04b | Audit row presente após insert | INV-1 (append-only) |
| CT05 | `WEBHOOK_SECRET_ROTATED` inserível via service_role | INV-28 |
| CT05b | Audit row presente após insert | INV-1 (append-only) |
| CT06 | UNIQUE partial index bloqueia 2ª chave `active` na mesma org | INV-28 |
| CT06b | Chave `retiring` pode coexistir com `active` | Semântica de rotação |
| CT07 | Índice `idx_system_audit_log_webhook_secret` existe | Performance forense |

---

## Verificação Manual (complementar ao pgTAP)

1. `make test-db` — todos os 10 assertions devem passar com `ok`.
2. Edge fn: `POST /reveal-webhook-signing-secret` com JWT de role `OPERATOR` → HTTP 404.
3. Edge fn: action `"reveal"` → HTTP 404 (reveal direto negado).
4. Edge fn: action `"provision"` com TENANT_ADMIN → `{ secret_hex, version }` retornado.
5. Verificar assinatura com openssl: `openssl dgst -sha256 -hmac <secret_hex_decoded> <payload>`.
6. `system_audit_log` deve ter 1 row `WEBHOOK_SECRET_REVEALED` após provision.

---

## Rollback

Migração usa somente `CREATE INDEX IF NOT EXISTS` e `COMMENT ON INDEX` — ambos
safe para rollback manual (`DROP INDEX IF EXISTS idx_system_audit_log_webhook_secret`).
Nenhum `ALTER TABLE` ou mudança de schema destrutiva.
