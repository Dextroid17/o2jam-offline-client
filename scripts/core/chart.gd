class_name Chart
extends RefCounted
## A playable chart: metadata + sorted note list + audio reference.

class Note:
	var time_ms: float          # hit time (head time for long notes)
	var lane: int               # 0..6
	var end_ms: float = -1.0    # > time_ms for long notes, -1 for taps
	var sample_id: int = 0      # key-sound index (0 = none / unsupported)

	# Runtime judgement state (not serialized).
	var judged: bool = false
	var tail_judged: bool = false

	func is_long() -> bool:
		return end_ms > time_ms


var title := ""
var artist := ""
var noter := ""
var difficulty_name := ""
var level := 1
var bpm := 130.0
var audio_path := ""          # resolved .ogg/.mp3/.wav, "" = metronome mode
var source_path := ""         # chart file this was loaded from
var demo := false             # built-in generated chart (use synthesized track)
var notes: Array[Note] = []
var duration_ms: float = 0.0


func sort_notes() -> void:
	notes.sort_custom(func(a: Note, b: Note) -> bool: return a.time_ms < b.time_ms)
	duration_ms = 0.0
	for n in notes:
		duration_ms = maxf(duration_ms, maxf(n.time_ms, n.end_ms))


func lane_count() -> int:
	return 7
