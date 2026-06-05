#!/usr/bin/env bash
# Resolve the desktop autologin user and wait until their graphical session is ready.

set -euo pipefail

CONFIG_FILE="${RUNREADY_KIOSK_CONFIG:-/etc/runready-kiosk/config.env}"
LOG_DIR="${RUNREADY_LOG_DIR:-/var/log/runready-kiosk}"
MAX_WAIT_SEC="${RUNREADY_DISPLAY_WAIT_SEC:-180}"
POLL_SEC="${RUNREADY_DISPLAY_POLL_SEC:-2}"

mkdir -p "$LOG_DIR"

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

log() { echo "[$(date -Iseconds)] $*" | tee -a "$LOG_DIR/watchdog.log"; }

detect_desktop_user() {
  if [[ -n "${RUNREADY_DESKTOP_USER:-}" ]]; then
    echo "$RUNREADY_DESKTOP_USER"
    return 0
  fi

  local u=""
  if [[ -d /etc/lightdm ]]; then
    u="$(grep -rhE '^[[:space:]]*autologin-user=' /etc/lightdm 2>/dev/null | tail -1 | cut -d= -f2 | tr -d '[:space:]')"
  fi
  if [[ -z "$u" && -f /etc/systemd/system/getty@tty1.service.d/autologin.conf ]]; then
    u="$(grep -E '^ExecStart=' /etc/systemd/system/getty@tty1.service.d/autologin.conf 2>/dev/null | sed -n 's/.*--autologin \([^ ]*\).*/\1/p')"
  fi
  if [[ -z "$u" ]]; then
    for candidate in pi runready display; do
      if id "$candidate" &>/dev/null; then
        u="$candidate"
        break
      fi
    done
  fi
  if [[ -z "$u" ]]; then
    u="$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 && $7 !~ /false$/ { print $1; exit }')"
  fi
  echo "${u:-pi}"
}

wait_for_display() {
  local desktop_user="$1"
  local uid home xauth xdg_runtime waited=0

  if ! id "$desktop_user" &>/dev/null; then
    log "ERROR: Desktop user '$desktop_user' does not exist"
    return 1
  fi

  uid="$(id -u "$desktop_user")"
  home="$(getent passwd "$desktop_user" | cut -d: -f6)"
  xauth="${home}/.Xauthority"
  xdg_runtime="/run/user/${uid}"

  log "Waiting for graphical session (user=${desktop_user}, up to ${MAX_WAIT_SEC}s)..."

  while (( waited < MAX_WAIT_SEC )); do
    # Wayland session (common on newer Raspberry Pi OS)
    if [[ -d "$xdg_runtime" ]]; then
      if [[ -S "${xdg_runtime}/wayland-0" ]] || compgen -G "${xdg_runtime}/wayland-*" >/dev/null; then
        local wl="${WAYLAND_DISPLAY:-wayland-0}"
        if sudo -u "$desktop_user" \
          env "XDG_RUNTIME_DIR=${xdg_runtime}" "WAYLAND_DISPLAY=${wl}" \
          sh -c 'test -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}"' 2>/dev/null; then
          export RUNREADY_DESKTOP_USER="$desktop_user"
          export RUNREADY_SESSION_TYPE="wayland"
          export XDG_RUNTIME_DIR="$xdg_runtime"
          export WAYLAND_DISPLAY="$wl"
          export DISPLAY="${DISPLAY:-:0}"
          log "Wayland session ready (${WAYLAND_DISPLAY}, XDG_RUNTIME_DIR=${xdg_runtime})"
          return 0
        fi
      fi
    fi

    # X11 session
    if [[ -S /tmp/.X11-unix/X0 ]] || [[ -f "$xauth" ]]; then
      if sudo -u "$desktop_user" env DISPLAY=:0 "XAUTHORITY=${xauth}" xset q >/dev/null 2>&1; then
        export RUNREADY_DESKTOP_USER="$desktop_user"
        export RUNREADY_SESSION_TYPE="x11"
        export DISPLAY=":0"
        export XAUTHORITY="$xauth"
        export XDG_RUNTIME_DIR="$xdg_runtime"
        log "X11 session ready (DISPLAY=:0, XAUTHORITY=${xauth})"
        return 0
      fi
    fi

    sleep "$POLL_SEC"
    waited=$((waited + POLL_SEC))
  done

  log "ERROR: Graphical session not ready after ${MAX_WAIT_SEC}s for user ${desktop_user}"
  log "Check: desktop autologin enabled, user can log in, and chromium starts manually as ${desktop_user}"
  return 1
}

DESKTOP_USER="$(detect_desktop_user)"
wait_for_display "$DESKTOP_USER"
