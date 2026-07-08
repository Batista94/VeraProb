# Test Plan: 20260914000002_update_permission_descriptions

## Objective
Verify that the `tenant_permissions` table descriptions are updated to use "organização" instead of "tenant" for the `financial:read` and `contracts:read` keys.

## Pre-conditions
- The `tenant_permissions` table exists.
- The default seed is loaded.

## Test Cases

### 1. Financial Read Description
- **Action:** Query the description of the `financial:read` permission.
- **Assertion:** Description is exactly `Visualizar dados financeiros da organização`.

### 2. Contracts Read Description
- **Action:** Query the description of the `contracts:read` permission.
- **Assertion:** Description is exactly `Visualizar contratos da organização`.

## Environment
- **DB:** pgTAP via `make test-db`
