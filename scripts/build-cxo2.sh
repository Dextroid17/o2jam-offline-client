#!/usr/bin/env bash
# ============================================================================
#  Build the NATIVE (Wine-free) O2Jam client: CXO2
#  - everything user-space (cmake fetched deps, no sudo)
#  - bundled deps: -DSFML_USE_SYSTEM_DEPS=OFF  (SFML builds mbedtls/libssh2)
#  - patches come from this repo's patches/ and are applied idempotently:
#      CXO2 + Genode before the build, the fetched SFML source after the first
#      configure (that's when CMake has downloaded it).
#  - log:  ${O2JAM_BUILD_LOG:-<CXO2>/../build.log}
#
#  usage: build-cxo2.sh            (all cores)
#         O2JAM_JOBS=8 build-cxo2.sh
# ============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
export PATH="$HOME/.local/bin:$PATH"

CXO2="${O2JAM_CXO2:-$HOME/o2jam/native/CXO2}"
# find the patch set: explicit env var wins, otherwise probe the layouts this
# repo ships with and the one the installer creates
PATCHES="${O2JAM_PATCHES:-}"
if [ -z "$PATCHES" ]; then
    for cand in "$HERE/../patches" "$HERE/patches" "$HERE"/../src/*/patches "$HOME/o2jam-offline-client/patches" "$CXO2/../patches"; do
        [ -f "$cand/01-cxo2-window-and-toolchain.patch" ] && { PATCHES="$(cd "$cand" && pwd)"; break; }
    done
fi
LOG="${O2JAM_BUILD_LOG:-$(dirname "$CXO2")/build.log}"
JOBS="${O2JAM_JOBS:-$(nproc 2>/dev/null || echo 4)}"
FLAGS="-DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DSFML_USE_SYSTEM_DEPS=OFF"

cd "$CXO2" || { echo "no CXO2 checkout at $CXO2" >&2; exit 1; }

FAILED=0
log() { echo "### $*" >> "$LOG"; }
run() { log "CMD: $*"; "$@" >> "$LOG" 2>&1; local rc=$?; log "EXIT: $rc $([ $rc -ne 0 ] && echo '<<< FAILED')"; [ $rc -ne 0 ] && FAILED=1; return $rc; }

show() { printf '    %s\n' "$*"; }

{
echo "=============================================================="
echo "CXO2 native build  --  started $(date)"
echo "  cmake : $(command -v cmake)  $(cmake --version 2>/dev/null | head -1)"
echo "  cxo2  : $CXO2"
echo "  jobs  : $JOBS"
echo "=============================================================="
} > "$LOG"

# ---------------------------------------------------------------- patches --
if [ -f "$PATCHES/01-cxo2-window-and-toolchain.patch" ]; then
    show "applying patches (CXO2 + Genode)"
    if ! O2JAM_CXO2="$CXO2" bash "$HERE/apply-patches.sh" --cxo2 "$CXO2" --patches "$PATCHES" >> "$LOG" 2>&1; then
        show "WARNING: patches did not all apply -- see $LOG"
        log "PATCH STEP: problems (see above)"
    fi
else
    show "no patch set found at $PATCHES -- building upstream as-is"
fi

# -------------------------------------------------------------- configure --
show "step 1/4  cmake configure (fetches SFML, Genode deps ...)"
run cmake -B build/linux $FLAGS || { show "configure failed -- see $LOG"; exit 1; }

# the SFML source only exists now, so its (small) patch is applied here and
# CMake is asked to configure once more so the change is actually picked up
SFML_PATCHED=0
for p in "$PATCHES"/02-*.patch; do
    [ -f "$p" ] || continue
    SFML_DIR="$(ls -d build/*/_deps/sfml-src 2>/dev/null | head -1)"
    if [ -n "$SFML_DIR" ]; then
        if O2JAM_CXO2="$CXO2" bash "$HERE/apply-patches.sh" --sfml --cxo2 "$CXO2" \
              --patches "$PATCHES" >> "$LOG" 2>&1; then
            grep -q "ok applied" "$LOG" && { SFML_PATCHED=1; show "step 2/4  SFML patch applied -- re-configuring"; }
        fi
    fi
done
if [ "$SFML_PATCHED" = 1 ]; then
    run cmake -B build/linux $FLAGS || show "re-configure complained -- continuing"
else
    show "step 2/4  SFML patch already in place (or no SFML yet)"
fi

# ------------------------------------------------------- resource compiler --
show "step 3/4  resource compiler (upstream requires it before the game)"
run cmake --build build/linux --target ResourceCompiler -j"$JOBS" || show "ResourceCompiler build failed"

RC="$(find bin -type f -name ResourceCompiler -perm -u+x 2>/dev/null | head -1)"
log "ResourceCompiler located at: ${RC:-<not found>}"
if [ -n "$RC" ]; then
    ( cd "$(dirname "$RC")" && ./ResourceCompiler >> "$LOG" 2>&1 )
    log "ResourceCompiler run EXIT: $?"
fi

# --------------------------------------------------------------- the game --
show "step 4/4  the game itself (this is the slow one)"
run cmake --build build/linux --target CXO2 -j"$JOBS" || show "CXO2 build failed"

{
echo "=============================================================="
echo "BUILD PHASE FINISHED $(date)   failed=$FAILED"
echo "binaries:"
find bin -type f -perm -u+x 2>/dev/null | sed 's/^/  /'
echo "=============================================================="
} >> "$LOG"

BIN="$CXO2/bin/linux/Release/OTwo"
if [ -x "$BIN" ]; then
    show "client: $BIN"
    exit 0
fi
show "no client binary at $BIN -- full log: $LOG"
tail -25 "$LOG" | sed 's/^/    /'
exit 1
