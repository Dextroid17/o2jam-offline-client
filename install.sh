#!/usr/bin/env bash
# ============================================================================
#                     O2Jam Offline Client -- installer
#
#   One line:
#     curl -fsSL https://raw.githubusercontent.com/Dextroid17/o2jam-offline-client/main/install.sh | bash
#
#   Or, with your game data already in mind:
#     curl -fsSL .../install.sh | bash -s -- --assets "$HOME/O2Jam"
#
#   What it does, in order:
#     1. checks the tools it needs (never installs anything, never uses sudo)
#     2. clones this project + the upstream CXO2 client into ~/o2jam
#     3. applies our patches (window behaviour, modern-toolchain fixes)
#     4. builds the client  (~15-40 min, all 16 cores if you have them)
#     5. links YOUR OWN O2Jam data into the build
#     6. installs a menu entry + icon (+ Desktop icon)
#
#   Options:  --prefix DIR   --assets DIR   --jobs N   --src DIR
#             --no-build     --no-shortcut  --no-venv  --skip-patches
#             --gui          --yes
#
#   Nothing is downloaded except source code. No game data. No sudo. Ever.
# ============================================================================
set -uo pipefail

VERSION="1.1"
REPO_DEFAULT="https://github.com/Dextroid17/o2jam-offline-client.git"
CXO2_DEFAULT="https://github.com/SirusDoma/CXO2.git"
CXO2_REF_DEFAULT="720f966"          # the commit our patches are verified against

PREFIX="${O2JAM_HOME:-$HOME/o2jam}"
ASSETS="" ; BRANCH="main" ; REPO="$REPO_DEFAULT" ; CXO2_URL="$CXO2_DEFAULT"
CXO2_REF="$CXO2_REF_DEFAULT"
JOBS="$(nproc 2>/dev/null || echo 4)"
DO_BUILD=1 ; DO_SHORTCUT=1 ; DO_VENV=1 ; DO_PATCHES=1 ; ASSUME_YES=0 ; GUI=0 ; SRC_DIR=""

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)     PREFIX="$2"; shift 2 ;;
        --assets)     ASSETS="$2"; shift 2 ;;
        --repo)       REPO="$2"; shift 2 ;;
        --branch)     BRANCH="$2"; shift 2 ;;
        --cxo2-url)   CXO2_URL="$2"; shift 2 ;;
        --cxo2-ref)   CXO2_REF="$2"; shift 2 ;;
        --jobs|-j)    JOBS="$2"; shift 2 ;;
        --src)        SRC_DIR="$2"; shift 2 ;;
        --no-build)   DO_BUILD=0; shift ;;
        --no-shortcut) DO_SHORTCUT=0; shift ;;
        --no-venv)    DO_VENV=0; shift ;;
        --skip-patches) DO_PATCHES=0; shift ;;
        --gui)        GUI=1; shift ;;
        -y|--yes)     ASSUME_YES=1; shift ;;
        -h|--help)    sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "install.sh: unknown option '$1'  (try --help)" >&2; exit 2 ;;
    esac
done

# ---------------------------------------------------------------- pretty ---
if [ -t 1 ]; then B=$'\033[1m'; D=$'\033[2m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; N=$'\033[0m'
else B=""; D=""; G=""; Y=""; R=""; N=""; fi
step() { printf '\n%s==>%s %s%s\n' "$B$G" "$N" "$B" "$*$N"; }
info() { printf '    %s\n' "$*"; }
dim()  { printf '    %s%s%s\n' "$D" "$*" "$N"; }
warn() { printf '    %s!%s %s\n' "$Y" "$N" "$*"; }
die()  { printf '\n%sxx%s  %s\n\n' "$R" "$N" "$*" >&2; exit 1; }

# ask() -- prompts come from the TERMINAL, not stdin, because when this script
# arrives through a pipe (`curl | bash`) stdin *is the script itself*.
ask() {
    local q="$1" ans
    [ "$ASSUME_YES" = 1 ] && return 0
    if [ ! -r /dev/tty ]; then return 0; fi      # non-interactive: take defaults
    printf '    %s [Y/n] ' "$q" > /dev/tty
    read -r ans < /dev/tty || return 0
    case "${ans:-y}" in [Nn]*) return 1 ;; *) return 0 ;; esac
}

cat <<BANNER
${B}
  ============================================================
    O2Jam Offline Client -- installer v$VERSION  (Linux)
    native client, no Wine, no emulator, no VM
  ============================================================
