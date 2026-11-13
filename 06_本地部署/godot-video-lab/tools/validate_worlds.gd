extends SceneTree
## Exercise v2 world adapters using actual Godot physics and display-only replay.

var results: Array = []
var world: Node
var events: Array = []


## Run the isolated checks after the tree has initialized.
func _initialize() -> void:
	_run.call_deferred()


## Verify native contacts, complete replacement, capacity rejection and seek lifecycle.
func _run() -> void:
	Engine.physics_ticks_per_second = 120
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/examples/scene_v2.example.json"))
	base["world"]["physics_hz"] = 120
	base["world"]["gravity"] = [0, 450]
	base["world"]["max_dynamic_bodies"] = 12
	base["objects"][0]["transform"]["position"] = [200, 1060]
	base["objects"][0]["physics"]["velocity"] = [30, 140]
	base["objects"].remove_at(1)
	await _case_2d(base, "floor_split", true)
	var ball_pair := base.duplicate(true)
	ball_pair["world"]["gravity"] = [0, 0]
	ball_pair["objects"][0]["transform"]["position"] = [300, 600]
	ball_pair["objects"][0]["physics"]["velocity"] = [160, 0]
	var second: Dictionary = ball_pair["objects"][0].duplicate(true)
	second["id"] = "ball_B"
	second["transform"]["position"] = [420, 600]
	second["physics"]["velocity"] = [-160, 0]
	ball_pair["objects"].append(second)
	await _case_2d(ball_pair, "ball_pair_split", true)
	var cap := base.duplicate(true)
	cap["world"]["max_dynamic_bodies"] = 1
	await _case_2d(cap, "capacity_reason", false)
	var no_contact := base.duplicate(true)
	no_contact["world"]["gravity"] = [0, 0]
	no_contact["objects"][0]["transform"]["position"] = [300, 500]
	no_contact["objects"][0]["physics"]["velocity"] = [0, 0]
	await _case_2d(no_contact, "no_contact", false)
	var guarded := base.duplicate(true)
	guarded["objects"][0]["transform"]["position"] = [220, 1110]
	guarded["objects"][0]["physics"]["velocity"] = [0, 0]
	guarded["objects"][0]["physics"]["material"]["restitution"] = 0
	await _case_2d(guarded, "guard_expiry_current_contact", true)
	await _sensor_case(base)
	await _case_3d()
	var passed := true
	for result in results: passed = passed and bool(result["passed"])
	var file := FileAccess.open("res://outputs/worlds_validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": passed, "cases": results}, "\t"))
	print("WORLDS_VALIDATION " + JSON.stringify({"passed": passed, "cases": results}))
	quit(0 if passed else 1)


## Start a clean isolated world and collect its native and mechanism events.
func _start(doc: Dictionary, dimension: String, playback: bool = false) -> void:
	if is_instance_valid(world):
		root.remove_child(world)
		world.queue_free()
	events.clear()
	world = load("res://src/physics/world_" + dimension + ".gd").new()
	world.event_logged.connect(_observe)
	world.setup(doc, playback)
	root.add_child(world)


## Observe poses during contact dispatch to independently verify effect anchor placement.
func _observe(event: Dictionary) -> void:
	var copy := event.duplicate(true)
	if event.get("type", "") == "contact":
		for id in [str(event.get("id", "")), str(event.get("other_id", ""))]:
			if world.records.has(id) and world.records[id]["spec"].get("shape", {}).get("primitive", "") in ["circle", "sphere"]:
				copy["observed_ball_position"] = world.object_position(id)
	events.append(copy)


