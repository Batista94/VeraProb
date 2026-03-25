# 🌊 VeraProb
### The Immutable Verifier for B2B Compliance & Financial Protection

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Stack: Flutter](https://img.shields.io/badge/Stack-Flutter%20|%20Supabase%20|%20PostgreSQL-02569B?logo=flutter)](https://flutter.dev)
[![Architecture: Clean Architecture](https://img.shields.io/badge/Architecture-Clean%20|%20Event--Driven-green)](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html)

**VeraProb** is a high-performance, event-driven platform designed to eliminate the friction between signed B2B contracts and real-world operational execution. It acts as an automated, impartial **"Digital Judge"** that:

1. **Ingests** real-world telemetry (GPS, Check-ins, IoT).
2. **Normalizes** noisy data into deterministic, unified facts.
3. **Evaluates** facts against strict contractual rules in real-time.
4. **Verdicts** financial impacts (penalties/approvals) into an **Immutable Ledger**.


---

VeraProb transforms raw telemetry into **Verifiable Contractual Truth**, protecting participants from administrative fatigue and financial leakage.

- **🛡️ Financial Shield (INV-19):** Real-time monitoring of breaches with automatic penalty calculation and **Financial Ceiling** (Teto Financeiro) to protect operator margins.
- **📜 Burden of Proof:** Generates cryptographic-like evidence of execution. Disputes are resolved by facts, not emails.
- **⚡ Zero-Friction JIT Master Data:** Just-in-Time geofencing and contractor creation inline with operations.
- **🔒 Multi-Tenant Sovereignty:** Complete data isolation powered by Supabase Row-Level Security (RLS).
- **📈 Relative Risk KPIs:** Instant visibility into financial exposure vs. negotiated contract caps.


---

Built for forensics, reliability, and deterministic results:

*   **Logic:** Pure Dart Domain (Sovereign Logic) — zero dependencies on infrastructure.
*   **Engine:** Deterministic Evaluation Engine for contractual rule replay.
*   **Persistence:** PostgreSQL/Supabase with strict RLS enforcement.
*   **Frontend:** Premium Flutter Web interface with reactive state management (Riverpod).
*   **Precision:** All financial operations handled in integer cents via `Money` Value Objects.
*   **Invariants:** Adherence to the [25 Forensic Invariants](.claude/rules/invariants.md).


---

## 🚀 Vertical Applications

While the core engine is industry-agnostic, VeraProb is optimized for B2B Logistics, Industrial Charter (Fretamento), and Facilities Management.


---
© 2026 VeraProb — *Generating Truth from Telemetry.*
