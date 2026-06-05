#!/usr/bin/env bash
# Download the public RunReady kiosk bundle and run install.sh (no git or monorepo required).
#
# One-liner on a Raspberry Pi (Pi Connect → Remote Shell):
#   curl -fsSL https://raw.githubusercontent.com/run-ready/runready-kiosk/main/bootstrap-install.sh | sudo bash
#
# Or after cloning the public repo:
#   sudo ./bootstrap-install.sh

set -euo pipefail

PUBLIC_TARBALL_URL="${RUNREADY_KIOSK_TARBALL_URL:-https://github.com/run-ready/runready-kiosk/archive/refs/heads/main.tar.gz}"
WORKDIR="${RUNREADY_KIOSK_BOOTSTRAP_DIR:-/tmp/runready-kiosk-bootstrap.$$}"
ARCHIVE="${WORKDIR}/runready-kiosk.tgz"
EXTRACTED=""

cleanup() {
  if [[ -n "$EXTRACTED" && -d "$EXTRACTED" ]]; then
    rm -rf "$WORKDIR"
  fi
}
trap cleanup EXIT

mkdir -p "$WORKDIR"

echo "Downloading RunReady kiosk from ${PUBLIC_TARBALL_URL}..."
curl -fsSL "$PUBLIC_TARBALL_URL" -o "$ARCHIVE"

echo "Extracting..."
tar xzf "$ARCHIVE" -C "$WORKDIR"
EXTRACTED="$(find "$WORKDIR" -mindepth 1 -maxdepth 1 -type d | head -1)"
if [[ -z "$EXTRACTED" || ! -f "${EXTRACTED}/install.sh" ]]; then
  echo "ERROR: Could not find install.sh in downloaded archive." >&2
  exit 1
fi

chmod +x "${EXTRACTED}"/*.sh 2>/dev/null || true

echo "Running install.sh..."
if [[ "${EUID}" -eq 0 ]]; then
  exec "${EXTRACTED}/install.sh"
else
  exec sudo "${EXTRACTED}/install.sh"
fi
