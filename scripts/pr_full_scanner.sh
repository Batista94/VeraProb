#!/usr/bin/env bash
# =============================================================================
# VeraProb PR Full Scanner — Deterministic Gatekeeper (Forensic Mode)
# =============================================================================
#
# MISSION: Apply deterministic regex patterns to git diff to ensure
# absolute compliance with the Forensic Audit Manifesto.
#
# Path Scoping: FINANCIAL/DDD rules restricted to lib/domain & lib/application.
# Escape Hatch: // forensic-ignore: RULE_NAME (on same or previous line).
# Bypass: Automatically ignores *.g.dart and *.freezed.dart.
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PATTERNS_JSON="$SCRIPT_DIR/pr_patterns.json"
BASE_BRANCH="${BASE_BRANCH:-main}"

# ── Color codes ──────────────────────────────────────────────────────────────
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ── State ────────────────────────────────────────────────────────────────────
TOTAL_BLOCKS=0
TOTAL_WARNS=0
HAS_REGRESSION=0

# ── Helpers ──────────────────────────────────────────────────────────────────
log_block() {
  echo -e "  ${RED}${BOLD}[BLOCK]${NC} ${RED}$1${NC}"
  TOTAL_BLOCKS=$((TOTAL_BLOCKS + 1))
}

log_warn() {
  echo -e "  ${YELLOW}${BOLD}[WARN]${NC}  ${YELLOW}$1${NC}"
  TOTAL_WARNS=$((TOTAL_WARNS + 1))
}

# ── Step 1: Run Original Scanner ─────────────────────────────────────────────
echo -e "${BOLD}${BLUE}Step 1: Running Original Forensic Scanner...${NC}"
bash "$SCRIPT_DIR/pr_scanner.sh" || {
  echo -e "${RED}Original scanner reported hard blocks.${NC}"
  # We continue to collect all deterministic errors
}

# ── Step 2: Deterministic Pattern Scan ───────────────────────────────────────
echo -e "\n${BOLD}${BLUE}Step 2: Deterministic Pattern Scan (Lead Reviewer Mode)...${NC}"

# Detect changed files
CHANGED_FILES=$(git diff --name-only "$BASE_BRANCH"...HEAD 2>/dev/null || git diff --name-only HEAD~1 HEAD 2>/dev/null || true)

if [[ -z "$CHANGED_FILES" ]]; then
  echo "No changes detected in Git Diff."
else
  # Use Node.js to parse the JSON and apply rules for efficiency/portability
  node.exe -e "
const fs = require('fs');
const { execSync } = require('child_process');

