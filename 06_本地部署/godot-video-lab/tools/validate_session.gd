extends SceneTree
## Verify the actual session clocks, single solver step and replay lifecycle.

const Session = preload("res://src/runtime/scene_session.gd")
const Document = preload("res://src/document/scene_document.gd")
var session: Node
var results: Array = []


## Begin after root tree initialization so all native resources are available.
func _initialize() -> void:
	_run.call_deferred()


## Execute observable motion/clock checks instead of mirroring implementation fields.
func _run() -> void:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/workbench_2d.json"))
	doc["presentation"]["audio"]["enabled"] = false
	doc["presentation"]["effects"]["enabled"] = false
	doc["world"]["gravity"] = [0, 0]
	doc["objects"][0]["physics"]["velocity"] = [240, 0]
	doc["objects"][0]["physics"]["linear_damp"] = 0
	doc["objects"][0]["mechanisms"] = []
	doc["objects"][1]["mechanisms"] = []
	session = Session.new()
	root.add_child(session)
	session.load_document(doc)
	var edit_pose := _pose()
	for frame in 8: await process_frame
	results.append({"name": "edit_world_stationary", "passed": edit_pose == _pose() and session.time == 0 and session.sim_time == 0})
	var before := _ball_position()
	session.step_once()
	for frame in 10: await process_frame
	var after := _ball_position()
	var ticks: int = session.stage.world.get_report()["physics_tick"]
	var movement := after.x - before.x
	var expected := 240.0 / float(doc["world"]["physics_hz"])
	results.append({"name": "single_native_physics_step", "passed": ticks == 1 and absf(movement - expected) < 0.02,
		"actual_world_ticks": ticks, "actual_displacement": movement, "expected_displacement": expected,
		"film_time": session.time, "sim_time": session.sim_time})
	var pause_pose := _pose()
	var pause_time: float = session.time
	for frame in 8: await process_frame
	results.append({"name": "paused_pose_and_clocks", "passed": pause_pose == _pose() and session.time == pause_time})
	var split_doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/workbench_2d.json"))
	split_doc["presentation"]["audio"]["enabled"] = false
	split_doc["objects"][0]["transform"]["position"] = [220, 1060]
	split_doc["objects"][0]["physics"]["velocity"] = [0, 180]
	session.load_document(split_doc)
	session.start_recording()
	for frame in 1000:
		await process_frame
		if session.time >= 3.2: break
	session.stop_recording()
	var report: Dictionary = session.stage.world.get_report()
	var recorded_time: float = session.take.get_duration()
	var recorded_events: int = session.take.get_data()["events"].size()
	results.append({"name": "recording_hitstop_and_ledger", "passed": recorded_time >= 3.0 and session.sim_time < recorded_time and report["splits"] > 0 and report["ledger_ok"],
		"duration": recorded_time, "sim_time": session.sim_time, "splits": report["splits"], "events": recorded_events,
		"ledger_ok": report["ledger_ok"], "frames": session.take.get_data()["frames"].size()})
	var first_seen: Dictionary = {}
	for frame in session.take.get_data()["frames"]:
		for state in frame["states"]:
			if not first_seen.has(state["id"]): first_seen[state["id"]] = float(frame["time"])
	var maximum_offset := 0.0
	var minimum_offset := 0.0
	for event in session.take.get_data()["events"]:
		if event.get("type", "") == "birth" and not str(event.get("parent", "")).is_empty():
			var difference: float = float(first_seen.get(event["id"], event["time"])) - float(event["time"])
			maximum_offset = maxf(maximum_offset, difference)
			minimum_offset = minf(minimum_offset, difference)
	results.append({"name": "birth_event_pose_alignment", "passed": maxf(absf(minimum_offset), maximum_offset) <= 0.000001,
		"earliest_offset_seconds": minimum_offset, "latest_offset_seconds": maximum_offset, "tolerance_seconds": 0.000001})
	var count_before: int = session.events.size()
	session.seek(1.0)
	var replay_pose := _pose()
	session.seek(2.0)
	session.seek(0.0)
	session.seek(1.0)
	results.append({"name": "replay_round_trip_no_new_events", "passed": replay_pose == _pose() and session.events.size() == count_before and session.take.get_data()["events"].size() == recorded_events and session.stage.world.runner.splits == 0,
		"event_count_before": count_before, "event_count_after": session.events.size(), "pose_identical": replay_pose == _pose()})
	var presentation_doc: Dictionary = split_doc.duplicate(true)
	presentation_doc["objects"][0]["appearance"]["color"] = "#3b82f6"
	presentation_doc["presentation"]["captions"][0]["text"] = "验证文字修改"
	var hash_before := Document.simulation_hash(split_doc)
	session.apply_presentation(presentation_doc)
	results.append({"name": "presentation_reuses_take", "passed": Document.simulation_hash(presentation_doc) == hash_before and not session.get_info()["take_stale"]})
	var physics_doc := presentation_doc.duplicate(true)
	physics_doc["objects"][0]["physics"]["mass"] = 2.0
	session.load_document(physics_doc)
	results.append({"name": "physics_change_marks_take_stale", "passed": session.get_info()["take_stale"]})
	var passed := true
	for result in results: passed = passed and bool(result["passed"])
	var file := FileAccess.open("res://outputs/session_validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": passed, "cases": results}, "\t"))
	print("SESSION_VALIDATION " + JSON.stringify({"passed": passed, "cases": results}))
	root.remove_child(session)
	session.queue_free()
	quit(0 if passed else 1)


## Return the observed first ball position from actual adapter state.
func _ball_position() -> Vector2:
	for state in session.stage.world.capture_state():
		if state["id"] == "ball_A": return Vector2(float(state["position"][0]), float(state["position"][1]))
	return Vector2.INF


## Compare stable IDs and actual poses independent of dictionary insertion order.
func _pose() -> String:
	var states: Array = session.stage.world.capture_state()
	states.sort_custom(func(a, b): return str(a["id"]) < str(b["id"]))
	return JSON.stringify(states)
