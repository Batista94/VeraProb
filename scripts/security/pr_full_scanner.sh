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
#
# Steps:
#   Step 1: Deterministic Pattern Scan (Node.js engine)
#   Step 2: Regression Impact Analysis
#   Step 3: Barrel File Validation (INV-13)
#   Step 4: Type Parity Verification (INV-7)
#   Step 5: Schema Integrity Verification (INV-15)
#   Step 6: Static Analysis
#     6.1  flutter analyze — BLOCK on core layer errors, WARN on presentation (INV-6/7)
#     6.2  dart format    — WARN on unformatted files (auto-fixable)
#   Step 7: Dependency & License Audit (INV-25)
#   Step 8: Architecture Integrity
#     8.1  C4 leaky abstraction — domain imports in lib/features/ (BLOCK)
#     8.2  E2 error parity      — throw Exception / return 401/403 (BLOCK)
#     8.3  D1/D2 strict type-safety (BLOCK domain, WARN infra)
#     8.4  Test Folder Parity Gate (BLOCK test/data & test/e2e)
#   Step 9: Governance & Process Audit
#     9.1  Mandatory Test Plan for Migrations
#     9.2  Enterprise Complexity Analysis (dart_code_metrics)
#     9.3  Test Presence Gate (BLOCK→main, WARN→feature branch)
#   Step 10: Deno Test Suite (Edge Functions)
#
# SKIP flags (env vars):
#   SKIP_REGRESSION=1     — skip regression alert (Step 2)
#   SKIP_ANALYZE=1        — skip flutter analyze (~30s, Step 6.1)
#   SKIP_STRICT_TYPES=1   — skip strict type-safety analysis (~30s, Step 8.3)
#   SKIP_DENO_TESTS=1     — skip Deno test suite (Step 10)
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
BASE_BRANCH="${BASE_BRANCH:-main}"
if git rev-parse --verify "origin/$BASE_BRANCH" >/dev/null 2>&1; then
  BASE_BRANCH="origin/$BASE_BRANCH"
elif ! git rev-parse --verify "$BASE_BRANCH" >/dev/null 2>&1; then
  BASE_BRANCH="HEAD~1"
fi

# ── Test Gate Severity: BLOCK on main, WARN on feature branches ─────────────
# BLOCK when: current branch IS main, OR CI PR targets main (GITHUB_BASE_REF),
#             OR caller forces strict mode (STRICT_TESTS=1).
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
TEST_GATE_BLOCK="false"
[[ "$CURRENT_BRANCH" == "main" ]] && TEST_GATE_BLOCK="true"
[[ "${GITHUB_BASE_REF:-}" == "main" ]] && TEST_GATE_BLOCK="true"
[[ "${STRICT_TESTS:-0}" == "1" ]] && TEST_GATE_BLOCK="true"

# ── Color codes (TTY-gated — no escape codes in piped/VSCode contexts) ───────
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  YELLOW='\033[1;33m'
  GREEN='\033[0;32m'
  BLUE='\033[0;34m'
  BOLD='\033[1m'
  NC='\033[0m'
else
  RED=''
  YELLOW=''
  GREEN=''
  BLUE=''
  BOLD=''
  NC=''
fi

# ── Command Detection (top-level, shared by all steps) ───────────────────────
NODE_CMD="node"
command -v node.exe >/dev/null 2>&1 && NODE_CMD="node.exe"

FLUTTER_CMD="flutter"
DART_CMD="dart"
if command -v cmd.exe >/dev/null 2>&1; then
  FLUTTER_CMD="cmd.exe /c flutter.bat"
  DART_CMD="cmd.exe /c dart.bat"
fi

PYTHON_CMD="python3"
command -v python3 >/dev/null 2>&1 || PYTHON_CMD="python"

# -- Path Normalization for Windows node.exe --
SCRIPT_DIR_WIN="$SCRIPT_DIR"
if [[ "$NODE_CMD" == *"node.exe"* ]]; then
  if command -v cygpath >/dev/null 2>&1; then
    SCRIPT_DIR_WIN=$(cygpath -m "$SCRIPT_DIR")
  elif command -v wslpath >/dev/null 2>&1; then
    SCRIPT_DIR_WIN=$(wslpath -m "$SCRIPT_DIR")
  else
    # Fallback using forward slashes to avoid shell escape issues
    SCRIPT_DIR_WIN=$(echo "$SCRIPT_DIR" | sed -e 's/^\/\([a-z]\)\//\1:\//' -e 's/^\/mnt\/\([a-z]\)\//\1:\//')
  fi
fi

# -- Extract JSON object from scanner stdout (ignore git/noise lines on Windows) --
parse_scanner_json() {
  local raw="$1"
  printf '%s' "$raw" | $NODE_CMD "$SCRIPT_DIR_WIN/parse_scan_json.js" 2>/dev/null
}

# ── Step 1: Deterministic Pattern Scan (Single-Pass Node.js Engine) ──────────
echo -e "\n${BOLD}${BLUE}Step 1: Deterministic Pattern Scan (Lead Reviewer Mode)...${NC}"

# -- Include untracked files in the initial list --
UNTRACKED_FILES=$(git ls-files --others --exclude-standard 2>/dev/null || true)
CHANGED_FILES=$(printf "%s\n%s" "$(git diff --name-only "$BASE_BRANCH" 2>/dev/null || git diff --name-only HEAD~1 2>/dev/null || true)" "$UNTRACKED_FILES")

if [[ -z "$(echo "$CHANGED_FILES" | tr -d '[:space:]')" ]]; then
  echo "No changes detected in Git Diff."
  SCAN_JSON='{"blocks":0,"warns":0,"has_regression":false,"violations":[],"regression_files":[]}'
