extends RefCounted
## Validate long-world, camera and object visual controls before commands reach the engine.

## Only optional fields are checked here, preserving v2 scenes that predate these controls.
static func validate(doc: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var bounds: Variant = doc.get("world", {}).get("bounds_2d", [0, 0, 720, 1280])
	if not bounds is Array or bounds.size() != 4: errors.append("世界范围需要[x,y,宽,高]")
	else:
		for number in bounds:
			if not _number(number, -100000, 100000): errors.append("世界范围需要±100000内有限数值")
		if _number(bounds[2], 1, 100000) == false or _number(bounds[3], 1, 100000) == false: errors.append("世界宽高需要1～100000")
	var render: Variant = doc.get("presentation", {}).get("render", {})
	if not render is Dictionary: return errors
	var camera: Variant = render.get("camera", {})
	if not camera is Dictionary: return errors
	if camera.get("mode", "fixed") not in ["fixed", "follow_y"]: errors.append("二维镜头模式需要fixed或follow_y")
	if camera.get("on_split", "lowest_descendant") not in ["lowest_descendant", "stop"]: errors.append("分裂跟随策略无效")
	for key in ["only_down", "limit_world"]:
		if camera.has(key) and not camera[key] is bool: errors.append("镜头开关需要布尔值：" + key)
	for key in ["framing_y", "dead_zone_top", "dead_zone_bottom"]:
		if not _number(camera.get(key, {"framing_y": 0.42, "dead_zone_top": 0.32, "dead_zone_bottom": 0.58}[key]), 0, 1): errors.append("镜头画幅比例需要0～1：" + key)
	if _number(camera.get("dead_zone_top", 0.32), 0, 1) and _number(camera.get("dead_zone_bottom", 0.58), 0, 1) and float(camera.get("dead_zone_top", 0.32)) > float(camera.get("dead_zone_bottom", 0.58)): errors.append("镜头死区上限不能超过下限")
	if not _number(camera.get("smooth_seconds", 0.18), 0, 10): errors.append("镜头平滑需要0～10秒")
	if camera.has("target_root") and not camera["target_root"] is String: errors.append("跟随根物体ID需要文本")
	var top: Variant = camera.get("position_2d", [0, 0])
	if not top is Array or top.size() != 2: errors.append("镜头左上角需要二维坐标")
	else:
		for value in top:
			if not _number(value, -100000, 100000): errors.append("镜头位置无效")
	for spec in doc.get("objects", []):
		if not spec is Dictionary or not spec.get("appearance", {}) is Dictionary: continue
		var physics: Variant = spec.get("physics", {})
		if physics is Dictionary and physics.get("material", {}) is Dictionary:
			for key in ["friction", "restitution"]:
				if not _number(physics.get("material", {}).get(key, 0.5), 0, 1): errors.append("物理材质参数需要0～1：" + key)
		for type in ["material", "effects"]:
			var value: Variant = spec.get("appearance", {}).get(type, {})
			if not value is Dictionary: errors.append("物体" + type + "需要对象数据"); continue
			if value.get("mode", "inherit") not in ["inherit", "custom"]: errors.append("物体覆盖模式需要inherit或custom")
			if type == "effects": errors.append_array(effect_errors(value))
			else:
				for key in ["roughness", "metallic", "emission"]:
					if value.has(key) and not _number(value[key], 0, 8 if key == "emission" else 1): errors.append("物体材质参数范围无效：" + key)
				if value.has("neon"):
					if not value["neon"] is Dictionary: errors.append("物体荧光需要对象数据")
					else:
						var neon: Dictionary = value["neon"]
						if not neon.get("enabled", false) is bool: errors.append("物体荧光开关需要布尔值")
						for key in {"glow_width": [1,64], "glow_strength": [0,2], "highlight_size": [0,1], "highlight_strength": [0,3]}:
							var ranges: Dictionary = {"glow_width": [1,64], "glow_strength": [0,2], "highlight_size": [0,1], "highlight_strength": [0,3]}
							if neon.has(key) and not _number(neon[key], ranges[key][0], ranges[key][1]): errors.append("物体荧光参数范围无效：" + key)
	return errors

## Keep event lifetime/search ranges bounded for both global and local effects.
static func effect_errors(value: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	for key in ["enabled", "particles_enabled", "impact_particles", "impact_flash", "trail_enabled", "ring", "flash"]:
		if value.has(key) and not value[key] is bool: errors.append("物体特效开关需要布尔值：" + key)
	for key in {"lifetime": [0.05,3], "trail_seconds": [0.03,2], "count": [0,64], "speed": [10,800]}:
		var ranges: Dictionary = {"lifetime": [0.05,3], "trail_seconds": [0.03,2], "count": [0,64], "speed": [10,800]}
		if value.has(key) and not _number(value[key], ranges[key][0], ranges[key][1]): errors.append("特效参数范围无效：" + key)
	if value.has("time_domain") and value["time_domain"] not in ["simulation", "presentation"]: errors.append("特效时间域无效")
	return errors

## No implicit string/null/NaN coercions are allowed for editable numeric fields.
static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high
