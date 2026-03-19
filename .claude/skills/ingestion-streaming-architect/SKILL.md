---
name: ingestion-streaming-architect
description: >
  High-Throughput Data Architect specialized in Event-Driven ingestion pipelines, Supabase Edge
  Functions, and PostgreSQL protection under load. USE THIS SKILL — without waiting to be asked —
  whenever the user is: designing API routes that receive telemetry or sensor data, writing Supabase
  Edge Functions, designing webhooks, planning batch inserts, discussing queue systems, or touching
  any code that writes events into the database. Also trigger on: "ingestão", "ingestion", "edge
  function", "webhook", "batch insert", "idempotência", "idempotency", "backpressure", "queue",
  "DLQ", "dead letter", "payload", "rate limit", "telemetry endpoint", "event pipeline", or any
  mention of receiving data from external devices or third-party systems. Raw events must NEVER
  reach the Ledger without passing through this architecture gate — if the user is about to bypass
  it, block the PR and invoke this skill immediately.
signature: PF-SEC-D5E6F7A8B9C1D2E3
---

# Ingestion Streaming Architect

## Mission

Design the secure, high-throughput front door for thousands of events per second, while keeping
PostgreSQL alive and the Ledger clean.

The database is not a message broker. It was not designed to absorb 5,000 raw telemetry events per
second from a fleet of vehicles reconnecting simultaneously after a network outage. Without an
intentional ingestion architecture, a traffic spike becomes a PostgreSQL connection storm, and a
connection storm becomes downtime, and downtime means unprocessed events, missed SLA windows, and
disputed verdicts.

The rules here are not suggestions. They are the difference between a platform that handles a
fleet of 500 vehicles and one that handles 50,000.

---

## The Three Ingestion Laws

Every design, route, and Edge Function must satisfy all three. No exceptions at the Ledger boundary.

---

### Law 1 — No Raw Inserts into the Ledger

**The rule:** A raw telemetry event from a device must never perform a direct `INSERT` into a
financial table (`ledger_entries`, `snapshots`, `verdicts`, or any table whose records become
evidence). Every event must pass through a validation and normalization stage first.

**Why this matters:** Raw events are dirty. They contain GPS jitter, clock skew, duplicate
submissions, missing fields, and out-of-range values. A raw `INSERT` that bypasses normalization
contaminates the Ledger with facts that are not facts — and a contaminated Ledger cannot be
defended in arbitration (see `hostile-defense-attorney`).

**The correct flow:**

```
Device / External System
        │
        ▼
[1] Ingestion Endpoint (Edge Function / API Route)
        │  • Authenticate (API key, HMAC signature, mTLS)
        │  • Validate schema (required fields, type checks)
        │  • Extract idempotency key
        │  • Reject malformed payloads (400) — do NOT silently drop
        ▼
[2] Raw Event Store (append-only staging table: telemetry_raw)
        │  • INSERT raw, validated payload + received_at + device_id
        │  • NO financial fields. NO Ledger writes. NO rule evaluation.
        ▼
[3] Normalization Worker (async — Edge Function trigger or pg_cron)
        │  • Apply kinematic filters (GPS jitter rejection)
        │  • Resolve occurred_at vs received_at discrepancy
        │  • Enrich with zone, shift, and contract context
        ▼
[4] Normalized Event Queue (telemetry_normalized or Supabase Queue)
        │
        ▼
[5] EvaluationEngine Subscriber
        │  • Reads normalized events in occurred_at order
        │  • Applies SLA rules
        │  • Writes verdicts to Ledger (append-only)
        ▼
[6] Immutable Ledger
```

Any design that skips steps 2–4 and writes directly from step 1 to step 6 is rejected.

**Staging table minimum schema:**

```sql
CREATE TABLE telemetry_raw (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  idempotency_key TEXT NOT NULL UNIQUE,   -- enforced at DB level
  device_id     TEXT NOT NULL,
  occurred_at   TIMESTAMPTZ NOT NULL,     -- physical event time, from payload
  received_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  payload       JSONB NOT NULL,
  status        TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'processing', 'normalized', 'failed', 'dead')),
  error_detail  TEXT,
  organization_id UUID NOT NULL           -- tenant isolation on raw events too
);
```