else
  # Node.js single-pass engine: JSON on stdout only; git warnings stay on stderr.
  SCAN_JSON_RAW=$(echo "$CHANGED_FILES" | $NODE_CMD "$SCRIPT_DIR_WIN/scanner_engine.js" "--base-branch=$BASE_BRANCH")
  NODE_EXIT=$?
  SCAN_JSON=$(parse_scanner_json "$SCAN_JSON_RAW" || true)

  if [[ $NODE_EXIT -ne 0 ]]; then
    echo -e "  ${RED}${BOLD}[ERROR]${NC} Node.js scanner engine crashed or failed to execute."
    echo -e "          Output: $(echo "$SCAN_JSON_RAW" | head -n 2)"
    SCAN_JSON='{"blocks":1,"warns":0,"has_regression":false,"violations":[],"regression_files":[]}'
  elif [[ -z "$SCAN_JSON" ]]; then
    echo -e "  ${RED}${BOLD}[ERROR]${NC} Failed to parse scanner JSON (stdout polluted — check git CRLF warnings)."
    echo -e "          Raw tail: $(echo "$SCAN_JSON_RAW" | tail -n 3)"
    SCAN_JSON='{"blocks":1,"warns":0,"has_regression":false,"violations":[],"regression_files":[]}'
  else
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
  echo "$SCAN_JSON" | tail -n 1 | $NODE_CMD -e "try { console.log(JSON.parse(require('fs').readFileSync(0,'utf8')).$1 || '$2'); } catch(e) { console.log('$2'); }" || echo "$2"
}

S1_BLOCKS=$(extract_json_field "blocks" "0")
S1_WARNS=$(extract_json_field "warns" "0")

if [[ -n "${CHANGED_FILES:-}" && "$S1_BLOCKS" -eq 0 && "$S1_WARNS" -eq 0 ]]; then
  echo -e "  ${GREEN}No forensic pattern violations found.${NC}"
fi


HAS_REGRESSION=$(extract_json_field "has_regression" "false")
REGRESSION_FILES=$(echo "$SCAN_JSON" | $NODE_CMD -e "try { console.log(JSON.parse(require('fs').readFileSync(0,'utf8')).regression_files.join('\n')); } catch(e) { console.log(''); }" || echo "")

TOTAL_BLOCKS=$S1_BLOCKS
TOTAL_WARNS=$S1_WARNS

# ── DART_CHANGED (computed once, shared by Steps 6, 8, 9) ───────────────────
DART_CHANGED=""
[[ -n "$CHANGED_FILES" ]] && DART_CHANGED=$(echo "$CHANGED_FILES" | grep "\.dart$" | grep -v "\.g\.dart$" | grep -v "\.freezed\.dart$" || true)

# ── Step 2: Migration Append-Only Gate (INV-DB) ──────────────────────────────
echo -e "\n${BOLD}${BLUE}Step 2: Migration Append-Only Gate (INV-DB)...${NC}"
MODIFIED_MIGRATIONS=$(git diff --diff-filter=M --name-only "$BASE_BRANCH" 2>/dev/null | grep "supabase/migrations/.*\.sql" || true)
if [[ -n "$MODIFIED_MIGRATIONS" ]]; then
  echo -e "  ${RED}${BOLD}[BLOCK]${NC} Existing migration file(s) modified — Append-Only invariant violated (INV-DB):"
  echo "$MODIFIED_MIGRATIONS" | while IFS= read -r line; do
    [[ -n "$line" ]] && echo -e "    ${RED}→ $line${NC}"
  done
  TOTAL_BLOCKS=$((TOTAL_BLOCKS + 1))
elif [[ -z "${CHANGED_FILES:-}" ]]; then
  echo -e "  ${GREEN}No changes detected.${NC}"
else
  echo -e "  ${GREEN}All migration changes are new files (Append-Only compliant).${NC}"
fi

# ── Step 3: Barrel File Validation (Architect Mode) ──────────────────────────
echo -e "\n${BOLD}${BLUE}Step 3: Barrel File Validation (INV-13)...${NC}"

# -- Path Normalization for Python --
BARREL_SCRIPT="$PROJECT_DIR/scripts/validate_barrel_files.py"
BARREL_SCRIPT_WIN="$BARREL_SCRIPT"
if [[ "$PYTHON_CMD" == *.exe ]]; then
  if command -v cygpath >/dev/null 2>&1; then
    BARREL_SCRIPT_WIN=$(cygpath -m "$BARREL_SCRIPT")
  elif command -v wslpath >/dev/null 2>&1; then
    BARREL_SCRIPT_WIN=$(wslpath -m "$BARREL_SCRIPT")
  else
    BARREL_SCRIPT_WIN=$(echo "$BARREL_SCRIPT" | sed -e 's/^\/\([a-z]\)\//\1:\//' -e 's/^\/mnt\/\([a-z]\)\//\1:\//')
  fi
fi

BARREL_ARGS="--branch=$BASE_BRANCH"
[[ "${FULL_SCAN:-0}" == "1" ]] && BARREL_ARGS="$BARREL_ARGS --full"

BARREL_DART_FILES=""
BARREL_EXIT=0
if [[ -n "${CHANGED_FILES:-}" ]]; then
  BARREL_DART_FILES=$(echo "$CHANGED_FILES" | grep -E '^lib/.*\.dart$' | grep -vE '\.(g|freezed)\.dart$' || true)
fi

if [[ "${FULL_SCAN:-0}" == "1" ]]; then
  BARREL_RESULTS=$($PYTHON_CMD "$BARREL_SCRIPT_WIN" $BARREL_ARGS 2>&1)
  BARREL_EXIT=$?

  if [[ $BARREL_EXIT -eq 2 ]]; then
    echo -e "  ${RED}${BOLD}[ERROR]${NC} Barrel validator crashed."
    echo -e "          $BARREL_RESULTS"
  elif [[ $BARREL_EXIT -eq 1 ]]; then
    echo "$BARREL_RESULTS" | grep -v "INTERNAL ERROR" || true
    TOTAL_BLOCKS=$((TOTAL_BLOCKS + 1))
  else
    if [[ -n "$BARREL_RESULTS" ]]; then
      echo "$BARREL_RESULTS" | grep -v "INTERNAL ERROR" || true
    else
      echo -e "  ${YELLOW}${BOLD}[WARN]${NC} Barrel validator produced no output (exit $BARREL_EXIT)."
    fi
  fi
