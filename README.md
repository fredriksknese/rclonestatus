# rclonestatus

Two-way OneDrive sync with `rclone bisync`, run on a systemd user timer, with a GNOME Shell top-bar status icon.

- `onedrive-sync` – sync script; writes `~/.local/state/rclone/onedrive-status.ini` for the status icon and only notifies on failure
- `gnome-extension/` – GNOME Shell 48 extension (`onedrive-sync@fredrik.local`)
- `systemd/` – user service and timer

## Install

```sh
install -m 755 onedrive-sync ~/bin/onedrive-sync
cp systemd/onedrive-sync.{service,timer} ~/.config/systemd/user/
systemctl --user daemon-reload && systemctl --user enable --now onedrive-sync.timer

ext=~/.local/share/gnome-shell/extensions/onedrive-sync@fredrik.local
mkdir -p "$ext" && cp gnome-extension/* "$ext/"
gnome-extensions enable onedrive-sync@fredrik.local   # after restarting GNOME Shell
```

The first run needs `onedrive-sync --resync` to establish the bisync baseline.
