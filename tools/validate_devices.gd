extends SceneTree
## Native motor/contact, editor transaction, pause, recorded replay and persistence acceptance.
const Document = preload("res://src/document/scene_document.gd")
const Device = preload("res://src/document/device_spec.gd")
const Session = preload("res://src/runtime/scene_session.gd")
var checks: Dictionary = {}
var capture := false

## Run after the root can host actual sessions and native controls.
func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()

## Record a real GPU screenshot only when explicitly requested.
func _shot(name: String) -> void:
	if not capture: return
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/devices/" + name + ".png")

## Extract one JSON pose without relying on the motor's implementation.
func _state(states: Array, id: String) -> Dictionary:
	for state in states:
		if state["id"] == id: return state
	return {}

## Exercise the complete existing workbench rather than a second inspector implementation.
func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://outputs/devices")
	var loaded := Document.load_file("res://config/workbench_devices.json")
	checks["demo_document_valid"] = loaded["ok"]
	checks["malformed_component_container_rejected"] = not Device.validate({"world": null, "objects": null}).is_empty()
	if not loaded["ok"]: push_error(loaded["error"]); quit(2); return
	var doc: Dictionary = loaded["document"]
	var bad := doc.duplicate(true)
	bad["objects"][5]["motion"]["period_seconds"] = 0
	checks["zero_period_rejected"] = not Document.validate(bad).is_empty()
	bad = doc.duplicate(true)
	bad["objects"][5]["physics"]["mode"] = "dynamic"
	checks["dynamic_motor_rejected"] = not Document.validate(bad).is_empty()
	bad = doc.duplicate(true)
	bad["objects"][5]["motion"]["pivot"] = [null, 0]
	checks["malformed_pivot_rejected"] = not Document.validate(bad).is_empty()
	var host = load("res://src/ui/workbench.gd").new()
	root.add_child(host)
	await process_frame
	host.service.execute({"op": "scene.load", "args": {"path": "res://config/workbench_devices.json"}})
	var panel: Node = host.panel.object_panel
	checks["device_entry_visible_in_2d"] = not panel.device_menu.disabled and panel.device_menu.get_popup().item_count == 3
	for index in 3:
		panel.device_menu.get_popup().id_pressed.emit(index)
		checks["add_" + Device.KINDS[index]] = host.service.document["objects"].back().get("motion", {}).get("type", "") == Device.KINDS[index]
		host.service.execute({"op": "history.undo"})
	checks["adding_device_undo_preserves_scene"] = host.service.document["objects"] == doc["objects"]
	# Existing dynamic objects can become driven shapes without replacing their identity.
	host.panel.sync_document(host.service.document, "ball_0_0")
	panel.fields["motor_enabled"].button_pressed = true
	panel._apply()
	var converted: Dictionary = host.service.document["objects"][Document.object_index(host.service.document, "ball_0_0")]
	checks["existing_object_can_enable_motor"] = converted["motion"]["enabled"] and converted["physics"]["mode"] == "static" and converted["mechanisms"].is_empty() and converted["shape"] == doc["objects"][6]["shape"]
	host.service.execute({"op": "history.undo"})
	host.service.execute({"op": "object.select", "args": {"id": "device_swing"}})
	host.panel.sync_document(host.service.document, "device_swing")
	await process_frame
	checks["numbers_keep_88px"] = panel.fields["motor_amplitude_degrees"].custom_minimum_size.x == 88
	panel.fields["motor_amplitude_degrees"].get_line_edit().text = "35"
	host.panel.sync_document(host.service.document, "device_rotor")
	host.panel.sync_document(host.service.document, "device_swing")
	checks["draft_survives_selection"] = panel.fields["motor_amplitude_degrees"].value == 35
	host.panel.apply_button.pressed.emit()
	var index := Document.object_index(host.service.document, "device_swing")
	checks["apply_run_commits_motor_draft"] = host.service.document["objects"][index]["motion"]["amplitude_degrees"] == 35 and host.session.mode == "playing"
	host.service.execute({"op": "simulation.pause"})
	var saved: Dictionary = host.service.execute({"op": "scene.save", "args": {"path": "res://outputs/devices/saved_scene.json"}})
	checks["scene_roundtrip_keeps_component"] = saved["ok"] and Document.load_file("res://outputs/devices/saved_scene.json")["document"]["objects"][index]["motion"]["amplitude_degrees"] == 35
	host.panel.update_runtime(host.session.get_info())
	await _shot("01_motor_inspector")
	host.service.execute({"op": "scene.load", "args": {"path": "res://config/workbench_devices.json"}})
	host.service.execute({"op": "object.select", "args": {"id": "device_swing"}})
	host.panel.sync_document(host.service.document, "device_swing")
	host.session.start_recording()
	var world: Node = host.session.stage.world
	checks["all_three_are_native_driven_colliders"] = world.records["device_rotor"]["body"] is AnimatableBody2D and world.records["device_slider"]["body"] is AnimatableBody2D and world.records["device_swing"]["body"] is AnimatableBody2D
	while host.session.time < 8.0: await process_frame
	host.session.stop_recording()
	var frozen: Array = world.capture_state()
	var clock: float = world.devices.elapsed
	for frame in 12: await process_frame
	checks["pause_freezes_all_bodies_and_motor_clock"] = frozen == world.capture_state() and clock == world.devices.elapsed
	var contacts: Dictionary = {}
	for event in host.session.events:
		if event.get("type", "") == "contact" and event.get("phase", "") == "enter":
			for key in ["id", "other_id"]:
				if str(event.get(key, "")).begins_with("device_"): contacts[event[key]] = true
	checks["all_three_make_native_ball_contacts"] = contacts.size() == 3
	var data: Dictionary = host.session.take.get_data()
	var pivot_error := 0.0
	for frame in data["frames"]:
		var pose := _state(frame["states"], "device_swing")
		pivot_error = maxf(pivot_error, Vector2(pose["position"][0], pose["position"][1]).distance_to(Vector2(360, 1155)))
	checks["swing_pivot_remains_fixed"] = pivot_error < 0.01
	checks["take_saves_real_motor_motion"] = host.session.take.save("res://outputs/devices/take.json") == OK and _state(data["frames"][0]["states"], "device_rotor") != _state(data["frames"][120]["states"], "device_rotor")
	var take = preload("res://src/takes/take_store.gd").new()
	checks["take_loads_with_motor_definitions"] = take.load_take("res://outputs/devices/take.json") == OK
	host.session.seek(2.0)
	var replay: Array = host.session.stage.world.capture_state()
	host.session.seek(5.0)
	host.session.seek(2.0)
	checks["seek_roundtrip_replays_identical_motor_poses"] = replay == host.session.stage.world.capture_state() and host.session.stage.world.records["device_rotor"].get("body") == null
	host.panel.update_runtime(host.session.get_info())
	await _shot("02_replay")
	var old_hash := Document.simulation_hash(doc)
	bad = doc.duplicate(true)
	bad["objects"][5]["motion"]["speed_degrees"] += 10
	checks["motor_change_invalidates_old_take"] = old_hash != Document.simulation_hash(bad)
	# Existing split-hitstop behavior must freeze motor transforms as well as dynamic balls.
	var split_doc: Dictionary = Document.load_file("res://config/workbench_2d.json")["document"]
	for rule in split_doc["mechanisms"]:
		if rule.get("type", "") == "hit_stop_on_event": rule["enabled"] = true
	split_doc["objects"][0]["transform"]["position"] = [220, 1060]
	split_doc["objects"][0]["physics"]["velocity"] = [0, 180]
	var motor := Document.new_object(split_doc, "rotor", "hold_motor")
	motor["transform"]["position"] = [360, 250]
	split_doc["objects"].append(motor)
	host.session.load_document(split_doc)
	host.session.start_recording()
	while host.session.time < 3.2: await process_frame
	host.session.stop_recording()
	var hold_frames := 0
	var hold_ok := true
	var previous: Dictionary = {}
	for frame in host.session.take.get_data()["frames"]:
		if not previous.is_empty() and frame["sim_time"] == previous["sim_time"]:
			hold_frames += 1
			hold_ok = hold_ok and _state(frame["states"], "hold_motor") == _state(previous["states"], "hold_motor")
		previous = frame
	checks["split_hitstop_freezes_motor_in_recorded_frames"] = hold_frames > 0 and hold_ok and host.session.stage.world.runner.splits > 0
	# A rising platform must physically lift a real ball; transform animation alone cannot pass.
	var lift_doc := doc.duplicate(true)
	var lift := Document.new_object(lift_doc, "slider", "lift")
	lift["transform"]["position"] = [360, 600]
	lift["shape"]["size"] = [300, 20]
	lift["motion"].merge({"direction_degrees": -90, "travel": 200, "period_seconds": 4.0}, true)
	var ball := Document.new_object(lift_doc, "ball", "lift_ball")
	ball["mechanisms"] = []
	ball["transform"]["position"] = [360, 550]
	ball["physics"]["material"]["restitution"] = 0
	lift_doc["objects"] = [lift, ball]
	host.session.load_document(lift_doc)
	host.session.play()
	while host.session.time < 0.9: await process_frame
	host.session.pause()
	checks["platform_physically_lifts_ball"] = host.session.stage.world.object_position("lift_ball")[1] < 530 and host.session.stage.world.runner.contacts > 0
	# The moving collider uses the same real-contact split route as a stationary wall.
	lift_doc["mechanisms"] = split_doc["mechanisms"].duplicate(true)
	ball["mechanisms"] = ["split_ball"]
	host.session.load_document(lift_doc)
	host.session.play()
	while host.session.time < 1.0: await process_frame
	host.session.pause()
	checks["motor_contact_triggers_existing_split_rules"] = host.session.stage.world.runner.splits > 0
	# Off-centre rotation must retain the world-space hinge, including a rotated initial pose.
	lift["motion"] = Device.defaults("rotor")
	lift["motion"]["pivot"] = [-80, 0]
	lift["transform"]["rotation_degrees"] = 25
	lift_doc["objects"] = [lift]
	host.session.load_document(lift_doc)
	host.session.play()
	while host.session.time < 0.7: await process_frame
	host.session.pause()
	var body: Node2D = host.session.stage.world.records["lift"]["body"]
	var hinge := body.position + Vector2(-80, 0).rotated(body.rotation)
	checks["offcentre_hinge_is_fixed_in_world"] = hinge.distance_to(Vector2(360,600) + Vector2(-80,0).rotated(deg_to_rad(25))) < 0.01
	var before_step: float = host.session.stage.world.devices.elapsed
	host.session.step_once()
	for frame in 8: await process_frame
	var one_step: float = host.session.stage.world.devices.elapsed
	for frame in 8: await process_frame
	checks["single_step_drives_motor_once"] = is_equal_approx(one_step - before_step, 1.0 / 120.0) and one_step == host.session.stage.world.devices.elapsed
	# Incompatible dimensions are rejected by data/command validation as well as the UI.
	host.service.execute({"op": "scene.new", "args": {"name": "3d", "blank": true}})
	checks["3d_entry_disabled"] = panel.device_menu.disabled
	var result: Dictionary = host.service.execute({"op": "object.add", "args": {"kind": "rotor"}})
	checks["3d_command_rejected"] = not result["ok"]
	var passed := true
	for value in checks.values(): passed = passed and bool(value)
	var report := {"passed": passed, "checks": checks, "native_contacts": contacts, "pivot_error": pivot_error}
	FileAccess.open("res://outputs/devices_validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("DEVICES_VALIDATION " + JSON.stringify(report))
	host.queue_free()
	await process_frame
	quit(0 if passed else 1)
