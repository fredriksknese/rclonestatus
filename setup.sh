#!/bin/bash
# Set up rclone OneDrive bisync, the systemd user timer and the GNOME status extension.
# Run without arguments for an interactive install, or pass options (see --help).
set -euo pipefail

SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
EXT_UUID=onedrive-sync@fredrik.local
EXT_DIR="$HOME/.local/share/gnome-shell/extensions/$EXT_UUID"
UNIT_DIR="$HOME/.config/systemd/user"
FILTERS="$HOME/.config/rclone/onedrive-bisync-filters.txt"
SYNC_DIR="$HOME/OneDrive"  # also hardcoded in onedrive-sync and the extension

# Defaults (overridden by options or interactive answers)
REMOTE=OneDrive
BIN_DIR="$HOME/bin"
INTERVAL=6h
CONFIGURE_REMOTE=auto  # auto: create the remote only if it is missing
RESYNC=auto            # auto: resync only if no bisync baseline exists
EXTENSION=auto         # auto: install if GNOME Shell is present
ENABLE_TIMER=yes
INTERACTIVE=auto
UNINSTALL=no

usage() {
  cat <<EOF
Usage: $0 [options]

With no options (and a terminal), the setup asks for each setting interactively.

Options:
  -r, --remote NAME      rclone remote name (default: $REMOTE)
  -b, --bin-dir DIR      where to install onedrive-sync (default: $BIN_DIR)
  -i, --interval SPAN    time between syncs, systemd timespan (default: $INTERVAL)
      --configure        always run rclone config for the remote (re-authenticate)
      --no-configure     never touch the rclone remote
      --resync           run the initial 'onedrive-sync --resync' now
      --no-resync        skip the initial resync
      --extension        install the GNOME Shell extension
      --no-extension     don't install the GNOME Shell extension
      --no-timer         install the units but don't enable the timer
      --interactive      ask for each setting even when options are given
  -y, --yes              accept defaults without asking
      --uninstall        remove the script, units and extension (keeps config and data)
  -h, --help             show this help
EOF
}

die() { echo "error: $*" >&2; exit 1; }
info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }

ask() { # var prompt
  local reply
  read -rp "$2 [${!1}]: " reply
  [ -n "$reply" ] && printf -v "$1" '%s' "$reply"
  return 0
}

confirm() { # prompt default(y/n)
  local reply hint=y/N
  [ "$2" = y ] && hint=Y/n
  read -rp "$1 [$hint]: " reply
  reply=${reply:-$2}
  [[ $reply =~ ^[Yy] ]]
}

need_arg() { [ $# -ge 2 ] && [ -n "$2" ] || die "$1 requires an argument"; }

[ $# -eq 0 ] && [ -t 0 ] && INTERACTIVE=yes
while [ $# -gt 0 ]; do
  case $1 in
    -r|--remote)    need_arg "$@"; REMOTE=$2; shift ;;
    -b|--bin-dir)   need_arg "$@"; BIN_DIR=$2; shift ;;
    -i|--interval)  need_arg "$@"; INTERVAL=$2; shift ;;
    --configure)    CONFIGURE_REMOTE=yes ;;
    --no-configure) CONFIGURE_REMOTE=no ;;
    --resync)       RESYNC=yes ;;
    --no-resync)    RESYNC=no ;;
    --extension)    EXTENSION=yes ;;
    --no-extension) EXTENSION=no ;;
    --no-timer)     ENABLE_TIMER=no ;;
    --interactive)  INTERACTIVE=yes ;;
    -y|--yes)       INTERACTIVE=no ;;
    --uninstall)    UNINSTALL=yes ;;
    -h|--help)      usage; exit 0 ;;
    *)              usage >&2; die "unknown option: $1" ;;
  esac
  shift
done
[ "$INTERACTIVE" = yes ] || INTERACTIVE=no
[ "$INTERACTIVE" = yes ] && ! [ -t 0 ] && die "--interactive needs a terminal"

