extends Control
## Gameplay screen: 7 lanes, time-based note scrolling, input judged against
## the audio clock (never the frame clock).
##
## Esc   pause (Q = quit to menu, R = restart while paused)

const LANE_COUNT := 7
const LEAD_IN_SEC := 3.0
const NOTE_H := 18.0

var chart: Chart
var judgement := Judgement.new()
var player: AudioStreamPlayer

var lanes: Array = []              # per-lane Array of Chart.Note
var lane_ptr: Array[int] = []      # first unjudged note index per lane
var lane_flash: Array[float] = []  # seconds since key press, per lane
var active_ln: Array = []          # held long note per lane (or null)

var started := false
var lead_in_left := LEAD_IN_SEC
var game_paused := false
var finished := false

var combo := 0
var max_combo := 0
var score := 0
var acc_sum := 0.0
var judged_count := 0
var counts := {
	Judgement.Rank.COOL: 0,
	Judgement.Rank.GOOD: 0,
	Judgement.Rank.BAD: 0,
	Judgement.Rank.MISS: 0,
}

var popup_rank := -1
var popup_at := -10.0
var song_t := -LEAD_IN_SEC


func setup(p_chart: Chart) -> void:
	chart = p_chart


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_split_lanes()
	lane_ptr.resize(LANE_COUNT)
	lane_ptr.fill(0)
	lane_flash.resize(LANE_COUNT)
	lane_flash.fill(99.0)
	active_ln.resize(LANE_COUNT)
	active_ln.fill(null)

	player = AudioStreamPlayer.new()
	player.stream = _load_audio()
	player.bus = &"Master"
	add_child(player)
	AudioClock.attach(player)


func _exit_tree() -> void:
	AudioClock.detach()


func _split_lanes() -> void:
	lanes.clear()
	for i in LANE_COUNT:
		lanes.append([])
	for n in chart.notes:
		lanes[n.lane].append(n)


func _load_audio() -> AudioStream:
	if chart.audio_path != "":
		var stream: AudioStream = null
		match chart.audio_path.get_extension().to_lower():
			"ogg":
				stream = AudioStreamOggVorbis.load_from_file(chart.audio_path)
			"mp3":
				stream = AudioStreamMP3.load_from_file(chart.audio_path)
			"wav":
				stream = AudioStreamWAV.load_from_file(chart.audio_path)
		if stream != null:
			return stream
		push_warning("Gameplay: could not decode " + chart.audio_path + " — metronome mode")
	if chart.demo:
		return AudioGen.make_demo_track(chart.bpm)
	return AudioGen.make_metronome_loop(chart.bpm)


## Current song time in seconds. Negative during the lead-in countdown.
func _now() -> float:
	if not started:
		return -lead_in_left
	return AudioClock.song_time()


func _process(delta: float) -> void:
	if finished:
		return
	if game_paused:
		queue_redraw()
		return

	if not started:
		lead_in_left -= delta
		if lead_in_left <= 0.0:
			started = true
			player.play()
	else:
		song_t = AudioClock.song_time()
		_check_misses()
		_check_long_note_holds()
		if song_t * 1000.0 > chart.duration_ms + 2000.0:
			_finish()

	for i in LANE_COUNT:
		lane_flash[i] += delta
	queue_redraw()


func _check_misses() -> void:
	var t_ms := song_t * 1000.0
	for lane in LANE_COUNT:
		while lane_ptr[lane] < lanes[lane].size():
			var n: Chart.Note = lanes[lane][lane_ptr[lane]]
			if n.judged:
				lane_ptr[lane] += 1
				continue
			if t_ms - n.time_ms > judgement.bad_ms:
				_apply_rank(Judgement.Rank.MISS, n)
				lane_ptr[lane] += 1
			else:
				break


func _check_long_note_holds() -> void:
	var t_ms := song_t * 1000.0
	for lane in LANE_COUNT:
		var n: Chart.Note = active_ln[lane]
		if n != null and not n.tail_judged and t_ms >= n.end_ms:
			# Still held at the tail: best possible tail judgement.
			n.tail_judged = true
			active_ln[lane] = null
			_apply_rank(Judgement.Rank.COOL, null)


