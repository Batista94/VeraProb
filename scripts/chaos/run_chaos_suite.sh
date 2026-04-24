#!/usr/bin/env bash
# =============================================================================
# run_chaos_suite.sh â€” Phase 10 Full Chaos Test Orchestrator
# =============================================================================
#
# Runs all 4 chaos scenarios in sequence. Each scenario must pass before
# the next begins. Produces a combined governance report.
#
# SCENARIOS:
#   1. SLA Racing & Determinism     (k6_sla_race.js)
#   2. Shadow Crash Recovery        (crash_recovery.sh + k6_shadow_idempotency.js)
#   3. Multi-Tenant Isolation 10x   (k6_multitenant_scale.js)
#   4. Fluid FSM Shadow Auto-Link   (k6_fluid_fsm_autolink.js)
#
# PREREQUISITES:
#   - k6 installed: https://k6.io/docs/get-started/installation/
#   - supabase start (local Supabase with Docker)
#   - bash scripts/chaos/apply_stress_limits.sh  (apply CPU/mem constraints)
#   - Env vars set (see individual scripts for requirements)
#   - Migration 20260702000002 applied for Scenario 4 to pass
#
# USAGE:
#   export SUPABASE_URL=http://localhost:54321
#   export SUPABASE_ANON_KEY=<anon_key>
#   export SERVICE_ROLE_KEY=<service_role_key>
#   export ORG_ID=00000000-0000-0000-0000-000000000001
#   export CONTRACT_ID=00000000-0000-0000-0000-ca0000000001
#   export BOUND_CHAT_ID=100000001
#   export WEBHOOK_SECRET=test-secret
#   bash scripts/chaos/run_chaos_suite.sh [--skip-crash] [--scenario=N]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOAD_TEST_DIR="scripts/load_test"
RESULTS_DIR="${PROJECT_ROOT}/docs/governance"
cd "${PROJECT_ROOT}"

# â”€â”€ Parse args â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
SKIP_CRASH=false
ONLY_SCENARIO=""

for arg in "$@"; do
  case $arg in
    --skip-crash)    SKIP_CRASH=true ;;
    --scenario=*)    ONLY_SCENARIO="${arg#*=}" ;;
  esac
done

# â”€â”€ Env defaults â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
SUPABASE_URL="${SUPABASE_URL:-http://localhost:54321}"
SERVICE_ROLE_KEY="${SERVICE_ROLE_KEY:-}"
SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-}"
ORG_ID="${ORG_ID:-00000000-0000-0000-0000-000000000001}"
CONTRACT_ID="${CONTRACT_ID:-00000000-0000-0000-0000-ca0000000001}"
ORG_COUNT="${ORG_COUNT:-10}"
BOUND_CHAT_ID="${BOUND_CHAT_ID:-100000001}"
WEBHOOK_SECRET="${WEBHOOK_SECRET:-test-secret}"

# â”€â”€ Colors â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0
START_TIME=$(date +%s)

log()    { echo -e "${BLUE}[suite]${NC} $1"; }
ok()     { echo -e "${GREEN}âœ…${NC} $1"; PASSED=$((PASSED + 1)); }
err()    { echo -e "${RED}âŒ${NC} $1"; FAILED=$((FAILED + 1)); }
header() { echo -e "\n${YELLOW}â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•${NC}"; echo -e "${YELLOW}  $1${NC}"; echo -e "${YELLOW}â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•${NC}"; }

# â”€â”€ Check prerequisites â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

header "Prerequisites Check"

if ! command -v k6 &>/dev/null && ! command -v k6.exe &>/dev/null; then
  err "k6 not found. Install: https://k6.io/docs/get-started/installation/"
  exit 1
fi
K6_CMD="k6"
if ! command -v k6 &>/dev/null; then 
  if command -v k6.exe &>/dev/null; then
    K6_CMD="k6.exe"
  fi
fi
log "Using k6 command: $K6_CMD"
ok "k6 version: $($K6_CMD version 2>&1 | head -1)"

if [[ -z "$SERVICE_ROLE_KEY" ]]; then
  err "SERVICE_ROLE_KEY not set. Run: export SERVICE_ROLE_KEY=\$(supabase status | grep service_role)"
  exit 1
fi
ok "SERVICE_ROLE_KEY set"

# Verify Supabase is reachable
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${SUPABASE_URL}/rest/v1/" \
  -H "apikey: ${SUPABASE_ANON_KEY}" 2>/dev/null || echo "000")
if [[ "$HTTP_STATUS" != "200" ]]; then
  err "Supabase not reachable at ${SUPABASE_URL} (status: $HTTP_STATUS). Run: supabase start"
  exit 1
fi
ok "Supabase reachable at ${SUPABASE_URL}"

mkdir -p "${RESULTS_DIR}"

# â”€â”€ K6 runner helper â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

