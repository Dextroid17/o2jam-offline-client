extends Node
## Music-as-clock: the single source of truth for "what time is it in the song".
##
## Never use Time.get_ticks_* or frame deltas for note timing — they drift
## against the audio hardware. The only clock that matters is how many
## samples the sound card has actually played:
##
##     song_time = playback_position
##               + time_since_last_mix   (samples mixed but not yet handed over)
##               - output_latency        (samples in the OS/driver buffer)
##               + user_offset           (per-machine calibration, ±100 ms)
##
## That combination is what makes judgement feel identical across machines.

var player: AudioStreamPlayer
var paused_position: float = 0.0


func attach(p: AudioStreamPlayer) -> void:
	player = p
	paused_position = 0.0


func detach() -> void:
	player = null


## Song position in seconds, compensated and offset-corrected.
func song_time() -> float:
	var offset := Settings.offset_ms / 1000.0
	if player == null:
		return paused_position + offset
	if not player.playing or player.stream_paused:
		return paused_position + offset
	var pos := player.get_playback_position()
	pos += AudioServer.get_time_since_last_mix()
	pos -= AudioServer.get_output_latency()
	return pos + offset


## Call when pausing so song_time() stays frozen at the right place.
func freeze() -> void:
	if player != null:
		paused_position = player.get_playback_position()


## Raw measured output latency in ms, for display on the calibration screen.
func measured_output_latency_ms() -> float:
	return AudioServer.get_output_latency() * 1000.0
