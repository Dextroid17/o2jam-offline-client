extends Node
## Global settings: persistence, input map, video/threading policy.
##
## Latency policy baked in here:
##  - VSync off, FPS capped high (default 240) so input polling is not
##    frame-quantized to the display refresh.
##  - Accumulated input OFF: input events are dispatched immediately instead
##    of being batched once per frame.

const CONFIG_PATH := "user://settings.cfg"
const DEFAULT_LANE_KEYS := [KEY_S, KEY_D, KEY_F, KEY_SPACE, KEY_J, KEY_K, KEY_L]

## Global audio offset in milliseconds, from the calibration screen (-100..+100).
## Positive = your hits land late relative to what you hear (slow audio path),
## so the clock is advanced to compensate.
var offset_ms: float = 0.0
## Note fall speed, pixels per second at 720p reference height.
var scroll_speed: float = 900.0
var fps_cap: int = 240
var vsync_enabled: bool = false
## Folder scanned for charts (.ojn / .json). Empty = built-in user://songs.
var songs_dir: String = ""
var lane_keys: Array = DEFAULT_LANE_KEYS.duplicate()


func _ready() -> void:
	load_config()
	setup_input_map()
	apply_video_settings()
	Input.set_use_accumulated_input(false)


func setup_input_map() -> void:
	for i in 7:
		var action := "lane_%d" % (i + 1)
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for e in InputMap.action_get_events(action):
			InputMap.action_erase_event(action, e)
		var ev := InputEventKey.new()
		ev.physical_keycode = lane_keys[i]
		InputMap.action_add_event(action, ev)
	# Shared with the calibration screen.
	if not InputMap.has_action("calibrate_tap"):
		InputMap.add_action("calibrate_tap")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_SPACE
		InputMap.action_add_event("calibrate_tap", ev)


func apply_video_settings() -> void:
	if vsync_enabled:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		Engine.max_fps = 0
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = fps_cap


func load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	offset_ms = cfg.get_value("audio", "offset_ms", offset_ms)
	scroll_speed = cfg.get_value("gameplay", "scroll_speed", scroll_speed)
	fps_cap = cfg.get_value("video", "fps_cap", fps_cap)
	vsync_enabled = cfg.get_value("video", "vsync", vsync_enabled)
	songs_dir = cfg.get_value("songs", "dir", songs_dir)
	var keys: Array = cfg.get_value("input", "lane_keys", lane_keys)
	if keys.size() == 7:
		lane_keys = keys


func save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "offset_ms", offset_ms)
	cfg.set_value("gameplay", "scroll_speed", scroll_speed)
	cfg.set_value("video", "fps_cap", fps_cap)
	cfg.set_value("video", "vsync", vsync_enabled)
	cfg.set_value("songs", "dir", songs_dir)
	cfg.set_value("input", "lane_keys", lane_keys)
	cfg.save(CONFIG_PATH)


func default_songs_dir() -> String:
	if songs_dir != "":
		return songs_dir
	# user://songs always exists and is writable; drop .ojn/.json charts here.
	DirAccess.make_dir_recursive_absolute("user://songs")
	return "user://songs"
