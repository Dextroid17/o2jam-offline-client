#!/usr/bin/env bash
# PipeWire low-latency tuning for rhythm games (the same tuning competitive
# osu! players use — it gets you to DirectSound-era latency on Linux).
#
# What it does:
#   - Writes a user-level PipeWire config dropping the audio quantum to 64
#     samples (~1.3 ms per buffer at 48 kHz), min 32 / max 128.
#   - PipeWire already requests realtime scheduling via rtkit on most distros;
#     this script just verifies that path is healthy.
#
# Safe to re-run. Only touches files under ~/.config/pipewire.

set -euo pipefail

CONF_DIR="$HOME/.config/pipewire/pipewire.conf.d"
CONF_FILE="$CONF_DIR/99-o2jam-lowlatency.conf"

mkdir -p "$CONF_DIR"
cat > "$CONF_FILE" <<'EOF'
context.properties = {
    # 48 kHz to match the game's mix rate — no resampling, no jitter.
    default.clock.rate        = 48000
    # 64-sample quantum ≈ 1.3 ms per buffer. If you hear crackling on a weak
    # CPU, raise to 128. Below 32 is instability territory, not performance.
    default.clock.quantum     = 64
    default.clock.min-quantum = 32
    default.clock.max-quantum = 128
}
EOF

echo "Wrote $CONF_FILE"

# Realtime scheduling check: PipeWire asks rtkit for RT priority automatically.
if ! command -v rtkitctl >/dev/null 2>&1 && ! systemctl --user list-unit-files 2>/dev/null | grep -q rtkit; then
    if ! ps -e | grep -q rtkit-daemon; then
        echo "NOTE: rtkit-daemon not detected. Install 'rtkit' (or 'libpipewire' with"
        echo "      realtime support) so the audio thread gets RT priority."
    fi
fi

echo "Restarting PipeWire user services..."
systemctl --user restart pipewire pipewire-pulse wireplumber 2>/dev/null || \
    systemctl --user restart pipewire pipewire-pulse 2>/dev/null || true

echo
echo "Done. Verify with:  pw-top   (the QUANT column should read 64 while the game runs)"
echo "In-game, the bottom-left readout should show output latency under ~10 ms."
