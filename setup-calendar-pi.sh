#!/usr/bin/env bash
# Turn a fresh Raspberry Pi OS (Desktop) install into a full-screen Google Calendar kiosk.
# Based on https://pimylifeup.com/raspberry-pi-google-calendar/
#
# One-liner on a fresh Pi:
#   sudo CAL_SRC="<embed URL>" bash -c "$(curl -fsSL https://raw.githubusercontent.com/ConfidentCyberLLC/CalendarPi/main/setup-calendar-pi.sh)" setup [hostname]
#
# Or, with the file copied over:
#   sudo CAL_SRC="<embed URL>" ./setup-calendar-pi.sh [hostname]
#
#   [hostname] optional, e.g. lobby-calendar
#
# Settings (put them before the command, as above):
#   CAL_SRC=<url|file>  required: the calendar's embed URL (the src="..." value from
#                       https://calendar.google.com/calendar/u/0/embedhelper), or an index.html
#                       copied from an existing calendar Pi (exact clone)
#   CAL_SRC2=<url>      optional second calendar
#   DUAL_MODE=<mode>    with two calendars: "combined" = one grid, color-coded (default)
#                                           "flip"     = show each in turn
#   CAL_TITLE=<text>    title under the calendar, e.g. "Staff (purple) + Students (orange)"
#   COLOR1/COLOR2=<hex> combined-view event colors (default 7986CB purple / F4511E orange)
#   FLIP=<seconds>      flip mode: how long each calendar shows (default 45)
#   CONTROLS=1          show Google's Today/arrows/print/Month buttons (default: hidden, nobody can click them)
#   REFRESH=<seconds>   page reload interval (default 600)
#   ZOOM=<factor>       screen scale (default 1; about 2-2.5 suits a 4K TV, 1.25 a 1080p TV viewed from afar)
#   KIOSK_USER=<user>   desktop user to run Chromium as (default: the user running sudo)
#   SLIM=0              keep Bluetooth, printing, NFS etc. (default 1 = turn them off)
#   UPGRADE=0           skip the OS + EEPROM firmware updates (default 1 = install them)
set -euo pipefail

SRC="${CAL_SRC:-}"
SRC2="${CAL_SRC2:-}"
TITLE="${CAL_TITLE:-}"
DUAL_MODE="${DUAL_MODE:-combined}"
COLOR1="${COLOR1:-7986CB}"
COLOR2="${COLOR2:-F4511E}"
FLIP="${FLIP:-45}"
CONTROLS="${CONTROLS:-0}"
NEW_HOSTNAME="${1:-}"
REFRESH="${REFRESH:-600}"
ZOOM="${ZOOM:-1}"
SLIM="${SLIM:-1}"
UPGRADE="${UPGRADE:-1}"
KIOSK_USER="${KIOSK_USER:-${SUDO_USER:-}}"
APP_DIR=/opt/stacks/googlecalendar
UNIT=/etc/systemd/system/googlecalendar.service

