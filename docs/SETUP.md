# Setup

Everything here installs into your home directory. No `sudo`, no system-wide
packages, no game data downloaded, nothing deleted without you asking.

---

## 1. Quick install

### Linux (tested end to end)

```bash
curl -fsSL https://raw.githubusercontent.com/Dextroid17/o2jam-offline-client/main/install.sh | bash
```

With your game data in the same breath:

```bash
curl -fsSL https://raw.githubusercontent.com/Dextroid17/o2jam-offline-client/main/install.sh \
  | bash -s -- --assets "$HOME/O2Jam"
```

### Windows

Upstream's client builds on Windows with MSVC + Ninja, so the script follows
upstream's own CI recipe:

```powershell
irm https://raw.githubusercontent.com/Dextroid17/o2jam-offline-client/main/install.ps1 | iex
```

> **Honesty box.** The Linux path was developed and measured on real hardware.
> The Windows script is written from upstream's CI configuration and has **not**
> been run on a Windows machine — I don't have one. If it breaks, the log says
> where; open an issue.

### Graphical installer (both platforms)

```bash
python3 installer/o2jam-installer.py     # Linux
py -3 installer\o2jam-installer.py       # Windows
```

Same options as the CLI, with a log pane. `install.sh --gui` does both in one go.

---

## 2. Requirements

| Need | Linux | Windows |
|---|---|---|
| Compiler | g++ 9+ (13/16 fine) or clang++ | MSVC C++ build tools |
| Build system | cmake ≥ 3.20, make/ninja | cmake, ninja |
| Fetching | git, curl | git |
| Window tooling *(optional)* | python3 + venv | python3 (GUI only) |
| Runtime graphics | OpenGL 3.x driver | OpenGL 3.x driver |

The installer **never** installs these for you with elevation: it prints the
exact command (e.g. `sudo pacman -S git cmake make gcc python`) and stops.

---

## 3. What gets created

Default prefix is `~/o2jam` (override with `--prefix`):

```
~/o2jam/
├── src/o2jam-offline-client/   this project (scripts, patches, docs)
├── native/
│   ├── CXO2/                   upstream client + our patches, built here
│   │   ├── bin/linux/Release/OTwo      <- the game (Linux)
│   │   ├── bin/windows/Release/OTwo.exe <- the game (Windows)
│   │   └── Image/ Music/       linked from YOUR data
│   ├── run-windowed.sh         the launcher (window size/position)
│   ├── run-desktop.sh          fullscreen desktop-mode launcher
│   ├── o2jam-launch.sh         focus-if-running wrapper + notifications
│   ├── apply-patches.sh        idempotent patch application
│   ├── link-assets.sh          links your game data in
│   ├── install-shortcut.sh     menu entry + icon (--uninstall to undo)
│   └── build.log               everything the build said
└── tools/venv/                 python-xlib for the window tooling
```

Cleanup is `bash native/install-shortcut.sh --uninstall` plus `rm -rf ~/o2jam`.

---

## 4. Your game data

Nothing is bundled or downloaded — the client needs a 3.10-era **e-Games O2Jam**
data set (the one with `Image/` and `Music/` in it):

```
<your data>/
├── Image/
│   ├── avatar.opa
│   ├── Interface1.opi
│   ├── Playing1.opi
│   └── OJNList.dat
└── Music/         (*.ojn charts + *.ojm audio)
```

Point the installer at the parent folder:

```bash
bash ~/o2jam/native/link-assets.sh '/path/to/your/o2jam/data'
bash ~/o2jam/native/link-assets.sh --list      # what's currently linked
```

Symlinks are used on Linux, junctions on Windows, so your files stay yours and
nothing is duplicated. `--copy` is there if you'd rather have real copies.

---

## 5. Launcher options

Windows are sized in **X11 pixels** on Linux (see the scale note below).

| Variable | Values | Default |
|---|---|---|
| `O2JAM_WINDOW` | `1080p` · `720p` · `screen` · any `WxH` | `1080p` |
| `O2JAM_POS` | `x,y` — client-area position | centred |
| `O2JAM_FIT` | `letterbox` (4:3 with pillarbox bars) · anything else = fill | fill |
| `O2JAM_BORDERLESS` | `1` = decoration-free window, still draggable/resizable | on in the launcher |
| `O2JAM_FRAME_TOP` | titlebar height in px, for placement maths | auto-detected |

