class_name AudioGen
extends RefCounted
## Procedural audio: metronome clicks and a synthesized demo track, so the
## client is playable and calibratable with zero external assets.

const MIX_RATE := 48000


## Short percussive click (decaying sine), used for the metronome and
## as a fallback hit-sound.
static func make_click(freq := 2200.0, length_ms := 30.0, gain := 0.7) -> AudioStreamWAV:
	var n := int(MIX_RATE * length_ms / 1000.0)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / MIX_RATE
		var env := exp(-t * 90.0)
		var s := sin(TAU * freq * t) * env * gain
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	return _wrap(data)


## A looping metronome bar: `beats` clicks evenly spaced, accent on beat 0.
static func make_metronome_loop(bpm: float, beats := 4) -> AudioStreamWAV:
	var beat_sec := 60.0 / bpm
	var total := int(MIX_RATE * beat_sec * beats)
	var data := PackedByteArray()
	data.resize(total * 2)
	for b in beats:
		var freq := 2200.0 if b == 0 else 1600.0
		_overlay_click(data, int(b * beat_sec * MIX_RATE), freq, 0.8)
	var stream := _wrap(data)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = total
	return stream


## 8-bar synthesized loop (kick / snare / hats / bass) used by the built-in
## demo chart. Not pretty — but it is sample-accurate, which is the point.
static func make_demo_track(bpm := 140.0, bars := 8) -> AudioStreamWAV:
	var beat_sec := 60.0 / bpm
	var total := int(MIX_RATE * beat_sec * 4.0 * bars)
	var data := PackedByteArray()
	data.resize(total * 2)
	for bar in bars:
		for beat in 4:
			var s0 := int((bar * 4 + beat) * beat_sec * MIX_RATE)
			_overlay_kick(data, s0)
			if beat == 1 or beat == 3:
				_overlay_snare(data, s0)
			for eighth in 2:
				_overlay_hat(data, s0 + int(eighth * beat_sec * 0.5 * MIX_RATE), eighth == 1)
			_overlay_bass(data, s0, 55.0 * pow(2.0, (bar % 4) / 12.0), beat_sec)
	var stream := _wrap(data)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = total
	return stream


static func _wrap(data: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream


static func _put(data: PackedByteArray, idx: int, v: float) -> void:
	if idx < 0 or idx * 2 + 1 >= data.size():
		return
	var prev := data.decode_s16(idx * 2) / 32767.0
	data.encode_s16(idx * 2, int(clampf(prev + v, -1.0, 1.0) * 32767.0))


static func _overlay_click(data: PackedByteArray, start: int, freq: float, gain: float) -> void:
	var n := int(MIX_RATE * 0.03)
	for i in n:
		var t := float(i) / MIX_RATE
		_put(data, start + i, sin(TAU * freq * t) * exp(-t * 90.0) * gain)


static func _overlay_kick(data: PackedByteArray, start: int) -> void:
	var n := int(MIX_RATE * 0.18)
	for i in n:
		var t := float(i) / MIX_RATE
		var f := 120.0 * exp(-t * 18.0) + 45.0
		_put(data, start + i, sin(TAU * f * t) * exp(-t * 14.0) * 0.9)


static func _overlay_snare(data: PackedByteArray, start: int) -> void:
	var n := int(MIX_RATE * 0.12)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in n:
		var t := float(i) / MIX_RATE
		var noise := rng.randf_range(-1.0, 1.0)
		_put(data, start + i, (noise * 0.6 + sin(TAU * 190.0 * t) * 0.4) * exp(-t * 30.0) * 0.5)


static func _overlay_hat(data: PackedByteArray, start: int, open_hat: bool) -> void:
	var n := int(MIX_RATE * (0.09 if open_hat else 0.03))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		var t := float(i) / MIX_RATE
		_put(data, start + i, rng.randf_range(-1.0, 1.0) * exp(-t * 70.0) * 0.18)


static func _overlay_bass(data: PackedByteArray, start: int, freq: float, beat_sec: float) -> void:
	var n := int(MIX_RATE * beat_sec * 0.9)
	for i in n:
		var t := float(i) / MIX_RATE
		var s: float = signf(sin(TAU * freq * t)) * 0.25 + sin(TAU * freq * t) * 0.35
		_put(data, start + i, s * exp(-t * 3.0) * 0.35)