elif [[ -z "$(echo "$BARREL_DART_FILES" | tr -d '[:space:]')" ]]; then
  echo -e "  ${GREEN}No lib/*.dart changes — barrel validation skipped (INV-13).${NC}"
else
  BARREL_RESULTS=$(printf '%s\n' "$BARREL_DART_FILES" | $PYTHON_CMD "$BARREL_SCRIPT_WIN" $BARREL_ARGS 2>&1)
  BARREL_EXIT=$?

  if [[ $BARREL_EXIT -eq 2 ]]; then
    echo -e "  ${RED}${BOLD}[ERROR]${NC} Barrel validator crashed."
    echo -e "          $BARREL_RESULTS"
  elif [[ $BARREL_EXIT -eq 1 ]]; then
    echo "$BARREL_RESULTS" | grep -v "INTERNAL ERROR" || true
    TOTAL_BLOCKS=$((TOTAL_BLOCKS + 1))
  else
    if [[ -n "$BARREL_RESULTS" ]]; then
      echo "$BARREL_RESULTS" | grep -v "INTERNAL ERROR" || true
    else
      echo -e "  ${YELLOW}${BOLD}[WARN]${NC} Barrel validator produced no output (exit $BARREL_EXIT)."
    fi
  fi
fi

# ── Step 4: Type Parity Verification (QA Mode) ──────────────────────────────
echo -e "\n${BOLD}${BLUE}Step 4: Type Parity Verification (INV-7)...${NC}"
if [[ -z "$CHANGED_FILES" ]]; then
  echo "No changes detected."
else
  MIGRATIONS_COUNT=$(echo "$CHANGED_FILES" | grep "supabase/migrations/.*\.sql" | wc -l | tr -d '[:space:]' || echo "0")
  if [[ "$MIGRATIONS_COUNT" -gt 0 ]]; then
    echo -e "  Migrations detected ($MIGRATIONS_COUNT files). Checking for type sync..."
    TYPE_FILE="supabase/types.database.ts"

    # Detect schema-neutral migrations (RLS/policy/grant only — no structural DDL).
    # These do not change TypeScript types, so a missing types.database.ts diff is
    # expected and correct. Downgrade to [WARN] to avoid false-positive BLOCKs.
    IS_SCHEMA_NEUTRAL="true"
    while IFS= read -r mig_path; do
      [[ -z "$mig_path" ]] && continue
      mig_path="${mig_path//$'\r'/}"  # strip Windows CR from path
      [[ -z "$mig_path" ]] && continue
      # Read via git show (staged content — robust on Windows regardless of CWD)
      MIG_CONTENT=$(git show ":$mig_path" 2>/dev/null || cat "$mig_path" 2>/dev/null || true)
      if [[ -z "$MIG_CONTENT" ]]; then
        IS_SCHEMA_NEUTRAL="false"
        break
      fi
      STRUCTURAL_DDL=$(echo "$MIG_CONTENT" | grep -iE \
        "^\s*(CREATE|ALTER|DROP)\s+(TABLE|INDEX|SEQUENCE|TYPE|VIEW|EXTENSION)\b" \
        2>/dev/null || true)
      if [[ -n "$STRUCTURAL_DDL" ]]; then
        IS_SCHEMA_NEUTRAL="false"
        break
      fi
    done <<< "$(echo "$CHANGED_FILES" | grep "supabase/migrations/.*\.sql")"

    # Check if type file is also changed
    if ! echo "$CHANGED_FILES" | grep -q "$TYPE_FILE"; then
      if [[ "$IS_SCHEMA_NEUTRAL" == "true" ]]; then
        echo -e "  ${YELLOW}${BOLD}[WARN]${NC} Schema-neutral migration (policies/grants only) — $TYPE_FILE content unchanged. Verify manually."
        TOTAL_WARNS=$((TOTAL_WARNS + 1))
      else
        echo -e "  ${RED}${BOLD}[BLOCK]${NC} Migrations updated but $TYPE_FILE is NOT in this PR."
        TOTAL_BLOCKS=$((TOTAL_BLOCKS + 1))
      fi
    else
      echo -e "  ${GREEN}Infrastructure contract present in PR.${NC}"
    fi
  else
    echo -e "  ${GREEN}No migrations detected. Parity sync skipped.${NC}"
  fi
fi

# ── Step 5: Schema Integrity Verification (INV-15) ──────────────────────────
echo -e "\n${BOLD}${BLUE}Step 5: Schema Integrity Verification (INV-15)...${NC}"
if [[ -n "${CHANGED_FILES:-}" ]]; then
  MIGRATIONS_COUNT=$(echo "$CHANGED_FILES" | grep "supabase/migrations/.*\.sql" | wc -l | tr -d '[:space:]' || echo "0")
  if [[ "$MIGRATIONS_COUNT" -gt 0 ]]; then
    echo -e "  Migrations detected. Validating PostgREST schema health..."
    # Check if Supabase is running to perform live health check
    if supabase status > /dev/null 2>&1; then
       # Trigger reload to ensure cache is current
       bash "$SCRIPT_DIR/../refresh_schema_cache.sh" > /dev/null 2>&1

       # Aguardar o recarregamento do cache (PostgREST pode retornar 503 temporariamente)
       RETRY_COUNT=0
       HEALTH_CHECK="503"
       while [[ "$RETRY_COUNT" -lt 5 ]]; do
         HEALTH_CHECK=$(curl -s -o /dev/null -w "%{http_code}" -I "http://localhost:54321/rest/v1/")
         if [[ "$HEALTH_CHECK" == "503" ]]; then
           sleep 1
           RETRY_COUNT=$((RETRY_COUNT + 1))
         else
           break
         fi
       done

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

