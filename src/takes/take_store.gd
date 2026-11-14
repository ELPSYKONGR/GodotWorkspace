extends RefCounted
## Bounded pose recording; replay reads committed snapshots and never runs physics.
const GlassRecording=preload("res://src/glass/recording.gd")
const Document = preload("res://src/document/scene_document.gd")

var data: Dictionary = {}
var last_error := ""
var recording_error := ""
const MAX_SECONDS := 60.0
const MAX_OBJECTS := Document.MAX_DYNAMIC_OBJECTS + Document.MAX_FIXED_OBJECTS
const MAX_FRAMES := 60000


## Begin a fresh take while retaining a frozen scene document.
func begin(doc: Dictionary) -> void:
	data = {"take_version": 1, "scene": doc.duplicate(true), "definitions": {}, "frames": [], "events": [],
		"engine": Engine.get_version_info(), "sampling": "previous_committed_pose", "duration": 0.0}
	last_error = ""
	recording_error = ""


## Record a complete lifecycle snapshot; reject unbounded recording.
func append(time: float, sim_time: float, states: Array, definitions: Dictionary) -> bool:
	if not recording_error.is_empty():
		last_error = recording_error
		return false
	if data.is_empty():
		last_error = "尚未开始录制"
		recording_error = last_error
		return false
	if time > MAX_SECONDS or states.size() > MAX_OBJECTS or data["frames"].size() >= MAX_FRAMES:
		last_error = "录制达到限制：60秒、512活跃物体（256动态＋256静态/区域）或60000采样"
		recording_error = last_error
		return false
	if not data["frames"].is_empty() and time < float(data["frames"][-1]["time"]):
		last_error = "录制时间不能倒退"
		recording_error = last_error
		return false
	for id in definitions:
		if not data["definitions"].has(str(id)):
			data["definitions"][str(id)] = definitions[id].duplicate(true)
	var frame := {"time": time, "sim_time": sim_time, "states": states.duplicate(true)}
	if not data["frames"].is_empty() and absf(time - float(data["frames"][-1]["time"])) < 0.0000001:
		data["frames"][-1] = frame
	else:
		data["frames"].append(frame)
	data["duration"] = time
	return true


## Preserve event identity and both time domains for effects and offline mixing.
func add_event(event: Dictionary) -> void:
	if data.is_empty():
		return
	var copy := event.duplicate(true)
	if not copy.has("event_id"):
		copy["event_id"] = "event_%06d" % data["events"].size()
	if not copy.has("time"):
		copy["time"] = get_duration()
	data["events"].append(copy)


## Save the self-contained initial scene, definitions, states and event ledger.
func save(path: String) -> Error:
	if not recording_error.is_empty():
		last_error = recording_error
		return ERR_INVALID_DATA
	if is_empty():
		last_error = "没有可保存的轨迹"
		return ERR_INVALID_DATA
	var directory := path.get_base_dir()
	var err := DirAccess.make_dir_recursive_absolute(directory)
	if err != OK:
		last_error = "无法创建轨迹目录"
		return err
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		last_error = "无法写入轨迹：" + path
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data))
	return OK


## Validate loaded snapshots before replacing the currently usable take.
func load_take(path: String) -> Error:
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		last_error = "轨迹JSON读取失败：" + parser.get_error_message()
		return ERR_PARSE_ERROR
	var candidate: Dictionary = parser.data
	if not _valid(candidate):
		last_error = "轨迹结构无效或超过录制限制"
		return ERR_INVALID_DATA
	data = candidate
	last_error = ""
	recording_error = ""
	return OK


## Choose the previous committed pose to avoid interpolation through collision walls.
func sample(time: float) -> Dictionary:
	if is_empty():
		return {"states": [], "definitions": {}, "time": 0.0, "sim_time": 0.0}
	var frames: Array = data["frames"]
	var clamped := clampf(time, 0.0, get_duration())
	var low := 0
	var high := frames.size() - 1
	while low < high:
		var middle := (low + high + 1) / 2
		if float(frames[middle]["time"]) <= clamped:
			low = middle
		else:
			high = middle - 1
	var frame: Dictionary = frames[low]
	return {"states": frame["states"].duplicate(true), "definitions": data["definitions"],
		"time": clamped, "sample_time": float(frame["time"]), "sim_time": float(frame["sim_time"])}


## Return the recorded presentation duration in seconds.
func get_duration() -> float:
	return float(data.get("duration", 0.0))


## Expose immutable-by-convention data for rendering and export snapshots.
func get_data() -> Dictionary:
	return data


## Report whether any committed pose is available.
func is_empty() -> bool:
	return data.get("frames", []).is_empty()


## Check types, monotonic clocks and stable object references on imported data.
func _valid(candidate: Dictionary) -> bool:
	if candidate.get("take_version", 0) != 1 or not candidate.get("frames") is Array or not candidate.get("definitions") is Dictionary or not candidate.get("events") is Array or not candidate.get("scene") is Dictionary:
		return false
	var has_glass: bool=candidate["definitions"].values().any(func(spec): return spec is Dictionary and spec.has("glass"))
	if has_glass and not Document.validate(candidate["scene"]).is_empty(): return false
	var frames: Array = candidate["frames"]
	if frames.is_empty() or frames.size() > MAX_FRAMES:
		return false
	for definition in candidate["definitions"].values():
		if not definition is Dictionary or not definition.get("shape") is Dictionary:
			return false
	for definition in candidate["definitions"].values():
		if definition.has("glass") and not GlassRecording.definition_valid(definition,candidate["scene"]): return false
	var previous := -1.0
	for frame in frames:
		if not frame is Dictionary or not frame.get("states") is Array:
			return false
		if not _number(frame.get("time")) or not _number(frame.get("sim_time")):
			return false
		var t := float(frame.get("time", -1.0))
		var sim := float(frame.get("sim_time", -1.0))
		if not is_finite(t) or not is_finite(sim) or t < previous or t > MAX_SECONDS or sim < 0 or frame["states"].size() > MAX_OBJECTS:
			return false
		var ids: Dictionary = {}
		for state in frame["states"]:
			if not state is Dictionary or not state.get("position") is Array:
				return false
			var id := str(state.get("id", ""))
			if id.is_empty() or ids.has(id) or not candidate["definitions"].has(id):
				return false
			if not GlassRecording.state_valid(state,candidate["definitions"][id]): return false
			ids[id] = true
			if state["position"].size() not in [2, 3]:
				return false
			var rotation = state.get("rotation", 0.0)
			if state["position"].size() == 2 and not (rotation is float or rotation is int):
				return false
			if state["position"].size() == 3 and (not rotation is Array or rotation.size() != 4):
				return false
			if state.has("velocity") and (not state["velocity"] is Array or state["velocity"].size() != state["position"].size()):
				return false
			for value in state.get("velocity", []):
				if not _number(value):
					return false
			for value in state["position"]:
				if not (value is float or value is int) or not is_finite(float(value)):
					return false
			if rotation is Array:
				for value in rotation:
					if not (value is float or value is int) or not is_finite(float(value)):
						return false
			elif not is_finite(float(rotation)):
				return false
		previous = t
	for event in candidate["events"]:
		if event is Dictionary and not GlassRecording.event_valid(event,candidate["definitions"]): return false
		if not event is Dictionary or not _number(event.get("time")) or float(event["time"]) < 0 or float(event["time"]) > MAX_SECONDS:
			return false
	return _number(candidate.get("duration")) and absf(float(candidate["duration"]) - previous) < 0.001


## Reject string/object coercions and non-finite numbers in imported clocks and poses.
func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
