#!/usr/bin/env bash
# ============================================================================
#  Build the Linux installers -- a standalone binary and an AppImage.
#
#      bash packaging/build-linux.sh
#
#  Produces (in ./dist):
#      O2Jam-Installer                      single file, no Python needed
#      O2Jam-Installer-x86_64.AppImage      double-click, no install
#
#  Needs: python3 (venv), curl. Installs PyInstaller + Pillow into a private
#  virtualenv under ~/.cache/o2jam-packaging. Never calls sudo.
# ============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"
DIST="${DIST:-$REPO/dist}"
WORK="${O2JAM_PACKAGING_WORK:-$HOME/.cache/o2jam-packaging}"
VENV="$WORK/venv"
APPIMAGETOOL_URL="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"

say() { printf '\n\033[1;32m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
dim() { printf '    %s\n' "$*"; }

mkdir -p "$DIST" "$WORK"

say "1/5  packaging virtualenv"
if [ ! -x "$VENV/bin/pyinstaller" ]; then
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install -q --upgrade pip
    "$VENV/bin/pip" install -q pyinstaller pillow
fi
dim "pyinstaller $("$VENV/bin/pyinstaller" --version)"

say "2/5  icon"
"$VENV/bin/python" "$HERE/make-icon.py"

say "3/5  standalone binary (PyInstaller, one file)"
"$VENV/bin/pyinstaller" --noconfirm --clean \
    --distpath "$DIST" --workpath "$WORK/build" "$HERE/o2jam-installer.spec" >"$WORK/pyinstaller.log" 2>&1 \
    || { dim "pyinstaller failed -- tail of its log:"; tail -25 "$WORK/pyinstaller.log"; exit 1; }
BIN="$DIST/O2Jam-Installer"
dim "$BIN  ($(du -h "$BIN" | cut -f1))"

say "4/5  self-test of the built binary"
"$BIN" --self-test || { dim "the built binary failed its own self-test"; exit 1; }

if [ "${SKIP_APPIMAGE:-0}" = 1 ]; then
    say "5/5  AppImage skipped (SKIP_APPIMAGE=1)"
    exit 0
fi

say "5/5  AppImage"
TOOL="$WORK/appimagetool-x86_64.AppImage"
if [ ! -s "$TOOL" ]; then
    dim "downloading appimagetool (~9 MB) from the AppImage project"
    curl -fL --retry 3 -o "$TOOL" "$APPIMAGETOOL_URL"
fi
chmod +x "$TOOL"

# appimagetool is itself an AppImage: extracting it avoids needing FUSE to
# *build* (FUSE is only needed to run an AppImage).
rm -rf "$WORK/squashfs-root" "$WORK/AppDir"
( cd "$WORK" && "./appimagetool-x86_64.AppImage" --appimage-extract >/dev/null )

APP="$WORK/AppDir"
mkdir -p "$APP/usr/bin"
cp "$BIN" "$APP/usr/bin/O2Jam-Installer"
cp "$HERE/o2jam.png" "$APP/o2jam.png"
cp "$HERE/o2jam.png" "$APP/.DirIcon"
cp "$HERE/o2jam-installer.desktop" "$APP/o2jam-installer.desktop"
cat > "$APP/AppRun" <<'EOF'
#!/bin/bash
HERE="$(dirname "$(readlink -f "${0}")")"
exec "$HERE/usr/bin/O2Jam-Installer" "$@"
EOF
chmod +x "$APP/AppRun"

OUT="$DIST/O2Jam-Installer-x86_64.AppImage"
ARCH=x86_64 "$WORK/squashfs-root/AppRun" --no-appstream "$APP" "$OUT"
dim "$OUT  ($(du -h "$OUT" | cut -f1))"

say "done"
dim "binary   : $BIN"
dim "AppImage : $OUT"
dim "both run offline, need no Python and use no admin rights."