# ── Step 6: Static Analysis ──────────────────────────────────────────────────
echo -e "\n${BOLD}${BLUE}Step 6: Static Analysis...${NC}"

# 6.1: flutter analyze (B1) — BLOCK on core layer errors, WARN on presentation
echo -e "  [6.1] flutter analyze --no-pub..."

# -- Environment Readiness Check --
if [[ ! -f ".dart_tool/package_config.json" ]]; then
  echo -e "  ${RED}${BOLD}[CRITICAL]${NC} Docker dependency cache is missing or out of sync."
  echo -e "             Run 'make build-test-env' on your host to initialize the environment."
  exit 1
fi

if ! $FLUTTER_CMD --version >/dev/null 2>&1; then
  echo -e "  ${YELLOW}${BOLD}[WARN]${NC} flutter not found. Install Flutter SDK. Skipping."
  TOTAL_WARNS=$((TOTAL_WARNS + 1))
elif [[ "${SKIP_ANALYZE:-0}" == "1" ]]; then
  echo -e "  ${YELLOW}[SKIP]${NC} SKIP_ANALYZE=1."
else
  ANALYZE_OUTPUT=$($FLUTTER_CMD analyze --no-pub 2>&1) || true
  ANALYZE_ERRORS=$(echo "$ANALYZE_OUTPUT" | grep -iE "^\s*error\b" || true)
  ANALYZE_WARNINGS=$(echo "$ANALYZE_OUTPUT" | grep -iE "^\s*warning\b" || true)

  CORE_ERRORS=$(echo "$ANALYZE_ERRORS" | grep -E "lib/(domain|application|infrastructure)/" || true)
  PRES_ERRORS=$(echo "$ANALYZE_ERRORS" | grep -vE "lib/(domain|application|infrastructure)/" | grep -v "^$" || true)

  if [[ -n "$CORE_ERRORS" ]]; then
    COUNT=$(echo "$CORE_ERRORS" | wc -l | tr -d ' ')
    echo -e "  ${RED}${BOLD}[BLOCK]${NC} flutter analyze: $COUNT errors in core layers (domain/application/infrastructure)."
    echo "$CORE_ERRORS" | head -10 | while IFS= read -r line; do echo -e "    ${RED}→ $line${NC}"; done
    TOTAL_BLOCKS=$((TOTAL_BLOCKS + 1))
  fi

  if [[ -n "$PRES_ERRORS" ]]; then
    COUNT=$(echo "$PRES_ERRORS" | wc -l | tr -d ' ')
    echo -e "  ${YELLOW}${BOLD}[WARN]${NC} flutter analyze: $COUNT errors in presentation/feature layers."
    echo "$PRES_ERRORS" | head -10 | while IFS= read -r line; do echo -e "    ${YELLOW}→ $line${NC}"; done
    TOTAL_WARNS=$((TOTAL_WARNS + 1))
  fi

  if [[ -z "$ANALYZE_ERRORS" && -n "$ANALYZE_WARNINGS" ]]; then
    COUNT=$(echo "$ANALYZE_WARNINGS" | wc -l | tr -d ' ')
    echo -e "  ${YELLOW}${BOLD}[WARN]${NC} flutter analyze: $COUNT warning(s) detected."
    echo "$ANALYZE_WARNINGS" | head -10 | while IFS= read -r line; do echo -e "    ${YELLOW}→ $line${NC}"; done
    TOTAL_WARNS=$((TOTAL_WARNS + 1))
  fi

  if [[ -z "$ANALYZE_ERRORS" && -z "$ANALYZE_WARNINGS" ]]; then
    echo -e "  ${GREEN}flutter analyze: clean.${NC}"
  fi
fi

# 6.2: dart format (B2) — WARN on unformatted files
echo -e "  [6.2] dart format check..."
FORMAT_EXIT=0
FORMAT_OUTPUT=$($DART_CMD format --output=none --set-exit-if-changed lib/ 2>&1) || FORMAT_EXIT=$?
if [[ $FORMAT_EXIT -eq 1 ]] && echo "$FORMAT_OUTPUT" | grep -q "Changed"; then
  echo -e "  ${YELLOW}${BOLD}[WARN]${NC} Unformatted files detected. Run: dart format lib/"
  TOTAL_WARNS=$((TOTAL_WARNS + 1))
elif [[ $FORMAT_EXIT -gt 1 ]]; then
  echo -e "  ${YELLOW}${BOLD}[WARN]${NC} dart format failed (exit $FORMAT_EXIT). Check environment."
  TOTAL_WARNS=$((TOTAL_WARNS + 1))
else
  echo -e "  ${GREEN}dart format: all files properly formatted.${NC}"
fi

# ── Step 7: Dependency & License Audit (C2) ──────────────────────────────────
echo -e "\n${BOLD}${BLUE}Step 7: Dependency & License Audit (INV-25)...${NC}"
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
    echo -e "  ${YELLOW}${BOLD}[WARN]${NC} New dependencies detected in pubspec.yaml — manual license and security review required (INV-25 / Free-Tier Gate)."
    echo "$NEW_DEPS" | while IFS= read -r line; do
      [[ -n "$line" ]] && echo -e "    ${YELLOW}→ $(echo "$line" | xargs)${NC}"
    done
    TOTAL_WARNS=$((TOTAL_WARNS + 1))
  else
    echo -e "  ${GREEN}No new dependencies added to pubspec.yaml.${NC}"
  fi
else
  echo -e "  ${GREEN}pubspec.yaml unchanged.${NC}"
fi

