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


# Build placement actions and the initial-object list once.
func _ready() -> void:
	F.text(self, "编辑初始布局。预览中可点选，编辑模式可拖动。修改物理参数会重置并使旧轨迹过期。")
	var actions := HFlowContainer.new()
	add_child(actions)
	for pair in [["添加球", "ball"], ["添加方块", "box"], ["添加墙", "wall"]]:
		F.button(actions, pair[0], func(): command_requested.emit("object.add", {"kind": pair[1]}))
	F.button(actions, "排列成行", func(): command_requested.emit("object.arrange", {"mode": "row"}))
	F.button(actions, "排列网格", func(): command_requested.emit("object.arrange", {"mode": "grid"}))
	listing = ItemList.new()
	listing.custom_minimum_size.y = 145
	listing.item_selected.connect(_select)
	add_child(listing)
	form = VBoxContainer.new()
	add_child(form)


# Rebuild inspector fields after a structural document command.
func sync_document(doc: Dictionary, object_id: String = "") -> void:
	document = doc
	selected_id = object_id
	listing.clear()
	var objects: Array = doc.get("objects", [])
	for index in objects.size():
		var spec: Dictionary = objects[index]
		listing.add_item("%s%s  ·  %s" % ["[锁定] " if F.value(spec, "editor.locked", false) else "", spec.get("name", spec.get("id", "")), spec.get("id", "")])
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
	F.clear(form)
	fields.clear()
	selected_spec = {}
	for item in document.get("objects", []):
		if str(item.get("id", "")) == selected_id:
			selected_spec = item
			break
	if selected_spec.is_empty():
		F.text(form, "请选择初始物体。运行中新生物体可在调试日志查看。")
		return
	var is_3d: bool = F.value(document, "world.dimension", "2d") == "3d"
	var count := 3 if is_3d else 2
	fields["name"] = F.line(form, "名称", str(selected_spec.get("name", selected_id)))
	fields["tags"] = F.line(form, "标签（逗号分隔）", ",".join(selected_spec.get("tags", [])))
	var position: Array = F.value(selected_spec, "transform.position", [0, 0, 0] if is_3d else [0, 0])
	var velocity: Array = F.value(selected_spec, "physics.velocity", [0, 0, 0] if is_3d else [0, 0])
	for index in count:
		var axis: String = ["X", "Y", "Z"][index]
		fields["p%d" % index] = F.number(form, "位置 " + axis, float(position[index]), -10000, 10000, 0.1 if is_3d else 1)
		fields["v%d" % index] = F.number(form, "初速度 " + axis, float(velocity[index]), -5000, 5000, 0.1 if is_3d else 1)
	var rotation: Variant = F.value(selected_spec, "transform.rotation_degrees", [0, 0, 0] if is_3d else 0)
	if is_3d:
		for index in 3:
			fields["r%d" % index] = F.number(form, "旋转° " + ["X", "Y", "Z"][index], float(rotation[index]), -3600, 3600, 1)
	else:
		fields["r0"] = F.number(form, "旋转°", float(rotation), -3600, 3600, 1)
	var shape: Dictionary = selected_spec.get("shape", {})
	if str(shape.get("primitive", "circle")) in ["circle", "sphere"]:
		fields["radius"] = F.number(form, "半径", float(shape.get("radius", 18)), 0.02 if is_3d else 1, 500, 0.01 if is_3d else 1)
	else:
		var dimensions: Array = shape.get("size", [1, 1, 1] if is_3d else [40, 40])
		for index in count:
			fields["s%d" % index] = F.number(form, "尺寸 " + ["X", "Y", "Z"][index], float(dimensions[index]), 0.02 if is_3d else 1, 5000, 0.05 if is_3d else 1)
	fields["mass"] = F.number(form, "质量", float(F.value(selected_spec, "physics.mass", 1)), 0.01, 10000, 0.01)
	fields["bounce"] = F.number(form, "弹性", float(F.value(selected_spec, "physics.material.restitution", 0.8)), 0, 1, 0.01)
	fields["friction"] = F.number(form, "摩擦", float(F.value(selected_spec, "physics.material.friction", 0.1)), 0, 1, 0.01)
	fields["color"] = F.color(form, "物体颜色", str(F.value(selected_spec, "appearance.color", "#22c55e")))
	fields["mode"] = F.choice(form, "物理模式", ["dynamic", "static", "sensor"], str(F.value(selected_spec, "physics.mode", "dynamic")))
	F.text(form, "dynamic受力运动；static作为实体边界；sensor只感知接触。碰撞层和掩码是位掩码（常用1、2、3）。")
	fields["layer"] = F.number(form, "碰撞层位掩码", float(F.value(selected_spec, "physics.collision_layer", 1)), 0, 4294967295, 1)
	fields["mask"] = F.number(form, "碰撞检测位掩码", float(F.value(selected_spec, "physics.collision_mask", 3)), 0, 4294967295, 1)
	fields["ccd"] = F.check(form, "连续碰撞检测 CCD", bool(F.value(selected_spec, "physics.ccd", true)))
	fields["split"] = F.check(form, "启用碰撞分裂组件", "split_ball" in selected_spec.get("mechanisms", []))
	var locked := bool(F.value(selected_spec, "editor.locked", false))
	fields["locked"] = F.check(form, "锁定物体布置与参数", locked)
	F.button(form, "应用锁定状态", func(): command_requested.emit("object.update", {"id": selected_id, "changes": {"editor.locked": fields["locked"].button_pressed}}))
	if locked: F.text(form, "此物体已锁定。取消勾选锁定并应用后，才能继续编辑。")
	for key in fields:
		if key == "locked": continue
		var control: Control = fields[key]
		if control is LineEdit or control is SpinBox: control.editable = not locked
		elif control is BaseButton: control.disabled = locked
	F.button(form, "应用物体参数并重置", _apply).disabled = locked
	var actions := HFlowContainer.new()
	form.add_child(actions)
	F.button(actions, "复制物体", func(): command_requested.emit("object.duplicate", {"id": selected_id}))
	F.button(actions, "删除物体", func(): command_requested.emit("object.remove", {"id": selected_id})).disabled = locked


