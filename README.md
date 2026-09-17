# 🎹 O2Jam Offline Client

**O2Jam — the legendary Korean rhythm game — running natively on Linux. No Wine. No emulator. No VM. Just the game, in a real window, on a real desktop.**

> **This is my passion project. This is thanks to Hermes agent, this is purely vibe-coded.**

---

## So... what is this? 🎮

If you grew up hammering a keyboard to 7 keys falling down a lane, you already know. O2Jam is *the* classic PC rhythm game — and it has spent the last decade locked behind dead servers, Windows-only clients and "install this, then install Wine, then pray" rituals.

This repo is my attempt to fix that **for real**: a native Linux build of an O2Jam client, windowed, movable, resizable, with buttons that actually close the game, sitting on my desktop as a normal app.

No compatibility layer translating every pixel through three interpreters. The client is native C++ talking straight to X11/Wayland. It boots, it plays, it's *fast* (165 FPS in the titlebar, if you're the type who checks).

## The backstory 🍜

I wanted to play O2Jam again. Offline. On my Linux box. That's it. That was the whole plan.

What followed was a week of me saying "why is it opening on the wrong monitor", "why can't I drag the corner", "there are two black bars and I hate them", and "where did my close button go" — while an AI agent sat next to me reading X11 internals, measuring pixels with a ruler, and occasionally admitting it had read the wrong element of an array for three hours.

Every single one of those problems got solved by *measuring the actual thing* instead of guessing. That's the whole ethos of this repo. 🔬

**This is my passion project. This is thanks to Hermes agent, this is purely vibe-coded.** I am not a C++ developer. I am a guy who wanted to play O2Jam and refused to give up. If you're in the same boat, welcome aboard. 🚢

## What actually works ✅

