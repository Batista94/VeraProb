# VeraProb - Forensic Contract Governance

VeraProb is a high-performance platform designed to eliminate friction between B2B contracts and operational execution. It acts as an automated "Digital Judge" that transforms raw telemetry into Verifiable Contractual Truth, ensuring financial protection and forensic auditability.

---

## The Problem We Solve
1. **Revenue Leakage:** Capture of unplanned trips via **Shadow Executions**.
2. **Legal Fragility:** Replacing driver-vs-client disputes with a **Forensic PDF with Chain of Custody**.
3. **SLA Fraud:** Detection of **Clock Drift** and GPS spoofing.
4. **Penny Precision Gap:** Eliminating rounding errors using **INV-4/5 (Fixed-Point Math)** with BigInt.
5. **Evidence Poisoning:** Entropy scanning to detect malicious script injection in photos (Ratio > 0.60).
6. **Low Adoption:** Invisible, friction-free interface designed for field operators and drivers.

## Business Vision & ROI
- **Zero-Glosa objective:** Automated Proof of Delivery (POD) with forensic sealing accelerates cash flow.
- **90% Backoffice Reduction:** Automated reconciliation by exception eliminates manual photo checking.
- **Claims Shielding:** Irrefutable dossier forcing insurance payouts without contestation.
- **Civil Liability:** Systematic transfer of custody materialized at the moment of cryptographic sealing.

---

## Architecture & Data Pipeline
The platform follows a strict Event-Sourced logic:
1. **Ingestion:** Raw telemetry and Evidence (Telegram Bot) received via secure Edge Functions.
2. **Normalization:** Unification into Canonical Facts (Deterministic Snapshots).
3. **Evaluation:** Facts replayed against SLA Rules by the Forensic Evaluation Engine.
4. **Verdict:** Impacts sealed into an Immutable Ledger (INV-3).

## Tech Stack
- **Frontend:** Flutter (WASM), Riverpod, Industrial Deep Design.
- **Backend:** Supabase, PostgreSQL (PostGIS), Edge Functions.
- **Security:** SHA-256, HMAC per-org (INV-28), Magic Bytes Entropy.
- **Governance:** Sequential Thinking (MCP), Lead Reviewer AI, Forensic Scanner.

---

## Getting Started (Local Development)

### 1. Prerequisites
- **Flutter SDK** (>= 3.41.5)
- **Docker Desktop**
- **Supabase CLI**
- **Node.js** (>= 18)

### 2. Setup & Run
```bash
# Start infrastructure
supabase start
supabase db reset

# Provision test data
node scripts/dev/bootstrap_dev.mjs

# Setup environment
cp .env.example .env

# Run app
flutter run -d web-server --web-port=8080 --dart-define=SKIP_MFA_DEV=true --web-renderer wasm
```

### 3. Testing & Quality
- **Unit/Integration:** `flutter test`
- **Forensic Scanning:** `bash scripts/security/pr_full_scanner.sh` (Mandatory before PR).

For the complete list of **28 Forensic Invariants**, refer to [CLAUDE.md](CLAUDE.md).
