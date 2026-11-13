extends SceneTree
## Exercise real descendant contacts and distinguish policy from capacity/placement limits.
const Session = preload("res://src/runtime/scene_session.gd")
const Document = preload("res://src/document/scene_document.gd")
var results: Array = []
var events: Array = []
var world: Node


## Defer native node creation until the tree is ready.
func _initialize() -> void:
	_run.call_deferred()


## Baseline mode is run before the policy exists; the full suite checks the new switch.
func _run() -> void:
	var baseline_only := "--baseline-only" in OS.get_cmdline_user_args()
	await _diagnose_default_scene()
	for dimension in ["2d", "3d"]:
		await _case(dimension, null, 8, "default_inherited", true)
		if not baseline_only:
			await _case(dimension, true, 8, "enabled_inherited", true)
			await _case(dimension, false, 8, "disabled_first_generation_only", false)
			await _case(dimension, true, 2, "capacity_is_still_enforced", false)
	if not baseline_only:
		await _other_rule_case()
		var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/workbench_2d.json"))
		for value in ["false", 0, null]:
			doc["mechanisms"][0]["params"]["children_can_split"] = value
			_check("non_boolean_policy_rejected_" + str(value), not Document.validate(doc).is_empty())
		for value in [true, false]:
			doc["mechanisms"][0]["params"]["children_can_split"] = value
			_check("boolean_policy_accepted_" + str(value), Document.validate(doc).is_empty())
	await _clear_world()
	var passed := results.all(func(result): return result["passed"])
	var path := "res://outputs/split_inheritance_baseline.json" if baseline_only else "res://outputs/split_inheritance_validation.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": passed, "cases": results}, "\t"))
	file.close()
	print("SPLIT_INHERITANCE " + JSON.stringify({"passed": passed, "cases": results}))
	quit(0 if passed else 1)


## Run the shipped 48-body scene through the actual hit-stop/recording session.
func _diagnose_default_scene() -> void:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/workbench_2d.json"))
	doc["presentation"]["audio"]["enabled"] = false
	var session := Session.new()
	root.add_child(session)
	session.event_logged.connect(func(event): events.append(event.duplicate(true)))
	session.load_document(doc)
	events.clear()
	session.start_recording()
	for frame in 1600:
		await process_frame
		if session.time >= 8: break
	session.stop_recording()
	var report: Dictionary = session.stage.world.get_report()
	var definitions: Dictionary = session.stage.world.get_definitions()
	var evidence := _evidence(report, definitions)
	evidence["film_time"] = session.time
	evidence["sim_time"] = session.sim_time
	evidence["configured_capacity"] = int(doc["world"]["max_dynamic_bodies"])
	_check("shipped_2d_descendants_reach_48_body_capacity", session.time >= 8 and report["active"] == 48 and report["ledger_ok"] and evidence["highest_generation"] >= 2 and evidence["descendant_rules_inherited"] and evidence["rejected"].get("capacity_limit", 0) > 0, evidence)
	root.remove_child(session)
	session.queue_free()
	await process_frame


## Both dimensions receive the same split rule while using native engine contacts.
func _fixture(dimension: String, policy: Variant, capacity: int) -> Dictionary:
	var three := dimension == "3d"
	var rule := {"id": "split_ball", "type": "split_on_contact", "priority": 100,
		"params": {"children_total": 2}, "conditions": {"other_tags_any": ["boundary", "ball"]}}
	if policy != null: rule["params"]["children_can_split"] = policy
	return {"world": {"dimension": dimension, "gravity": [0, -9.8, 0] if three else [0, 450], "physics_hz": 120, "max_dynamic_bodies": capacity},
		"objects": [{"id": "parent", "tags": ["ball"], "shape": {"primitive": "sphere" if three else "circle", "radius": 0.44 if three else 18},
			"transform": {"position": [-0.7, 3, 0] if three else [200, 1060]}, "physics": {"mode": "dynamic", "velocity": [0, 0, 0] if three else [30, 140]}, "mechanisms": ["split_ball"]},
			{"id": "floor", "tags": ["boundary"], "shape": {"primitive": "box" if three else "rectangle", "size": [10, 0.5, 8] if three else [646, 14]},
				"transform": {"position": [0, -0.25, 0] if three else [360, 1136]}, "physics": {"mode": "static"}}],
		"presentation": {"render": {}}, "mechanisms": [rule]}


