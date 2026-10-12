# rclonestatus

Two-way OneDrive sync with `rclone bisync`, run on a systemd user timer, with a GNOME Shell top-bar status icon.

- `onedrive-sync` – sync script; writes `~/.local/state/rclone/onedrive-status.ini` for the status icon and only notifies on failure
- `gnome-extension/` – GNOME Shell 48 extension (`onedrive-sync@fredrik.local`)
- `systemd/` – user service and timer
- `setup.sh` – installer (rclone remote, filters, script, units, extension, initial resync)

## Requirements

- `rclone`, systemd (user session)
- GNOME Shell 48 for the status icon (optional)
- `notify-send` (`libnotify-bin`) for failure notifications (optional)

## Install

```sh
git clone https://github.com/fredriksknese/rclonestatus.git
cd rclonestatus
./setup.sh              # interactive
./setup.sh -y           # defaults, no questions
./setup.sh --help       # all options (remote name, interval, --no-extension, --uninstall, …)
```

It creates the rclone remote if missing, writes a default filters file, installs the script, units and extension, runs the initial `--resync` if there's no baseline yet, and enables the timer. Files sync to `~/OneDrive`; filters live in `~/.config/rclone/onedrive-bisync-filters.txt`.

To uninstall (keeps the rclone remote, filters and synced data):

```sh
./setup.sh --uninstall
```

Manual install:

```sh
install -m 755 onedrive-sync ~/bin/onedrive-sync
cp systemd/onedrive-sync.{service,timer} ~/.config/systemd/user/
systemctl --user daemon-reload && systemctl --user enable --now onedrive-sync.timer

ext=~/.local/share/gnome-shell/extensions/onedrive-sync@fredrik.local
mkdir -p "$ext" && cp gnome-extension/* "$ext/"
gnome-extensions enable onedrive-sync@fredrik.local   # after restarting GNOME Shell
```

The first run needs `onedrive-sync --resync` to establish the bisync baseline.
