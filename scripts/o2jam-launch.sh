#!/bin/bash
# ============================================================================
#  O2Jam - desktop-shortcut entry point
#  Double-clicking the O2Jam icon (Desktop / app menu) lands here.
#
#  * game already running -> bring THAT window to the front.  It never restarts
#    the client, so a stray double-click can't cost you a song in progress.
#  * game not running     -> run the verified windowed launcher: 1080p on the
#    Gigabyte, normal titlebar with drag / minimise / maximise / close.
#
#  The shortcut runs WITHOUT a terminal, and the game needs ~25 s to load, so
#  every branch reports through a desktop notification - silence would look
#  like a broken shortcut.
# ============================================================================
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
PY="${O2JAM_PY:-$HOME/o2jam/tools/venv/bin/python}"
LOG=/tmp/o2jam-shortcut.log
ICON="$HOME/.local/share/icons/o2jam.png"

export DISPLAY="${DISPLAY:-:0}"
# The X authority file is recreated at every login (xauth_XXXXXX), so a stale
# name points at a file that no longer exists - always take the newest one.
if [ -z "${XAUTHORITY:-}" ] || [ ! -r "${XAUTHORITY:-/nonexistent}" ]; then
  export XAUTHORITY="$(ls -t /run/user/"$(id -u)"/xauth_* 2>/dev/null | head -1)"
fi
export XAUTHORITY

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a O2Jam -i "$ICON" "$1" "${2:-}" >/dev/null 2>&1 || true
}

if pgrep -x OTwo >/dev/null 2>&1; then
  # Already up: activate the existing window (un-iconify it first) rather than
  # starting a second client - run-windowed.sh *kills* any stray client, so
  # blindly re-running it would throw away the current session.
  "$PY" - <<'PYEOF' >/dev/null 2>&1 || true
import Xlib.display as D
from Xlib import X, protocol

d = D.Display()
root = d.screen().root
at = d.intern_atom


def find(w):
    try:
        for c in w.query_tree().children:
            try:
                n = c.get_wm_class()
                if n and n[1] == 'O2-JAM':
                    return c
            except Exception:
                pass
            r = find(c)
            if r:
                return r
    except Exception:
        pass
    return None


w = find(root)
if w:
    # un-minimise (IconicState=3 -> NormalState=1), then ask the WM to focus it
    w.send_event(protocol.event.ClientMessage(
        window=w, client_type=at('WM_CHANGE_STATE'), data=(32, [1, 0, 0, 0, 0])))
    root.send_event(protocol.event.ClientMessage(
        window=w, client_type=at('_NET_ACTIVE_WINDOW'),
        data=(32, [1, X.CurrentTime, 0, 0, 0])),
        event_mask=X.SubstructureRedirectMask | X.SubstructureNotifyMask)
    d.sync()
    print('activated', w.id)
PYEOF
  notify "O2Jam is already running" "Brought the game window to the front."
  exit 0
fi

notify "Starting O2Jam..." "1080p window on the Gigabyte - about 25 seconds."
bash "$HERE/run-windowed.sh" >"$LOG" 2>&1

if pgrep -x OTwo >/dev/null 2>&1; then
  notify "O2Jam is ready" "Window is up on the Gigabyte - 1080p, titlebar with all buttons."
  exit 0
fi

notify "O2Jam failed to start" "Nothing is running - see $LOG"
echo "launch failed, see $LOG" >&2
exit 1