# Commit one object edit instead of rebuilding on every spinbox change.
func _apply() -> void:
	if selected_spec.is_empty():
		return
	var is_3d: bool = F.value(document, "world.dimension", "2d") == "3d"
	var count := 3 if is_3d else 2
	var position: Array = []
	var velocity: Array = []
	var rotation: Array = []
	var dimensions: Array = []
	for index in count:
		position.append(fields["p%d" % index].value)
		velocity.append(fields["v%d" % index].value)
		rotation.append(fields["r%d" % index].value if fields.has("r%d" % index) else 0)
		if fields.has("s%d" % index): dimensions.append(fields["s%d" % index].value)
	var tags: Array = []
	for tag in str(fields["tags"].text).split(","):
		if not tag.strip_edges().is_empty(): tags.append(tag.strip_edges())
	var rules: Array = selected_spec.get("mechanisms", []).duplicate()
	rules.erase("split_ball")
	if fields["split"].button_pressed: rules.append("split_ball")
	var changes := {"name": fields["name"].text, "tags": tags, "transform.position": position,
		"transform.rotation_degrees": rotation if is_3d else rotation[0], "physics.velocity": velocity,
		"physics.mass": fields["mass"].value, "physics.material.restitution": fields["bounce"].value,
		"physics.material.friction": fields["friction"].value, "appearance.color": "#" + fields["color"].color.to_html(),
		"physics.mode": F.selected(fields["mode"]), "physics.collision_layer": int(fields["layer"].value),
		"physics.collision_mask": int(fields["mask"].value), "physics.ccd": fields["ccd"].button_pressed, "mechanisms": rules}
	if fields.has("radius"): changes["shape.radius"] = fields["radius"].value
	else: changes["shape.size"] = dimensions
	command_requested.emit("object.update", {"id": selected_id, "changes": changes})
