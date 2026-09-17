#!/bin/bash
# Launch the native (Wine-free) O2Jam client as a MOVEABLE, RESIZABLE WINDOW WITH A NORMAL
# TITLEBAR (drag it, minimise it, close it with the buttons) on the Gigabyte (DP-2 = primary)
# - never on the ASUS PB287Q (DP-1).  The titlebar itself is forced by setup-frame-rule.sh.
#
#   O2JAM_WINDOW=...   window client area: a preset, or raw X11 pixels
#                      presets: 1080p (DEFAULT) | 720p | screen (= whole Gigabyte work area,
#                      titlebar included)
#                      "1080p" means 1920x1080 REAL screen pixels, i.e. 3072x1728 in this
#                      desktop's 1.6x XWayland coordinate space (see SCALE below); it covers
#                      75% of the panel, leaving room to move the window around
#   O2JAM_POS=x,y      top-left of the VISIBLE FRAME, i.e. the titlebar corner (default:
#                      centred on the Gigabyte with the titlebar included in the maths)
#   O2JAM_FRAME_TOP=n  titlebar height in X11 px, used to budget the launch-time geometry
#                      (default 56 = the Breeze titlebar here; the real value is measured
#                      from _NET_FRAME_EXTENTS and applied at snap time)
#
# No EWMH fullscreen keeper in this mode: the window is WM-managed, so the user can drag it by
# the titlebar and stretch its edges/corners.  True fullscreen stays run-desktop.sh.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CX="${O2JAM_CXO2:-$HOME/o2jam/native/CXO2}"
LOG=/tmp/native-windowed.log
PY="${O2JAM_PY:-$HOME/o2jam/tools/venv/bin/python}"
# The X authority file is recreated at every login (xauth_XXXXXX), so a hard-coded name goes
# stale - keep the newest one that actually authorises.
XA="${XAUTHORITY:-}"
if [ -z "$XA" ] || ! DISPLAY=:0 XAUTHORITY="$XA" "$PY" -c "from Xlib import display; display.Display(':0')" >/dev/null 2>&1; then
  for f in $(ls -t /run/user/1000/xauth_* 2>/dev/null); do
    if DISPLAY=:0 XAUTHORITY="$f" "$PY" -c "from Xlib import display; display.Display(':0')" >/dev/null 2>&1; then XA="$f"; break; fi
  done
fi
export DISPLAY=:0 XAUTHORITY="$XA"
WANT="${O2JAM_WINDOW:-1080p}"

echo "=== stopping anything from the previous run ==="
pkill -x OTwo 2>/dev/null && echo "  previous client stopped" || echo "  no stray client"
pkill -f "fullscreen-keep[.]py" 2>/dev/null && echo "  fullscreen keeper stopped (it would force fullscreen)" || echo "  keeper not running (good - this mode must not be fullscreen)"
sleep 1

echo "=== target monitor (Gigabyte = primary) ==="
GIG="$(xrandr --query 2>/dev/null | grep ' connected primary' | grep -oE '[0-9]+x[0-9]+\+[0-9]+\+[0-9]+' | head -1)"
echo "  primary X11 rect: ${GIG:-<unknown>}"

# X11 pixels are NOT screen pixels here: this desktop renders the 2560x1440 Gigabyte into a
# 4096x2304 X11 space (XWayland scale), so every X11 coordinate is 1.6 physical pixels.
# Size the presets in REAL screen pixels and convert, or the window comes out ~47% of the
# panel when you asked for 1080p. Override SCALE if the desktop scale ever changes.
SCALE="${O2JAM_X11_SCALE:-1.6}"
case "$WANT" in
  1080p) WANT="$("$PY" -c "print(f'{round(1920*$SCALE)}x{round(1080*$SCALE)}')")" ;;
  720p)  WANT="$("$PY" -c "print(f'{round(1280*$SCALE)}x{round(720*$SCALE)}')")" ;;
  screen|1440p|"") WANT="screen" ;;
  *)     : ;;   # raw X11 pixels, e.g. 2048x1152
