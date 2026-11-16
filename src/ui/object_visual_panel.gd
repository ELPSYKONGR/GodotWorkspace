extends RefCounted
## Object-specific visual panels own only appearance fields, never global or physical settings.
const F = preload("res://src/ui/form_helpers.gd")
const Style = preload("res://src/document/object_style.gd")

## Keep material/effect application separate from the physical-parameter form transaction.
static func build(parent: Node, doc: Dictionary, spec: Dictionary, send: Callable, pending: RefCounted) -> void:
	var render: Dictionary = F.value(doc, "presentation.render", {})
	var local: Dictionary = F.value(spec, "appearance.material", {})
	var resolved := Style.material(spec, render)
	F.text(parent, "物体材质：继承全局时使用渲染页；独立设置只影响当前物体及其后代。粗糙度/金属度/自发光用于三维；二维荧光用于圆/矩形，多边形为亮边。")
	var mode := F.choice(parent, "物体材质来源", ["inherit", "custom"], str(local.get("mode", "inherit")))
	var roughness := F.number(parent, "物体粗糙度（3D）", float(resolved.get("roughness", 0.35)), 0, 1, 0.01)
	var metallic := F.number(parent, "物体金属度（3D）", float(resolved.get("metallic", 0.15)), 0, 1, 0.01)
	var emission := F.number(parent, "物体自发光（3D）", float(resolved.get("emission", 0)), 0, 8, 0.05)
	var neon: Dictionary = resolved.get("neon", {})
	var glowing := F.check(parent, "此物体启用二维荧光", bool(neon.get("enabled", false)))
	var width := F.number(parent, "物体光晕范围", float(neon.get("glow_width", 18)), 1, 64, 1)
	var strength := F.number(parent, "物体光晕强度", float(neon.get("glow_strength", 0.9)), 0, 2, 0.05)
	var highlight := F.number(parent, "物体高光大小", float(neon.get("highlight_size", 0.3)), 0, 1, 0.05)
	var energy := F.number(parent, "物体高光强度", float(neon.get("highlight_strength", 1.1)), 0, 3, 0.05)
	var controls: Array = [mode, roughness, metallic, emission, glowing, width, strength, highlight, energy]
	var changes := func() -> Dictionary:
		for control in controls:
			if control is SpinBox: control.apply()
		var value := local.duplicate(true)
		value.merge({"mode": F.selected(mode), "roughness": roughness.value, "metallic": metallic.value, "emission": emission.value, "neon": {"enabled": glowing.button_pressed, "glow_width": width.value, "glow_strength": strength.value, "highlight_size": highlight.value, "highlight_strength": energy.value}}, true)
		return {"appearance.material": value}
	_register(parent, "应用物体材质（保留运动）", "object_material:", spec, controls, changes, send, pending)
	_effects(parent, doc, spec, send, pending)

## Every supported local effect has an explicit control and is consumed during live/replay/export.
static func _effects(parent: Node, doc: Dictionary, spec: Dictionary, send: Callable, pending: RefCounted) -> void:
	F.text(parent, "物体特效：独立于其它物体。全局特效总开关仍控制全部输出；同一碰撞中两方各自的不同特效可同时出现。")
	var global: Dictionary = F.value(doc, "presentation.effects", {})
	var local: Dictionary = F.value(spec, "appearance.effects", {})
	var resolved := global.duplicate(true)
	if local.get("mode", "inherit") == "custom": resolved.merge(local, true)
	var mode := F.choice(parent, "物体特效来源", ["inherit", "custom"], str(local.get("mode", "inherit")))
	var controls: Array = [mode]
	var flags: Dictionary = {}
	for key in {"enabled": "此物体特效", "trail_enabled": "此物体拖尾", "ring": "此物体碰撞光圈", "impact_particles": "此物体碰撞粒子", "impact_flash": "此物体碰撞闪光", "particles_enabled": "此物体分裂粒子", "flash": "此物体分裂闪光"}:
		var names: Dictionary = {"enabled": "此物体特效", "trail_enabled": "此物体拖尾", "ring": "此物体碰撞光圈", "impact_particles": "此物体碰撞粒子", "impact_flash": "此物体碰撞闪光", "particles_enabled": "此物体分裂粒子", "flash": "此物体分裂闪光"}
		flags[key] = F.check(parent, names[key], bool(resolved.get(key, key not in ["impact_particles", "impact_flash"])))
		controls.append(flags[key])
	var count := F.number(parent, "物体粒子数量", float(resolved.get("count", 12)), 0, 64, 1)
	var lifetime := F.number(parent, "物体粒子寿命", float(resolved.get("lifetime", 0.35)), 0.05, 3, 0.01)
	var speed := F.number(parent, "物体粒子速度", float(resolved.get("speed", 130)), 10, 800, 1)
	var trail := F.number(parent, "物体拖尾秒数", float(resolved.get("trail_seconds", 0.25)), 0.03, 2, 0.01)
	var color := F.color(parent, "物体特效颜色", str(resolved.get("color", "#baf7d0")))
	var clock := F.choice(parent, "物体特效时钟", ["simulation", "presentation"], str(resolved.get("time_domain", "simulation")))
	controls.append_array([count, lifetime, speed, trail, color, clock])
	var changes := func() -> Dictionary:
		for control in controls:
			if control is SpinBox: control.apply()
		var value := local.duplicate(true)
		value.merge({"mode": F.selected(mode), "count": int(count.value), "lifetime": lifetime.value, "speed": speed.value, "trail_seconds": trail.value, "color": "#" + color.color.to_html(), "time_domain": F.selected(clock)}, true)
		for key in flags: value[key] = flags[key].button_pressed
		return {"appearance.effects": value}
	_register(parent, "应用物体特效（保留运动）", "object_effects:", spec, controls, changes, send, pending)

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
