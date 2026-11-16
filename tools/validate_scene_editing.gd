extends SceneTree
## Real workbench transactions: existing contours, new drawing, navigation, style isolation and persistence.
const Document = preload("res://src/document/scene_document.gd")
const Geometry = preload("res://src/document/shape_geometry.gd")
var checks: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

## Locate real controls by their captions; no second implementation of the edit pipeline.
func _find(node: Node, caption: String) -> Node:
	if node is Button and node.text == caption: return node
	if node is BoxContainer and node.get_child_count() == 2 and node.get_child(0) is Label and node.get_child(0).text == caption: return node.get_child(1)
	for child in node.get_children():
		var found := _find(child, caption)
		if found != null: return found
	return null

## Select a real initial object just as a viewport click would do.
func _select(host: Node, id: String) -> void:
	host.service.execute({"op": "object.select", "args": {"id": id}})
	host.panel.sync_document(host.service.document, id)

## Exercise complete native transactions and actual bodies in a task-isolated project.
func _run() -> void:
	var host = load("res://src/ui/workbench.gd").new()
	root.add_child(host)
	await process_frame
	host.service.execute({"op": "scene.load", "args": {"path": "res://config/workbench_long.json"}})
	var original: Dictionary = host.service.document.duplicate(true)
	_select(host, "outline_U")
	(_find(host.panel.object_panel, "编辑所选轮廓") as Button).pressed.emit()
	var editor: Window = host.panel.object_panel.shape_editor
	checks["existing_outline_opens_native_draft"] = editor.visible and editor.source["id"] == "outline_U"
	var shape := {"primitive": "polygon", "points": [[-120,-80],[120,-80],[120,-32],[-64,-32],[-64,96],[-120,96]]}
	editor.canvas.configure(shape)
	(_find(editor, "应用轮廓") as Button).pressed.emit()
	var index := Document.object_index(host.service.document, "outline_U")
	var changed: Dictionary = host.service.document["objects"][index]
	checks["geometry_replaces_same_id_without_extra_objects"] = changed["shape"] == shape and host.service.document["objects"].size() == original["objects"].size() and not editor.visible
	var prior: Dictionary = original["objects"][index]
	checks["geometry_retains_transform_material_and_physics"] = changed["transform"] == prior["transform"] and changed["appearance"] == prior["appearance"] and changed["physics"] == prior["physics"]
	var others_ok := true
	for i in original["objects"].size():
		if i != index: others_ok = others_ok and original["objects"][i] == host.service.document["objects"][i]
	checks["geometry_preserves_all_other_objects"] = others_ok
	var world = host.session.stage.world
	host.service.execute({"op": "simulation.play"})
	world = host.session.stage.world
	checks["concave_shape_compiles_multiple_fixtures_on_one_body"] = world.records["outline_U"]["body"].get_child_count() >= 2 and world.records["outline_U"]["body"] is StaticBody2D
	checks["static_wall_material_is_consumed"] = is_equal_approx(world.records["wall_left"]["body"].physics_material_override.bounce, 0.05) and is_equal_approx(world.records["wall_left"]["body"].physics_material_override.friction, 0.1)
	host.service.execute({"op": "simulation.edit"})
	host.service.execute({"op": "history.undo"})
	checks["geometry_has_one_step_undo"] = host.service.document["objects"] == original["objects"]
	host.service.execute({"op": "history.redo"})
	checks["geometry_redo_restores_outline"] = host.service.document["objects"][index]["shape"] == shape
	_select(host, "outline_U")
	host.panel.object_panel._open_shape(false)
	var before: Array = host.service.document["objects"].duplicate(true)
	editor.canvas.configure({"primitive": "polygon", "points": [[0,0],[80,80],[0,80],[80,0]]})
	editor.submit(false)
	checks["invalid_geometry_cannot_mutate_scene"] = host.service.document["objects"] == before and editor.visible and editor.status.text.contains("自相交")
	(_find(editor, "放弃草稿") as Button).pressed.emit()
	checks["cancel_keeps_original_object_exactly"] = host.service.document["objects"] == before and not editor.visible
	host.panel.object_panel._open_shape(false)
	host.service.execute({"op": "object.update", "args": {"id": "outline_U", "changes": {"name": "新的名称"}}})
	editor.submit(false)
	checks["stale_draft_conflict_preserves_newer_scene"] = editor.visible and editor.status.text.contains("场景已修改") and host.service.document["objects"][index]["name"] == "新的名称"
	editor.hide()
	var result: Dictionary = host.service.execute({"op": "camera.pan", "args": {"position": [0, 7800]}})
	checks["minimap_navigation_uses_render_only_transform"] = result["ok"] and host.session.stage.view_top == Vector2(0,7800) and host.session.stage.world.records["outline_U"]["position"] == Vector2(360,8500)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true
	host._viewport_input(click, Vector2(280,700))
	checks["viewport_selection_inverts_camera_offset"] = host.selected_id == "outline_U"
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	host._viewport_input(motion, Vector2(312,732))
	click.pressed = false; host._viewport_input(click, Vector2(312,732))
	checks["drag_in_long_world_commits_world_coordinates"] = host.service.document["objects"][index]["transform"]["position"] == [392.0,8532.0]
	host.panel.object_panel.view_top = host.session.stage.view_top
	host.panel.object_panel._open_shape(true)
	editor.canvas.tool = "polygon"
	for point in [Vector2(-80,-64),Vector2(80,-64),Vector2(80,64),Vector2(-80,64)]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT; event.pressed = true; event.position = editor.canvas.size / 2 + point * editor.canvas.zoom
		editor.canvas._gui_input(event)
	editor.canvas.close_polygon()
	editor.submit(false)
	checks["drawn_new_object_enters_current_scene"] = host.service.document["objects"].size() == before.size() + 1 and host.service.document["objects"][-1]["shape"]["primitive"] == "polygon" and host.service.document["objects"][-1]["shape"]["points"].size() == 4
	host.service.execute({"op": "simulation.play"})
	_select(host, "ball_A")
	var body: Node = host.session.stage.world.records["ball_A"]["body"]
	var hash_before := Document.simulation_hash(host.service.document)
	var global: Dictionary = host.service.document["presentation"].duplicate(true)
	var other: Dictionary = host.service.document["objects"][1].duplicate(true)
	(_find(host.panel.object_panel, "物体材质来源") as OptionButton).select(1)
	(_find(host.panel.object_panel, "物体光晕范围") as SpinBox).get_line_edit().text = "35"
	(_find(host.panel.object_panel, "应用物体材质（保留运动）") as Button).pressed.emit()
	checks["local_material_changes_only_selected_object"] = host.service.document["presentation"] == global and host.service.document["objects"][1] == other and host.service.document["objects"][0]["appearance"]["material"]["neon"]["glow_width"] == 35
	checks["local_material_preserves_native_body_and_running_mode"] = body == host.session.stage.world.records["ball_A"]["body"] and host.session.mode == "playing" and hash_before == Document.simulation_hash(host.service.document)
	(_find(host.panel.object_panel, "物体特效来源") as OptionButton).select(1)
	(_find(host.panel.object_panel, "物体粒子数量") as SpinBox).get_line_edit().text = "4"
	(_find(host.panel.object_panel, "应用物体特效（保留运动）") as Button).pressed.emit()
	checks["local_effects_keep_global_and_physical_state"] = host.service.document["presentation"] == global and host.service.document["objects"][0]["appearance"]["effects"]["count"] == 4 and hash_before == Document.simulation_hash(host.service.document) and body == host.session.stage.world.records["ball_A"]["body"]
	await process_frame
	var numeric: SpinBox = host.panel.object_panel.fields["mass"]
	checks["numeric_controls_are_fixed_88_pixels"] = is_equal_approx(numeric.size.x, 88)
	checks["numeric_controls_share_wrapping_row"] = numeric.get_parent().get_parent() is HFlowContainer and numeric.get_parent().get_parent().get_child_count() >= 3
	host.service.execute({"op": "simulation.edit"})
	result = host.service.execute({"op": "scene.save", "args": {"path": "res://outputs/editing_saved.json"}})
	var saved: Dictionary = Document.load_file("res://outputs/editing_saved.json")
	var normalized: Dictionary = JSON.parse_string(JSON.stringify(host.service.document))
	checks["save_reload_preserves_geometry_camera_and_local_visuals"] = result["ok"] and saved["ok"] and saved["document"]["objects"] == normalized["objects"] and saved["document"]["presentation"]["render"]["camera"] == normalized["presentation"]["render"]["camera"]
	_select(host, "ball_A")
	host.panel.object_panel._open_shape(false)
	editor.canvas.configure({"primitive":"rectangle","size":[48,64]})
	editor.submit(false)
	checks["noncircle_retains_draft_until_split_component_removed"] = editor.visible and editor.status.text.contains("分裂组件") and host.service.document["objects"][0]["shape"]["primitive"] == "circle"
	editor.remove_split.button_pressed = true
	editor.submit(false)
	checks["explicit_component_removal_allows_same_id_shape_change"] = not editor.visible and host.service.document["objects"][0]["id"] == "ball_A" and host.service.document["objects"][0]["shape"]["primitive"] == "rectangle" and "split_ball" not in host.service.document["objects"][0]["mechanisms"]
	result = host.service.execute({"op":"scene.new","args":{"name":"long","blank":false}})
	checks["long_world_available_through_native_scene_creation"] = result["ok"] and host.service.document["world"]["bounds_2d"][3] == 20000 and host.session.stage.world.records.has("outline_U")
	result = host.service.execute({"op":"scene.new","args":{"name":"long","blank":true}})
	checks["blank_long_world_clears_target_and_objects"] = result["ok"] and host.service.document["objects"].is_empty() and host.service.document["presentation"]["render"]["camera"]["target_root"] == ""
	checks["passed"] = not checks.values().has(false)
	FileAccess.open("res://outputs/scene_editing_validation.json", FileAccess.WRITE).store_string(JSON.stringify(checks, "\t"))
	print("SCENE_EDITING ", JSON.stringify(checks))
	host.queue_free()
	await process_frame
	quit(0 if checks["passed"] else 1)
