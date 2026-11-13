extends SceneTree
## Exercise actual inspector controls without physics or rendering assumptions.
var commands: Array = []
var mapped := Vector2(-1, -1)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/examples/scene_v2.example.json"))
	var ui = load("res://src/ui/workbench_ui.gd").new()
	ui.setup(doc, GradientTexture2D.new())
	ui.command_requested.connect(func(op: String, args: Dictionary): commands.append({"op": op, "args": args}))
	ui.viewport_input.connect(func(_event: InputEvent, point: Vector2): mapped = point)
	root.add_child(ui)
	await process_frame
	ui.sync_document(doc, "ball_A")
	await process_frame
	var buttons: Array[Button] = []
	_buttons(ui, buttons)
	for caption in ["二维", "正交三维", "透视三维", "应用物体参数并重置", "应用机制并重新模拟", "应用音效", "应用粒子与拖尾", "应用渲染与文字", "提交视频生产任务"]:
		for button in buttons:
			if button.text == caption:
				button.pressed.emit()
				break
	var unchanged_count := commands.size()
	ui.update_runtime({"mode": "编辑", "time": 1.2, "sim_time": 1.1, "duration": 3.0, "active": 6, "events": []})
	var click := InputEventMouseButton.new()
	click.position = ui.get_preview_rect().get_center()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	ui._preview_input(click)
	var result := {
		"nine_control_commands": commands.size() == 9,
		"preset_buttons_capture_distinct_values": commands[0]["args"]["name"] == "2d" and commands[1]["args"]["name"] == "3d" and commands[2]["args"]["name"] == "perspective",
		"unchanged_numeric_values_preserved": commands[3]["args"]["changes"]["physics.mass"] == 1.0 and commands[3]["args"]["changes"]["shape.radius"] == 18.0 and is_equal_approx(commands[6]["args"]["changes"]["presentation.effects"]["lifetime"], 0.35),
		"runtime_slider_update_does_not_issue_seek": commands.size() == unchanged_count,
		"letterbox_center_maps_to_logical_center": mapped.is_equal_approx(Vector2(360, 640))
	}
	var object_changes: Dictionary = commands[3]["args"]["changes"]
	result["collision_mode_layers_ccd"] = object_changes["physics.mode"] == "dynamic" and object_changes["physics.collision_layer"] == 1 and object_changes["physics.collision_mask"] == 3 and object_changes["physics.ccd"]
	result["local_wav_field_preserved"] = commands[5]["args"]["changes"]["presentation.audio"]["wav_path"] == ""
	var render_changes: Dictionary = commands[7]["args"]["changes"]
	var target: Array = render_changes["presentation.render.camera.target"]
	result["camera_and_lighting_fields"] = render_changes["presentation.render.camera.position"] == [13.0, 15.0, 20.0] and target[0] == 0 and is_equal_approx(float(target[1]), 2.3) and target[2] == 0 and is_equal_approx(float(render_changes["presentation.render.camera.fov"]), 46) and is_equal_approx(float(render_changes["presentation.render.light_energy"]), 1.5)
	ui.object_panel.fields["mode"].select(2)
	ui.object_panel._apply()
	result["sensor_mode_command"] = commands.back()["args"]["changes"]["physics.mode"] == "sensor"
	ui.object_panel.fields["locked"].button_pressed = true
	for button in buttons:
		if button.text == "应用锁定状态": button.pressed.emit(); break
	result["lock_is_independent_edit"] = commands.back()["args"]["changes"] == {"editor.locked": true}
	var error_info := {"last_message": "测试错误", "last_message_is_error": true, "audio": {"error": "test_missing_audio"}}
	ui.update_runtime(error_info)
	ui.update_runtime(error_info)
	result["runtime_error_keeps_error_color"] = ui.message_label.get_theme_color("font_color") == Color("ff9d9d")
	result["audio_error_remains_visible"] = "test_missing_audio" in ui.debug_text.text
	# The same object inspector accepts three-dimensional arrays and shape fields.
	doc["world"]["dimension"] = "3d"
	doc["objects"] = [{"id": "sphere", "shape": {"primitive": "sphere", "radius": 0.44}, "transform": {"position": [0, 2, 0], "rotation_degrees": [0, 0, 0]}, "physics": {"velocity": [0, 0, 0]}, "mechanisms": []}]
	ui.sync_document(doc, "sphere")
	ui.object_panel._apply()
	result["three_dimensional_fields"] = commands.back()["args"]["changes"]["transform.position"].size() == 3 and is_equal_approx(commands.back()["args"]["changes"]["shape.radius"], 0.44)
	result["passed"] = not result.values().has(false)
	DirAccess.make_dir_recursive_absolute("res://outputs")
	var file := FileAccess.open("res://outputs/ui_validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	print("UI_VALIDATION " + JSON.stringify(result))
	quit(0 if result["passed"] else 1)


func _buttons(node: Node, result: Array[Button]) -> void:
	if node is Button: result.append(node)
	for child in node.get_children(): _buttons(child, result)
