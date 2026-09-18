# AGENTS.md — O2Jam Godot (offline client)

> For the agent (Hermes) working on this machine. You are handed an existing,
> working project. Your job is local setup, verification, tuning, and iteration.
> The architecture was deliberately designed and headless-validated.
> **Measure, don't guess.**

## What this repo is

`main` is a complete Godot 4 rewrite of the O2Jam offline client (the old
C++/SFML patch stack was replaced in merge commit `2002320`). Native desktop
rhythm game for Linux + Windows. Zero game assets ship here — the built-in
synthesized demo song means the game is fully playable without any.

## Audio & timing policy (IMPLEMENTED — do not regress)

These are deliberate design decisions, not defaults that happened to be left
in. If you think one is wrong, bring measured evidence before changing it.

- **Music-as-clock is the only timing source**:
  `playback_position + AudioServer.get_time_since_last_mix()
   - AudioServer.get_output_latency() + user_offset`
  (`scripts/autoload/audio_clock.gd`). NEVER use frame deltas or wall time
  for note logic.
- **Why it matters**: the 2003 originals weren't magic — they had an
  unobstructed audio path. This config reproduces exactly that.
- **Low-latency policy** (`project.godot`): 5 ms output latency, 48000 Hz
  mix rate, VSync off + 240 FPS cap, unaccumulated input, multithreaded
  rendering. Desktop can afford what web couldn't; 5–10 ms is the target band.
- **Mix rate must match the player's device.** Mismatched rates cause
  resampling jitter that feels like timing drift. If you touch audio init,
  verify the runtime mix rate against the output device.
- **Judgement windows**: COOL ±40 ms / GOOD ±80 ms / BAD ±120 ms
  (`scripts/core/judgement.gd`). Tune only with user sign-off.
- **Calibration screen** (metronome + ±100 ms offset slider,
  `scripts/ui/calibration.gd`) is MANDATORY and per-machine — every
  sound-card/monitor combo differs. Offset must persist across restarts.

## OS-specific tuning

### Linux (dev box: CachyOS, PipeWire, BORE scheduler)
- Works out of the box via PipeWire, but for "O2Jam feel" run
  `bash tools/pipewire-lowlatency.sh` — drops quantum to 64 @ 48 kHz and
  restarts PipeWire user services. Verify with `pw-top`: QUANT column = 64
  while the game runs. This is the same tuning competitive osu! players use;
  it reaches DirectSound-era latency.
- Ship/distribute as AppImage or Flatpak, or raw binary + launch script.

### Windows
- Godot uses WASAPI shared mode — ~10–15 ms is achievable with the
  output_latency setting, and that is PLENTY for a mania game.
- Do NOT chase tighter latency with native plugins or a custom engine unless
  a measured problem proves it's needed. Calibration + WASAPI shared wins.
- Export as ZIP or installer (Inno Setup); Godot makes no installers natively.
- **Test the calibration screen on a real Windows machine** — Linux tuning
  does not carry over.

## Setup & verification checklist (the machine you're on)

1. `sudo pacman -S godot rtkit` — verify `godot --version` >= 4.4 (else AUR
   `godot-bin` or official binary).
2. Clone, `godot --path .`.
3. `bash tools/pipewire-lowlatency.sh`; confirm `pw-top` QUANT 64 in-game.
4. Smoke test: main menu footer shows 48000 Hz; during gameplay the
   bottom-left readout shows output latency < ~10 ms. If higher, the
   PipeWire tuning didn't take — debug THAT before anything else.
5. Calibration: tap SPACE on the metronome 12x, Use suggested, Save.
   Re-run on the actual monitor + audio output the user plays on.
6. Feel check: play demo song on all 3 difficulties. Only if spread is
   consistently tight but feel is still wrong, discuss judgement windows
   with the user before touching `judgement.gd`.
7. CI: Actions tab → latest "Build exports" run → download
   `o2jam-linux-x86_64.zip` → verify it runs standalone (`o2jam-launch.sh`).

## Definition of done

- Game boots to menu; demo song playable end-to-end with results screen.
- `pw-top` shows QUANT 64 during gameplay; in-game readout < 10 ms latency.
- Calibration completed, saved, persists across restarts.
- User confirms hit feel (user's call, not yours).
- CI artifact binary runs standalone on this machine.

## Rules of engagement

- Don't touch the audio clock math in `audio_clock.gd` without measured
  evidence it's wrong. The architecture is intentional.
- Don't vendor game assets into the repo. Ever.
- Every latency/timing change must be backed by a measurement (terminal
  output, `pw-top`, in-game readout) — log it in the commit message or docs.
- If something fails, capture the actual error and report it with your
  diagnosis — don't silently work around audio/latency problems.
- Commits: small, descriptive messages. The user reviews everything.

## Key file map

```
project.godot                     audio/display/rendering policy
scripts/autoload/audio_clock.gd   music-as-clock (timing source of truth)
scripts/autoload/settings.gd      config, input map, vsync/FPS policy
scripts/core/judgement.gd         hit windows
scripts/core/chart_library.gd     .ojn / .json / demo chart loading
scripts/core/audio_gen.gd         synthesized metronome + demo track
scripts/game/gameplay.gd          7-lane gameplay
scripts/ui/calibration.gd         calibration screen
tools/pipewire-lowlatency.sh      Linux audio tuning
README.md                         full docs, export workflow, known limits
```
