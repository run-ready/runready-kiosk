#!/usr/bin/env bash
# Starts Chromium in kiosk mode with the RunReady auth extension loaded.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${RUNREADY_KIOSK_CONFIG:-/etc/runready-kiosk/config.env}"
PID_FILE="${RUNREADY_BROWSER_PID_FILE:-/var/run/runready-kiosk/chromium.pid}"
LOG_DIR="${RUNREADY_LOG_DIR:-/var/log/runready-kiosk}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Missing config: $CONFIG_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

DISPLAY_URL="${RUNREADY_DISPLAY_URL:-https://ops.runready.app/cad}"
PROFILE_DIR="${RUNREADY_CHROMIUM_PROFILE_DIR:-/var/lib/runready-kiosk/chromium}"
EXTENSION_DIR="${SCRIPT_DIR}/extension"

mkdir -p "$PROFILE_DIR" "$LOG_DIR" "$(dirname "$PID_FILE")"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/wait-for-display.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/chromium-process.sh"

DESKTOP_USER="${RUNREADY_DESKTOP_USER:?Desktop user not set}"

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

chown -R "${DESKTOP_USER}:${DESKTOP_USER}" "$PROFILE_DIR" 2>/dev/null || true
chmod -R a+rX "${EXTENSION_DIR}" 2>/dev/null || true

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
  --disable-dev-shm-usage
  --load-extension="${EXTENSION_DIR}"
  "--user-data-dir=${PROFILE_DIR}"
  --window-size=1920,1080
  --start-fullscreen
)

if [[ "${RUNREADY_SESSION_TYPE:-}" == "wayland" ]]; then
  CHROMIUM_FLAGS+=(--ozone-platform=wayland)
fi

CHROMIUM_FLAGS+=("${DISPLAY_URL}")

RUN_ENV=(
  "DISPLAY=${DISPLAY:-:0}"
)
if [[ -n "${XAUTHORITY:-}" ]]; then
  RUN_ENV+=("XAUTHORITY=${XAUTHORITY}")
fi
if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
  RUN_ENV+=("XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}")
fi
if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
  RUN_ENV+=("WAYLAND_DISPLAY=${WAYLAND_DISPLAY}")
fi

if [[ "${RUNREADY_HIDE_CURSOR:-true}" == "true" ]] && command -v unclutter >/dev/null 2>&1; then
  pkill -x unclutter 2>/dev/null || true
  sudo -u "$DESKTOP_USER" env "${RUN_ENV[@]}" unclutter -idle 5 -root &
fi

if [[ "${RUNREADY_SESSION_TYPE:-}" == "x11" ]] && command -v xset >/dev/null 2>&1; then
  sudo -u "$DESKTOP_USER" env "${RUN_ENV[@]}" xset s off 2>/dev/null || true
  sudo -u "$DESKTOP_USER" env "${RUN_ENV[@]}" xset -dpms 2>/dev/null || true
  sudo -u "$DESKTOP_USER" env "${RUN_ENV[@]}" xset s noblank 2>/dev/null || true
fi

echo "[$(date -Iseconds)] Starting ${CHROMIUM} as ${DESKTOP_USER} (${RUNREADY_SESSION_TYPE:-unknown}) -> ${DISPLAY_URL}" >>"$LOG_DIR/browser.log"

sudo -u "$DESKTOP_USER" env "${RUN_ENV[@]}" \
  "$CHROMIUM" "${CHROMIUM_FLAGS[@]}" >>"$LOG_DIR/chromium-stdout.log" 2>>"$LOG_DIR/chromium-stderr.log" &

# Wait for the browser process tree to settle (launcher PIDs exit quickly on some builds).
for _ in 1 2 3 4 5 6; do
  sleep 2
  if write_kiosk_chromium_pid_file "$PID_FILE"; then
    exit 0
  fi
done

echo "Chromium exited or never started — see ${LOG_DIR}/chromium-stderr.log" >&2
tail -30 "$LOG_DIR/chromium-stderr.log" 2>/dev/null >&2 || true
exit 1
