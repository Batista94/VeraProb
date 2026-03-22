# Security Rules

## Mandatory Checks Before Any Commit

- [ ] No hardcoded secrets, API keys, or connection strings
- [ ] `SUPABASE_SERVICE_ROLE_KEY` not exposed in client-side code or Flutter Web bundle
- [ ] Every new table has RLS enabled with `organization_id` filter
- [ ] All RLS policies use `auth.jwt() ->> 'organization_id'` — never `auth.uid()` alone
- [ ] No `select('*')` — explicit column lists only
- [ ] All queries include `.limit()` to prevent unbounded result sets
- [ ] Secrets absent from logs, error messages, and audit exports

## RLS Standard

```sql
USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid)
```

- Never bypass RLS via service role client in application code
- Service role restricted to migrations and Edge Functions with explicit justification
- Cross-tenant queries are forbidden at the application layer — RLS is the enforcement mechanism

## Multi-Tenancy (INV-6 + INV-20)

- Every record in every table MUST carry an `organization_id` column
- `CONTRACTOR_VIEWER` roles require BOTH `org_id` AND `contractor_id` in JWT (Dual-Key Isolation)
- Never trust client-supplied tenant context — always derive from verified JWT
- Tenant isolation MUST be validated in tests using separate org credentials, not just positive-path tests

## JWT Claims

- JWT must contain `organization_id` claim for RLS to function (INV-10)
- `CONTRACTOR_VIEWER` JWT must additionally contain `contractor_id` (INV-20)
- JWT claim structure changes require a [GO] Verdict from the Lead Reviewer (INV-22)

## Ingestion Security

- Zero-trust ingestion: all telemetry is untrusted until normalized (INV-9)
- Facts with `suspectedSpoofing = true` are quarantined — excluded from EvaluationEngine until manual Auditor approval (INV-21)
- Raw 3rd-party payloads (Sascar, Omnitracs) MUST pass through Adapter Isolation before reaching Core (INV-14)
- Every evidence file MUST receive a server-side SHA-256 hash at point of ingestion (INV-16)

## Third-Party Services (INV-25)

- Every new integration MUST have a free/freemium tier covering pre-revenue stage
- MUST enforce SOC 2 / GDPR-equivalent security
- Paid-only services require explicit PO sign-off
- Prefer existing stack: Supabase · MapTiler · Sentry · PostHog · Resend

## Security Incident Protocol

If a security issue is found:
1. STOP immediately
2. Invoke `hostile-defense-attorney` skill
3. Fix CRITICAL issues before continuing
4. Rotate any exposed secrets
5. Check entire codebase for similar patterns
