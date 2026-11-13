extends Node
## Explicit simulation/presentation clocks; UI and production never share global pause.
const Stage = preload("res://src/presentation/stage.gd")
const Take = preload("res://src/takes/take_store.gd")
const Document = preload("res://src/document/scene_document.gd")
signal event_logged(event: Dictionary)
var document: Dictionary = {}
var stage: Node2D
var audio: Node
var take = Take.new()
var mode := "edit"
var events: Array = []
var time := 0.0
var sim_time := 0.0
var replay_playing := false
var last_error := ""
var _film_ticks := 0
var _sim_ticks := 0
var _last_active := false
var _last_hold := false
var _hold_ticks := 0
var _requested_steps := 0
var _event_serial := 0
var _audio_cursor := -0.000001
var _scale := 1.0

## Capture the previous solved step before choosing whether the next solver step runs.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -1000
	audio = load("res://src/presentation/audio.gd").new()
	add_child(audio)

## Reset only the active preview; a prior take is retained and can become stale.
func load_document(doc: Dictionary, output_scale: float = 1.0) -> void:
	last_error = ""
	document = doc.duplicate(true)
	_scale = output_scale
	mode = "edit"
	replay_playing = false
	_reset_clocks()
	_make_stage(true)

## Create display-only edit/replay worlds or native dynamic simulation worlds.
func _make_stage(playback: bool) -> void:
	_set_active(false)
	if is_instance_valid(audio): audio.stop_all()
	if is_instance_valid(stage):
		remove_child(stage)
		stage.queue_free()
	stage = Stage.new()
	add_child(stage)
	stage.event_logged.connect(_on_event)
	stage.setup(document, playback, _scale)
	if is_instance_valid(audio): audio.configure(document)
	Engine.physics_ticks_per_second = int(document["world"].get("physics_hz", 240))

## Discard stale runtime clocks without editing initial object transforms.
func _reset_clocks() -> void:
	_film_ticks = 0
	_sim_ticks = 0
	_hold_ticks = 0
	_requested_steps = 0
	_last_active = false
	_last_hold = false
	time = 0
	sim_time = 0
	events.clear()
	_event_serial = 0
	_audio_cursor = -0.000001

## Start playback, resume a paused world, or begin native simulation from the layout.
func play() -> void:
	if mode == "replay": replay_playing = true; return
	if mode == "edit" or stage.world.playback:
		_reset_clocks()
		mode = "playing"
		_make_stage(false)
	else: mode = "playing" if mode != "recording" else "recording"

## Manual pause freezes film time and bodies; the UI keeps processing.
func pause() -> void:
	if mode == "replay":
		replay_playing = false
		audio.stop_all()
		return
	if mode == "recording": stop_recording()
	mode = "paused"
	_set_active(false)
	_last_active = false
	_last_hold = false
	if is_instance_valid(audio): audio.stop_all()

## Request one actual solver step, independent of render FPS.
func step_once() -> void:
	if mode in ["edit", "replay"]:
		_reset_clocks()
		mode = "paused"
		_make_stage(false)
	else: pause()
	_requested_steps = 1

## Record high-frequency committed poses into a self-contained take.
func start_recording() -> void:
	last_error = ""
	_reset_clocks()
	take.begin(document)
	mode = "recording"
	_make_stage(false)
	_capture()

## Stop and retain the take in memory; the host chooses the save path.
func stop_recording() -> void:
	if mode == "recording": _capture()
	mode = "paused"
	_set_active(false)
	_last_active = false
	_last_hold = false
	audio.stop_all()

## Update only appearance, fonts, audio and effect presets while retaining motion.
func apply_presentation(doc: Dictionary) -> void:
	document = doc.duplicate(true)
	stage.apply_presentation(doc)
	audio.configure(doc)

## Position a read-only stage; seek cannot trigger native collisions or rules.
func seek(value: float, silent: bool = true) -> bool:
	if take.is_empty(): last_error = "请先录制或加载轨迹"; return false
	last_error = ""
	if mode != "replay":
		mode = "replay"
		_make_stage(true)
		stage.effects.set_take(take.get_data())
	if silent:
		replay_playing = false
		audio.stop_all()
	var frame: Dictionary = take.sample(value)
	time = frame["time"]
	sim_time = frame["sim_time"]
	stage.world.apply_state(frame["states"], frame["definitions"])
	stage.world.apply_presentation(document)
	stage.present(time, sim_time, take.get_data()["events"], take.get_data())
	if silent: _audio_cursor = time
	return true

