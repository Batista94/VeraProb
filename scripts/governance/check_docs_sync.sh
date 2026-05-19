#!/usr/bin/env bash
# VeraProb — AGENTS.md ↔ SSOT sync validator.
#
# Verifies that the navigation indexes in AGENTS.md are not stale relative to
# their source-of-truth files:
#   - "Common CI Blocks — Index"  ↔  .claude/rules/ci-blocks.md  (## N. headings)
#   - "Lessons Learned — Index"   ↔  .kiro/steering/lessons.md   (## N. headings)
#
# Drift = mismatch in the set of top-level numeric headings.
# Exit 0 on sync, 1 on drift.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AGENTS_MD="${ROOT}/AGENTS.md"
CIB_MD="${ROOT}/.claude/rules/ci-blocks.md"
LESSONS_MD="${ROOT}/.kiro/steering/lessons.md"

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BOLD=$'\033[1m'
NC=$'\033[0m'

errors=0

# Extract numeric top-level (## N.) heading numbers from a markdown file.
ssot_nums() {
  local file="$1"
  grep -E '^## [0-9]+\. ' "$file" | sed -E 's/^## ([0-9]+)\..*/\1/' | sort -n -u
}

# Extract numeric table-row indexes from AGENTS.md between two markers.
index_nums() {
  local start="$1"
  local end="$2"
  awk -v s="$start" -v e="$end" '
    $0 ~ s {capture=1; next}
    capture && $0 ~ e {capture=0}
    capture && /^\| *[0-9]+ *\|/ {
      gsub(/^\| */, ""); gsub(/ *\|.*/, "")
      print
    }
  ' "$AGENTS_MD" | sort -n -u
}

check_block() {
  local label="$1"
  local ssot_file="$2"
  local start_marker="$3"
  local end_marker="$4"

  if [[ ! -f "$ssot_file" ]]; then
    printf '%b[FAIL]%b %s — SSOT file missing: %s\n' "$RED" "$NC" "$label" "$ssot_file"
    errors=$((errors+1))
    return
  fi

  local ssot_set index_set
  ssot_set="$(ssot_nums "$ssot_file")"
  index_set="$(index_nums "$start_marker" "$end_marker")"

  local missing_in_index missing_in_ssot
  missing_in_index="$(comm -23 <(printf '%s\n' "$ssot_set") <(printf '%s\n' "$index_set") | tr -d '[:space:]' | wc -c)"
  missing_in_ssot="$(comm -13  <(printf '%s\n' "$ssot_set") <(printf '%s\n' "$index_set") | tr -d '[:space:]' | wc -c)"

  if [[ "$missing_in_index" -eq 0 && "$missing_in_ssot" -eq 0 ]]; then
    local count
    count="$(printf '%s\n' "$ssot_set" | grep -c . || true)"
    printf '%b[OK]%b %s — %s entries in sync.\n' "$GREEN" "$NC" "$label" "$count"
    return
  fi

  errors=$((errors+1))
  printf '%b[DRIFT]%b %s\n' "$RED" "$NC" "$label"
  if [[ "$missing_in_index" -ne 0 ]]; then
    printf '  %bMissing in AGENTS.md index%b (present in SSOT, absent in table):\n' "$YELLOW" "$NC"
    comm -23 <(printf '%s\n' "$ssot_set") <(printf '%s\n' "$index_set") | sed 's/^/    - /'
  fi
  if [[ "$missing_in_ssot" -ne 0 ]]; then
    printf '  %bMissing in SSOT%b (in AGENTS.md table, no matching ## N. heading):\n' "$YELLOW" "$NC"
    comm -13 <(printf '%s\n' "$ssot_set") <(printf '%s\n' "$index_set") | sed 's/^/    - /'
  fi
}

printf '%b🔍 AGENTS.md ↔ SSOT Drift Check%b\n' "$BOLD" "$NC"
printf '─────────────────────────────────────────────\n'

check_block "Common CI Blocks Index" \
  "$CIB_MD" \
  '^## Common CI Blocks — Index' \
  '^## '

check_block "Lessons Learned Index" \
  "$LESSONS_MD" \
  '^## Lessons Learned — Index' \
  '^## '

printf '─────────────────────────────────────────────\n'
if [[ "$errors" -eq 0 ]]; then
  printf '%b✓ docs in sync.%b\n' "$GREEN" "$NC"
  exit 0
fi
printf '%b✗ %d drift(s) detected. Update AGENTS.md indexes or SSOT files.%b\n' "$RED" "$errors" "$NC"
exit 1