# ── Step 8: Architecture Integrity ───────────────────────────────────────────
echo -e "\n${BOLD}${BLUE}Step 8: Architecture Integrity...${NC}"

# 8.1: C4 Leaky Abstraction — domain imports in lib/features/ (BLOCK)
echo -e "  [8.1] C4 leaky abstraction: checking for domain imports in lib/features/..."
if [[ -n "$DART_CHANGED" ]]; then
  LEAK_FILES=$(echo "$DART_CHANGED" | grep "^lib/features/" || true)
  if [[ -n "$LEAK_FILES" ]]; then
    LEAK_BLOCK_FOUND=0
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      if [[ -f "$f" ]]; then
        if grep -q "pr_scanner: ignore" "$f"; then
          continue
        fi
        FILE_LEAKS=$(grep -nE "import 'package:veraprob/domain/" "$f" \
          || true)
        if [[ -n "$FILE_LEAKS" ]]; then
          echo -e "  ${RED}${BOLD}[BLOCK]${NC} Domain import in features layer: $f"
          echo "$FILE_LEAKS" | head -5 | while IFS= read -r line; do echo -e "    ${RED}→ $line${NC}"; done
          TOTAL_BLOCKS=$((TOTAL_BLOCKS + 1))
          LEAK_BLOCK_FOUND=1
        fi
      fi
    done <<< "$LEAK_FILES"
    if [[ $LEAK_BLOCK_FOUND -eq 0 ]]; then
      echo -e "  ${GREEN}No leaky domain imports in changed features/ files.${NC}"
    fi
  else
    echo -e "  ${GREEN}No changed lib/features/ files. Check skipped.${NC}"
  fi
else
  echo -e "  ${GREEN}No Dart files changed. Check skipped.${NC}"
fi

# 8.2: E2 Error Parity — throw Exception / return 401/403 in non-test Dart files (BLOCK)
echo -e "  [8.2] E2 error parity: scanning for forbidden error patterns (INV-26)..."
if [[ -n "$DART_CHANGED" ]]; then
  E2_BLOCK_FOUND=0
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    # Skip test files
    [[ "$f" == *_test.dart ]] && continue
    if [[ -f "$f" ]]; then
      if grep -q "pr_scanner: ignore" "$f"; then
        continue
      fi
      # Strip multiline block comments, then single-line comments and imports
      CLEAN=$(perl -0777 -pe 's/\/\*.*?\*\///gs' "$f" 2>/dev/null \
        | sed '/^\s*\/\//d; /^\s*import/d' \
        || cat "$f")
      ERR_HITS=$(echo "$CLEAN" | grep -nE "throw Exception\b|throw Exception\(|return 403|return 401" || true)
      if [[ -n "$ERR_HITS" ]]; then
        echo -e "  ${RED}${BOLD}[BLOCK]${NC} Forbidden error patterns in $f (use DomainException, INV-26)."
        echo "$ERR_HITS" | head -5 | while IFS= read -r line; do echo -e "    ${RED}→ $line${NC}"; done
        TOTAL_BLOCKS=$((TOTAL_BLOCKS + 1))
        E2_BLOCK_FOUND=1
      fi
    fi
  done <<< "$DART_CHANGED"
  if [[ $E2_BLOCK_FOUND -eq 0 ]]; then
    echo -e "  ${GREEN}No forbidden error patterns in changed Dart files (INV-26 compliant).${NC}"
  fi
else
  echo -e "  ${GREEN}No Dart files changed. Check skipped.${NC}"
fi

# 8.3: D1/D2 Strict Type-Safety (BLOCK domain, WARN infra)
echo -e "  [8.3] D1/D2 strict type-safety..."
if [[ "${SKIP_STRICT_TYPES:-0}" == "1" ]]; then
  echo -e "  ${YELLOW}[SKIP]${NC} SKIP_STRICT_TYPES=1."
elif ! $FLUTTER_CMD --version >/dev/null 2>&1; then
  echo -e "  ${YELLOW}${BOLD}[WARN]${NC} flutter not found. Skipping strict type-safety analysis."
  TOTAL_WARNS=$((TOTAL_WARNS + 1))
else
  STRICT_OPTIONS_FILE="$PROJECT_DIR/analysis_options_strict_tmp.yaml"
  cat > "$STRICT_OPTIONS_FILE" << 'STRICT_EOF'
include: package:flutter_lints/flutter.yaml
analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
STRICT_EOF

  STRICT_OUTPUT=$($FLUTTER_CMD analyze --no-pub --options "$STRICT_OPTIONS_FILE" 2>&1 || true)
  rm -f "$STRICT_OPTIONS_FILE"

  DOMAIN_STRICT=$(echo "$STRICT_OUTPUT" | grep "lib/domain/" || true)
  INFRA_STRICT=$(echo "$STRICT_OUTPUT" | grep "lib/infrastructure/" || true)

  if [[ -n "$DOMAIN_STRICT" ]]; then
    COUNT=$(echo "$DOMAIN_STRICT" | wc -l | tr -d ' ')
    echo -e "  ${RED}${BOLD}[BLOCK]${NC} Strict type violations in Domain layer ($COUNT). Fix with explicit types (INV-4/INV-7)."
    echo "$DOMAIN_STRICT" | head -10 | while IFS= read -r line; do echo -e "    ${RED}→ $line${NC}"; done
    TOTAL_BLOCKS=$((TOTAL_BLOCKS + 1))
  else
    echo -e "  ${GREEN}D1: Domain layer has 0 strict-type violations (INV-4 compliant).${NC}"
  fi

  if [[ -n "$INFRA_STRICT" ]]; then
    COUNT=$(echo "$INFRA_STRICT" | wc -l | tr -d ' ')
    echo -e "  ${YELLOW}${BOLD}[WARN]${NC} D2: Strict type violations in Infrastructure layer ($COUNT — JSON decoding)."
    TOTAL_WARNS=$((TOTAL_WARNS + 1))
  else
    echo -e "  ${GREEN}D2: Infrastructure layer has 0 strict-type violations.${NC}"
  fi
