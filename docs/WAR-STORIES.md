# War stories

Every one of these cost real hours on real hardware. Written down so the next
person (probably me, six months from now) doesn't pay again.

The machine: CachyOS, KDE Plasma on **Wayland**, XWayland, KWin, an RTX 3080 Ti,
g++ 16. The game: native CXO2, no Wine anywhere.

---

## 1. A window that refused to be resized

The goal was modest: a decoration-free 1080p window you can drag around and
stretch by its corners. We got the "no decorations" part easily —
`sf::Style::None` — and then found that you could not drag a single edge.

The reason is SFML's X11 backend. When a window asks for no decorations it
*helpfully* also tells the X server "this window has a fixed size", by setting
`WM_NORMAL_HINTS` to a minimum size equal to a maximum size. An X11 window with
`PMinSize == PMaxSize` is not resizeable, by design, and no window manager will
offer you a resize handle. It is not a bug in SFML so much as a policy for a
style we weren't really using.

The fix is one line of intent: keep `Style::None` **and** OR the resize flag back
in.

```cpp
auto style = m_state == sf::State::Fullscreen
             ? sf::Style::None
             : sf::Style::Titlebar | sf::Style::Close;
if (borderless)
    style = sf::Style::None | sf::Style::Resize | sf::Style::Close;
```

That flag also makes SFML set `MWM_FUNC_RESIZE` in the Motif hints and skip the
min/max clamp, so the window manager starts offering resize handles again.
(`Close` is not there for decoration theatre — see #3: without it SFML actively
*clears* `MWM_FUNC_CLOSE` and the titlebar gets no ✕.)

**Lesson:** when an X11 window "can't be resized", read `WM_NORMAL_HINTS` before
blaming the window manager. `xprop` would have saved a day.

---

## 2. Two black bars on the sides

The game renders its UI at a fixed 800×600 design resolution and letterboxes
itself into whatever the window is (`GetLetterBoxView()`), which on a widescreen
window gives two fat black pillars. In a borderless window they look like a
rendering bug.

Fix: in `O2.cpp`'s `Boot()`, in borderless-windowed mode, stretch the design view
over the whole viewport instead of letterboxing it. The aspect-true version is
still one environment variable away (`O2JAM_FIT=letterbox`) because some people
prefer the original framing — and `Alt+Up` toggles it live.

**Lesson:** "black bars" is very often an application choice, not a driver bug.
Grep for the letterbox call before touching anything else.

---

## 3. The vanishing ✕

The window drew `∨ ∧` (minimise, maximise) and no close button. The Motif hints
said exactly why:

```
_MOTIF_WM_HINTS = [3, 0x1e, 126, 0, 0]
```

`0x1e` is a bitmask of allowed functions — resize|move|minimise|maximise, no close
bit. KWin believes the client and, quite correctly, refuses to draw a button the
client says it does not have.

**Why the bit was missing.** SFML derives that mask from the style flags, and it is
deliberate — `WindowImplX11.cpp`: *"We have to assume the reason `Style::Close` was
not specified is to prevent the close button from appearing in the window
titlebar"*. Our borderless style never asked for `Close`, so SFML cleared the bit
for us. And the effective style was **not** the `None | Resize` that was written:
`WindowImpl.cpp` re-adds `Titlebar` whenever `Resize` is set — which is why the
hint read `0x1e` (titlebar functions) and not `0x12`.

**The real fix — ask for it (one flag):**

```cpp
if (borderless)
    style = sf::Style::None | sf::Style::Resize | sf::Style::Close;
```

SFML then sets `MWM_FUNC_CLOSE` itself: the hint is `0x3e` on the **first** map and
KWin draws `∨ ∧ ✕` from the first paint. Nothing has to be patched after launch.

`scripts/fix-close-button.py` stays in the launcher as a **no-op fallback** for an
unpatched binary. It now understands both encodings — CLOSE `0x20` (SFML's/KWin's
layout) and ALL `0x01` (Motif's layout, which KWin reads as "every function",
which is why OR-ing `0x1` appeared to work) — and when close is already allowed it
changes nothing and does not bounce the window.

The bounce is worth spelling out, because it looked like a bug of its own: KWin
**caches** `_NET_WM_ALLOWED_ACTIONS` for a mapped window, so a property change on a
live window changes nothing on screen. The helper had to push the window through
`WM_CHANGE_STATE` (minimise → restore) to force a re-read, then call
`kwin reconfigure` to repaint the decoration. Visually that is the game blinking
once ~22 s into the loading screen — which is exactly what "the ✕ only shows up
after it reboots" was.

