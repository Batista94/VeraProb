#!/usr/bin/env bash
# =============================================================================
# apply_stress_limits.sh -- Apply CPU/Memory Limits to Running Supabase Stack
# Phase 10 Chaos Environment Setup
# =============================================================================
#
# Supabase CLI manages its own internal docker-compose. This script uses
# `docker update` to apply resource constraints to already-running containers.
# Must run AFTER `supabase start`.
#
# LIMITS APPLIED:
#   DB (postgres):      2 CPU, 1.5GB RAM  -- forces pool pressure (INV-16)
#   Edge Runtime:       1 CPU, 512MB RAM  -- forces queue buildup under load
#   PostgREST:          1 CPU, 256MB RAM
#   Kong:               0.5 CPU, 256MB RAM
#
# USAGE:
#   supabase start
#   bash scripts/chaos/apply_stress_limits.sh
#   bash scripts/chaos/run_chaos_suite.sh
#
# TEARDOWN (restore unlimited):
#   bash scripts/chaos/apply_stress_limits.sh --restore
# =============================================================================

set -euo pipefail

RESTORE="${1:-}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${YELLOW}[stress]${NC} $1"; }
ok()   { echo -e "${GREEN}[stress]${NC} $1"; }
err()  { echo -e "${RED}[stress]${NC} $1"; }

# -- Find running Supabase containers ------------------------------------------
# Supabase CLI names containers with a project prefix (usually the dir name).
# Pattern: supabase_<service>_<project> or supabase-<service>

find_container() {
  local pattern="$1"
  docker ps --format "{{.Names}}" | grep -i "$pattern" | head -1 || echo ""
}

DB_CONTAINER=$(find_container "supabase.*db\|postgres.*supabase" || find_container "supabase_db")
EDGE_CONTAINER=$(find_container "edge.runtime\|edge-runtime\|supabase.*edge")
REST_CONTAINER=$(find_container "supabase.*rest\|postgrest")
KONG_CONTAINER=$(find_container "supabase.*kong\|kong")

log "Detected containers:"
log "  DB:   ${DB_CONTAINER:-NOT FOUND}"
log "  Edge: ${EDGE_CONTAINER:-NOT FOUND}"
log "  REST: ${REST_CONTAINER:-NOT FOUND}"
log "  Kong: ${KONG_CONTAINER:-NOT FOUND}"

if [[ -z "$DB_CONTAINER" ]]; then
  err "No Supabase DB container found. Run 'supabase start' first."
  err "Use 'docker ps' to verify container names and update find_container() patterns."
  exit 1
fi

apply_limits() {
  if [[ "$RESTORE" == "--restore" ]]; then
    log "Restoring unlimited resources..."

    [[ -n "$DB_CONTAINER" ]]   && docker update --cpus="0" --memory="0" "$DB_CONTAINER"   2>/dev/null && ok "DB: restored"
    [[ -n "$EDGE_CONTAINER" ]] && docker update --cpus="0" --memory="0" "$EDGE_CONTAINER" 2>/dev/null && ok "Edge: restored"
    [[ -n "$REST_CONTAINER" ]] && docker update --cpus="0" --memory="0" "$REST_CONTAINER" 2>/dev/null && ok "REST: restored"
    [[ -n "$KONG_CONTAINER" ]] && docker update --cpus="0" --memory="0" "$KONG_CONTAINER" 2>/dev/null && ok "Kong: restored"
  else
    log "Applying stress limits..."

    if [[ -n "$DB_CONTAINER" ]]; then
      docker update \
        --cpus="2.0" \
        --memory="1536m" \
        --memory-swap="1536m" \
        "$DB_CONTAINER"
      ok "DB ($DB_CONTAINER): 2 CPU, 1.5GB -- pool pressure mode"
    fi

    if [[ -n "$EDGE_CONTAINER" ]]; then
      docker update \
        --cpus="1.0" \
        --memory="512m" \
        --memory-swap="512m" \
        "$EDGE_CONTAINER"
      ok "Edge ($EDGE_CONTAINER): 1 CPU, 512MB -- SIGKILL target for crash_recovery.sh"
    fi

    if [[ -n "$REST_CONTAINER" ]]; then
      docker update \
        --cpus="1.0" \
        --memory="256m" \
        --memory-swap="256m" \
        "$REST_CONTAINER"
      ok "REST ($REST_CONTAINER): 1 CPU, 256MB"
    fi

    if [[ -n "$KONG_CONTAINER" ]]; then
      docker update \
        --cpus="0.5" \
        --memory="256m" \
        --memory-swap="256m" \
        "$KONG_CONTAINER"
      ok "Kong ($KONG_CONTAINER): 0.5 CPU, 256MB"
    fi
  fi
}

apply_limits

echo ""
if [[ "$RESTORE" == "--restore" ]]; then
  ok "Stress limits removed. Containers back to unlimited."
else
  ok "Stress limits applied. Run: bash scripts/chaos/run_chaos_suite.sh"
  log "To restore: bash scripts/chaos/apply_stress_limits.sh --restore"
fi

# -- Show current limits -------------------------------------------------------
echo ""
log "Current container limits:"
for name in "$DB_CONTAINER" "$EDGE_CONTAINER" "$REST_CONTAINER" "$KONG_CONTAINER"; do
  [[ -z "$name" ]] && continue
  NANO_CPU=$(docker inspect "$name" --format "{{.HostConfig.NanoCpus}}" 2>/dev/null || echo "0")
  MEM=$(docker inspect "$name" --format "{{.HostConfig.Memory}}" 2>/dev/null || echo "0")
  CPU_CORES=$(echo "scale=1; $NANO_CPU / 1000000000" | bc 2>/dev/null || echo "unlimited")
  MEM_MB=$(echo "scale=0; $MEM / 1048576" | bc 2>/dev/null || echo "unlimited")
  echo "  $name: ${CPU_CORES} CPU, ${MEM_MB} MB"
done
