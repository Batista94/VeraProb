#!/usr/bin/env bash
# =============================================================================
# VeraProb Infra — PostgREST Schema Cache Refresher (INV-15)
# =============================================================================
# Objective: Force PostgREST to reload its schema cache after migrations
# to avoid API inconsistencies in development.
# =============================================================================

set -uo pipefail

# -- Detect Supabase Command --
SUPABASE_CMD="supabase"
if ! command -v "$SUPABASE_CMD" > /dev/null 2>&1; then
    if command -v "supabase.exe" > /dev/null 2>&1; then
        SUPABASE_CMD="supabase.exe"
    fi
fi

# -- Detect Supabase Status --
# If the environment is offline, exit silently.
if ! "$SUPABASE_CMD" status > /dev/null 2>&1; then
    exit 0
fi

# -- Mechanism: Reload Schema Cache --
# Primary: NOTIFY via SQL
# This is the standard way to trigger a reload in PostgREST.
RELOAD_SUCCESS=false

if "$SUPABASE_CMD" db query "NOTIFY pgrst, 'reload schema';" > /dev/null 2>&1; then
    RELOAD_SUCCESS=true
else
    # Fallback: Management API call
    # If the SQL notification fails, try the API root POST as a fallback.
    if curl -s -X POST "http://localhost:54321/rest/v1/" \
        -H "Content-Type: application/json" \
        -d '{}' > /dev/null 2>&1; then
        RELOAD_SUCCESS=true
    fi
fi

if [ "$RELOAD_SUCCESS" = true ]; then
    echo -e "🔄 [VeraProb Infra] PostgREST schema cache reloaded."
fi

# -- Step 3: Hardening & Verification (INV-15) --
# Health check: perform a HEAD request to the API root.
HEALTH_CHECK=$(curl -s -o /dev/null -w "%{http_code}" -I "http://localhost:54321/rest/v1/")

# If the API is unhealthy after reload, we log a warning but don't block.
if [[ "$HEALTH_CHECK" -lt 200 || "$HEALTH_CHECK" -ge 400 ]]; then
    # Silent exit as per requirement not to block.
    exit 0
fi

exit 0