${N}
  install dir : ${B}$PREFIX${N}
  source      : $REPO   (branch $BRANCH)
  client      : $CXO2_URL  @ $CXO2_REF
  game data   : ${ASSETS:-<you'll be asked / point me later with --assets>}
  build       : $([ "$DO_BUILD" = 1 ] && echo "yes, $JOBS jobs" || echo "skipped")
BANNER

# ------------------------------------------------------------- 1. tools ----
step "1/6  checking the toolchain"
MISSING=""
need() { command -v "$1" >/dev/null 2>&1 || MISSING="$MISSING $1"; }
need git ; need cmake ; need make
command -v g++ >/dev/null 2>&1 || command -v clang++ >/dev/null 2>&1 || MISSING="$MISSING g++"
need python3

if [ -n "$MISSING" ]; then
    warn "missing:$MISSING"
    echo
    dim "Install them yourself, then re-run me. I never call sudo."
    if   command -v pacman  >/dev/null 2>&1; then dim "  sudo pacman -S git cmake make gcc python"
    elif command -v apt     >/dev/null 2>&1; then dim "  sudo apt install git cmake make g++ python3 python3-venv"
    elif command -v dnf     >/dev/null 2>&1; then dim "  sudo dnf install git cmake make gcc-c++ python3"
    elif command -v zypper  >/dev/null 2>&1; then dim "  sudo zypper install git cmake make gcc-c++ python3"
    fi
    exit 1
fi
info "git $(git --version | awk '{print $3}')"
info "$( { cmake --version 2>/dev/null | head -1; } )"
info "$( { ${CXX:-g++} --version 2>/dev/null || g++ --version; } | head -1)"
info "python $(python3 -c 'import sys;print(".".join(map(str,sys.version_info[:3])))')"
info "$JOBS build jobs"

# ------------------------------------------------------------ 2. layout ----
step "2/6  creating the layout under $PREFIX"
mkdir -p "$PREFIX"/{src,native,tools} || die "cannot create $PREFIX"
info "$PREFIX/src      this project"
info "$PREFIX/native   scripts + the built client"
info "$PREFIX/tools    python venv for the window tooling"

# ----------------------------------------------------------- 3. sources ----
step "3/6  getting the sources"

# this project: use the checkout we're sitting in, else clone it
if [ -z "$SRC_DIR" ]; then
    HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"
else
    HERE="$SRC_DIR"
fi
if [ -n "$HERE" ] && [ -f "$HERE/scripts/apply-patches.sh" ]; then
    info "using the checkout at $HERE"
    SRC="$HERE"
else
    SRC="$PREFIX/src/o2jam-offline-client"
    if [ -d "$SRC/.git" ]; then
        info "updating $SRC"
        git -C "$SRC" fetch --depth 1 origin "$BRANCH" >/dev/null 2>&1 \
            && git -C "$SRC" checkout -q "$BRANCH" >/dev/null 2>&1 \
            && git -C "$SRC" pull -q --ff-only >/dev/null 2>&1
    else
        info "cloning $REPO"
        git clone -q --branch "$BRANCH" --depth 1 "$REPO" "$SRC" \
            || die "clone failed -- is the repo public? ($REPO)"
    fi
fi
[ -f "$SRC/scripts/run-windowed.sh" ] || die "$SRC does not look like this project"

# our scripts live next to the client, exactly like the layout they expect
for f in "$SRC"/scripts/*; do
    cp -f "$f" "$PREFIX/native/" 2>/dev/null
done
chmod +x "$PREFIX/native"/*.sh 2>/dev/null
info "scripts  -> $PREFIX/native/"

CXO2="${O2JAM_CXO2:-$PREFIX/native/CXO2}"
if [ -d "$CXO2/.git" ]; then
    info "CXO2 already present at $CXO2"
else
    info "cloning CXO2 (with its Genode submodule) -- this is the big one"
    git clone -q "$CXO2_URL" "$CXO2" || die "CXO2 clone failed"
fi
if git -C "$CXO2" cat-file -e "${CXO2_REF}^{commit}" 2>/dev/null; then
    git -C "$CXO2" checkout -q "$CXO2_REF" 2>/dev/null \
        && info "CXO2 pinned to $CXO2_REF  (the commit our patches are tested against)"
else
    warn "cannot find commit $CXO2_REF -- staying on the default branch"
fi
git -C "$CXO2" submodule update --init --recursive >/dev/null 2>&1 \
    && info "submodules ready" || warn "submodule init had problems (see above)"

# ------------------------------------------------------------ 4. patches ----
step "4/6  applying patches"
if [ "$DO_PATCHES" = 1 ]; then
    O2JAM_CXO2="$CXO2" bash "$PREFIX/native/apply-patches.sh" --cxo2 "$CXO2" \
        --patches "$SRC/patches"
    PATCH_RC=$?
    [ "$PATCH_RC" = 0 ] || warn "some patches did not apply -- the build will probably fail, but let's try"
else
    dim "skipped (--skip-patches) -- the client will build unpatched"
fi

# --------------------------------------------------------------- 5. venv ---
step "5/6  python venv for the window tooling"
PYBIN=""
if [ "$DO_VENV" = 1 ]; then
    if python3 -m venv "$PREFIX/tools/venv" >>"$PREFIX/tools/venv.log" 2>&1; then
        "$PREFIX/tools/venv/bin/pip" install -q --upgrade pip >>"$PREFIX/tools/venv.log" 2>&1
        if "$PREFIX/tools/venv/bin/pip" install -q python-xlib >>"$PREFIX/tools/venv.log" 2>&1; then
            PYBIN="$PREFIX/tools/venv/bin/python"
            info "python-xlib installed -> $PYBIN"
        else
            warn "python-xlib install failed (log: $PREFIX/tools/venv.log)"
        fi
    else
        warn "venv creation failed -- is python3-venv installed? (log: $PREFIX/tools/venv.log)"
    fi
else
    dim "skipped (--no-venv); the game still runs, you just lose the auto-placement tooling"
fi
[ -n "$PYBIN" ] || PYBIN="$(command -v python3)"

# a launcher that carries any non-default paths, so the .desktop entry is dumb
cat > "$PREFIX/native/o2jam-run.sh" <<EOF
#!/usr/bin/env bash
# generated by install.sh -- binds the launcher to this install
export O2JAM_CXO2="$CXO2"
export O2JAM_PY="$PYBIN"
exec bash "$PREFIX/native/o2jam-launch.sh" "\$@"
EOF
chmod +x "$PREFIX/native/o2jam-run.sh"

# ---------------------------------------------------------------- build ----
step "6/6  building the client"
if [ "$DO_BUILD" = 1 ]; then
    dim "this is the long part: 15-40 minutes. Log: $PREFIX/native/build.log"
    if ask "Start the build now?"; then
        LOG="$PREFIX/native/build.log" O2JAM_CXO2="$CXO2" \
            bash "$PREFIX/native/build-cxo2.sh" || warn "build returned non-zero -- check the log"
        BIN="$CXO2/bin/linux/Release/OTwo"
        [ -x "$BIN" ] && info "client built: $BIN" \
                      || warn "no client binary at $BIN -- that's the thing to fix next"
    else
        dim "fine -- later: O2JAM_CXO2=$CXO2 bash $PREFIX/native/build-cxo2.sh"
    fi
else
    dim "skipped (--no-build)"
fi

# --------------------------------------------------------------- assets ----
if [ -n "$ASSETS" ]; then
    step "linking your game data"
    O2JAM_CXO2="$CXO2" bash "$PREFIX/native/link-assets.sh" "$ASSETS" --cxo2 "$CXO2"
else
    step "game data"
    dim "I did not touch your game data. Point me at it whenever you like:"
    dim "  O2JAM_CXO2=$CXO2 bash $PREFIX/native/link-assets.sh '/path/to/your/o2jam/data'"
    dim "  (the folder that contains Image/ and Music/)"
fi

# ------------------------------------------------------------ shortcuts ----
if [ "$DO_SHORTCUT" = 1 ]; then
    step "menu entry + icon"
    O2JAM_CXO2="$CXO2" O2JAM_LAUNCHER="$PREFIX/native/o2jam-run.sh" \
        bash "$PREFIX/native/install-shortcut.sh" || warn "shortcut install hiccup"
else
    dim "shortcut install skipped (--no-shortcut)"
fi

if [ "$GUI" = 1 ]; then
    step "launching the graphical installer"
    exec python3 "$SRC/installer/o2jam-installer.py" --prefix "$PREFIX"
fi

cat <<DONE

${B}${G}  ============================================================
    that's it -- O2Jam should be yours now
  ============================================================${N}

  play it:          ${B}bash $PREFIX/native/run-windowed.sh${N}
  or from the menu: ${B}O2Jam Offline Client${N}
  whole screen:     ${B}O2JAM_WINDOW=screen bash $PREFIX/native/run-windowed.sh${N}
  720p:             ${B}O2JAM_WINDOW=720p   bash $PREFIX/native/run-windowed.sh${N}

  window size/pos are X11 pixels: on a scaled Wayland desktop multiply your real
  resolution by the XWayland scale factor. The default preset is 1080p.

  build log:        $PREFIX/native/build.log
  menu entry off:   bash $PREFIX/native/install-shortcut.sh --uninstall
  everything off:   rm -rf $PREFIX   (then run the uninstall line above while the
                    scripts still exist, or delete the menu entry by hand)

  Something broken? Read docs/SETUP.md -- it has the errors I actually hit.
DONE
