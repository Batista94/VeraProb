#!/usr/bin/env bash
# =============================================================================
# VeraProb PR Full Scanner — Deterministic Gatekeeper (Forensic Mode)
# =============================================================================
#
# MISSION: Apply deterministic regex patterns to git diff to ensure
# absolute compliance with the Forensic Audit Manifesto.
#
# Architecture: Node.js scanner_engine.js executes a SINGLE PASS over all
# changed files and returns structured JSON. Bash handles color output,
# verdict calculation, and exit code.
#
# Path Scoping: FINANCIAL/DDD rules restricted to lib/domain & lib/application.
# Bypass: Automatically ignores *.g.dart and *.freezed.dart.
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
BASE_BRANCH="${BASE_BRANCH:-main}"

# ── Color codes ──────────────────────────────────────────────────────────────
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ── Detect Node.js ───────────────────────────────────────────────────────────
NODE_CMD="node"
if command -v node.exe >/dev/null 2>&1; then
  NODE_CMD="node.exe"
fi

# -- Path Normalization for Windows node.exe --
SCRIPT_DIR_WIN="$SCRIPT_DIR"
if [[ "$NODE_CMD" == *"node.exe"* ]]; then
  if command -v cygpath >/dev/null 2>&1; then
    SCRIPT_DIR_WIN=$(cygpath -w "$SCRIPT_DIR")
  else
    # Fallback to manual sed conversion if cygpath is missing
    SCRIPT_DIR_WIN=$(echo "$SCRIPT_DIR" | sed -e 's/^\/\([a-z]\)\//\1:\\/' -e 's/^\/mnt\/\([a-z]\)\//\1:\\/' -e 's/\//\\/g')
  fi
fi

# ── Step 1: Run Legacy Scanner (optional) ────────────────────────────────────
S1_BLOCKS=0
S1_WARNS=0

if [[ "${FAST_SCAN:-0}" == "1" ]]; then
  echo -e "${YELLOW}FAST_SCAN=1: Skipping Step 1 (Slow Forensic Analysis)...${NC}"
else
  echo -e "${BOLD}${BLUE}Step 1: Running Original Forensic Scanner...${NC}"
  S1_RESULTS=$(bash "$SCRIPT_DIR/pr_scanner.sh" 2>&1 || true)
  echo "$S1_RESULTS" | grep -v "COUNTS:" || true

  S1_BLOCKS=$(echo "$S1_RESULTS" | grep "COUNTS:" | cut -d: -f2 | cut -d'|' -f1 || echo "0")
  S1_WARNS=$(echo "$S1_RESULTS" | grep "COUNTS:" | cut -d: -f2 | cut -d'|' -f2 || echo "0")
fi

# ── Step 2: Deterministic Pattern Scan (Single-Pass Node.js Engine) ──────────
echo -e "\n${BOLD}${BLUE}Step 2: Deterministic Pattern Scan (Lead Reviewer Mode)...${NC}"

CHANGED_FILES=$(git diff --name-only "$BASE_BRANCH" 2>/dev/null || git diff --name-only HEAD~1 2>/dev/null || true)

if [[ -z "$CHANGED_FILES" ]]; then
  echo "No changes detected in Git Diff."
  SCAN_JSON='{"blocks":0,"warns":0,"has_regression":false,"violations":[],"regression_files":[]}'
else
  # Node.js single-pass engine returns structured JSON
  SCAN_JSON_RAW=$(echo "$CHANGED_FILES" | $NODE_CMD "$SCRIPT_DIR_WIN/scanner_engine.js" "--base-branch=$BASE_BRANCH" 2>&1)
  NODE_EXIT=$?

  if [[ $NODE_EXIT -ne 0 ]]; then
    echo -e "  ${RED}${BOLD}[ERROR]${NC} Node.js scanner engine crashed or failed to execute."
    echo -e "          Output: $(echo "$SCAN_JSON_RAW" | head -n 2)"
    SCAN_JSON='{"blocks":1,"warns":0,"has_regression":false,"violations":[],"regression_files":[]}'
  else
    SCAN_JSON="$SCAN_JSON_RAW"
    # Display violations in human-readable format
    echo "$SCAN_JSON" | $NODE_CMD -e "
    const fs = require('fs');
    try {
      const data = JSON.parse(fs.readFileSync(0, 'utf8'));
      const RED = '\x1b[0;31m';
      const YELLOW = '\x1b[1;33m';
      const BOLD = '\x1b[1m';
      const NC = '\x1b[0m';
      if (data.violations) {
        data.violations.forEach(v => {
          const tag = v.severity === 'BLOCK'
            ? RED + BOLD + '[BLOCK]' + NC
            : YELLOW + BOLD + '[WARN]' + NC;
          const loc = v.line ? v.file + ':' + v.line : v.file;
          console.log('  ' + tag + ' ' + loc + ' — ' + v.rule + ': ' + v.description);
        });
      }
    } catch (e) {
      console.error('  [ERROR] Failed to parse scanner output: ' + e.message);
    }
    "
  fi
