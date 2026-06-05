#!/usr/bin/env bash
# Verifies the display token in config.env against the RunReady API.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${RUNREADY_KIOSK_CONFIG:-/etc/runready-kiosk/config.env}"

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
elif [[ -f "$SCRIPT_DIR/config.example.env" ]]; then
  echo "Using config.example.env — copy to /etc/runready-kiosk/config.env for production"
  # shellcheck disable=SC1090
  source "$SCRIPT_DIR/config.example.env"
else
  echo "No config file found" >&2
  exit 1
fi

API_BASE="${RUNREADY_API_BASE_URL:-https://api.runready.app}"
TOKEN="${RUNREADY_AUTH_TOKEN:-}"

if [[ -z "$TOKEN" ]]; then
  echo "RUNREADY_AUTH_TOKEN is not set" >&2
  exit 1
fi

echo "Verifying token with ${API_BASE}/auth/verify ..."

response=$(curl -sf --max-time 30 \
  -X POST "${API_BASE}/auth/verify" \
  -H "Content-Type: application/json" \
  -d "$(TOKEN="$TOKEN" python3 - <<'PY'
import json, os
print(json.dumps({"token": os.environ["TOKEN"]}))
PY
)")

python3 - <<'PY' "$response"
import json, sys
data = json.loads(sys.argv[1])
user = data.get("user") or {}
print("OK — token valid")
print(f"  userId:    {user.get('userId', '?')}")
print(f"  email:     {user.get('email', '?')}")
print(f"  accountId: {user.get('accountId', '(none)')}")
print(f"  name:      {user.get('firstName', '')} {user.get('lastName', '')}".strip())
if data.get("token"):
    print("  (API returned a refreshed token — watchdog will persist it)")
PY

echo ""
echo "Display URL: ${RUNREADY_DISPLAY_URL:-https://ops.runready.app/cad}"
echo "Organization: ${RUNREADY_ORGANIZATION_ID:-(not set)}"