const patterns = JSON.parse(fs.readFileSync('$PATTERNS_JSON', 'utf8'));
const files = \`$CHANGED_FILES\`.split('\n').filter(f => f.length > 0);

let blocks = 0;
let warns = 0;

files.forEach(file => {
  // Generated Code Bypass
  if (file.endsWith('.g.dart') || file.endsWith('.freezed.dart')) return;
  if (!fs.existsSync(file)) return;

  const content = fs.readFileSync(file, 'utf8');
  const lines = content.split('\n');

  Object.entries(patterns).forEach(([ruleName, config]) => {
    // Path Scoping
    if (config.path_filter && !new RegExp(config.path_filter).test(file)) return;

    // Files Containing filter (e.g. for FINANCIAL-BLOCK)
    if (config.files_containing) {
       const matchesFile = config.files_containing.some(term => file.includes(term));
       if (!matchesFile) return;
    }

    const regex = new RegExp(config.pattern, 'g');
    
    lines.forEach((line, index) => {
      if (regex.test(line)) {
        // Escape Hatch Check
        const prevLine = index > 0 ? lines[index - 1] : '';
        const hasIgnore = line.includes('// forensic-ignore: ' + ruleName) || 
                          prevLine.includes('// forensic-ignore: ' + ruleName);

        if (hasIgnore) {
          console.log(\`  WARN: \${file}:\${index + 1} - \${ruleName} ignored via comment\`);
          warns++;
        } else {
          console.log(\`  BLOCK: \${file}:\${index + 1} - \${ruleName}: \${config.description}\`);
          blocks++;
        }
      }
    });
  });
});

process.exit(blocks > 0 ? 1 : 0);
" || {
    # Node will exit 1 if blocks found, but it already printed them.
    # We'll parse the output in shell to increment counts if needed, 
    # but for now let's just use it to report.
    # Actually, let's capture the counts.
    true
  }
fi

# ── Step 3: Regression Alerts ───────────────────────────────────────────────
echo -e "\n${BOLD}${BLUE}Step 3: Regression Impact Analysis...${NC}"
REGRESSION_FILES=$(echo "$CHANGED_FILES" | grep -E "supabase/migrations/|lib/domain/" || true)
if [[ -n "$REGRESSION_FILES" ]]; then
  echo -e "  ${YELLOW}${BOLD}[REGRESSION-ALERT]${NC} Changes in migrations or domain detected."
  echo "$REGRESSION_FILES" | while read -r line; do echo "    → $line"; done
  HAS_REGRESSION=1
fi

# ── Final Summary ────────────────────────────────────────────────────────────
# Re-summarize for final verdict box
# (Since the Node script doesn't update bash variables easily, I'll just run it again or 
# parse its output. Let's adjust the node script to output a parsable count).

RESULTS=$(node.exe -e "
const fs = require('fs');
const patterns = JSON.parse(fs.readFileSync('$PATTERNS_JSON', 'utf8'));
const files = \`$CHANGED_FILES\`.split('\n').filter(f => f.length > 0);
let blocks = 0; let warns = 0;
files.forEach(file => {
  if (file.endsWith('.g.dart') || file.endsWith('.freezed.dart')) return;
  if (!fs.existsSync(file)) return;
  const content = fs.readFileSync(file, 'utf8');
  const lines = content.split('\n');
  Object.entries(patterns).forEach(([ruleName, config]) => {
    if (config.path_filter && !new RegExp(config.path_filter).test(file)) return;
    if (config.files_containing && !config.files_containing.some(term => file.includes(term))) return;
    const regex = new RegExp(config.pattern);
    lines.forEach((line, index) => {
      if (regex.test(line)) {
        const prevLine = index > 0 ? lines[index - 1] : '';
        if (line.includes('// forensic-ignore: ' + ruleName) || prevLine.includes('// forensic-ignore: ' + ruleName)) warns++;
        else blocks++;
      }
    });
  });
});
console.log(blocks + '|' + warns);
")

TOTAL_BLOCKS=$(echo "$RESULTS" | cut -d'|' -f1)
TOTAL_WARNS=$(echo "$RESULTS" | cut -d'|' -f2)

VERDICT="[GO]"
[[ $TOTAL_BLOCKS -gt 0 ]] && VERDICT="[NO-GO]"
[[ $TOTAL_BLOCKS -eq 0 && ($TOTAL_WARNS -gt 0 || $HAS_REGRESSION -gt 0) ]] && VERDICT="[REVISE]"

echo -e "\n${BOLD}════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  LEAD REVIEWER VERDICT (Deterministic Mode)${NC}"
echo -e "════════════════════════════════════════════════════════════"
echo -e "  Deterministic Blocks: $TOTAL_BLOCKS"
echo -e "  Deterministic Warns:  $TOTAL_WARNS"
echo -e "  Regression Alert:    $( [[ $HAS_REGRESSION -eq 1 ]] && echo 'YES' || echo 'NO' )"
echo ""
echo -e "  FINAL VERDICT:        ${BOLD}$VERDICT${NC}"
echo -e "════════════════════════════════════════════════════════════"

if [[ "$VERDICT" == "[NO-GO]" ]]; then
  echo -e "${RED}Veto absoluto: violação invariante detectada.${NC}"
  exit 1
fi

exit 0
