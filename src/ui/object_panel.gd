extends VBoxContainer
## Initial object placement inspector. Edits become one command when Apply is pressed.

signal command_requested(op: String, args: Dictionary)
const F = preload("res://src/ui/form_helpers.gd")
var document: Dictionary = {}
var selected_id := ""
var listing: ItemList
var form: VBoxContainer
var fields: Dictionary = {}
var selected_spec: Dictionary = {}
var pending_edits: RefCounted
var shape_editor: Window
var new_shape_button: Button
var view_top := Vector2.ZERO
var parameter_baseline: Dictionary = {}
var browser: VBoxContainer


# Build placement actions and the initial-object list once.
func _ready() -> void:
	browser = VBoxContainer.new()
	browser.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(browser)
	var actions := HBoxContainer.new()
	browser.add_child(actions)
	var add_menu := MenuButton.new()
	add_menu.text = "添加物体"
	add_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(add_menu)
	for caption in ["球", "方块", "墙壁", "玻璃（二维）"]: add_menu.get_popup().add_item(caption)
	add_menu.get_popup().id_pressed.connect(func(id): command_requested.emit("object.add", {"kind": ["ball", "box", "wall", "glass"][id]}))
	new_shape_button = F.button(actions, "绘制", func(): _open_shape(true))
	new_shape_button.tooltip_text = "绘制二维轮廓并赋予物理属性"
	shape_editor = preload("res://src/ui/shape_editor.gd").new()
	shape_editor.submitted.connect(func(op, args): command_requested.emit(op, args))
	add_child(shape_editor)
	shape_editor.hide()
	listing = ItemList.new()
	listing.custom_minimum_size.y = 130
	listing.size_flags_vertical = Control.SIZE_EXPAND_FILL
	listing.item_selected.connect(_select)
	browser.add_child(listing)
	var menu := MenuButton.new()
	menu.text = "物体操作"
	browser.add_child(menu)
	for caption in ["复制所选", "删除所选", "排列成行", "排列网格"]: menu.get_popup().add_item(caption)
	menu.get_popup().id_pressed.connect(func(id):
		if id < 2 and not selected_id.is_empty(): command_requested.emit("object.duplicate" if id == 0 else "object.remove", {"id": selected_id})
		elif id >= 2: command_requested.emit("object.arrange", {"mode": "row" if id == 2 else "grid"}))
	form = VBoxContainer.new()
	add_child(form)


# Rebuild inspector fields after a structural document command.
func sync_document(doc: Dictionary, object_id: String = "") -> void:
	document = doc
	selected_id = object_id
	new_shape_button.disabled = doc.get("world", {}).get("dimension", "2d") != "2d"
	listing.clear()
	var objects: Array = doc.get("objects", [])
	for index in objects.size():
		var spec: Dictionary = objects[index]
		listing.add_item("%s%s" % ["[锁] " if F.value(spec, "editor.locked", false) else "", spec.get("name", spec.get("id", ""))])
		listing.set_item_tooltip(index, str(spec.get("id", "")))
		listing.set_item_metadata(index, str(spec.get("id", "")))
		if str(spec.get("id", "")) == object_id:
			listing.select(index)
	_build_form()


# Selection changes only the inspector, not the simulated object.
func _select(index: int) -> void:
	selected_id = str(listing.get_item_metadata(index))
	_build_form()
	command_requested.emit("object.select", {"id": selected_id})


