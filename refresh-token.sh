#!/usr/bin/env bash
# Calls POST /auth/verify and updates RUNREADY_AUTH_TOKEN in config when refreshed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${RUNREADY_KIOSK_CONFIG:-/etc/runready-kiosk/config.env}"
LOG_DIR="${RUNREADY_LOG_DIR:-/var/log/runready-kiosk}"

mkdir -p "$LOG_DIR"
log() { echo "[$(date -Iseconds)] $*" | tee -a "$LOG_DIR/token-refresh.log"; }

if [[ ! -f "$CONFIG_FILE" ]]; then
  log "ERROR: Missing config $CONFIG_FILE"
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

API_BASE="${RUNREADY_API_BASE_URL:-https://api.runready.app}"
TOKEN="${RUNREADY_AUTH_TOKEN:-}"

if [[ -z "$TOKEN" ]]; then
  log "ERROR: RUNREADY_AUTH_TOKEN is empty"
  exit 1
fi

payload=$(RUNREADY_TOKEN="$TOKEN" python3 - <<'PY'
import json, os
print(json.dumps({"token": os.environ["RUNREADY_TOKEN"]}))
PY
)

response=$(curl -sf --max-time 30 \
  -X POST "${API_BASE}/auth/verify" \
  -H "Content-Type: application/json" \
  -d "$payload" 2>&1) || {
  log "ERROR: /auth/verify request failed: $response"
  exit 1
}

read -r new_token <<<"$(VERIFY_RESPONSE="$response" python3 - <<'PY'
import json, os
try:
    data = json.loads(os.environ["VERIFY_RESPONSE"])
    print(data.get("token") or "")
except Exception:
    print("")
PY
)"

if [[ -z "$new_token" ]]; then
  log "ERROR: No token in verify response"
  exit 1
fi

if [[ "$new_token" == "$TOKEN" ]]; then
  log "Token still valid (unchanged)"
  exit 0
fi

log "Token refreshed — updating config"

NEW_TOKEN="$new_token" CONFIG_PATH="$CONFIG_FILE" python3 - <<'PY'
import os, re
path = os.environ["CONFIG_PATH"]
new_token = os.environ["NEW_TOKEN"]
with open(path, "r", encoding="utf-8") as f:
    text = f.read()
escaped = new_token.replace("\\", "\\\\").replace('"', '\\"')
pattern = r'^(RUNREADY_AUTH_TOKEN=)(\".*?\"|\'.*?\'|[^\n#]*)'
repl = r'\1"' + escaped + '"'
updated, n = re.subn(pattern, repl, text, count=1, flags=re.MULTILINE)
if n == 0:
    updated = text.rstrip() + f'\nRUNREADY_AUTH_TOKEN="{escaped}"\n'
with open(path, "w", encoding="utf-8") as f:
    f.write(updated)
PY

export RUNREADY_FORCE_TOKEN_SYNC=true
"$SCRIPT_DIR/generate-extension-config.sh"
unset RUNREADY_FORCE_TOKEN_SYNC

log "Config and extension updated"
echo "TOKEN_REFRESHED=1"