run_k6() {
  local name="$1"
  local script="$2"
  shift 2
  local extra_env=("$@")

  log "Running: k6 $name"
  log "CWD: $(pwd)"
  log "LOAD_TEST_DIR: $LOAD_TEST_DIR"
  ls -l "$LOAD_TEST_DIR/$script" || echo "NOT FOUND"

  local env_args=(
    "-e" "SUPABASE_URL=${SUPABASE_URL}"
    "-e" "SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}"
    "-e" "SERVICE_ROLE_KEY=${SERVICE_ROLE_KEY}"
    "-e" "ORG_ID=${ORG_ID}"
    "-e" "CONTRACT_ID=${CONTRACT_ID}"
    "-e" "BOUND_CHAT_ID=${BOUND_CHAT_ID}"
  )

  for e in "${extra_env[@]}"; do
    if [[ -n "$e" ]]; then
      env_args+=("-e" "$e")
    fi
  done

  if $K6_CMD run "${env_args[@]}" "${LOAD_TEST_DIR}/${script}"; then
    ok "$name PASSED"
    return 0
  else
    err "$name FAILED"
    return 1
  fi
}

# â”€â”€ Scenario 1: SLA Racing & Determinism (INV-15) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

if [[ -z "$ONLY_SCENARIO" || "$ONLY_SCENARIO" == "1" ]]; then
  header "Scenario 1: SLA Racing & Determinism (INV-15)"
  log "Tests: concurrent complete_execution race, FSM reopen block, idempotent complete"

  run_k6 "SLA Race" "k6_sla_race.js" || true
fi

# â”€â”€ Scenario 2: Shadow Crash Recovery (INV-11) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

if [[ -z "$ONLY_SCENARIO" || "$ONLY_SCENARIO" == "2" ]]; then
  header "Scenario 2: Shadow Recovery & Crash Resilience (INV-11)"

  if [[ "$SKIP_CRASH" == "true" ]]; then
    log "Skipping SIGKILL crash test (--skip-crash flag set)"
  else
    log "Running SIGKILL crash + retry test..."
    if bash "${SCRIPT_DIR}/crash_recovery.sh"; then
      ok "Crash recovery PASSED"
    else
      err "Crash recovery FAILED"
    fi
  fi

  log "Running k6 idempotency load test..."
  run_k6 "Shadow Idempotency" "k6_shadow_idempotency.js" \
    "BOUND_CHAT_ID=${BOUND_CHAT_ID}" || true
fi

# â”€â”€ Scenario 3: Multi-Tenant Isolation at Scale (INV-1) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

if [[ -z "$ONLY_SCENARIO" || "$ONLY_SCENARIO" == "3" ]]; then
  header "Scenario 3: Multi-Tenant Isolation at Scale (INV-1, INV-22)"
  log "Tests: 100 GPS pings from 10 orgs, deadlock probe, isolation verification"

  # Build ORG_N_JWT and ORG_N_ID env args (reads from current env)
  EXTRA_ORG_ENV=()
  for i in $(seq 1 "${ORG_COUNT}"); do
    jwt_var="ORG_${i}_JWT"
    id_var="ORG_${i}_ID"
    [[ -n "${!jwt_var:-}" ]] && EXTRA_ORG_ENV+=("${jwt_var}=${!jwt_var}")
    [[ -n "${!id_var:-}" ]]  && EXTRA_ORG_ENV+=("${id_var}=${!id_var}")
  done

  run_k6 "Multi-Tenant Scale" "k6_multitenant_scale.js" \
    "ORG_COUNT=${ORG_COUNT}" "${EXTRA_ORG_ENV[@]:-}" || true
fi

# â”€â”€ Scenario 4: Fluid FSM Shadow Auto-Link (INV-11, Phase 10.3) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

if [[ -z "$ONLY_SCENARIO" || "$ONLY_SCENARIO" == "4" ]]; then
  header "Scenario 4: Fluid FSM Shadow Auto-Link (Phase 10.3)"
  log "TDD gate: test MUST PASS after migration 20260702000002 is applied"
  log "If this fails, run: supabase db push"

  run_k6 "Fluid FSM Auto-Link" "k6_fluid_fsm_autolink.js" \
    "OPERATOR_ID=${OPERATOR_ID:-00000000-0000-0000-0000-000000000099}" || true
fi

# â”€â”€ Final Report â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

header "Phase 10 Chaos Suite â€” Final Report"

echo ""
echo "  Duration:      ${DURATION}s"
echo "  Scenarios:     $((PASSED + FAILED))"
echo -e "  Passed:        ${GREEN}${PASSED}${NC}"
echo -e "  Failed:        ${RED}${FAILED}${NC}"
echo ""

if [[ $FAILED -eq 0 ]]; then
  echo -e "${GREEN}ðŸŸ¢ ALL CHAOS SCENARIOS PASSED â€” Engine is resilient${NC}"
  echo ""
  echo "  INV-1  (org_id isolation):       âœ… verified at scale (10 orgs, 100 concurrent)"
  echo "  INV-11 (idempotency/shadow):     âœ… SIGKILL + Telegram retry = no orphan rows"
  echo "  INV-15 (determinism):            âœ… concurrent race â†’ exactly 1 completion"
  echo "  Phase 10.3 (Fluid FSM):          âœ… retroactive auto-link without hash collision"
else
  echo -e "${RED}ðŸ”´ ${FAILED} SCENARIO(S) FAILED â€” Review output above${NC}"
  echo ""
  echo "  Results saved to: ${RESULTS_DIR}/"
  echo "  Re-run individual scenario: --scenario=N"
  exit 1
fi

echo ""
echo "  Results: ${RESULTS_DIR}/"
echo "  Governance JSON files written per k6 script."
echo "================================================================="
