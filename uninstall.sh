#!/usr/bin/env bash
# Remove the RunReady kiosk service and installed files from a Raspberry Pi.
#
#   sudo ./uninstall.sh           # stop service, remove /opt/runready-kiosk (keeps config & browser profile)
#   sudo ./uninstall.sh --purge     # also remove config, logs, state, and Chromium profile
#
# One-liner from the public repo (Pi Connect → Remote Shell):
#   curl -fsSL https://raw.githubusercontent.com/run-ready/runready-kiosk/main/uninstall.sh | sudo bash
#   curl -fsSL https://raw.githubusercontent.com/run-ready/runready-kiosk/main/uninstall.sh | sudo bash -s -- --purge

set -euo pipefail

INSTALL_DIR="/opt/runready-kiosk"
CONFIG_DIR="/etc/runready-kiosk"
CONFIG_FILE="${CONFIG_DIR}/config.env"
SERVICE_NAME="runready-kiosk.service"
STATE_DIR="/var/lib/runready-kiosk"
LOG_DIR="/var/log/runready-kiosk"
RUN_DIR="/var/run/runready-kiosk"
PID_FILE="${RUN_DIR}/chromium.pid"

PURGE=false
for arg in "$@"; do
  case "$arg" in
    --purge) PURGE=true ;;
    -h | --help)
      echo "Usage: sudo $0 [--purge]"
      echo "  --purge  Also remove ${CONFIG_DIR}, ${STATE_DIR}, ${LOG_DIR}, and browser profile"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg (try --help)" >&2
      exit 1
      ;;
  esac
done

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

echo "RunReady Operations display kiosk — uninstall"
echo "=============================================="
echo ""

if systemctl is-active --quiet "${SERVICE_NAME}" 2>/dev/null; then
  echo "Stopping ${SERVICE_NAME}..."
  systemctl stop "${SERVICE_NAME}"
fi

if systemctl is-enabled --quiet "${SERVICE_NAME}" 2>/dev/null; then
  echo "Disabling ${SERVICE_NAME}..."
  systemctl disable "${SERVICE_NAME}"
fi

if [[ -f "/etc/systemd/system/${SERVICE_NAME}" ]]; then
  echo "Removing systemd unit..."
  rm -f "/etc/systemd/system/${SERVICE_NAME}"
  systemctl daemon-reload
fi

if [[ -f "$PID_FILE" ]]; then
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
    echo "Stopping kiosk Chromium (pid $pid)..."
    kill "$pid" 2>/dev/null || true
    sleep 1
    kill -9 "$pid" 2>/dev/null || true
  fi
fi

pkill -x unclutter 2>/dev/null || true

if [[ -d "$INSTALL_DIR" ]]; then
  echo "Removing ${INSTALL_DIR}..."
  rm -rf "$INSTALL_DIR"
fi

if [[ "$PURGE" == true ]]; then
  echo "Purging config, state, and logs..."
  rm -rf "$CONFIG_DIR" "$STATE_DIR" "$LOG_DIR" "$RUN_DIR"
else
  echo "Keeping ${CONFIG_FILE} and ${STATE_DIR} (re-run with --purge to remove)."
fi

echo ""
echo "Uninstall complete."
if [[ "$PURGE" != true ]]; then
  echo "To reinstall: curl -fsSL https://raw.githubusercontent.com/run-ready/runready-kiosk/main/bootstrap-install.sh | sudo bash"
fi