die() { echo "ERROR: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run with sudo"
[[ -n "$SRC" ]] || die "set CAL_SRC to your calendar's embed URL (see https://calendar.google.com/calendar/u/0/embedhelper)"
[[ -n "$KIOSK_USER" && "$KIOSK_USER" != root ]] || die "set KIOSK_USER to the desktop login user"
id "$KIOSK_USER" >/dev/null || die "user $KIOSK_USER does not exist"
KIOSK_UID=$(id -u "$KIOSK_USER")

export DEBIAN_FRONTEND=noninteractive
apt-get update
if [[ "$UPGRADE" == 1 ]]; then
    echo "==> Installing OS updates"
    apt-get full-upgrade -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold
    apt-get autoremove -y
    apt-get clean
    # New Pis can ship with old bootloader firmware; this stages the latest for the next reboot.
    if command -v rpi-eeprom-update >/dev/null; then
        echo "==> Updating EEPROM firmware"
        rpi-eeprom-update -a || true
    fi
fi

echo "==> Installing Chromium"
apt-get install -y chromium || apt-get install -y chromium-browser

echo "==> Writing $APP_DIR/index.html"
mkdir -p "$APP_DIR"
if [[ -f "$SRC" ]]; then
    install -m 644 "$SRC" "$APP_DIR/index.html"
else
    URLS=("$SRC" ${SRC2:+"$SRC2"})
    for url in "${URLS[@]}"; do
        [[ "$url" == https://calendar.google.com/* ]] || die "not a file or a calendar.google.com URL: $url"
    done
    if [[ -n "$SRC2" && "$DUAL_MODE" == combined ]]; then
        # Google's embed overlays every src= it is given; color= after each src sets its events' color.
        param() { sed -n "s/.*[?&]$2=\([^&]*\).*/\1/p" <<<"$1"; }
        ID1=$(param "$SRC" src); ID2=$(param "$SRC2" src); CTZ=$(param "$SRC" ctz)
        [[ -n "$ID1" && -n "$ID2" ]] || die "could not find src= in both calendar URLs"
        CTZ="${CTZ:-America/Phoenix}"
        URL="https://calendar.google.com/calendar/embed?src=$ID1&color=%23$COLOR1&src=$ID2&color=%23$COLOR2&ctz=${CTZ//\//%2F}"
        [[ -n "$TITLE" ]] && URL+="&title=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$TITLE")"
        URLS=("$URL")
        echo "    two calendars on one grid${TITLE:+, titled \"$TITLE\"}"
    elif [[ -n "$SRC2" ]]; then
        [[ "$DUAL_MODE" == flip ]] || die "DUAL_MODE must be combined or flip, not: $DUAL_MODE"
        echo "    two calendars, flipping every ${FLIP}s"
    fi
    IFRAMES=""
    for url in "${URLS[@]}"; do
        [[ "$CONTROLS" == 1 ]] || url+="&showNav=0&showPrint=0&showTabs=0"
        IFRAMES+="            <iframe class=\"responsive-iframe\" src=\"${url//&/&amp;}\" frameborder=\"0\" scrolling=\"no\"></iframe>"$'\n'
    done
    # In flip mode every calendar stays loaded and only the current one is visible, so flips are instant.
    cat > "$APP_DIR/index.html" <<EOF
<!doctype html>
<html lang="en-US">
    <head>
        <meta charset="utf-8">
        <meta http-equiv="refresh" content="$REFRESH">
        <title>Google Calendar</title>
        <style>
            body { margin: 0; }
            .container { position: relative; overflow: hidden; width: 100vw; height: 100vh; }
            .responsive-iframe { position: absolute; top: 0; left: 0; bottom: 0; right: 0;
                                 width: 100%; height: 100%; border: 0; visibility: hidden; }
            .responsive-iframe.active { visibility: visible; }
        </style>
    </head>
    <body>
        <div class="container">
$IFRAMES        </div>
        <script>
            const frames = document.querySelectorAll(".responsive-iframe");
            let i = 0;
            frames[0].classList.add("active");
            if (frames.length > 1) {
                setInterval(() => {
                    frames[i].classList.remove("active");
                    i = (i + 1) % frames.length;
                    frames[i].classList.add("active");
                }, $FLIP * 1000);
            }
        </script>
    </body>
</html>
EOF
    chmod 644 "$APP_DIR/index.html"
fi

echo "==> Writing launcher"
# Newer Pi OS images run Wayland (labwc), older ones X11; the guide's unit only
# handles X11. This waits for whichever desktop is up and points Chromium at it.
cat > "$APP_DIR/launch.sh" <<'EOF'
#!/usr/bin/env bash
RUN="/run/user/$(id -u)"
for _ in $(seq 1 60); do
    if [[ -S "$RUN/wayland-0" ]]; then
        export XDG_RUNTIME_DIR="$RUN" WAYLAND_DISPLAY=wayland-0
        PLATFORM=--ozone-platform=wayland; break
    elif [[ -S /tmp/.X11-unix/X0 ]]; then
        export DISPLAY=:0 XAUTHORITY="$HOME/.Xauthority"
        PLATFORM=--ozone-platform=x11; break
    fi
    sleep 2
done
BROWSER=$(command -v chromium || command -v chromium-browser)
exec "$BROWSER" $PLATFORM --force-device-scale-factor="${CAL_ZOOM:-1}" --password-store=basic --noerrdialogs --disable-infobars --no-first-run \
    --disable-session-crashed-bubble --check-for-update-interval=31536000 \
    --start-maximized --kiosk "file:///opt/stacks/googlecalendar/index.html"
EOF
chmod 755 "$APP_DIR/launch.sh"

echo "==> Writing $UNIT"
cat > "$UNIT" <<EOF
[Unit]
Description=Chromium Kiosk (Google Calendar)
Wants=graphical.target
After=graphical.target

[Service]
Type=simple
User=$KIOSK_USER
Group=$KIOSK_USER
Environment=HOME=/home/$KIOSK_USER
Environment=XDG_RUNTIME_DIR=/run/user/$KIOSK_UID
Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$KIOSK_UID/bus
Environment=CAL_ZOOM=$ZOOM
ExecStart=$APP_DIR/launch.sh
Restart=always
RestartSec=5

[Install]
WantedBy=graphical.target
EOF

echo "==> Desktop autologin + no screen blanking"
if command -v raspi-config >/dev/null; then
    raspi-config nonint do_boot_behaviour B4   # desktop, auto-login
    raspi-config nonint do_blanking 1          # 1 = disable blanking
fi

if [[ -n "$NEW_HOSTNAME" ]]; then
    echo "==> Setting hostname to $NEW_HOSTNAME"
    if command -v raspi-config >/dev/null; then
        raspi-config nonint do_hostname "$NEW_HOSTNAME"
    else
        hostnamectl set-hostname "$NEW_HOSTNAME"
    fi
fi

if [[ "$SLIM" == 1 ]]; then
    # Wi-Fi, SSH, Raspberry Pi Connect and avahi (.local names) stay on.
    echo "==> Turning off Bluetooth, printing, NFS, modem and cloud-init"
    for u in bluetooth.service hciuart.service \
             cups.service cups.socket cups.path cups-browsed.service \
             rpcbind.service rpcbind.socket nfs-blkmap.service nfs-client.target \
             ModemManager.service; do
        systemctl disable --now "$u" >/dev/null 2>&1 || true
    done
    systemctl mask bluetooth.service >/dev/null 2>&1 || true
    systemctl --global disable mpris-proxy.service >/dev/null 2>&1 || true   # Bluetooth media helper
    # cloud-init only applies the Pi Imager settings on first boot; that's done by now.
    [[ -d /etc/cloud ]] && touch /etc/cloud/cloud-init.disabled
    # Power the Bluetooth radio off in firmware (takes effect on reboot).
    CFG=/boot/firmware/config.txt
    if [[ -f "$CFG" ]] && ! grep -q '^dtoverlay=disable-bt' "$CFG"; then
        printf '\n[all]\ndtoverlay=disable-bt\n' >> "$CFG"
    fi
fi

systemctl daemon-reload
systemctl enable googlecalendar.service

echo
echo "Done. Reboot to start the kiosk:  sudo reboot"
echo "Logs:  journalctl -u googlecalendar -b"
