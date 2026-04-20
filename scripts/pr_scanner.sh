#!/usr/bin/env bash
# =============================================================================
# VeraProb PR Scanner — Forensic First-Line Defense
# =============================================================================
#
# PILLAR A: Forensic Binary Rules
#   A1 — Wasm-Ready:       Blocks dart:html / dart:js imports (INV-17)
#   A2 — Financial Prec.:  Blocks double/float near financial terms (INV-4)
#   A3 — UTC Determinism:  Blocks DateTime.now() without .toUtc() (INV-6)
#   A4 — Zero-Downtime DB: Blocks destructive migration operations (INV-DB)
#
# PILLAR B: Static Quality
#   B1 — Dart Analyzer:    Blocks on errors; warns on warnings
#   B2 — Format Check:     Warns on unformatted files
#   B3 — God Class Check: Warns on files approaching 1,000 lines (maintainability limit)
#
# PILLAR C: Cost Efficiency & Automated Security
#   C1 — Secret Detection:    Blocks hardcoded API keys / service tokens
#   C2 — Dependency Audit:    Warns on new pubspec.yaml dependencies (INV-25)
#   C3 — Test Presence Ratio: Warns when domain/application files lack test files
#   C4 — Leaky Abstractions:  Warns on domain imports inside lib/features/
#
# PILLAR D: Strict Type-Safety (Phase 8.5)
#   D1 — Strict Casting:      Blocks implicit dynamic casts in Domain (INV-4)
#   D2 — Infra Audit:         Warns on strict violations in other layers
#
# Exit codes:
#   0 = PASS (may have warnings — flagged for LLM neural review)
#   1 = BLOCKED (hard invariant violation or analyzer errors)
#
# Usage:
#   bash scripts/pr_scanner.sh
#   BASE_BRANCH=develop bash scripts/pr_scanner.sh
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BASE_BRANCH="${BASE_BRANCH:-main}"

BLOCK_COUNT=0
WARN_COUNT=0

# ── Color codes ──────────────────────────────────────────────────────────────
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ── Helpers ──────────────────────────────────────────────────────────────────
header() {
  echo ""
  echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}${BLUE}  $1${NC}"
  echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════════════${NC}"
}

block() {
  echo -e "  ${RED}${BOLD}[BLOCK]${NC} ${RED}$1${NC}"
  BLOCK_COUNT=$((BLOCK_COUNT + 1))
}

warn() {
  echo -e "  ${YELLOW}[WARN] ${NC}$1"
  WARN_COUNT=$((WARN_COUNT + 1))
}

pass() {
  echo -e "  ${GREEN}[PASS] ${NC}$1"
}

print_hits() {
  local limit=${1:-5}
  local input_str
  input_str=$(cat -)
  local count=0
  local total
  total=$(echo "$input_str" | grep -c "^" || echo "0")
  
  echo "$input_str" | while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if (( count < limit )); then
      echo -e "         ${RED}→ $line${NC}"
    fi
    count=$((count + 1))
  done
  
  if (( count > limit )); then
    echo -e "         ${YELLOW}... and $((count - limit)) more hits (truncated to save tokens)${NC}"
  fi
}

cd "$PROJECT_DIR"

echo ""
echo -e "${BOLD}════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  VeraProb PR Scanner — $(date -u '+%Y-%m-%d %H:%M UTC')${NC}"
echo -e "${BOLD}  Base branch: $BASE_BRANCH${NC}"
echo -e "${BOLD}════════════════════════════════════════════════════════════${NC}"

# ─────────────────────────────────────────────────────────────────────────────
# PILLAR A — FORENSIC BINARY RULES
# ─────────────────────────────────────────────────────────────────────────────

header "PILLAR A — Forensic Invariant Checks"

# ── A1: Wasm-Ready Check ─────────────────────────────────────────────────────
echo ""
echo "  A1 — Wasm-Ready: scanning lib/ for forbidden dart:html / dart:js imports..."

WASM_HITS=$(grep -rn --include="*.dart" \
  -E "import ['\"]dart:html['\"]|import ['\"]dart:js['\"]" \
  lib/ 2>/dev/null \
  | grep -v "dart:js_interop" \
  | grep -vE "// Physical Metric|// pr_scanner: ignore" \
  || true)

