extends SceneTree
## Reproduce a one-screen world locking a real falling lineage, then fix it through the actual UI.
const Document = preload("res://src/document/scene_document.gd")
var checks: Dictionary = {}
var capture := false

## Defer until the scene tree is ready to host the real workbench.
func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()

## Resolve real user-facing controls rather than duplicating the camera command.
func _find(node: Node, caption: String) -> Node:
	if node is Button and node.text == caption: return node
	if node is BoxContainer and node.get_child_count() == 2 and node.get_child(0) is Label and node.get_child(0).text == caption: return node.get_child(1)
	for child in node.get_children():
		var found := _find(child, caption)
		if found != null: return found
	return null

## Capture GPU output only when requested; pause advances neither bodies nor camera.
func _shot(name: String) -> void:
	if not capture: return
	Input.warp_mouse(Vector2(2, 2))
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/camera_follow/" + name + ".png")

## Use native physics in an isolated project, including real descendants and recorded replay.
func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://outputs/camera_follow")
	var source := "res://config/workbench_2d.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--source="): source = arg.trim_prefix("--source=")
	var doc: Dictionary = Document.load_file(source)["document"]
	doc["objects"] = doc["objects"].filter(func(spec): return spec["id"] != "floor")
	doc["world"]["bounds_2d"] = [0, 0, 720, 1280]
	var camera: Dictionary = doc["presentation"]["render"].get("camera", {}).duplicate(true)
	camera.merge({"mode": "follow_y", "limit_world": true, "only_down": true, "on_split": "lowest_descendant"}, true)
	doc["presentation"]["render"]["camera"] = camera
	var path := "res://outputs/camera_follow/fixture.json"
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(doc))
	var host = load("res://src/ui/workbench.gd").new()
	root.add_child(host)
	await process_frame
	host.service.execute({"op": "scene.load", "args": {"path": path}})
	host.panel.select_page("场景")
	var page: Node = host.panel.pages["场景"]
	var action := _find(page, "允许越界跟随") as Button
	checks["short_world_explains_and_offers_fix"] = action != null and action.is_visible_in_tree()
	host.panel.play_button.pressed.emit()
	while host.session.time < 2.0: await process_frame
	host.service.execute({"op": "simulation.pause"})
	var before: Dictionary = host.session.get_info()
	checks["reproduces_target_detected_but_camera_clamped"] = not before["camera"]["target"].is_empty() and before["camera"]["top"][1] == 0 and host.session.stage.world.object_position(str(before["camera"]["target"]))[1] > 1280
	checks["runtime_reports_actual_camera_block"] = before["camera"].get("blocked_reason", "") == "world_too_short"
	host.panel.update_runtime(before)
	checks["blocked_camera_is_visible_outside_debug"] = host.panel.runtime_label.text.contains("镜头受限")
	await _shot("01_blocked")
	var stage: Node = host.session.stage
	var time: float = host.session.time
	var physics_hash := Document.simulation_hash(host.service.document)
	if action != null: action.pressed.emit()
	else:
		(_find(page, "限制在世界范围") as CheckBox).button_pressed = false
		(_find(page, "应用世界与镜头") as Button).pressed.emit()
	checks["fix_preserves_world_physics_and_paused_time"] = host.session.stage == stage and host.session.time == time and Document.simulation_hash(host.service.document) == physics_hash and host.session.mode == "paused"
	host.panel.play_button.pressed.emit()
	while host.session.time < 3.0: await process_frame
	host.service.execute({"op": "simulation.pause"})
	var after: Dictionary = host.session.get_info()
	checks["unbounded_follow_moves_past_first_screen"] = after["camera"]["top"][1] > 1280
	var wall: Dictionary = host.service.document["objects"][Document.object_index(host.service.document, "wall_left")]
	checks["follow_does_not_translate_physics_world"] = stage.world.records["wall_left"]["body"].position.y == wall["transform"]["position"][1]
	checks["actual_child_lineage_remains_target"] = str(after["camera"]["target"]).begins_with("ball_A_child")
	var resolved := _find(host.panel.pages["场景"], "允许越界跟随") as Button
	checks["fix_clears_boundary_warning"] = after["camera"].get("blocked_reason", "") == "" and resolved != null and not resolved.is_visible_in_tree()
	host.panel.update_runtime(after)
	await _shot("02_following")
	host.service.execute({"op": "take.record"})
	while host.session.time < 3.0: await process_frame
	host.service.execute({"op": "take.stop"})
	var live_top: Vector2 = host.session.stage.view_top
	host.session.seek(host.session.take.get_duration())
	checks["recorded_replay_matches_live_follow"] = host.session.stage.view_top.distance_to(live_top) < 0.001
	checks["passed"] = not checks.values().has(false)
	var report := {"passed": checks["passed"], "checks": checks, "source": source, "before": before["camera"], "after": after["camera"]}
	FileAccess.open("res://outputs/camera_follow_validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("CAMERA_FOLLOW ", JSON.stringify(report))
	quit(0 if checks["passed"] else 1)