fi

# Extract counts from JSON (robust fallback to 0)
extract_json_field() {
  echo "$SCAN_JSON" | $NODE_CMD -e "try { console.log(JSON.parse(require('fs').readFileSync(0,'utf8')).$1 ?? '0'); } catch(e) { console.log('$2'); }" || echo "$2"
}

S2_BLOCKS=$(extract_json_field "blocks" "1")
S2_WARNS=$(extract_json_field "warns" "0")
HAS_REGRESSION=$(extract_json_field "has_regression" "false")
REGRESSION_FILES=$(echo "$SCAN_JSON" | $NODE_CMD -e "try { console.log(JSON.parse(require('fs').readFileSync(0,'utf8')).regression_files.join('\n')); } catch(e) { console.log(''); }" || echo "")

TOTAL_BLOCKS=$((S1_BLOCKS + S2_BLOCKS))
TOTAL_WARNS=$((S1_WARNS + S2_WARNS))

# ── Step 3: Regression Alerts ───────────────────────────────────────────────
echo -e "\n${BOLD}${BLUE}Step 3: Regression Impact Analysis...${NC}"
if [[ "${SKIP_REGRESSION:-0}" == "1" ]]; then
  echo -e "  ${GREEN}SKIP_REGRESSION=1: Skipping regression analysis.${NC}"
elif [[ "$HAS_REGRESSION" == "true" ]]; then
  echo -e "  ${YELLOW}${BOLD}[REGRESSION-ALERT]${NC} Changes in migrations or domain detected."
  echo "$REGRESSION_FILES" | while read -r line; do
    [[ -n "$line" ]] && echo "    → $line"
  done
else
  echo -e "  ${GREEN}No regression-impacting changes detected.${NC}"
fi

# ── Step 4: Barrel File Validation (Architect Mode) ──────────────────────────
echo -e "\n${BOLD}${BLUE}Step 4: Barrel File Validation (INV-13)...${NC}"
PYTHON_CMD="python3"
if ! command -v python3 >/dev/null 2>&1; then
  PYTHON_CMD="python"
fi

# -- Path Normalization for Python --
BARREL_SCRIPT="$PROJECT_DIR/scripts/validate_barrel_files.py"
BARREL_SCRIPT_WIN="$BARREL_SCRIPT"
if [[ "$NODE_CMD" == *"node.exe"* ]]; then
  if command -v cygpath >/dev/null 2>&1; then
    BARREL_SCRIPT_WIN=$(cygpath -w "$BARREL_SCRIPT")
  else
    BARREL_SCRIPT_WIN=$(echo "$BARREL_SCRIPT" | sed -e 's/^\/\([a-z]\)\//\1:\\/' -e 's/^\/mnt\/\([a-z]\)\//\1:\\/' -e 's/\//\\/g')
  fi
fi

BARREL_RESULTS=$($PYTHON_CMD "$BARREL_SCRIPT_WIN" --branch="$BASE_BRANCH" 2>&1)
BARREL_EXIT=$?

if [[ $BARREL_EXIT -eq 2 ]]; then
  echo -e "  ${RED}${BOLD}[ERROR]${NC} Barrel validator crashed."
  echo -e "          $BARREL_RESULTS"
fi
echo "$BARREL_RESULTS" | grep -v "INTERNAL ERROR" || true

# ── Step 5: Type Parity Verification (QA Mode) ──────────────────────────────
echo -e "\n${BOLD}${BLUE}Step 5: Type Parity Verification (INV-7)...${NC}"
if [[ -z "$CHANGED_FILES" ]]; then
  echo "No changes detected."
