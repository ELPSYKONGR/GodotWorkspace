extends Node
## Native editor host: all user and AI operations share CommandService.
const Document = preload("res://src/document/scene_document.gd")
const Commands = preload("res://src/commands/command_service.gd")
const Session = preload("res://src/runtime/scene_session.gd")
const UI = preload("res://src/ui/workbench_ui.gd")
const Bridge = preload("res://src/commands/file_bridge.gd")
const Jobs = preload("res://src/production/job_queue.gd")
const Workspace = preload("res://src/document/scene_workspace.gd")
var workspace = Workspace.new()
var service = Commands.new()
var bridge = Bridge.new()
var jobs = Jobs.new()
var session: Node
var panel: Control
var viewport: SubViewport
var selected_id := ""
var message := "就绪：先布置，再运行或录制。"
var message_is_error := false
var output_fps := 30
var scene_path := "res://config/workbench_2d.json"
var poll_time := 0.0
var dragging := false
var drag_position: Array = []
var drag_offset: Array = []
var drag_moved := false
var snapshot_path := ""
var exit_after_snapshot := false

## Fixed logical video viewport stays separate from the resizable workbench UI.
func _ready() -> void:
	get_window().title = "解压视频工作台 · Godot"
	get_window().content_scale_size = Vector2i(1440, 900)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_window().min_size = Vector2i(1100, 720)
	get_window().size = Vector2i(1440, 900)
	Engine.max_fps = 60
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="): scene_path = arg.trim_prefix("--scene=")
		elif arg.begins_with("--snapshot="): snapshot_path = arg.trim_prefix("--snapshot="); exit_after_snapshot = true
	var loaded := Document.load_file(scene_path)
	if not loaded["ok"]: push_error(loaded["error"]); get_tree().quit(2); return
	service.initialize(loaded["document"], _runtime_command)
	workspace.initialize(service.document, scene_path)
	service.completed.connect(_after_command)
	viewport = SubViewport.new()
	viewport.size = Vector2i(720, 1280)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	session = Session.new()
	viewport.add_child(session)
	session.load_document(service.document)
	panel = UI.new()
	panel.setup(service.document, viewport.get_texture())
	panel.command_requested.connect(_from_ui)
	panel.viewport_input.connect(_viewport_input)
	add_child(panel)
	_sync_scene_file()
	bridge.setup(service)
	if not snapshot_path.is_empty(): _snapshot_after_ready.call_deferred()

## The bridge and status refresh remain active during physical pause and replay.
func _process(delta: float) -> void:
	if not is_instance_valid(session): return
	poll_time += delta
	if poll_time < 0.2: return
	poll_time = 0
	bridge.poll()
	var info: Dictionary = session.get_info()
	if not str(info.get("last_error", "")).is_empty():
		message = str(info["last_error"])
		message_is_error = true
	var job: Dictionary = jobs.status()
	info.merge({"selected_id": selected_id, "last_message": message, "last_message_is_error": message_is_error, "job_status": JSON.stringify(job), "output_fps": output_fps}, true)
	panel.update_runtime(info)
	bridge.publish(info)

## UI edits become revisioned commands just like AI files.
func _from_ui(op: String, args: Dictionary) -> void:
	service.execute({"op": op, "args": args})

## Apply data changes once; presentation edits never reset physical trajectories.
func _after_command(result: Dictionary) -> void:
	message = str(result.get("message", result.get("error", "完成")))
	message_is_error = not result.get("ok", false)
	if result.get("changed", false):
		if result.get("requires_reset", false): session.load_document(service.document)
		else: session.apply_presentation(service.document)
		panel.sync_document(service.document, selected_id)
		bridge.publish(session.get_info())
	elif result.get("refresh_document", false): panel.sync_document(service.document, selected_id)
	panel.show_message(message, not result.get("ok", false))
	_sync_scene_file()
	panel.update_play_button(session.get_info())
	panel.scene_bar.operation_finished(result)

## File identity belongs to the document workspace, not the simulation or its Take.
func _sync_scene_file() -> void:
	panel.scene_bar.sync(workspace.path, workspace.is_dirty(service.document), service.document)
	get_window().title = "%s%s · 解压视频工作台" % ["* " if workspace.is_dirty(service.document) else "", workspace.path.get_file() if not workspace.path.is_empty() else str(service.document.get("metadata", {}).get("title", "未命名场景"))]

## Delete uses the same validated, undoable command as the object inspector.
func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or event.keycode != KEY_DELETE: return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	if selected_id.is_empty(): return
	_from_ui("object.remove", {"id": selected_id})
	get_viewport().set_input_as_handled()

