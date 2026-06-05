#!/usr/bin/env bash
# Starts Chromium in kiosk mode with the RunReady auth extension loaded.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${RUNREADY_KIOSK_CONFIG:-/etc/runready-kiosk/config.env}"
PID_FILE="${RUNREADY_BROWSER_PID_FILE:-/var/run/runready-kiosk/chromium.pid}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Missing config: $CONFIG_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

DISPLAY_URL="${RUNREADY_DISPLAY_URL:-https://ops.runready.app/cad}"
PROFILE_DIR="${RUNREADY_CHROMIUM_PROFILE_DIR:-/var/lib/runready-kiosk/chromium}"
EXTENSION_DIR="${SCRIPT_DIR}/extension"
LOG_DIR="${RUNREADY_LOG_DIR:-/var/log/runready-kiosk}"

mkdir -p "$PROFILE_DIR" "$LOG_DIR" "$(dirname "$PID_FILE")"

"$SCRIPT_DIR/generate-extension-config.sh"

if [[ ! -f "${EXTENSION_DIR}/config.generated.js" ]]; then
  echo "Extension config not generated" >&2
  exit 1
fi

CHROMIUM=""
for candidate in chromium-browser chromium google-chrome google-chrome-stable; do
  if command -v "$candidate" >/dev/null 2>&1; then
    CHROMIUM="$candidate"
    break
  fi
done

if [[ -z "$CHROMIUM" ]]; then
  echo "Chromium not found. Install with: sudo apt install chromium-browser" >&2
  exit 1
fi

export DISPLAY="${DISPLAY:-:0}"

# Hide cursor on wall displays
if [[ "${RUNREADY_HIDE_CURSOR:-true}" == "true" ]] && command -v unclutter >/dev/null 2>&1; then
  pkill -x unclutter 2>/dev/null || true
  unclutter -idle 5 -root &
fi

# Prevent screen blanking
if command -v xset >/dev/null 2>&1; then
  xset s off 2>/dev/null || true
  xset -dpms 2>/dev/null || true
  xset s noblank 2>/dev/null || true
fi

CHROMIUM_FLAGS=(
  --kiosk
  --noerrdialogs
  --disable-infobars
  --disable-session-crashed-bubble
  --disable-restore-session-state
  --no-first-run
  --disable-translate
  --disable-features=TranslateUI
  --check-for-update-interval=31536000
  --load-extension="${EXTENSION_DIR}"
  "--user-data-dir=${PROFILE_DIR}"
  --window-size=1920,1080
  --start-fullscreen
  "${DISPLAY_URL}"
)

echo "[$(date -Iseconds)] Starting ${CHROMIUM} -> ${DISPLAY_URL}" >>"$LOG_DIR/browser.log"

# Run in background so watchdog can supervise
nohup "$CHROMIUM" "${CHROMIUM_FLAGS[@]}" >>"$LOG_DIR/chromium-stdout.log" 2>>"$LOG_DIR/chromium-stderr.log" &
echo $! >"$PID_FILE"