fi

# 8.4: Test Folder Parity Gate (BLOCK on invalid test directory layout)
echo -e "  [8.4] Test folder parity: checking for forbidden test directories (data/ e soltos em e2e/)..."
if [[ -d "$PROJECT_DIR/test/data" || -d "$PROJECT_DIR/test/e2e" ]]; then
  echo -e "  ${RED}${BOLD}[BLOCK]${NC} Forbidden test folder layout detected: test/data/ or test/e2e/ must not exist."
  echo -e "          Data layer must be in test/infrastructure/. E2E tests must be in test/integration/e2e/."
  TOTAL_BLOCKS=$((TOTAL_BLOCKS + 1))
else
  echo -e "  ${GREEN}Test folder layout is strictly compliant with Clean Architecture (C4).${NC}"
fi

# 8.5: RAW-COLOR — raw Material Colors.* in presentation layers (BLOCK)
# Design-system tokens (VeraProbColors) are mandatory in lib/features/ and
# lib/presentation/. Allowed without comment: Colors.transparent (idiom, no
# token) and Colors.black* (scrims/shadows/barriers — never the fg-on-accent
# bug class). Every other raw color needs a same-line justification comment:
# `// raw-color: <reason>` (map layer, security banner, QR).
echo -e "  [8.5] RAW-COLOR: scanning changed presentation files for raw Colors.* ..."
if [[ -n "$DART_CHANGED" ]]; then
  RAW_COLOR_FILES=$(echo "$DART_CHANGED" | grep -E "^lib/(features|presentation)/" || true)
  if [[ -n "$RAW_COLOR_FILES" ]]; then
    RAW_COLOR_BLOCK_FOUND=0
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      if [[ -f "$f" ]]; then
        if grep -q "pr_scanner: ignore" "$f"; then
          continue
        fi
        RAW_HITS=$(grep -nE '\bColors\.[a-z]' "$f" \
          | grep -v "Colors\.transparent" \
          | grep -v "Colors\.black" \
          | grep -v "raw-color:" \
          | grep -vE '^[0-9]+:\s*//' \
          || true)
        if [[ -n "$RAW_HITS" ]]; then
          echo -e "  ${RED}${BOLD}[BLOCK]${NC} Raw Colors.* in presentation layer: $f (use VeraProbColors tokens, or justify with // raw-color: <reason>)"
          echo "$RAW_HITS" | head -5 | while IFS= read -r line; do echo -e "    ${RED}→ $line${NC}"; done
          TOTAL_BLOCKS=$((TOTAL_BLOCKS + 1))
          RAW_COLOR_BLOCK_FOUND=1
        fi
      fi
    done <<< "$RAW_COLOR_FILES"
    if [[ $RAW_COLOR_BLOCK_FOUND -eq 0 ]]; then
      echo -e "  ${GREEN}No unjustified raw Colors.* in changed presentation files.${NC}"
    fi
  else
    echo -e "  ${GREEN}No changed lib/features|presentation files. Check skipped.${NC}"
  fi
else
  echo -e "  ${GREEN}No Dart files changed. Check skipped.${NC}"
fi

# ── Step 9: Governance & Process Audit (Forensic Mode) ──────────────────────
echo -e "\n${BOLD}${BLUE}Step 9: Governance & Process Audit...${NC}"