func _input(event: InputEvent) -> void:
	if finished:
		return
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()
		return
	if game_paused:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.physical_keycode == KEY_Q:
				Main.go(load("res://scripts/ui/song_select.gd").new())
			elif event.physical_keycode == KEY_R:
				Main.restart_song()
		return
	if not started or event.is_echo():
		return
	for lane in LANE_COUNT:
		var action := "lane_%d" % (lane + 1)
		if event.is_action_pressed(action):
			_on_lane_press(lane)
		elif event.is_action_released(action):
			_on_lane_release(lane)


func _on_lane_press(lane: int) -> void:
	lane_flash[lane] = 0.0
	var t_ms := _now() * 1000.0
	var ptr: int = lane_ptr[lane]
	if ptr >= lanes[lane].size():
		return
	var n: Chart.Note = lanes[lane][ptr]
	var delta := t_ms - n.time_ms
	if not judgement.in_window(delta):
		return  # stray tap, too far from any note
	_apply_rank(judgement.judge(delta), n)
	n.judged = true
	lane_ptr[lane] += 1
	if n.is_long():
		active_ln[lane] = n


func _on_lane_release(lane: int) -> void:
	var n: Chart.Note = active_ln[lane]
	if n == null or n.tail_judged:
		return
	var t_ms := _now() * 1000.0
	n.tail_judged = true
	active_ln[lane] = null
	var delta := t_ms - n.end_ms
	if judgement.in_window(delta):
		_apply_rank(judgement.judge(delta), null)
	else:
		_apply_rank(Judgement.Rank.BAD, null)  # let go early


func _apply_rank(rank: Judgement.Rank, n: Chart.Note) -> void:
	if n != null:
		n.judged = true
	counts[rank] += 1
	judged_count += 1
	acc_sum += judgement.score_value(rank)
	if rank == Judgement.Rank.MISS or rank == Judgement.Rank.BAD:
		combo = 0
	else:
		combo += 1
		max_combo = maxi(max_combo, combo)
	score += int(round(1000.0 * judgement.score_value(rank) * (1.0 + combo * 0.01)))
	popup_rank = rank
	popup_at = _now()


func _toggle_pause() -> void:
	if not started:
		return
	game_paused = not game_paused
	player.stream_paused = game_paused
	if game_paused:
		AudioClock.freeze()


func _finish() -> void:
	finished = true
	player.stop()
	var results := load("res://scripts/ui/results.gd").new()
	results.setup({
		"chart": chart,
		"score": score,
		"max_combo": max_combo,
		"counts": counts,
		"accuracy": acc_sum / maxf(1.0, float(judged_count)),
	})
	Main.go(results)


## ---- Drawing -------------------------------------------------------------

