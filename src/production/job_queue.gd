extends RefCounted
## Frozen input snapshots and one independent production process at a time.
var directory := ""
var pid := -1
var last_error := ""
var _last_status: Dictionary = {"state": "starting"}

## Enqueue a recorded take; refuse stale simulations and existing output names.
func enqueue(doc: Dictionary, take: Dictionary, args: Dictionary) -> Dictionary:
	if not directory.is_empty() and status().get("state", "") not in ["complete", "failed", "cancelled"]: return {"ok": false, "error": "已有生产任务正在运行"}
	if take.get("frames", []).is_empty(): return {"ok": false, "error": "先录制一条轨迹，再提交视频生产"}
	var name := str(args.get("name", "video_" + str(Time.get_unix_time_from_system()).replace(".", "_")))
	var regex := RegEx.new()
	regex.compile("^[a-zA-Z0-9_-]+$")
	if regex.search(name) == null: return {"ok": false, "error": "任务名称只接受字母、数字、下划线和短横线"}
	var fps := int(args.get("fps", 30))
	var frames := int(args.get("frames", 240))
	var width := int(args.get("width", 720))
	var height := int(args.get("height", 1280))
	var backend := str(args.get("backend", "gl_compatibility"))
	if backend not in ["gl_compatibility", "forward_plus"]: return {"ok": false, "error": "请选择 Compatibility 或 Forward+ 渲染器"}
	if fps not in [30, 60] or frames < 1 or frames > 3600 or [width, height] not in [[720, 1280], [1080, 1920]]: return {"ok": false, "error": "请选择30/60fps、1～3600帧和竖屏预设尺寸"}
	if frames / float(fps) > float(take.get("duration", 0)) + 0.00001: return {"ok": false, "error": "导出时长超过轨迹；请录制更长或减少帧数"}
	var destination := "res://outputs/jobs/" + name
	if DirAccess.dir_exists_absolute(destination): return {"ok": false, "error": "该任务名称已存在，请使用新名称"}
	DirAccess.make_dir_recursive_absolute(destination)
	directory = ProjectSettings.globalize_path(destination)
	_last_status = {"state": "queued"}
	var snapshot := doc.duplicate(true)
	var wav_path := str(snapshot.get("presentation", {}).get("audio", {}).get("wav_path", "")).strip_edges()
	if not wav_path.is_empty():
		var frozen_path := directory.path_join("assets/collision.wav")
		DirAccess.make_dir_recursive_absolute(frozen_path.get_base_dir())
		var copy_error := DirAccess.copy_absolute(ProjectSettings.globalize_path(wav_path), frozen_path)
		if copy_error != OK: return _failed("无法冻结声音文件：" + wav_path)
		snapshot["presentation"]["audio"]["wav_path"] = frozen_path
	var job := args.duplicate(true)
	job.merge({"fps": fps, "frames": frames, "width": width, "height": height, "backend": backend}, true)
	for file in ["job.json", "scene.snapshot.json", "take.json", "status.json"]:
		var data: Dictionary = job if file == "job.json" else (snapshot if file == "scene.snapshot.json" else (take if file == "take.json" else {"state": "queued"}))
		var handle := FileAccess.open(directory.path_join(file), FileAccess.WRITE)
		if handle == null: return _failed("无法冻结生产输入：" + file)
		handle.store_string(JSON.stringify(data))
		handle.close()
	var script := ProjectSettings.globalize_path("res://tools/render_take.ps1")
	pid = OS.create_process("powershell.exe", PackedStringArray(["-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", script, "-JobDir", directory]))
	if pid < 0: return _failed("无法启动独立生产任务")
	var process_file := FileAccess.open(directory.path_join("job.pid"), FileAccess.WRITE)
	process_file.store_string(str(pid))
	return {"ok": true, "message": "生产任务已启动：" + name, "path": directory}

## Failed preparation is terminal so the next enqueue is not blocked by queued status.
func _failed(reason: String) -> Dictionary:
	last_error = reason
	var file := FileAccess.open(directory.path_join("status.json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify({"state": "failed", "message": reason}))
	return {"ok": false, "error": reason}

## Read only this job's progress; editor changes cannot alter frozen inputs.
func status() -> Dictionary:
	if directory.is_empty(): return {"state": "idle"}
	var path := directory.path_join("status.json")
	# A Windows replacement may briefly deny a concurrent reader; retain the last full value.
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return _last_status
	var content := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(content) == OK and parser.data is Dictionary: _last_status = parser.data
	return _last_status

## Cooperative cancellation is checked by every production stage.
func cancel() -> Dictionary:
	if directory.is_empty(): return {"ok": false, "error": "没有生产任务"}
	var request := FileAccess.open(directory.path_join("cancel.request"), FileAccess.WRITE)
	request.store_string("cancel")
	return {"ok": true, "message": "已请求取消本任务，预览继续运行"}
