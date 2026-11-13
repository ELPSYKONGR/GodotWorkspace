extends SceneTree
## Exercise the same command service used by the workbench and AI command files.

const Commands = preload("res://src/commands/command_service.gd")
const Document = preload("res://src/document/scene_document.gd")
var base: Dictionary = {}
var results: Array = []
var serial := 0


## Check edit transactions independently from the native interface widgets.
func _initialize() -> void:
	base = JSON.parse_string(FileAccess.get_file_as_string("res://config/workbench_2d.json"))
	_run.call_deferred()


## Validate editing behavior, failure atomicity and take-invalidation decisions.
func _run() -> void:
	var service = _service()
	var count: int = service.document["objects"].size()
	var added: Dictionary = _execute(service, "object.add", {"kind": "box"})
	var added_id: String = service.document["objects"][-1]["id"]
	var copied: Dictionary = _execute(service, "object.duplicate", {"id": "ball_A"})
	var copy_id: String = service.document["objects"][-1]["id"]
	var removed: Dictionary = _execute(service, "object.remove", {"id": added_id})
	_check("add_duplicate_remove", added["ok"] and copied["ok"] and removed["ok"] and service.document["objects"].size() == count + 1 and Document.object_index(service.document, added_id) < 0 and copy_id != "ball_A" and Document.object_index(service.document, copy_id) >= 0)
	service = _service()
	var initial: Array = service.document["objects"][0]["transform"]["position"].duplicate()
	var moved: Dictionary = _execute(service, "object.update", {"id": "ball_A", "changes": {"transform.position": [300, 500]}})
	var revision_after_move: int = service.document["revision"]
	var undone: Dictionary = _execute(service, "history.undo", {})
	var restored: bool = service.document["objects"][0]["transform"]["position"] == initial
	var revision_after_undo: int = service.document["revision"]
	var redone: Dictionary = _execute(service, "history.redo", {})
	_check("undo_redo_and_revision", moved["ok"] and undone["ok"] and redone["ok"] and restored and service.document["objects"][0]["transform"]["position"] == [300, 500] and revision_after_undo > revision_after_move and int(service.document["revision"]) > revision_after_undo)
	service = _service()
	var before := JSON.stringify(service.document)
	var conflict: Dictionary = service.execute({"command_id": "conflict", "base_revision": 0, "op": "object.remove", "args": {"id": "ball_A"}})
	_check("stale_revision_rejected_atomically", not conflict["ok"] and before == JSON.stringify(service.document))
	var idempotent := {"command_id": "only_add_once", "base_revision": service.document["revision"], "op": "object.add", "args": {"kind": "ball"}}
	var first: Dictionary = service.execute(idempotent)
	var after_first := JSON.stringify(service.document)
	var history_count: int = service.history.size()
	var second: Dictionary = service.execute(idempotent)
	_check("command_id_is_idempotent", first["ok"] and first == second and after_first == JSON.stringify(service.document) and history_count == service.history.size())
	service = _service()
	before = JSON.stringify(service.document)
	var negative: Dictionary = _execute(service, "object.update", {"id": "ball_A", "changes": {"shape.radius": -1}})
	_check("negative_radius_rejected_atomically", not negative["ok"] and before == JSON.stringify(service.document))
	var wrong_vector: Dictionary = _execute(service, "object.update", {"id": "floor", "changes": {"shape.size": [100]}})
	_check("wrong_size_dimensions_rejected_atomically", not wrong_vector["ok"] and before == JSON.stringify(service.document))
	var original_hash := Document.simulation_hash(service.document)
	var appearance: Dictionary = _execute(service, "object.update", {"id": "ball_A", "changes": {"appearance.color": "#3b82f6"}})
	var caption: Dictionary = _execute(service, "scene.patch", {"changes": {"presentation.captions.0.text": "命令验证标题"}})
	_check("presentation_reuses_simulation_take", appearance["ok"] and caption["ok"] and not appearance["requires_reset"] and not caption["requires_reset"] and original_hash == Document.simulation_hash(service.document))
	service = _service()
	var arranged: Dictionary = _execute(service, "object.arrange", {"mode": "row"})
	var a: Array = service.document["objects"][0]["transform"]["position"]
	var b: Array = service.document["objects"][1]["transform"]["position"]
	_check("row_arrangement", arranged["ok"] and a[1] == b[1] and absf(float(b[0]) - float(a[0]) - 120) < 0.001)
	service = _service()
	service.document["objects"][0]["editor"]["locked"] = true
	before = JSON.stringify(service.document)
	var locked: Dictionary = _execute(service, "object.update", {"id": "ball_A", "changes": {"transform.position": [300, 500]}})
	_check("locked_object_update_rejected", not locked["ok"] and before == JSON.stringify(service.document))
	var locked_position: Array = service.document["objects"][0]["transform"]["position"].duplicate()
	_execute(service, "object.arrange", {"mode": "grid"})
	_check("arrangement_preserves_locked_objects", service.document["objects"][0]["transform"]["position"] == locked_position)
	service = _service()
	var nonfinite: Dictionary = _execute(service, "object.update", {"id": "ball_A", "changes": {"shape.radius": INF}})
	_check("nonfinite_radius_rejected", not nonfinite["ok"])
	before = JSON.stringify(service.document)
	var malformed_args: Dictionary = service.execute({"op": "object.update", "args": []})
	var malformed_changes: Dictionary = service.execute({"op": "scene.patch", "args": {"changes": []}})
	_check("malformed_commands_return_errors_atomically", not malformed_args["ok"] and not malformed_changes["ok"] and before == JSON.stringify(service.document))
	var malformed_caption: Dictionary = _execute(service, "scene.patch", {"changes": {"presentation.captions": [123]}})
	_check("invalid_caption_rejected_before_rendering", not malformed_caption["ok"] and before == JSON.stringify(service.document))
	var passed := true
	for result in results: passed = passed and bool(result["passed"])
	var file := FileAccess.open("res://outputs/commands_validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": passed, "cases": results}, "\t"))
	print("COMMANDS_VALIDATION " + JSON.stringify({"passed": passed, "cases": results}))
	quit(0 if passed else 1)


## Use an inert runtime handler because this suite exercises document edits only.
func _service():
	var service = Commands.new()
	service.initialize(base, func(_op, _args): return {"ok": false, "error": "not an edit"})
	return service


## Submit a unique revision-aware command through the real public entry point.
func _execute(service, op: String, args: Dictionary) -> Dictionary:
	serial += 1
	return service.execute({"command_id": "test_%d" % serial, "base_revision": service.document["revision"], "op": op, "args": args})


## Keep check results separate from command receipts for an independent report.
func _check(label: String, passed: bool) -> void:
	results.append({"name": label, "passed": passed})
