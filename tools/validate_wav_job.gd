extends SceneTree
## Actual enqueue, source deletion, production and decoded media validation for frozen WAVs.
const Document = preload("res://src/document/scene_document.gd")
const Take = preload("res://src/takes/take_store.gd")
const Jobs = preload("res://src/production/job_queue.gd")


## Defer until the tree can schedule asynchronous production polling.
func _initialize() -> void:
	_run.call_deferred()


## Remove only our temporary source after enqueue and prove the frozen copy survives.
func _run() -> void:
	var report := {"passed": false, "checks": {}}
	var name := "wav_frozen_%d" % Time.get_ticks_usec()
	var source := "res://outputs/" + name + "_source.wav"
	var source_absolute := ProjectSettings.globalize_path(source)
	if DirAccess.copy_absolute(ProjectSettings.globalize_path("res://outputs/media_pcm_16_1.wav"), source_absolute) != OK:
		_finish(report, "Could not copy WAV fixture")
		return
	var source_hash := FileAccess.get_sha256(source)
	var loaded := Document.load_file("res://config/workbench_2d.json")
	var take = Take.new()
	if not loaded["ok"] or take.load_take("res://outputs/takes/integration_2d.json") != OK:
		_finish(report, "Could not load matching scene and take")
		return
	var doc: Dictionary = loaded["document"]
	if Document.simulation_hash(doc) != Document.simulation_hash(take.get_data()["scene"]):
		_finish(report, "Fixture scene and take physics differ")
		return
	doc["presentation"]["audio"]["enabled"] = true
	doc["presentation"]["audio"]["wav_path"] = source_absolute
	var jobs = Jobs.new()
	var queued: Dictionary = jobs.enqueue(doc, take.get_data(), {"name": name, "fps": 30, "frames": 30, "width": 720, "height": 1280, "backend": "gl_compatibility"})
	if not queued["ok"]:
		_finish(report, str(queued.get("error", "enqueue failed")))
		return
	var frozen: String = jobs.directory.path_join("assets/collision.wav")
	var before := FileAccess.get_sha256(frozen)
	var deletion := DirAccess.remove_absolute(source_absolute)
	report["job"] = jobs.directory
	report["source"] = source_absolute
	report["source_sha256"] = source_hash
	report["frozen_sha256_before"] = before
	report["checks"]["enqueue_froze_identical_wav"] = before == source_hash and not before.is_empty()
	report["checks"]["source_deleted_immediately_after_enqueue"] = deletion == OK and not FileAccess.file_exists(source)
	var deadline := Time.get_ticks_msec() + 180000
	while Time.get_ticks_msec() < deadline:
		var status: Dictionary = jobs.status()
		if status.get("state", "") in ["complete", "failed", "cancelled"]:
			var after := FileAccess.get_sha256(frozen)
			var validation = JSON.parse_string(FileAccess.get_file_as_string(jobs.directory.path_join("validation.json")))
			var snapshot = JSON.parse_string(FileAccess.get_file_as_string(jobs.directory.path_join("scene.snapshot.json")))
			report["status"] = status
			report["frozen_sha256_after"] = after
			report["validation"] = validation
			report["checks"]["job_complete"] = status.get("state", "") == "complete"
			report["checks"]["frozen_wav_unchanged"] = after == before
			report["checks"]["snapshot_references_frozen_asset"] = snapshot is Dictionary and snapshot["presentation"]["audio"]["wav_path"] == frozen
			report["checks"]["decoded_validation_passed"] = validation is Dictionary and validation.get("passed", false)
			report["checks"]["decoded_audio_non_silent"] = validation is Dictionary and validation.get("audio", {}).get("decoded", {}).get("non_silent", false)
			report["checks"]["has_measured_production_time"] = float(status.get("elapsed_seconds", 0)) > 0 and status.get("stage_seconds", {}).size() == 4
			report["passed"] = not report["checks"].values().has(false)
			_finish(report)
			return
		await create_timer(0.2).timeout
	jobs.cancel()
	_finish(report, "Production timed out; cancellation requested")


## Retain a machine-readable report and return a failing exit code on any unmet check.
func _finish(report: Dictionary, error := "") -> void:
	if not error.is_empty(): report["error"] = error
	var output := FileAccess.open("res://outputs/wav_job_validation.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	quit(0 if report["passed"] else 1)
