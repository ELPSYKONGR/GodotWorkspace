extends SceneTree
## Exercise the redesigned native shell, disclosure, scope, keyboard and actual recording controls.
const F = preload("res://src/ui/form_helpers.gd")
var checks: Dictionary = {}
var capture := false
var host: Node
var evidence := "res://outputs/editor_layout"

## Captures are optional; the same real control checks also run headless in the normal suite.
func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()

## Locate a property or action by the label a user sees.
func _find(node: Node, caption: String) -> Node:
	if node is Button and node.text == caption: return node
	if node is BoxContainer and node.get_child_count() == 2 and node.get_child(0) is Label and node.get_child(0).text == caption: return node.get_child(1)
	for child in node.get_children():
		var found := _find(child, caption)
		if found != null: return found
	return null

## Mirror object selection without bypassing the domain command or draft handling.
func _select(id: String) -> void:
	host.service.execute({"op": "object.select", "args": {"id": id}})
	host.panel.sync_document(host.service.document, id)
	host.panel.select_page("物体")

## Allow container layout to settle before measuring or capturing controls.
func _settle() -> void:
	for frame in 4: await process_frame

## Save only real GPU output, never an HTML approximation of the native app.
func _shot(name: String) -> void:
	if capture: Input.warp_mouse(Vector2(2, 2))
	await _settle()
	if not capture: return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(evidence.path_join(name + ".png"))

