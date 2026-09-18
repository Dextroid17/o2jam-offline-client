extends Control
## Calibration screen. Still required on every machine — every sound card /
## monitor / desk setup is a few milliseconds different, and ±40 ms COOL
## windows do not forgive guesswork.
##
## Method: a 120 BPM metronome loop (sample-accurate, generated in code).
## Tap SPACE on the beat. Each tap is timed against the same audio-clock math
## the gameplay screen uses, so the suggested offset transfers directly.

const BPM := 120.0
const BEAT_SEC := 60.0 / BPM
const MAX_TAPS := 12

var metro: AudioStreamPlayer
var errors: Array[float] = []
var status: Label
var suggestion: Label
var slider: HSlider
var slider_value: Label
var flash := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	box.custom_minimum_size = Vector2(640, 0)
	add_child(box)

	var title := Label.new()
	title.text = "CALIBRATION"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var help := Label.new()
	help.text = ("Tap SPACE exactly on the metronome beat, %d times.\n" % MAX_TAPS) \
		+ "Listen, don't watch — this measures your audio path, not your eyes."
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(help)

	status = Label.new()
	status.text = "measured output latency: %.1f ms" % AudioClock.measured_output_latency_ms()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	box.add_child(status)

	suggestion = Label.new()
	suggestion.text = "no taps yet"
	suggestion.add_theme_font_size_override("font_size", 24)
	suggestion.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(suggestion)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	row.add_child(_mk_label("Offset:"))
	slider = HSlider.new()
	slider.min_value = -100.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = Settings.offset_ms
	slider.custom_minimum_size = Vector2(320, 0)
	slider.value_changed.connect(_on_slider)
	row.add_child(slider)
	slider_value = _mk_label("%+.0f ms" % Settings.offset_ms)
	slider_value.custom_minimum_size = Vector2(80, 0)
	row.add_child(slider_value)

	var apply_row := HBoxContainer.new()
	apply_row.alignment = BoxContainer.ALIGNMENT_CENTER
	apply_row.add_theme_constant_override("separation", 12)
	box.add_child(apply_row)
	var use_suggested := Button.new()
	use_suggested.text = "Use suggested"
	use_suggested.pressed.connect(_on_use_suggested)
	apply_row.add_child(use_suggested)
	var save := Button.new()
	save.text = "Save"
	save.pressed.connect(_on_save)
	apply_row.add_child(save)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func(): Main.go(load("res://scripts/ui/main_menu.gd").new()))
	apply_row.add_child(back)

	metro = AudioStreamPlayer.new()
	metro.stream = AudioGen.make_metronome_loop(BPM)
	add_child(metro)
	metro.play()


func _mk_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _exit_tree() -> void:
	metro.stop()


func _process(delta: float) -> void:
	flash = maxf(0.0, flash - delta)
	# Beat indicator: pulse the background on each beat so you can sanity-check
	# that what you see and what you hear disagree (that's the point).
	if metro.playing:
		var pos := _clock()
		var phase := fmod(pos, BEAT_SEC) / BEAT_SEC
		var glow := clampf(1.0 - phase * 4.0, 0.0, 1.0) * 0.06 + flash * 0.15
		(get_child(0) as ColorRect).color = Color(0.05 + glow, 0.05 + glow, 0.08 + glow)


## Same math as AudioClock.song_time(), minus the user offset.
func _clock() -> float:
	return metro.get_playback_position() \
		+ AudioServer.get_time_since_last_mix() \
		- AudioServer.get_output_latency()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("calibrate_tap") and not event.is_echo() and metro.playing:
		flash = 1.0
		var pos := _clock()
		var beat_pos := fmod(pos, BEAT_SEC)
		var err := beat_pos
		if err > BEAT_SEC * 0.5:
			err -= BEAT_SEC
		errors.append(err * 1000.0)
		if errors.size() > MAX_TAPS:
			errors.pop_front()
		_update_suggestion()


func _update_suggestion() -> void:
	var mean := 0.0
	for e in errors:
		mean += e
	mean /= errors.size()
	var spread := 0.0
	for e in errors:
		spread = maxf(spread, absf(e - mean))
	suggestion.text = "taps: %d · mean %+.1f ms · spread ±%.0f ms" % [
		errors.size(), mean, spread]
	suggestion.set_meta("mean", mean)


func _on_slider(v: float) -> void:
	slider_value.text = "%+.0f ms" % v


func _on_use_suggested() -> void:
	if errors.is_empty():
		return
	slider.value = clampf(suggestion.get_meta("mean"), -100.0, 100.0)


func _on_save() -> void:
	Settings.offset_ms = slider.value
	Settings.save_config()
	suggestion.text = "saved: offset %+.0f ms" % Settings.offset_ms
