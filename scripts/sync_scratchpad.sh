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

# Hardcoded path to Python script (for Windows compatibility)
# In Bash on Windows, C:\Users -> /c/Users
SCRATCHPAD_PY="/c/Users/wes_b/.claude/plugins/cache/scratchpad-manager/scripts/sync_scratchpad.py"

# Fallback to relative path if absolute doesn't exist
if [ ! -f "$SCRATCHPAD_PY" ]; then
    # Try relative to scripts dir
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SCRATCHPAD_PY="${SCRIPT_DIR}/../.claude/plugins/cache/scratchpad-manager/scripts/sync_scratchpad.py"
fi

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