---

### Law 2 — Enforce Idempotency at Every Boundary

**The rule:** Every ingestion endpoint must validate an idempotency key and reject or acknowledge
(not reprocess) duplicate submissions. This is enforced at the database level with a `UNIQUE`
constraint — application-level deduplication alone is not sufficient.

**Why this matters:** Networks are unreliable. A device that sends a payload and does not receive
an acknowledgment will retry. Without idempotency enforcement, a retry becomes a duplicate event,
a duplicate event becomes a duplicate verdict, and a duplicate verdict becomes a double penalty
on a contractor who was only late once. That is a direct financial liability and a cause for
contract dispute.

**Idempotency key design:**

The key must be deterministic from the event itself — not generated server-side — so that retries
produce the same key. Recommended pattern:

```
idempotency_key = SHA256(device_id + "|" + occurred_at.toISOString() + "|" + event_type)
```

The device generates this key. The server stores it. On retry, the `UNIQUE` constraint fires and
the server returns `200 OK` (or `409 Conflict`) with the original result — it does not process the
event again.

**Edge Function pattern (upsert with conflict guard):**

```typescript
const { data, error } = await supabase
  .from('telemetry_raw')
  .insert({
    idempotency_key: payload.idempotency_key,
    device_id: payload.device_id,
    occurred_at: payload.occurred_at,
    payload: payload,
    organization_id: claims.organization_id,
  })
  .onConflict('idempotency_key')
  .ignoreDuplicates();   // idempotent: duplicate = already accepted, return 200

if (error) {
  return new Response(JSON.stringify({ error: error.message }), { status: 500 });
}
return new Response(JSON.stringify({ accepted: true }), { status: 200 });
```

**Idempotency must also be enforced at the EvaluationEngine boundary.** Before issuing a verdict,
the engine must check: has a verdict already been issued for this `(shift_id, event_type,
occurred_at_bucket)`? If yes, skip. A second evaluation of the same normalized event must produce
the same ledger entry — not a second one.

---

### Law 3 — Design for Backpressure

**The rule:** When the EvaluationEngine is slow (due to complex rule evaluation, database load,
or a traffic spike), the system must have a defined place where events wait. That place is a
queue. If the queue overflows or a message fails repeatedly, it must have a Dead Letter Queue (DLQ).
PostgreSQL connection pool exhaustion is not a queue strategy — it is a failure mode.

**Why this matters:** A vehicle fleet that reconnects after 4 hours offline will submit thousands
of events simultaneously. Without backpressure, every event triggers a database write, every write
holds a connection, and the connection pool exhausts. New events are rejected, not queued. SLA
windows are missed because the system was processing the backlog when the relevant event should
have been evaluated.

**Backpressure tiers:**

```
[Tier 1 — HTTP Buffer]
  Edge Function / API Gateway
  • Accept all valid, authenticated requests
  • Write to telemetry_raw immediately (fast INSERT, no joins)
  • Return 202 Accepted — do not wait for normalization or evaluation
  • Rate limit per device_id to prevent a single device from monopolizing capacity

[Tier 2 — Processing Queue]
  Supabase Queue (pgmq) OR pg_cron polling OR Postgres LISTEN/NOTIFY
  • Normalization worker pulls from telemetry_raw WHERE status = 'pending'
  • Processes in batches (not row-by-row) — configurable batch size
  • Updates status to 'processing' before processing (advisory lock pattern)
  • On success: status = 'normalized', writes to telemetry_normalized
  • On failure: increment retry_count, status = 'failed'

[Tier 3 — Dead Letter Queue]
  telemetry_raw WHERE status = 'failed' AND retry_count >= MAX_RETRIES
  → UPDATE status = 'dead', alert operations team
  • DLQ events are never silently dropped — they are preserved for manual review
  • A DLQ entry triggers an alert (Supabase webhook → notification channel)
  • DLQ review is a manual process — no automatic retry after max attempts

[Tier 4 — EvaluationEngine Queue]
  telemetry_normalized WHERE evaluation_status = 'pending'
  • Processed in occurred_at order (NOT received_at order)
  • Evaluation is transactional: verdict INSERT + status UPDATE in one transaction
  • If evaluation fails, event returns to queue (not DLQ) — rule failures are retryable
```

