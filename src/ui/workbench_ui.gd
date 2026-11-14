extends Control
## Native workbench shell. The preview is a texture; all edits use domain commands.

signal command_requested(op: String, args: Dictionary)
signal viewport_input(event: InputEvent, logical_position: Vector2)
const F = preload("res://src/ui/form_helpers.gd")
const ObjectPanel = preload("res://src/ui/object_panel.gd")
const Components = preload("res://src/ui/component_panels.gd")
const Production = preload("res://src/ui/production_panels.gd")
const SceneBar = preload("res://src/ui/scene_bar.gd")
const REJECTION_LABELS := {
	"capacity_limit": "动态物体容量不足，可在机制页调整上限",
	"birth_space_blocked": "子球出生空间不足",
	"newborn_guard": "子球仍在短暂新生保护期",
	"children_split_disabled": "子球继续分裂已关闭",
	"minimum_radius": "子球尺寸已达物理最小值",
	"tag_mismatch": "碰撞对象标签不符合规则",
	"split_requires_ball": "此分裂规则只适用于球",
	"impact_metric_unavailable": "尚无可用的真实碰撞强度数据"
}
var document: Dictionary = {}
var preview_texture: Texture2D
var preview: TextureRect
var object_panel: VBoxContainer
var pages: Dictionary = {}
var timeline: HSlider
var clock_label: Label
var runtime_label: Label
var play_button: Button
var message_label: Label
var debug_text: TextEdit
var job_status_label: Label
var scene_bar: VBoxContainer
var built := false
var current_time := 0.0
var current_fps := 30.0


# Accept scene data and the clean stage texture before or after tree insertion.
func setup(doc: Dictionary, viewport_texture: Texture2D) -> void:
	document = doc
	preview_texture = viewport_texture
	if is_inside_tree() and not built: _build()


# Keep user controls responsive while the simulation is paused.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not built: _build()


# Compose the responsive preview, inspector tabs and timeline.
func _build() -> void:
	built = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "Arial"])
	theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 16
	var background := ColorRect.new()
	background.color = Color("111a27")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var layout := VBoxContainer.new()
	margin.add_child(layout)
	_build_toolbar(layout)
	runtime_label = F.text(layout, "编辑模式 · 正在加载场景")
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(body)
	var preview_column := VBoxContainer.new()
	preview_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_column.size_flags_stretch_ratio = 0.9
	body.add_child(preview_column)
	preview = TextureRect.new()
	preview.texture = preview_texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size = Vector2(380, 450)
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.mouse_filter = Control.MOUSE_FILTER_STOP
	preview.focus_mode = Control.FOCUS_ALL
	preview.gui_input.connect(_preview_input)
	preview_column.add_child(preview)
	F.text(preview_column, "点选物体 · Delete删除 · 编辑模式拖动布置 · 右侧应用参数\n视频只渲染上方画面，工作台与调试叠加不会进入成片。")
	var tabs := TabContainer.new()
	tabs.custom_minimum_size.x = 560
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_stretch_ratio = 1.15
	body.add_child(tabs)
	for caption in ["物体", "机制", "渲染", "声音", "特效", "回放", "生产", "调试"]:
		var scroll := ScrollContainer.new()
		scroll.name = caption
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tabs.add_child(scroll)
		var page := VBoxContainer.new()
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_theme_constant_override("separation", 8)
		scroll.add_child(page)
		pages[caption] = page
	object_panel = ObjectPanel.new()
	object_panel.command_requested.connect(_send)
	pages["物体"].add_child(object_panel)
	_build_timeline(layout)
	message_label = F.text(layout, "就绪。保存场景保留初始布局，录制保存实际运动轨迹。")
	sync_document(document)


# Route scene, simulation and file actions through the host command service.
func _build_toolbar(parent: Node) -> void:
	scene_bar = SceneBar.new()
	scene_bar.command_requested.connect(_send)
	parent.add_child(scene_bar)
	var bar := HFlowContainer.new()
	parent.add_child(bar)
	F.button(bar, "编辑布置", func(): _send("simulation.edit", {}))
	play_button = F.button(bar, "运行", func(): _send("simulation.toggle", {}))
	for command in [["单物理步", "simulation.step"], ["重置", "simulation.reset"], ["录制", "take.record"], ["停止录制", "take.stop"], ["撤销", "history.undo"], ["重做", "history.redo"]]:
		F.button(bar, command[0], func(): _send(command[1], {}))


# Distinguish video-frame seeking from the physical-step toolbar action.
func _build_timeline(parent: Node) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	F.button(row, "◀ 一帧", func(): _send("take.seek", {"time": maxf(0, current_time - 1.0 / current_fps)}))
	F.button(row, "一帧 ▶", func(): _send("take.seek", {"time": current_time + 1.0 / current_fps}))
	timeline = HSlider.new()
	timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline.min_value = 0
	timeline.max_value = 0.01
	timeline.step = 0.001
	timeline.value_changed.connect(func(value: float): _send("take.seek", {"time": value}))
	row.add_child(timeline)
	clock_label = Label.new()
	clock_label.custom_minimum_size.x = 255
	clock_label.tooltip_text = "成片逐帧默认30fps，提交生产任务后沿用该任务FPS；顶部“单物理步”推进一次求解。"
	row.add_child(clock_label)


