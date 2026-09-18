class_name ChartLibrary
extends RefCounted
## Chart discovery and loading.
##
## Supported sources:
##  - .ojn  (real O2Jam charts — bring your own, nothing is distributed)
##  - .json (simple native format, documented in README.md)
##  - built-in generated demo chart (zero assets needed)
##
## OJN notes: the header and note-data layout below follows the publicly
## documented format. Timing uses the header BPM (constant-BPM assumption);
## charts with mid-song BPM events will drift — see README "Known limits".
## OJM audio: encrypted OJM containers (M30/OMC/OMZ) are NOT decoded; place a
## decoded .ogg/.mp3/.wav next to the chart instead, or play in metronome mode.

const OJN_MEASURES_PER_PACKAGE := 192
const OJN_EVENTS_PER_CHANNEL := 48   # 48 events x 4 bytes = 192 bytes
const OJN_CHANNELS := 8              # 7 playable + 1 BGM


## ---- Discovery -----------------------------------------------------------

## Returns Array of Dictionaries: {path, title, artist, bpm, levels, kind}
static func scan(dir_path: String) -> Array:
	var out: Array = []
	_scan_dir(dir_path, out, 2)
	out.append({
		"path": "", "title": "Demo Song (built-in)", "artist": "AudioGen",
		"bpm": 140.0, "levels": [8, 14, 20], "kind": "demo",
	})
	return out


static func _scan_dir(dir_path: String, out: Array, depth: int) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name.begins_with("."):
			name = d.get_next()
			continue
		var full := dir_path.path_join(name)
		if d.current_is_dir():
			if depth > 0:
				_scan_dir(full, out, depth - 1)
		elif name.get_extension().to_lower() == "ojn":
			var meta := read_ojn_metadata(full)
			if not meta.is_empty():
				out.append(meta)
		elif name.get_extension().to_lower() == "json":
			var meta := read_json_metadata(full)
			if not meta.is_empty():
				out.append(meta)
		name = d.get_next()
	d.list_dir_end()


## ---- Loading -------------------------------------------------------------

## diff_index: 0=EX 1=NX 2=HX (OJN), ignored for JSON/demo.
static func load_chart(entry: Dictionary, diff_index := 1) -> Chart:
	match entry.get("kind", ""):
		"demo":
			return make_demo_chart(diff_index)
		"ojn":
			return load_ojn(entry["path"], diff_index)
		"json":
			return load_json(entry["path"])
	return null


static func make_demo_chart(diff_index := 1) -> Chart:
	var c := Chart.new()
	c.title = "Demo Song (built-in)"
	c.artist = "AudioGen"
	c.noter = "auto"
	c.demo = true
	c.bpm = 140.0
	c.difficulty_name = ["EX", "NX", "HX"][diff_index]
	c.level = [8, 14, 20][diff_index]
	var beat_ms := 60000.0 / c.bpm
	var patterns := [
		[0], [2], [4], [6], [1], [3], [5], [3],
		[0, 6], [2], [4], [1, 5], [3], [0, 6], [2, 4], [3],
	]
	var density: int = [1, 2, 2][diff_index]  # notes per beat
	for bar in 8:
		for beat in 4:
			var t := (bar * 4 + beat) * beat_ms
			var pat: Array = patterns[(bar * 4 + beat) % patterns.size()]
			for k in min(density, pat.size()):
				var n := Chart.Note.new()
				n.time_ms = t + k * beat_ms * 0.5
				n.lane = pat[k]
				c.notes.append(n)
			# Occasional long note on HX.
			if diff_index == 2 and beat == 0 and bar % 2 == 1:
				var ln := Chart.Note.new()
				ln.time_ms = t
				ln.lane = 3
				ln.end_ms = t + beat_ms * 2.0
				c.notes.append(ln)
	c.sort_notes()
	return c


## ---- JSON charts ---------------------------------------------------------

