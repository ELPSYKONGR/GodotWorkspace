extends RefCounted
## Object-specific visual panels own only appearance fields, never global or physical settings.
const F = preload("res://src/ui/form_helpers.gd")
const Style = preload("res://src/document/object_style.gd")

## Keep material/effect application separate from the physical-parameter form transaction.
static func build(parent: Node, doc: Dictionary, spec: Dictionary, send: Callable, pending: RefCounted) -> void:
	parent = F.section(parent, "独立材质", false)
	var render: Dictionary = F.value(doc, "presentation.render", {})
	var local: Dictionary = F.value(spec, "appearance.material", {})
	var resolved := Style.material(spec, render)
	parent.tooltip_text = "独立设置只影响当前物体及其后代，应用后保留运动"
	var mode := F.choice(parent, "材质来源", ["inherit", "custom"], str(local.get("mode", "inherit")))
	var body := VBoxContainer.new()
	parent.add_child(body)
	var pbr := VBoxContainer.new()
	body.add_child(pbr)
	pbr.visible = doc["world"]["dimension"] == "3d"
	var roughness := F.number(pbr, "粗糙度", float(resolved.get("roughness", 0.35)), 0, 1, 0.01)
	var metallic := F.number(pbr, "金属度", float(resolved.get("metallic", 0.15)), 0, 1, 0.01)
	var emission := F.number(pbr, "自发光", float(resolved.get("emission", 0)), 0, 8, 0.05)
	var neon: Dictionary = resolved.get("neon", {})
	var neon_body := VBoxContainer.new()
	body.add_child(neon_body)
	neon_body.visible = not pbr.visible
	var glowing := F.check(neon_body, "二维荧光", bool(neon.get("enabled", false)))
	var width := F.number(neon_body, "光晕范围 / px", float(neon.get("glow_width", 18)), 1, 64, 1)
	var strength := F.number(neon_body, "光晕强度", float(neon.get("glow_strength", 0.9)), 0, 2, 0.05)
	var highlight := F.number(neon_body, "高光大小", float(neon.get("highlight_size", 0.3)), 0, 1, 0.05)
	var energy := F.number(neon_body, "高光强度", float(neon.get("highlight_strength", 1.1)), 0, 3, 0.05)
	var controls: Array = [mode, roughness, metallic, emission, glowing, width, strength, highlight, energy]
	var changes := func() -> Dictionary:
		for control in controls:
			if control is SpinBox: control.apply()
		var value := local.duplicate(true)
		value.merge({"mode": F.selected(mode), "roughness": roughness.value, "metallic": metallic.value, "emission": emission.value, "neon": {"enabled": glowing.button_pressed, "glow_width": width.value, "glow_strength": strength.value, "highlight_size": highlight.value, "highlight_strength": energy.value}}, true)
		return {"appearance.material": value}
	_register(parent, "应用材质", "object_material:", spec, controls, changes, send, pending)
	mode.item_selected.connect(func(_index): body.visible = F.selected(mode) == "custom")
	body.visible = F.selected(mode) == "custom"
	_effects(parent.get_parent().get_parent(), doc, spec, send, pending)

## Every supported local effect has an explicit control and is consumed during live/replay/export.
static func _effects(parent: Node, doc: Dictionary, spec: Dictionary, send: Callable, pending: RefCounted) -> void:
	parent = F.section(parent, "独立特效", false)
	parent.tooltip_text = "只影响当前物体及其后代；全局特效总开关仍控制全部输出"
	var global: Dictionary = F.value(doc, "presentation.effects", {})
	var local: Dictionary = F.value(spec, "appearance.effects", {})
	var resolved := global.duplicate(true)
	if local.get("mode", "inherit") == "custom": resolved.merge(local, true)
	var mode := F.choice(parent, "特效来源", ["inherit", "custom"], str(local.get("mode", "inherit")))
	var body := VBoxContainer.new()
	parent.add_child(body)
	var controls: Array = [mode]
	var flags: Dictionary = {}
	for key in {"enabled": "此物体特效", "trail_enabled": "此物体拖尾", "ring": "此物体碰撞光圈", "impact_particles": "此物体碰撞粒子", "impact_flash": "此物体碰撞闪光", "particles_enabled": "此物体分裂粒子", "flash": "此物体分裂闪光"}:
		var names: Dictionary = {"enabled": "此物体特效", "trail_enabled": "此物体拖尾", "ring": "此物体碰撞光圈", "impact_particles": "此物体碰撞粒子", "impact_flash": "此物体碰撞闪光", "particles_enabled": "此物体分裂粒子", "flash": "此物体分裂闪光"}
		flags[key] = F.check(body, names[key].replace("此物体", ""), bool(resolved.get(key, key not in ["impact_particles", "impact_flash"])))
		controls.append(flags[key])
	var count := F.number(body, "粒子数量", float(resolved.get("count", 12)), 0, 64, 1)
	var lifetime := F.number(body, "粒子寿命 / s", float(resolved.get("lifetime", 0.35)), 0.05, 3, 0.01)
	var speed := F.number(body, "扩散速度 / px/s", float(resolved.get("speed", 130)), 10, 800, 1)
	var trail := F.number(body, "拖尾长度 / s", float(resolved.get("trail_seconds", 0.25)), 0.03, 2, 0.01)
	var color := F.color(body, "特效颜色", str(resolved.get("color", "#baf7d0")))
	var clock := F.choice(body, "时间依据", ["simulation", "presentation"], str(resolved.get("time_domain", "simulation")))
	controls.append_array([count, lifetime, speed, trail, color, clock])
	var changes := func() -> Dictionary:
		for control in controls:
			if control is SpinBox: control.apply()
		var value := local.duplicate(true)
		value.merge({"mode": F.selected(mode), "count": int(count.value), "lifetime": lifetime.value, "speed": speed.value, "trail_seconds": trail.value, "color": "#" + color.color.to_html(), "time_domain": F.selected(clock)}, true)
		for key in flags: value[key] = flags[key].button_pressed
		return {"appearance.effects": value}
	_register(parent, "应用特效", "object_effects:", spec, controls, changes, send, pending)
	mode.item_selected.connect(func(_index): body.visible = F.selected(mode) == "custom")
	body.visible = F.selected(mode) == "custom"

## Preserve per-object drafts across selection changes and respect the object's editor lock.
static func _register(parent: Node, caption: String, prefix: String, spec: Dictionary, controls: Array, changes: Callable, send: Callable, pending: RefCounted) -> void:
	var locked: bool = F.value(spec, "editor.locked", false)
	for control in controls:
		if control is SpinBox: control.editable = not locked
		elif control is BaseButton: control.disabled = locked
	var command := func() -> Dictionary: return {"op": "object.update", "args": {"id": spec["id"], "changes": changes.call()}}
	var apply := func():
		var value: Dictionary = command.call()
		send.call(value["op"], value["args"])
	F.button(parent, caption, apply).disabled = locked
	if pending != null: pending.register(prefix + str(spec["id"]), controls, apply, command)
