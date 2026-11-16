extends RefCounted
## JSON-only motor component definitions, presets and validation; no runtime nodes.
const KINDS := ["rotor", "slider", "swing"]
const LABELS := ["旋转挡板", "往复平台", "摆动挡板"]

## Initial transform is the exact starting pose; phase changes the subsequent stroke.
static func defaults(kind: String = "rotor") -> Dictionary:
	return {"enabled": true, "type": kind, "speed_degrees": 60.0, "travel": 180.0,
		"direction_degrees": 0.0, "amplitude_degrees": 45.0, "period_seconds": 4.0,
		"phase_degrees": 0.0, "pivot": [0.0, 0.0]}

## Reject unsupported dimensions, incompatible components and unsafe numeric inputs.
static func validate(doc: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var objects: Variant = doc.get("objects", [])
	if not objects is Array: return PackedStringArray(["机关物体列表需要数组"])
	if not doc.get("world", {}) is Dictionary: return PackedStringArray(["机关世界需要对象数据"])
	for spec in objects:
		if not spec is Dictionary or not spec.has("motion"): continue
		var value: Variant = spec["motion"]
		if not value is Dictionary:
			errors.append("机关motion需要对象数据")
			continue
		var id := str(spec.get("id", ""))
		if doc.get("world", {}).get("dimension", "") != "2d": errors.append("机关目前仅支持二维：" + id)
		if not value.get("enabled", false) is bool: errors.append("机关启用需要布尔值：" + id)
		if value.get("type", "") not in KINDS: errors.append("机关类型需要rotor/slider/swing：" + id)
		if value.get("enabled", false) == true:
			if not spec.get("physics", {}) is Dictionary or spec.get("physics", {}).get("mode", "") != "static": errors.append("机关需要固定物体模式，由电机驱动：" + id)
			if spec.has("glass"): errors.append("玻璃破坏与电机机关不能装在同一物体：" + id)
		var ranges := {"speed_degrees": [-360, 360], "travel": [0, 2000], "direction_degrees": [-360, 360],
			"amplitude_degrees": [0, 170], "period_seconds": [1, 120], "phase_degrees": [-360, 360]}
		var fallback := defaults()
		for key in ranges:
			if not _number(value.get(key, fallback[key]), ranges[key][0], ranges[key][1]): errors.append("机关参数范围无效：" + key + " · " + id)
		var pivot: Variant = value.get("pivot", [0, 0])
		if not pivot is Array or pivot.size() != 2: errors.append("机关支点需要二维坐标：" + id)
		elif not _number(pivot[0], -2000, 2000) or not _number(pivot[1], -2000, 2000): errors.append("机关支点范围需要±2000：" + id)
	return errors

## Avoid implicit coercion of null, strings or infinite values in scene files.
static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high
