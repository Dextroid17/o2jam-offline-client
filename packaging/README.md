# Packaging — real installers, not just scripts 🛠️

`install.sh` / `install.ps1` in the repo root are the *one-line* installers.
This folder builds **installer programs** — things a person can double-click
without having Python, a terminal, or this repo on disk.

| Artifact | Platform | Needs Python? | Built by |
|---|---|---|---|
| `O2Jam-Installer` (single binary) | Linux x86_64 | ❌ no | `build-linux.sh` |
| `O2Jam-Installer-x86_64.AppImage` | Linux x86_64 | ❌ no | `build-linux.sh` |
| `O2Jam-Installer.exe` (single exe) | Windows x64 | ❌ no | `build-windows.ps1` |
| `O2Jam-Installer-Setup.exe` (wizard) | Windows x64 | ❌ no | `build-windows.ps1` + Inno Setup |
| `Install-O2Jam.cmd` (double-click) | Windows | ❌ no (uses built-in PowerShell) | ships as-is |

All of them drive the same two CLI installers. `install.sh` and `install.ps1`
are **embedded inside** the packaged builds as data files and unpacked to a
temp folder at run time, so one file is the whole installer.

---

## Build

```bash
# Linux -- binary + AppImage, output in ./dist
bash packaging/build-linux.sh
SKIP_APPIMAGE=1 bash packaging/build-linux.sh     # binary only, no download

# Windows -- .exe (+ setup.exe when Inno Setup 6 is installed)
powershell -ExecutionPolicy Bypass -File packaging\build-windows.ps1
```

Both scripts create a private virtualenv (PyInstaller + Pillow) under
`~/.cache/o2jam-packaging` / `%LOCALAPPDATA%\o2jam-packaging`, generate the
icon, build, and then run the built artifact's own `--self-test`.
**No sudo, no admin rights, nothing installed system-wide.**

---

## Using the packaged installer

```bash
./dist/O2Jam-Installer                                    # the window
./dist/O2Jam-Installer --assets ~/O2Jam --prefix ~/o2jam    # pre-filled
./dist/O2Jam-Installer --dry-run --prefix /tmp/try        # no build, no shortcuts
./dist/O2Jam-Installer --self-test                        # verify this build
./dist/O2Jam-Installer --print-command                    # what would it run?
./dist/O2Jam-Installer --simulate-windows --print-command  # ... the Windows one?
```

The AppImage is the same program with no install step at all:

```bash
chmod +x dist/O2Jam-Installer-x86_64.AppImage
./dist/O2Jam-Installer-x86_64.AppImage
```

Running an AppImage normally needs FUSE (`libfuse2`). Without it, use
`--appimage-extract-and-run`.

---

## What the installer actually does

1. checks for `git`, `cmake`, `make`, a compiler, `python3` — **and tells you
   what to install instead of installing it for you**
2. clones this project + upstream CXO2 into your chosen folder
3. applies the project's patches
4. builds the client (optional — untick it to just set things up)
5. links *your own* O2Jam data (nothing is copied or downloaded)
6. installs a menu entry / shortcut

No game data is ever shipped or downloaded, and every option is one checkbox
away. Full detail: [`../docs/SETUP.md`](../docs/SETUP.md).

---

## Notes for packagers

* `o2jam.png` / `o2jam.ico` are drawn by `make-icon.py` — the project's own
  artwork, not traced from the game.
* The spec embeds `install.sh` **and** `install.ps1` in every build, so a Linux
  binary can still print the Windows command line (`--simulate-windows`) and the
  Windows exe can do the same in reverse.
* **Tcl/Tk libraries**: the spec asks `ldd` what `_tkinter` links against and
  bundles those libraries. Relocatable CPython builds (uv,
  python-build-standalone) keep `libtcl9.0.so` / `libtcl9tk9.0.so` inside the
  interpreter's own `lib/`, and PyInstaller's default hooks miss them — the
  frozen app then dies the moment a window opens.
* **No console on Windows**: a windowed `.exe` has no `stdout`. The installer
  attaches to the console it was launched from (`AttachConsole`) so CLI flags
  still print; launched by double-click it writes its report to
  `%TEMP%\o2jam-installer-self-test.txt` and shows it in a message box.
* PyInstaller is not a cross-compiler. `build-windows.ps1` is the supported way
  to build the `.exe` (Windows, or CI `windows-latest`). A Linux box *can* do it
  through Wine + Windows CPython if you want a build without leaving Linux — it
  is what produced the release exe, and its self-test passes under Wine — but
  treat CI as the authority. That route is scripted as
  `packaging/build-windows-wine.sh`; everything it downloads (Wine prefix,
  Windows CPython 3.11, PyInstaller) stays in `~/.cache/o2jam-packaging` and can
  be deleted at any time — a rebuild just re-downloads it.
* **Verifying Windows scripts from Linux**: `check-powershell.ps1` runs under a
  real PowerShell 7 (there is a
  [portable Linux build](https://github.com/PowerShell/PowerShell/releases), no
  sudo) and reports syntax errors, declared parameters, and whether `install.ps1`
  still accepts every flag the GUI sends. It caught two bugs that would have
  stopped the one-liner dead on Windows — one of them a `"$var: text"` string
  that PowerShell reads as a drive reference:

  ```bash
  pwsh -NoProfile -Command "& packaging/check-powershell.ps1 -Files install.ps1,packaging/build-windows.ps1"
  ```

---

## What has actually been verified

Measured on the build machine, not aspirational:

| Check | Result |
|---|---|
| `dist/O2Jam-Installer` self-test | **13/13 ok**, exit 0 |
| `dist/O2Jam-Installer-x86_64.AppImage` self-test | exit 0 directly *and* via `--appimage-extract-and-run` |
| Bundled driver unpacks + runs | staged to a temp dir, `--help` exits 0, both drivers present |
| Real install through the packaged binary | `--dry-run` → clone + 3 patches + venv + asset linking, **driver exit 0** |
| GUI renders | screenshot under Xvfb, log pane contrast 16.5:1 |
| Windows `.exe` | `PE32+ executable for MS Windows 6.00 (GUI), x86-64`; self-test **13/13 ok** under Wine |
| `install.ps1` / `build-windows.ps1` syntax | parse-checked by real PowerShell 7.4.6; the flag contract the GUI sends (`-Prefix -Assets -Jobs -NoBuild -NoShortcut -SkipPatches -Yes`) is verified present |
| CI | `.github/workflows/build-installers.yml` builds both on real runners |

Not verified: a full Windows install (`MSVC + Ninja`) — that needs a Windows
machine or the CI job above. The `.exe` itself runs and its driver is
syntax-checked; the *build step inside it* is not something Linux can exercise.

