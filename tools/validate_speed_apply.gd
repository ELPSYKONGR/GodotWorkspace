extends SceneTree
## Real native contacts and real inspector drafts verify speed filtering and atomic Apply + Run.
const Document = preload("res://src/document/scene_document.gd")
const Session = preload("res://src/runtime/scene_session.gd")
var checks: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _control(node: Node, caption: String) -> Node:
	if node is Button and node.text == caption: return node
	if node is BoxContainer and node.get_child_count() == 2 and node.get_child(0) is Label and node.get_child(0).text == caption: return node.get_child(1)
	for child in node.get_children():
		var found := _control(child, caption)
		if found != null: return found
	return null

## Low restitution distinguishes incoming-speed filtering from testing the slow rebound.
func _native(three: bool, speed: float, threshold: float, moving_target: bool = false) -> Dictionary:
	var doc: Dictionary = Document.load_file("res://config/workbench_3d.json" if three else "res://config/workbench_2d.json")["document"]
	doc["world"].merge({"gravity": [0, 0, 0] if three else [0, 0], "physics_hz": 120, "max_dynamic_bodies": 8}, true)
	var ball: Dictionary = Document.new_object(doc, "ball", "test_ball")
	ball["shape"]["radius"] = 0.15 if three else 10
	ball["transform"]["position"] = [0, 1, 0] if three else [360, 500]
	ball["physics"].merge({"velocity": [0, -speed, 0] if three else [0, speed], "linear_damp": 0, "linear_damp_replace": true, "material": {"restitution": 0.05, "friction": 0}}, true)
	ball["mechanisms"] = ["speed_split"]
	var floor: Dictionary = Document.new_object(doc, "wall", "test_floor")
	floor["tags"] = ["boundary"]
	floor["physics"].merge({"mode": "static", "material": {"restitution": 0.05, "friction": 0}}, true)
	floor["shape"] = {"primitive": "box", "size": [8, 0.2, 8]} if three else {"primitive": "rectangle", "size": [600, 10]}
	floor["transform"]["position"] = [0, 0, 0] if three else [360, 540]
	if moving_target:
		ball["transform"]["position"] = [360, 500]
		ball["physics"]["velocity"] = [speed, 0]
		floor["shape"] = {"primitive": "circle", "radius": 10}
		floor["transform"]["position"] = [400, 500]
		floor["physics"].merge({"mode": "dynamic", "velocity": [-speed, 0], "linear_damp": 0, "linear_damp_replace": true, "collision_layer": 1, "collision_mask": 3}, true)
	doc["objects"] = [ball, floor]
	doc["mechanisms"] = [{"id": "speed_split", "type": "split_on_contact", "enabled": true, "conditions": {"other_tags_any": ["boundary"], "newborn_guard_seconds": 0, "minimum_collision_speed": threshold}, "params": {"children_total": 2, "children_can_split": false, "ejection_speed": 0}}]
	doc["presentation"]["audio"]["enabled"] = false
	var session := Session.new()
	root.add_child(session)
	session.load_document(doc)
	session.play()
	while session.time < 2.0: await physics_frame
	var result: Dictionary = session.stage.world.get_report()
	result["speed_rejected"] = session.events.any(func(event): return event.get("reason", "") == "collision_speed_below_threshold")
	session.queue_free()
	await process_frame
	return result