else
  MIGRATIONS_COUNT=$(echo "$CHANGED_FILES" | grep "supabase/migrations/.*\.sql" | wc -l || echo "0")
  if [[ $MIGRATIONS_COUNT -gt 0 ]]; then
    echo -e "  Migrations detected ($MIGRATIONS_COUNT files). Checking for type sync..."
    TYPE_FILE="supabase/types.database.ts"
    
    # Check if type file is also changed
    if ! echo "$CHANGED_FILES" | grep -q "$TYPE_FILE"; then
       echo -e "  ${RED}${BOLD}[BLOCK]${NC} Migrations updated but $TYPE_FILE is NOT in this PR."
       TOTAL_BLOCKS=$((TOTAL_BLOCKS + 1))
    else
       echo -e "  ${GREEN}Infrastructure contract present in PR.${NC}"
    fi
  else
    echo -e "  ${GREEN}No migrations detected. Parity sync skipped.${NC}"
  fi
fi

# ── Step 6: Schema Integrity Verification (INV-15) ──────────────────────────
echo -e "\n${BOLD}${BLUE}Step 6: Schema Integrity Verification (INV-15)...${NC}"
if [[ -n "${CHANGED_FILES:-}" ]]; then
  MIGRATIONS_COUNT=$(echo "$CHANGED_FILES" | grep "supabase/migrations/.*\.sql" | wc -l || echo "0")
  if [[ $MIGRATIONS_COUNT -gt 0 ]]; then
    echo -e "  Migrations detected. Validating PostgREST schema health..."
    # Check if Supabase is running to perform live health check
    if supabase status > /dev/null 2>&1; then
       # Trigger reload to ensure cache is current
       bash "$SCRIPT_DIR/../refresh_schema_cache.sh" > /dev/null 2>&1
       
       HEALTH_CHECK=$(curl -s -o /dev/null -w "%{http_code}" -I "http://localhost:54321/rest/v1/")
       if [[ "$HEALTH_CHECK" -lt 200 || "$HEALTH_CHECK" -ge 400 ]]; then
          echo -e "  ${RED}${BOLD}[BLOCK]${NC} PostgREST API is unhealthy (HTTP $HEALTH_CHECK) after migration sync."
          TOTAL_BLOCKS=$((TOTAL_BLOCKS + 1))
       else
          echo -e "  ${GREEN}PostgREST API is healthy.${NC}"
       fi
    else
       echo -e "  ${YELLOW}${BOLD}[WARN]${NC} Supabase offline. Skipping live integrity check."
    fi
  else
    echo -e "  ${GREEN}No migrations detected. Integrity check skipped.${NC}"
  fi
else
  echo -e "  ${GREEN}No changes detected.${NC}"
fi

# ── Final Summary ────────────────────────────────────────────────────────────
# Note: BARREL_EXIT == 1 means ARCHITECTURAL VIOLATION.
# Other non-zero codes (2, 127, etc) are execution errors and shouldn't cause a Veto by default.

VERDICT="[GO]"
[[ $TOTAL_BLOCKS -gt 0 || $BARREL_EXIT -eq 1 ]] && VERDICT="[NO-GO]"
[[ $VERDICT == "[GO]" && ($TOTAL_WARNS -gt 0 || "$HAS_REGRESSION" == "true") ]] && VERDICT="[REVISE]"

echo -e "\n${BOLD}════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  LEAD REVIEWER VERDICT (Deterministic Mode)${NC}"
echo -e "════════════════════════════════════════════════════════════"
echo -e "  Deterministic Blocks: $TOTAL_BLOCKS"
echo -e "  Barrel Violations:   $( [[ $BARREL_EXIT -eq 1 ]] && echo 'YES' || echo 'NO' )"
echo -e "  Deterministic Warns:  $TOTAL_WARNS"
echo -e "  Regression Alert:    $( [[ "$HAS_REGRESSION" == "true" ]] && echo 'YES' || echo 'NO' )"
echo ""
echo -e "  FINAL VERDICT:        ${BOLD}$VERDICT${NC}"
echo -e "════════════════════════════════════════════════════════════"

if [[ "$VERDICT" == "[NO-GO]" ]]; then
  echo -e "${RED}Veto absoluto: violação invariante detectada.${NC}"
  exit 1
fi

exit 0
