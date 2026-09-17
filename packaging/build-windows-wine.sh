#!/usr/bin/env bash
# Build a real Windows O2Jam-Installer.exe on Linux, via Wine + Windows CPython.
# Everything lives in throwaway dirs; nothing touches the system.
#
#   bash packaging/build-windows-wine.sh
#
# Env: O2JAM_WIN_WORK (default ~/.cache/o2jam-packaging/winework), O2JAM_REPO
# Note: PyInstaller does not officially support cross-building, so treat the
# CI workflow (.github/workflows/build-installers.yml) as the authority and this
# script as the offline fallback. The .exe it produces is a genuine PE32+
# x86-64 GUI binary and it runs its own --self-test under Wine before we trust it.
set -uo pipefail

WORK="${O2JAM_WIN_WORK:-$HOME/.cache/o2jam-packaging/winework}"
REPO="${O2JAM_REPO:-$HOME/o2jam-offline-client}"
export WINEPREFIX="$WORK/prefix"
export WINEDEBUG=-all
export WINEDLLOVERRIDES="mscoree,mshtml="
PYVER=3.11.9

mkdir -p "$WORK"
say() { printf '\n==> %s\n' "$*"; }

say "1/6  wine prefix"
if [ ! -d "$WINEPREFIX/drive_c" ]; then
    wineboot -u >/dev/null 2>&1 || true
    sleep 3
fi
ls -d "$WINEPREFIX/drive_c" >/dev/null 2>&1 || { echo "   prefix not created"; exit 1; }
echo "   $WINEPREFIX"

say "2/6  windows python $PYVER"
EXE="$WORK/python-$PYVER-amd64.exe"
if [ ! -f "$EXE" ]; then
    curl -fL --retry 3 -o "$EXE" \
        "https://www.python.org/ftp/python/$PYVER/python-$PYVER-amd64.exe" || exit 1
fi
echo "   $(du -h "$EXE" | cut -f1) installer"

if ! wine "C:\\Py311\\python.exe" -c "print('hello')" >/dev/null 2>&1; then
    say "   running the installer silently (this takes a few minutes)"
    wine "$EXE" /quiet InstallAllUsers=0 TargetDir='C:\Py311' PrependPath=0 \
        Include_pip=1 Include_tcltk=1 Include_test=0 SimpleInstall=1 >/dev/null 2>&1
    sleep 5
fi
wine "C:\\Py311\\python.exe" -c "import sys;print('   python', sys.version.split()[0], 'on', sys.platform)" || exit 1

say "3/6  pip + pyinstaller inside wine"
wine "C:\\Py311\\python.exe" -m pip install --quiet --disable-pip-version-check \
    --no-warn-script-location pyinstaller pillow 2>&1 | tail -3
wine "C:\\Py311\\python.exe" -c "import PyInstaller, PIL;print('   pyinstaller', PyInstaller.__version__)" || exit 1

say "4/6  icon"
wine "C:\\Py311\\python.exe" "$REPO\\packaging\\make-icon.py" 2>&1 | tail -2

say "5/6  pyinstaller (windows .exe)"
rm -rf "$WORK/dist" "$WORK/build"
mkdir -p "$WORK/dist"
(cd "$REPO" && wine "C:\\Py311\\python.exe" -m PyInstaller --noconfirm --clean \
    --distpath "$WORK/dist" --workpath "$WORK/build" \
    "$REPO/packaging/o2jam-installer.spec" 2>&1 | tail -12)

EXE_OUT="$WORK/dist/O2Jam-Installer.exe"
if [ -f "$EXE_OUT" ]; then
    say "6/6  built"
    echo "   $(ls -la "$EXE_OUT" | awk '{print $5}') bytes -> $EXE_OUT"
    # PE sanity check + smoke test under wine
    file "$EXE_OUT" | sed 's/^/   /'
    echo "   ---- smoke test under wine ----"
    wine "$EXE_OUT" --self-test 2>&1 | tail -22
    echo "   ---- exit=${PIPESTATUS[0]} ----"
else
    say "6/6  FAILED -- no exe produced"
    ls -la "$WORK/dist" 2>&1
    exit 1
fi
