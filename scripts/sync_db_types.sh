#!/usr/bin/env bash
# =============================================================================
# VeraProb Type-Safe Database Sync (INV-7)
# =============================================================================
# Detects staged migrations, resets local DB (Main/PR), generates Dart types, 
# formats and validates code.
# =============================================================================

set -uo pipefail

# -- Detect Supabase Command --
SUPABASE_CMD="supabase"
if ! command -v "$SUPABASE_CMD" > /dev/null 2>&1; then
    if command -v "supabase.exe" > /dev/null 2>&1; then
        SUPABASE_CMD="supabase.exe"
    fi
fi

# -- Step 1: Fast-Exit A (SQL staged?) --
STAGED_MIGRATIONS=$(git diff --cached --name-only | grep "supabase/migrations/.*\.sql" || true)

if [[ -z "$STAGED_MIGRATIONS" ]]; then
    exit 0
fi

# -- Color codes (TTY-gated) --
if [[ -t 1 ]]; then
  C_BLUE='\033[1;34m'; C_WARN='\033[1;33m'; C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_NC='\033[0m'
else
  C_BLUE=''; C_WARN=''; C_RED=''; C_GREEN=''; C_NC=''
fi

echo -e "${C_BLUE}[Type-Sync]${C_NC} Staged migrations detected. Starting parity sync..."

# -- Constants --
OUTPUT_FILE="supabase/types.database.ts"
TEMP_ERR="scripts/supabase_gen_err.tmp"
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# Detect if protected branch (Main or PR environment)
IS_PROTECTED=false
if [[ "$CURRENT_BRANCH" == "main" || "${GITHUB_EVENT_NAME:-}" == "pull_request" ]]; then
    IS_PROTECTED=true
fi

# -- Step 2: Branch Analysis & Fast-Exit B --
if [[ "$IS_PROTECTED" == "false" ]]; then
    echo -e "${C_WARN}[WARN]${C_NC} Dev branch detected. Skipping full reset for speed."
    # In Dev, we just try to generate types without resetting the DB
else
    # Main/PR: Mandatory Database Reset (Fidelity Guard)
    echo -e "${C_BLUE}[Type-Sync]${C_NC} Protected branch: Resetting local database..."
    if ! "$SUPABASE_CMD" db reset --local > /dev/null 2>&1; then
        echo -e "${C_RED}[ERROR]${C_NC} Failed to reset local database. Parity sync failed."
        exit 1
    fi
fi

# -- Step 3: Type Generation (Infrastructure Contract) --
echo -e "${C_BLUE}[Type-Sync]${C_NC} Generating infrastructure contract (TypeScript)..."
if ! "$SUPABASE_CMD" gen types typescript --local > "$OUTPUT_FILE" 2>"$TEMP_ERR"; then
    ERR_MSG=$(cat "$TEMP_ERR" 2>/dev/null || echo "Unknown error")
    rm -f "$TEMP_ERR"
    echo -e "${C_RED}[ERROR]${C_NC} Failed to generate types: $ERR_MSG"

    if [[ "$IS_PROTECTED" == "true" ]]; then
        exit 1
    else
        echo -e "${C_WARN}[WARN]${C_NC} Proceeding in dev branch with stale types."
        exit 0
    fi
fi
rm -f "$TEMP_ERR"

# -- Step 4: Linting (Aesthetic Guard) --
if command -v npx > /dev/null 2>&1; then
    echo -e "${C_BLUE}[Type-Sync]${C_NC} Formatting contract with Prettier..."
    npx prettier --write "$OUTPUT_FILE" > /dev/null 2>&1 || true
fi

# -- Step 5: Self-Healing (Git Re-staging) --
# Stage the generated file automatically to ensure atomic commit
git add "$OUTPUT_FILE"

echo -e "${C_GREEN}[SUCCESS]${C_NC} Infrastructure contract (INV-7) synchronized."
exit 0