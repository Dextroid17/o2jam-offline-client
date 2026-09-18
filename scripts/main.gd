class_name Main
extends Control
## Root screen manager. Screens are plain Controls built in code; Main owns
## exactly one at a time.

static var instance: Main

var current: Control
var last_entry: Dictionary = {}
var last_diff := 1


func _ready() -> void:
	instance = self
	# Smoke-test hook: `-- --auto-play-demo` jumps straight into the demo song
	# (used by CI/headless validation, harmless in normal runs).
	var args := OS.get_cmdline_args()
	if "--auto-play-demo" in args:
		play_song({"kind": "demo"}, 1)
		return
	if "--auto-screen" in args:
		var screen_name: String = args[args.find("--auto-screen") + 1]
		go(load("res://scripts/ui/%s.gd" % screen_name).new())
		return
	go(load("res://scripts/ui/main_menu.gd").new())


static func go(screen: Control) -> void:
	instance._go(screen)


func _go(screen: Control) -> void:
	if current != null:
		current.queue_free()
	current = screen
	add_child(screen)


static func play_song(entry: Dictionary, diff: int) -> void:
	var chart := ChartLibrary.load_chart(entry, diff)
	if chart == null:
		push_error("Main: failed to load chart: " + str(entry.get("path", "")))
		return
	instance.last_entry = entry
	instance.last_diff = diff
	var g: Control = load("res://scripts/game/gameplay.gd").new()
	g.setup(chart)
	go(g)


static func restart_song() -> void:
	if not instance.last_entry.is_empty():
		play_song(instance.last_entry, instance.last_diff)