## Test the information architecture and the workflows most likely to break during a visual rewrite.
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(evidence)
	host = load("res://src/ui/workbench.gd").new()
	root.add_child(host)
	await _settle()
	# Initial shader/font warm-up must not be presented as a steady-state FPS measurement.
	if capture: await create_timer(1.2).timeout
	var ui: Control = host.panel
	_select("ball_A")
	await _settle()
	checks["object_browser_stays_left_of_stage"] = ui.object_panel.listing.global_position.x < ui.preview.global_position.x
	checks["properties_stay_right_of_stage"] = ui.object_panel.form.global_position.x >= ui.preview.get_global_rect().end.x
	checks["six_visible_setting_entries"] = ui.navigation.size() == 6 and not ui.tabs.tabs_visible
	checks["stage_height_at_least_650_at_1440x900"] = ui.get_preview_rect().size.y >= 650
	checks["runtime_and_result_labels_have_visible_height"] = ui.runtime_label.size.y >= 20 and ui.message_label.size.y >= 20
	checks["object_browser_has_keyboard_focus_outline"] = ui.object_panel.listing.get_theme_stylebox("focus") is StyleBoxFlat and ui.object_panel.listing.get_theme_stylebox("focus").border_width_left >= 1
	checks["advanced_collision_collapsed"] = not ui.object_panel.fields["layer"].is_visible_in_tree()
	checks["native_select_translates_without_changing_data"] = ui.object_panel.fields["mode"].get_item_text(0) == "动态物体" and F.selected(ui.object_panel.fields["mode"]) == "dynamic"
	await _shot("01_objects")
	(_find(ui.object_panel, "物理与运动") as Button).button_pressed = true
	await _settle()
	checks["numeric_fields_are_88_pixels"] = is_equal_approx(ui.object_panel.fields["mass"].size.x, 88)
	checks["numbers_share_multiple_columns"] = ui.object_panel.fields["mass"].get_parent().get_parent().get_child_count() >= 3
	ui.object_panel.fields["mass"].get_line_edit().text = "2.75"
	ui.select_page("声音")
	ui.select_page("物体")
	checks["navigation_preserves_typed_draft"] = ui.object_panel.fields["mass"].get_line_edit().text == "2.75"
	_select("ball_B")
	_select("ball_A")
	checks["selection_restores_draft_and_disclosure"] = is_equal_approx(ui.object_panel.fields["mass"].get_line_edit().text.to_float(), 2.75) and ui.object_panel.fields["mass"].is_visible_in_tree()
	await _shot("02_physics")
	(_find(ui.object_panel, "独立材质") as Button).button_pressed = true
	var source := _find(ui.object_panel, "材质来源") as OptionButton
	var glow := _find(ui.object_panel, "光晕范围 / px") as SpinBox
	checks["inherited_material_hides_custom_controls"] = not glow.is_visible_in_tree()
	source.select(1); source.item_selected.emit(1)
	checks["custom_material_reveals_2d_controls"] = glow.is_visible_in_tree() and not (_find(ui.object_panel, "粗糙度") as SpinBox).is_visible_in_tree()
	(_find(ui.object_panel, "物理与运动") as Button).button_pressed = false
	await _shot("03_material")
	ui.select_page("渲染")
	checks["2d_hides_3d_settings"] = not (_find(ui.pages["渲染"], "三维相机") as Button).is_visible_in_tree()
	await _shot("04_picture")
	ui.select_page("机制")
	await _shot("05_mechanisms")
	ui.select_page("声音")
	await _shot("06_audio")
	ui.select_page("特效")
	await _shot("07_effects")
	ui.select_page("生产")
	ui.update_runtime(host.session.get_info())
	checks["export_prevents_missing_take"] = (_find(ui.pages["生产"], "开始导出") as Button).disabled
	checks["idle_cancel_is_disabled"] = (_find(ui.pages["生产"], "取消导出") as Button).disabled
	await _shot("08_export_empty")
	ui.record_button.pressed.emit()
	checks["single_record_button_becomes_stop"] = host.session.get_info()["recording"] and ui.record_button.text == "停止录制"
	for frame in 20: await physics_frame
	ui.record_button.pressed.emit()
	ui.update_runtime(host.session.get_info())
	checks["same_record_button_stops_and_retains_take"] = not host.session.get_info()["recording"] and ui.record_button.text == "录制" and host.session.take.get_duration() > 0
	checks["valid_take_enables_export"] = not (_find(ui.pages["生产"], "开始导出") as Button).disabled
	ui.select_page("场景")
	# A genuine preview click must reveal the object inspector from a different settings page.
	host.service.execute({"op": "simulation.edit"})
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true
	host._viewport_input(click, Vector2(240, 420))
	checks["viewport_selection_opens_object_properties"] = ui.tabs.current_tab == ui.pages["物体"].get_parent().get_index() and host.selected_id == "ball_A"
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE; key.pressed = true
	ui.preview.grab_focus()
	host._unhandled_key_input(key)
	checks["space_runs_simulation"] = host.session.mode == "playing"
	ui.object_panel.fields["name"].grab_focus()
	host._unhandled_key_input(key)
	checks["text_editing_does_not_trigger_space_shortcut"] = host.session.mode == "playing"
	ui.preview.grab_focus()
	host.service.execute({"op": "scene.load", "args": {"path": "res://config/workbench_long.json"}})
	ui.select_page("场景")
	await _shot("09_long_world")
	root.size = Vector2i(1100, 720)
	await _settle()
	checks["1100_layout_keeps_all_work_areas_inside_window"] = ui.preview.get_global_rect().end.x <= ui.tabs.global_position.x and ui.tabs.get_global_rect().end.x <= root.size.x
	await _shot("10_compact_1100")
	root.size = Vector2i(1920, 1080)
	await _settle()
	checks["1920_stage_uses_extra_space"] = ui.get_preview_rect().size.y >= 800
	await _shot("11_wide_1920")
	root.size = Vector2i(1440, 900)
	host.service.execute({"op": "scene.load", "args": {"path": "res://config/workbench_3d.json"}})
	if capture: await create_timer(1.2).timeout
	ui.select_page("渲染")
	(_find(ui.pages["渲染"], "三维材质与光照") as Button).button_pressed = true
	await _settle()
	checks["3d_reveals_pbr_and_hides_2d_glow"] = (_find(ui.pages["渲染"], "粗糙度") as SpinBox).is_visible_in_tree() and not (_find(ui.pages["渲染"], "全局荧光") as Button).is_visible_in_tree()
	await _shot("12_3d")
	host.service.execute({"op": "object.remove", "args": {"id": "missing_object"}})
	checks["runtime_error_has_visible_result_feedback"] = not ui.message_label.text.is_empty() and ui.message_label.get_theme_color("font_color") == Color("ff9d9d") and ui.message_label.size.y >= 20
	ui.object_panel.listing.grab_focus()
	await _shot("13_error_and_focus")
	checks["passed"] = not checks.values().has(false)
	var file := FileAccess.open("res://outputs/editor_layout_validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(checks, "\t"))
	print("EDITOR_LAYOUT_VALIDATION ", JSON.stringify(checks))
	quit(0 if checks["passed"] else 1)
