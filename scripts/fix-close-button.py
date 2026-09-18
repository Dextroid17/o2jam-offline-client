#!/usr/bin/env python3
"""Make the window manager draw the CLOSE (X) button on the O2Jam window.

STATUS: with the current client this script is a READ-ONLY no-op.  The client asks for
sf::Style::Close in its borderless branch (Genode/Application.cpp), so SFML sets
MWM_FUNC_CLOSE in _MOTIF_WM_HINTS itself and KWin draws the X button on the FIRST paint --
no minimise/restore bounce at launch, so the window no longer "blinks" once before the X
appears.  The steps below are kept as a fallback for a client that still lacks that flag.

THE ORIGINAL PROBLEM: the client asked for decorations (_MOTIF_WM_HINTS decorations=126) but
left MWM_FUNC_CLOSE out of the functions field (0x1e = resize|move|minimise|maximise).  KWin
believes the client and correctly refuses to offer a close button - the titlebar then shows
only - and ^.

THE FALLBACK FIX (three steps, no rebuild):
  1. OR the CLOSE bit back into _MOTIF_WM_HINTS.
  2. Bounce the window minimise -> restore: KWin caches a window's capabilities and only
     re-reads them on (re)map, which is what makes _NET_WM_ALLOWED_ACTIONS gain CLOSE.
  3. Ask KWin to reconfigure: the decoration is only REPAINTED after that, which is when the
     third button actually appears.  (Capability alone is not enough - this step is easy to
     miss, and skipping it looks exactly like "the fix did not work".)
The window keeps its geometry through all of this; it runs at launch while the game is still on
its loading screen.

BITS: KWin parses _MOTIF_WM_HINTS with the layout SFML writes - ALL=0x01, RESIZE=0x02, MOVE=0x04,
MINIMISE=0x08, MAXIMISE=0x10, CLOSE=0x20.  (Motif's own header puts CLOSE at 0x01, and KWin
reads that bit as ALL, which is why OR-ing 0x01 used to work too.)  Accept either; only ADD.

usage: fix-close-button.py     exit 0 = close button available, 1 = still missing
"""
import subprocess
import sys
import time

from Xlib import display, X, protocol

MWM_FUNC_ALL = 0x01
MWM_FUNC_CLOSE = 0x20


def close_allowed(functions):
    """KWin grants close when the specific CLOSE bit or the ALL umbrella bit is set."""
    return bool(functions & (MWM_FUNC_ALL | MWM_FUNC_CLOSE))


def find(d):
    for win in d.screen().root.query_tree().children:
        try:
            cls = win.get_wm_class()
        except Exception:
            continue
        if cls and any('O2' in str(c).upper() or 'JAM' in str(c).upper() for c in cls):
            return win
    return None


def allowed(d, win):
    v = win.get_full_property(d.intern_atom('_NET_WM_ALLOWED_ACTIONS'), X.AnyPropertyType)
    return [d.get_atom_name(a) for a in (list(v.value) if v else [])]


def reconfigure():
    """Make KWin rebuild/repaint window decorations (step 3)."""
    for cmd in (['qdbus6', 'org.kde.KWin', '/KWin', 'reconfigure'],
                ['qdbus', 'org.kde.KWin', '/KWin', 'reconfigure']):
        try:
            if subprocess.run(cmd, capture_output=True, text=True, timeout=10).returncode == 0:
                return True
        except Exception:
            continue
    return False


def main():
    d = display.Display(':0')
    root = d.screen().root
    win = None
    for _ in range(40):                     # the game takes a while to map its window
        win = find(d)
        if win is not None:
            break
        time.sleep(0.5)
    if win is None:
        print('no O2Jam window found - close button not adjusted')
        return 1

    atom = d.intern_atom('_MOTIF_WM_HINTS')
    fe = win.get_full_property(atom, 0)
    hints = list(fe.value) if fe else []
    changed = False

    if len(hints) >= 2 and not close_allowed(hints[1]):
        new = hints[:]
        new[1] |= MWM_FUNC_CLOSE
        win.change_property(atom, atom, 32, new)
        d.sync()
        print('_MOTIF_WM_HINTS functions 0x%x -> 0x%x (added MWM_FUNC_CLOSE)' % (hints[1], new[1]))
        changed = True

    if '_NET_WM_ACTION_CLOSE' not in allowed(d, win):
        # KWin re-reads a window's capabilities on (re)map -> bounce minimise/restore once.
        # Ask the WM to do it (WM_CHANGE_STATE): mapping the window ourselves with a raw
        # win.map() makes KWin treat it as a new map and RE-PLACE the window, moving it.
        root.send_event(protocol.event.ClientMessage(
            window=win, client_type=d.intern_atom('WM_CHANGE_STATE'),
            data=(32, [3, 0, 0, 0, 0])), event_mask=X.SubstructureRedirectMask)
        d.sync()
        time.sleep(1.5)
        root.send_event(protocol.event.ClientMessage(
            window=win, client_type=d.intern_atom('WM_CHANGE_STATE'),
            data=(32, [1, 0, 0, 0, 0])), event_mask=X.SubstructureRedirectMask)
        root.send_event(protocol.event.ClientMessage(
            window=win, client_type=d.intern_atom('_NET_ACTIVE_WINDOW'),
            data=(32, [2, 0, 0, 0, 0])), event_mask=X.SubstructureRedirectMask)
        d.sync()
        changed = True
        for _ in range(16):
            time.sleep(0.5)
            if '_NET_WM_ACTION_CLOSE' in allowed(d, win):
                break

    acts = [a.replace('_NET_WM_ACTION_', '') for a in allowed(d, win)]
    if 'CLOSE' not in acts:
        print('KWin still refuses CLOSE - the client did not set MWM_FUNC_CLOSE')
        print('(rebuild the client with sf::Style::Close - see Genode/Application.cpp)')
        return 1
    print('window capabilities now:', ' | '.join(a.lower() for a in acts))

    if not changed:
        print('_MOTIF_WM_HINTS functions 0x%x already allows close (%s) - nothing to do'
              % (hints[1], 'MWM_FUNC_ALL' if hints[1] & MWM_FUNC_ALL else 'MWM_FUNC_CLOSE'))
        print('titlebar buttons: minimise | maximise | close')
        return 0

    if reconfigure():
        print('KWin reconfigured -> decoration repainted, close (X) button drawn')
    else:
        print('CLOSE is allowed but KWin could not be asked to repaint - the X button may only')
        print('appear after the next window (re)decoration')
    print('titlebar buttons: minimise | maximise | close')
    return 0


if __name__ == '__main__':
    sys.exit(main())
