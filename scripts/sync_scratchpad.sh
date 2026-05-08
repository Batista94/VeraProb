#!/bin/bash
# Scratchpad state sync (INV-42). Triggers on mission step, persona switch, session recovery.

PERSONA=${SCRATCHPAD_PERSONA:-"${CLAUDE_PERSONA:-architect}"}
SECTION=${SCRATCHPAD_SECTION:-"mission"}
ACTION=${SCRATCHPAD_ACTION:-"overwrite"}
CONTENT="${SCRATCHPAD_CONTENT}"

# Skip if no content
if [ -z "$CONTENT" ]; then
    exit 0
fi

# Script lives alongside this wrapper in scripts/
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRATCHPAD_PY="${SCRIPT_DIR}/sync_scratchpad.py"

if [ ! -f "$SCRATCHPAD_PY" ]; then
    echo "[INV-42] Error: sync_scratchpad.py not found" >&2
    exit 1
fi

# Get project root (try git, fall back to current dir)
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

python "$SCRATCHPAD_PY" \
    --persona "$PERSONA" \
    --section "$SECTION" \
    --action "$ACTION" \
    --content "$CONTENT" \
    --root "$PROJECT_ROOT"

exit $?