if [[ -n "$WASM_HITS" ]]; then
  block "[WASM-BLOCK] dart:html/dart:js forbidden — use dart:js_interop (INV-17)"
  echo "$WASM_HITS" | print_hits 5
else
  pass "No forbidden dart:html/dart:js imports"
fi

# ── A2: Financial Precision Check ────────────────────────────────────────────
echo ""
echo "  A2 — Financial Precision: scanning lib/ for double/float near financial terms..."

FIN_HITS=$(grep -rn --include="*.dart" \
  -iE "(double|float).{0,60}(fine|price|amount|ledger|cents|penalty|revenue|cost)|(fine|price|amount|ledger|cents|penalty|revenue|cost).{0,60}(double|float)" \
  lib/domain/ lib/application/ 2>/dev/null \
  | grep -ivE "multiplier|rate\b|\.toDouble\(\)|toDouble\b|tryParse|fromDouble" \
  | grep -ivE "^[^:]*(coordinate|latitude|longitude|speed|heading|spatial)[^/]*\.dart:" \
  | grep -vE "// Physical Metric|// pr_scanner: ignore" \
  || true)

if [[ -n "$FIN_HITS" ]]; then
  block "[FIN-BLOCK] double/float storing monetary value in domain/application — use BIGINT cents (INV-4)"
  echo "         (Checked: lib/domain/ + lib/application/ | Excluded: multipliers, rates, toDouble())"
  echo "$FIN_HITS" | print_hits 5
else
  pass "No floating-point monetary storage in domain/application layers"
fi

# ── A3: UTC Determinism Check ────────────────────────────────────────────────
echo ""
echo "  A3 — UTC Determinism: BLOCKING raw DateTime.now() in lib/domain/ lib/application/ lib/infrastructure/..."

# A3 STRICT: Block ALL raw DateTime.now() in core layers — must use IDateTimeProvider
# Exclusions: date_time_provider.dart (it IS the provider), StaticDateTimeProvider fallback, 
# UI date pickers, mock implementations, and logger timestamp
STRICT_DT_HITS=$(grep -rn --include="*.dart" \
  "DateTime\.now()" \
  lib/domain/ lib/application/ lib/infrastructure/ 2>/dev/null \
  | grep -vE "date_time_provider\.dart|// ignore:|// Physical Metric|// pr_scanner: ignore|IDateTimeProvider|_dateTimeProvider\.now\(\)|provider\.now\(\)|BrazilDateTimeProvider|FakeDateTimeProvider" \
  | grep -vE "StaticDateTimeProvider\.instance" \
  | grep -vE "millisecondsSinceEpoch|\.difference\(|initialDate:|firstDate:|lastDate:|pdf_export_service" \
  | grep -vE "\?\?[[:space:]]*DateTime\.now\(\)|DateTime\.now\(\)\.subtract\(" \
  | grep -vE "DateTime _[a-zA-Z]*[Dd]ate\s*=" \
  | grep -vE "date_time_provider\.dart" \
  || true)

if [[ -n "$STRICT_DT_HITS" ]]; then
  block "[UTC-BLOCK] Raw DateTime.now() detected in core layers — use IDateTimeProvider.nowUtc() instead (INV-6)"
  echo "$STRICT_DT_HITS" | print_hits 5
else
  pass "No raw DateTime.now() in domain/application/infrastructure layers"
fi

echo ""
echo "  A3-legacy — UTC Determinism: scanning lib/ test/ for DateTime.now() without .toUtc()..."

UTC_HITS=$(grep -rn --include="*.dart" \
  "DateTime\.now()" lib/ test/ 2>/dev/null \
  | grep -v "\.toUtc()" \
  | grep -vE "millisecondsSinceEpoch|\.difference\(|initialDate:|firstDate:|lastDate:|pdf_export_service" \
  | grep -vE "\?\?[[:space:]]*DateTime\.now\(\)|DateTime\.now\(\)\.subtract\(" \
  | grep -vE "DateTime _[a-zA-Z]*[Dd]ate\s*=" \
  | grep -vE "// Physical Metric|// pr_scanner: ignore" \
  | while IFS= read -r hit; do
      file=$(echo "$hit" | cut -d: -f1)
      linenum=$(echo "$hit" | sed 's/[^:]*:\([0-9]*\):.*/\1/')
      nextline=$(sed -n "$((linenum+1))p" "$file" 2>/dev/null || true)
      if ! echo "$nextline" | grep -q "\.toUtc()"; then
        echo "$hit"
      fi
    done \
  || true)