## Check a true 2D contact fixture and verify read-only reconstruction does not split.
func _case_2d(doc: Dictionary, label: String, expect_split: bool) -> void:
	_start(doc, "2d")
	if label == "guard_expiry_current_contact": world.records["ball_A"]["born"] = 0
	for tick in 180: await physics_frame
	await process_frame
	var report: Dictionary = world.get_report()
	var reasons: Array = []
	for event in events:
		if event.get("type", "") == "rule_rejected" and event.get("reason", "") not in reasons: reasons.append(event["reason"])
	var passed: bool = report["ledger_ok"] and ((report["splits"] > 0) if expect_split else (report["splits"] == 0))
	if label == "capacity_reason": passed = passed and "capacity_limit" in reasons
	if label == "no_contact": passed = passed and report["contacts"] == 0
	if label == "guard_expiry_current_contact": passed = passed and "newborn_guard" in reasons
	if label == "floor_split":
		var anchor_ok := false
		var observed: Dictionary = {}
		for event in events:
			if event.get("type", "") == "contact" and event.get("phase", "") == "enter" and "floor" in [event.get("id", ""), event.get("other_id", "")] and event.has("observed_ball_position"):
				observed = {"anchor": event["position"], "ball": event["observed_ball_position"], "source": event["position_source"]}
				anchor_ok = absf(float(event["position"][0]) - float(event["observed_ball_position"][0])) < 0.001 and absf(float(event["position"][1]) - 1129.0) < 0.001 and event["position_source"] == "shape_surface_estimate"
				break
		results.append({"name": "offcenter_floor_effect_anchor", "passed": anchor_ok, "observed": observed})
	var states: Array = world.capture_state()
	var definitions: Dictionary = world.get_definitions()
	_start(doc, "2d", true)
	world.apply_state(states, definitions)
	var ids: Array = []
	for state in states: ids.append(state["id"])
	var actual: Array = []
	for state in world.capture_state(): actual.append(state["id"])
	ids.sort()
	actual.sort()
	passed = passed and ids == actual and world.runner.splits == 0
	results.append({"name": label, "passed": passed, "splits": report["splits"], "contacts": report["contacts"], "ledger_ok": report["ledger_ok"], "reasons": reasons, "replay_lifecycle": ids == actual})


## A native Area2D overlap must retire a matching dynamic body exactly once.
func _sensor_case(base: Dictionary) -> void:
	var doc := base.duplicate(true)
	doc["world"]["gravity"] = [0, 0]
	doc["objects"][0]["transform"]["position"] = [300, 500]
	doc["objects"][0]["physics"]["velocity"] = [0, 220]
	doc["objects"][0]["mechanisms"] = ["remove_at_gate"]
	doc["objects"].append({"id": "gate", "tags": ["exit"], "shape": {"primitive": "rectangle", "size": [200, 100]},
		"transform": {"position": [300, 650]}, "physics": {"mode": "sensor", "collision_layer": 4, "collision_mask": 1}})
	doc["mechanisms"].append({"id": "remove_at_gate", "type": "despawn_on_contact", "conditions": {"other_tags_any": ["exit"]}})
	_start(doc, "2d")
	for tick in 180: await physics_frame
	await process_frame
	var report: Dictionary = world.get_report()
	results.append({"name": "sensor_despawn", "passed": report["active"] == 0 and report["retired"] == 1 and report["ledger_ok"], "contacts": report["contacts"], "retired": report["retired"]})


## Confirm sphere/box falling contacts and pure-display quaternion restoration in 3D.
func _case_3d() -> void:
	var doc := {"world": {"dimension": "3d", "gravity": [0, -9.8, 0], "physics_hz": 120}, "objects": [
		{"id": "sphere", "tags": ["ball"], "shape": {"primitive": "sphere", "radius": 0.44}, "transform": {"position": [-0.7, 3, 0]}, "physics": {"mode": "dynamic"}},
		{"id": "box", "shape": {"primitive": "box", "size": [0.8, 0.8, 0.8]}, "transform": {"position": [0.7, 4, 0]}, "physics": {"mode": "dynamic"}},
		{"id": "floor", "tags": ["boundary"], "shape": {"primitive": "box", "size": [10, 0.5, 8]}, "transform": {"position": [0, -0.25, 0]}, "physics": {"mode": "static"}}
	], "presentation": {"render": {}}, "mechanisms": []}
	_start(doc, "3d")
	for tick in 240: await physics_frame
	await process_frame
	var report: Dictionary = world.get_report()
	var states: Array = world.capture_state()
	var definitions: Dictionary = world.get_definitions()
	var passed: bool = report["contacts"] > 0 and report["escaped"] == 0 and report["ledger_ok"]
	_start(doc, "3d", true)
	world.apply_state(states, definitions)
	for state in world.capture_state():
		if str(state["id"]) in ["sphere", "box"]: passed = passed and float(state["position"][1]) >= 0.35
	results.append({"name": "3d_native_and_replay", "passed": passed, "contacts": report["contacts"], "escaped": report["escaped"], "ledger_ok": report["ledger_ok"]})
	doc["objects"].remove_at(1)
	doc["objects"][0]["mechanisms"] = ["sphere_split"]
	doc["mechanisms"] = [{"id": "sphere_split", "type": "split_on_contact", "params": {"children_total": 2}, "conditions": {"other_tags_any": ["boundary", "ball"]}}]
	doc["world"]["max_dynamic_bodies"] = 8
	_start(doc, "3d")
	for tick in 240: await physics_frame
	await process_frame
	report = world.get_report()
	results.append({"name": "3d_sphere_split", "passed": report["splits"] > 0 and report["ledger_ok"] and report["escaped"] == 0, "splits": report["splits"], "ledger_ok": report["ledger_ok"]})
