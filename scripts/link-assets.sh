#!/usr/bin/env bash
# ============================================================================
#  link-assets.sh -- point the built client at YOUR OWN O2Jam data.
#
#  No game data is downloaded, copied or redistributed by this script: it only
#  creates symlinks (junctions on Windows, see install.ps1) from the CXO2
#  directory to the data directory you already own.
#
#  usage:
#     link-assets.sh /path/to/your/o2jam/data [--cxo2 DIR] [--copy] [--list]
#
#  The data directory is the folder that contains the client folders, typically:
#     Image/    (avatar.opa, Interface1.opi, Playing1.opi, OJNList.dat ...)
#     Music/    (*.ojn charts + *.ojm audio)
#     and optionally Interface*/ Avatar/ etc.
# ============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CXO2="${O2JAM_CXO2:-$HOME/o2jam/native/CXO2}"
COPY=0 ; LIST=0 ; SRC=""

while [ $# -gt 0 ]; do
    case "$1" in
        --cxo2)  CXO2="$2"; shift 2 ;;
        --copy)  COPY=1; shift ;;
        --list)  LIST=1; shift ;;
        -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "link-assets.sh: unknown option '$1'" >&2; exit 2 ;;
        *)  SRC="$1"; shift ;;
    esac
done

[ -d "$CXO2" ] || { echo "link-assets.sh: no CXO2 checkout at $CXO2" >&2; exit 1; }

if [ "$LIST" = 1 ]; then
    echo "top-level entries in $CXO2:"
    for e in "$CXO2"/*; do
        [ -e "$e" ] || continue
        if [ -L "$e" ]; then
            printf '  %-14s -> %s\n' "$(basename "$e")" "$(readlink "$e")"
        else
            printf '  %-14s (real)\n' "$(basename "$e")"
        fi
    done
    exit 0
fi

if [ -z "$SRC" ]; then
    echo "usage: link-assets.sh /path/to/your/o2jam/data [--cxo2 DIR] [--copy]" >&2
    echo "  (a folder containing Image/ or Music/ -- --list shows current state)" >&2
    exit 2
fi

SRC="$(cd "$SRC" 2>/dev/null && pwd)" || { echo "link-assets.sh: '$SRC' is not a directory" >&2; exit 1; }

# Which folders does the client actually need?
CANDS="Image Music Interface1 Interface Interface3 Avatar Effect"
FOUND=0
for d in $CANDS; do
    [ -d "$SRC/$d" ] && FOUND=$((FOUND+1))
done
if [ "$FOUND" = 0 ]; then
    echo "link-assets.sh: no Image/, Music/ (or similar) inside $SRC" >&2
    echo "  point me at the folder that CONTAINS those directories." >&2
    exit 1
fi

linked=0
for d in $CANDS; do
    [ -d "$SRC/$d" ] || continue
    tgt="$CXO2/$d"
    if [ -e "$tgt" ] && [ ! -L "$tgt" ]; then
        # already there (the build may ship a stub Image/ or Music/ dir)
        if [ "$COPY" = 1 ]; then
            echo "  copying $d  (existing directory kept, merging)"
            cp -rn "$SRC/$d/." "$tgt/" 2>/dev/null
            linked=$((linked+1))
            continue
        fi
        if [ -z "$(ls -A "$tgt" 2>/dev/null)" ]; then
            rmdir "$tgt" 2>/dev/null || true
        else
            echo "  keeping existing $d/  (already populated -- not touching it)"
            continue
        fi
    fi
    if [ "$COPY" = 1 ]; then
        echo "  copying $d  ->  $tgt"
        cp -r "$SRC/$d" "$CXO2/" && linked=$((linked+1))
    else
        ln -sfn "$SRC/$d" "$tgt" && { echo "  linked  $d  ->  $SRC/$d"; linked=$((linked+1)); }
    fi
done

echo
echo "== $linked entr$( [ "$linked" = 1 ] && echo y || echo ies ) wired up =="
echo "   run:  bash $HERE/run-windowed.sh"
