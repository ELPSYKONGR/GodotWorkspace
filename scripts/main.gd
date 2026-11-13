extends Node
## JSON-driven preview host. Keeps physical scene, UI and export orchestration separate.

var config_path := "res://config/demo_2d.json"
var report_path := ""
var snapshot_path := ""
var target_frames := 0
var rendered_frames := 0
var config: Dictionary = {}
var probe: Node
var ui: CanvasLayer
var status: Label
var user_paused := false
var hold_remaining := 0.0
var hold_frames := 0
var events: Array[Dictionary] = []
var config_mtime := 0
var watch_elapsed := 0.0
var finishing := false
var load_error := ""


# Read command-line overrides before building the configured scene.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--config="): config_path = arg.trim_prefix("--config=")
		elif arg.begins_with("--report="): report_path = arg.trim_prefix("--report=")
		elif arg.begins_with("--snapshot="): snapshot_path = arg.trim_prefix("--snapshot=")
		elif arg.begins_with("--frames="): target_frames = maxi(1, int(arg.trim_prefix("--frames=")))
	if not _load_scene():
		get_tree().quit(2)


func _load_scene() -> bool:
	# Parse before replacing the active scene; an invalid edit keeps the previous preview.
	var parser := JSON.new()
	var source := FileAccess.get_file_as_string(config_path)
	if source.is_empty() or parser.parse(source) != OK or not parser.data is Dictionary:
		load_error = "配置读取失败：" + config_path + " " + parser.get_error_message()
		push_error(load_error)
		return false
	var next: Dictionary = parser.data
	if str(next.get("mode", "2d")) not in ["2d", "3d"]:
		push_error("mode must be 2d or 3d")
		return false
	config = next
	config_mtime = FileAccess.get_modified_time(config_path)
	load_error = ""
	get_tree().paused = false
	user_paused = false
	hold_remaining = 0
	hold_frames = 0
	events.clear()
	if is_instance_valid(probe):
		remove_child(probe)
		probe.queue_free()
	if is_instance_valid(ui):
		remove_child(ui)
		ui.queue_free()
	Engine.physics_ticks_per_second = clampi(int(config.get("physics_hz", 120)), 60, 480)
	Engine.max_fps = clampi(int(config.get("preview_fps", 60)), 15, 240)
	var script_path := "res://scripts/probe_2d.gd" if config.get("mode", "2d") == "2d" else "res://scripts/probe_3d.gd"
	var scene_script = load(script_path)
	if scene_script == null:
		return false
	probe = scene_script.new()
	probe.process_mode = Node.PROCESS_MODE_PAUSABLE
	probe.event_logged.connect(_on_event)
	probe.setup(config)
	add_child(probe)
	_build_ui()
	return true


# Put configurable text inside the rendered viewport, using an installed font.
func _label(text: String, at: Vector2, size: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.size = size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	var font := SystemFont.new()
	font.font_names = PackedStringArray([str(config.get("font_family", "Microsoft YaHei")), "Noto Sans CJK SC", "Arial"])
	label.add_theme_font_override("font", font)
	ui.add_child(label)
	return label


# Keep the overlay independent of either physical scene.
func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	_label(str(config.get("title", "碰撞分裂实验")), Vector2(44, 54), Vector2(640, 65), int(config.get("title_size", 44)), Color(str(config.get("text_color", "#edf5ff"))))
	_label(str(config.get("subtitle", "真实二维刚体 · 接触触发 1 → 2")), Vector2(44, 130), Vector2(640, 60), int(config.get("subtitle_size", 23)), Color("9cb2cc"))
	status = _label("", Vector2(44, 1160), Vector2(640, 46), 22, Color("c0d7ee"))
	_label("1 二维  2 正交三维  3 透视三维\n空格 暂停  R 重放  F5 重载配置", Vector2(44, 1210), Vector2(640, 65), 18, Color("819ab7"))


# Capture an audit trail and request one shared hold for simultaneous splits.
func _on_event(event: Dictionary) -> void:
	events.append(event.duplicate(true))
	if event.get("type", "") == "split":
		# All splits in one physical step share one hold; output time continues during holds.
		hold_remaining = maxf(hold_remaining, clampf(float(config.get("hitstop_seconds", 0.06)), 0.0, 0.5))


# Output time continues while the physical world is held or manually paused.
func _process(delta: float) -> void:
	if finishing or not is_instance_valid(probe):
		return
	rendered_frames += 1
	var hold := hold_remaining > 0
	if hold:
		hold_frames += 1
		hold_remaining = maxf(0, hold_remaining - delta)
	get_tree().paused = user_paused or hold
	var report: Dictionary = probe.get_report()
	status.text = "物体 %d   碰撞 %d   分裂 %d%s" % [int(report.get("active", 0)), int(report.get("collision_events", report.get("contact_counts", {}).get("wall", 0) + report.get("contact_counts", {}).get("ball", 0))), int(report.get("splits", 0)), "   暂停" if get_tree().paused else ""]
	if target_frames > 0 and rendered_frames >= target_frames:
		finishing = true
		_finish.call_deferred()
	if target_frames == 0:
		watch_elapsed += delta
		if watch_elapsed >= 0.5:
			watch_elapsed = 0
			if FileAccess.get_modified_time(config_path) != config_mtime:
				_load_scene.call_deferred()


# Preview-only controls cannot alter an unattended export.
func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or target_frames > 0:
		return
	if event.keycode == KEY_SPACE:
		user_paused = not user_paused
	elif event.keycode == KEY_R or event.keycode == KEY_F5:
		_load_scene.call_deferred()
	elif event.keycode in [KEY_1, KEY_2, KEY_3]:
		config_path = {KEY_1: "res://config/demo_2d.json", KEY_2: "res://config/demo_3d.json", KEY_3: "res://config/demo_perspective.json"}[event.keycode]
		_load_scene.call_deferred()


func _finish() -> void:
	# Wait for a real rendered frame; headless runs only validate physics and the report.
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	if not snapshot_path.is_empty() and DisplayServer.get_name() != "headless":
		var snapshot_error := get_viewport().get_texture().get_image().save_png(snapshot_path)
		if snapshot_error != OK:
			push_error("Snapshot save failed: " + str(snapshot_error))
	var report: Dictionary = probe.get_report()
	report["godot_version"] = Engine.get_version_info()
	report["config_path"] = config_path
	report["config"] = config
	report["rendered_frames"] = rendered_frames
	report["hold_frames"] = hold_frames
	report["display"] = DisplayServer.get_name()
	report["user_data_dir"] = OS.get_user_data_dir()
	report["physics_hz"] = Engine.physics_ticks_per_second
	report["events"] = events
	if not report_path.is_empty():
		var file := FileAccess.open(report_path, FileAccess.WRITE)
		if file == null:
			push_error("Report save failed: " + report_path)
			get_tree().quit(3)
			return
		file.store_string(JSON.stringify(report, "\t"))
	print("PROBE_COMPLETE " + JSON.stringify({"frames": rendered_frames, "active": report.get("active", 0), "splits": report.get("splits", 0), "collisions": report.get("collision_events", 0), "hold_frames": hold_frames}))
	get_tree().quit()
