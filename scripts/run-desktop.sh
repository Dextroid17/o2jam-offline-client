#!/bin/bash
# Launch the native (Wine-free) O2Jam client as a NORMAL DESKTOP APP window on
# the real session, and make sure it lands on the Gigabyte (DP-2 = primary),
# never on the ASUS PB287Q (DP-1).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CX="${O2JAM_CXO2:-$HOME/o2jam/native/CXO2}"
LOG=/tmp/native-desktop.log
PY="${O2JAM_PY:-$HOME/o2jam/tools/venv/bin/python}"
XA="${XAUTHORITY:-}"
[ -f "$XA" ] || XA=$(ls -t /run/user/"$(id -u)"/xauth_* 2>/dev/null | head -1)

echo "=== stopping the headless/browser instances (avoid CPU hog + double audio) ==="
if xpra list 2>/dev/null | grep -q "LIVE session at :90"; then
  xpra stop :90 >/dev/null 2>&1 && echo "  browser session :90 stopped"
fi
pkill -x OTwo 2>/dev/null && echo "  previous native clients stopped" || echo "  no stray native client"

echo "=== launching native client on the desktop (DISPLAY=:0, X11 window) ==="
echo "  XAUTHORITY=$XA"
cd "$CX" || exit 1
nohup env -u WAYLAND_DISPLAY DISPLAY=:0 XAUTHORITY="$XA" SDL_VIDEODRIVER=x11 \
  ./bin/linux/Release/OTwo > "$LOG" 2>&1 &
sleep 20

echo "=== launch the fullscreen keeper (real EWMH fullscreen -> KWin covers the Gigabyte) ==="
pkill -f fullscreen-keep.py 2>/dev/null
nohup env DISPLAY=:0 XAUTHORITY="$XA" "$PY" "$HERE/fullscreen-keep.py" :0 \
  > /tmp/o2-fullscreen.log 2>&1 &
sleep 4
sed 's/^/  /' /tmp/o2-fullscreen.log 2>/dev/null | tail -4

echo "=== render mode ==="
echo "  borderless fullscreen on the primary (Gigabyte) output, rendered 1:1 with the window"

echo "=== process ==="
pgrep -x OTwo >/dev/null && ps -o pid,%cpu,%mem,rss,etime -p "$(pgrep -x OTwo | head -1)" | sed 's/^/  /' || echo "  NOT RUNNING ❌"

echo "=== window geometry on the desktop (:0 X11 / XWayland) ==="
GIG="$(XAUTHORITY="$XA" DISPLAY=:0 xrandr --query 2>/dev/null | grep ' connected primary' | grep -oE '[0-9]+x[0-9]+\+[0-9]+\+[0-9]+' | head -1)"
echo "  primary monitor X11 rect: ${GIG:-<unknown>}"
XAUTHORITY="$XA" DISPLAY=:0 GIG="$GIG" "$PY" - <<'EOF'
from Xlib import display
d = display.Display(':0')
found = []
def walk(w, dep=0):
    try:
        for c in w.query_tree().children:
            g = c.get_geometry()
            n = c.get_wm_name() or ''
            if g.width > 100 and g.height > 80 and ('JAM' in n.upper() or 'o2' in n.lower() or g.width > 600):
                # absolute coords
                try:
                    t = c.translate_coords(d.screen().root, 0, 0)
                    ax, ay = -t.x, -t.y
                except Exception:
                    ax, ay = g.x, g.y
                found.append((c, n, g, ax, ay))
            walk(c, dep + 1)
    except Exception:
        pass
walk(d.screen().root)
for c, n, g, ax, ay in found:
    if g.width < 400:
        continue
    import os, re
    m = re.match(r'(\d+)x(\d+)\+(\d+)\+(\d+)', os.environ.get('GIG', ''))
    if m:
        gw, gh, gx, gy = (int(v) for v in m.groups())
        covers = ax <= gx and ay <= gy and (ax + g.width) >= (gx + gw) and (ay + g.height) >= (gy + gh)
        where = 'covers the Gigabyte fully ✅' if covers else f'does NOT cover the Gigabyte ❌ (dx={ax-gx:+d} dy={ay-gy:+d})'
    else:
        where = '?'
    print(f'  0x{c.id:x} {g.width}x{g.height} at ({ax},{ay})  {n!r}  -> {where}')
if not found:
    print('  (no game window found yet)')
EOF
echo "=== game log ==="
tail -6 "$LOG" | sed 's/^/  /'
echo "=== DONE ==="
