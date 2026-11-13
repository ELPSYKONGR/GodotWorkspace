extends RefCounted
## Versioned scene data and edits. Runtime poses never overwrite the initial layout.
const MAX_DYNAMIC_OBJECTS := 256
const MAX_FIXED_OBJECTS := 256

## Parse and validate a scene before any native nodes are constructed.
static func load_file(path: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		return {"ok": false, "error": "场景JSON无效：" + parser.get_error_message()}
	var errors := validate(parser.data)
	return {"ok": errors.is_empty(), "document": parser.data, "error": "；".join(errors)}

## Validate executable primitives and finite physical values before touching the world.
static func validate(doc: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if int(doc.get("schema_version", 0)) != 2: errors.append("需要schema_version=2场景")
	if not doc.get("world", {}) is Dictionary or not doc.get("presentation", {}) is Dictionary: return PackedStringArray(["world和presentation需要对象数据"])
	var world: Dictionary = doc.get("world", {})
	var dimension := str(world.get("dimension", ""))
	if dimension not in ["2d", "3d"]: errors.append("world.dimension需要2d或3d")
	var dimensions := 3 if dimension == "3d" else 2
	if not _vector(world.get("gravity", []), dimensions): errors.append("重力维度或数值无效")
	if int(world.get("physics_hz", 240)) < 60 or int(world.get("physics_hz", 240)) > 480: errors.append("物理频率需要60～480")
	var max_dynamic := int(world.get("max_dynamic_bodies", 48))
	if max_dynamic < 2 or max_dynamic > MAX_DYNAMIC_OBJECTS: errors.append("动态物体上限需要2～256")
	if not doc.get("objects", []) is Array: return PackedStringArray(["objects需要数组"])
	var ids: Dictionary = {}
	var dynamic_count := 0
	var fixed_count := 0
	for spec in doc.get("objects", []):
		if not spec is Dictionary: errors.append("物体需要对象数据"); continue
		var structural := false
		for field in ["shape", "transform", "physics", "appearance", "editor"]:
			if not spec.get(field, {}) is Dictionary: errors.append("物体字段需要对象：" + field); structural = true
		if structural: continue
		var id := str(spec.get("id", ""))
		if id.is_empty() or ids.has(id): errors.append("物体ID为空或重复：" + id)
		ids[id] = true
		var shape: Dictionary = spec.get("shape", {})
		var primitive := str(shape.get("primitive", ""))
		var allowed := ["sphere", "box"] if dimensions == 3 else ["circle", "rectangle", "line"]
		if primitive not in allowed: errors.append("不支持的形状：" + primitive)
		if primitive in ["circle", "sphere"]:
			if not _positive(shape.get("radius", 0)) or float(shape.get("radius", 0)) < (0.02 if dimensions == 3 else 1.0): errors.append("半径低于物理最小尺寸：" + id)
		elif not _vector(shape.get("size", []), dimensions) or shape.get("size", []).any(func(n): return float(n) <= 0): errors.append("尺寸无效：" + id)
		elif shape.get("size", []).any(func(n): return float(n) < (0.02 if dimensions == 3 else 1.0)): errors.append("尺寸低于物理最小尺寸：" + id)
		if not _vector(spec.get("transform", {}).get("position", []), dimensions): errors.append("位置无效：" + id)
		var rotation: Variant = spec.get("transform", {}).get("rotation_degrees", [0, 0, 0] if dimensions == 3 else 0)
		if dimensions == 3 and not _vector(rotation, 3): errors.append("三维旋转无效：" + id)
		elif dimensions == 2 and (not (rotation is int or rotation is float) or not is_finite(float(rotation))): errors.append("二维旋转无效：" + id)
		var physics: Dictionary = spec.get("physics", {})
		if not physics.get("material", {}) is Dictionary or not spec.get("appearance", {}).get("generation_color", {}) is Dictionary: errors.append("材质和代际颜色需要对象：" + id)
		if physics.get("mode", "dynamic") not in ["dynamic", "static", "sensor"]: errors.append("物理模式无效：" + id)
		if physics.get("mode", "dynamic") == "dynamic": dynamic_count += 1
		else: fixed_count += 1
		if not _positive(physics.get("mass", 1)): errors.append("质量必须是有限正数：" + id)
		if physics.has("velocity") and not _vector(physics["velocity"], dimensions): errors.append("速度无效：" + id)
		if not spec.get("mechanisms", []) is Array or not spec.get("tags", []) is Array: errors.append("标签和机制引用需要数组：" + id)
	if dynamic_count > max_dynamic: errors.append("初始动态物体超过world.max_dynamic_bodies")
	if fixed_count > MAX_FIXED_OBJECTS: errors.append("静态物体和区域合计不能超过256")
	if not doc.get("mechanisms", []) is Array: return PackedStringArray(["mechanisms需要数组"])
	for rule in doc.get("mechanisms", []):
		if not rule is Dictionary or not rule.get("params", {}) is Dictionary or not rule.get("conditions", {}) is Dictionary: errors.append("机制结构无效"); continue
		if rule.get("type", "") not in ["split_on_contact", "despawn_on_contact", "hit_stop_on_event"]: errors.append("不支持的机制类型")
		if rule.get("type", "") == "split_on_contact" and (int(rule.get("params", {}).get("children_total", 2)) < 2 or int(rule.get("params", {}).get("children_total", 2)) > 100): errors.append("分裂子球总数需要2～100")
		if rule.get("type", "") == "split_on_contact" and not (rule.get("params", {}).get("children_can_split", true) is bool): errors.append("children_can_split需要布尔值true或false")
	var presentation: Dictionary = doc.get("presentation", {})
	for field in ["render", "audio", "effects"]:
		if not presentation.get(field, {}) is Dictionary: errors.append("表现字段需要对象：" + field)
	if not presentation.get("captions", []) is Array: errors.append("文字需要数组")
	else:
		for caption in presentation.get("captions", []):
			if not caption is Dictionary: errors.append("每条文字需要对象数据"); continue
			if not _vector(caption.get("position", [44, 54]), 2): errors.append("文字位置需要二维有限数值")
			var size: Variant = caption.get("font_size", 44)
			if not _positive(size) or float(size) < 8 or float(size) > 256: errors.append("文字字号需要8～256")
	if presentation.get("render", {}) is Dictionary and not presentation.get("render", {}).get("camera", {}) is Dictionary: errors.append("相机需要对象数据")
	return errors

## Only simulation-affecting data invalidates a recorded take.
static func simulation_hash(doc: Dictionary) -> String:
	var copy := doc.duplicate(true)
	for key in ["presentation", "revision", "metadata", "export_preset", "take_settings"]: copy.erase(key)
	for spec in copy.get("objects", []):
		spec.erase("appearance")
		spec.erase("editor")
		spec.erase("name")
	return JSON.stringify(copy, "", true).sha256_text()

## Set dictionary/array paths, allowing the inspector to use one edit protocol.
static func set_field_path(target: Variant, path: String, value: Variant) -> bool:
	var keys := path.split(".")
	var current: Variant = target
	for index in keys.size():
		var key: Variant = int(keys[index]) if current is Array and keys[index].is_valid_int() else keys[index]
		if current is Array:
			if not key is int or key < 0 or key >= current.size(): return false
		elif not current is Dictionary: return false
		if index == keys.size() - 1: current[key] = value; return true
		if current is Dictionary and not current.has(key): current[key] = {}
		current = current[key]
	return false

## Locate only editable initial objects; newborn runtime bodies remain read-only.
static func object_index(doc: Dictionary, id: String) -> int:
	for index in doc.get("objects", []).size():
		if str(doc["objects"][index].get("id", "")) == id: return index
	return -1

## Produce a complete primitive specification for the active dimension.
static func new_object(doc: Dictionary, kind: String, id: String) -> Dictionary:
	var three: bool = doc.get("world", {}).get("dimension", "2d") == "3d"
	var ball := kind == "ball"
	var wall := kind == "wall"
	return {"id": id, "name": {"ball": "球", "box": "方块", "wall": "墙"}.get(kind, "物体"), "tags": ["boundary"] if wall else (["ball", "splitter"] if ball else ["box"]),
		"shape": {"primitive": "sphere" if three else "circle", "radius": 0.44 if three else 18} if ball else {"primitive": "box" if three else "rectangle", "size": ([3, 0.3, 1] if wall else [0.85, 0.65, 0.75]) if three else ([160, 14] if wall else [42, 42])},
		"transform": {"position": [0, 4, 0] if three else [360, 450], "rotation_degrees": [0, 0, 0] if three else 0},
		"physics": {"mode": "static" if wall else "dynamic", "mass": 1, "velocity": [0, 0, 0] if three else [0, 0], "material": {"restitution": 0.75, "friction": 0.15}, "collision_layer": 2 if wall else 1, "collision_mask": 1 if wall else 3, "ccd": true},
		"appearance": {"color": "#42667d" if wall else "#22c55e", "generation_color": {"fade": 0.2}}, "mechanisms": ["split_ball"] if ball else [], "editor": {"locked": false}}

## Check JSON numeric vectors without accepting NaN or malformed dimensions.
static func _vector(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != count: return false
	for number in value:
		if not (number is int or number is float) or not is_finite(float(number)): return false
	return true

## JSON inputs must not smuggle null, strings or infinities into physical dimensions.
static func _positive(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) > 0