**Lesson:** a wrong-looking X11 hint is often a library writing precisely what you
asked for. Read the toolkit's own source (and remember it may normalise your flags)
before patching the property at runtime.

---

## 4. `_NET_FRAME_EXTENTS` is not what you think it is

For a while, the placement helper put the window ~60px too low. The culprit was
reading `_NET_FRAME_EXTENTS` as `[left, top, right, bottom]` — the order everyone
expects — when the property is actually **`left, right, top, bottom`**. Index `1`
is the *right* border, not the top. On a window with a 56px titlebar and 0px
side borders this is invisible until the arithmetic is off by exactly that 56px.

```python
left, right, top, bottom = extents      # yes, really: left, RIGHT, top, bottom
```

**Lesson:** EWMH properties are documented, and the docs are boring because they
are right. Read the spec, not the variable name you wished for.

---

## 5. "1080p" is not 1920×1080

On Wayland, X11 clients live in a scaled coordinate space. With an XWayland
scale factor of 1.6 on a 2560×1440 panel:

- physical: 2560×1440
- KDE's logical space: 2048×1152
- **X11 space: 4096×2304**

So a launcher that asks for `1920x1080` gets a window about 47% of the screen
area — technically correct, visually wrong, and the reason the first "1080p"
preset looked tiny. The preset now multiplies by the scale factor: 1920×1.6 =
**3072×1728** X11 pixels.

**Lesson:** on Wayland, always ask "pixels in *whose* space?" before trusting a
resolution number.

---

## 6. The window that kept going to the other monitor

Multi-monitor placement via `ConfigureRequest`/EWMH is a race with the window
manager: if you move the window before it is mapped, KWin may place it wherever
it likes on map, and *then* honour your coordinates — which looks like the window
"jumping" to the wrong screen. Add frame gravity, and your offset is wrong too.

The fix is ordering plus measurement: map the window, wait until it is
`viewable`, read the frame extents (see story 4), then move it with a
`_NET_MOVERESIZE_WINDOW` client message that carries the frame offset
(`scripts/place-window.py`). Running the ✕-fix *after* the snap, not before,
keeps the bounce from nudging the window back.

**Lesson:** with a window manager, "set the geometry" is a negotiation with
three steps: map, measure, move.

---

## 7. g++ 16 does not have your back

Modern GCC dropped a pile of transitive includes. The client built fine on the
toolchain its author used and fell over here on `uint32_t`, `memcpy` and friends.
It is the least glamorous patch in the repo (`patches/01-…`, a few `#include`
lines) and the one that makes the whole thing build on a 2026 distro. Same story
for `-lstdc++fs` (merged into libstdc++ in GCC 9+) and a hard `find_library(iconv
REQUIRED)` on a glibc that has iconv built in and ships no `libiconv` at all
(the same `patches/01-…`).

**Lesson:** "it compiles upstream" only means "it compiles on their compiler".
New compiler, new missing includes.

---

## 8. Wine was never the point

The whole project exists because the obvious answer — run the Windows client
under Wine — is the wrong one for this game. Rhythm games are latency-critical;
a translation layer between you and the audio clock is exactly what you don't
want, and fullscreen wine on Wayland fights the compositor for the display.

CXO2 is a native reimplementation: real SDL/SFML window, real OpenGL, real
latency. The cost is the debugging above — and honestly, that was the fun part.

---

## 9. Things that are still true and still annoying

- **`Itemdata.dat`** in some data sets is v3.82 layout; the v3.10 parser rejects
  it with a log line and continues. Cosmetic, fixable, not fixed.
- **Login needs `Mozart.Encore`** (a v3.10-era native server). `Amadeus.Encore`
  speaks v3.82. Offline is what works today.
- **The ✕ was never actually pressed** on the test machine — pressing it would
  have ended the session that was being used to verify it. The button exists, is
  advertised in `_NET_WM_ALLOWED_ACTIONS`, and is drawn; the click is on you.

---

*Built with [Hermes Agent](https://nousresearch.com), which did the boring parts
(patch archaeology, property dumps, screenshot forensics) and let the human keep
the fun parts. Literally vibe-coded: "does it look right?" was a legitimate
acceptance test throughout.*
