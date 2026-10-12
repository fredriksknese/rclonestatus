import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import GObject from 'gi://GObject';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const STATE_DIR = GLib.build_filenamev([GLib.get_home_dir(), '.local', 'state', 'rclone']);
const STATUS_FILE = GLib.build_filenamev([STATE_DIR, 'onedrive-status.ini']);
const LOG_FILE = GLib.build_filenamev([STATE_DIR, 'onedrive-bisync.log']);
const SYNC_DIR = GLib.build_filenamev([GLib.get_home_dir(), 'OneDrive']);
const UNIT = 'onedrive-sync';

const ICONS = {
    ok: 'folder-remote-symbolic',
    syncing: 'view-refresh-symbolic',
    error: 'dialog-warning-symbolic',
};

function readStatus() {
    const kf = new GLib.KeyFile();
    try {
        kf.load_from_file(STATUS_FILE, GLib.KeyFileFlags.NONE);
        const get = key => {
            try {
                return kf.get_string('status', key);
            } catch {
                return '';
            }
        };
        return {
            state: get('state'),
            time: parseInt(get('time')) || 0,
            copied: get('copied') || '0',
            deleted: get('deleted') || '0',
            message: get('message'),
        };
    } catch {
        return null;
    }
}

function ago(seconds) {
    const d = Math.max(0, Math.floor(Date.now() / 1000) - seconds);
    if (d < 60)
        return 'just now';
    if (d < 3600)
        return `${Math.floor(d / 60)} min ago`;
    if (d < 86400)
        return `${Math.floor(d / 3600)} h ago`;
    return `${Math.floor(d / 86400)} d ago`;
}

function run(argv, callback) {
    try {
        const proc = Gio.Subprocess.new(argv,
            Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE);
        proc.communicate_utf8_async(null, null, (p, res) => {
            try {
                const [, out] = p.communicate_utf8_finish(res);
                callback?.(out.trim());
            } catch (e) {
                logError(e);
            }
        });
    } catch (e) {
        logError(e);
    }
}

const Indicator = GObject.registerClass(
class Indicator extends PanelMenu.Button {
    _init() {
        super._init(0.5, 'OneDrive Sync');

        this._icon = new St.Icon({icon_name: ICONS.ok, style_class: 'system-status-icon'});
        this.add_child(this._icon);

        this._stateItem = new PopupMenu.PopupMenuItem('', {reactive: false});
        this._detailItem = new PopupMenu.PopupMenuItem('', {reactive: false});
        this._nextItem = new PopupMenu.PopupMenuItem('', {reactive: false});
        this.menu.addMenuItem(this._stateItem);
        this.menu.addMenuItem(this._detailItem);
        this.menu.addMenuItem(this._nextItem);
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        this._syncItem = this.menu.addAction('Sync now',
            () => run(['systemctl', '--user', 'start', '--no-block', `${UNIT}.service`]));
        this.menu.addAction('Open OneDrive folder',
            () => Gio.AppInfo.launch_default_for_uri(GLib.filename_to_uri(SYNC_DIR, null), null));
        this.menu.addAction('Open log',
            () => Gio.AppInfo.launch_default_for_uri(GLib.filename_to_uri(LOG_FILE, null), null));

        this.menu.connect('open-state-changed', (_menu, open) => {
            if (open)
                this._refresh();
        });

        this._monitor = Gio.File.new_for_path(STATUS_FILE)
            .monitor_file(Gio.FileMonitorFlags.WATCH_MOVES, null);
        this._monitor.connect('changed', () => this._refresh());

        this._refresh();
    }

    _refresh() {
        const s = readStatus();
        const state = s?.state in ICONS ? s.state : 'ok';
        this._icon.icon_name = ICONS[state];
        this._syncItem.setSensitive(state !== 'syncing');

        if (!s) {
            this._stateItem.label.text = 'No sync has run yet';
            this._detailItem.visible = false;
        } else if (state === 'syncing') {
            this._stateItem.label.text = `Syncing… (started ${ago(s.time)})`;
            this._detailItem.visible = false;
        } else if (state === 'error') {
            this._stateItem.label.text = `Sync failed ${ago(s.time)}`;
            this._detailItem.label.text = s.message || 'See log for details';
            this._detailItem.visible = true;
        } else {
            this._stateItem.label.text = `Up to date — synced ${ago(s.time)}`;
            this._detailItem.label.text = `${s.copied} copied, ${s.deleted} deleted`;
            this._detailItem.visible = true;
        }

        this._nextItem.visible = false;
        run(['systemctl', '--user', 'show', `${UNIT}.timer`,
            '-p', 'NextElapseUSecRealtime', '--value'], next => {
            if (!next || !this._nextItem)
                return;
            this._nextItem.label.text = `Next sync: ${next}`;
            this._nextItem.visible = true;
        });
    }

    destroy() {
        this._monitor?.cancel();
        this._monitor = null;
        this._nextItem = null;
        super.destroy();
    }
});

export default class OneDriveSyncExtension extends Extension {
    enable() {
        this._indicator = new Indicator();
        Main.panel.addToStatusArea(this.uuid, this._indicator);
    }

    disable() {
        this._indicator?.destroy();
        this._indicator = null;
    }
}