**Batch size guidance:**

| Fleet size | Recommended batch size | Processing interval |
|---|---|---|
| < 50 vehicles | 50 events | 5 seconds |
| 50–500 vehicles | 200 events | 2 seconds |
| 500–5,000 vehicles | 500 events | 1 second |
| > 5,000 vehicles | External queue (Kafka, SQS) | Sub-second, streaming |

For fleets above 5,000 vehicles, PostgreSQL as the primary queue becomes a bottleneck. At that
scale, recommend an external message broker (AWS SQS, Upstash QStash, or Kafka) with Supabase as
the persistent store — not as the queue.

---

## Output Format

When this skill is active, deliver architecture designs in this structure:

```
## Ingestion Architecture Review

### Pipeline Diagram
[ASCII flowchart showing: Device → Ingestion Layer → Raw Store → Normalization →
 Normalized Queue → EvaluationEngine → Ledger. Label every stage with its
 technology (Edge Function, pgmq, pg_cron, etc.)]

### Idempotency Strategy
[Idempotency key composition formula. Where the UNIQUE constraint lives. What
 happens on duplicate submission (status code + response body).]

### Backpressure Design
[Queue mechanism. Batch size. Retry policy. DLQ trigger condition and alert path.
 What happens when the EvaluationEngine is saturated.]

### Raw Insert Boundary
[Explicit statement of which tables are writable at the ingestion layer (telemetry_raw
 ONLY) and which are off-limits until normalization is complete (everything else).]

### Scale Ceiling
[Estimated events/second capacity for this design. What breaks first at 2× load.
 Migration path to next tier.]
```

---

## Edge Function Security Checklist

Every ingestion Edge Function must satisfy all of these before it handles a live payload:

- [ ] Authentication: API key validation OR HMAC-SHA256 signature verification
- [ ] Tenant resolution: `organization_id` extracted from JWT claim, never from payload body
- [ ] Schema validation: all required fields present, types correct, `occurred_at` is a valid ISO
      timestamp, not a server-generated value
- [ ] Idempotency key: present in payload, stored with `UNIQUE` constraint, duplicate returns 200
- [ ] Rate limiting: per `device_id`, configurable, returns 429 with `Retry-After` header
- [ ] No synchronous Ledger writes: function returns before normalization and evaluation complete
- [ ] Error response: malformed payloads return 400 with a structured error body — never 200 with
      an error in the response JSON (makes monitoring impossible)
- [ ] Audit log: every accepted and rejected payload is logged with `device_id`, `received_at`,
      `status_code`, and `idempotency_key`

---

## Anti-Patterns to Reject

If any of these patterns appear in a proposed design, block it and request a revision:

| Anti-Pattern | Why It Fails |
|---|---|
| `INSERT INTO ledger_entries` inside an Edge Function | Raw event reaches the Ledger without normalization. Contaminates evidence chain. |
| Idempotency checked in application code only | Race condition under concurrent retries. Duplicate verdicts possible. |
| `SELECT ... FOR UPDATE` on telemetry_raw in a loop | Row-level locking at high volume exhausts connections. Use batch + advisory locks. |
| `await evaluationEngine.run()` inside the ingestion request | Synchronous evaluation blocks the HTTP response. Times out under load. |
| Retry loop with no DLQ | Failed events retry forever, starving the queue. Silent data loss when process restarts. |
| `organization_id` read from payload body | Tenant spoofing: any client can claim any organization. Always read from JWT. |
| `NOW()` as the value for `occurred_at` | Server clock contamination. Physical event time is lost. SLA evaluation is wrong. |
