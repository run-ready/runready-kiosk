#!/usr/bin/env bash
# Shared helpers to find and stop the kiosk Chromium process(es).

set -euo pipefail

kiosk_config() {
  CONFIG_FILE="${RUNREADY_KIOSK_CONFIG:-/etc/runready-kiosk/config.env}"
  if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
  fi
  DESKTOP_USER="${RUNREADY_DESKTOP_USER:-pi}"
  PROFILE_DIR="${RUNREADY_CHROMIUM_PROFILE_DIR:-/var/lib/runready-kiosk/chromium}"
}

# Print PIDs (one per line) for Chromium using the kiosk profile.
find_kiosk_chromium_pids() {
  kiosk_config
  local pids=""
  pids="$(pgrep -u "$DESKTOP_USER" -f "user-data-dir=${PROFILE_DIR}" 2>/dev/null || true)"
  if [[ -n "$pids" ]]; then
    echo "$pids"
    return 0
  fi
  # Fallback: any chromium owned by the desktop user (last resort)
  pgrep -u "$DESKTOP_USER" -x chromium 2>/dev/null || pgrep -u "$DESKTOP_USER" -x chromium-browser 2>/dev/null || true
}

kiosk_chromium_running() {
  [[ -n "$(find_kiosk_chromium_pids | head -1)" ]]
}

stop_kiosk_chromium() {
  kiosk_config
  local pid
  while read -r pid; do
    [[ -z "$pid" ]] && continue
    kill "$pid" 2>/dev/null || true
  done < <(find_kiosk_chromium_pids)
  sleep 2
  while read -r pid; do
    [[ -z "$pid" ]] && continue
    kill -9 "$pid" 2>/dev/null || true
  done < <(find_kiosk_chromium_pids)
  pkill -x unclutter 2>/dev/null || true
}

write_kiosk_chromium_pid_file() {
  local pid_file="${1:-/var/run/runready-kiosk/chromium.pid}"
  local pid
  pid="$(find_kiosk_chromium_pids | head -1)"
  if [[ -n "$pid" ]]; then
    echo "$pid" >"$pid_file"
  else
    rm -f "$pid_file"
    return 1
  fi
}