if [[ -n "$UTC_HITS" ]]; then
  block "[UTC-BLOCK] DateTime.now() without .toUtc() — all timestamps must be UTC (INV-6)"
  echo "$UTC_HITS" | print_hits 5
else
  pass "All DateTime.now() calls use .toUtc()"
fi

# ── A4: Zero-Downtime DB Check ───────────────────────────────────────────────
echo ""
echo "  A4 — Zero-Downtime DB: scanning changed migrations for destructive operations..."

CHANGED_MIGRATIONS=""
normalize_migration_paths() {
  tr '\\' '/' | tr -d '\r' | grep "supabase/migrations" || true
}

if git rev-parse --verify "$BASE_BRANCH" > /dev/null 2>&1; then
  CHANGED_MIGRATIONS=$(git diff --name-only "$BASE_BRANCH"...HEAD 2>/dev/null \
    | normalize_migration_paths)
fi
if [[ -z "$CHANGED_MIGRATIONS" ]]; then
  CHANGED_MIGRATIONS=$(git diff --name-only HEAD~1 HEAD 2>/dev/null \
    | normalize_migration_paths)
fi

if [[ -z "$CHANGED_MIGRATIONS" ]]; then
  warn "No changed migration files detected — if this is a DB-related PR, verify migrations manually"
else
  DB_BLOCK_FOUND=0
  while IFS= read -r migration_file; do
    if [[ -f "$migration_file" ]]; then
      DB_HITS=$(grep -niE \
        "DROP TABLE|DELETE FROM|TRUNCATE|ALTER COLUMN.+TYPE" \
        "$migration_file" 2>/dev/null \
        | grep -v "pr_scanner: ignore" \
        || true)
      if [[ -n "$DB_HITS" ]]; then
        block "[DB-BLOCK] Destructive migration in $migration_file — append-only schema required (INV-DB)"
        echo "$DB_HITS" | print_hits 3
        DB_BLOCK_FOUND=1
      fi
    fi
  done <<< "$CHANGED_MIGRATIONS"

  if [[ $DB_BLOCK_FOUND -eq 0 ]]; then
    pass "No destructive DB operations in changed migrations"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# PILLAR B — STATIC QUALITY
# ─────────────────────────────────────────────────────────────────────────────

header "PILLAR B — Static Quality & Clean Code Metrics"

# ── B1: Dart Analyzer ────────────────────────────────────────────────────────
echo ""
echo "  B1 — Dart Analyzer: running flutter analyze --no-pub..."
echo "       (this may take 10–30 seconds)"

if command -v cmd.exe >/dev/null 2>&1; then
  FLUTTER_CMD="cmd.exe /c flutter.bat"
else
  FLUTTER_CMD="flutter"
fi

ANALYZE_OUTPUT=$($FLUTTER_CMD analyze --no-pub 2>&1)
ANALYZE_EXIT=$?
ANALYZE_ERRORS=$(echo "$ANALYZE_OUTPUT" | grep -iE "^\s*error\b" || true)
ANALYZE_WARNINGS=$(echo "$ANALYZE_OUTPUT" | grep -iE "^\s*warning\b" || true)
ANALYZE_INFOS=$(echo "$ANALYZE_OUTPUT" | grep -iE "^\s*info\b" || true)

if [[ $ANALYZE_EXIT -ne 0 && -z "$ANALYZE_ERRORS" && -z "$ANALYZE_WARNINGS" ]]; then
  block "[ANALYZE-BLOCK] flutter analyze failed to execute (binary error). Check environment."
  echo -e "         ${RED}Output:${NC}"
  echo "$ANALYZE_OUTPUT" | grep -v "^\s*$" | head -n 5 | while read -r line; do
    echo -e "         ${RED}→ $line${NC}"
  done
fi

