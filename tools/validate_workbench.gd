extends SceneTree
## End-to-end commands drive the real host, recorder, replay and independent producer.
var checks: Array = []
const Document = preload("res://src/document/scene_document.gd")

func _initialize() -> void:
	_run.call_deferred()

## Exercise the UI/AI command route rather than a parallel test implementation.
func _run() -> void:
	var host = load("res://src/ui/workbench.gd").new()
	root.add_child(host)
	await process_frame
	var result: Dictionary = host.service.execute({"op": "object.add", "args": {"kind": "box"}})
	_check("command_updates_host_world", result.get("ok", false) and host.session.stage.world.records.size() == host.service.document["objects"].size())
	result = host.service.execute({"op": "history.undo"})
	_check("undo_rebuilds_initial_world", result.get("ok", false) and host.service.document["objects"].size() == 6)
	var request := "res://outputs/control/inbox/integration_%d.json" % Time.get_ticks_usec()
	var file := FileAccess.open(request, FileAccess.WRITE)
	file.store_string(JSON.stringify({"command_id": request, "op": "object.update", "args": {"id": "ball_A", "changes": {"physics.mass": 2.5}}}))
	file.close()
	host.bridge.poll()
	_check("file_bridge_applies_to_world", host.session.stage.world.records["ball_A"]["spec"]["physics"]["mass"] == 2.5)
	host.service.execute({"op": "object.update", "args": {"id": "ball_A", "changes": {"editor.locked": true}}})
	var locked_before := JSON.stringify(host.session.stage.world.capture_state())
	var spec: Dictionary = host.service.document["objects"][Document.object_index(host.service.document, "ball_A")]
	var point := Vector2(spec["transform"]["position"][0], spec["transform"]["position"][1])
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	host._viewport_input(click, point)
	host._viewport_input(InputEventMouseMotion.new(), point + Vector2(80, 20))
	click.pressed = false
	host._viewport_input(click, point + Vector2(80, 20))
	_check("locked_object_cannot_move_in_preview", locked_before == JSON.stringify(host.session.stage.world.capture_state()))
	host.service.execute({"op": "scene.preset", "args": {"name": "2d"}})
	host.service.execute({"op": "take.record"})
	while host.session.time < 8.0: await process_frame
	result = host.service.execute({"op": "take.stop", "args": {"path": "res://outputs/takes/integration_2d.json"}})
	_check("record_save_native_take", result.get("ok", false) and host.session.take.get_duration() >= 8 and host.session.stage.world.get_report()["splits"] > 0)
	host.service.execute({"op": "take.seek", "args": {"time": 1.0}})
	var expected := JSON.stringify(host.session.stage.world.capture_state())
	var before: int = host.session.take.get_data()["events"].size()
	host.service.execute({"op": "take.seek", "args": {"time": 3.0}})
	host.service.execute({"op": "take.seek", "args": {"time": 1.0}})
	_check("host_seek_no_resimulation", expected == JSON.stringify(host.session.stage.world.capture_state()) and before == host.session.take.get_data()["events"].size())
	var job_name := "workbench_2d_" + str(int(Time.get_unix_time_from_system()))
	result = host.service.execute({"op": "render.enqueue", "args": {"name": job_name, "fps": 30, "frames": 240, "width": 720, "height": 1280, "backend": "gl_compatibility"}})
	_check("independent_job_started", result.get("ok", false))
	var job_directory := str(result.get("path", ""))
	var snapshot_hash := FileAccess.get_sha256(job_directory.path_join("scene.snapshot.json")) if not job_directory.is_empty() else ""
	host.service.execute({"op": "scene.patch", "args": {"changes": {"presentation.captions.0.text": "工作台仍可修改"}}})
	_check("job_snapshot_isolated", FileAccess.get_sha256(job_directory.path_join("scene.snapshot.json")) == snapshot_hash)
	var deadline := Time.get_ticks_msec() + 180000
	while result.get("ok", false) and host.jobs.status().get("state", "") not in ["complete", "failed", "cancelled"] and Time.get_ticks_msec() < deadline:
		await create_timer(0.2).timeout
	_check("independent_production_completed", host.jobs.status().get("state", "") == "complete")
	var validation_path := job_directory.path_join("validation.json")
	var media: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(validation_path)) if FileAccess.file_exists(validation_path) else {}
	_check("complete_video_audio_decode_verified", media.get("passed", false))
	result = host.service.execute({"op": "render.enqueue", "args": {"name": "invalid_backend", "fps": 30, "frames": 30, "backend": "invented"}})
	_check("unsupported_backend_rejected_before_launch", not result.get("ok", true))
	var report := {"checks": checks, "passed": checks.all(func(check): return check["passed"]), "job_directory": job_directory}
	var output := FileAccess.open("res://outputs/workbench_validation.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	print("WORKBENCH_VALIDATION " + JSON.stringify(report))
	host.session.audio.stop_all()
	await create_timer(0.2).timeout
	quit(0 if report["passed"] else 1)

## Preserve every outcome in the machine-readable report.
func _check(name: String, passed: bool) -> void:
	checks.append({"name": name, "passed": passed})
