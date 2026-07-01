# 20260905000003_expand_webhook_payload Test Plan

## Objective
Verify that the `enqueue_verdict_webhooks` trigger correctly generates the expanded `v_payload` JSON without leaking PII, and validates reason codes.

## Invariants Covered
- **INV-9 (Evidence Immutability):** Payload includes `case.queue_entry_id` and `evidence.evidence_hash`.
- **PII Minimization:** The payload must not contain `placa`, `motorista`, or `decided_by`.

## Test Cases

1. **Payload Structure Validation**
   - **Setup:** Insert a `VERDICT_SEALED` event into `sla_audit_ledger_v2` with complete financial and verdict data.
   - **Action:** Check the generated `webhook_delivery_logs`.
   - **Assertion:** `payload` contains `case.queue_entry_id`, `evidence.evidence_hash`, `verdict.outcome`, `financial.fine_cents`.

2. **PII Leak Prevention**
   - **Setup:** Insert an event.
   - **Action:** Inspect the `payload` JSONB.
   - **Assertion:** Ensure `payload->'verdict'->>'decided_by'` IS NULL, and no `placa` or `motorista` keys exist anywhere in the payload.

3. **Reason Code Validation**
   - **Setup:** Insert an event with an invalid `reason_code`.
   - **Action:** Check the generated `webhook_delivery_logs`.
   - **Assertion:** `payload->'verdict'->>'reason_code'` IS NULL (or the whole trigger fails depending on implementation, but plan says "mapped to null").