if [[ $ANALYZE_EXIT -ne 0 && -n "$ANALYZE_ERRORS" ]]; then
  block "[ANALYZE-BLOCK] flutter analyze reported errors — fix before merge"
  echo "$ANALYZE_ERRORS" | print_hits 10
elif [[ $ANALYZE_EXIT -eq 0 && -z "$ANALYZE_WARNINGS" ]]; then
  pass "flutter analyze: clean"
fi

if [[ -n "$ANALYZE_WARNINGS" ]]; then
  warn "[ANALYZE-WARN] flutter analyze reported warnings — LLM neural review required"
  echo "$ANALYZE_WARNINGS" | print_hits 10
fi

if [[ -n "$ANALYZE_INFOS" ]]; then
  echo -e "  ${NC}[INFO]  $(echo "$ANALYZE_INFOS" | wc -l | tr -d ' ') info hints (non-blocking)"
fi

# ── B2: Format Check ─────────────────────────────────────────────────────────
echo ""
echo "  B2 — Format Check: running dart format check on lib/..."

if command -v cmd.exe >/dev/null 2>&1; then
  DART_CMD="cmd.exe /c dart.bat"
else
  DART_CMD="dart"
fi

FORMAT_OUTPUT=$($DART_CMD format --output=none --set-exit-if-changed lib/ 2>&1)
FORMAT_EXIT=$?

if [[ $FORMAT_EXIT -eq 1 ]]; then
  # Check if it was actually unformatted files or an execution error
  if echo "$FORMAT_OUTPUT" | grep -q "Changed "; then
    warn "[FORMAT-WARN] Unformatted files detected — run: dart format lib/"
    echo -e "         ${YELLOW}(Run 'dart format lib/' to auto-fix before committing)${NC}"
  else
    block "[FORMAT-BLOCK] dart format failed to execute. Check environment/shebangs."
    echo -e "         ${RED}Output: $(echo "$FORMAT_OUTPUT" | head -n 2)${NC}"
  fi
elif [[ $FORMAT_EXIT -ne 0 ]]; then
  block "[FORMAT-BLOCK] dart format exited with code $FORMAT_EXIT"
  echo -e "         ${RED}Output: $(echo "$FORMAT_OUTPUT" | head -n 2)${NC}"
else
  pass "dart format: all files properly formatted"
fi

# ── B3: Large File Delta Warning ─────────────────────────────────────────────
echo ""
echo "  B3 — God Class Check: scanning for files approaching 1,000 lines..."

CHANGED_DART=""
normalize_paths() {
  tr '\\' '/' | tr -d '\r' | tr '\t' '\n' | grep "\.dart$" || true
}
if git rev-parse --verify "$BASE_BRANCH" > /dev/null 2>&1; then
  CHANGED_DART=$(git diff --name-only "$BASE_BRANCH"...HEAD 2>/dev/null \
    | normalize_paths)
fi
if [[ -z "$CHANGED_DART" ]]; then
  CHANGED_DART=$(git diff --name-only HEAD~1 HEAD 2>/dev/null \
    | normalize_paths)
fi