```bash
bash ~/o2jam/native/run-windowed.sh                    # 1080p windowed (default)
O2JAM_WINDOW=720p   bash ~/o2jam/native/run-windowed.sh
O2JAM_WINDOW=screen bash ~/o2jam/native/run-windowed.sh   # whole work area
O2JAM_WINDOW=2560x1440 O2JAM_POS=200,100 bash ~/o2jam/native/run-windowed.sh
```

In-game, `Alt+Up` toggles the letterbox live.

### The scale trap (Wayland desktops)

XWayland gives X11 clients a scaled coordinate space, so "1920×1080" written by
an X11 program is not 1920×1080 of glass. Measured on the reference machine
(a 2560×1440 panel, KDE/Wayland, XWayland scale factor 1.6):

| Space | Size of the same screen |
|---|---|
| physical panel | 2560 × 1440 |
| KDE logical (1.25 desktop scale) | 2048 × 1152 |
| **X11 / XWayland (what the launcher speaks)** | **4096 × 2304** |

So the rule is:

```
X11 pixels = physical pixels × XWayland scale factor   (1.6 here)
1920×1080 of glass  ->  3072×1728 in X11 pixels
```

That's exactly what the `1080p` preset emits — the numbers look absurd until you
know the factor. The presets apply it automatically; a hand-written `WxH` is
taken literally, and `screen` uses the whole work area (the panel reserves its
height, so it is a little less than the full 4096×2304).

---

## 6. Troubleshooting (the errors I actually hit)

| Symptom | Cause | Fix |
|---|---|---|
| `error: 'uint32_t' has not been declared` etc. building CXO2 | g++ 13+/16 needs explicit includes | `patches/01-…` adds them (already applied by the installer) |
| `cannot find -lstdc++fs` / `libiconv not found` | modern glibc merged both into libc | `patches/01-…` guards both |
| SFML configure fails on a Freetype/HarfBuzz target alias | fork vs upstream SFML `FetchContent` | `patches/02-…`, applied after the first configure + a re-configure |
| Window can't be resized by dragging a corner | SFML sets `PMinSize == PMaxSize` for a decoration-free window | the Resize flag is OR'd back in (`patches/01-…`) — resize then works, MWM hints included |
| Two black bars on the sides | the game letterboxes its 800×600 design view | patched to fill the window; `O2JAM_FIT=letterbox` brings them back deliberately |
| No ✕ in the titlebar / can't close | `_MOTIF_WM_HINTS` missing `MWM_FUNC_CLOSE` — i.e. a client built without `sf::Style::Close` in its borderless style | rebuild the client (the flag is in `patches/03-…`), or run `native/fix-close-button.py`; KWin caches allowed actions, so the helper has to bounce the window and reconfigure KWin |
| Window opens on the wrong monitor | EWMH placement races the WM | `native/place-window.py` (frame-aware, uses `_NET_FRAME_EXTENTS`), `O2JAM_POS=x,y` |
| `XAUTHORITY` errors after re-login | the xauth file name rotates per session | the launchers pick the newest `/run/user/$UID/xauth_*` themselves |
| Game starts and exits immediately | data not linked / wrong folder | `link-assets.sh --list`, check `Image/` + `Music/` both resolve |
| Build takes forever | it's C++, and SFML's bundled mbedtls comes along | expected: 15–40 min. `O2JAM_JOBS=N` to throttle |

Still stuck? `~/o2jam/native/build.log` and the venv log `~/o2jam/tools/venv.log`
contain every command and its output.

---

## 7. Known gaps (no pretending)

- **Login is offline.** The native client needs a v3.10-era native server
  (`Mozart.Encore`). `Amadeus.Encore` speaks the v3.82 protocol and will not
  authenticate it. Single-player/offline play is what this project gives you.
- **`Itemdata.dat`** from some v3.82-era data sets is rejected by the v3.10
  layout parser; the game logs it and continues without shop items.
- **The ✕ button** was verified down to the pixel (`∨ ∧ ✕` present in the
  decoration-free frame) but never literally pressed, because on the test
  machine that would have killed a session mid-experiment.
- Some data sets ship differently-named interface archives (`Interface1.opi`
  vs `Interface3.opi`); the game is tolerant but a missing file will show up in
  the log.
