extends Control
## Results screen after a song.

var data: Dictionary = {}


func setup(p_data: Dictionary) -> void:
	data = p_data


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var chart: Chart = data["chart"]
	var counts: Dictionary = data["counts"]

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	var title := Label.new()
	title.text = "%s — %s  [%s Lv.%d]" % [
		chart.artist, chart.title, chart.difficulty_name, chart.level]
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var score := Label.new()
	score.text = "%08d" % data["score"]
	score.add_theme_font_size_override("font_size", 64)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(score)

	var acc := Label.new()
	acc.text = "%.2f%%  ·  max combo %d" % [data["accuracy"] * 100.0, data["max_combo"]]
	acc.add_theme_font_size_override("font_size", 24)
	acc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(acc)

	for rank in [Judgement.Rank.COOL, Judgement.Rank.GOOD, Judgement.Rank.BAD, Judgement.Rank.MISS]:
		var l := Label.new()
		l.text = "%-5s %d" % [Judgement.RANK_NAMES[rank], counts[rank]]
		l.add_theme_font_size_override("font_size", 22)
		l.add_theme_color_override("font_color", Judgement.RANK_COLORS[rank])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var retry := Button.new()
	retry.text = "Retry"
	retry.pressed.connect(func(): Main.restart_song())
	row.add_child(retry)
	var back := Button.new()
	back.text = "Song Select"
	back.pressed.connect(func(): Main.go(load("res://scripts/ui/song_select.gd").new()))
	row.add_child(back)
