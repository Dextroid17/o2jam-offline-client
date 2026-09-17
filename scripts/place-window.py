#!/usr/bin/env python3
"""Place the O2Jam (OTwo) window at an exact on-screen geometry - FRAME-aware.

usage: place-window.py FX FY W H [--title "Some Title"]

  FX FY = desired position of the visible FRAME's top-left corner (titlebar corner - this is
          what you actually see on the monitor, and what O2JAM_POS means now)
  W H   = desired CLIENT (game) size in X11 px
  --title sets the titlebar caption (WM_NAME + _NET_WM_NAME)

Why the indirection: raw XConfigureWindow gets a frame-gravity offset from KWin (the window
lands ~60px off), so we use the EWMH client message _NET_MOVERESIZE_WINDOW with gravity 10
(StaticGravity).  Static gravity positions the CLIENT area - but with a titlebar the thing the
user sees starts (frame_left, frame_top) above/left of the client, so we add the window's
_NET_FRAME_EXTENTS to hit the requested FRAME corner.  Verification below compares the frame
corner, not the client corner.
"""
import sys
import time

from Xlib import display, X, protocol


def find_window(d):
    for win in d.screen().root.query_tree().children:
        try:
            cls = win.get_wm_class()
        except Exception:
            continue
        if cls and any('O2' in str(c).upper() or 'JAM' in str(c).upper() for c in cls):
            return win
    return None


def frame_extents(d, win):
    fe = win.get_full_property(d.intern_atom('_NET_FRAME_EXTENTS'), X.AnyPropertyType)
    v = list(fe.value) if fe else [0, 0, 0, 0]
    while len(v) < 4:
        v.append(0)
    # _NET_FRAME_EXTENTS order is left, right, TOP, bottom - re-order to left, top, right, bottom
    return int(v[0]), int(v[2]), int(v[1]), int(v[3])


def set_title(d, win, text):
    atom = d.intern_atom('_NET_WM_NAME')
    utf8 = d.intern_atom('UTF8_STRING')
    try:
        win.set_wm_name(text)
        win.change_property(atom, utf8, 8, text.encode('utf-8'))
        d.sync()
        print(f'title set to {text!r}')
    except Exception as exc:
        print(f'title set failed: {exc}')


def main(argv):
    if len(argv) < 5:
        sys.exit(__doc__)
    fx, fy, w, h = (int(v) for v in argv[1:5])
    title = None
    if '--title' in argv:
        title = argv[argv.index('--title') + 1]

    d = display.Display(':0')
    root = d.screen().root
    target = find_window(d)
    if target is None:
        sys.exit('place-window: no O2Jam/OTwo window found')

    # clear any maximise state first, otherwise the WM re-maximises after the move
    for atom in ('_NET_WM_STATE_MAXIMIZED_VERT', '_NET_WM_STATE_MAXIMIZED_HORZ'):
        root.send_event(protocol.event.ClientMessage(
            window=target, client_type=d.intern_atom('_NET_WM_STATE'),
            data=(32, [0, d.intern_atom(atom), 0, 1, 0])),
            event_mask=X.SubstructureRedirectMask | X.SubstructureNotifyMask)
    d.sync()
    time.sleep(0.6)
    # wait for the WM to actually drop the maximise state, otherwise it re-maximises over the
    # geometry we are about to request
    for _ in range(10):
        st = target.get_full_property(d.intern_atom('_NET_WM_STATE'), X.AnyPropertyType)
        names = [d.get_atom_name(a) for a in (list(st.value) if st else [])]
        if not any('MAXIMIZED' in n for n in names):
            break
        time.sleep(0.3)

    fl, ft, fr, fb = frame_extents(d, target)
    cx, cy = fx + fl, fy + ft          # client corner implied by the requested frame corner

    # gravity 10 = StaticGravity -> x/y are the client area; 0x0F00 sets the x/y/w/h flags
    root.send_event(protocol.event.ClientMessage(
        window=target, client_type=d.intern_atom('_NET_MOVERESIZE_WINDOW'),
        data=(32, [0x0F00 | 10, cx, cy, w, h])),
        event_mask=X.SubstructureRedirectMask | X.SubstructureNotifyMask)
    d.sync()
    time.sleep(1.5)

    if title:
        set_title(d, target, title)

    # KWin applies the request asynchronously (and may still be un-maximising), so poll until
    # the frame really is where we asked - sampling once and reporting that would be a lie.
    deadline = time.time() + 6.0
    while True:
        g = target.get_geometry()
        c = root.translate_coords(target, 0, 0)
        gfl, gft, gfr, gfb = frame_extents(d, target)
        if ((c.x - gfl, c.y - gft) == (fx, fy) and (g.width, g.height) == (w, h)) or time.time() > deadline:
            break
        time.sleep(0.4)
    frame_pos = (c.x - gfl, c.y - gft)
    frame_size = (g.width + gfl + gfr, g.height + gft + gfb)
    print(f'frame extents  : left={gfl} top={gft} right={gfr} bottom={gfb} X11 px'
          f' (titlebar {gft}px = {gft / 1.6:.0f} real px)')
    print(f'client (game)  : {g.width}x{g.height} at ({c.x},{c.y})   requested {w}x{h}')
    print(f'visible frame  : {frame_size[0]}x{frame_size[1]} at ({frame_pos[0]},{frame_pos[1]})'
          f'   requested {fx},{fy}')
    print('exact match    :', frame_pos == (fx, fy) and (g.width, g.height) == (w, h))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