## Bound growth by policy or capacity, then verify the lifecycle conservation ledger.
func _case(dimension: String, policy: Variant, capacity: int, label: String, expect_descendants: bool) -> void:
	var doc := _fixture(dimension, policy, capacity)
	await _start(doc, dimension)
	for tick in 480: await physics_frame
	await process_frame
	var report: Dictionary = world.get_report()
	var evidence := _evidence(report, world.get_definitions())
	var passed: bool = report["ledger_ok"] and report["active"] <= capacity and report["splits"] > 0 and evidence["descendant_rules_inherited"]
	if expect_descendants: passed = passed and evidence["highest_generation"] >= 2
	elif label == "disabled_first_generation_only": passed = passed and report["splits"] == 1 and evidence["highest_generation"] == 1 and evidence["rejected"].get("children_split_disabled", 0) > 0
	else: passed = passed and report["active"] == 2 and evidence["highest_generation"] == 1 and evidence["rejected"].get("capacity_limit", 0) > 0
	_check(dimension + "_" + label, passed, evidence)


## Disabling descendant splits must not remove their other inherited contact rules.
func _other_rule_case() -> void:
	var doc := _fixture("2d", false, 8)
	doc["objects"][0]["mechanisms"].append("retire_on_floor")
	doc["mechanisms"].append({"id": "retire_on_floor", "type": "despawn_on_contact", "conditions": {"other_tags_any": ["boundary"]}})
	await _start(doc, "2d")
	for tick in 480: await physics_frame
	await process_frame
	var report: Dictionary = world.get_report()
	var evidence := _evidence(report, world.get_definitions())
	_check("disabled_descendants_keep_other_contact_rules", report["splits"] == 1 and report["active"] == 0 and report["retired"] == 3 and report["ledger_ok"] and evidence["rejected"].get("children_split_disabled", 0) > 0, evidence)


## Keep each fixture independent and restore the server after a Session paused it.
func _start(doc: Dictionary, dimension: String) -> void:
	await _clear_world()
	events.clear()
	Engine.physics_ticks_per_second = 120
	PhysicsServer2D.set_active(true)
	PhysicsServer3D.set_active(true)
	world = load("res://src/physics/world_" + dimension + ".gd").new()
	world.event_logged.connect(func(event): events.append(event.duplicate(true)))
	world.setup(doc)
	root.add_child(world)


## Observe definitions and emitted reasons rather than predicting solver outcomes.
func _evidence(report: Dictionary, definitions: Dictionary) -> Dictionary:
	var generation := 0
	var inherited := true
	for spec in definitions.values():
		generation = maxi(generation, int(spec.get("generation", 0)))
		if int(spec.get("generation", 0)) > 0: inherited = inherited and "split_ball" in spec.get("mechanisms", [])
	var rejected: Dictionary = {}
	var first_capacity_time := -1.0
	for event in events:
		if event.get("type", "") != "rule_rejected": continue
		var reason := str(event.get("reason", ""))
		rejected[reason] = int(rejected.get(reason, 0)) + 1
		if reason == "capacity_limit" and first_capacity_time < 0: first_capacity_time = float(event.get("time", 0))
	return {"active": report["active"], "splits": report["splits"], "births": report["births"], "retired": report["retired"], "ledger_ok": report["ledger_ok"], "highest_generation": generation,
		"descendant_rules_inherited": inherited, "rejected": rejected, "first_capacity_time": first_capacity_time}


## Release a complete world before starting another native fixture.
func _clear_world() -> void:
	if is_instance_valid(world):
		root.remove_child(world)
		world.queue_free()
	await process_frame


## Retain compact, directly inspectable evidence for every assertion.
func _check(label: String, passed: bool, evidence: Dictionary = {}) -> void:
	results.append({"name": label, "passed": passed, "evidence": evidence})
