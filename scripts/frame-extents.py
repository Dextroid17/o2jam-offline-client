#!/usr/bin/env python3
"""Print the O2Jam (OTwo) window's _NET_FRAME_EXTENTS as "left top right bottom".

These are the pixels KWin's decoration adds AROUND the client area (titlebar = the "top"
value).  They only exist once the window is mapped, so call this AFTER the client is up.
Prints "0 0 0 0" when the window is missing or has no frame.
"""
import sys
from Xlib import display, X


def find(d):
    for win in d.screen().root.query_tree().children:
        try:
            cls = win.get_wm_class()
        except Exception:
            continue
        if cls and any('O2' in str(c).upper() or 'JAM' in str(c).upper() for c in cls):
            return win
    return None


def main():
    d = display.Display(':0')
    win = find(d)
    if win is None:
        print("0 0 0 0")
        return 0
    fe = win.get_full_property(d.intern_atom('_NET_FRAME_EXTENTS'), X.AnyPropertyType)
    vals = list(fe.value) if fe else [0, 0, 0, 0]
    while len(vals) < 4:
        vals.append(0)
    # _NET_FRAME_EXTENTS order is left, right, TOP, bottom - print left top right bottom
    l, r, t, b = (int(v) for v in vals[:4])
    print(f"{l} {t} {r} {b}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