# Expose dimension-specific shape and physics fields for one object.
func _build_form() -> void:
	if pending_edits != null:
		pending_edits.capture()
		for key in pending_edits.groups.keys():
			if str(key).begins_with("object_"): pending_edits.groups.erase(key)
	F.clear(form)
	fields.clear()
	selected_spec = {}
	for item in document.get("objects", []):
		if str(item.get("id", "")) == selected_id:
			selected_spec = item
			break
	if selected_spec.is_empty():
		F.text(form, "选择一个物体，编辑它的形状、物理和外观。")
		return
	var is_3d: bool = F.value(document, "world.dimension", "2d") == "3d"
	var count := 3 if is_3d else 2
	fields["name"] = F.line(form, "名称", str(selected_spec.get("name", selected_id)))
	var identity := F.line(form, "物体 ID", selected_id)
	identity.editable = false
	identity.add_theme_color_override("font_uneditable_color", Color("a5b5b3"))
	identity.tooltip_text = "固定标识，可选中文字后 Ctrl+C；镜头跟随可直接按名称选择物体"
	var geometry := F.section(form, "几何与布置")
	var position: Array = F.value(selected_spec, "transform.position", [0, 0, 0] if is_3d else [0, 0])
	var velocity: Array = F.value(selected_spec, "physics.velocity", [0, 0, 0] if is_3d else [0, 0])
	for index in count:
		var axis: String = ["X", "Y", "Z"][index]
		fields["p%d" % index] = F.number(geometry, "位置 " + axis, float(position[index]), -100000, 100000, 0.1 if is_3d else 1)
	var rotation: Variant = F.value(selected_spec, "transform.rotation_degrees", [0, 0, 0] if is_3d else 0)
	if is_3d:
		for index in 3:
			fields["r%d" % index] = F.number(geometry, "旋转° " + ["X", "Y", "Z"][index], float(rotation[index]), -3600, 3600, 1)
	else:
		fields["r0"] = F.number(geometry, "旋转°", float(rotation), -3600, 3600, 1)
	var shape: Dictionary = selected_spec.get("shape", {})
	if str(shape.get("primitive", "circle")) in ["circle", "sphere"]:
		fields["radius"] = F.number(geometry, "半径", float(shape.get("radius", 18)), 0.02 if is_3d else 1, 500, 0.01 if is_3d else 1)
	elif shape.get("primitive","")=="arc":
		for key in ["inner_radius","outer_radius","start_degrees","end_degrees"]:
			fields[key]=F.number(geometry,{"inner_radius":"内半径","outer_radius":"外半径","start_degrees":"起始角度","end_degrees":"结束角度"}[key],float(shape[key]),-3600 if "degrees" in key else 1,3600 if "degrees" in key else 2000,0.1 if "degrees" in key else 1)
	elif shape.get("primitive", "") == "polygon":
		F.text(geometry, "自定义轮廓 · %d 个顶点" % shape["points"].size())
	else:
		var dimensions: Array = shape.get("size", [1, 1, 1] if is_3d else [40, 40])
		for index in count:
			fields["s%d" % index] = F.number(geometry, "尺寸 " + ["X", "Y", "Z"][index], float(dimensions[index]), 0.02 if is_3d else 1, 100000, 0.05 if is_3d else 1)
	if not is_3d: F.button(geometry, "编辑轮廓", func(): _open_shape(false)).disabled = bool(F.value(selected_spec, "editor.locked", false)) or selected_spec.has("glass")
	var physical := F.section(form, "物理与运动", false)
	fields["mode"] = F.choice(physical, "物理模式", ["dynamic", "static", "sensor"], str(F.value(selected_spec, "physics.mode", "dynamic")))
	for index in count:
		fields["v%d" % index] = F.number(physical, "初速度 " + ["X", "Y", "Z"][index], float(velocity[index]), -5000, 5000, 0.1 if is_3d else 1)
	fields["mass"] = F.number(physical, "质量", float(F.value(selected_spec, "physics.mass", 1)), 0.01, 10000, 0.01)
	# Show the same absent-material defaults that the native body builder consumes.
	var is_static: bool = F.value(selected_spec, "physics.mode", "dynamic") == "static"
	fields["bounce"] = F.number(physical, "弹性", float(F.value(selected_spec, "physics.material.restitution", 0.0 if is_static else (0.65 if is_3d else 0.88))), 0, 1, 0.01)
	fields["friction"] = F.number(physical, "摩擦", float(F.value(selected_spec, "physics.material.friction", 1.0 if is_static else (0.4 if is_3d else 0.03))), 0, 1, 0.01)
	fields["color"] = F.color(form, "物体颜色", str(F.value(selected_spec, "appearance.color", "#22c55e")))
	fields["split"] = F.check(physical, "参与碰撞分裂", "split_ball" in selected_spec.get("mechanisms", []))
	var advanced := F.section(form, "高级碰撞", false)
	fields["tags"] = F.line(advanced, "标签", ",".join(selected_spec.get("tags", [])))
	fields["tags"].tooltip_text = "用英文逗号分隔；机制用标签识别碰撞对象"
	fields["layer"] = F.number(advanced, "碰撞层", float(F.value(selected_spec, "physics.collision_layer", 1)), 0, 4294967295, 1)
	fields["mask"] = F.number(advanced, "检测掩码", float(F.value(selected_spec, "physics.collision_mask", 3)), 0, 4294967295, 1)
	fields["ccd"] = F.check(advanced, "连续碰撞检测", bool(F.value(selected_spec, "physics.ccd", true)))
	if selected_spec.has("glass"):
		var glass := F.section(form, "玻璃破坏")
		glass.tooltip_text = "接触扣耐久，归零移除碰撞体；飞散碎屑仅为视觉效果"
		fields["glass_hits"]=F.number(glass,"破裂碰撞次数",float(selected_spec["glass"]["hits"]),1,100000,1)
		fields["glass_font_size"]=F.number(glass,"数字字号",float(selected_spec["glass"].get("font_size",24)),8,96,1)
		fields["glass_shards"]=F.number(glass,"视觉碎屑数",float(selected_spec["glass"].get("shards",48)),1,256,1)
	var locked := bool(F.value(selected_spec, "editor.locked", false))
	fields["locked"] = F.check(form, "锁定物体", locked)
	fields["locked"].toggled.connect(func(value): command_requested.emit("object.update", {"id": selected_id, "changes": {"editor.locked": value}}))
	for key in fields:
		if key == "locked": continue
		var control: Control = fields[key]
		if control is LineEdit or control is SpinBox: control.editable = not locked
		elif control is BaseButton: control.disabled = locked
	var apply := F.button(form, "应用物体", _apply)
	apply.disabled = locked
	apply.tooltip_text = "点击后提交；形状、位置或物理变化会回到初始布置，再点运行。单改外观保留运动"
	form.tooltip_text = "几何或物理修改会回到初始布局，旧轨迹可能过期；材质与特效独立应用"
	parameter_baseline = _changes(fields, selected_spec, document)
	if pending_edits != null:
		var parameters: Array = []
		for key in fields:
			if key != "locked": parameters.append(fields[key])
		var captured_fields := fields.duplicate()
		var captured_spec := selected_spec.duplicate(true)
		var captured_doc := document
		pending_edits.register("object_parameters:" + selected_id, parameters, _apply, func() -> Dictionary: return {"op": "object.update", "args": {"id": captured_spec["id"], "changes": _changes(captured_fields, captured_spec, captured_doc)}})
	preload("res://src/ui/object_visual_panel.gd").build(form, document, selected_spec, func(op, args): command_requested.emit(op, args), pending_edits)