# --- Uninstall ---------------------------------------------------------------
if [ "$UNINSTALL" = yes ]; then
  if [ "$INTERACTIVE" = yes ]; then
    ask BIN_DIR "Directory onedrive-sync was installed to"
    confirm "Remove onedrive-sync, its systemd units and the GNOME extension?" n || exit 0
  fi
  info "Disabling timer"
  systemctl --user disable --now onedrive-sync.timer 2>/dev/null || true
  systemctl --user stop onedrive-sync.service 2>/dev/null || true
  rm -f "$UNIT_DIR/onedrive-sync.service" "$UNIT_DIR/onedrive-sync.timer"
  systemctl --user daemon-reload
  info "Removing $BIN_DIR/onedrive-sync"
  rm -f "$BIN_DIR/onedrive-sync"
  if [ -d "$EXT_DIR" ]; then
    info "Removing GNOME extension"
    gnome-extensions disable "$EXT_UUID" 2>/dev/null || true
    rm -rf "$EXT_DIR"
  fi
  info "Done. Left in place: rclone remote, $FILTERS, ~/.local/state/rclone and $SYNC_DIR"
  exit 0
fi

# --- Prerequisites -----------------------------------------------------------
command -v rclone >/dev/null || die "rclone is not installed (e.g. 'sudo apt install rclone' or https://rclone.org/install/)"
command -v systemctl >/dev/null || die "systemd is required"
command -v notify-send >/dev/null || warn "notify-send not found; failure notifications won't show (install libnotify-bin)"

remote_exists() { rclone listremotes | grep -qx "$REMOTE:"; }
have_gnome() { command -v gnome-shell >/dev/null && command -v gnome-extensions >/dev/null; }
have_baseline() { compgen -G "$HOME/.cache/rclone/bisync/${REMOTE}_*.path1.lst" >/dev/null; }

# --- Interactive questions ---------------------------------------------------
if [ "$INTERACTIVE" = yes ]; then
  echo "OneDrive bisync setup — press Enter to accept the default in brackets."
  echo
  ask REMOTE "rclone remote name"
  if [ "$CONFIGURE_REMOTE" = auto ]; then
    if remote_exists; then
      confirm "Remote '$REMOTE:' exists. Re-authenticate it?" n && CONFIGURE_REMOTE=yes || CONFIGURE_REMOTE=no
    else
      confirm "Remote '$REMOTE:' not found. Create it now (opens a browser to sign in)?" y \
        && CONFIGURE_REMOTE=yes || CONFIGURE_REMOTE=no
    fi
  fi
  ask BIN_DIR "Install onedrive-sync to"
  ask INTERVAL "Time between syncs"
  if [ "$EXTENSION" = auto ] && have_gnome; then
    confirm "Install the GNOME Shell top-bar extension?" y && EXTENSION=yes || EXTENSION=no
  fi
  confirm "Enable the sync timer?" y && ENABLE_TIMER=yes || ENABLE_TIMER=no
  if [ "$RESYNC" = auto ]; then
    if have_baseline; then
      confirm "A bisync baseline exists. Run a --resync anyway?" n && RESYNC=yes || RESYNC=no
    else
      confirm "Run the initial --resync now (required before the first sync; may take a while)?" y \
        && RESYNC=yes || RESYNC=no
    fi
  fi
  echo
fi

[[ $REMOTE =~ ^[A-Za-z0-9_.-]+$ ]] || die "invalid remote name: $REMOTE"
systemd-analyze timespan "$INTERVAL" >/dev/null 2>&1 || die "invalid interval: $INTERVAL"
BIN_DIR=${BIN_DIR%/}

# --- rclone remote -----------------------------------------------------------
if [ "$CONFIGURE_REMOTE" = yes ] || { [ "$CONFIGURE_REMOTE" = auto ] && ! remote_exists; }; then
  if remote_exists; then
    info "Re-authenticating rclone remote '$REMOTE:'"
    rclone config reconnect "$REMOTE:"
  else
    info "Creating rclone remote '$REMOTE:' (a browser window opens for sign-in)"
    rclone config create "$REMOTE" onedrive
  fi
