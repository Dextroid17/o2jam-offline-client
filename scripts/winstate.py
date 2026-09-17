#!/usr/bin/env python3
"""Report the real, measured state of the O2Jam client window on :0.

Prints geometry, absolute position, whether the WM/USER can resize it (max-size
clamp?), whether it is borderless, whether it is on the Gigabyte, and writes the
window rect to /tmp/win-rect.txt for cropping the screenshot.
"""
import os
import re
import sys

from Xlib import X, display

d = display.Display(':0')
root = d.screen().root
gigm = re.match(r'(\d+)x(\d+)\+(\d+)\+(\d+)', os.environ.get('GIG') or '')
want = os.environ.get('WANT', '')

found = []


def walk(w):
    try:
        for c in w.query_tree().children:
            try:
                g = c.get_geometry()
                n = c.get_wm_name() or ''
                if g.width > 200 and g.height > 150:
                    try:
                        t = c.translate_coords(root, 0, 0)
                        ax, ay = -t.x, -t.y
                    except Exception:
                        ax, ay = g.x, g.y
                    found.append((c, n, g, ax, ay))
            except Exception:
                pass
            walk(c)
    except Exception:
        pass


walk(root)
game = [f for f in found if 'JAM' in f[1].upper() or 'O2' in f[1].upper()]
if not game:
    print('  (no game window found)')
    sys.exit(0)

for c, n, g, ax, ay in game:
    geo = f'{g.width}x{g.height}'
    print(f"  window 0x{c.id:x}  {geo} at ({ax},{ay})  {n!r}")
    if want:
        print(f"    requested client area {want}: {'EXACT MATCH' if geo == want else 'MISMATCH (got ' + geo + ')'}")
    with open('/tmp/win-rect.txt', 'w') as fh:
        fh.write(f'{ax} {ay} {g.width} {g.height}\n')

    v = c.get_full_property(d.intern_atom('_NET_FRAME_EXTENTS'), X.AnyPropertyType)
    fe = list(v.value) if v else None
    print(f"    _NET_FRAME_EXTENTS (l,r,t,b) = {fe}  -> {'BORDERLESS (no frame)' if fe and sum(fe) == 0 else 'HAS A FRAME' if fe else '?'}")

    v = c.get_full_property(d.intern_atom('WM_NORMAL_HINTS'), 0)
    f = list(v.value) if v else []
    if f:
        flags = f[0]
        mn = (f[5], f[6]) if flags & 16 else None
        mx = (f[7], f[8]) if flags & 32 else None
        clamped = bool(mx) and mx[0] <= g.width and mx[1] <= g.height
        print(f"    WM_NORMAL_HINTS flags=0x{flags:x} min={mn} max={mx} -> RESIZE {'BLOCKED (max clamp)' if clamped else 'ALLOWED'}")
    else:
        print("    WM_NORMAL_HINTS: none -> RESIZE ALLOWED")

    v = c.get_full_property(d.intern_atom('_MOTIF_WM_HINTS'), 0)
    f = list(v.value) if v else []
    if len(f) >= 3:
        print(f"    _MOTIF_WM_HINTS functions=0x{f[1]:x} decorations={f[2]} -> MWM move={bool(f[1] & 4)} resize={bool(f[1] & 2)}")

    v = c.get_full_property(d.intern_atom('_NET_WM_STATE'), X.AnyPropertyType)
    st = [d.get_atom_name(a) for a in (v.value if v else [])]
    print(f"    _NET_WM_STATE: {st}  -> {'NOT fullscreen OK' if '_NET_WM_STATE_FULLSCREEN' not in st else 'FULLSCREEN'}")

    if gigm:
        gw, gh, gx, gy = (int(x) for x in gigm.groups())
        inside = ax >= gx and ay >= gy and ax + g.width <= gx + gw and ay + g.height <= gy + gh
        print(f"    Gigabyte (DP-2) rect {gw}x{gh}+{gx}+{gy}: {'ON THE GIGABYTE' if inside else 'WRONG MONITOR (dx=%+d dy=%+d)' % (ax - gx, ay - gy)}")
    print(f"    physical size on the panel: ~{round(g.width * 0.625)}x{round(g.height * 0.625)} px of 2560x1440")