static func read_json_metadata(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return {
		"path": path,
		"title": data.get("title", path.get_file()),
		"artist": data.get("artist", "?"),
		"bpm": data.get("bpm", 0.0),
		"levels": [data.get("level", 1)],
		"kind": "json",
	}


static func load_json(path: String) -> Chart:
	var text := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("ChartLibrary: bad JSON chart: " + path)
		return null
	var c := Chart.new()
	c.source_path = path
	c.title = data.get("title", path.get_file())
	c.artist = data.get("artist", "?")
	c.noter = data.get("noter", "?")
	c.bpm = data.get("bpm", 120.0)
	c.difficulty_name = data.get("difficulty", "NX")
	c.level = data.get("level", 1)
	for nd in data.get("notes", []):
		var n := Chart.Note.new()
		n.time_ms = nd.get("t", 0.0)
		n.lane = clampi(nd.get("lane", 0), 0, 6)
		n.end_ms = nd.get("end", -1.0)
		c.notes.append(n)
	c.sort_notes()
	var audio: String = data.get("audio", "")
	if audio != "":
		var full := path.get_base_dir().path_join(audio)
		if FileAccess.file_exists(full):
			c.audio_path = full
	return c


## ---- OJN charts ----------------------------------------------------------

static func read_ojn_metadata(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 300:
		return {}
	var data := f.get_buffer(300)
	var hdr := _parse_ojn_header(data)
	if hdr.is_empty():
		return {}
	hdr["path"] = path
	hdr["kind"] = "ojn"
	return hdr


static func load_ojn(path: String, diff_index := 1) -> Chart:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var header_data := f.get_buffer(300)
	var hdr := _parse_ojn_header(header_data)
	if hdr.is_empty():
		push_error("ChartLibrary: unrecognized OJN header: " + path)
		return null

	var c := Chart.new()
	c.source_path = path
	c.title = hdr["title"]
	c.artist = hdr["artist"]
	c.noter = hdr["noter"]
	c.bpm = hdr["bpm"]
	c.difficulty_name = ["EX", "NX", "HX"][diff_index]
	c.level = hdr["levels"][diff_index]

	var ms_per_measure := 4.0 * 60000.0 / c.bpm
	var package_count: int = hdr["package_counts"][diff_index]
	f.seek(hdr["note_offsets"][diff_index])

	var ln_heads := {}  # lane -> Chart.Note
	for p in package_count:
		if f.get_position() + 8 > f.get_length():
			break
		var measure_count := f.get_32()
		var package_number := f.get_32()
		for m in measure_count:
			var abs_measure: int = package_number * OJN_MEASURES_PER_PACKAGE + m
			for ch in OJN_CHANNELS:
				for i in OJN_EVENTS_PER_CHANNEL:
					var value := f.get_8()
					var _volpan := f.get_8()
					var type := f.get_8()
					var _pad := f.get_8()
					if ch >= 7 or type == 0:
						continue  # BGM channel or empty slot
					var pos := abs_measure + float(i) / OJN_EVENTS_PER_CHANNEL
					var t := pos * ms_per_measure
					match type:
						2:  # normal note
							var n := Chart.Note.new()
							n.time_ms = t
							n.lane = ch
							n.sample_id = value
							c.notes.append(n)
						3:  # long note head
							var n := Chart.Note.new()
							n.time_ms = t
							n.lane = ch
							n.sample_id = value
							ln_heads[ch] = n
						4:  # long note tail
							if ln_heads.has(ch):
								var head: Chart.Note = ln_heads[ch]
								head.end_ms = t
								c.notes.append(head)
								ln_heads.erase(ch)
	c.sort_notes()
	c.audio_path = _resolve_audio(path, hdr["ojm_file"])
	return c


## Parses the 300-byte header of the modern OJN variant (magic "ojn\0" at
## offset 4). Pre-magic legacy headers are rejected rather than misparsed.
static func _parse_ojn_header(d: PackedByteArray) -> Dictionary:
	if d.size() < 300:
		return {}
	if d.slice(4, 8) != PackedByteArray([0x6F, 0x6A, 0x6E, 0x00]):  # "ojn\0"
		return {}
	var bpm := d.decode_float(16)
	if bpm <= 0.0 or bpm > 1000.0:
		return {}
	return {
		"bpm": bpm,
		"levels": [
			d.decode_s16(20), d.decode_s16(22), d.decode_s16(24),
		],
		"package_counts": [
			d.decode_s32(64), d.decode_s32(68), d.decode_s32(72),
		],
		"title": _decode_cstr(d.slice(108, 172)),
		"artist": _decode_cstr(d.slice(172, 204)),
		"noter": _decode_cstr(d.slice(204, 236)),
		"ojm_file": _decode_cstr(d.slice(236, 268)),
		"note_offsets": [
			d.decode_s32(284), d.decode_s32(288), d.decode_s32(292),
		],
	}


## Find playable audio for a chart. Prefers a decoded file sitting next to
## the chart; accepts an OJM that is secretly a plain OGG; otherwise gives up
## honestly (metronome mode) instead of shipping broken crypto.
static func _resolve_audio(chart_path: String, ojm_name: String) -> String:
	var dir := chart_path.get_base_dir()
	var candidates: Array[String] = []
	if ojm_name != "":
		var base := ojm_name.get_basename()
		for ext in ["ogg", "mp3", "wav"]:
			candidates.append(dir.path_join(base + "." + ext))
		candidates.append(dir.path_join(ojm_name))
	candidates.append(dir.path_join(chart_path.get_file().get_basename() + ".ogg"))
	for path in candidates:
		if not FileAccess.file_exists(path):
			continue
		if path.get_extension().to_lower() == "ojm":
			var f := FileAccess.open(path, FileAccess.READ)
			if f != null and f.get_buffer(4) == PackedByteArray([0x4F, 0x67, 0x67, 0x53]):  # "OggS"
				return path
			push_warning("ChartLibrary: encrypted OJM not supported, using metronome: " + path)
			continue
		return path
	return ""


static func _decode_cstr(bytes: PackedByteArray) -> String:
	var end := bytes.find(0)
	if end >= 0:
		bytes = bytes.slice(0, end)
	# OJN strings are usually a legacy codepage (often CP949). UTF-8 decodes
	# cleanly when possible; anything else degrades to '?' rather than crashing.
	var s := bytes.get_string_from_utf8()
	if s.is_empty() and bytes.size() > 0:
		s = bytes.get_string_from_ascii()
	return s.strip_edges()
