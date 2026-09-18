# O2Jam Offline Client — Godot Rewrite

A complete rewrite of the client as a **native Godot 4 desktop app** for
Windows and Linux. The old C++/SFML patch stack is gone; what remains is one
codebase, one scene tree, and an audio path tuned like a competitive rhythm
game — because that's what reproduces the 2003 feel. Those games weren't
magic; they just had an unobstructed audio path. So does this.

```
MUSIC AS CLOCK
  song_time = playback_position
            + AudioServer.get_time_since_last_mix()
            - AudioServer.get_output_latency()
            + user_offset            (calibration screen, ±100 ms)
```

Judgement is computed against that clock and nothing else — never frame
deltas, never wall time. Default windows: **COOL ±40 ms / GOOD ±80 ms /
BAD ±120 ms** (`scripts/core/judgement.gd`).

## Why it's fast

| Decision | Where | Why |
|---|---|---|
| Output latency 5 ms | `project.godot` → `audio/driver/output_latency` | Desktop drivers (WASAPI shared, PipeWire) can handle what a browser couldn't |
| Mix rate 48000 Hz | `project.godot` → `audio/driver/mix_rate` | Matches the native rate of modern devices; mismatched rates cause resampling jitter that *feels like timing drift* |
| VSync off, 240 FPS cap | `project.godot` + `Settings.apply_video_settings()` | Input polling must not be frame-quantized to the display refresh |
| Accumulated input off | `Settings._ready()` | Input events dispatch immediately, not batched per frame |
| Multi-threaded rendering | `project.godot` → `rendering/driver/threads/thread_model` | Keep the main thread free for input + judgement |
| Live latency readout | bottom-left HUD in gameplay | Proof, not vibes: you can *see* your output latency and FPS mid-song |

## Running from source

1. Install **Godot 4.4+** (standard build).
2. Open the project folder, press F5.
3. First stop: **Calibration** (main menu). Tap SPACE on the metronome beat
   12 times, hit *Use suggested*, *Save*. Every sound card/monitor combo is
   different — this step is not optional if you care about COOLs.

The game ships with a **built-in demo song** (synthesized track + generated
chart) so everything — gameplay, judgement, calibration — works with zero
external files.

## Songs: bring your own assets

No game assets are distributed here. Drop charts into the songs folder
(shown on the song-select screen; defaults to `user://songs`):

- **`.ojn`** — real O2Jam charts. Metadata + notes for EX/NX/HX are parsed.
  For audio, place a decoded `.ogg`/`.mp3`/`.wav` with the same base name as
  the `.ojm` next to the chart. Encrypted OJM containers (M30/OMC/OMZ) are
  **not** decoded — the game falls back to a metronome at the chart's BPM so
  the chart is still playable.
- **`.json`** — simple native format:

```json
{
  "title": "My Song", "artist": "Me", "bpm": 150,
  "audio": "song.ogg",
  "difficulty": "HX", "level": 20,
  "notes": [
    {"t": 1000.0, "lane": 0},
    {"t": 1200.0, "lane": 3, "end": 1800.0}
  ]
}
```

(`t`/`end` in milliseconds, `lane` 0–6, `end` optional = long note.)

### Known limits (honest list)

- OJN timing assumes the header BPM; charts with mid-song BPM events will
  drift. The timing code is structured so BPM events can be added later.
- OJN strings in legacy Korean codepages degrade to `?` if not valid UTF-8.
- Key-sounds (per-note samples from the OJM) are parsed but not played;
  the song plays as a single mixed track.

## OS-specific tuning

### Linux (PipeWire)

Works out of the box via PulseAudio/PipeWire. For the real O2Jam feel:

```bash
bash tools/pipewire-lowlatency.sh
```

Drops `default.clock.quantum` to 64 samples (~1.3 ms/buffer), locks the
clock at 48 kHz, and checks realtime scheduling (rtkit). Same tuning
competitive osu! players use — DirectSound-era latency. Verify with
`pw-top` (QUANT = 64) and the in-game latency readout (< 10 ms).

### Windows

Godot uses **WASAPI shared mode** — solid, ~10–15 ms achievable with the
5 ms output-latency setting. For a mania game, WASAPI shared + calibration
is plenty. If you ever need tighter than that, that's the one case for a
native engine or an ASIO audio plugin — not before.

## Export workflow

```bash
# 1. Install export templates (Editor → Manage Export Templates, or:)
godot --headless --path . --import

# 2. Build both presets — same project, no code changes
godot --headless --path . --export-release "Linux Desktop"   builds/linux/o2jam.x86_64
godot --headless --path . --export-release "Windows Desktop" builds/windows/o2jam.exe
```

- **Linux**: ship the raw binary + `packaging/linux/o2jam-launch.sh`, or wrap
  in an AppImage/Flatpak. Godot exports a self-contained executable either way.
- **Windows**: ZIP is fine (portable). For an installer:
  `iscc packaging\windows\o2jam-installer.iss` (Inno Setup 6).
- **Test calibration on a real Windows machine** — do not assume your Linux
  tuning carries over. Different driver stack, different offset.
- **Distribution**: itch.io (one page, players pick their OS) or Steam (one
  depot per OS, same build pipeline).

## Project layout

```
project.godot              audio/display/rendering policy (the spec, baked in)
export_presets.cfg         Linux Desktop + Windows Desktop presets
scenes/main.tscn           single root scene
scripts/
  autoload/settings.gd     config, input map, vsync/FPS policy
  autoload/audio_clock.gd  music-as-clock (the timing source of truth)
  core/chart.gd            chart + note model
  core/judgement.gd        COOL/GOOD/BAD/MISS windows
  core/chart_library.gd    .ojn / .json / demo chart loading
  core/audio_gen.gd        synthesized metronome + demo track (sample-accurate)
  game/gameplay.gd         7-lane gameplay, input, judgement, rendering
  ui/                      menu, song select, calibration, results
tools/pipewire-lowlatency.sh
packaging/                 Linux launcher, Inno Setup script
```

## License

Code: MIT. O2Jam and all associated assets are the property of their
respective owners; this is an unofficial fan project that distributes no
game content.
