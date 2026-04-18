#!/usr/bin/env bash

# Batch runner for scanning all common .lk second-level domain groups.
#
# Behavior:
# - Preserves and restores existing .env after the batch run.
# - Reuses existing config values from .env when present.
# - Scans each group sequentially using ./run.sh.
# - Continues on individual domain failures and prints a final summary.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ ! -f "run.sh" ]]; then
  echo "Error: run.sh was not found in $SCRIPT_DIR"
  exit 1
fi

if [[ ! -x "run.sh" ]]; then
  chmod +x run.sh
fi

read_env_value() {
  local key="$1"
  local value
  value="$(grep -E "^${key}=" .env 2>/dev/null | tail -n 1 | cut -d'=' -f2- || true)"
  echo "$value"
}

DEFAULT_DOMAINS=(
  "gov.lk"
  "ac.lk"
  "edu.lk"
  "com.lk"
  "org.lk"
  "net.lk"
  "sch.lk"
  "hotel.lk"
  "int.lk"
  "grp.lk"
  "soc.lk"
  "ngo.lk"
  "ltd.lk"
  "assn.lk"
  "web.lk"
  "me.lk"
)

if [[ $# -gt 0 ]]; then
  DOMAINS=("$@")
else
  DOMAINS=("${DEFAULT_DOMAINS[@]}")
fi

ORIGINAL_ENV_EXISTS=false
ENV_BACKUP=".env.batch_backup_$(date +%Y%m%d_%H%M%S)"

if [[ -f ".env" ]]; then
  ORIGINAL_ENV_EXISTS=true
  cp .env "$ENV_BACKUP"
fi

cleanup() {
  if [[ "$ORIGINAL_ENV_EXISTS" == "true" && -f "$ENV_BACKUP" ]]; then
    mv "$ENV_BACKUP" .env
  elif [[ -f "$ENV_BACKUP" ]]; then
    rm -f "$ENV_BACKUP"
  fi
}

trap cleanup EXIT

BASE_ALLOW_ACTIVE_PROBES="$(read_env_value "ALLOW_ACTIVE_PROBES")"
BASE_STATE_DIR="$(read_env_value "STATE_DIR")"
BASE_OUT_DIR="$(read_env_value "OUT_DIR")"
BASE_ENABLE_EXCEL="$(read_env_value "ENABLE_EXCEL")"
BASE_RESCAN_HOURS="$(read_env_value "RESCAN_HOURS")"
BASE_ERROR_RETRY_HOURS="$(read_env_value "ERROR_RETRY_HOURS")"
BASE_WORKERS="$(read_env_value "WORKERS")"
BASE_ENUM_WORKERS="$(read_env_value "ENUM_WORKERS")"

ALLOW_ACTIVE_PROBES="${ALLOW_ACTIVE_PROBES:-${BASE_ALLOW_ACTIVE_PROBES:-false}}"
STATE_DIR="${STATE_DIR:-${BASE_STATE_DIR:-state}}"
OUT_DIR="${OUT_DIR:-${BASE_OUT_DIR:-out}}"
ENABLE_EXCEL="${ENABLE_EXCEL:-${BASE_ENABLE_EXCEL:-true}}"
RESCAN_HOURS="${RESCAN_HOURS:-${BASE_RESCAN_HOURS:-24}}"
ERROR_RETRY_HOURS="${ERROR_RETRY_HOURS:-${BASE_ERROR_RETRY_HOURS:-6}}"
WORKERS="${WORKERS:-${BASE_WORKERS:-}}"
ENUM_WORKERS="${ENUM_WORKERS:-${BASE_ENUM_WORKERS:-}}"

SUCCESS_COUNT=0
FAIL_COUNT=0
FAILED_DOMAINS=()
START_TS="$(date +%s)"

echo "============================================================"
echo "LK Domain Batch Audit"
echo "============================================================"
echo "Total domain groups: ${#DOMAINS[@]}"
echo "ALLOW_ACTIVE_PROBES: $ALLOW_ACTIVE_PROBES"
echo "STATE_DIR: $STATE_DIR"
echo "OUT_DIR: $OUT_DIR"
echo "ENABLE_EXCEL: $ENABLE_EXCEL"
if [[ "$ALLOW_ACTIVE_PROBES" == "true" ]]; then
  echo "WARNING: Active probing is enabled. Use only with authorization."
fi
echo "============================================================"

for domain in "${DOMAINS[@]}"; do
  echo ""
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting: $domain"

  {
    echo "DOMAIN=$domain"
    echo "ALLOW_ACTIVE_PROBES=$ALLOW_ACTIVE_PROBES"
    echo "STATE_DIR=$STATE_DIR"
    echo "OUT_DIR=$OUT_DIR"
    echo "ENABLE_EXCEL=$ENABLE_EXCEL"
    echo "RESCAN_HOURS=$RESCAN_HOURS"
    echo "ERROR_RETRY_HOURS=$ERROR_RETRY_HOURS"
    if [[ -n "$WORKERS" ]]; then
      echo "WORKERS=$WORKERS"
    fi
    if [[ -n "$ENUM_WORKERS" ]]; then
      echo "ENUM_WORKERS=$ENUM_WORKERS"
    fi
  } > .env

  if ./run.sh; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Completed: $domain"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAILED_DOMAINS+=("$domain")
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Failed: $domain"
    echo "Continuing to next domain..."
  fi
done

END_TS="$(date +%s)"
ELAPSED="$((END_TS - START_TS))"

echo ""
echo "============================================================"
echo "Batch scan summary"
echo "============================================================"
echo "Success: $SUCCESS_COUNT"
echo "Failed:  $FAIL_COUNT"
echo "Elapsed: ${ELAPSED}s"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  echo ""
  echo "Failed domain groups:"
  for d in "${FAILED_DOMAINS[@]}"; do
    echo "- $d"
  done
fi

echo ""
echo "Output root: $OUT_DIR"
echo "Done."
