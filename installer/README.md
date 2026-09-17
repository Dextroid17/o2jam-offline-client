# The graphical installer

One window, both platforms: it drives `install.sh` (Linux) or `install.ps1`
(Windows) and shows you the raw output while it works.

<p align="center"><em>Install folder · your game data · Install · done.</em></p>

## Run it

| Platform | Command |
|---|---|
| Linux | `python3 installer/o2jam-installer.py` |
| Linux (menu) | `installer/Install-O2Jam.desktop` |
| Windows | `py -3 installer\o2jam-installer.py` |
| From the one-liner | `install.sh --gui` / `install.ps1 -Gui` |

Needs Python 3 with Tkinter — the only dependency, and it's in every normal
Python install. Linux users who built Python from a minimal image may need
`python3-tk` (the GUI says so if it's missing).

## What the buttons do

| Button | Means |
|---|---|
| **Install** | checks the toolchain, clones the sources, applies patches, optionally builds, links your data, installs the shortcut |
| **Dry run** | everything except the build and the shortcut — the fast way to find out whether your system is ready |
| **Stop** | kills the running installer process. Nothing is ever deleted by it |

Options map 1:1 onto the CLI flags, so anything the GUI can do the terminal can
do too — `--no-build`, `--no-shortcut`, `--jobs N`.

## Things it deliberately does not do

- **No `sudo` / no admin prompt.** If something needs root, the installer prints
  the command for *you* to run. On Windows, installing the VC build tools may
  show a UAC prompt — that one is Windows' doing, not ours.
- **No game data download.** You point it at data you already own; the installer
  only creates links (symlinks on Linux, junctions on Windows).
- **No deletions.** Uninstalling is `--uninstall` on the shortcut script, or
  deleting the install folder yourself.
