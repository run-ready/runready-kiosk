#!/usr/bin/env bash
# Detects a new ops web deployment by hashing index.html from CloudFront.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${RUNREADY_KIOSK_CONFIG:-/etc/runready-kiosk/config.env}"
STATE_FILE="${RUNREADY_DEPLOY_STATE:-/var/lib/runready-kiosk/deploy-hash.txt}"
LOG_DIR="${RUNREADY_LOG_DIR:-/var/log/runready-kiosk}"

mkdir -p "$(dirname "$STATE_FILE")" "$LOG_DIR"
log() { echo "[$(date -Iseconds)] $*" >> "$LOG_DIR/deploy-check.log"; }

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

OPS_BASE="${RUNREADY_OPS_BASE_URL:-https://ops.runready.app}"

html=$(curl -sf --max-time 30 "${OPS_BASE}/index.html" 2>/dev/null) || {
  log "WARN: Could not fetch ${OPS_BASE}/index.html"
  exit 0
}

new_hash=$(printf '%s' "$html" | sha256sum | awk '{print $1}')
old_hash=""

if [[ -f "$STATE_FILE" ]]; then
  old_hash=$(cat "$STATE_FILE")
fi

if [[ -z "$old_hash" ]]; then
  echo "$new_hash" >"$STATE_FILE"
  log "Initial deploy hash recorded: $new_hash"
  exit 0
fi

if [[ "$new_hash" != "$old_hash" ]]; then
  echo "$new_hash" >"$STATE_FILE"
  log "Deploy change detected: $old_hash -> $new_hash"
  echo "DEPLOY_CHANGED=1"
  exit 0
fi

exit 0
