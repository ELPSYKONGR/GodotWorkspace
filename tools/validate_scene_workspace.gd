extends SceneTree
## Exercise scene dialogs through the real command host in an isolated project copy.
var results: Dictionary = {}
const Document = preload("res://src/document/scene_document.gd")

func _initialize() -> void:
	_run.call_deferred()

## UI actions, native worlds and disk round trips must agree for every template.
func _run() -> void:
	var host = load("res://src/ui/workbench.gd").new()
	root.add_child(host)
	await process_frame
	var bar = host.panel.scene_bar
	var directory := "res://outputs/scene_workspace_validation"
	DirAccess.make_dir_recursive_absolute(directory)
	var all_types := true
	for index in host.workspace.TYPES.size():
		bar.dirty = false
		bar.type_choice.select(index)
		bar.examples.button_pressed = true
		bar.new_dialog.confirmed.emit()
		var kind: String = host.workspace.TYPES.keys()[index]
		var doc: Dictionary = host.service.document
		all_types = all_types and Document.validate(doc).is_empty() and host.workspace.path.is_empty() and bar.dirty
		if kind in ["3d", "perspective"]:
			var projection := Camera3D.PROJECTION_ORTHOGONAL if kind == "3d" else Camera3D.PROJECTION_PERSPECTIVE
			all_types = all_types and host.session.stage.world.camera.projection == projection
		else:
			all_types = all_types and host.session.stage.world.dimensions == 2
		var destination := directory.path_join(kind + ".json")
		var save: Dictionary = host.service.execute({"op": "scene.save", "args": {"path": destination}})
		var saved := Document.load_file(destination)
		all_types = all_types and save["ok"] and not bar.dirty and saved["ok"] and saved["document"]["objects"].size() == doc["objects"].size()
		# Full/locked templates can still edit scene metadata without adding or unlocking bodies.
		host.service.execute({"op": "scene.patch", "args": {"changes": {"metadata.title": str(doc["metadata"]["title"]) + "_dirty"}}})
		all_types = all_types and bar.dirty
		host.service.execute({"op": "scene.load", "args": {"path": destination}})
		all_types = all_types and not bar.dirty and host.session.stage.world.records.size() == saved["document"]["objects"].size()
	results["all_six_types_create_save_reopen_native_worlds"] = all_types
	var file_path: String = host.workspace.path
	var saved_doc := JSON.stringify(host.service.document)
	var signature: String = host.workspace.saved_signature
	# A malformed input cannot change the current document or saved destination.
	var bad := FileAccess.open(directory.path_join("bad.json"), FileAccess.WRITE)
	bad.store_string("{bad}")
	bad.close()
	var failure: Dictionary = host.service.execute({"op": "scene.load", "args": {"path": directory.path_join("bad.json")}})
	results["invalid_open_preserves_scene_and_path"] = not failure["ok"] and file_path == host.workspace.path and saved_doc == JSON.stringify(host.service.document)
	var template_path := "res://config/workbench_glass.json"
	var template_hash := FileAccess.get_sha256(template_path)
	failure = host.service.execute({"op": "scene.save", "args": {"path": ProjectSettings.globalize_path(template_path)}})
	results["built_in_template_cannot_be_overwritten"] = not failure["ok"] and template_hash == FileAccess.get_sha256(template_path) and file_path == host.workspace.path
	# Undo to the saved data clears dirty despite a newer command revision.
	host.service.execute({"op": "object.add", "args": {"kind": "ball"}})
	results["edits_mark_unsaved"] = bar.dirty and bar.title.text.begins_with("* ")
	host.service.execute({"op": "history.undo"})
	results["undo_to_saved_clears_dirty"] = not bar.dirty and signature == host.workspace.signature(host.service.document)
	# The same dialog guards new and open; cancel never dispatches a replacement.
	host.service.execute({"op": "object.add", "args": {"kind": "ball"}})
	var before := JSON.stringify(host.service.document)
	bar.request_replace("scene.new", {"name": "2d", "blank": true})
	results["dirty_switch_waits_for_decision"] = bar.unsaved_dialog.visible and before == JSON.stringify(host.service.document)
	bar.unsaved_dialog.hide()
	bar.unsaved_dialog.canceled.emit()
	results["cancel_preserves_scene"] = bar.pending.is_empty() and before == JSON.stringify(host.service.document)
	bar.request_replace("scene.new", {"name": "perspective", "blank": true})
	bar.unsaved_dialog.confirmed.emit()
	results["save_then_switch_keeps_previous_edits"] = Document.load_file(file_path)["document"]["objects"] == JSON.parse_string(before)["objects"] and host.service.document["objects"].is_empty() and host.service.document["world"]["dimension"] == "3d" and bar.dirty and host.workspace.path.is_empty()
	bar.unsaved_dialog.hide()
	# New scenes need a filename; canceling Save As also cancels the pending switch.
	bar.request_replace("scene.new", {"name": "glass"})
	bar.unsaved_dialog.confirmed.emit()
	results["unsaved_scene_requests_save_picker"] = bar.file_dialog.visible and host.service.document["objects"].is_empty()
	bar.file_dialog.hide()
	bar.file_dialog.canceled.emit()
	bar.unsaved_dialog.hide()
	results["cancel_save_picker_cancels_switch"] = bar.pending.is_empty() and host.service.document["objects"].is_empty()
	bar.request_replace("scene.new", {"name": "glass"})
	bar.unsaved_dialog.custom_action.emit("discard")
	results["discard_then_switch_opens_glass"] = host.service.document["objects"].size() == 13 and host.workspace.path.is_empty()
	# Save failures keep the current document and never continue the pending switch.
	bar.current_path = directory.path_join("invalid.txt")
	before = JSON.stringify(host.service.document)
	bar.request_replace("scene.new", {"name": "2d"})
	bar.unsaved_dialog.confirmed.emit()
	results["save_failure_prevents_switch"] = bar.pending.is_empty() and before == JSON.stringify(host.service.document) and host.workspace.path.is_empty()
	bar.unsaved_dialog.hide()
	# Actual picker selection supports Chinese names, and ordinary Save reuses it.
	bar.file_action = "save"
	bar.file_dialog.file_selected.emit(ProjectSettings.globalize_path(directory.path_join("我的玻璃场景.json")))
	var chinese_path: String = host.workspace.path
	results["save_as_updates_active_path"] = chinese_path.ends_with("我的玻璃场景.json") and not bar.dirty
	host.service.execute({"op": "scene.patch", "args": {"changes": {"presentation.render.background": "#112233"}}})
	bar.save()
	results["ordinary_save_updates_same_file"] = not bar.dirty and Document.load_file(chinese_path)["document"]["presentation"]["render"]["background"] == "#112233"
	# Running bodies do not overwrite the initial document when saving.
	var initial: String = host.workspace.signature(host.service.document)
	host.service.execute({"op": "simulation.play"})
	for frame in 15: await physics_frame
	bar.save()
	results["save_during_simulation_keeps_initial_layout"] = initial == host.workspace.signature(Document.load_file(chinese_path)["document"])
	host.service.execute({"op": "take.record"})
	for frame in 10: await physics_frame
	host.service.execute({"op": "take.stop", "args": {"path": directory.path_join("motion.take.json")}})
	host.service.execute({"op": "scene.new", "args": {"name": "3d", "blank": true}})
	host.service.execute({"op": "scene.save", "args": {"path": directory.path_join("blank_3d.json")}})
	host.service.execute({"op": "take.load", "args": {"path": directory.path_join("motion.take.json")}})
	results["take_import_cannot_overwrite_previous_scene_file"] = host.workspace.path.is_empty() and bar.dirty and host.service.document["world"]["dimension"] == "2d" and Document.load_file(directory.path_join("blank_3d.json"))["document"]["objects"].is_empty()
	results["passed"] = not results.values().has(false)
	var report := FileAccess.open("res://outputs/scene_workspace_validation.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(results, "\t"))
	print("SCENE_WORKSPACE_VALIDATION ", JSON.stringify(results))
	for child in root.get_children(): child.queue_free()
	var deadline := Time.get_ticks_msec() + 100
	while Time.get_ticks_msec() < deadline: await process_frame
	quit(0 if results["passed"] else 1)
