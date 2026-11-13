extends SceneTree
## AI/CLI recording uses the same native session and clock as the workbench.
const Session = preload("res://src/runtime/scene_session.gd")
const Document = preload("res://src/document/scene_document.gd")

func _initialize() -> void:
	_run.call_deferred()

## Record real physics before choosing output FPS or visual production settings.
func _run() -> void:
	var scene := "res://config/workbench_2d.json"
	var output := "res://outputs/takes/latest.json"
	var duration := 8.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="): scene = arg.trim_prefix("--scene=")
		elif arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		elif arg.begins_with("--seconds="): duration = clampf(float(arg.trim_prefix("--seconds=")), 0.1, 60)
	var loaded := Document.load_file(scene)
	if not loaded["ok"]: push_error(loaded["error"]); quit(2); return
	var session := Session.new()
	root.add_child(session)
	session.load_document(loaded["document"])
	session.start_recording()
	while session.time < duration:
		await process_frame
		if session.mode != "recording": break
	session.stop_recording()
	if session.take.save(output) != OK: push_error(session.take.last_error); quit(3); return
	var report: Dictionary = session.get_info()
	report["take_frames"] = session.take.get_data()["frames"].size()
	report["take_events"] = session.take.get_data()["events"].size()
	report["path"] = ProjectSettings.globalize_path(output)
	report["user_data_dir"] = OS.get_user_data_dir()
	var file := FileAccess.open(output + ".report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("TAKE_RECORDED " + JSON.stringify({"path": output, "duration": session.time, "sim_time": session.sim_time, "frames": report["take_frames"], "splits": report.get("splits", 0)}))
	await create_timer(0.1).timeout
	quit()
