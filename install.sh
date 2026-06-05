#!/usr/bin/env bash
# One-time setup on Raspberry Pi OS (Bookworm / Bullseye).
# Run from the repo: sudo ./scripts/kiosk/install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/runready-kiosk"
CONFIG_DIR="/etc/runready-kiosk"
CONFIG_FILE="${CONFIG_DIR}/config.env"
SERVICE_NAME="runready-kiosk.service"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

echo "RunReady Operations display kiosk — install"
echo "============================================"
echo ""

echo "Installing packages..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  chromium-browser chromium \
  unclutter \
  curl \
  python3 \
  x11-xserver-utils \
  2>/dev/null || DEBIAN_FRONTEND=noninteractive apt-get install -y \
  chromium \
  unclutter \
  curl \
  python3 \
  x11-xserver-utils

echo "Copying kiosk files to ${INSTALL_DIR}..."
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cp -R "$SCRIPT_DIR/"* "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR"/*.sh

mkdir -p "$CONFIG_DIR" /var/lib/runready-kiosk /var/log/runready-kiosk /var/run/runready-kiosk

if [[ ! -f "$CONFIG_FILE" ]]; then
  cp "$INSTALL_DIR/config.example.env" "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
  echo ""
  echo "Created ${CONFIG_FILE}"
  echo "Edit it with your display token, URL, and organization ID before starting the service."
else
  echo "Keeping existing ${CONFIG_FILE}"
fi

chown -R root:root "$INSTALL_DIR" "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

# systemd unit
cat >/etc/systemd/system/${SERVICE_NAME} <<EOF
[Unit]
Description=RunReady Operations wall display kiosk
After=graphical.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/$(logname 2>/dev/null || echo pi)/.Xauthority
Environment=RUNREADY_KIOSK_CONFIG=${CONFIG_FILE}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/runready-kiosk-watchdog.sh
Restart=always
RestartSec=5

[Install]
WantedBy=graphical.target
EOF

systemctl daemon-reload

echo ""
echo "Install complete."
echo ""
echo "Next steps:"
echo "  1. Edit ${CONFIG_FILE}"
echo "     - Paste values from ops.runready.app → CAD Settings → Open display setup"
echo "     - RUNREADY_AUTH_TOKEN, RUNREADY_DISPLAY_URL, RUNREADY_ORGANIZATION_ID"
echo ""
echo "  2. Enable auto-login to desktop (raspi-config → System Options → Boot / Auto Login)"
echo ""
echo "  3. Disable screen blanking in desktop preferences (already handled at runtime via xset)"
echo ""
echo "  4. Start the kiosk:"
echo "     sudo systemctl enable --now ${SERVICE_NAME}"
echo ""
echo "  5. View logs:"
echo "     sudo journalctl -u ${SERVICE_NAME} -f"
echo "     tail -f /var/log/runready-kiosk/watchdog.log"
echo ""
echo "See ${INSTALL_DIR}/README.md for full documentation."