esac

# The window now has a real KWin/Breeze titlebar, which sits ABOVE the client area and eats
# vertical space.  KWin only reports _NET_FRAME_EXTENTS once the window is mapped, so we budget
# the known titlebar height for the launch-time geometry and apply the measured value at snap
# time (place-window.py reads the real extents and positions the FRAME corner).
FT="${O2JAM_FRAME_TOP:-56}"
TOPFLUSH=0

# "screen" = the whole Gigabyte minus the strip KWin reserves for the taskbar AND minus the
# titlebar, so titlebar + game together fill the monitor and the panel never covers the game's
# bottom UI row.
if [ "$WANT" = "screen" ]; then
  TOPFLUSH=1
  WANT="$("$PY" - <<EOF
from Xlib import display, X
import re
m = re.match(r'(\d+)x(\d+)\+(\d+)\+(\d+)', "${GIG}" or '')
gw, gh, gx, gy = (int(v) for v in m.groups()) if m else (1920, 1080, 0, 0)
d = display.Display(':0')
wa = d.screen().root.get_full_property(d.intern_atom('_NET_WORKAREA'), X.AnyPropertyType)
bottom = min(gy + gh, wa.value[1] + wa.value[3]) if wa else gy + gh
print(f"{gw}x{bottom - gy - ${FT}}")
EOF
)"
  echo "  'screen' preset resolved to $WANT (game area; ${FT} X11 px budgeted for the titlebar)"
fi

echo "  window size  : $WANT in X11 px  =  $("$PY" -c "w,h='$WANT'.split('x');print(f'{round(int(w)/$SCALE)}x{round(int(h)/$SCALE)}')") real screen px  (scale $SCALE)"

# Centre the FRAME (titlebar + game) on the Gigabyte unless O2JAM_POS was given.  A window as
# tall as the usable area (the "screen" preset) is pinned flush to the top instead of centred,
# so its titlebar is always reachable.
if [ -z "${O2JAM_POS:-}" ]; then
  O2JAM_POS="$("$PY" - <<EOF
import os, re
from Xlib import display, X
m = re.match(r'(\d+)x(\d+)\+(\d+)\+(\d+)', "$GIG" or '')
w, h = (int(v) for v in "$WANT".split('x'))
ft = int("$FT")
if not m:
    print("0,0")
