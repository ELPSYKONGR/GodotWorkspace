extends Node
## Render an immutable take into a clean offscreen viewport using the real GPU.
const Session = preload("res://src/runtime/scene_session.gd")
var directory := ""
var job: Dictionary
var session: Node
var viewport: SubViewport
var index := 0
var busy := false

## The worker never builds workbench controls or runs the physical solver.
func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--job="): directory = arg.trim_prefix("--job=")
	if directory.is_empty(): push_error("Missing --job"); get_tree().quit(2); return
	job = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("job.json")))
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("scene.snapshot.json")))
	doc["presentation"]["render"]["debug"] = false
	viewport = SubViewport.new()
	viewport.size = Vector2i(int(job["width"]), int(job["height"]))
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	session = Session.new()
	viewport.add_child(session)
	session.load_document(doc, float(job["width"]) / 720.0)
	if session.take.load_take(directory.path_join("take.json")) != OK:
		push_error(session.take.last_error); get_tree().quit(3); return
	session.seek(0)
	session.stage.world.set_debug(false, "")
	DirAccess.make_dir_recursive_absolute(directory.path_join("frames"))

## Each saved frame samples the same take at i/FPS; render speed has no effect.
func _process(_delta: float) -> void:
	if busy or not is_instance_valid(session): return
	busy = true
	if FileAccess.file_exists(directory.path_join("cancel.request")): get_tree().quit(5); return
	if index >= int(job["frames"]):
		session.audio.stop_all()
		_status("rendered")
		get_tree().quit()
		return
	session.seek(index / float(job["fps"]))
	session.stage.world.set_debug(false, "")
	await RenderingServer.frame_post_draw
	var error := viewport.get_texture().get_image().save_png(directory.path_join("frames/frame_%07d.png" % index))
	if error != OK: push_error("PNG save failed: " + str(error)); get_tree().quit(4); return
	index += 1
	if index % 10 == 0: _status("rendering")
	busy = false

## Publish the current phase without exposing half-written JSON to the UI.
func _status(state: String) -> void:
	var target := directory.path_join("status.json")
	var temporary := target + ".renderer.tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	file.store_string(JSON.stringify({"state": state, "frame": index, "total": int(job["frames"])}))
	file.close()
	DirAccess.rename_absolute(temporary, target)
