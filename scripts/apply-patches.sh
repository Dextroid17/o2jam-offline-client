#!/usr/bin/env bash
# ============================================================================
#  apply-patches.sh -- put this repo's patch set onto a CXO2 checkout.
#
#  Idempotent: re-running it is safe. For every patch it reports
#      ok applied   |  ok already applied  |  FAILED
#
#  usage:
#     apply-patches.sh [--cxo2 DIR] [--patches DIR] [--check] [--sfml] [--quiet]
#
#     (no flags)   patch the CXO2 checkout AND its Genode submodule
#     --sfml       only patch the SFML source that CMake fetched (run this
#                  AFTER the first `cmake -B build/linux ...` configure step,
#                  then configure once more so CMake picks the change up)
#     --check      dry run: verify everything would apply, change nothing
# ============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CXO2="${O2JAM_CXO2:-$HOME/o2jam/native/CXO2}"
# find the patch set: --patches / $O2JAM_PATCHES win, otherwise probe the layouts
# this repo ships with and the one the installer creates
PATCHES="${O2JAM_PATCHES:-}"
if [ -z "$PATCHES" ]; then
    for cand in "$HERE/../patches" "$HERE/patches" "$HERE"/../src/*/patches "$HOME/o2jam-offline-client/patches" "$CXO2/../patches"; do
        [ -f "$cand/01-cxo2-window-and-toolchain.patch" ] && { PATCHES="$(cd "$cand" && pwd)"; break; }
    done
fi
MODE=source ; CHECK=0 ; QUIET=0

while [ $# -gt 0 ]; do
    case "$1" in
        --cxo2)    CXO2="$2"; shift 2 ;;
        --patches) PATCHES="$2"; shift 2 ;;
        --check)   CHECK=1; shift ;;
        --sfml)    MODE=sfml; shift ;;
        --quiet)   QUIET=1; shift ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "apply-patches.sh: unknown argument '$1'" >&2; exit 2 ;;
    esac
done

[ -n "$PATCHES" ] || {
    echo "apply-patches.sh: no patch set found -- pass --patches DIR or set O2JAM_PATCHES" >&2
    exit 2
}
[ -d "$PATCHES" ] || { echo "apply-patches.sh: patch directory not found -- $PATCHES" >&2; exit 2; }

say()  { [ "$QUIET" = 1 ] || echo "$*"; }
warn() { echo "$*" >&2; }

# --- where did CMake put SFML? ---------------------------------------------
find_sfml() {
    local d
    for d in "$CXO2"/build/*/_deps/sfml-src; do
        [ -d "$d/.git" ] && { printf '%s\n' "$d"; return 0; }
        [ -d "$d" ] && { printf '%s\n' "$d"; return 0; }
    done
    return 1
}

# --- apply one patch to one repo -------------------------------------------
# returns 0 = applied or already applied, 1 = failed, 2 = repo missing
apply_one() {
    local repo="$1" patch="$2" label="$3"
    local name; name="$(basename "$patch")"

    if [ ! -d "$repo" ]; then
        warn "  ?  $label: directory not found -- $repo"
        return 2
    fi
    if [ ! -f "$patch" ]; then
        warn "  ?  $label: patch not found -- $patch"
        return 2
    fi

    # already applied? (reverse-apply check succeeds only if it is)
    if git -C "$repo" apply --reverse --check "$patch" 2>/dev/null; then
        say "  ok already applied  $name  ($label)"
        return 0
    fi

    if [ "$CHECK" = 1 ]; then
        if git -C "$repo" apply --check "$patch" 2>/dev/null; then
            say "  ok would apply     $name  ($label)"
            return 0
        fi
        warn "  !! FAILED (dry run) $name  ($label)"
        git -C "$repo" apply --check "$patch" 2>&1 | sed 's/^/     /' >&2
        return 1
    fi

    if git -C "$repo" apply --3way "$patch" 2>/dev/null \
       || git -C "$repo" apply "$patch" 2>/dev/null; then
        say "  ok applied         $name  ($label)"
        return 0
    fi

    warn "  !! FAILED           $name  ($label)"
    git -C "$repo" apply --check "$patch" 2>&1 | sed 's/^/     /' >&2
    warn "     ...the checkout is probably not at the expected base commit."
    warn "     ...try: git -C '$repo' log --oneline -1   (expected $(base_for "$name"))"
    return 1
}

base_for() {
    case "$1" in
        01-*)      echo "CXO2 720f966" ;;
        02-*)      echo "whatever the fetch_content pin resolves to" ;;
        03-*)      echo "the Genode commit CXO2 pins" ;;
    esac
}

rc=0
if [ "$MODE" = sfml ]; then
    SFML="$(find_sfml)" || {
        warn "apply-patches.sh: no SFML source under $CXO2/build/*/_deps/ -- run the"
        warn "  cmake configure step first (scripts/build-cxo2.sh does it for you)."
        exit 1
    }
    say "== patching fetched SFML =="
    apply_one "$SFML" "$PATCHES"/02-*.patch "sfml-src" || rc=1
else
    say "== patching CXO2 =="
    for p in "$PATCHES"/01-*.patch; do
        apply_one "$CXO2" "$p" "CXO2" || rc=1
    done

    say "== patching Genode (submodule) =="
    if [ -d "$CXO2/modules/Genode/.git" ] || [ -f "$CXO2/modules/Genode/.git" ]; then
        apply_one "$CXO2/modules/Genode" "$PATCHES"/03-*.patch "Genode" || rc=1
    else
        warn "  ?  Genode submodule not checked out in $CXO2/modules/Genode"
        warn "     run: git -C '$CXO2' submodule update --init --recursive"
        rc=1
    fi
fi

if [ "$rc" = 0 ]; then
    say "== patch set complete =="
else
    say "== finished WITH PROBLEMS (see above) =="
fi
exit "$rc"