func _run() -> void:
	for three in [false, true]:
		var prefix := "3d_" if three else "2d_"
		var low: Dictionary = await _native(three, 0.5 if three else 20, 2 if three else 100)
		var high: Dictionary = await _native(three, 8 if three else 400, 2 if three else 100)
		var disabled: Dictionary = await _native(three, 0.5 if three else 20, 0)
		checks[prefix + "low_speed_contact_does_not_split"] = low["splits"] == 0 and low["speed_rejected"]
		checks[prefix + "fast_incoming_slow_rebound_still_splits"] = high["splits"] > 0
		checks[prefix + "zero_threshold_keeps_legacy_behavior"] = disabled["splits"] > 0
	var opposing: Dictionary = await _native(false, 100, 150, true)
	checks["opposing_balls_use_relative_not_single_body_speed"] = opposing["splits"] > 0
	var host = load("res://src/ui/workbench.gd").new()
	root.add_child(host)
	await process_frame
	host.service.execute({"op": "object.select", "args": {"id": "ball_A"}})
	host.panel.sync_document(host.service.document, "ball_A")
	host.panel.object_panel.fields["mass"].get_line_edit().text = "2.5"
	(_control(host.panel.pages["机制"], "最低碰撞速度") as SpinBox).get_line_edit().text = "125"
	(_control(host.panel.pages["机制"], "每次子球总数") as SpinBox).get_line_edit().text = "4"
	(_control(host.panel.pages["渲染"], "标题") as LineEdit).text = "统一应用测试"
	(_control(host.panel.pages["渲染"], "光晕强度") as SpinBox).get_line_edit().text = "1.5"
	(_control(host.panel.pages["声音"], "音量（dB）") as SpinBox).get_line_edit().text = "-18"
	(_control(host.panel.pages["特效"], "单次粒子数") as SpinBox).get_line_edit().text = "7"
	(_control(host.panel.pages["生产"], "输出FPS") as OptionButton).select(1)
	(_control(host.panel.pages["生产"], "输出帧数") as SpinBox).get_line_edit().text = "180"
	(_control(host.panel.pages["特效"], "碰撞粒子") as CheckBox).button_pressed = true
	checks["unrelated_immediate_switch_keeps_typed_drafts"] = host.panel.object_panel.fields["mass"].get_line_edit().text.to_float() == 2.5 and (_control(host.panel.pages["机制"], "最低碰撞速度") as SpinBox).get_line_edit().text.to_float() == 125 and (_control(host.panel.pages["特效"], "单次粒子数") as SpinBox).get_line_edit().text.to_int() == 7
	var before: Dictionary = host.service.document.duplicate(true)
	var history_size: int = host.service.history.size()
	host.panel.apply_button.pressed.emit()
	var doc: Dictionary = host.service.document
	checks["all_panels_apply_in_one_transaction"] = doc["objects"][0]["physics"]["mass"] == 2.5 and doc["mechanisms"][0]["conditions"]["minimum_collision_speed"] == 125 and doc["mechanisms"][0]["params"]["children_total"] == 4 and doc["presentation"]["captions"][0]["text"] == "统一应用测试" and doc["presentation"]["render"]["neon"]["glow_strength"] == 1.5 and doc["presentation"]["audio"]["volume_db"] == -18 and doc["presentation"]["effects"]["count"] == 7
	checks["batch_runs_once_and_adds_one_undo"] = host.session.mode == "playing" and host.service.history.size() == history_size + 1 and host.panel.play_button.text == "暂停"
	checks["export_settings_apply_without_starting_a_job"] = doc["export_preset"]["fps"] == 60 and doc["export_preset"]["frames"] == 180 and host.jobs.status().get("state", "") == "idle"
	host.service.execute({"op": "history.undo"})
	var restored: Dictionary = host.service.document.duplicate(true)
	before.erase("revision")
	restored.erase("revision")
	checks["one_undo_restores_all_applied_fields"] = before == restored
	var signature := JSON.stringify(host.service.document)
	var failure: Dictionary = host.service.execute({"op": "scene.apply_run", "args": {"edits": [{"op": "scene.patch", "args": {"changes": {"presentation.render.background": "#123456"}}}, {"op": "scene.patch", "args": {"changes": {"world.physics_hz": 0}}}]}})
	checks["invalid_batch_commits_nothing"] = not failure["ok"] and signature == JSON.stringify(host.service.document)
	host.panel.object_panel.fields["mass"].get_line_edit().text = "3.1"
	host.panel.object_panel._select(Document.object_index(host.service.document, "ball_B"))
	host.panel.object_panel.fields["mass"].get_line_edit().text = "4.2"
	host.panel.apply_button.pressed.emit()
	checks["all_modified_objects_apply_after_selection_changes"] = is_equal_approx(host.service.document["objects"][0]["physics"]["mass"], 3.1) and is_equal_approx(host.service.document["objects"][1]["physics"]["mass"], 4.2)
	host.service.execute({"op": "scene.preset", "args": {"name": "neon"}})
	before = host.service.document.duplicate(true)
	host.panel.apply_button.pressed.emit()
	checks["untouched_panels_do_not_create_rules_or_titles"] = before == host.service.document and host.service.document["mechanisms"].is_empty() and host.session.mode == "playing"
	(_control(host.panel.pages["场景"], "重力 Y") as SpinBox).get_line_edit().text = "300"
	host.panel.apply_button.pressed.emit()
	checks["world_only_edit_does_not_enable_virtual_split_rules"] = host.service.document["mechanisms"].is_empty() and host.service.document["world"]["gravity"][1] == 300
	var service = load("res://src/commands/command_service.gd").new()
	service.initialize(Document.load_file("res://config/workbench_neon.json")["document"], Callable())
	var combined: Dictionary = service.execute({"op": "scene.apply_run", "args": {"edits": [{"op": "object.update", "args": {"id": "rail_0_-1", "changes": {"editor.locked": false}}}, {"op": "object.update", "args": {"id": "rail_0_-1", "changes": {"physics.mode": "dynamic"}}}, {"op": "scene.patch", "args": {"changes": {"world.max_dynamic_bodies": 129}}}]}})
	checks["combined_capacity_change_validated_on_final_document"] = combined["ok"] and service.document["world"]["max_dynamic_bodies"] == 129
	var invalid: Dictionary = Document.load_file("res://config/workbench_2d.json")["document"]
	invalid["mechanisms"][0]["conditions"]["minimum_collision_speed"] = -1
	checks["invalid_speed_threshold_rejected"] = not Document.validate(invalid).is_empty()
	invalid["mechanisms"][0]["conditions"]["minimum_collision_speed"] = NAN
	checks["nan_speed_threshold_rejected"] = not Document.validate(invalid).is_empty()
	var store = load("res://src/takes/take_store.gd").new()
	store.begin(host.service.document)
	var states: Array = host.session.stage.world.capture_state()
	store.append(0, 0, states, host.session.stage.world.definitions)
	store.append(1, 1, states, host.session.stage.world.definitions)
	store.add_event({"type": "contact", "time": 0.8})
	store.add_event({"type": "contact", "time": 0.2})
	store.save("res://outputs/unordered_events.take.json")
	var imported = load("res://src/takes/take_store.gd").new()
	checks["unordered_events_rejected_for_binary_replay"] = imported.load_take("res://outputs/unordered_events.take.json") == ERR_INVALID_DATA
	checks["passed"] = not checks.values().has(false)
	var output := FileAccess.open("res://outputs/speed_apply_validation.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(checks, "\t"))
	print("SPEED_APPLY ", JSON.stringify(checks))
	for child in root.get_children(): child.queue_free()
	var deadline := Time.get_ticks_msec() + 100
	while Time.get_ticks_msec() < deadline: await process_frame
	quit(0 if checks["passed"] else 1)