## Open a local draft using typed properties as well as the saved geometry, preserving unknown fields.
func _open_shape(creating: bool) -> void:
	if document["world"]["dimension"] != "2d": return
	if shape_editor.visible:
		shape_editor.grab_focus()
		return
	var spec: Dictionary = preload("res://src/document/scene_document.gd").new_object(document, "box", "draft") if creating else selected_spec.duplicate(true)
	if creating: spec["transform"]["position"] = [view_top.x + 360, view_top.y + 640]
	else:
		var changes := _changes(fields, selected_spec, document)
		for path in changes:
			if changes[path] != parameter_baseline.get(path): preload("res://src/document/scene_document.gd").set_field_path(spec, path, changes[path])
	shape_editor.begin(spec, int(document.get("revision", 1)), creating)

## Successful geometry edits consumed the draft values; do not restore stale pre-edit form snapshots.
func shape_operation_finished(result: Dictionary) -> void:
	if not is_instance_valid(shape_editor) or not shape_editor.awaiting: return
	if result.get("ok", false) and pending_edits != null:
		var key := "object_parameters:" + str(shape_editor.source["id"])
		pending_edits.groups.erase(key)
		pending_edits.drafts.erase(key)
	shape_editor.operation_finished(result)


# Commit one object edit instead of rebuilding on every spinbox change.
func _apply() -> void:
	var changes := _changes(fields, selected_spec, document)
	if not changes.is_empty(): command_requested.emit("object.update", {"id": selected_id, "changes": changes})

## Build a draft without mutating the document, including fields of an object being deselected.
func _changes(controls: Dictionary, spec: Dictionary, doc: Dictionary) -> Dictionary:
	if spec.is_empty(): return {}
	var is_3d: bool = F.value(doc, "world.dimension", "2d") == "3d"
	var count := 3 if is_3d else 2
	var position: Array = []
	for field in controls.values():
		if field is SpinBox: field.apply()
	var velocity: Array = []
	var rotation: Array = []
	var dimensions: Array = []
	for index in count:
		position.append(controls["p%d" % index].value)
		velocity.append(controls["v%d" % index].value)
		rotation.append(controls["r%d" % index].value if controls.has("r%d" % index) else 0)
		if controls.has("s%d" % index): dimensions.append(controls["s%d" % index].value)
	var tags: Array = []
	for tag in str(controls["tags"].text).split(","):
		if not tag.strip_edges().is_empty(): tags.append(tag.strip_edges())
	var rules: Array = spec.get("mechanisms", []).duplicate()
	rules.erase("split_ball")
	if controls["split"].button_pressed: rules.append("split_ball")
	var changes := {"name": controls["name"].text, "tags": tags, "transform.position": position,
		"transform.rotation_degrees": rotation if is_3d else rotation[0], "physics.velocity": velocity,
		"physics.mass": controls["mass"].value, "physics.material.restitution": controls["bounce"].value,
		"physics.material.friction": controls["friction"].value, "appearance.color": "#" + controls["color"].color.to_html(),
		"physics.mode": F.selected(controls["mode"]), "physics.collision_layer": int(controls["layer"].value),
		"physics.collision_mask": int(controls["mask"].value), "physics.ccd": controls["ccd"].button_pressed, "mechanisms": rules}
	if controls.has("radius"): changes["shape.radius"] = controls["radius"].value
	elif controls.has("inner_radius"):
		for key in ["inner_radius","outer_radius","start_degrees","end_degrees"]: changes["shape."+key]=controls[key].value
	elif controls.has("s0"): changes["shape.size"] = dimensions
	if controls.has("glass_hits"):
		changes["glass.hits"]=int(controls["glass_hits"].value)
		changes["glass.shards"]=int(controls["glass_shards"].value)
		changes["glass.font_size"]=int(controls["glass_font_size"].value)
	return changes
