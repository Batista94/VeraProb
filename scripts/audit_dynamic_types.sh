#!/usr/bin/env bash
# =============================================================================
# Phase 8.5 — Strict Type-Safety Audit
# =============================================================================
# Reports implicit dynamic-type violations by layer (domain / infra / presentation)
# WITHOUT modifying analysis_options.yaml or breaking CI.
#
# Usage (Linux/macOS/WSL):
#   bash scripts/audit_dynamic_types.sh
#
# Usage (Windows — requires Git Bash or WSL):
#   bash scripts/audit_dynamic_types.sh
#
# The script creates a TEMPORARY analysis_options_strict.yaml, runs
# `flutter analyze` against it, categorizes results by layer, and
# prints a summary. The temp file is cleaned up on exit.
#
# Activation roadmap (from architect ruling):
#   1. Run this script to baseline the violation count per layer
#   2. Fix Domain layer first (must be 0 — INV-4: Domain Sovereignty)
#   3. Fix Infrastructure layer (JSON casts — use `as Type` or jsonDecode helpers)
#   4. Fix Presentation layer
#   5. Enable strict flags globally in analysis_options.yaml once all layers are clean
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
STRICT_OPTIONS="$PROJECT_DIR/analysis_options_strict.yaml"
REPORT_FILE="$PROJECT_DIR/audit_strict_types_report.txt"

cleanup() {
  rm -f "$STRICT_OPTIONS"
}
trap cleanup EXIT

# ── 1. Write a temporary strict analysis_options ──────────────────────────────
cat > "$STRICT_OPTIONS" << 'EOF'
include: package:flutter_lints/flutter.yaml

analyzer:
  errors:
    missing_return: error
    dead_code: warning

  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true

linter:
  rules:
    avoid_print: true
    unawaited_futures: true
    prefer_const_constructors: true
    prefer_const_declarations: true
    use_super_parameters: true
    always_declare_return_types: true
    exhaustive_cases: true
EOF

# ── 2. Run analyze against the strict config ─────────────────────────────────
echo "Running flutter analyze with strict-casts/strict-inference/strict-raw-types..."
echo "(This may take a few seconds...)"
echo ""

cd "$PROJECT_DIR"

# Capture all output — don't fail on non-zero exit (violations are expected)
ANALYZE_OUTPUT=$(flutter analyze --no-pub \
  --options "$STRICT_OPTIONS" 2>&1 || true)

# ── 3. Categorize by layer ────────────────────────────────────────────────────
DOMAIN_HITS=$(echo "$ANALYZE_OUTPUT" | grep "lib/domain/" || true)
INFRA_HITS=$(echo "$ANALYZE_OUTPUT" | grep "lib/infrastructure/" || true)
PRES_HITS=$(echo "$ANALYZE_OUTPUT" | \
  grep -E "lib/features/|lib/state/|lib/core/" || true)
OTHER_HITS=$(echo "$ANALYZE_OUTPUT" | grep "lib/" | \
  grep -vE "lib/domain/|lib/infrastructure/|lib/features/|lib/state/|lib/core/" || true)

DOMAIN_COUNT=$(echo "$DOMAIN_HITS" | grep -c "^" 2>/dev/null || echo "0")
INFRA_COUNT=$(echo "$INFRA_HITS"   | grep -c "^" 2>/dev/null || echo "0")
PRES_COUNT=$(echo "$PRES_HITS"     | grep -c "^" 2>/dev/null || echo "0")
OTHER_COUNT=$(echo "$OTHER_HITS"   | grep -c "^" 2>/dev/null || echo "0")

# Suppress spurious "0" from empty grep
[[ -z "$DOMAIN_HITS" ]] && DOMAIN_COUNT=0
[[ -z "$INFRA_HITS"  ]] && INFRA_COUNT=0
[[ -z "$PRES_HITS"   ]] && PRES_COUNT=0
[[ -z "$OTHER_HITS"  ]] && OTHER_COUNT=0

TOTAL=$((DOMAIN_COUNT + INFRA_COUNT + PRES_COUNT + OTHER_COUNT))

# ── 4. Write report ───────────────────────────────────────────────────────────
{
  echo "============================================================"
  echo " PactaFlow — Phase 8.5 Strict Type-Safety Audit Report"
  echo " Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "============================================================"
  echo ""
  echo "SUMMARY"
  echo "-------"
  printf " %-20s %s\n" "Domain layer:"        "$DOMAIN_COUNT violations  (target: 0 — INV-4)"
  printf " %-20s %s\n" "Infrastructure:"      "$INFRA_COUNT violations"
  printf " %-20s %s\n" "Presentation/State:"  "$PRES_COUNT violations"
  printf " %-20s %s\n" "Other:"               "$OTHER_COUNT violations"
  echo "                     ──────────────────────"
  printf " %-20s %s\n" "TOTAL:"               "$TOTAL violations"
  echo ""

  if [[ $DOMAIN_COUNT -gt 0 ]]; then
    echo "⛔ DOMAIN LAYER VIOLATIONS (must be zero — INV-4: Domain Sovereignty)"
    echo "----------------------------------------------------------------------"
    echo "$DOMAIN_HITS"
    echo ""
  else
    echo "✅ Domain layer — 0 violations (INV-4 compliant)"
    echo ""
  fi

  if [[ $INFRA_COUNT -gt 0 ]]; then
    echo "🔄 INFRASTRUCTURE VIOLATIONS (JSON cast issues — fix iteratively)"
    echo "----------------------------------------------------------------------"
    echo "$INFRA_HITS"
    echo ""
  fi

  if [[ $PRES_COUNT -gt 0 ]]; then
    echo "🔄 PRESENTATION / STATE / CORE VIOLATIONS"
    echo "----------------------------------------------------------------------"
    echo "$PRES_HITS"
    echo ""
  fi

  if [[ $OTHER_COUNT -gt 0 ]]; then
    echo "🔄 OTHER VIOLATIONS"
    echo "----------------------------------------------------------------------"
    echo "$OTHER_HITS"
    echo ""
  fi

  echo "============================================================"
  echo " ACTIVATION ROADMAP"
  echo "============================================================"
  echo " 1. Fix all DOMAIN violations first (zero-tolerance per INV-4)"
  echo " 2. Fix INFRASTRUCTURE violations (JSON decoding layer)"
  echo "    Pattern: Replace implicit casts with explicit 'as Type'"
  echo "    Example: json['id'] → json['id'] as String"
  echo " 3. Fix PRESENTATION/STATE violations"
  echo " 4. Enable strict flags in analysis_options.yaml:"
  echo "    analyzer:"
  echo "      language:"
  echo "        strict-casts: true"
  echo "        strict-inference: true"
  echo "        strict-raw-types: true"
  echo "============================================================"
} | tee "$REPORT_FILE"

echo ""
echo "Report saved to: $REPORT_FILE"

# Exit non-zero if Domain layer has violations (CI gate for INV-4)
if [[ $DOMAIN_COUNT -gt 0 ]]; then
  echo ""
  echo "❌ FAIL: Domain layer has $DOMAIN_COUNT violations — INV-4 violated."
  exit 1
fi

echo ""
echo "✅ Domain layer clean. $TOTAL total violations remain in non-domain layers."
exit 0