fi
remote_exists || die "rclone remote '$REMOTE:' does not exist; run 'rclone config' or rerun with --configure"
[ "$(rclone config show "$REMOTE" | sed -n 's/^type *= *//p')" = onedrive ] \
  || warn "remote '$REMOTE:' is not of type onedrive (--onedrive-delta will be ignored)"
info "Checking access to '$REMOTE:'"
rclone lsf --max-depth 1 "$REMOTE:" >/dev/null || die "cannot list '$REMOTE:'; try --configure"

# --- Filters and sync directory ----------------------------------------------
mkdir -p "$SYNC_DIR" "$HOME/.local/state/rclone" "${FILTERS%/*}"
if [ ! -f "$FILTERS" ]; then
  info "Writing default filters to $FILTERS"
  cat > "$FILTERS" <<'EOF'
# rclone bisync filters for OneDrive. Run 'onedrive-sync --resync' after editing.
- .~lock.*#
- ~$*
- .Trash-*/**
- .directory
- desktop.ini
- Thumbs.db
- .DS_Store
EOF
fi

# --- Script and systemd units ------------------------------------------------
info "Installing onedrive-sync to $BIN_DIR"
mkdir -p "$BIN_DIR"
sed "s|bisync OneDrive: |bisync \"$REMOTE:\" |" "$SRC/onedrive-sync" > "$BIN_DIR/onedrive-sync.tmp"
chmod 755 "$BIN_DIR/onedrive-sync.tmp"
mv -f "$BIN_DIR/onedrive-sync.tmp" "$BIN_DIR/onedrive-sync"

info "Installing systemd user units (every $INTERVAL)"
mkdir -p "$UNIT_DIR"
sed "s|^ExecStart=.*|ExecStart=$BIN_DIR/onedrive-sync|; s|OneDrive <->|$REMOTE: <->|" \
  "$SRC/systemd/onedrive-sync.service" > "$UNIT_DIR/onedrive-sync.service"
sed "s|^OnUnitInactiveSec=.*|OnUnitInactiveSec=$INTERVAL|" \
  "$SRC/systemd/onedrive-sync.timer" > "$UNIT_DIR/onedrive-sync.timer"
systemctl --user daemon-reload

# --- GNOME extension ---------------------------------------------------------
if [ "$EXTENSION" = auto ]; then
  have_gnome && EXTENSION=yes || EXTENSION=no
fi
if [ "$EXTENSION" = yes ]; then
  have_gnome || die "GNOME Shell / gnome-extensions not found; rerun with --no-extension"
  info "Installing GNOME extension $EXT_UUID"
  mkdir -p "$EXT_DIR"
  cp "$SRC"/gnome-extension/* "$EXT_DIR/"
  shell_ver=$(gnome-shell --version | grep -oE '[0-9]+' | head -1)
  grep -q "\"$shell_ver\"" "$SRC/gnome-extension/metadata.json" \
    || warn "metadata.json doesn't list GNOME Shell $shell_ver; the extension may refuse to load"
  if ! gnome-extensions enable "$EXT_UUID" 2>/dev/null; then
    warn "log out and back in, then run: gnome-extensions enable $EXT_UUID"
  fi
fi

# --- Initial resync and timer ------------------------------------------------
# Resync before enabling the timer: a newly enabled timer whose OnBootSec has
# passed fires immediately, and a normal bisync fails without a baseline.
if [ "$RESYNC" = auto ]; then
  have_baseline && RESYNC=no || RESYNC=yes
fi
if [ "$RESYNC" = yes ]; then
  info "Running initial resync ($REMOTE: <-> $SYNC_DIR); log: ~/.local/state/rclone/onedrive-bisync.log"
  "$BIN_DIR/onedrive-sync" --resync || die "resync failed; see ~/.local/state/rclone/onedrive-bisync.log"
fi

if [ "$ENABLE_TIMER" = yes ]; then
  if [ "$RESYNC" = no ] && ! have_baseline; then
    warn "no bisync baseline yet; syncs will fail until you run: $BIN_DIR/onedrive-sync --resync"
  fi
  info "Enabling onedrive-sync.timer"
  systemctl --user enable --now onedrive-sync.timer
  systemctl --user list-timers onedrive-sync.timer --no-pager || true
fi

info "Done."