func _draw() -> void:
	var size := get_size()
	var unit := size.y / 720.0
	var lane_w := 64.0 * unit
	var field_w := lane_w * LANE_COUNT
	var x0 := (size.x - field_w) * 0.5
	var receptor_y := size.y * 0.86
	var speed := Settings.scroll_speed * unit
	var font := ThemeDB.fallback_font
	var t := _now()

	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.05, 0.08))

	# Lane backgrounds and key-press flashes.
	for lane in LANE_COUNT:
		var x := x0 + lane * lane_w
		var bg := Color(0.09, 0.09, 0.13) if lane % 2 == 0 else Color(0.11, 0.11, 0.16)
		draw_rect(Rect2(x, 0, lane_w, size.y), bg)
		var flash: float = clampf(1.0 - lane_flash[lane] * 6.0, 0.0, 1.0)
		if flash > 0.0:
			draw_rect(Rect2(x, 0, lane_w, size.y), Color(0.4, 0.7, 1.0, flash * 0.25))
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.25, 0.25, 0.32), 1.0)
	draw_line(Vector2(x0 + field_w, 0), Vector2(x0 + field_w, size.y), Color(0.25, 0.25, 0.32), 1.0)

	# Receptor.
	draw_rect(Rect2(x0, receptor_y - 2, field_w, 4), Color(1.0, 0.85, 0.3))
	for lane in LANE_COUNT:
		var x := x0 + lane * lane_w
		draw_rect(Rect2(x + 3, receptor_y - NOTE_H * unit, lane_w - 6, NOTE_H * unit),
			Color(1, 1, 1, 0.08), false, 2.0)

	# Notes.
	for lane in LANE_COUNT:
		var x := x0 + lane * lane_w
		var note_color := _lane_color(lane)
		var list: Array = lanes[lane]
		var first: int = maxi(0, lane_ptr[lane] - 1)
		for i in range(first, list.size()):
			var n: Chart.Note = list[i]
			if n.judged and not (n.is_long() and not n.tail_judged):
				continue
			var head_y: float = receptor_y - (n.time_ms / 1000.0 - t) * speed
			if head_y < -80.0:
				break  # everything beyond is off the top of the screen
			if n.is_long():
				var tail_y: float = receptor_y - (n.end_ms / 1000.0 - t) * speed
				var body_top: float = minf(head_y, tail_y)
				var body_bottom: float = receptor_y if n.judged else maxf(head_y, tail_y)
				draw_rect(Rect2(x + lane_w * 0.25, body_top, lane_w * 0.5,
					body_bottom - body_top), note_color * Color(1, 1, 1, 0.45))
				draw_rect(Rect2(x + 3, tail_y - NOTE_H * unit * 0.5, lane_w - 6,
					NOTE_H * unit), note_color.darkened(0.2))
			if not n.judged:
				draw_rect(Rect2(x + 3, head_y - NOTE_H * unit * 0.5, lane_w - 6,
					NOTE_H * unit), note_color)

	# HUD.
	var fs := int(28 * unit)
	draw_string(font, Vector2(20, 36 * unit), "%s — %s  [%s Lv.%d]" % [
		chart.artist, chart.title, chart.difficulty_name, chart.level],
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.8, 0.8, 0.85))
	draw_string(font, Vector2(size.x - 20, 36 * unit), "%08d" % score,
		HORIZONTAL_ALIGNMENT_RIGHT, -1, fs, Color(1, 1, 1))
	if chart.duration_ms > 0.0 and started:
		var prog: float = clampf(t * 1000.0 / chart.duration_ms, 0.0, 1.0)
		draw_rect(Rect2(0, 0, size.x * prog, 4), Color(0.35, 0.9, 1.0))

	if combo >= 2:
		draw_string(font, Vector2(size.x * 0.5, size.y * 0.35), str(combo),
			HORIZONTAL_ALIGNMENT_CENTER, -1, int(72 * unit), Color(1, 1, 1, 0.9))

	var popup_age: float = t - popup_at
	if popup_rank >= 0 and popup_age < 0.6:
		var alpha: float = clampf(1.0 - popup_age / 0.6, 0.0, 1.0)
		var col: Color = Judgement.RANK_COLORS[popup_rank]
		col.a = alpha
		draw_string(font, Vector2(size.x * 0.5, size.y * 0.45),
			Judgement.RANK_NAMES[popup_rank],
			HORIZONTAL_ALIGNMENT_CENTER, -1, int(48 * unit), col)

	if not started:
		draw_string(font, Vector2(size.x * 0.5, size.y * 0.5),
			str(int(ceil(lead_in_left))),
			HORIZONTAL_ALIGNMENT_CENTER, -1, int(96 * unit), Color(1, 1, 1, 0.8))

	# Latency readout (small, bottom-left) — proof the audio path is healthy.
	draw_string(font, Vector2(20, size.y - 14),
		"output latency %.1f ms · offset %+.0f ms · %d fps" % [
			AudioClock.measured_output_latency_ms(), Settings.offset_ms,
			Engine.get_frames_per_second()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * unit), Color(0.5, 0.5, 0.55))

	if game_paused:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6))
		draw_string(font, Vector2(size.x * 0.5, size.y * 0.45), "PAUSED",
			HORIZONTAL_ALIGNMENT_CENTER, -1, int(64 * unit), Color(1, 1, 1))
		draw_string(font, Vector2(size.x * 0.5, size.y * 0.55),
			"Esc resume · R restart · Q quit",
			HORIZONTAL_ALIGNMENT_CENTER, -1, int(24 * unit), Color(0.8, 0.8, 0.8))


func _lane_color(lane: int) -> Color:
	if lane == 3:
		return Color(1.0, 0.5, 0.75)
	return Color(0.35, 0.75, 1.0) if lane % 2 == 0 else Color(0.95, 0.95, 0.95)
