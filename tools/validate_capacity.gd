extends SceneTree
## Exercise the real world/take boundary, including retired lifecycle definitions.
const Document = preload("res://src/document/scene_document.gd")
const Take = preload("res://src/takes/take_store.gd")
const World = preload("res://src/physics/world_2d.gd")
const Session = preload("res://src/runtime/scene_session.gd")
var results: Array = []
var world: Node2D


## Wait for the tree before creating native bodies.
func _initialize() -> void:
	_run.call_deferred()


## Confirm valid physical scenes always fit the active-pose recording budget.
func _run() -> void:
	Engine.physics_ticks_per_second = 120
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/workbench_2d.json"))
	doc["world"]["max_dynamic_bodies"] = 256
	doc["world"]["gravity"] = [0, 0]
	doc["mechanisms"] = []
	var ball: Dictionary = doc["objects"][0].duplicate(true)
	doc["objects"] = doc["objects"].filter(func(spec): return spec.get("physics", {}).get("mode", "dynamic") != "dynamic")
	for index in 256:
		var copy := ball.duplicate(true)
		copy["id"] = "ball_%03d" % index
		copy["shape"]["radius"] = 3
		copy["transform"]["position"] = [90 + (index % 16) * 32, 300 + (index / 16) * 32]
		copy["physics"]["velocity"] = [0, 0]
		copy["mechanisms"] = []
		doc["objects"].append(copy)
	_check("256_dynamic_plus_4_walls_valid", Document.validate(doc).is_empty())
	await _start(doc)
	var states: Array = world.capture_state()
	var definitions: Dictionary = world.get_definitions()
	var take = Take.new()
	take.begin(doc)
	var appended: bool = take.append(0, 0, states, definitions)
	var path := "res://scratch/capacity_260.json"
	var saved: Error = take.save(path)
	var loaded = Take.new()
	var read: Error = loaded.load_take(path)
	_check("native_260_states_save_load", appended and states.size() == 260 and saved == OK and read == OK and loaded.sample(0)["states"].size() == 260, {"states": states.size()})
	var excess_dynamic := doc.duplicate(true)
	var extra_ball := ball.duplicate(true)
	extra_ball["id"] = "ball_extra"
	excess_dynamic["objects"].append(extra_ball)
	_check("257_dynamic_rejected", not Document.validate(excess_dynamic).is_empty())
	var wall: Dictionary = doc["objects"][0].duplicate(true)
	for index in 252:
		var copy := wall.duplicate(true)
		copy["id"] = "fixed_%03d" % index
		copy["shape"]["size"] = [2, 2]
		copy["transform"]["position"] = [40, 260 + index * 3]
		doc["objects"].append(copy)
	_check("256_dynamic_plus_256_fixed_valid", Document.validate(doc).is_empty())
	await _start(doc)
	states = world.capture_state()
	definitions = world.get_definitions()
	take.begin(doc)
	appended = take.append(0, 0, states, definitions)
	path = "res://scratch/capacity_512.json"
	saved = take.save(path)
	read = loaded.load_take(path)
	_check("native_512_states_save_load", appended and states.size() == 512 and saved == OK and read == OK and loaded.sample(0)["states"].size() == 512, {"states": states.size()})
	var excess_fixed := doc.duplicate(true)
	var extra_wall := wall.duplicate(true)
	extra_wall["id"] = "wall_extra"
	excess_fixed["objects"].append(extra_wall)
	_check("257_fixed_rejected", not Document.validate(excess_fixed).is_empty())
	for index in 600:
		var retired := ball.duplicate(true)
		retired["id"] = "retired_%04d" % index
		definitions[retired["id"]] = retired
	take.begin(doc)
	appended = take.append(0, 0, states, definitions)
	path = "res://scratch/capacity_lifecycles.json"
	saved = take.save(path)
	read = loaded.load_take(path)
	_check("retired_definitions_do_not_consume_active_budget", appended and definitions.size() == 1112 and saved == OK and read == OK and loaded.data["definitions"].size() == 1112, {"definitions": definitions.size(), "active": states.size()})
	var excess_states := states.duplicate(true)
	var extra_state: Dictionary = states[0].duplicate(true)
	extra_state["id"] = "overflow"
	excess_states.append(extra_state)
	var old_frames: int = take.data["frames"].size()
	var rejected: bool = not take.append(0.1, 0.1, excess_states, definitions)
	_check("513_states_rejected_and_incomplete_save_blocked", rejected and take.data["frames"].size() == old_frames and not take.recording_error.is_empty() and take.save("res://scratch/capacity_overflow.json") == ERR_INVALID_DATA)
	for name in ["workbench_2d", "workbench_3d"]:
		path = "res://outputs/takes/" + name + ".json"
		if FileAccess.file_exists(path):
			read = loaded.load_take(path)
			_check("existing_" + name + "_compatible", read == OK and loaded.recording_error.is_empty())
	root.remove_child(world)
	world.queue_free()
	await process_frame
	var session := Session.new()
	root.add_child(session)
	session.load_document(doc)
	session.start_recording()
	# Simulate a runtime component violating the legal document's active budget.
	session.stage.world.create_object(extra_wall, 0)
	session._capture()
	_check("session_stops_and_reports_capture_overflow", session.mode == "paused" and not session.last_error.is_empty() and session.get_info()["last_error"] == session.take.last_error and session.take.save("res://scratch/session_overflow.json") == ERR_INVALID_DATA)
	session.start_recording()
	_check("fresh_recording_clears_prior_failure", session.mode == "recording" and session.last_error.is_empty() and session.take.recording_error.is_empty() and session.take.data["frames"][0]["states"].size() == 512)
	session.stop_recording()
	root.remove_child(session)
	session.queue_free()
	var passed := true
	for result in results: passed = passed and bool(result["passed"])
	var file := FileAccess.open("res://outputs/capacity_validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": passed, "cases": results}, "\t"))
	print("CAPACITY_VALIDATION " + JSON.stringify({"passed": passed, "cases": results}))
	quit(0 if passed else 1)


## Build fresh native bodies so capture counts are measured independently of JSON.
func _start(doc: Dictionary) -> void:
	if is_instance_valid(world):
		root.remove_child(world)
		world.queue_free()
	world = World.new()
	world.setup(doc)
	root.add_child(world)
	for tick in 3: await physics_frame
	await process_frame


## Store only the evidence relevant to the recording budget.
func _check(label: String, passed: bool, evidence: Dictionary = {}) -> void:
	results.append({"name": label, "passed": passed, "evidence": evidence})
