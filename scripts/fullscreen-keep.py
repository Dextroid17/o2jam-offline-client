#!/usr/bin/env python3
"""Keep the native O2Jam client as a REAL fullscreen window on the Gigabyte.

Why this exists
---------------
CXO2 creates its window as a *borderless window* (sf::Style::None) and then hacks
`setPosition(0, 0)`. On a KWin multi-output layout whose primary output does not
start at the desktop origin (Gigabyte is at logical 0,403 / X11 0,806), that lands
the window ~403 logical px ABOVE the monitor: the top of the game is cut off and the
bottom of the screen shows the desktop. It is never a real fullscreen window.

This watcher sends the standard EWMH `_NET_WM_STATE_FULLSCREEN` client message, i.e.
exactly what a normal game does when you pick "borderless fullscreen". KWin then
sizes and places the window over its output, keeps it undecorated and above panels.

It also re-applies the request whenever the window is recreated - the client's own
Alt+Enter windowed/fullscreen toggle does that - and exits by itself once no game
window has been seen for a while.

Usage: fullscreen-keep.py [display]            (default :0)
"""
import sys
import time

from Xlib import X, Xatom, display, protocol

RES_NAME = "OTwo"          # WM_CLASS res_name set by CXO2
IDLE_EXIT_SECONDS = 90     # give up (and let the process die) after this long with no window


def game_windows(d, root):
    """Every mapped top-level-ish window whose WM_CLASS matches the game."""
    found = []

    def walk(win, depth=0):
        if depth > 4:
            return
        try:
            children = win.query_tree().children
        except Exception:
            return
        for child in children:
            try:
                wm_class = child.get_wm_class()
            except Exception:
                continue
            if wm_class and wm_class[0] == RES_NAME:
                found.append(child)
            else:
                walk(child, depth + 1)

    walk(root)
    return found


def main():
    disp_name = sys.argv[1] if len(sys.argv) > 1 else ":0"
    d = display.Display(disp_name)
    root = d.screen().root
    net_wm_state = d.intern_atom("_NET_WM_STATE")
    net_wm_state_fs = d.intern_atom("_NET_WM_STATE_FULLSCREEN")

    last_seen = time.time()
    while True:
        windows = game_windows(d, root)
        if windows:
            last_seen = time.time()

        for win in windows:
            try:
                current = win.get_full_property(net_wm_state, Xatom.ATOM)
                states = set(current.value) if current else set()
            except Exception:
                continue

            if net_wm_state_fs in states:
                continue

            # _NET_WM_STATE_ADD (1) of _NET_WM_STATE_FULLSCREEN, source = normal app (1)
            ev = protocol.event.ClientMessage(
                window=win,
                client_type=net_wm_state,
                data=(32, [1, net_wm_state_fs, 0, 1, 0]),
            )
            ev.send_event = True
            try:
                root.send_event(
                    ev,
                    event_mask=X.SubstructureNotifyMask | X.SubstructureRedirectMask,
                    propagate=False,
                )
                d.sync()
                print(f"requested fullscreen for 0x{win.id:x}", flush=True)
            except Exception as exc:  # keep the watcher alive
                print(f"send failed for 0x{win.id:x}: {exc}", flush=True)

        if time.time() - last_seen > IDLE_EXIT_SECONDS:
            print("no game window for a while - exiting", flush=True)
            return
        time.sleep(1.5)


if __name__ == "__main__":
    main()