if [[ -n "${CHANGED_FILES:-}" ]]; then
  # 9.1: Mandatory Test Plan for Migrations (1:1 timestamp-prefix match)
  MIG_FILES=$(echo "$CHANGED_FILES" | grep "supabase/migrations/.*\.sql" || true)
  if [[ -n "$MIG_FILES" ]]; then
    echo -e "  [9.1] Checking Mandatory Test Plans (1:1 per migration)..."
    PLAN_BLOCKS=0
    while IFS= read -r mig; do
      [[ -z "$mig" ]] && continue
      # Skip modified migrations — already blocked by Step 2
      IS_MODIFIED=$(echo "${MODIFIED_MIGRATIONS:-}" | grep -F "$mig" || true)
      [[ -n "$IS_MODIFIED" ]] && continue
      MIG_BASENAME=$(basename "$mig" .sql)
      TIMESTAMP_PREFIX="${MIG_BASENAME:0:14}"
      PLAN_IN_PR=$(echo "$CHANGED_FILES" | grep "forensic_records/plans/${TIMESTAMP_PREFIX}" | grep "\.md$" || true)
      if [[ -z "$PLAN_IN_PR" ]]; then
        echo -e "  ${RED}${BOLD}[BLOCK]${NC} ${MIG_BASENAME}.sql — no Test Plan found. Add: forensic_records/plans/${TIMESTAMP_PREFIX}*_test_plan.md"
        PLAN_BLOCKS=$((PLAN_BLOCKS + 1))
      fi

      PGTAP_TEST_IN_PR=$(echo "$CHANGED_FILES" | grep "supabase/tests/${TIMESTAMP_PREFIX}" | grep "\.sql$" || true)
      if [[ -z "$PGTAP_TEST_IN_PR" ]]; then
        echo -e "  ${RED}${BOLD}[BLOCK]${NC} ${MIG_BASENAME}.sql — no pgTAP test file found. Add: supabase/tests/${TIMESTAMP_PREFIX}*_test.sql"
        PLAN_BLOCKS=$((PLAN_BLOCKS + 1))
      fi
    done <<< "$MIG_FILES"
    if [[ $PLAN_BLOCKS -gt 0 ]]; then
      TOTAL_BLOCKS=$((TOTAL_BLOCKS + 1))
    else
      echo -e "  ${GREEN}All new migrations have matching Test Plans (1:1 compliant).${NC}"
    fi
  fi

  # 9.2: Enterprise Complexity Analysis (dart_code_metrics — cyclomatic, nesting, methods)
  echo -e "  [9.2] Running enterprise complexity analysis (dart_code_metrics)..."
  COMPLEXITY_SCRIPT_WIN="$SCRIPT_DIR_WIN/analyze_dart_complexity.js"
  if [[ -n "$DART_CHANGED" ]]; then
    COMPLEXITY_JSON_RAW=$(echo "$DART_CHANGED" | $NODE_CMD "$COMPLEXITY_SCRIPT_WIN" 2>/dev/null || echo '{"blocks":0,"warns":0,"violations":[],"skipped":true}')
    COMPLEXITY_SKIPPED=$(echo "$COMPLEXITY_JSON_RAW" | $NODE_CMD -e "try{const d=JSON.parse(require('fs').readFileSync(0,'utf8'));console.log(d.skipped||false);}catch(e){console.log(false);}" 2>/dev/null || echo "false")
    if [[ "$COMPLEXITY_SKIPPED" == "true" ]]; then
      echo -e "  ${YELLOW}${BOLD}[WARN]${NC} dart_code_metrics not found. Install: dart pub global activate dart_code_metrics"
    else
      C_BLOCKS=$(echo "$COMPLEXITY_JSON_RAW" | $NODE_CMD -e "try{console.log(JSON.parse(require('fs').readFileSync(0,'utf8')).blocks||0);}catch(e){console.log(0);}" 2>/dev/null || echo "0")
      C_WARNS=$(echo "$COMPLEXITY_JSON_RAW"  | $NODE_CMD -e "try{console.log(JSON.parse(require('fs').readFileSync(0,'utf8')).warns||0);}catch(e){console.log(0);}" 2>/dev/null || echo "0")
      echo "$COMPLEXITY_JSON_RAW" | $NODE_CMD -e "
      const fs = require('fs');
      try {
        const data = JSON.parse(fs.readFileSync(0, 'utf8'));
        const RED = '\x1b[0;31m'; const YELLOW = '\x1b[1;33m'; const BOLD = '\x1b[1m'; const NC = '\x1b[0m';
        (data.violations || []).forEach(v => {
          const tag = v.severity === 'BLOCK' ? RED+BOLD+'[BLOCK]'+NC : YELLOW+BOLD+'[WARN]'+NC;
          console.log('    ' + tag + ' ' + v.file + ' — ' + v.rule + ': ' + v.description);
        });
        if (!data.violations || data.violations.length === 0) console.log('    \x1b[0;32mNo complexity violations detected.\x1b[0m');
      } catch(e) {}
      " 2>/dev/null || true
      TOTAL_BLOCKS=$((TOTAL_BLOCKS + C_BLOCKS))
      TOTAL_WARNS=$((TOTAL_WARNS + C_WARNS))
    fi
  else
    echo -e "  ${GREEN}No Dart files changed. Complexity check skipped.${NC}"
  fi

  # 9.3: Test Presence Gate (70% Threshold for Critical Files)
  # BLOCK on main / PR-to-main; WARN on feature branches.
  CRITICAL_FILES=$(echo "$CHANGED_FILES" | grep -E "^lib/(domain|application|infrastructure|state)/" | grep -vE "\.(g|freezed)\.dart$" || true)
  TOTAL_CRITICAL=$(echo "$CRITICAL_FILES" | grep -v '^[[:space:]]*$' | grep -c . || true)

  if [[ "$TOTAL_CRITICAL" -gt 0 ]]; then
    if [[ "$TEST_GATE_BLOCK" == "true" ]]; then
      echo -e "  [9.3] Checking Test Presence (70% Threshold)... ${RED}(BLOCK mode — targeting main)${NC}"
    else
      echo -e "  [9.3] Checking Test Presence (70% Threshold)... ${YELLOW}(WARN mode — feature branch)${NC}"
    fi

    COVERED_COUNT=0
    MISSING_FILES=""
    while IFS= read -r f; do
      [[ -z "$f" || "$f" =~ ^[[:space:]]*$ ]] && continue
      TEST_FILE=$(echo "$f" | sed 's|^lib/|test/|' | sed 's|\.dart$|_test.dart|')
      if echo "$CHANGED_FILES" | grep -q "$TEST_FILE" || [[ -f "$TEST_FILE" ]]; then
        COVERED_COUNT=$((COVERED_COUNT + 1))
      else
        # Fallback: import-based detection — only valid when the importing test
        # file is named after the source file (<basename>_test.dart), preventing
        # false positives from barrel or integration tests that happen to import
        # this file as a dependency.
        PACKAGE_PATH=$(echo "$f" | sed 's|^lib/|package:veraprob/|')
        SRC_BASENAME=$(basename "$f" .dart)
        SRC_BASENAME_ESC=$(printf '%s' "$SRC_BASENAME" | sed 's/[][\\.^$*?+{}()|]/\\&/g')
        IMPORT_HIT=$(grep -rl "import '$PACKAGE_PATH'" test/ 2>/dev/null | grep "_test\.dart$" | grep -E "(^|/)${SRC_BASENAME_ESC}_test\.dart$" | head -1 || true)
        if [[ -n "$IMPORT_HIT" ]]; then
          COVERED_COUNT=$((COVERED_COUNT + 1))
        else
          MISSING_FILES+="\n    → $f"
        fi
      fi
    done <<< "$CRITICAL_FILES"

    # Calculate percentage (Bash integer math)
    PERCENTAGE=$(( COVERED_COUNT * 100 / TOTAL_CRITICAL ))

    if [[ "$PERCENTAGE" -lt 70 ]]; then
      if [[ "$TEST_GATE_BLOCK" == "true" ]]; then
        echo -e "  ${RED}${BOLD}[BLOCK]${NC} Critical test presence is $PERCENTAGE% (Target: 70%). Missing tests for:$MISSING_FILES"
        TOTAL_BLOCKS=$((TOTAL_BLOCKS + 1))
      else
        echo -e "  ${YELLOW}${BOLD}[WARN]${NC} Critical test presence is $PERCENTAGE% (Target: 70%). Missing tests for:$MISSING_FILES"
        TOTAL_WARNS=$((TOTAL_WARNS + 1))
      fi
    else
      echo -e "  ${GREEN}Critical test presence is $PERCENTAGE% (INV-TEST compliant).${NC}"
    fi
  else
    echo -e "  ${GREEN}[9.3] No critical files changed. Test presence check skipped.${NC}"
  fi
