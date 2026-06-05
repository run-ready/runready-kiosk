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

# shellcheck disable=SC1091
source "$SCRIPT_DIR/chromium-process.sh"

DEPLOY_INTERVAL="${RUNREADY_CHECK_DEPLOY_INTERVAL_SEC:-300}"
TOKEN_INTERVAL="${RUNREADY_TOKEN_REFRESH_INTERVAL_SEC:-21600}"
HEALTH_INTERVAL="${RUNREADY_BROWSER_HEALTH_INTERVAL_SEC:-60}"
MIN_UPTIME_BEFORE_RESTART_SEC="${RUNREADY_MIN_UPTIME_BEFORE_RESTART_SEC:-45}"

last_deploy_check=0
last_token_refresh=0
last_health_check=0
last_start_epoch=0
consecutive_dead_checks=0

stop_browser() {
  stop_kiosk_chromium
  rm -f "$PID_FILE"
}

start_browser() {
  stop_browser
  if ! "$SCRIPT_DIR/launch-browser.sh"; then
    log "ERROR: Browser failed to start (see ${LOG_DIR}/chromium-stderr.log)"
    if [[ -f "${LOG_DIR}/chromium-stderr.log" ]]; then
      tail -5 "$LOG_DIR/chromium-stderr.log" | while read -r line; do log "  stderr: $line"; done
    fi
    return 1
  fi
  last_start_epoch=$(date +%s)
  consecutive_dead_checks=0
  log "Browser started (pid $(cat "$PID_FILE" 2>/dev/null || echo '?'))"
}

browser_alive() {
  write_kiosk_chromium_pid_file "$PID_FILE" 2>/dev/null || true
  kiosk_chromium_running
}

reload_browser() {
  log "Reloading browser"
  start_browser
}

log "RunReady kiosk watchdog starting"

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
    if browser_alive; then
      consecutive_dead_checks=0
    else
      consecutive_dead_checks=$((consecutive_dead_checks + 1))
      uptime=$((now - last_start_epoch))
      if (( uptime < MIN_UPTIME_BEFORE_RESTART_SEC && consecutive_dead_checks < 2 )); then
        log "Browser process not detected yet (${uptime}s uptime, check ${consecutive_dead_checks}/2) — waiting"
      else
        log "Browser not running — restarting (uptime ${uptime}s)"
        if [[ -f "${LOG_DIR}/chromium-stderr.log" ]]; then
          tail -5 "$LOG_DIR/chromium-stderr.log" | while read -r line; do log "  stderr: $line"; done
        fi
        start_browser || true
      fi
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
