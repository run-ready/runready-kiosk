# RunReady Operations wall display kiosk

Turn a Raspberry Pi into a hands-off display for the [Operations web UI](https://ops.runready.app) — Monitor CAD or Calendar view — with automatic auth refresh and reload when you deploy updates.

## What it does

- Opens **Chromium in full-screen kiosk mode** on a single URL (`/cad` or `/calendar`)
- **Authenticates** as a dedicated display user via a JWT stored in config (injected before the app loads)
- **Refreshes tokens** every 6 hours via `POST /auth/verify` (same as the web app; supports expired tokens)
- **Detects new deployments** by hashing `index.html` and reloads the browser when you push ops UI updates
- **Restarts the browser** if it crashes or the Pi reboots (systemd service)
- **Hides the mouse cursor** after 5 seconds (`unclutter`)
- **Prevents screen blanking** (`xset`)

## Prerequisites

- Raspberry Pi 4 (or newer) with Raspberry Pi OS Desktop
- Display connected via HDMI
- Network access to `ops.runready.app` and `api.runready.app`
- A **dedicated RunReady user** per display (recommended: one Google/email account per department wall)

## Quick start

### 1. Create a display user

For each wall display, create or designate a RunReady user (e.g. `greencastle-display@yourdomain.com`):

1. Sign in once at https://ops.runready.app with that account
2. Link the correct account / organization if prompted
3. Open **CAD** or **Calendar**, pick the correct org in the header, and configure view settings (kiosk mode for calendar, CAD filters, etc.)
4. Open **CAD → Settings (gear) → Open display setup** (or go to `/display-setup`)
5. Copy the auth token, organization ID, and full `config.env` block onto the Pi
6. Note the URL path you want (`/cad` or `/calendar`) — choose it on the setup page

The Pi will reuse org/view preferences saved in the Chromium profile after the first successful load.

### 2. Install on the Pi

Customer Pis do **not** need the private RunReady monorepo. Use the **public install bundle** (recommended) or copy files from your laptop.

#### Option A — One command on the Pi (recommended)

Open **Raspberry Pi Connect → Remote Shell** (or SSH) on the Pi and run:

```bash
curl -fsSL https://raw.githubusercontent.com/run-ready/runready-kiosk/main/bootstrap-install.sh | sudo bash
```

This downloads [github.com/run-ready/runready-kiosk](https://github.com/run-ready/runready-kiosk) (public), installs packages, and copies scripts to `/opt/runready-kiosk`. No git required.

If `git` is installed, you can clone instead:

```bash
git clone --depth 1 https://github.com/run-ready/runready-kiosk.git /tmp/runready-kiosk
cd /tmp/runready-kiosk
sudo ./install.sh
```

#### Option B — Copy from your laptop (private network / no outbound GitHub)

On your **Mac** (RunReady repo), create a tarball and copy over SSH (Pi Connect Remote Shell uses the same SSH as `scp`):

```bash
tar czf /tmp/runready-kiosk.tgz -C scripts kiosk
scp /tmp/runready-kiosk.tgz pi@PI_HOST:~/
```

On the Pi:

```bash
cd ~
tar xzf runready-kiosk.tgz
cd kiosk
sudo ./install.sh
```

#### Option C — USB drive

On your Mac: `tar czf /Volumes/YOUR_USB/runready-kiosk.tgz -C scripts kiosk`

On the Pi: extract, `cd kiosk`, `sudo ./install.sh` (see Option B for tar steps).

#### Maintainers — publish updates to the public repo

After changing files under `scripts/kiosk/` in the RunReady monorepo:

```bash
./scripts/kiosk/publish-public-repo.sh
```

This syncs to [run-ready/runready-kiosk](https://github.com/run-ready/runready-kiosk) so customer one-liners stay current.

### 3. Configure

```bash
sudo nano /etc/runready-kiosk/config.env
```

Required settings:

```bash
RUNREADY_AUTH_TOKEN="eyJ..."
RUNREADY_DISPLAY_URL="https://ops.runready.app/cad"
RUNREADY_ORGANIZATION_ID="your-org-uuid"
```

For calendar wall displays:

```bash
RUNREADY_DISPLAY_URL="https://ops.runready.app/calendar"
RUNREADY_CALENDAR_KIOSK_MODE="true"
```

Verify before starting:

```bash
sudo /opt/runready-kiosk/verify-config.sh
```

### 4. Auto-login (recommended)

So the kiosk starts after power loss without someone logging into the desktop:

```bash
sudo raspi-config
# System Options → Boot / Auto Login → Desktop Autologin
```

### 5. Start the service

```bash
sudo systemctl enable --now runready-kiosk.service
```

Logs:

```bash
sudo journalctl -u runready-kiosk.service -f
tail -f /var/log/runready-kiosk/watchdog.log
```

## Updating display credentials

If you rotate the display user or the token is revoked:

1. Sign in as the display user in a normal browser and copy a fresh `auth_token`
2. Update `/etc/runready-kiosk/config.env`
3. Restart: `sudo systemctl restart runready-kiosk.service`

The watchdog also refreshes tokens automatically and writes them back to `config.env`.

## After you deploy ops UI updates

No action needed on the Pi. The watchdog checks `index.html` every 5 minutes (configurable) and reloads Chromium when the hash changes.

To force an immediate reload:

```bash
sudo systemctl restart runready-kiosk.service
```

## Configuration reference

| Variable | Default | Description |
|----------|---------|-------------|
| `RUNREADY_AUTH_TOKEN` | *(required)* | JWT from ops localStorage |
| `RUNREADY_DISPLAY_URL` | `https://ops.runready.app/cad` | Page to open |
| `RUNREADY_ORGANIZATION_ID` | *(required)* | Org UUID for header selection |
| `RUNREADY_CALENDAR_KIOSK_MODE` | `true` | Set `calendarOps_kioskMode` in localStorage |
| `RUNREADY_CHECK_DEPLOY_INTERVAL_SEC` | `300` | How often to check for new deploys |
| `RUNREADY_TOKEN_REFRESH_INTERVAL_SEC` | `21600` | How often to refresh auth (6h) |
| `RUNREADY_BROWSER_HEALTH_INTERVAL_SEC` | `60` | How often to check browser process |
| `RUNREADY_HIDE_CURSOR` | `true` | Use unclutter to hide pointer |
| `RUNREADY_CHROMIUM_PROFILE_DIR` | `/var/lib/runready-kiosk/chromium` | Persistent browser profile |

## How authentication works

The Operations app stores its session in `localStorage.auth_token` and validates on load via `/auth/verify`. The kiosk uses a small Chromium extension that runs at `document_start` and sets:

- `auth_token`
- `selectedOrganizationId`
- `calendarOps_kioskMode` (calendar displays)

Because injection happens before React loads, the app sees a normal signed-in session. The verify endpoint also **re-issues expired tokens** (up to the limits in the auth Lambda), so displays stay signed in across months of uptime as long as the user account remains active.

## Troubleshooting

| Symptom | Check |
|---------|--------|
| Login screen on display | Run `verify-config.sh`; token may be invalid or user disabled |
| Blank screen | `journalctl -u runready-kiosk`; ensure desktop autologin and `DISPLAY=:0` |
| Wrong organization | Update `RUNREADY_ORGANIZATION_ID` and restart |
| Maps not loading | Maps key is baked at deploy time — not a Pi issue |
| Cursor visible | Install `unclutter`: `sudo apt install unclutter` |

## Security notes

- Treat `/etc/runready-kiosk/config.env` like a password file (`chmod 600`); it contains a long-lived JWT
- Use a **dedicated display user** with minimal permissions — not a personal admin account
- Physical access to the Pi gives access to the token; lock down USB and shell access on wall-mounted units

## File layout (after install)

```
/opt/runready-kiosk/          # Scripts and extension
/etc/runready-kiosk/config.env
/var/lib/runready-kiosk/      # Browser profile, deploy hash
/var/log/runready-kiosk/      # watchdog, token, browser logs
```
