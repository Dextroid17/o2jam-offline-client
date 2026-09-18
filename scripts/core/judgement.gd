class_name Judgement
extends RefCounted
## Hit windows. Defaults follow the classic O2Jam feel:
##   COOL ±40 ms, GOOD ±80 ms, BAD ±120 ms, beyond = MISS.
## Tighten COOL/GOOD once your calibration trust is high; loosen for HIDPI
## displays or Bluetooth audio (or fix the audio path instead — better).

enum Rank { COOL, GOOD, BAD, MISS }

const RANK_NAMES := {
	Rank.COOL: "COOL",
	Rank.GOOD: "GOOD",
	Rank.BAD: "BAD",
	Rank.MISS: "MISS",
}

const RANK_COLORS := {
	Rank.COOL: Color(0.35, 0.9, 1.0),
	Rank.GOOD: Color(0.55, 1.0, 0.45),
	Rank.BAD: Color(1.0, 0.8, 0.3),
	Rank.MISS: Color(1.0, 0.3, 0.35),
}

var cool_ms := 40.0
var good_ms := 80.0
var bad_ms := 120.0


## delta_ms = hit_time - note_time (positive = late).
func judge(delta_ms: float) -> Rank:
	var a := absf(delta_ms)
	if a <= cool_ms:
		return Rank.COOL
	if a <= good_ms:
		return Rank.GOOD
	if a <= bad_ms:
		return Rank.BAD
	return Rank.MISS


func in_window(delta_ms: float) -> bool:
	return absf(delta_ms) <= bad_ms


## Score weight per rank (classic-ish proportions).
func score_value(rank: Rank) -> float:
	match rank:
		Rank.COOL: return 1.0
		Rank.GOOD: return 0.7
		Rank.BAD: return 0.3
		Rank.MISS: return 0.0
	return 0.0
