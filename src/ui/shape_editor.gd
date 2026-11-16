extends Window
## Native draft dialog for new geometry and in-place edits; commit uses revisioned commands.
signal submitted(op: String, args: Dictionary)
const F = preload("res://src/ui/form_helpers.gd")
const Geometry = preload("res://src/document/shape_geometry.gd")
var canvas: Control
var source: Dictionary = {}
var revision := 0
var creating := false
var awaiting := false
var remove_split: CheckBox
var status: Label

## Dialog cancellation never changes the initial scene, its other objects or the retained Take.
func _ready() -> void:
	title = "物体轮廓编辑 · 局部坐标"
	size = Vector2i(850, 690)
	min_size = Vector2i(700, 600)
	transient = true
	exclusive = true
	close_requested.connect(hide)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 12)
	add_child(margin)
	var form := VBoxContainer.new(); margin.add_child(form)
	F.text(form, "已有物体应用后保留ID与未修改属性。圆/矩形以局部原点为中心拖动尺寸；多边形逐点绘制，闭合后可拖顶点。")
	var toolbar := HFlowContainer.new(); form.add_child(toolbar)
	canvas = preload("res://src/ui/shape_canvas.gd").new()
	canvas.custom_minimum_size = Vector2(640, 380)
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.focus_mode = Control.FOCUS_ALL
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	for tool in [["选择顶点", "select"], ["绘制圆", "circle"], ["绘制矩形", "rectangle"], ["绘制多边形", "polygon"]]:
		F.button(toolbar, tool[0], func(): canvas.tool = tool[1]; canvas.cancel_drawing())
	F.button(toolbar, "闭合轮廓", func(): canvas.close_polygon())
	F.button(toolbar, "取消绘制", func(): canvas.cancel_drawing())
	var presets := HFlowContainer.new(); form.add_child(presets)
	for pair in [["L形", [[-112,-80],[112,-80],[112,-32],[-64,-32],[-64,96],[-112,96]]], ["U形", [[-112,-96],[-64,-96],[-64,64],[64,64],[64,-96],[112,-96],[112,112],[-112,112]]], ["三角形", [[0,-112],[112,80],[-112,80]]]]:
		F.button(presets, pair[0], func(): canvas.configure({"primitive": "polygon", "points": pair[1]}); _shape_changed())
	var snap := F.check(presets, "网格吸附16px", true)
	snap.toggled.connect(func(value): canvas.snap = value)
	form.add_child(canvas)
	canvas.changed.connect(func(_shape): _shape_changed())
	canvas.message.connect(func(value): status.text = value)
	remove_split = F.check(form, "变更为非圆轮廓时，移除此物体不适用的分裂组件", false)
	status = F.text(form, "草稿尚未应用")
	var actions := HFlowContainer.new(); form.add_child(actions)
	F.button(actions, "应用轮廓", func(): submit(false))
	F.button(actions, "保存为新物体副本", func(): submit(true))
	F.button(actions, "放弃草稿", hide)

## Reopen only on explicit request; other inspector changes cannot silently replace a draft.
func begin(spec: Dictionary, base_revision: int, is_new: bool) -> void:
	source = spec.duplicate(true)
	revision = base_revision
	creating = is_new
	awaiting = false
	remove_split.button_pressed = false
	canvas.configure(spec["shape"])
	_shape_changed()
	popup_centered()

## Emit one atomic geometry edit, including any explicitly staged object form values.
func submit(copy: bool) -> void:
	if canvas.pending_points.size() > 0: status.text = "请先闭合轮廓或取消未完成的绘制"; return
	if canvas.shape.get("primitive", "") == "polygon":
		var errors := Geometry.validate(canvas.shape)
		if not errors.is_empty(): status.text = "；".join(errors); return
	var spec := source.duplicate(true)
	spec["shape"] = canvas.shape.duplicate(true)
	if remove_split.button_pressed and spec["shape"].get("primitive", "") != "circle": spec["mechanisms"].erase("split_ball")
	awaiting = true
	if creating or copy:
		if copy: spec["name"] = str(spec.get("name", "物体")) + "副本"
		submitted.emit("object.add", {"spec": spec})
	else:
		var changes := spec.duplicate(true)
		changes.erase("id")
		submitted.emit("object.update", {"id": source["id"], "expected_revision": revision, "changes": changes})

## Keep failed/conflicted drafts editable; close only after the real command succeeds.
func operation_finished(result: Dictionary) -> void:
	if not awaiting: return
	awaiting = false
	if result.get("ok", false): hide()
	else: status.text = str(result.get("error", "轮廓应用失败"))

## Surface contour validity while editing, before native physics is constructed.
func _shape_changed() -> void:
	if not is_instance_valid(status): return
	var errors := Geometry.validate(canvas.shape) if canvas.shape.get("primitive", "") == "polygon" else PackedStringArray()
	status.text = "轮廓有效；应用后按新的初始形状重新运行" if errors.is_empty() else "；".join(errors)