COMPLEXITY_FLAGS=0
if [[ -n "$CHANGED_DART" ]]; then
  while IFS= read -r dart_file; do
    [[ -z "$dart_file" ]] && continue
    dart_file=$(echo "$dart_file" | tr '\\' '/')
    if [[ -f "$dart_file" ]]; then
      # Skip test files for God Class check — integration tests are naturally verbose
      if [[ "$dart_file" == test/* ]]; then
        continue
      fi
      TOTAL_LINES=$(wc -l < "$dart_file" | tr -d ' ' || echo "0")
      if (( TOTAL_LINES >= 1000 )); then
        block "[GOD-CLASS-BLOCK] $dart_file has $TOTAL_LINES lines — exceeds 1,000 line limit (Refactor required)"
        COMPLEXITY_FLAGS=$((COMPLEXITY_FLAGS + 1))
      elif (( TOTAL_LINES >= 800 )); then
        warn "[GOD-CLASS-WARN] $dart_file approaching God Class status ($TOTAL_LINES lines) — plan refactoring"
        COMPLEXITY_FLAGS=$((COMPLEXITY_FLAGS + 1))
      fi
    fi
  done <<< "$CHANGED_DART"
  if [[ $COMPLEXITY_FLAGS -eq 0 ]]; then
    pass "All modified files are within safe maintainability limits (<800 lines)"
  fi
else
  echo -e "  ${NC}[INFO]  No changed Dart files found for God Class check"
fi

# ─────────────────────────────────────────────────────────────────────────────
# PILLAR C — COST EFFICIENCY & AUTOMATED SECURITY
# ─────────────────────────────────────────────────────────────────────────────

header "PILLAR C — Cost Efficiency & Automated Security"

# ── C1: Secret Detection ──────────────────────────────────────────────────────
echo ""
echo "  C1 — Secret Detection: scanning lib/ for hardcoded secrets / API keys..."
SECRET_HITS=$(grep -rn --include="*.dart" \
  -E "(sb_[a-zA-Z0-9]{20,}|sk_[a-zA-Z0-9]{20,}|(serviceRoleKey|anonKey|apiKey|api_key|secretKey)\s*[=:]\s*['\"][^'\"]{20,}['\"]|eyJ[a-zA-Z0-9_\-]{50,})" \
  lib/ 2>/dev/null \
  | grep -vE "Env\.|AppConfig\.|\.env" \
  | grep -vE "// Physical Metric|// pr_scanner: ignore" \
  || true)
if [[ -n "$SECRET_HITS" ]]; then
  block "[SECRET-BLOCK] Hardcoded secret or API key pattern detected — move to .env / Env class (Security / INV-25)"
  echo "$SECRET_HITS" | print_hits 5
else
  pass "No hardcoded secret patterns detected in lib/"
fi

# ── C2: Dependency & License Audit ───────────────────────────────────────────
echo ""
echo "  C2 — Dependency Audit: scanning pubspec.yaml for new dependencies..."
PUBSPEC_DIFF=""
if git rev-parse --verify "$BASE_BRANCH" > /dev/null 2>&1; then
  PUBSPEC_DIFF=$(git diff "$BASE_BRANCH"...HEAD -- pubspec.yaml 2>/dev/null || true)
fi
if [[ -z "$PUBSPEC_DIFF" ]]; then
  PUBSPEC_DIFF=$(git diff HEAD~1 HEAD -- pubspec.yaml 2>/dev/null || true)
fi
if [[ -n "$PUBSPEC_DIFF" ]]; then
  NEW_DEPS=$(echo "$PUBSPEC_DIFF" \
    | grep "^+" | grep -v "^+++" | grep -E "^\+[[:space:]]+[a-z_]+:[[:space:]]" | grep -v "^#" \
    || true)
  if [[ -n "$NEW_DEPS" ]]; then
    warn "[DEP-WARN] New dependencies detected in pubspec.yaml — manual license and security review required (INV-25 / Free-Tier Gate)"
    echo "$NEW_DEPS" | while IFS= read -r line; do
      [[ -n "$line" ]] && echo -e "         ${YELLOW}→ $(echo "$line" | xargs)${NC}"
    done
  else
    pass "No new dependencies added to pubspec.yaml"
  fi
else
  pass "pubspec.yaml unchanged"
fi

# ── C3: Test Presence Ratio ───────────────────────────────────────────────────
echo ""
echo "  C3 — Test Coverage Gate: checking for missing test files for changed domain/application sources..."
MISSING_TESTS=0
if [[ -n "$CHANGED_DART" ]]; then
  while IFS= read -r dart_file; do
    [[ -z "$dart_file" ]] && continue
    [[ "$dart_file" == *.g.dart ]] && continue
    [[ "$dart_file" == *.freezed.dart ]] && continue
    [[ "$dart_file" == *_test.dart ]] && continue
    [[ "$dart_file" == lib/features/* ]] && continue
    [[ "$dart_file" == lib/main*.dart ]] && continue
    [[ "$dart_file" == lib/core/config/* ]] && continue
    [[ "$dart_file" == lib/core/theme/* ]] && continue
    [[ "$dart_file" == lib/core/router/* ]] && continue
    test_file=$(echo "$dart_file" | sed 's|^lib/|test/|' | sed 's|\.dart$|_test.dart|')
    if [[ ! -f "$test_file" ]]; then
      warn "[TEST-WARN] No test file for $dart_file — expected: $test_file (coverage gate >60%)"
      MISSING_TESTS=$((MISSING_TESTS + 1))
    fi
  done <<< "$CHANGED_DART"
  if [[ $MISSING_TESTS -eq 0 ]]; then
    pass "All changed domain/application/infrastructure files have corresponding test files"
  fi
else
  echo -e "  ${NC}[INFO]  No changed Dart files found for test coverage check"
fi

# ── C4: Leaky Abstraction Static Check ────────────────────────────────────────
echo ""
echo "  C4 — Leaky Abstraction: scanning lib/features/ for direct domain imports..."
LEAK_HITS=$(grep -rn --include="*.dart" \
  "import 'package:veraprob/domain/" \
  lib/features/ 2>/dev/null \
  | grep -vE "// Physical Metric|// pr_scanner: ignore" \
  || true)
if [[ -n "$LEAK_HITS" ]]; then
  warn "[LEAK-WARN] Domain imports found in lib/features/ — domain types must flow through application-layer ViewModels/DTOs (INV-4 / Lens 2)"
  echo "$LEAK_HITS" | print_hits
else
  pass "No leaky domain imports in features/ presentation layer"
fi

# ─────────────────────────────────────────────────────────────────────────────
# PILLAR D — STRICT TYPE-SAFETY AUDIT (PHASE 8.5)
# ─────────────────────────────────────────────────────────────────────────────

header "PILLAR D — Strict Type-Safety Audit (Phase 8.5)"

STRICT_OPTIONS="$PROJECT_DIR/analysis_options_strict.yaml"

# Write a temporary strict analysis_options
cat > "$STRICT_OPTIONS" << 'EOF'
include: package:flutter_lints/flutter.yaml
analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
EOF

echo ""
echo "  D1 — Strict Casting: checking for implicit dynamic casts (INV-4)..."

# Capture output — don't fail on non-zero exit (violations are expected during Phase 8.5)
STRICT_OUTPUT=$($FLUTTER_CMD analyze --no-pub --options "$STRICT_OPTIONS" 2>&1 || true)
rm -f "$STRICT_OPTIONS"

DOMAIN_STRICT=$(echo "$STRICT_OUTPUT" | grep "lib/domain/" || true)
if [[ -n "$DOMAIN_STRICT" ]]; then
  block "[STRICT-BLOCK] Implicit dynamic cast in Domain layer — fix with 'as Type' (INV-4)"
  echo "$DOMAIN_STRICT" | print_hits 10
else
  pass "Domain layer: 0 strict-type violations (INV-4 compliant)"
fi

INFRA_STRICT=$(echo "$STRICT_OUTPUT" | grep "lib/infrastructure/" || true)
if [[ -n "$INFRA_STRICT" ]]; then
  warn "[STRICT-WARN] Strict-type violations in Infrastructure layer (JSON decoding)"
  echo -e "         ${YELLOW}$(echo "$INFRA_STRICT" | grep -c "^" || echo "0") violations detected${NC}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# PILLAR E — FORENSIC IDENTITY & ERROR PARITY (INV-1 / INV-26)
# ─────────────────────────────────────────────────────────────────────────────

header "PILLAR E — Forensic Identity & Error Parity"

echo ""
echo "  E1 — Identity Sovereignty: validating TenantValidationService in Handlers (INV-1)..."

# Target: Files in lib/application/ ending in _handler.dart
HANDLER_FILES=$(find lib/application/ -name "*_handler.dart" 2>/dev/null || true)

if [[ -z "$HANDLER_FILES" ]]; then
  pass "No application handlers found to validate"
else
  INV1_BLOCK_FOUND=0
  while IFS= read -r handler_file; do
    [[ -z "$handler_file" ]] && continue

    # Pre-processing: Strip multiline comments, single-line comments (starting with //), and imports
    CLEAN_TEXT=$(perl -0777 -pe 's/\/\*.*?\*\///gs' "$handler_file" | sed '/^\s*\/\//d; /^\s*import/d')

    # Handlers exempt from tenant validation (public token ops, super-admin, MFA)
    BASENAME=$(basename "$handler_file")
    if [[ "$BASENAME" == "accept_invitation_handler.dart" ]] || \
       [[ "$BASENAME" == "accept_by_contractor_handler.dart" ]] || \
       [[ "$BASENAME" == "mfa_challenge_handler.dart" ]] || \
       [[ "$BASENAME" == "mfa_enrollment_handler.dart" ]] || \
       [[ "$BASENAME" == "create_organization_handler.dart" ]]; then
      continue
    fi

    # Check INV-1: _tenantValidator.assertTenantMatches( must be present in the clean text
    if ! echo "$CLEAN_TEXT" | grep -q "assertTenantMatches("; then
      # Allow bypass if explicitly ignored in the file
      if ! grep -q "// pr_scanner: ignore" "$handler_file"; then
        block "[INV-1-BLOCK] $handler_file missing _tenantValidator.assertTenantMatches() call."
        INV1_BLOCK_FOUND=1
      fi
    fi
  done <<< "$HANDLER_FILES"

  if [[ $INV1_BLOCK_FOUND -eq 0 ]]; then
    pass "All application handlers implement mandatory identity sovereignty checks (INV-1)"
  fi
fi

echo ""
echo "  E2 — Error Parity: scanning lib/ for forbidden error patterns (INV-26)..."

# Search for forbidden patterns in all dart files in lib/
# We use the same stripping logic per file to ensure we don't block commented-out code
FORBIDDEN_HITS=""
DART_FILES=$(find lib/ -name "*.dart" 2>/dev/null || true)

if [[ -n "$DART_FILES" ]]; then
  while IFS= read -r dart_file; do
    [[ -z "$dart_file" ]] && continue
    
    # Pre-processing: Strip multiline comments, single-line comments, and imports
    CLEAN_LINES=$(perl -0777 -pe 's/\/\*.*?\*\///gs' "$dart_file" | sed '/^\s*\/\//d; /^\s*import/d')
    
    # Check for INV-26 forbidden patterns
    ERR_HITS=$(echo "$CLEAN_LINES" | grep -nE "throw Exception|return 403|return 401" || true)
    
    if [[ -n "$ERR_HITS" ]]; then
       if ! grep -q "// pr_scanner: ignore" "$dart_file"; then
         while IFS= read -r hit; do
           line_num=$(echo "$hit" | cut -d: -f1)
           content=$(echo "$hit" | cut -d: -f2-)
           FORBIDDEN_HITS="${FORBIDDEN_HITS}${dart_file}:${line_num}:${content}\n"
         done <<< "$ERR_HITS"
       fi
    fi
  done <<< "$DART_FILES"
fi

if [[ -n "$FORBIDDEN_HITS" ]]; then
  block "[INV-26-BLOCK] Forbidden error patterns (throw Exception/return 401/403) detected — use DomainException (INV-26)"
  echo -e "$FORBIDDEN_HITS" | print_hits 5
else
  pass "No forbidden error patterns detected in lib/ (INV-26 compliance)"
fi


echo ""
echo -e "${BOLD}════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  SCAN SUMMARY${NC}"
echo -e "${BOLD}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}BLOCKS  (hard failures, exit 1):${NC}  $BLOCK_COUNT"
echo -e "  ${BOLD}WARNINGS (flagged for LLM review):${NC} $WARN_COUNT"
echo ""

if [[ $BLOCK_COUNT -gt 0 ]]; then
  echo -e "  ${RED}${BOLD}❌ VERDICT: PR BLOCKED — $BLOCK_COUNT invariant violation(s) detected.${NC}"
  echo -e "  ${RED}   The Lead Reviewer MUST issue [NO-GO] immediately.${NC}"
  echo -e "  ${RED}   Fix all [BLOCK] violations and re-run this script.${NC}"
  echo ""
  echo "COUNTS:$BLOCK_COUNT|$WARN_COUNT"
  exit 1
else
  echo -e "  ${GREEN}${BOLD}✅ VERDICT: SCRIPT CLEAN — Proceed to LLM Neural Analysis (Step 1).${NC}"
  if [[ $WARN_COUNT -gt 0 ]]; then
    echo -e "  ${YELLOW}   $WARN_COUNT warning(s) flagged for LLM attention in neural review.${NC}"
  fi
  echo ""
  echo "COUNTS:$BLOCK_COUNT|$WARN_COUNT"
  exit 0
fi
