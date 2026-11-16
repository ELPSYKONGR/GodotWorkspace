extends SceneTree
## Exercise the real inspector-to-command-to-physics path across repeated edits.
var results: Dictionary = {}

## Wait until the SceneTree exists before constructing the real workbench.
func _initialize() -> void:
	_run.call_deferred()

## Find a live panel action by its displayed caption.
func _button(node: Node, caption: String) -> Button:
	if node is Button and node.text == caption: return node
	for child in node.get_children():
		var found := _button(child, caption)
		if found != null: return found
	return null

## Locate the numeric property by its adjacent label, as presented to the user.
func _number(node: Node, caption: String) -> SpinBox:
	if node is BoxContainer and node.get_child_count() == 2 and node.get_child(0) is Label:
		if node.get_child(0).text == caption: return node.get_child(1) as SpinBox
	for child in node.get_children():
		var found := _number(child, caption)
		if found != null: return found
	return null

## Reproduce edits, native collisions and keyboard deletion in an isolated project.
func _run() -> void:
	var host = load("res://src/ui/workbench.gd").new()
	root.add_child(host)
	await process_frame
	for operation in ["simulation.pause", "take.stop"]:
		host.service.execute({"op": "simulation.reset"})
		host.service.execute({"op": operation})
		host.service.execute({"op": "simulation.play"})
		for frame in 1200:
			await process_frame
			if host.session.time >= 5: break
		results[operation + "_then_play_splits"] = host.session.stage.world.get_report()["splits"] > 0
		host.service.execute({"op": "simulation.reset"})
		await process_frame
	for count in [2, 4, 100]:
		var field := _number(host.panel.pages["机制"], "每次子球总数")
		field.get_line_edit().text = str(count)
		_button(host.panel.pages["机制"], "应用机制").pressed.emit()
		await process_frame
		results["typed_count_" + str(count)] = host.service.document["mechanisms"][0]["params"]["children_total"] == count
		host.session.play()
		for frame in 1200:
			await process_frame
			if host.session.time >= 5: break
		var report: Dictionary = host.session.stage.world.get_report()
		results["count_physics_" + str(count)] = report["splits"] > 0 if count < 100 else report["splits"] == 0 and report["active"] == 2
		host.service.execute({"op": "simulation.reset"})
		await process_frame
	# Restore two children for policy checks below.
	_number(host.panel.pages["机制"], "每次子球总数").get_line_edit().text = "2"
	_button(host.panel.pages["机制"], "应用机制").pressed.emit()
	await process_frame
	for enabled in [false, true, false, true]:
		var checkbox := _button(host.panel.pages["机制"], "子球继续分裂") as CheckBox
		checkbox.button_pressed = enabled
		_button(host.panel.pages["机制"], "应用机制").pressed.emit()
		await process_frame
		print("APPLIED ", JSON.stringify(host.service.document["mechanisms"]))
		host.service.execute({"op": "simulation.play"})
		for frame in 1200:
			await process_frame
			if host.session.time >= 5: break
		var report: Dictionary = host.session.stage.world.get_report()
		print("REPORT ", JSON.stringify(report))
		results[str(results.size()) + "_" + str(enabled)] = report["splits"] > 0
		host.service.execute({"op": "simulation.reset"})
		await process_frame
	host.selected_id = "ball_A"
	host.panel.sync_document(host.service.document, "ball_A")
	var delete := InputEventKey.new()
	delete.keycode = KEY_DELETE
	delete.pressed = true
	var name_field: LineEdit = host.panel.object_panel.fields["mass"].get_line_edit()
	name_field.grab_focus()
	host._unhandled_key_input(delete)
	results["delete_does_not_remove_while_editing_text"] = host.service.document["objects"].size() == 6
	name_field.release_focus()
	host._unhandled_key_input(delete)
	results["delete_removes_selected_object"] = host.service.document["objects"].size() == 5
	host.service.execute({"op": "history.undo"})
	results["delete_can_be_undone"] = host.service.document["objects"].size() == 6
	# A compact single-parent fixture can physically fit all 100 children.
	var objects: Array = host.service.document["objects"].duplicate(true)
	objects.remove_at(1)
	objects[0]["shape"]["radius"] = 1.0
	objects[0]["transform"]["position"] = [360, 1000]
	host.service.execute({"op": "scene.patch", "args": {"changes": {"objects": objects, "world.max_dynamic_bodies": 100}}})
	_number(host.panel.pages["机制"], "每次子球总数").get_line_edit().text = "100"
	_button(host.panel.pages["机制"], "应用机制").pressed.emit()
	host.session.play()
	for frame in 1200:
		await process_frame
		if host.session.time >= 5: break
	var hundred: Dictionary = host.session.stage.world.get_report()
	results["hundred_children_with_sufficient_space_and_capacity"] = hundred["splits"] == 1 and hundred["active"] == 100 and hundred["ledger_ok"]
	results["passed"] = not results.values().has(false)
	var file := FileAccess.open("res://outputs/split_controls_validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	print(JSON.stringify(results))
	quit(0 if results["passed"] else 1)
