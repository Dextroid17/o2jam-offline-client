extends Control
## Song select: scans the songs folder for .ojn / .json charts, plus the
## built-in demo. Also hosts the quick settings (scroll speed, keys, folder).

var entries: Array = []
var list: ItemList
var diff_option: OptionButton
var play_btn: Button
var dir_edit: LineEdit
var speed_label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	root.offset_left = 24
	root.offset_top = 20
	root.offset_right = -24
	root.offset_bottom = -20
	add_child(root)

	var title := Label.new()
	title.text = "SELECT MUSIC"
	title.add_theme_font_size_override("font_size", 36)
	root.add_child(title)

	# Songs folder row.
	var dir_row := HBoxContainer.new()
	root.add_child(dir_row)
	dir_row.add_child(_label("Songs folder:"))
	dir_edit = LineEdit.new()
	dir_edit.text = Settings.default_songs_dir()
	dir_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dir_edit.text_submitted.connect(func(_t): _rescan())
	dir_row.add_child(dir_edit)
	var scan_btn := Button.new()
	scan_btn.text = "Rescan"
	scan_btn.pressed.connect(_rescan)
	dir_row.add_child(scan_btn)

	list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_theme_font_size_override("font_size", 20)
	list.item_selected.connect(_on_select)
	root.add_child(list)

	# Bottom row: difficulty, speed, buttons.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	root.add_child(row)

	row.add_child(_label("Difficulty:"))
	diff_option = OptionButton.new()
	row.add_child(diff_option)

	row.add_child(_label("Speed:"))
	var speed := HSlider.new()
	speed.min_value = 400
	speed.max_value = 1800
	speed.step = 25
	speed.value = Settings.scroll_speed
	speed.custom_minimum_size = Vector2(160, 0)
	speed.value_changed.connect(_on_speed)
	row.add_child(speed)
	speed_label = _label("%d" % int(Settings.scroll_speed))
	row.add_child(speed_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func(): Main.go(load("res://scripts/ui/main_menu.gd").new()))
	row.add_child(back)

	var calib := Button.new()
	calib.text = "Calibration"
	calib.pressed.connect(func(): Main.go(load("res://scripts/ui/calibration.gd").new()))
	row.add_child(calib)

	play_btn = Button.new()
	play_btn.text = "PLAY"
	play_btn.custom_minimum_size = Vector2(140, 44)
	play_btn.disabled = true
	play_btn.pressed.connect(_on_play)
	row.add_child(play_btn)

	var keys := _label("Keys: " + " ".join(Settings.lane_keys.map(
		func(k): return OS.get_keycode_string(k)))
		+ "   ·   offset %+.0f ms" % Settings.offset_ms)
	keys.add_theme_font_size_override("font_size", 14)
	keys.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
	root.add_child(keys)

	_rescan()


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _rescan() -> void:
	Settings.songs_dir = dir_edit.text.strip_edges()
	Settings.save_config()
	entries = ChartLibrary.scan(Settings.default_songs_dir())
	list.clear()
	for e in entries:
		list.add_item("%s — %s  (%.0f BPM)" % [e["artist"], e["title"], e["bpm"]])
	play_btn.disabled = true


func _on_select(idx: int) -> void:
	diff_option.clear()
	var levels: Array = entries[idx].get("levels", [1])
	var names := ["EX", "NX", "HX"]
	for i in levels.size():
		var name: String = names[i] if i < names.size() else "LV"
		diff_option.add_item("%s Lv.%d" % [name, levels[i]], i)
	diff_option.select(mini(1, levels.size() - 1))
	play_btn.disabled = false


func _on_speed(v: float) -> void:
	Settings.scroll_speed = v
	speed_label.text = "%d" % int(v)
	Settings.save_config()


func _on_play() -> void:
	var idx: int = list.get_selected_items()[0]
	Main.play_song(entries[idx], diff_option.get_selected_id())
