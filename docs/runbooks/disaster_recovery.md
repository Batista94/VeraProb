# Runbook: Disaster Recovery & PITR (Phase 8.7)

This document defines the strategies, tools, and procedures to recover the PactaFlow platform in case of critical failures (data loss, regional outage, human error).

## 1. Objectives (RTO & RPO)
- **Recovery Time Objective (RTO):** < 4 hours (Restore core ledger and OCC accessibility).
- **Recovery Point Objective (RPO):** < 5 minutes (Maximum acceptable data loss window).

## 2. Infrastructure Backup Model
As a Supabase-backed platform, we leverage native cloud backup mechanisms:

- **Daily Backups:** Automatic full database dumps (standard for all tiers).
- **Point-in-Time Recovery (PITR):** Transaction-level logging that allows restoring to any specific millisecond (Enabled on Pro/Enterprise tiers).

## 3. Disaster Scenarios & Response Procedures

### Scenario A: Corruption of Domain Logic (Human Error)
*A bug in the EvaluationEngine causes incorrect financial verdicts to be written to the ledger.*

1. **Isolation:** Immediately trigger the "Maintenance Mode" toggle in the DB (Supabase Dashboard -> Database -> Settings).
2. **Identification:** Locate the exact UTC timestamp before the first corrupted entry.
3. **PITR Restore:** 
   - Dashboard -> Infrastructure -> Backups.
   - Select **Point-in-Time Recovery**.
   - Select timestamp and initialize a **Restore to a New Project**.
4. **Verification:**
   - Run the invariant checksum script on the restored project.
   - Verify that the ledger hash matches the known good state (INV-16).
5. **Cutover:** Update the production DNS/API URL to point to the restored project and retire the corrupted instance.

### Scenario B: Accidental Data Deletion (Bypass of RLS)
*A manual script or unauthorized access deletes records from non-ledger tables.*

1. **PITR Restore:** Restore the database to a new instance as described above.
2. **Selective Export:** Export missing data from the restored instance (using `pg_dump` with table filters).
3. **Data Re-injection:** Import missing data back into the production instance after fixing the security breach.

### Scenario C: Regional Supabase Outage
*The entire AWS/GCP region hosting the project goes offline.*

1. **Off-site Backups:** (Requirement for Phase 8.7.2) Weekly snapshots are exported to an external S3 bucket (AWS North America).
2. **Emergency Deployment:** Initialize a new Supabase project in an unaffected region.
3. **Schema Re-hydration:** Apply all migrations sequentially: `supabase db push`.
4. **Data Load:** Restore the last available off-site snapshot.

## 4. Verification Checklist (Post-Restore)
- [ ] **Ledger Integrity:** Run `SELECT verify_immutable_ledger()` (INV-1).
- [ ] **RLS Enforcement:** Verify `pg_policies` shows everything enabled (INV-6/10).
- [ ] **API Security:** Re-link the `custom_access_token_hook` and verify Org Isolation.
- [ ] **Liveness Check:** Confirm that telemetry ingestion edge functions are operational.

## 5. Maintenance & Testing (Quarterly)
- [ ] Run a simulated restore to a new project every quarter.
- [ ] Verify that the restore time aligns with the RTO (< 4h).
- [ ] Document the test results in `docs/governance/compliance/disaster_recovery_test_logs.md`.
