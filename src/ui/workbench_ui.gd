extends Control
## Native workbench shell. The preview is a texture; all edits use domain commands.

signal command_requested(op: String, args: Dictionary)
signal viewport_input(event: InputEvent, logical_position: Vector2)
const F = preload("res://src/ui/form_helpers.gd")
const ObjectPanel = preload("res://src/ui/object_panel.gd")
const Components = preload("res://src/ui/component_panels.gd")
const Production = preload("res://src/ui/production_panels.gd")
const SceneBar = preload("res://src/ui/scene_bar.gd")
const ScenePanel = preload("res://src/ui/scene_panel.gd")
var minimap: Control
var pending_edits = preload("res://src/ui/pending_edits.gd").new()
var collecting_edits := false
var collected_edits: Array = []
var synced_revision := -1
var synced_document: Dictionary = {}
const REJECTION_LABELS := {
	"capacity_limit": "动态物体容量不足，可在机制页调整上限",
	"birth_space_blocked": "子球出生空间不足",
	"newborn_guard": "子球仍在短暂新生保护期",
	"children_split_disabled": "子球继续分裂已关闭",
	"minimum_radius": "子球尺寸已达物理最小值",
	"tag_mismatch": "碰撞对象标签不符合规则",
	"split_requires_ball": "此分裂规则只适用于球",
	"impact_metric_unavailable": "尚无可用的真实碰撞强度数据",
	"collision_speed_below_threshold": "碰撞相对速度低于分裂阈值"
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
var tabs: TabContainer
var navigation: Dictionary = {}
var inspector_title: Label
var inspector_context: Label
var record_button: Button
var apply_button: Button
var is_recording := false


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
	set_meta("inspector_shell", true)
	preload("res://src/ui/workbench_layout.gd").build(self)
	sync_document(document)


## Navigation changes the inspector, never destroys a page or its uncommitted draft.
func select_page(caption: String) -> void:
	if not pages.has(caption): return
	tabs.current_tab = pages[caption].get_parent().get_index()
	for key in navigation: navigation[key].set_pressed_no_signal(key == caption)
	inspector_title.text = {"物体": "物体属性", "场景": "世界与镜头", "渲染": "画面", "机制": "碰撞机制", "声音": "碰撞声音", "特效": "全局特效", "回放": "轨迹文件", "生产": "导出视频", "调试": "调试日志"}.get(caption, caption)
	_update_inspector_context()

## Selecting an existing object also returns to its contextual properties.
func _object_command(op: String, args: Dictionary) -> void:
	if op == "object.select": select_page("物体")
	_send(op, args)

## Distinguish the selected object's scope from global settings without paragraphs.
func _update_inspector_context() -> void:
	if not is_instance_valid(inspector_context): return
	var object_page: bool = tabs.current_tab == pages["物体"].get_parent().get_index()
	inspector_context.text = "当前场景 · 全局设置" if not object_page else (str(object_panel.selected_spec.get("name", object_panel.selected_id)) if not object_panel.selected_spec.is_empty() else "点击画面或左侧列表选择物体")


# Refresh controls only when their underlying document or selection changes.
func sync_document(doc: Dictionary, selected_id: String = "") -> void:
	pending_edits.capture()
	if synced_document.get("scene_id", "") != doc.get("scene_id", ""):
		pending_edits.drafts.clear()
		pending_edits.groups.clear()
	document = doc
	if not built: return
	object_panel.sync_document(doc, selected_id)
	_update_inspector_context()
	if synced_revision == int(doc.get("revision", 0)) and synced_document == doc: return
	synced_revision = int(doc.get("revision", 0))
	synced_document = doc.duplicate(true)
	for caption in ["场景", "机制", "渲染", "声音", "特效", "回放", "生产", "调试"]: F.clear(pages[caption])
	ScenePanel.build(pages["场景"], doc, _send, pending_edits, selected_id)
	Components.mechanisms(pages["机制"], doc, _send, pending_edits)
	Production.rendering(pages["渲染"], doc, _send, pending_edits)
	Components.audio(pages["声音"], doc, _send, pending_edits)
	Components.effects(pages["特效"], doc, _send, pending_edits)
	Production.replay(pages["回放"], _send)
	Production.production(pages["生产"], _send, doc, pending_edits)
	job_status_label = F.text(pages["生产"], "生产任务：空闲")
	F.text(pages["调试"], "接触与机制事件").tooltip_text = "无法获取真实接触点时标为估算；这里只读，不修改模拟。"
	debug_text = TextEdit.new()
	debug_text.editable = false
	debug_text.custom_minimum_size.y = 460
	debug_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	debug_text.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	pages["调试"].add_child(debug_text)


# Reflect actual playback state, including a replay reaching its end.
func update_play_button(info: Dictionary) -> void:
	if is_instance_valid(play_button): play_button.text = "暂停" if info.get("running", false) else "运行"
	is_recording = bool(info.get("recording", false))
	if is_instance_valid(record_button): record_button.text = "停止录制" if is_recording else "录制"


# Update counters without issuing commands or overwriting fields being edited.
func update_runtime(info: Dictionary) -> void:
	if not built: return
	update_play_button(info)
	current_time = float(info.get("time", 0))
	current_fps = maxf(1, float(info.get("output_fps", 30)))
	var duration := float(info.get("duration", 0))
	timeline.editable = duration > 0 and not is_recording
	timeline.set_block_signals(true)
	timeline.max_value = maxf(0.01, duration)
	timeline.set_value_no_signal(minf(current_time, duration))
	timeline.set_block_signals(false)
	clock_label.text = "%.2f / %.2f s" % [current_time, duration]
	clock_label.tooltip_text = "成片 %.3f s · 模拟 %.3f s · %d fps" % [current_time, float(info.get("sim_time", 0)), current_fps]
	var take_status := "尚未录制轨迹" if duration <= 0 else ("轨迹已过期：请重新录制" if info.get("take_stale", false) else "轨迹可用")
	if duration <= 0: clock_label.text = "尚未录制"
	elif info.get("take_stale", false): clock_label.text = "轨迹已过期"
	clock_label.tooltip_text += "\n" + take_status
	var active := int(info.get("active", 0))
	var capacity := int(F.value(document, "world.max_dynamic_bodies", 48))
	var capacity_status := "（已达上限）" if active >= capacity else ""
	var modes := {"edit": "布置", "playing": "运行中", "paused": "已暂停", "recording": "录制中", "replay": "回放"}
	runtime_label.text = "%s · 物体 %d/%d%s · 渲染 %.0f FPS" % [str(modes.get(str(info.get("mode", "edit")), str(info.get("mode", "布置")))), active, capacity, capacity_status, float(info.get("fps", 0))]
	runtime_label.tooltip_text = "%s · 碰撞 %d · 分裂 %d" % [take_status, int(info.get("contacts", 0)), int(info.get("splits", 0))]
	if info.get("hit_stop_active", false): runtime_label.text += " · 分裂顿帧中：物理暂停"
	if float(info.get("hit_stop_elapsed_seconds", 0)) > 0.001: runtime_label.text += " · 累计顿帧 %.2fs" % float(info["hit_stop_elapsed_seconds"])
	var job: Variant = JSON.parse_string(str(info.get("job_status", "{}")))
	var state := str(job.get("state", "idle")) if job is Dictionary else "idle"
	var states := {"idle": "空闲", "starting": "准备中", "queued": "排队中", "rendering": "正在渲染", "mixing": "正在混音", "encoding": "正在编码", "complete": "已完成", "cancelled": "已取消", "failed": "失败"}
	job_status_label.text = "导出：" + str(states.get(state, state))
	if duration <= 0: job_status_label.text = "请先在底部录制一段轨迹"
	elif info.get("take_stale", false): job_status_label.text = "物理设置已改变，请重新录制"
	job_status_label.tooltip_text = str(info.get("job_status", ""))
	for control in get_tree().get_nodes_in_group("export_controls"):
		if control.get_meta("cancel", false): control.disabled = state in ["idle", "complete", "cancelled", "failed"]
		else: control.disabled = duration <= 0 or bool(info.get("take_stale", false)) or is_recording or state not in ["idle", "complete", "cancelled", "failed"]
	var dirty: bool = not pending_edits.drafts.is_empty()
	for group in pending_edits.groups.values():
		if pending_edits.changed(group): dirty = true; break
	apply_button.text = "应用更改并运行" if dirty else "应用并运行"
	var lines: PackedStringArray = PackedStringArray()
	lines.append("生产任务：" + str(info.get("job_status", "空闲")))
	lines.append("选中：" + str(info.get("selected_id", "无")))
	lines.append("声音状态：" + JSON.stringify(info.get("audio", {})))
	lines.append("镜头状态：" + JSON.stringify(info.get("camera", {})))
	var events: Array = info.get("events", [])
	# This is historical evidence; a prior guard/space rejection may already have cleared.
	for index in range(events.size() - 1, -1, -1):
		if events[index].get("type", "") == "rule_rejected":
			var reason := str(events[index].get("reason", ""))
			lines.append("最近一次机制未执行：" + str(REJECTION_LABELS.get(reason, reason)))
			runtime_label.tooltip_text += "\n最近一次机制未执行：" + str(REJECTION_LABELS.get(reason, reason))
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
	message_label.tooltip_text = message
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
	if collecting_edits:
		collected_edits.append({"op": op, "args": args})
		return
	command_requested.emit(op, args)

## Collect before committing, so a panel rebuild cannot discard another tab's pending inputs.
func _apply_all_and_run() -> void:
	collected_edits = []
	collecting_edits = true
	var inactive: Array = pending_edits.collect()
	collected_edits.append_array(inactive)
	collecting_edits = false
	_send("scene.apply_run", {"edits": collected_edits})
