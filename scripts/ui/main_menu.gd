extends Control
## Main menu.


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	add_child(box)

	var title := Label.new()
	title.text = "O2JAM"
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", Color(0.35, 0.9, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var sub := Label.new()
	sub.text = "offline client · native desktop · low-latency audio"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	box.add_child(sub)

	for spec in [["PLAY", "_on_play"], ["CALIBRATION", "_on_calib"], ["QUIT", "_on_quit"]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(280, 52)
		b.add_theme_font_size_override("font_size", 24)
		b.pressed.connect(Callable(self, spec[1]))
		box.add_child(b)

	var footer := Label.new()
	footer.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	footer.position = Vector2(16, -32)
	footer.text = "mix rate %d Hz · output latency %.1f ms · offset %+.0f ms" % [
		AudioServer.get_mix_rate(), AudioClock.measured_output_latency_ms(),
		Settings.offset_ms]
	footer.add_theme_font_size_override("font_size", 14)
	footer.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	add_child(footer)


func _on_play() -> void:
	Main.go(load("res://scripts/ui/song_select.gd").new())


func _on_calib() -> void:
	Main.go(load("res://scripts/ui/calibration.gd").new())


func _on_quit() -> void:
	get_tree().quit()
