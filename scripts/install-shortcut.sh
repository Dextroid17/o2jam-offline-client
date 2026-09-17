#!/usr/bin/env bash
# ============================================================================
#  install-shortcut.sh -- app-menu entry + icon (+ optional Desktop icon)
#
#  Everything goes in user space: ~/.local/share/applications, ~/.local/share
#  /icons, ~/Desktop. No sudo, ever. `--uninstall` puts it all back.
#
#  usage:
#     install-shortcut.sh [--cxo2 DIR] [--no-desktop] [--uninstall]
# ============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APPS="$HOME/.local/share/applications"
ICONS="$HOME/.local/share/icons/hicolor/256x256/apps"
ENTRY="$APPS/o2jam-offline.desktop"
DESKTOP_ICON="$HOME/Desktop/O2Jam.desktop"
WANT_DESKTOP=1 ; UNINSTALL=0

while [ $# -gt 0 ]; do
    case "$1" in
        --no-desktop) WANT_DESKTOP=0; shift ;;
        --uninstall)  UNINSTALL=1; shift ;;
        -h|--help)    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "install-shortcut.sh: unknown option '$1'" >&2; exit 2 ;;
    esac
done

if [ "$UNINSTALL" = 1 ]; then
    rm -f "$ENTRY" "$DESKTOP_ICON" "$ICONS/o2jam.png"
    command -v update-desktop-database >/dev/null && update-desktop-database "$APPS" 2>/dev/null
    command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -qtf "$HOME/.local/share/icons/hicolor" 2>/dev/null
    echo "removed the O2Jam menu entry, Desktop icon and installed icon."
    echo "(the launcher scripts and the build itself are untouched)"
    exit 0
fi

LAUNCHER="${O2JAM_LAUNCHER:-$HERE/o2jam-launch.sh}"
[ -f "$LAUNCHER" ] || { echo "install-shortcut.sh: $LAUNCHER is missing" >&2; exit 1; }
chmod +x "$LAUNCHER" "$HERE/run-windowed.sh" 2>/dev/null

# --- icon ------------------------------------------------------------------
ICON_SRC=""
for c in "$HERE/../desktop/o2jam.png" "$HERE/o2jam.png" ; do
    [ -f "$c" ] && { ICON_SRC="$c"; break; }
done
ICON_LINE="Icon=o2jam"
if [ -n "$ICON_SRC" ]; then
    mkdir -p "$ICONS"
    cp -f "$ICON_SRC" "$ICONS/o2jam.png"
    command -v gtk-update-icon-cache >/dev/null && \
        gtk-update-icon-cache -qtf "$HOME/.local/share/icons/hicolor" 2>/dev/null
    ICON_LINE="Icon=o2jam"
else
    ICON_LINE="Icon=applications-games"   # theme fallback
fi

# --- the .desktop entry ----------------------------------------------------
mkdir -p "$APPS"
cat > "$ENTRY" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=O2Jam Offline Client
Comment=O2Jam, running natively -- no Wine, no emulator
Exec=bash $LAUNCHER
$ICON_LINE
Terminal=false
Categories=Game;Music;
Keywords=o2jam;rhythm;music;game;
StartupNotify=true
StartupWMClass=O2-JAM
EOF
chmod +x "$ENTRY"

if [ "$WANT_DESKTOP" = 1 ] && [ -d "$HOME/Desktop" ]; then
    cp -f "$ENTRY" "$DESKTOP_ICON"
    chmod +x "$DESKTOP_ICON"
    # KDE/GNOME need the "trusted" flag before they will run a Desktop file
    command -v gio >/dev/null && gio set "$DESKTOP_ICON" metadata::trusted true 2>/dev/null
    command -v kwriteconfig6 >/dev/null && \
        kwriteconfig6 --file "$HOME/.config/kiorc" >/dev/null 2>&1
fi

command -v update-desktop-database >/dev/null && update-desktop-database "$APPS" 2>/dev/null

echo "== installed =="
echo "  menu entry : $ENTRY"
[ "$WANT_DESKTOP" = 1 ] && echo "  desktop    : $DESKTOP_ICON"
[ -n "$ICON_SRC" ] && echo "  icon       : $ICONS/o2jam.png"
echo "  launcher   : $LAUNCHER  (-> run-windowed.sh)"
echo
echo "If the Desktop icon shows a generic question-mark, right-click it and pick"
echo "'Allow this file to run' / 'Trust' once -- that's a desktop-environment rule,"
echo "not something the installer can do for you."
