#!/usr/bin/env bash
# =============================================================================
# VeraProb — Test Presence Check (Ad-hoc Step 9.3)
# =============================================================================

set -uo pipefail

BASE_BRANCH="${BASE_BRANCH:-main}"
if git rev-parse --verify "origin/$BASE_BRANCH" >/dev/null 2>&1; then
  BASE_BRANCH="origin/$BASE_BRANCH"
elif ! git rev-parse --verify "$BASE_BRANCH" >/dev/null 2>&1; then
  BASE_BRANCH="HEAD~1"
fi

UNTRACKED_FILES=$(git ls-files --others --exclude-standard 2>/dev/null || true)
CHANGED_FILES=$(printf "%s\n%s" "$(git diff --name-only "$BASE_BRANCH" 2>/dev/null || git diff --name-only HEAD~1 2>/dev/null || true)" "$UNTRACKED_FILES")

CRITICAL_FILES=$(echo "$CHANGED_FILES" | grep -E "^lib/(domain|application|infrastructure|state)/" | grep -vE "\.(g|freezed)\.dart$" || true)
TOTAL_CRITICAL=$(echo "$CRITICAL_FILES" | grep -v '^[[:space:]]*$' | grep -c . || true)

echo "Comparing changes against base branch/commit: $BASE_BRANCH"

if [[ "$TOTAL_CRITICAL" -eq 0 ]]; then
  echo "No critical files (domain, application, infrastructure, state) changed. Nothing to check."
  exit 0
fi

echo -e "Checking Test Presence (70% Threshold)..."
echo -e "Total critical files changed: $TOTAL_CRITICAL"

COVERED_COUNT=0
MISSING_FILES=""
while IFS= read -r f; do
  [[ -z "$f" || "$f" =~ ^[[:space:]]*$ ]] && continue
  TEST_FILE=$(echo "$f" | sed 's|^lib/|test/|' | sed 's|\.dart$|_test.dart|')
  if echo "$CHANGED_FILES" | grep -q "$TEST_FILE" || [[ -f "$TEST_FILE" ]]; then
    COVERED_COUNT=$((COVERED_COUNT + 1))
    echo "  [OK] Covered: $f (test file found)"
  else
    # Fallback: import-based detection
    PACKAGE_PATH=$(echo "$f" | sed 's|^lib/|package:veraprob/|')
    SRC_BASENAME=$(basename "$f" .dart)
    SRC_BASENAME_ESC=$(printf '%s' "$SRC_BASENAME" | sed 's/[][\\.^$*?+{}()|]/\\&/g')
    IMPORT_HIT=$(grep -rl "import '$PACKAGE_PATH'" test/ 2>/dev/null | grep "_test\.dart$" | grep -E "(^|/)${SRC_BASENAME_ESC}_test\.dart$" | head -1 || true)
    if [[ -n "$IMPORT_HIT" ]]; then
      COVERED_COUNT=$((COVERED_COUNT + 1))
      echo "  [OK] Covered: $f (imported in test: $IMPORT_HIT)"
    else
      echo "  [MISSING] No test for: $f"
      MISSING_FILES+="\n    → $f"
    fi
  fi
done <<< "$CRITICAL_FILES"

PERCENTAGE=$(( COVERED_COUNT * 100 / TOTAL_CRITICAL ))

echo -e "\nResult: $PERCENTAGE% of critical files are covered by tests."
if [[ "$PERCENTAGE" -lt 70 ]]; then
  echo -e "FAIL: Test presence is $PERCENTAGE% (Target: 70%). Missing tests for:$MISSING_FILES"
  exit 1
else
  echo -e "SUCCESS: Test presence is $PERCENTAGE% (Target: 70%)."
  exit 0
fi
