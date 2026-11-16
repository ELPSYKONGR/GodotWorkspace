extends SceneTree
## Validate the real inspector, native world, saved settings and shared replay presentation.
const Document = preload("res://src/document/scene_document.gd")
var checks: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

## Find the visible property/action rather than issuing an alternate UI implementation.
func _find(node: Node, caption: String) -> Node:
	if node is Button and node.text == caption: return node
	if node is BoxContainer and node.get_child_count() == 2 and node.get_child(0) is Label and node.get_child(0).text == caption: return node.get_child(1)
	for child in node.get_children():
		var found := _find(child, caption)
		if found != null: return found
	return null

func _run() -> void:
	var loaded := Document.load_file("res://config/workbench_neon.json")
	checks["demo_schema_valid"] = loaded["ok"]
	var doc: Dictionary = loaded["document"]
	var malformed := doc.duplicate(true)
	malformed["presentation"]["render"]["neon"] = "invalid"
	checks["invalid_structure_rejected"] = not Document.validate(malformed).is_empty()
	malformed = doc.duplicate(true)
	malformed["presentation"]["render"]["neon"]["glow_width"] = INF
	checks["non_finite_width_rejected"] = not Document.validate(malformed).is_empty()
	malformed["presentation"]["render"]["neon"]["glow_width"] = 65
	checks["unbounded_width_rejected"] = not Document.validate(malformed).is_empty()
	checks["presentation_does_not_change_physics_hash"] = Document.simulation_hash(malformed) == Document.simulation_hash(doc)
	var host = load("res://src/ui/workbench.gd").new()
	root.add_child(host)
	await process_frame
	var bar = host.panel.scene_bar
	bar.type_choice.select(4)
	bar.new_dialog.confirmed.emit()
	checks["unified_new_scene_opens_neon"] = host.service.document["metadata"]["title"].contains("荧光演示") and host.service.document["objects"].size() == doc["objects"].size()
	host.service.execute({"op": "simulation.play"})
	var world = host.session.stage.world
	var body: Node = world.records["ball_0_000"]["body"]
	var position: Vector2 = body.position
	var hash_before := Document.simulation_hash(host.service.document)
	var page: Node = host.panel.pages["渲染"]
	(_find(page, "光晕范围 / px") as SpinBox).get_line_edit().text = "30"
	(_find(page, "光晕强度") as SpinBox).get_line_edit().text = "1.5"
	(_find(page, "高光大小") as SpinBox).get_line_edit().text = "0.4"
	(_find(page, "高光强度") as SpinBox).get_line_edit().text = "1.8"
	(_find(page, "应用荧光") as Button).pressed.emit()
	print("NEON_SETTINGS ", JSON.stringify(world.neon.settings))
	checks["inspector_commits_typed_glow_values"] = world.neon.settings["glow_width"] == 30 and world.neon.settings["glow_strength"] == 1.5
	checks["uniforms_apply_to_both_batches"] = world.neon.balls.material.get_shader_parameter("glow_width") == 30 and world.neon.walls.material.get_shader_parameter("glow_width") == 30 and is_equal_approx(world.neon.balls.material.get_shader_parameter("highlight_strength"), 1.8)
	checks["visual_edit_preserves_body_pose_and_simulation"] = body == world.records["ball_0_000"]["body"] and body.position == position and host.session.mode == "playing" and hash_before == Document.simulation_hash(host.service.document)
	var settings: Dictionary = host.service.document["presentation"]["render"]["neon"].duplicate(true)
	host.service.execute({"op": "take.record"})
	for frame in 40: await physics_frame
	host.service.execute({"op": "take.stop", "args": {"path": "res://outputs/neon_validation.take.json"}})
	host.service.execute({"op": "scene.patch", "args": {"changes": {"presentation.render.neon.enabled": false}}})
	checks["disabling_neon_keeps_take_valid"] = not host.session.get_info()["take_stale"] and not host.session.stage.world.neon.enabled
	host.service.execute({"op": "scene.patch", "args": {"changes": {"presentation.render.neon": settings}}})
	host.service.execute({"op": "take.seek", "args": {"time": 0.1}})
	world = host.session.stage.world
	checks["replay_reuses_neon_with_no_native_bodies"] = world.neon.enabled and world.playback and not world.records["ball_0_000"].has("body")
	var circles: Array = []
	var walls: Array = []
	for id in world.records:
		var spec: Dictionary = world.records[id]["spec"]
		if spec["shape"]["primitive"] == "circle": circles.append({"position": world._position(id), "size": spec["shape"]["radius"], "color": world._color(spec)})
		else: walls.append({"position": world._position(id), "half_size": world._size(spec) / 2, "rotation": world._rotation(id), "color": world._color(spec)})
	world.neon.present(circles, walls)
	checks["all_balls_and_walls_use_two_multimeshes"] = world.neon.balls.multimesh.visible_instance_count == 128 and world.neon.walls.multimesh.visible_instance_count == walls.size()
	var expected: Vector2 = world._position("ball_0_000")
	host.service.execute({"op": "take.seek", "args": {"time": 0.2}})
	host.service.execute({"op": "take.seek", "args": {"time": 0.1}})
	checks["rewind_keeps_recorded_positions"] = world._position("ball_0_000").is_equal_approx(expected)
	var result: Dictionary = host.service.execute({"op": "scene.save", "args": {"path": "res://outputs/neon_saved.json"}})
	checks["saved_scene_keeps_neon_settings"] = result["ok"] and Document.load_file("res://outputs/neon_saved.json")["document"]["presentation"]["render"]["neon"] == settings
	checks["passed"] = not checks.values().has(false)
	var file := FileAccess.open("res://outputs/neon_validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(checks, "\t"))
	print("NEON_VALIDATION ", JSON.stringify(checks))
	for child in root.get_children(): child.queue_free()
	var deadline := Time.get_ticks_msec() + 100
	while Time.get_ticks_msec() < deadline: await process_frame
	quit(0 if checks["passed"] else 1)
