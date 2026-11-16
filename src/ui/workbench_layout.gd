extends RefCounted
## Three stable work areas: object browser, clean stage, contextual inspector.
const F = preload("res://src/ui/form_helpers.gd")
const T = preload("res://src/ui/workbench_theme.gd")

## Build the shell only; scene edits and rendering remain owned by their existing modules.
static func build(ui: Control) -> void:
	ui.theme = T.create()
	var background := ColorRect.new()
	background.color = Color("111b18")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(background)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 1)
	ui.add_child(layout)
	_header(ui, layout)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 1)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(body)
	var left := _panel(body, 220)
	var object_heading := F.text(left, "场景物体")
	object_heading.add_theme_color_override("font_color", T.MUTED)
	var browser_slot := VBoxContainer.new()
	browser_slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(browser_slot)
	var nav := GridContainer.new()
	nav.columns = 2
	left.add_child(nav)
	for pair in [["物体", "物体"], ["场景", "场景"], ["画面", "渲染"], ["机制", "机制"], ["声音", "声音"], ["特效", "特效"]]:
		var button := F.button(nav, pair[0], func(): ui.select_page(pair[1]))
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ui.navigation[pair[1]] = button
	var map_section := F.section(left, "世界概览", false)
	ui.minimap = preload("res://src/ui/world_minimap.gd").new()
	ui.minimap.navigate.connect(func(top): ui._send("camera.pan", {"position": [top.x, top.y]}))
	map_section.add_child(ui.minimap)
	_stage(ui, body)
	var right := _panel(body, 382)
	ui.inspector_title = F.text(right, "物体属性")
	ui.inspector_title.add_theme_font_size_override("font_size", 18)
	ui.inspector_context = F.text(right, "选择画面或左侧列表中的物体")
	ui.inspector_context.autowrap_mode = TextServer.AUTOWRAP_OFF
	ui.inspector_context.clip_text = true
	ui.inspector_context.custom_minimum_size.y = 22
	ui.inspector_context.add_theme_color_override("font_color", T.MUTED)
	ui.tabs = TabContainer.new()
	ui.tabs.tabs_visible = false
	ui.tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui.tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(ui.tabs)
	for caption in ["物体", "场景", "机制", "渲染", "声音", "特效", "回放", "生产", "调试"]:
		var scroll := ScrollContainer.new()
		scroll.name = caption
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		ui.tabs.add_child(scroll)
		var page := VBoxContainer.new()
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(page)
		ui.pages[caption] = page
	ui.object_panel = preload("res://src/ui/object_panel.gd").new()
	ui.object_panel.pending_edits = ui.pending_edits
	ui.object_panel.command_requested.connect(ui._object_command)
	ui.pages["物体"].add_child(ui.object_panel)
	ui.object_panel.browser.reparent(browser_slot)
	_transport(ui, layout)
	var footer := _panel(layout)
	footer.add_theme_constant_override("separation", 0)
	footer.get_parent().add_theme_stylebox_override("panel", T.box("1c2825", 0, 14, 5))
	ui.message_label = F.text(footer, "就绪")
	ui.message_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	ui.message_label.custom_minimum_size.y = 20
	ui.message_label.clip_text = true
	ui.message_label.add_theme_font_size_override("font_size", 12)
	ui.select_page("物体")

## One compact header replaces multiple lines of file and simulation buttons.
static func _header(ui: Control, parent: Node) -> void:
	var panel := PanelContainer.new()
	parent.add_child(panel)
	var row := HBoxContainer.new()
	panel.add_child(row)
	ui.scene_bar = preload("res://src/ui/scene_bar.gd").new()
	ui.scene_bar.command_requested.connect(ui._send)
	ui.scene_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ui.scene_bar)
	F.button(row, "撤销", func(): ui._send("history.undo", {})).tooltip_text = "撤销初始场景编辑 · Ctrl+Z"
	F.button(row, "重做", func(): ui._send("history.redo", {})).tooltip_text = "重做 · Ctrl+Shift+Z"
	ui.apply_button = F.button(row, "应用并运行", ui._apply_all_and_run)
	ui.apply_button.tooltip_text = "统一提交所有面板草稿，从初始布局运行"
	var export_button := F.button(row, "导出视频", func(): ui.select_page("生产"))
	T.primary(export_button)

## The image has all remaining height; minimap and help no longer shrink it.
static func _stage(ui: Control, parent: Node) -> void:
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 0)
	parent.add_child(center)
	var bar := HBoxContainer.new()
	center.add_child(bar)
	var label := F.text(bar, "  实时预览")
	label.add_theme_color_override("font_color", T.MUTED)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	F.button(bar, "返回布置", func(): ui._send("simulation.edit", {})).tooltip_text = "回到初始场景；当前轨迹仍保留"
	ui.preview = TextureRect.new()
	ui.preview.texture = ui.preview_texture
	ui.preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ui.preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ui.preview.custom_minimum_size = Vector2(310, 300)
	ui.preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui.preview.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.preview.focus_mode = Control.FOCUS_ALL
	ui.preview.tooltip_text = "点选物体 · 编辑模式拖动布置 · Delete 删除"
	ui.preview.gui_input.connect(ui._preview_input)
	center.add_child(ui.preview)
	ui.runtime_label = F.text(center, "编辑模式")
	ui.runtime_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	ui.runtime_label.custom_minimum_size.y = 22
	ui.runtime_label.add_theme_font_size_override("font_size", 12)
	ui.runtime_label.add_theme_color_override("font_color", T.MUTED)
	ui.runtime_label.clip_text = true

## Recording and seeking belong together. Low-frequency actions live in the adjacent menu.
static func _transport(ui: Control, parent: Node) -> void:
	var panel := PanelContainer.new()
	parent.add_child(panel)
	var row := HBoxContainer.new()
	panel.add_child(row)
	ui.play_button = F.button(row, "运行", func(): ui._send("simulation.toggle", {}))
	ui.play_button.tooltip_text = "运行 / 暂停 · Space（文本编辑时不触发）"
	ui.record_button = F.button(row, "录制", func(): ui._send("take.stop" if ui.is_recording else "take.record", {}))
	ui.record_button.tooltip_text = "从初始场景录制；再次点击停止并保存"
	F.button(row, "上一帧", func(): ui._send("take.seek", {"time": maxf(0, ui.current_time - 1.0 / ui.current_fps)}))
	F.button(row, "下一帧", func(): ui._send("take.seek", {"time": ui.current_time + 1.0 / ui.current_fps}))
	ui.timeline = HSlider.new()
	ui.timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.timeline.min_value = 0
	ui.timeline.max_value = 0.01
	ui.timeline.step = 0.001
	ui.timeline.value_changed.connect(func(value): ui._send("take.seek", {"time": value}))
	row.add_child(ui.timeline)
	ui.clock_label = Label.new()
	ui.clock_label.custom_minimum_size.x = 160
	row.add_child(ui.clock_label)
	var more := MenuButton.new()
	more.text = "更多"
	row.add_child(more)
	for caption in ["单物理步", "轨迹文件", "调试日志"]: more.get_popup().add_item(caption)
	more.get_popup().id_pressed.connect(func(id):
		if id == 0: ui._send("simulation.step", {})
		else: ui.select_page("回放" if id == 1 else "调试"))

## Panels share surface spacing; only the stage expands horizontally.
static func _panel(parent: Node, width: int = 0) -> VBoxContainer:
	var panel := PanelContainer.new()
	if width > 0: panel.custom_minimum_size.x = width
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(column)
	return column
