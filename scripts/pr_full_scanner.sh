#!/usr/bin/env bash
# =============================================================================
# VeraProb PR Full Scanner — Deterministic Gatekeeper (Forensic Mode)
# =============================================================================
#
# MISSION: Apply deterministic regex patterns to git diff to ensure
# absolute compliance with the Forensic Audit Manifesto.
#
# Path Scoping: FINANCIAL/DDD rules restricted to lib/domain & lib/application.
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
if [[ "${FAST_SCAN:-0}" == "1" ]]; then
  echo -e "${YELLOW}FAST_SCAN=1: Skipping Step 1 (Slow Forensic Analysis)...${NC}"
else
  echo -e "${BOLD}${BLUE}Step 1: Running Original Forensic Scanner...${NC}"
  # Run and capture output to extract counts
  S1_RESULTS=$(bash "$SCRIPT_DIR/pr_scanner.sh" 2>&1 || true)
  echo "$S1_RESULTS" | grep -v "COUNTS:" || true
  
  S1_BLOCKS=$(echo "$S1_RESULTS" | grep "COUNTS:" | cut -d: -f2 | cut -d'|' -f1 || echo "0")
  S1_WARNS=$(echo "$S1_RESULTS" | grep "COUNTS:" | cut -d: -f2 | cut -d'|' -f2 || echo "0")
  
  TOTAL_BLOCKS=$((TOTAL_BLOCKS + S1_BLOCKS))
  TOTAL_WARNS=$((TOTAL_WARNS + S1_WARNS))
fi


# ── Step 2: Deterministic Pattern Scan ───────────────────────────────────────
echo -e "\n${BOLD}${BLUE}Step 2: Deterministic Pattern Scan (Lead Reviewer Mode)...${NC}"

# Detect changed files
CHANGED_FILES=$(git diff --name-only "$BASE_BRANCH"...HEAD 2>/dev/null || git diff --name-only HEAD~1 HEAD 2>/dev/null || true)

if [[ -z "$CHANGED_FILES" ]]; then
  echo "No changes detected in Git Diff."
  SCAN_RESULTS="COUNTS:0|0"
else
  # Detect Node.js
  NODE_CMD="node"
  if command -v node.exe >/dev/null 2>&1; then
    NODE_CMD="node.exe"
  fi

  # Use Node.js to parse the JSON and apply rules
  SCAN_RESULTS=$(echo "$CHANGED_FILES" | $NODE_CMD -e "
const fs = require('fs');
const { execSync } = require('child_process');

if (!fs.existsSync('scripts/pr_patterns.json')) {
  console.error('Error: scripts/pr_patterns.json not found.');
  process.exit(1);
}

const patterns = JSON.parse(fs.readFileSync('scripts/pr_patterns.json', 'utf8'));
const files = fs.readFileSync(0, 'utf8').split('\n').filter(f => f.length > 0);

let blocks = 0;
let warns = 0;

files.forEach(file => {
  if (file.endsWith('.g.dart') || file.endsWith('.freezed.dart')) return;
  if (!fs.existsSync(file)) return;
  if (!fs.statSync(file).isFile()) return;

  const content = fs.readFileSync(file, 'utf8');
  const lines = content.split('\n');

  Object.entries(patterns).forEach(([ruleName, config]) => {
    if (config.path_filter && !new RegExp(config.path_filter).test(file)) return;
    if (config.exclude_path_pattern && new RegExp(config.exclude_path_pattern, 'i').test(file)) return;
    if (config.exclude_files && config.exclude_files.some(exclude => file.includes(exclude))) return;
    if (config.files_containing && !config.files_containing.some(term => file.includes(term))) return;

    const regex = new RegExp(config.pattern);

    // ── Absence Check (INV-1 / INV-26-REPO) ──
    if (config.type === 'absence_check') {
      if (!regex.test(content)) return;
      const strippedContent = content
        .replace(/\/\*[\s\S]*?\*\//g, '')
        .replace(/\/\/\/.*$/gm, '')
        .replace(/\/\/.*$/gm, '');

      if (config.requires_supabase_content) {
        const hasSupabaseCall = config.requires_supabase_content.some(
          supaPattern => new RegExp(supaPattern).test(strippedContent)
        );
        if (!hasSupabaseCall) return; 
      }

      const mustAlsoContain = new RegExp(config.must_also_contain);
      if (!mustAlsoContain.test(strippedContent)) {
        process.stdout.write(\`  BLOCK: \${file} - \${ruleName}: \${config.description}\\n\`);
        blocks++;
      }
      return;
    }

    lines.forEach((line, index) => {
      if (!regex.test(line)) return;
      const bypassKeywords = ['// Physical Metric', '// pr_scanner: ignore', '- Double Required', 'Bridge Conversion', 'Probability Score'];
      const hasBypass = (l) => l && bypassKeywords.some(kw => l.includes(kw));
      if (hasBypass(line) || hasBypass(lines[index + 1])) return;
      if (ruleName === 'UTC-BLOCK') {
        const hasUtcOnSameLine = line.includes('.toUtc()');
        const hasUtcOnNextLine = (lines[index + 1] || '').trim().startsWith('.toUtc()');
        if (hasUtcOnSameLine || hasUtcOnNextLine) return;
      }
      process.stdout.write(\`  BLOCK: \${file}:\${index + 1} - \${ruleName}: \${config.description}\\n\`);
      blocks++;
    });
  });
});

console.log('COUNTS:' + blocks + '|' + warns);
")
  # Filter the real output to display blocks, then extract counts
  echo "$SCAN_RESULTS" | grep -v "COUNTS:" || true
fi

S2_BLOCKS=$(echo "$SCAN_RESULTS" | grep "COUNTS:" | cut -d: -f2 | cut -d'|' -f1 || echo "0")
S2_WARNS=$(echo "$SCAN_RESULTS" | grep "COUNTS:" | cut -d: -f2 | cut -d'|' -f2 || echo "0")

TOTAL_BLOCKS=$((TOTAL_BLOCKS + S2_BLOCKS))
TOTAL_WARNS=$((TOTAL_WARNS + S2_WARNS))


# ── Step 3: Regression Alerts ───────────────────────────────────────────────
echo -e "\n${BOLD}${BLUE}Step 3: Regression Impact Analysis...${NC}"
if [[ "${SKIP_REGRESSION:-0}" == "1" ]]; then
  echo -e "  ${GREEN}SKIP_REGRESSION=1: Skipping regression analysis.${NC}"
else
  # Filter files that contain the ignore-regression comment
  REGRESSION_FILES=$(echo "$CHANGED_FILES" | grep -E "supabase/migrations/|lib/domain/" | while read -r f; do
    if [[ -f "$f" ]] && ! grep -q "pr_scanner: ignore-regression" "$f" 2>/dev/null; then
      echo "$f"
    fi
  done)

  if [[ -n "$REGRESSION_FILES" ]]; then
    echo -e "  ${YELLOW}${BOLD}[REGRESSION-ALERT]${NC} Changes in migrations or domain detected."
    echo "$REGRESSION_FILES" | while read -r line; do echo "    → $line"; done
    HAS_REGRESSION=1
  fi
fi

# ── Final Summary ────────────────────────────────────────────────────────────
# Results already parsed in Step 2.



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
