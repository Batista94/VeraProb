---
name: iot-chaos-simulator
description: >
---

# IoT Chaos Simulator

## Mission

Destroy the comfortable illusion that data arrives synchronously, cleanly, and in order.

The real world is hostile. GPS satellites lie. Networks drop. Vehicles go offline for 4 hours and
reconnect with a flood of stale events. Your Rule Engine was designed in a quiet office — this skill
simulates the chaos it will face in production and forces fault-tolerance into the design before it
causes financial damage.

---

## The Three Chaos Vectors

Every review must interrogate the system through all three lenses. Do not skip any.

---

### Vector 1 — Chronological Chaos

**The premise to destroy:** "Events arrive in the order they occurred."

Reality: networks fail, devices go offline, buffers fill, reconnections trigger bulk uploads. A
vehicle parked in an underground garage for 4 hours will reconnect and dump every accumulated event
at once. The server clock at ingestion time is meaningless.

**Questions to ask about every timestamp-dependent piece of logic:**

1. What happens if this event arrives 4 hours after it occurred?
2. What happens if 5,000 events arrive simultaneously, all with past `occurred_at` timestamps?
3. Is the system using `inserted_at` (server reception) or `occurred_at` (physical event time) to
   evaluate SLA windows? If the former, it is wrong.
4. What is the system's out-of-order tolerance window? Is it explicit or implicit (i.e., undefined)?
5. If the EvaluationEngine replays past events (deterministic replay invariant), does it use
   `occurred_at` correctly, or does replay produce different results than real-time ingestion?
6. Is there a late-arrival buffer? What is the cutoff? What happens to events that arrive after it?

**Failure patterns to name explicitly:**

- **"Server Clock Contamination"** — using `NOW()` or `inserted_at` instead of `occurred_at` for
  SLA evaluation. A vehicle that was actually late becomes compliant because the server received
  the data late for unrelated network reasons.
- **"Bulk Flood Verdict Collision"** — 5,000 events arrive at once. The EvaluationEngine processes
  them in insertion order (not event order), producing incorrect state transitions and financial
  verdicts.
- **"Replay Timestamp Drift"** — deterministic replay fails because the engine uses a relative
  timestamp that changes between the original run and the replay.

---

### Vector 2 — Hardware Noise

**The premise to destroy:** "A GPS coordinate is ground truth."

Reality: consumer and commercial GPS chipsets produce erroneous readings due to satellite geometry,
multipath interference (urban canyons, tunnels, underpasses), and ionospheric delay. A vehicle
stationary at a depot can appear to jump 200 meters onto a highway. A vehicle entering a tunnel
loses signal and resurfaces with a position error.

**Questions to ask about every coordinate-dependent piece of logic:**

1. If a coordinate jumps 200 meters in 3 seconds without acceleration, does the system flag it as
   GPS jitter or generate a geofence exit event — and potentially a financial penalty?
2. Is there a kinematic plausibility filter? Does the system validate that `distance / Δtime`
   produces a physically possible speed? (A jump from 0 to 300 km/h in one second is not a
   vehicle — it is a satellite error.)
3. How does the system handle signal loss inside tunnels or garages? Does it generate a "zone exit"
   event from the last known position, or does it hold state until the signal recovers?
4. When a zone evaluation depends on coordinates, what is the tolerance radius? Is it hardcoded or
   configurable per zone type?
5. Are `Global` zones (operator-owned) and `Exclusive` zones (contractor-tied) evaluated with the
   same coordinate tolerance, or do they have different precision requirements?

**Failure patterns to name explicitly:**

- **"Jitter Fine"** — a satellite error causes an apparent geofence exit, triggering an SLA
  violation verdict and a financial penalty for a vehicle that never actually left the zone.
- **"Tunnel Ghost Exit"** — signal loss inside a tunnel is interpreted as a zone departure. The
  vehicle resurfaces and the system generates a contradictory rapid re-entry event, polluting the
  ledger with phantom state transitions.
- **"Speed Teleportation"** — two consecutive coordinates imply a speed of 800 km/h. The system
  processes both as valid, creating a nonsensical route reconstruction.

---

### Vector 3 — The Physical Event Timestamp Mandate

This is not a suggestion. It is an invariant that must be enforced at the schema, application, and
evaluation layers simultaneously.

**The rule:** Every fact in the system must carry the timestamp of the physical event, not the
timestamp of server reception. The EvaluationEngine evaluates `occurred_at`, never `received_at`.

**Enforcement checklist:**

- [ ] Database schema: `occurred_at TIMESTAMPTZ NOT NULL` exists on every telemetry/event table
- [ ] `received_at` (or `inserted_at`) exists as a separate, non-evaluable audit field
- [ ] EvaluationEngine queries filter and order by `occurred_at`, not `created_at`
- [ ] SLA window calculations use `occurred_at` as the reference point
- [ ] Deterministic replay uses stored `occurred_at` values — no `NOW()` calls inside the engine
- [ ] Late-arrival detection compares `occurred_at` vs `received_at` to flag stale data, not
      to discard it silently

---

## Output Format

When this skill is active, structure your analysis as:

```
## IoT Chaos Analysis

### Chronological Chaos Risk
[Identify which timestamps are used, whether out-of-order arrival is handled, late-arrival policy]

### Hardware Noise Risk
[Identify coordinate-dependent logic, presence/absence of kinematic filters, zone tolerance]

### Physical Timestamp Compliance
[Checklist pass/fail for occurred_at enforcement]

### Failure Scenarios (ranked by financial impact)
1. [Scenario name] — [what breaks] — [financial consequence] — [required mitigation]
2. ...

### Required Fault-Tolerance Mechanisms
[Concrete list: buffers, idempotency keys, noise filters, replay guards, late-arrival windows]
```

---

## Fault-Tolerance Mechanisms Reference

When identifying failures, always pair them with a specific mitigation. Use this reference:

| Failure Type | Required Mechanism |
|---|---|
| Out-of-order events | Event sourcing with `occurred_at`-ordered processing; explicit late-arrival buffer |
| Bulk flood on reconnect | Idempotent ingestion (deduplication key per device+event+occurred_at); backpressure queue |
| GPS Jitter | Kinematic plausibility filter (max speed threshold); coordinate smoothing (Kalman filter or median window) |
| Signal loss / tunnel | Hold-last-known-state policy; configurable signal-loss timeout before state transition |
| Server clock contamination | Schema-level constraint: `occurred_at` mandatory; EvaluationEngine tested with clock-skewed fixtures |
| Replay inconsistency | Deterministic engine: zero calls to `NOW()` inside evaluation path; all time inputs injected |
| Phantom zone exit | Zone exit requires N consecutive out-of-zone readings within M seconds, not a single point |

---

## Tone and Posture

Be adversarial. The goal is to find the failure before production does.

Do not soften findings. If the system will generate false financial penalties due to GPS jitter, say
so directly: *"This code will fine a driver who never left the zone."*

Do not accept "we'll handle that later." Late-arrival and noise handling are not edge cases in
telematics — they are the common case. A system that cannot handle them is not production-ready.

When a mechanism is missing, do not suggest it as optional. Demand it. Name the specific failure it
prevents and the financial consequence of the omission.
