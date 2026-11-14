extends SceneTree
## Guard continuous simulation after repeated collisions, while preserving opt-in hit-stop.
const Document = preload("res://src/document/scene_document.gd")
const Session = preload("res://src/runtime/scene_session.gd")
var checks: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _measure(enabled: bool) -> Dictionary:
	var doc: Dictionary = Document.load_file("res://config/workbench_2d.json")["document"]
	for rule in doc["mechanisms"]:
		if rule.get("type", "") == "hit_stop_on_event": rule["enabled"] = enabled
	doc["presentation"]["audio"]["enabled"] = false
	var session := Session.new()
	root.add_child(session)
	session.load_document(doc)
	session.start_recording()
	var observed_hold := false
	while session.time < 4:
		await physics_frame
		observed_hold = observed_hold or session.get_info()["hit_stop_active"]
	session.stop_recording()
	var report: Dictionary = session.get_info()
	report["observed_hold"] = observed_hold
	report["recorded_hold"] = session.take.data["frames"].any(func(frame): return float(frame["time"]) - float(frame["sim_time"]) > 0.01)
	session.queue_free()
	await process_frame
	return report

func _run() -> void:
	var defaults_disabled := true
	for kind in ["2d", "3d", "perspective"]:
		var doc: Dictionary = Document.load_file("res://config/workbench_" + kind + ".json")["document"]
		for rule in doc["mechanisms"]:
			if rule.get("type", "") == "hit_stop_on_event": defaults_disabled = defaults_disabled and not rule["enabled"]
	checks["all_split_presets_default_to_continuous_motion"] = defaults_disabled
	var smooth: Dictionary = await _measure(false)
	var optional: Dictionary = await _measure(true)
	checks["repeated_collisions_keep_simulation_advancing"] = smooth["contacts"] >= 3 and smooth["splits"] >= 3 and is_equal_approx(smooth["time"], smooth["sim_time"]) and not smooth["recorded_hold"]
	checks["continuous_mode_has_no_hitstop"] = not smooth["observed_hold"] and smooth["hit_stop_elapsed_seconds"] == 0
	checks["explicit_hitstop_still_works_and_records"] = optional["observed_hold"] and optional["recorded_hold"] and optional["hit_stop_elapsed_seconds"] > 0
	var ui = load("res://src/ui/workbench_ui.gd").new()
	ui.setup(Document.load_file("res://config/workbench_2d.json")["document"], GradientTexture2D.new())
	root.add_child(ui)
	await process_frame
	ui.update_runtime({"fps": 60, "hit_stop_active": true, "hit_stop_elapsed_seconds": 0.2})
	checks["render_fps_and_physics_hold_are_distinguished"] = ui.runtime_label.text.contains("渲染 60 FPS") and ui.runtime_label.text.contains("物理暂停") and ui.runtime_label.text.contains("0.20s")
	ui.update_runtime({"fps": 60, "hit_stop_active": false, "hit_stop_elapsed_seconds": 0})
	checks["hold_badge_clears_after_fresh_run"] = not ui.runtime_label.text.contains("物理暂停") and not ui.runtime_label.text.contains("累计顿帧")
	checks["passed"] = not checks.values().has(false)
	var output := FileAccess.open("res://outputs/motion_validation.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(checks, "\t"))
	print("MOTION_VALIDATION ", JSON.stringify(checks))
	for child in root.get_children(): child.queue_free()
	var deadline := Time.get_ticks_msec() + 100
	while Time.get_ticks_msec() < deadline: await process_frame
	quit(0 if checks["passed"] else 1)
