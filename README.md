# CalendarPi

Turn a Raspberry Pi and a TV into a wall display for a Google Calendar. One command sets up the Pi, and at
every boot it opens the calendar full-screen. You can show one calendar, or two at once, either on one
color-coded grid or taking turns.

Based on [pimylifeup: Raspberry Pi Google Calendar](https://pimylifeup.com/raspberry-pi-google-calendar/),
scripted and hardened for running unattended.

## What you need

- A Raspberry Pi 4 or 5, a screen, and a network connection.
- **Raspberry Pi OS (64-bit) with Desktop**, flashed with [Raspberry Pi Imager](https://www.raspberrypi.com/software/).
  In the Imager settings, set a username and password, Wi-Fi if you're not using Ethernet, and turn on SSH.
- A Google Calendar that is **public**. In Google Calendar, open the calendar's **Settings and sharing**, then
  under *Access permissions* tick **Make available to public**. For a private calendar, see
  [Private calendars](#private-calendars).

## Get your calendar's embed URL

1. In Google Calendar, open the calendar's **Settings and sharing**, then **Integrate calendar**.
2. Copy the URL from **Embed code**, which is the part inside `src="..."`. It looks like this:
   ```
   https://calendar.google.com/calendar/embed?src=abc123%40group.calendar.google.com&ctz=America%2FChicago
   ```

## Set up a Pi

Boot the Pi, open a terminal on it (or SSH in), and run the following. Paste your URL between the quotes:

```bash
sudo CAL_SRC="https://calendar.google.com/calendar/embed?src=..." bash -c "$(curl -fsSL https://raw.githubusercontent.com/ConfidentCyberLLC/CalendarPi/main/setup-calendar-pi.sh)" setup lobby-calendar
```

`lobby-calendar` is the hostname the Pi gets. Change it, or leave it off to keep the current name. When the
script says `Done`, run `sudo reboot`. The calendar comes up on its own at every boot.

Settings go between `sudo` and `bash`, as with `CAL_SRC` above. The script is safe to run again. It rebuilds
the page from the settings you give it each time, so repeat every setting you want to keep.

### Two calendars

Add `CAL_SRC2` with the second calendar's embed URL. By default both calendars share one month grid, and each
calendar's events get their own color. Google's embed doesn't show which color is which, so put the
colors in the title:

```bash
sudo CAL_SRC="https://...first..." CAL_SRC2="https://...second..." CAL_TITLE="Staff (purple) + Students (orange)" \
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/ConfidentCyberLLC/CalendarPi/main/setup-calendar-pi.sh)" setup
```

On busy days a combined grid can run out of room and show "2 more" in place of some events. If every event
must be visible, use `DUAL_MODE=flip` instead, which shows each calendar full-screen in turn.

### Settings

| Setting | Default | What it does |
|---|---|---|
| `CAL_SRC` | *required* | The calendar's embed URL, or an `index.html` copied from another calendar Pi to clone it exactly |
| `CAL_SRC2` | none | A second calendar |
| `DUAL_MODE` | `combined` | With two calendars, `combined` puts both on one grid and `flip` shows them in turn |
| `CAL_TITLE` | none | Title under the calendar, for example to say which color is which |
| `COLOR1` / `COLOR2` | `7986CB` / `F4511E` | Event colors in the combined view (hex, no `#`); the defaults are purple and orange |
| `FLIP` | `45` | Flip mode: seconds each calendar is shown |
| `ZOOM` | `1` | Screen scale. Raise it if text is too small: about `1.25` on a 1080p TV seen from across a room, `2`–`2.5` on a 4K TV |
| `REFRESH` | `600` | Seconds between page reloads, which also picks up calendar changes |
| `CONTROLS` | `0` | `1` shows Google's Today, arrow, print and Month buttons. They're hidden by default because nobody can click them on a wall display |
| `SLIM` | `1` | `0` keeps the services the kiosk doesn't need (see below) |
| `UPGRADE` | `1` | `0` skips installing OS updates and the latest Pi firmware |
| `KIOSK_USER` | user running `sudo` | The desktop user Chromium runs as |

For example, a 4K TV with a 5-minute reload:

```bash
sudo CAL_SRC="https://..." ZOOM=2 REFRESH=300 bash -c "$(curl -fsSL https://raw.githubusercontent.com/ConfidentCyberLLC/CalendarPi/main/setup-calendar-pi.sh)" setup
```

To change the zoom on a Pi that's already set up, edit `CAL_ZOOM=` in
`/etc/systemd/system/googlecalendar.service`, then run
`sudo systemctl daemon-reload && sudo systemctl restart googlecalendar`.

## What the script does

| Path | Purpose |
|---|---|
| `/opt/stacks/googlecalendar/index.html` | Full-screen page holding the calendar embed; reloads every `REFRESH` seconds |
| `/opt/stacks/googlecalendar/launch.sh` | Waits for the desktop (Wayland or X11), then starts Chromium in kiosk mode |
| `/etc/systemd/system/googlecalendar.service` | Starts the launcher at boot and restarts Chromium if it closes |

It also:

- installs all OS updates and the latest Pi EEPROM firmware (`UPGRADE=0` skips this);
- turns on desktop auto-login and turns off screen blanking;
- turns off what a calendar display doesn't need: Bluetooth (the service, plus the radio itself via
  `dtoverlay=disable-bt` in `config.txt`), printing (CUPS), NFS, ModemManager, and cloud-init (it only applies
  the Imager settings on first boot). Wi-Fi, SSH, Raspberry Pi Connect and `.local` hostnames stay on.
  `SLIM=0` skips this.

## Private calendars

If the calendar isn't public, Chromium on the Pi needs to be signed in to a Google account that can see it.
Before rebooting after setup, open Chromium on the Pi's desktop and sign in at https://calendar.google.com.
The kiosk uses the same Chromium profile, so the sign-in persists.

## Troubleshooting

- `journalctl -u googlecalendar -b` shows the kiosk's logs since boot.
- `sudo systemctl restart googlecalendar` reloads the kiosk.
- To reach the desktop, run `sudo systemctl stop googlecalendar`. Closing Chromium with `Alt+F4` doesn't work,
  because the service starts it again 5 seconds later.
- **"You need permission" or a Google sign-in page:** the calendar isn't public, and Chromium isn't signed in
  to an account that can see it. See [Private calendars](#private-calendars).
- **White screen with a "Choose password for new keyring" box:** that Pi was set up with an old version of
  the script. Run the current one again.
- **Text too small or too large:** change `ZOOM`.