else:
    gw, gh, gx, gy = (int(v) for v in m.groups())
    fh = h + ft                      # what you actually see = game + titlebar
    d = display.Display(':0')
    wa = d.screen().root.get_full_property(d.intern_atom('_NET_WORKAREA'), X.AnyPropertyType)
    work_bottom = min(gy + gh, wa.value[1] + wa.value[3]) if wa else gy + gh
    if "$TOPFLUSH" == "1":
        fy = gy
    else:
        fy = gy + min(max(0, (gh - fh) // 2), max(0, work_bottom - (gy + fh)))
    print(f"{gx + max(0, (gw - w) // 2)},{fy}")
EOF
)"
fi
echo "  frame request : $WANT client at frame corner $O2JAM_POS (X11 px, relative to the X root)"

echo "=== launching native client (windowed: titlebar + minimise/maximise/close buttons) ==="
echo "  O2JAM_WINDOW=$WANT  O2JAM_POS=$O2JAM_POS (titlebar corner)"
echo "  note: O2JAM_BORDERLESS=1 below only means 'resizable client' in the patched client code -"
echo "        the titlebar is forced by the KWin rule from setup-frame-rule.sh, not by SFML."
cd "$CX" || exit 1
nohup env -u WAYLAND_DISPLAY O2JAM_BORDERLESS=1 O2JAM_WINDOW="$WANT" O2JAM_POS="$O2JAM_POS" \
  SDL_VIDEODRIVER=x11 ./bin/linux/Release/OTwo > "$LOG" 2>&1 &
sleep 22

# The close button must be fixed BEFORE the geometry snap below: the fix bounces the window
# through minimise/restore, and that bounce can make KWin re-place the window, so the snap has
# to come last.
echo "=== enabling the titlebar close (X) button ==="
"$PY" "$HERE/fix-close-button.py" | sed 's/^/  /'

echo "=== snapping the window to the exact requested geometry (frame corner aware) ==="
# Asking for a size through the WM leaves a frame-gravity offset (the window lands 60px
# off), so place it with _NET_MOVERESIZE_WINDOW + static gravity.  Static gravity means the
# CLIENT corner, and place-window.py adds the measured frame extents so the FRAME (what you
# see, titlebar included) lands exactly on the requested corner.
if pgrep -x OTwo >/dev/null; then
  "$PY" "$HERE/place-window.py" "${O2JAM_POS%,*}" "${O2JAM_POS#*,}" "${WANT%x*}" "${WANT#*x}" | sed 's/^/  /'
else
  echo "  client not running - skipping placement"
fi

echo "=== process ==="
pgrep -x OTwo >/dev/null && ps -o pid,%cpu,%mem,rss,etime -p "$(pgrep -x OTwo | head -1)" | sed 's/^/  /' || echo "  NOT RUNNING - see $LOG"

echo "=== ground truth: geometry, absolute position, RESIZABILITY, decoration ==="
WANT="$WANT" GIG="$GIG" "$PY" - <<'EOF'
from Xlib import display, X
import os, re
d = display.Display(':0')
root = d.screen().root
want = os.environ['WANT']
gigm = re.match(r'(\d+)x(\d+)\+(\d+)\+(\d+)', os.environ.get('GIG') or '')
found = []
def walk(w):
    try:
        for c in w.query_tree().children:
            g = c.get_geometry(); n = c.get_wm_name() or ''
            if g.width > 200 and g.height > 150:
                try:
                    t = c.translate_coords(root, 0, 0); ax, ay = -t.x, -t.y
                except Exception:
                    ax, ay = g.x, g.y
                found.append((c, n, g, ax, ay))
            walk(c)
    except Exception:
        pass
walk(root)
if not found:
    print('  (no game window found)')
for c, n, g, ax, ay in found:
    if 'O2' not in n.upper() and 'JAM' not in n.upper():
        continue
    geo = f'{g.width}x{g.height}'
    ok_size = geo == want
    line = f"  0x{c.id:x} {geo} at ({ax},{ay})  {n!r}"
    print(line)
    print(f"    requested size {want}: {'exact match OK' if ok_size else 'MISMATCH'}")
    # WM_NORMAL_HINTS -> is the max size clamped (=> not resizable)?
    try:
        v = c.get_full_property(d.intern_atom('WM_NORMAL_HINTS'), 0)
        f = list(v.value) if v else []
        if f:
            flags = f[0]
            mn = (f[5], f[6]) if flags & 16 else None
            mx = (f[7], f[8]) if flags & 32 else None
            print(f"    WM_NORMAL_HINTS flags=0x{flags:x} min={mn} max={mx}")
            print("    RESIZABLE: " + ("NO - max size is clamped " + str(mx) if mx and mx[0] <= g.width and mx[1] <= g.height else "YES - no max-size clamp, corners/edges will stretch it"))
        else:
            print("    WM_NORMAL_HINTS: <none> -> RESIZABLE: YES")
    except Exception as e:
        print(f"    WM_NORMAL_HINTS: read error {e}")
    # _MOTIF_WM_HINTS -> decorations off = borderless
    try:
        v = c.get_full_property(d.intern_atom('_MOTIF_WM_HINTS'), 0)
        f = list(v.value) if v else []
        dec = f[2] if len(f) > 2 else None
        fun = f[1] if len(f) > 1 else None
        print(f"    client asks for decorations={dec}; functions=0x{fun:x} move=bool{bool(fun & 4)} resize=bool{bool(fun & 2)} maximize=bool{bool(fun & 0x10)}")
        fe = c.get_full_property(d.intern_atom('_NET_FRAME_EXTENTS'), X.AnyPropertyType)
        actual = list(fe.value) if fe else None
        stripped = not actual or all(v == 0 for v in actual)
        # _NET_FRAME_EXTENTS order is left, right, TOP, bottom - element [1] is the RIGHT border,
        # so reading [1] reported a 0px titlebar on a window that demonstrably had one.
        _l, _r, _t, _b = (list(actual)[:4] if actual else [0, 0, 0, 0])
        print("    actual _NET_FRAME_EXTENTS=%s -> %s" % (actual,
              "NO TITLEBAR (frame stripped) - run setup-frame-rule.sh decorated and restart" if stripped
              else "TITLEBAR PRESENT (%d X11 px = %.0f real px) - drag it, minimise it, close it" % (_t, _t / 1.6)))
        # The buttons belong to the window manager, and it only offers the ones the client
        # declares: _NET_WM_ALLOWED_ACTIONS drives which buttons get drawn (the close bit comes
        # from MWM_FUNC_CLOSE in _MOTIF_WM_HINTS - see fix-close-button.py), while
        # WM_DELETE_WINDOW decides whether closing shuts the client down cleanly.
        try:
            prot = c.get_full_property(d.intern_atom('WM_PROTOCOLS'), X.AnyPropertyType)
            names = [d.get_atom_name(a) for a in (list(prot.value) if prot else [])]
        except Exception:
            names = []
        try:
            aa = c.get_full_property(d.intern_atom('_NET_WM_ALLOWED_ACTIONS'), X.AnyPropertyType)
            acts = [d.get_atom_name(a).replace('_NET_WM_ACTION_', '') for a in (list(aa.value) if aa else [])]
        except Exception:
            acts = []
        print("    titlebar buttons: minimise=%s | maximise=%s | close=%s" % (
            "OK" if 'MINIMIZE' in acts else "MISSING",
            "OK" if 'MAXIMIZE_HORZ' in acts else "MISSING",
            ("OK - drawn, and the client shuts down cleanly (advertises WM_DELETE_WINDOW)"
             if 'CLOSE' in acts and 'WM_DELETE_WINDOW' in names else
             "MISSING - MWM_FUNC_CLOSE not set; run fix-close-button.py" if 'CLOSE' not in acts else
             "OK - drawn, but no WM_DELETE_WINDOW: the WM would have to kill the client")))
    except Exception as e:
        print(f"    _MOTIF_WM_HINTS: read error {e}")
    # is it really inside the Gigabyte?
    if gigm:
        gw, gh, gx, gy = (int(v) for v in gigm.groups())
        inside = ax >= gx and ay >= gy and ax + g.width <= gx + gw and ay + g.height <= gy + gh
        print(f"    on the Gigabyte rect {gw}x{gh}+{gx}+{gy}: " + ("YES - fully inside OK" if inside else f"NO  (dx={ax-gx:+d} dy={ay-gy:+d})"))
    print(f"    fullscreen state: {[d.get_atom_name(a) for a in (c.get_full_property(d.intern_atom('_NET_WM_STATE'), X.AnyPropertyType).value if c.get_full_property(d.intern_atom('_NET_WM_STATE'), X.AnyPropertyType) else [])]}")
EOF

echo "=== per-monitor screenshots ==="
spectacle -b -n -f -o /tmp/win-run.png >/dev/null 2>&1
"$PY" - <<'EOF'
from PIL import Image
try:
    im = Image.open('/tmp/win-run.png'); print(f"  shot {im.size}")
    im.crop((0, 806, 4096, 3110)).resize((1024, 576)).save('/tmp/win-gig.png')
    im.crop((4096, 0, im.size[0], im.size[1])).resize((432, 768)).save('/tmp/win-asus.png')
    print("  crops: /tmp/win-gig.png (Gigabyte)  /tmp/win-asus.png (ASUS)")
except Exception as e:
    print(f"  screenshot crop failed: {e}")
EOF

echo "=== game log tail ==="
tail -5 "$LOG" | sed 's/^/  /'
echo "=== DONE ==="