| Feature | Status |
|---|---|
| Native Linux client (no Wine, no gamescope required) | ✅ Works |
| Runs **windowed** at 1080p by default | ✅ Works |
| Real titlebar — drag, minimise, maximise, **close** | ✅ Works |
| Resizable — grab any edge or corner and stretch it | ✅ Works |
| Clean fill (no letterbox bars, no pillarboxing) | ✅ Works |
| Launches on your **primary** monitor, every time | ✅ Works |
| Desktop shortcut + app-menu entry, no terminal window | ✅ Works |
| Double-click while playing → focuses the game instead of restarting it | ✅ Works |
| PH private-server + browser client (Xpra HTML5) | 🧪 Built, experimental |
| One-line Linux installer (`curl … \| bash`) | ✅ Works (tested) |
| One-line Windows installer (`irm … \| iex`) | 🧪 Written from upstream's CI, **untested on real Windows** |
| Graphical installer (Tkinter, Linux + Windows) | ✅ Works on Linux, 🧪 untested on Windows |
| `Itemdata.dat` v3.82 avatar data | ⚠️ Parser rejects it (see [docs/SETUP.md](docs/SETUP.md#known-gaps)) |

## What's in here 📦

```
install.sh   One-line Linux installer (also drives the GUI, --gui)
install.ps1  One-line Windows installer (MSVC + Ninja, like upstream CI)
installer/   Graphical installer app -- one Tkinter window for both platforms
patches/     The C++ fixes that make all this work (against upstream CXO2,
             its Genode framework and its SFML fork)
scripts/     The launcher + window-placement tooling (bash + python-xlib)
desktop/     .desktop entry and icon, ready to install
docs/        Setup guide, and the war stories behind the X11 fixes
```

**Nothing in here is a game asset.** No songs, no avatars, no interface files. Those are not mine to hand out — see [Bring your own assets](#bring-your-own-assets-).

## Quick start (the impatient version) ⚡

**Linux** — one line. No sudo, no game data downloaded, everything lands in `~/o2jam`:

```bash
curl -fsSL https://raw.githubusercontent.com/Dextroid17/o2jam-offline-client/main/install.sh | bash

# and if you want your own game data wired up in the same breath:
curl -fsSL https://raw.githubusercontent.com/Dextroid17/o2jam-offline-client/main/install.sh \
  | bash -s -- --assets "$HOME/O2Jam"
```

**Windows** — PowerShell, same idea (MSVC + Ninja, exactly like upstream's CI; the script offers to install what's missing via winget):

```powershell
irm https://raw.githubusercontent.com/Dextroid17/o2jam-offline-client/main/install.ps1 | iex
```

**Rather have buttons than a wall of text?** One graphical installer covers both platforms:

```bash
python3 installer/o2jam-installer.py     # Linux
py -3 installer\o2jam-installer.py       # Windows
```

Install · Dry run · Stop, a live log pane, folder pickers — and every option the flags have. (`install.sh --gui` opens it after the CLI steps.)

**Prefer a normal installer — no terminal, no Python, nothing to set up first?** Grab a packaged one and just double-click it:

| Download | Platform | What it is |
|---|---|---|
| [**O2Jam-Installer.exe**](https://github.com/Dextroid17/o2jam-offline-client/releases/latest) | Windows x64 | one file, the whole installer inside (10 MB) |
| [**O2Jam-Installer-x86_64.AppImage**](https://github.com/Dextroid17/o2jam-offline-client/releases/latest) | Linux x86_64 | double-click, no install step (14 MB) |
| [**O2Jam-Installer**](https://github.com/Dextroid17/o2jam-offline-client/releases/latest) | Linux x86_64 | the same program as a plain binary, for scripts |
| [**Install-O2Jam.cmd**](https://github.com/Dextroid17/o2jam-offline-client/releases/latest) | Windows | double-click .cmd that runs the PowerShell installer |

They are the same window as above, frozen into a single file with the CLI installers *inside* it — `install.sh` / `install.ps1` are unpacked to a temp folder when it runs, so there is nothing else to download. Build your own with `bash packaging/build-linux.sh` or `packaging\build-windows.ps1` — see [`packaging/README.md`](packaging/README.md) for what is verified and what is not.

<details>
<summary>Or do it by hand, four commands 🛠️</summary>

```bash
git clone https://github.com/Dextroid17/o2jam-offline-client
cd o2jam-offline-client

# 1. Build the client (clones CXO2 + Genode, applies the patches, compiles)
bash scripts/build-cxo2.sh

# 2. Point it at the game data you own (links it in, never copies)
bash scripts/link-assets.sh /path/to/your/assets

# 3. Play — 1080p window, real titlebar, primary monitor
bash scripts/run-windowed.sh

# 4. Optional: desktop icon + app menu entry
bash scripts/install-shortcut.sh
```

</details>

Full details, prerequisites and every environment variable: **[docs/SETUP.md](docs/SETUP.md)**.

## The fight list 🥊

The genuinely interesting part of this project is that almost none of it was "write a feature" — it was "convince the window manager that this game is a normal window". A few highlights, all documented in [docs/WAR-STORIES.md](docs/WAR-STORIES.md):

- **"I cannot drag the corners."** SFML *clamps* the window when you don't ask for `Style::Resize` — it sets `PMinSize == PMaxSize` on the X11 hints, and the window manager dutifully refuses to stretch it. It's not a bug you can see; it's a silent contract with the WM.
- **"Where's my close button?"** The client advertised `_MOTIF_WM_HINTS` with the close *function* bit switched off. The window manager draws the X only if the client claims it can handle it. One bit: `0x1e` → `0x1f`.
- **"It keeps opening on the wrong monitor."** `gamescope -O DP-2` is a *hint*, not a pin. Placement ended up being done properly through EWMH (`_NET_MOVERESIZE_WINDOW`) after the window maps.
- **"I asked for 1080p and got half a screen."** Under XWayland with a 1.6× scale factor, X11 pixels are not screen pixels. 1920×1080 real = 3072×1728 in X11 coordinates. Asking for the latter got exactly the former.
- **"There are two black things on the sides."** That was the client's own 4:3 letterboxing, not the window. Fixed in the client's boot path, with the old behaviour still one env var away.

## Bring your own assets 📼

This repo contains **code only**. To actually play you need O2Jam client data (`*.opa`, `*.opi`, `OJNList.dat`, songs, avatars) from a copy you legally own — the 3.10-era e-Games discs are the ones that work best with this build.

Point the launcher at your data directory and go. Neither this repo nor its patches ship, embed or download any copyrighted game content.

## Credits & honesty 🙏

- **[CXO2](https://github.com/SirusDoma/CXO2)** by SirusDoma — a faithful, open re-implementation of the O2Jam client. This project is a set of patches and launcher glue around it, not a fork of the whole thing.
- **[Genode](https://github.com/SirusDoma/Genode)** (Zlib) — the framework CXO2 is built on, and the **[SFML fork](https://github.com/SirusDoma/SFML)** it uses.
- **Hermes Agent** ([Nous Research](https://nousresearch.com)) — my collaborator on every one of those 300-odd commits worth of debugging. Vibe-coded, but *measured*.
- O2Jam and all associated assets are the property of their respective owners. This is an unofficial fan project with no affiliation whatsoever. No assets are distributed here.

## License 📄

The glue in this repo (scripts, launcher tooling, installer, docs) is **MIT** — see [LICENSE](LICENSE). Patches under `patches/` are derivative works of the projects they patch and keep those projects' terms; [THIRD-PARTY.md](THIRD-PARTY.md) spells out exactly who owns what (including the awkward bit: upstream CXO2 declares no license, so nothing of theirs is redistributed here at all — the installers clone it straight from GitHub, on your machine).

---

*Built by someone who just wanted to play O2Jam, at 2am, with an agent that refused to guess.* 🌙
