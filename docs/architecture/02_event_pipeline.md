# Event Pipeline Architecture

*(Pending full specification - Placeholder for pipeline documentation)*

This document will outline the journey of data through the platform:
1.  **Ingestion:** Realtime GPS and vehicle state telemetry.
2.  **Normalization:** Smoothing, deduplication, and anomaly detection.
3.  **Command Center Stream:** How sanitized state is efficiently pushed via Supabase Realtime to the OCC map without touching the evaluation disk context.
4.  **SLA Engine Intake:** How normalized events are chunked and fed into the `ContractualEvaluationEngine`.
5.  **Ledger Persistence:** The structure of the `sla_audit_ledger` acting as the ultimate system of record.
