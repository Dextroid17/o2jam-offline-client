#!/usr/bin/env bash
# Launcher for the raw Linux binary. Godot exports a self-contained
# executable; this script just adds a sane environment around it.

set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

# Hint PipeWire toward a small quantum for this process. The system-wide
# tuning lives in tools/pipewire-lowlatency.sh; this is the per-launch nudge.
export PIPEWIRE_LATENCY="${PIPEWIRE_LATENCY:-64/48000}"

# Make sure the game never accidentally runs with vsync forced on by the
# compositor — input polling must not be frame-quantized.
export __GL_SYNC_TO_VBLANK=0
export vblank_mode=0

exec ./o2jam.x86_64 "$@"
