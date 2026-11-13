extends SceneTree
## CLI production reuses the same frozen-input queue as the native workbench.
const Document = preload("res://src/document/scene_document.gd")
const Take = preload("res://src/takes/take_store.gd")
const Jobs = preload("res://src/production/job_queue.gd")

## Defer startup until native nodes and file services are available.
func _initialize() -> void:
	_run.call_deferred()

## Validate recorded motion, enqueue one job and wait for its actual terminal status.
func _run() -> void:
	var options := {"scene": "res://config/workbench_2d.json", "take": "res://outputs/takes/latest.json"}
	var args: Dictionary = {"name": "video_%d" % int(Time.get_unix_time_from_system()), "fps": 30, "frames": 240, "width": 720, "height": 1280, "backend": "gl_compatibility"}
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=", true, 1)
		if pair.size() != 2: push_error("Expected --key=value"); quit(2); return
		if pair[0] in ["scene", "take", "wav"]: options[pair[0]] = pair[1]
		elif pair[0] in ["fps", "frames", "width", "height"]: args[pair[0]] = int(pair[1])
		elif pair[0] in ["name", "backend"]: args[pair[0]] = pair[1]
		else: push_error("Unknown production option: " + pair[0]); quit(2); return
	var loaded := Document.load_file(options["scene"])
	if not loaded["ok"]: push_error(loaded["error"]); quit(2); return
	var take = Take.new()
	if take.load_take(options["take"]) != OK: push_error(take.last_error); quit(2); return
	var doc: Dictionary = loaded["document"]
	if Document.simulation_hash(doc) != Document.simulation_hash(take.get_data()["scene"]):
		push_error("Recorded motion does not match scene physics; record again"); quit(2); return
	if options.has("wav"): doc["presentation"]["audio"]["wav_path"] = options["wav"]
	var jobs = Jobs.new()
	var result: Dictionary = jobs.enqueue(doc, take.get_data(), args)
	if not result["ok"]: push_error(result["error"]); quit(3); return
	print("JOB_STARTED " + result["path"])
	var previous := ""
	while true:
		var state: Dictionary = jobs.status()
		var phase := str(state.get("state", "starting"))
		if phase != previous: print("JOB_STATUS " + JSON.stringify(state)); previous = phase
		if phase in ["complete", "failed", "cancelled"]:
			print("JOB_RESULT " + JSON.stringify({"path": jobs.directory, "status": state}))
			quit(0 if phase == "complete" else 4)
			return
		await create_timer(0.2).timeout
