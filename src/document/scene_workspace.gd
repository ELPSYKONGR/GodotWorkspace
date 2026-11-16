extends RefCounted
## User scene identity and safe persistence; built-in examples remain reusable templates.
const Document = preload("res://src/document/scene_document.gd")
const TYPES := {"2d": "二维", "3d": "正交三维", "perspective": "透视三维", "glass": "玻璃演示", "neon": "荧光演示", "long": "纵向长场景", "devices": "机关演示"}
var path := ""
var saved_signature := ""

## Revision is command bookkeeping, not a user edit.
func signature(doc: Dictionary) -> String:
	var copy := doc.duplicate(true)
	copy.erase("revision")
	return JSON.stringify(copy).sha256_text()

## Built-in examples open without a writable destination.
func initialize(doc: Dictionary, source: String) -> void:
	path = "" if is_template(source) else ProjectSettings.globalize_path(source).simplify_path()
	saved_signature = signature(doc)

## Compare actual content so undo back to the saved state clears the marker.
func is_dirty(doc: Dictionary) -> bool:
	return signature(doc) != saved_signature

## Resolve only registered types, then optionally remove example content.
func create_scene(kind: String, blank: bool) -> Dictionary:
	if not TYPES.has(kind): return {"ok": false, "error": "未知场景类型"}
	var result := Document.load_file("res://config/workbench_" + kind + ".json")
	if not result["ok"]: return result
	var doc: Dictionary = result["document"]
	doc["scene_id"] = "scene_%d" % Time.get_ticks_usec()
	doc["metadata"]["title"] = "未命名 · " + TYPES[kind]
	if blank:
		doc["objects"] = []
		doc["mechanisms"] = []
		doc["presentation"]["captions"] = []
		doc["presentation"]["glass_counter"] = false
		if doc["presentation"]["render"].get("camera", {}).has("target_root"): doc["presentation"]["render"]["camera"]["target_root"] = ""
	path = ""
	saved_signature = ""
	return result

## Only a validated file becomes the active saved baseline.
func open_scene(source: String) -> Dictionary:
	if not FileAccess.file_exists(source): return {"ok": false, "error": "场景文件不存在：" + source}
	var result := Document.load_file(source)
	if result["ok"]: initialize(result["document"], source)
	return result

## Write beside the destination and atomically replace it after a successful flush.
func save_scene(destination: String, doc: Dictionary) -> Dictionary:
	if destination.is_empty(): destination = path
	if not destination.begins_with("res://") and not destination.is_absolute_path(): return {"ok": false, "error": "请选择工程内或绝对路径"}
	if destination.get_extension().to_lower() != "json": return {"ok": false, "error": "场景文件需要.json扩展名"}
	if is_template(destination): return {"ok": false, "error": "内置示例请另存为新场景"}
	var errors := Document.validate(doc)
	if not errors.is_empty(): return {"ok": false, "error": "；".join(errors)}
	var absolute := ProjectSettings.globalize_path(destination).simplify_path()
	var error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if error != OK: return {"ok": false, "error": "无法创建场景目录"}
	var temporary := absolute + ".%d.tmp" % Time.get_ticks_usec()
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return {"ok": false, "error": "无法保存：" + absolute}
	file.store_string(JSON.stringify(doc, "\t"))
	file.flush()
	error = file.get_error()
	file.close()
	if error == OK: error = DirAccess.rename_absolute(temporary, absolute)
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return {"ok": false, "error": "场景保存失败，原文件已保留：" + absolute}
	path = absolute
	saved_signature = signature(doc)
	return {"ok": true, "message": "已保存场景：" + path, "path": path}

## Compare normalized absolute paths, including callers using res:// aliases.
func is_template(source: String) -> bool:
	var absolute := ProjectSettings.globalize_path(source).simplify_path().to_lower()
	for kind in TYPES:
		if absolute == ProjectSettings.globalize_path("res://config/workbench_" + kind + ".json").simplify_path().to_lower(): return true
	return false