## Dispatch runtime commands without giving panels ownership of world nodes.
func _runtime_command(op: String, args: Dictionary) -> Dictionary:
	match op:
		"scene.new":
			return _replace_scene(workspace.create_scene(str(args.get("name", "2d")), bool(args.get("blank", false))))
		"scene.preset":
			var kind := str(args.get("name", "2d"))
			if not Workspace.TYPES.has(kind): return {"ok": false, "error": "未知场景类型"}
			return _replace_scene(workspace.open_scene("res://config/workbench_" + kind + ".json"))
		"scene.load": return _replace_scene(workspace.open_scene(str(args.get("path", ""))))
		"scene.save":
			var result: Dictionary = workspace.save_scene(str(args.get("path", "")), service.document)
			result["scene_saved"] = result.get("ok", false)
			return result
		"scene.validate": return {"ok": Document.validate(service.document).is_empty(), "message": "场景数据校验完成"}
		"object.select":
			selected_id = str(args.get("id", ""))
			session.stage.world.set_debug(true, selected_id)
			return {"ok": true, "message": "选中：" + selected_id}
		"simulation.toggle":
			if session.get_info()["running"]: session.pause()
			else: session.play()
		"simulation.play": session.play()
		"simulation.pause": session.pause()
		"simulation.step": session.step_once()
		"simulation.reset", "simulation.edit": session.load_document(service.document)
		"take.record": session.start_recording()
		"take.stop":
			session.stop_recording()
			return _save_take(str(args.get("path", "res://outputs/takes/latest.json")))
		"take.save": return _save_take(str(args.get("path", "res://outputs/takes/latest.json")))
		"take.load":
			var error: Error = session.take.load_take(str(args.get("path", "res://outputs/takes/latest.json")))
			if error != OK: return {"ok": false, "error": session.take.last_error}
			if Document.simulation_hash(service.document) != Document.simulation_hash(session.take.get_data()["scene"]):
				var revision := int(service.document.get("revision", 1)) + 1
				service.document = session.take.get_data()["scene"].duplicate(true)
				service.document["revision"] = revision
				# A Take importing another scene must not inherit the previous file's destination.
				workspace.path = ""
				workspace.saved_signature = ""
				session.load_document(service.document)
			session.seek(0)
			return {"ok": true, "refresh_document": true, "message": "轨迹已加载；使用匹配的物理场景"}
		"take.seek":
			if not session.seek(float(args.get("time", 0))): return {"ok": false, "error": session.last_error}
		"audio.audition": session.audio.audition()
		"render.enqueue":
			if session.mode == "recording": session.stop_recording()
			if session.get_info().get("take_stale", false): return {"ok": false, "error": "轨迹与物理设置不符，请重新录制"}
			output_fps = int(args.get("fps", 30))
			return jobs.enqueue(service.document, session.take.get_data(), args)
		"render.cancel": return jobs.cancel()
		"render.open_output": OS.shell_open(jobs.directory if not jobs.directory.is_empty() else ProjectSettings.globalize_path("res://outputs/jobs"))
		"preview.snapshot":
			var path := ProjectSettings.globalize_path(str(args.get("path", "res://outputs/control/preview.png")))
			var error := viewport.get_texture().get_image().save_png(path)
			return {"ok": error == OK, "path": path}
		_: return {"ok": false, "error": "未知命令：" + op}
	return {"ok": true, "message": "已执行：" + op}

## Load only validated v2 scene data and preserve the previous take for comparison.
func _replace_scene(result: Dictionary) -> Dictionary:
	if not result["ok"]: return result
	service.history.append(service.document.duplicate(true))
	if service.history.size() > 50: service.history.pop_front()
	service.future.clear()
	var revision := int(service.document.get("revision", 1)) + 1
	service.document = result["document"]
	service.document["revision"] = revision
	selected_id = ""
	dragging = false
	return {"ok": true, "changed": true, "requires_reset": true, "message": "已打开场景：" + workspace.path if not workspace.path.is_empty() else "已新建场景，请编辑后保存"}

## Keep both latest and uniquely named takes so subsequent recordings are recoverable.
func _save_take(path: String) -> Dictionary:
	var error: Error = session.take.save(path)
	if error != OK: return {"ok": false, "error": session.take.last_error}
	var archive := "res://outputs/takes/take_%d.json" % Time.get_ticks_usec()
	session.take.save(archive)
	return {"ok": true, "message": "轨迹已保存：" + path, "path": ProjectSettings.globalize_path(path)}

## Picking and drag placement share logical coordinates across preview sizes.
func _viewport_input(event: InputEvent, point: Vector2) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			selected_id = session.stage.world.pick(point)
			session.stage.world.set_debug(true, selected_id)
			panel.sync_document(service.document, selected_id)
			dragging = session.mode == "edit" and Document.object_index(service.document, selected_id) >= 0
			drag_moved = false
			if dragging:
				var index := Document.object_index(service.document, selected_id)
				if service.document["objects"][index].get("editor", {}).get("locked", false):
					dragging = false
					return
				drag_position = service.document["objects"][index]["transform"]["position"].duplicate()
				var anchor: Array = session.stage.world.placement_position(point, selected_id)
				drag_offset.clear()
				for axis in anchor.size(): drag_offset.append(float(drag_position[axis]) - float(anchor[axis]))
		elif dragging:
			dragging = false
			if drag_moved: _from_ui("object.update", {"id": selected_id, "changes": {"transform.position": drag_position}})
	elif event is InputEventMouseMotion and dragging:
		drag_position = session.stage.world.placement_position(point, selected_id)
		for axis in drag_position.size(): drag_position[axis] += drag_offset[axis]
		drag_moved = true
		var states: Array = session.stage.world.capture_state()
		for state in states:
			if state["id"] == selected_id: state["position"] = drag_position
		session.stage.world.apply_state(states, session.stage.world.get_definitions())

## A GPU-rendered screenshot makes startup/layout reproducible without OS input scripts.
func _snapshot_after_ready() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(snapshot_path)
	if exit_after_snapshot: get_tree().quit()
