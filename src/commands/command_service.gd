extends RefCounted
## One revisioned edit route for both native controls and AI command files.
const Document = preload("res://src/document/scene_document.gd")
signal completed(result: Dictionary)
var document: Dictionary = {}
var history: Array[Dictionary] = []
var future: Array[Dictionary] = []
var receipts: Dictionary = {}
var runtime_handler: Callable

## Replace the document after validation; retain history when requested.
func initialize(doc: Dictionary, handler: Callable) -> void:
	document = doc.duplicate(true)
	runtime_handler = handler

## Idempotent commands reject stale revisions before any mutation.
func execute(command: Dictionary) -> Dictionary:
	var id := str(command.get("command_id", ""))
	if not id.is_empty() and receipts.has(id): return receipts[id]
	var revision := int(document.get("revision", 1))
	var result: Dictionary
	if not command.get("args", {}) is Dictionary:
		result = {"ok": false, "error": "命令args需要对象数据"}
	elif command.has("base_revision") and not (command["base_revision"] is int or command["base_revision"] is float):
		result = {"ok": false, "error": "base_revision需要数值"}
	elif int(command.get("base_revision", revision)) != revision:
		result = {"ok": false, "error": "场景版本冲突，请读取最新scene.current.json"}
	else:
		var op := str(command.get("op", ""))
		var args: Dictionary = command.get("args", {})
		if op == "history.undo" or op == "history.redo": result = _history(op == "history.undo")
		elif op in ["scene.patch", "object.add", "object.update", "object.remove", "object.duplicate", "object.arrange"]: result = _edit(op, args)
		else: result = runtime_handler.call(op, args)
	result["command_id"] = id
	result["revision"] = int(document.get("revision", revision))
	if not id.is_empty(): receipts[id] = result.duplicate(true)
	completed.emit(result)
	return result

## Validate a whole editing transaction before making it visible.
func _edit(op: String, args: Dictionary) -> Dictionary:
	if op in ["scene.patch", "object.update"] and not args.get("changes", {}) is Dictionary:
		return {"ok": false, "error": "changes需要字段路径到值的对象数据"}
	var next := document.duplicate(true)
	var index := Document.object_index(next, str(args.get("id", args.get("object_id", ""))))
	if op == "scene.patch":
		for path in args.get("changes", {}):
			if not Document.set_field_path(next, path, args["changes"][path]): return {"ok": false, "error": "无效字段路径：" + path}
	elif op == "object.add":
		var id := "object_" + str(Time.get_ticks_usec())
		next["objects"].append(Document.new_object(next, str(args.get("kind", "ball")), id))
	elif op == "object.arrange":
		var serial := 0
		var three: bool = next["world"]["dimension"] == "3d"
		for spec in next["objects"]:
			if spec.get("physics", {}).get("mode", "dynamic") != "dynamic" or spec.get("editor", {}).get("locked", false): continue
			var column := serial % 4 if args.get("mode", "row") == "grid" else serial
			var row := serial / 4 if args.get("mode", "row") == "grid" else 0
			spec["transform"]["position"] = [-2.5 + column * 1.3, 3.0 + row * 1.2, 0] if three else [120 + column * 120, 400 + row * 90]
			serial += 1
	else:
		if index < 0: return {"ok": false, "error": "请选择初始场景物体；运行中新生物体只读"}
		if next["objects"][index].get("editor", {}).get("locked", false) and not (op == "object.update" and args.get("changes", {}).keys() == ["editor.locked"]): return {"ok": false, "error": "物体已锁定"}
		if op == "object.remove": next["objects"].remove_at(index)
		elif op == "object.duplicate":
			var copy: Dictionary = next["objects"][index].duplicate(true)
			copy["id"] = str(copy["id"]) + "_copy_" + str(Time.get_ticks_usec())
			copy["name"] = str(copy.get("name", "物体")) + "副本"
			copy["transform"]["position"][0] += 1.0 if next["world"]["dimension"] == "3d" else 45
			next["objects"].append(copy)
		elif op == "object.update":
			for path in args.get("changes", {}):
				if not Document.set_field_path(next["objects"][index], path, args["changes"][path]): return {"ok": false, "error": "无效物体字段：" + path}
	var errors := Document.validate(next)
	if not errors.is_empty(): return {"ok": false, "error": "；".join(errors)}
	var stale := Document.simulation_hash(next) != Document.simulation_hash(document)
	history.append(document.duplicate(true))
	if history.size() > 50: history.pop_front()
	future.clear()
	next["revision"] = int(document.get("revision", 1)) + 1
	document = next
	return {"ok": true, "changed": true, "requires_reset": stale, "message": "物理数据已应用，初始布局已重置" if stale else "表现参数已应用，可复用轨迹"}

## Undo edits, not physical history, and keep revisions monotonically increasing.
func _history(undo: bool) -> Dictionary:
	var source := history if undo else future
	var destination := future if undo else history
	if source.is_empty(): return {"ok": false, "error": "没有可撤销/重做的编辑"}
	destination.append(document.duplicate(true))
	var revision := int(document.get("revision", 1)) + 1
	document = source.pop_back()
	document["revision"] = revision
	return {"ok": true, "changed": true, "requires_reset": true, "message": "已恢复初始场景编辑"}