# Refresh controls only when their underlying document or selection changes.
func sync_document(doc: Dictionary, selected_id: String = "") -> void:
	document = doc
	if not built: return
	object_panel.sync_document(doc, selected_id)
	for caption in ["机制", "渲染", "声音", "特效", "回放", "生产", "调试"]: F.clear(pages[caption])
	Components.mechanisms(pages["机制"], doc, _send)
	Production.rendering(pages["渲染"], doc, _send)
	Components.audio(pages["声音"], doc, _send)
	Components.effects(pages["特效"], doc, _send)
	Production.replay(pages["回放"], _send)
	Production.production(pages["生产"], _send)
	job_status_label = F.text(pages["生产"], "生产任务：空闲")
	F.text(pages["调试"], "接触事件来源于物理引擎。rule_rejected显示机制未执行的原因；无法获取真实接触点时来源标为估算。")
	debug_text = TextEdit.new()
	debug_text.editable = false
	debug_text.custom_minimum_size.y = 460
	debug_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	debug_text.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	pages["调试"].add_child(debug_text)


# Reflect actual playback state, including a replay reaching its end.
func update_play_button(info: Dictionary) -> void:
	if is_instance_valid(play_button): play_button.text = "暂停" if info.get("running", false) else "运行"


# Update counters without issuing commands or overwriting fields being edited.
func update_runtime(info: Dictionary) -> void:
	if not built: return
	update_play_button(info)
	current_time = float(info.get("time", 0))
	current_fps = maxf(1, float(info.get("output_fps", 30)))
	var duration := float(info.get("duration", 0))
	timeline.set_block_signals(true)
	timeline.max_value = maxf(0.01, duration)
	timeline.set_value_no_signal(minf(current_time, duration))
	timeline.set_block_signals(false)
	clock_label.text = "成片 %.3fs / %.3fs\n模拟 %.3fs" % [current_time, duration, float(info.get("sim_time", 0))]
	var take_status := "尚未录制轨迹" if duration <= 0 else ("轨迹已过期：请重新录制" if info.get("take_stale", false) else "轨迹可用")
	var active := int(info.get("active", 0))
	var capacity := int(F.value(document, "world.max_dynamic_bodies", 48))
	var capacity_status := "（已达上限）" if active >= capacity else ""
	runtime_label.text = "%s%s  |  物体 %d/%d%s  碰撞 %d  分裂 %d  |  %.0f FPS  |  %s" % [str(info.get("mode", "编辑")), " · 录制中" if info.get("recording", false) else "", active, capacity, capacity_status, int(info.get("contacts", 0)), int(info.get("splits", 0)), float(info.get("fps", 0)), take_status]
	job_status_label.text = "生产任务：" + str(info.get("job_status", "空闲"))
	var lines: PackedStringArray = PackedStringArray()
	lines.append("生产任务：" + str(info.get("job_status", "空闲")))
	lines.append("选中：" + str(info.get("selected_id", "无")))
	lines.append("声音状态：" + JSON.stringify(info.get("audio", {})))
	var events: Array = info.get("events", [])
	# This is historical evidence; a prior guard/space rejection may already have cleared.
	for index in range(events.size() - 1, -1, -1):
		if events[index].get("type", "") == "rule_rejected":
			var reason := str(events[index].get("reason", ""))
			lines.append("最近一次机制未执行：" + str(REJECTION_LABELS.get(reason, reason)))
			runtime_label.text += "\n最近一次机制未执行：" + str(REJECTION_LABELS.get(reason, reason))
			break
	# Hidden tabs need no text layout. Full event data stays in control state / recorded Take.
	if debug_text.is_visible_in_tree():
		for index in range(maxi(0, events.size() - 30), events.size()):
			var event: Dictionary = events[index]
			lines.append("%.3fs %s %s → %s %s" % [float(event.get("time", 0)), event.get("type", ""), event.get("id", ""), event.get("other_id", ""), event.get("reason", event.get("phase", ""))])
		debug_text.text = "\n".join(lines)
	if info.has("last_message") and not str(info["last_message"]).is_empty(): show_message(str(info["last_message"]), bool(info.get("last_message_is_error", false)))


# Keep the latest operation result visible outside the scrollable tabs.
func show_message(message: String, is_error: bool = false) -> void:
	if not is_instance_valid(message_label): return
	message_label.text = message
	message_label.add_theme_color_override("font_color", Color("ff9d9d") if is_error else Color("abd9bd"))


# Remove preview letterboxing before emitting a logical stage coordinate.
func _preview_input(event: InputEvent) -> void:
	if not event is InputEventMouse: return
	if event is InputEventMouseButton and event.pressed: preview.grab_focus()
	var area := get_preview_rect()
	var dragging: bool = event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	var releasing: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed
	if not area.has_point(event.position) and not dragging and not releasing: return
	var logical: Vector2 = (event.position - area.position) / area.size * Vector2(720, 1280)
	logical = logical.clamp(Vector2.ZERO, Vector2(720, 1280))
	viewport_input.emit(event, logical)
	accept_event()


# Return the image bounds in TextureRect-local coordinates.
func get_preview_rect() -> Rect2:
	if not is_instance_valid(preview): return Rect2()
	var scale_factor := minf(preview.size.x / 720.0, preview.size.y / 1280.0)
	var extent := Vector2(720, 1280) * scale_factor
	return Rect2((preview.size - extent) / 2.0, extent)


# All panel actions share this signal contract with the host.
func _send(op: String, args: Dictionary) -> void:
	command_requested.emit(op, args)
