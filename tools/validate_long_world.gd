extends SceneTree
## Record a real long-world simulation, then compare sequential and arbitrary camera replay.
const Session = preload("res://src/runtime/scene_session.gd")
const Document = preload("res://src/document/scene_document.gd")
const CameraTrack = preload("res://src/presentation/camera_track_2d.gd")
var checks: Dictionary = {}

## Native physics and committed snapshots must run in the actual scene tree.
func _initialize() -> void:
	_run.call_deferred()

## Export the validated Take so the identical motion can be used by the GPU producer.
func _run() -> void:
	var loaded := Document.load_file("res://config/workbench_long.json")
	if not loaded["ok"]: push_error(loaded["error"]); quit(2); return
	var doc: Dictionary = loaded["document"]
	var session = Session.new()
	root.add_child(session)
	session.load_document(doc)
	session.start_recording()
	var furthest_view := 0.0
	var followed_descendant := false
	var monotonic := true
	var physical_offset_ok := true
	var prior_top := 0.0
	var live_samples: Array = []
	while session.time < 8.0 and session.mode == "recording":
		await process_frame
		var top: Vector2 = session.stage.view_top
		monotonic = monotonic and top.y >= prior_top - 0.000001
		prior_top = top.y
		furthest_view = maxf(furthest_view, top.y)
		var target: String = session.stage.camera_track.state.get("target", "")
		if target != "ball_A" and not target.is_empty():
			followed_descendant = followed_descendant or session.stage.world.definitions.get(target, {}).get("root_id", "") == "ball_A"
		physical_offset_ok = physical_offset_ok and session.stage.world.records["floor"]["body"].global_position == Vector2(360,19988)
		live_samples.append({"time":session.time,"top":top})
	session.stop_recording()
	var report: Dictionary = session.get_info()
	var data: Dictionary = session.take.get_data()
	checks["long_scene_records_native_splits"] = report.get("splits",0) > 0 and report.get("ledger_ok",false) and data["frames"].size() > 900
	checks["camera_passes_first_screen"] = furthest_view > 1280
	checks["only_down_camera_is_monotonic_in_real_run"] = monotonic
	checks["camera_tracks_real_child_after_parent_retirement"] = followed_descendant
	checks["camera_does_not_translate_native_floor"] = physical_offset_ok
	var tracker = CameraTrack.new()
	tracker.configure(doc)
	var live_error := 0.0
	for sample in live_samples:
		tracker.sample(sample["time"],data)
		live_error = maxf(live_error, tracker.state["top"].distance_to(sample["top"]))
	checks["live_and_recorded_camera_match"] = live_error < 0.001
	var expected: Dictionary = {}
	for time in [0.0,0.5,1.0,2.5,4.0,5.5,7.5]:
		tracker.sample(time,data)
		expected[time] = tracker.state["top"]
	var seek_error := 0.0
	for time in [7.5,0.5,5.5,0.0,4.0,1.0,2.5]:
		session.seek(time)
		seek_error = maxf(seek_error, session.stage.view_top.distance_to(expected[time]))
	checks["arbitrary_seek_matches_sequential_camera"] = seek_error < 0.001 and session.stage.world.runner.splits == 0
	checks["take_is_self_contained_and_saved"] = session.take.save("res://outputs/long_world_validation.take.json") == OK
	checks["passed"] = not checks.values().has(false)
	var result := {"passed":checks["passed"],"checks":checks,"duration":session.take.get_duration(),"frames":data["frames"].size(),"splits":report.get("splits",0),"maximum_camera_y":furthest_view,"live_replay_max_error_px":live_error,"seek_max_error_px":seek_error}
	FileAccess.open("res://outputs/long_world_validation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("LONG_WORLD ",JSON.stringify(result))
	session.queue_free()
	await process_frame
	quit(0 if checks["passed"] else 1)
