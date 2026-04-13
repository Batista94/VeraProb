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
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
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

CHANGED_FILES=$(git diff --name-only "$BASE_BRANCH"...HEAD 2>/dev/null || git diff --name-only HEAD~1 HEAD 2>/dev/null || true)

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

# ── Final Summary ────────────────────────────────────────────────────────────

VERDICT="[GO]"
[[ $TOTAL_BLOCKS -gt 0 ]] && VERDICT="[NO-GO]"
[[ $TOTAL_BLOCKS -eq 0 && ($TOTAL_WARNS -gt 0 || "$HAS_REGRESSION" == "true") ]] && VERDICT="[REVISE]"

echo -e "\n${BOLD}════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  LEAD REVIEWER VERDICT (Deterministic Mode)${NC}"
echo -e "════════════════════════════════════════════════════════════"
echo -e "  Deterministic Blocks: $TOTAL_BLOCKS"
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