## Runtime reports keep physics, audio and recording state separately visible.
func get_info() -> Dictionary:
	var report: Dictionary = stage.world.get_report() if is_instance_valid(stage) else {}
	report["audio"] = audio.get_report() if is_instance_valid(audio) else {}
	report["last_error"] = last_error
	report.merge({"mode": mode, "time": time, "sim_time": sim_time, "duration": take.get_duration(), "recording": mode == "recording", "events": events.slice(maxi(0, events.size() - 30)), "fps": Engine.get_frames_per_second(), "take_stale": not take.is_empty() and Document.simulation_hash(document) != Document.simulation_hash(take.get_data()["scene"]), "has_take": not take.is_empty()}, true)
	return report

## Gate both the server and world callbacks; never pause the entire SceneTree.
func _set_active(value: bool) -> void:
	PhysicsServer2D.set_active(value)
	PhysicsServer3D.set_active(value)
	if is_instance_valid(stage) and is_instance_valid(stage.world): stage.world.process_mode = Node.PROCESS_MODE_INHERIT if value else Node.PROCESS_MODE_DISABLED

## Finalize one completed step or one held interval and schedule the next.
func _physics_process(_delta: float) -> void:
	if not is_instance_valid(stage) or mode in ["edit", "replay"]: return
	var hz := float(Engine.physics_ticks_per_second)
	if _last_active:
		_sim_ticks += 1
		_film_ticks += 1
	elif _last_hold:
		_film_ticks += 1
		_hold_ticks = maxi(0, _hold_ticks - 1)
	time = _film_ticks / hz
	sim_time = _sim_ticks / hz
	if mode == "recording" and (_last_active or _last_hold): _capture()
	if mode == "recording" and time >= 60.0:
		stop_recording()
		return
	var advancing := mode in ["playing", "recording"] or _requested_steps > 0
	_last_hold = advancing and _hold_ticks > 0
	_last_active = advancing and not _last_hold
	if _last_active and _requested_steps > 0: _requested_steps -= 1
	_set_active(_last_active)

## Rendering and audio use film time even when physical bodies are in hit-stop.
func _process(delta: float) -> void:
	if not is_instance_valid(stage): return
	if mode == "replay":
		if replay_playing:
			var next := minf(time + delta, take.get_duration())
			seek(next, false)
			for event in take.get_data()["events"]:
				if float(event["time"]) > _audio_cursor and float(event["time"]) <= time: audio.consume(event)
			_audio_cursor = time
			if time >= take.get_duration(): replay_playing = false
	else:
		if mode == "recording": _capture()
		stage.present(time, sim_time, events, take.get_data() if mode == "recording" else {})

## Attach clocks and stable IDs before committing event-driven presentation.
func _on_event(source: Dictionary) -> void:
	var event := source.duplicate(true)
	_event_serial += 1
	event["event_id"] = "event_%08d" % _event_serial
	event["time"] = time
	event["sim_time"] = sim_time
	event["seed"] = _event_serial * 7919
	events.append(event)
	if mode == "recording": take.add_event(event)
	if mode == "recording" and (event.get("type", "") == "split" or (event.get("type", "") == "retire" and event.get("reason", "") == "despawn")):
		_capture()
	if events.size() > 10000: events.pop_front()
	if event.get("type", "") == "split":
		for rule in document.get("mechanisms", []):
			if rule.get("type", "") == "hit_stop_on_event" and rule.get("enabled", true):
				_hold_ticks = maxi(_hold_ticks, int(ceil(float(rule.get("params", {}).get("seconds", 0.06)) * Engine.physics_ticks_per_second)))
	if mode in ["playing", "recording"] and is_instance_valid(audio): audio.consume(event)
	event_logged.emit(event)

## Same-time replacement includes deferred spawn/retire changes in the final pose.
func _capture() -> void:
	if not take.append(time, sim_time, stage.world.capture_state(), stage.world.get_definitions()):
		last_error = take.last_error
		mode = "paused"
		_set_active(false)
		_last_active = false
		_last_hold = false
		audio.stop_all()

## Release generated sound resources before the session leaves the tree.
func _exit_tree() -> void:
	if is_instance_valid(audio): audio.stop_all()