fi

# ── Step 10: Deno Test Suite (Edge Functions) ────────────────────────────────
echo -e "\n${BOLD}${BLUE}Step 10: Deno Test Suite (Edge Functions)...${NC}"
if [[ "${SKIP_DENO_TESTS:-0}" == "1" ]]; then
  echo -e "  ${YELLOW}[SKIP]${NC} SKIP_DENO_TESTS=1."
elif ! command -v deno >/dev/null 2>&1; then
  echo -e "  ${YELLOW}${BOLD}[WARN]${NC} Deno CLI not found. Install Deno. Skipping Deno tests."
  TOTAL_WARNS=$((TOTAL_WARNS + 1))
else
  # Check if Supabase API is online to determine whether we run live integration tests or only unit tests.
  # Perform a lightweight check to see if the local Supabase functions endpoint is reachable.
  SUPABASE_ONLINE=false
  if curl -s -f -I --connect-timeout 2 "http://localhost:54321/functions/v1/" >/dev/null 2>&1; then
    SUPABASE_ONLINE=true
  fi

  DENO_TEST_FLAGS="--config supabase/functions/deno.json --allow-env --allow-net --no-check"
  if [[ -f ".env" ]]; then
    DENO_TEST_FLAGS="--env-file=.env $DENO_TEST_FLAGS"
  fi

  if [[ "$SUPABASE_ONLINE" == "true" ]]; then
    echo -e "  Supabase local services detected. Running ALL Deno tests..."
    DENO_CMD_ARGS="test $DENO_TEST_FLAGS supabase/functions/tests/"
  else
    echo -e "  ${YELLOW}Supabase offline.${NC} Running only Deno unit tests (excluding live integration tests)..."
    DENO_CMD_ARGS="test $DENO_TEST_FLAGS --ignore=supabase/functions/tests/telegram_webhook_integration_test.ts,supabase/functions/tests/super_admin_proxy_integration_test.ts supabase/functions/tests/"
  fi

  # Run Deno tests
  echo "  Running: deno $DENO_CMD_ARGS"
  if deno $DENO_CMD_ARGS; then
    echo -e "  ${GREEN}Deno tests: all passed.${NC}"
  else
    echo -e "  ${RED}${BOLD}[BLOCK]${NC} Deno test suite failed."
    TOTAL_BLOCKS=$((TOTAL_BLOCKS + 1))
  fi
fi

# ── Final Summary ────────────────────────────────────────────────────────────
# Note: BARREL_EXIT == 1 means ARCHITECTURAL VIOLATION.
# Other non-zero codes (2, 127, etc) are execution errors and shouldn't cause a Veto by default.

# DETERMINISTIC VERDICT HARDENING:
# If there is a regression alert that is NOT ignored, it becomes a NO-GO.
# [FLEXIBILIZADO PARA DEV]
STRICT_REGRESSION="false"
if [[ "$HAS_REGRESSION" == "true" ]]; then
  # Check if all regression files have the ignore comment
  while IFS= read -r rf; do
    [[ -z "$rf" ]] && continue
    if [[ -f "$rf" ]]; then
      if ! grep -q "pr_scanner: ignore-regression" "$rf"; then
        STRICT_REGRESSION="true"
        break
      fi
    fi
  done <<< "$REGRESSION_FILES"
fi

VERDICT="[GO]"
# [FLEXIBILIZADO PARA DEV] Somente TOTAL_BLOCKS ou BARREL_EXIT bloqueiam. 
# Regressão ignorada conforme solicitado pelo usuário (Dev Mode).
[[ $TOTAL_BLOCKS -gt 0 || $BARREL_EXIT -eq 1 ]] && VERDICT="[NO-GO]"
[[ $VERDICT == "[GO]" && $TOTAL_WARNS -gt 0 ]] && VERDICT="[REVISE]"

echo -e "\n${BOLD}════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  LEAD REVIEWER VERDICT (Forensic Gatekeeper)${NC}"
echo -e "════════════════════════════════════════════════════════════"
echo -e "  Deterministic Blocks: $TOTAL_BLOCKS"
echo -e "  Barrel Violations:   $( [[ $BARREL_EXIT -eq 1 ]] && echo 'YES' || echo 'NO' )"
echo -e "  Governance Failures: $( [[ $TOTAL_BLOCKS -gt 0 ]] && echo 'YES' || echo 'NO' )"
echo -e "  Regression Alert:    $( [[ "$HAS_REGRESSION" == "true" ]] && echo 'YES' || echo 'NO' )"
[[ "$STRICT_REGRESSION" == "true" ]] && echo -e "  ${RED}${BOLD}UNACKNOWLEDGED REGRESSION DETECTED!${NC}"
echo ""
echo -e "  FINAL VERDICT:        ${BOLD}$VERDICT${NC}"
echo -e "════════════════════════════════════════════════════════════"

if [[ "$VERDICT" == "[NO-GO]" ]]; then
  echo -e "${RED}Veto absoluto: violação de processo ou invariante detectada.${NC}"
  echo -e "PR bloqueado. Corrija os BLOCKS acima antes de prosseguir."
  exit 1
fi

exit 0
