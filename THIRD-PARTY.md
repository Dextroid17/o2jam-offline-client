# Third-party components, licenses & honesty notes

This repository contains **our own work only**: launcher/window tooling, an
installer, docs, and a small set of patch files. It does **not** contain, vendor
or redistribute any upstream source tree or any game asset.

## What the patches modify (cloned at install time, never bundled)

| Component | Upstream | Declared license | How we use it |
|---|---|---|---|
| **CXO2** | https://github.com/SirusDoma/CXO2 | ⚠️ **none declared** (repo has no `LICENSE`/`COPYING` as of 2026-09-17) | The installer clones it fresh from GitHub and applies our patches **locally, on your machine**. We do not redistribute CXO2 source or binaries. |
| **Genode** | https://github.com/SirusDoma/Genode | Zlib | CXO2's framework; pinned git submodule. Patched locally by the installer. |
| **SFML** (fork) | https://github.com/SirusDoma/SFML | Zlib | Pulled in by CXO2's CMake `FetchContent`. One tiny CMake change patched locally. |
| **SFML** (upstream) | https://www.sfml-dev.org | Zlib | Same as above — the fork tracks upstream SFML. |
| **python-xlib** | https://github.com/python-xlib/python-xlib | LGPL-2.1-or-later | Installed into a local venv at install time by the window tooling. Not bundled. |

Because upstream CXO2 declares no license, **our patch files (`patches/`) are
derivative works of it and inherit whatever terms its author sets.** If you are
the author and you want a different arrangement, open an issue — genuinely, it's
your call. Our patches are published so that *you* can build the thing you
already wanted to build, nothing more.

## Game assets — not here, and never will be

O2Jam, its client data (`*.opa`, `*.opi`, `*.ojn`, `*.ojm`, `OJNList.dat`),
music, avatars, interface art and the name itself belong to their respective
owners. This is an unofficial, non-commercial fan project with **no affiliation
whatsoever**.

The installers never download game data. They ask you for a directory you
already own (a 3.10-era e-Games client install works best) and symlink it, so
the game can find it. Nothing is copied, uploaded or redistributed.

## Tools used to build this

- **Hermes Agent** by [Nous Research](https://nousresearch.com) — my
  collaborator for the entire debugging process.
- g++ 16 / CMake / KWin / XWayland on CachyOS — the environment everything here
  was measured in. Numbers in the docs are real measurements from that machine.
