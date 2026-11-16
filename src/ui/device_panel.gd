extends RefCounted
## Compact per-object motor controls, using the inspector's existing draft/apply transaction.
const F = preload("res://src/ui/form_helpers.gd")
const Spec = preload("res://src/document/device_spec.gd")

## Reuse any fixed 2D contour, including shapes drawn by the user.
static func build(parent: Node, spec: Dictionary, fields: Dictionary) -> void:
	var data: Dictionary = Spec.defaults()
	data["enabled"] = false
	data.merge(spec.get("motion", {}), true)
	var panel := F.section(parent, "机关驱动", spec.has("motion"))
	panel.tooltip_text = "固定物体由外部电机驱动；应用物体后从初始布置重新运行。支点是物体局部坐标"
	fields["motor_enabled"] = F.check(panel, "启用机关", data["enabled"])
	fields["motor_enabled"].toggled.connect(func(enabled):
		if enabled:
			fields["mode"].select(1)
			fields["split"].button_pressed = false)
	fields["motor_type"] = F.choice(panel, "运动方式", Spec.KINDS, data["type"])
	for index in Spec.LABELS.size(): fields["motor_type"].set_item_text(index, Spec.LABELS[index])
	var rotation := VBoxContainer.new(); panel.add_child(rotation)
	fields["motor_speed_degrees"] = F.number(rotation, "转速 °/秒", float(data["speed_degrees"]), -360, 360, 1)
	fields["motor_speed_degrees"].tooltip_text = "正数顺时针，负数逆时针，0为停转"
	var swing := VBoxContainer.new(); panel.add_child(swing)
	fields["motor_amplitude_degrees"] = F.number(swing, "摆幅 °", float(data["amplitude_degrees"]), 0, 170, 1)
	var slide := VBoxContainer.new(); panel.add_child(slide)
	fields["motor_travel"] = F.number(slide, "总行程 px", float(data["travel"]), 0, 2000, 1)
	fields["motor_direction_degrees"] = F.number(slide, "方向 °", float(data["direction_degrees"]), -360, 360, 1)
	var cycle := VBoxContainer.new(); panel.add_child(cycle)
	fields["motor_period_seconds"] = F.number(cycle, "周期 秒", float(data["period_seconds"]), 1, 120, 0.1)
	fields["motor_phase_degrees"] = F.number(cycle, "起始相位 °", float(data["phase_degrees"]), -360, 360, 1)
	var pivot := VBoxContainer.new(); panel.add_child(pivot)
	fields["motor_px"] = F.number(pivot, "支点 X", float(data["pivot"][0]), -2000, 2000, 1)
	fields["motor_py"] = F.number(pivot, "支点 Y", float(data["pivot"][1]), -2000, 2000, 1)
	fields["motor_type"].set_meta("motor_groups", {"rotor": rotation, "swing": swing, "slider": slide, "cycle": cycle, "pivot": pivot})
	fields["motor_type"].item_selected.connect(func(_index): refresh(fields))
	refresh(fields)

## Refresh explicitly after draft restoration, whose blocked signals must stay blocked.
static func refresh(fields: Dictionary) -> void:
	if not fields.has("motor_type"): return
	var kind := F.selected(fields["motor_type"])
	var groups: Dictionary = fields["motor_type"].get_meta("motor_groups")
	for key in Spec.KINDS: groups[key].visible = key == kind
	groups["cycle"].visible = kind != "rotor"
	groups["pivot"].visible = kind != "slider"

## Keep old scenes untouched until enabled; preserve unknown component fields when editing.
static func changes(fields: Dictionary, spec: Dictionary) -> Dictionary:
	if not fields.has("motor_enabled"): return {}
	if not spec.has("motion") and not fields["motor_enabled"].button_pressed: return {}
	var data: Dictionary = spec.get("motion", Spec.defaults()).duplicate(true)
	data["enabled"] = fields["motor_enabled"].button_pressed
	data["type"] = F.selected(fields["motor_type"])
	for key in ["speed_degrees", "amplitude_degrees", "travel", "direction_degrees", "period_seconds", "phase_degrees"]:
		data[key] = fields["motor_" + key].value
	data["pivot"] = [fields["motor_px"].value, fields["motor_py"].value]
	return {"motion": data}
