#!/usr/bin/env bash
# Supervises the kiosk browser: restarts on crash, reloads on deploy, refreshes auth tokens.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${RUNREADY_KIOSK_CONFIG:-/etc/runready-kiosk/config.env}"
PID_FILE="${RUNREADY_BROWSER_PID_FILE:-/var/run/runready-kiosk/chromium.pid}"
LOG_DIR="${RUNREADY_LOG_DIR:-/var/log/runready-kiosk}"

mkdir -p "$LOG_DIR" "$(dirname "$PID_FILE")"

log() { echo "[$(date -Iseconds)] $*" | tee -a "$LOG_DIR/watchdog.log"; }

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

DEPLOY_INTERVAL="${RUNREADY_CHECK_DEPLOY_INTERVAL_SEC:-300}"
TOKEN_INTERVAL="${RUNREADY_TOKEN_REFRESH_INTERVAL_SEC:-21600}"
HEALTH_INTERVAL="${RUNREADY_BROWSER_HEALTH_INTERVAL_SEC:-60}"

last_deploy_check=0
last_token_refresh=0
last_health_check=0

stop_browser() {
  if [[ -f "$PID_FILE" ]]; then
    pid=$(cat "$PID_FILE" 2>/dev/null || true)
    if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
      log "Stopping browser (pid $pid)"
      kill "$pid" 2>/dev/null || true
      sleep 2
      kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
  fi
  pkill -x unclutter 2>/dev/null || true
}

start_browser() {
  stop_browser
  if ! "$SCRIPT_DIR/launch-browser.sh"; then
    log "ERROR: Browser failed to start (see ${LOG_DIR}/chromium-stderr.log)"
    return 1
  fi
  log "Browser started"
}

browser_alive() {
  if [[ ! -f "$PID_FILE" ]]; then
    return 1
  fi
  pid=$(cat "$PID_FILE" 2>/dev/null || true)
  [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null
}

reload_browser() {
  log "Reloading browser"
  start_browser
}

log "RunReady kiosk watchdog starting"

# Initial token refresh + browser launch (retry until display session is up)
if "$SCRIPT_DIR/refresh-token.sh" >>"$LOG_DIR/watchdog.log" 2>&1; then
  :
else
  log "WARN: Initial token refresh failed — starting browser anyway"
fi

until start_browser; do
  log "Browser start failed — retrying in 10s (desktop session may still be starting)"
  sleep 10
done

while true; do
  now=$(date +%s)

  if (( now - last_health_check >= HEALTH_INTERVAL )); then
    last_health_check=$now
    if ! browser_alive; then
      log "Browser not running — restarting"
      start_browser
    fi
  fi

  if (( now - last_deploy_check >= DEPLOY_INTERVAL )); then
    last_deploy_check=$now
    deploy_out=$("$SCRIPT_DIR/check-deploy.sh" 2>&1 || true)
    if echo "$deploy_out" | grep -q 'DEPLOY_CHANGED=1'; then
      log "New ops web deployment detected — reloading"
      reload_browser
    fi
  fi

  if (( now - last_token_refresh >= TOKEN_INTERVAL )); then
    last_token_refresh=$now
    refresh_out=$("$SCRIPT_DIR/refresh-token.sh" 2>&1 || true)
    if echo "$refresh_out" | grep -q 'TOKEN_REFRESHED=1'; then
      log "Auth token refreshed — reloading browser"
      reload_browser
    elif echo "$refresh_out" | grep -qi 'ERROR'; then
      log "Token refresh error: $refresh_out"
    fi
  fi

  sleep 10
done
