extends Node2D
## Rebuild screen-space bursts, rings and trails directly from event age.

var settings: Dictionary = {}
var timeline: Array = []
var take: Dictionary = {}
var history: Array = []
var particles: Array = []
var rings: Array = []
var trails: Array = []
var flashes: Array = []
var current_time := 0.0
var current_sim_time := 0.0
const Batch = preload("res://src/presentation/effect_batch.gd")
var ring_batch: MultiMeshInstance2D
var particle_batch: MultiMeshInstance2D
var flash_batch: MultiMeshInstance2D

## Separate layers preserve trails/rings/particles/flashes while batching circular geometry.
func _ready() -> void:
	ring_batch = Batch.new()
	particle_batch = Batch.new()
	flash_batch = Batch.new()
	for batch in [ring_batch, particle_batch, flash_batch]: add_child(batch)


## Load presentation-only settings without changing physics or event randomness.
func configure(doc: Dictionary) -> void:
	settings = doc.get("presentation", {}).get("effects", {}).duplicate(true)
	history.clear()


## Use the recorded event stream; rule rejection events never create effects.
func set_timeline(events: Array) -> void:
	timeline = events


## A take supplies trail history even after an arbitrary backwards seek.
func set_take(data: Dictionary) -> void:
	take = data
	history.clear()


## Evaluate every visible effect at the requested film and simulation time.
func present(time: float, sim_time: float, projector: Callable, states: Array, definitions: Dictionary) -> void:
	if time < current_time:
		history.clear()
	current_time = time
	current_sim_time = sim_time
	particles.clear()
	rings.clear()
	trails.clear()
	flashes.clear()
	if not bool(settings.get("enabled", true)):
		_update_batches()
		queue_redraw()
		return
	var domain := str(settings.get("time_domain", "simulation"))
	var ring_indices: Dictionary = {}
	var lifetime := clampf(float(settings.get("lifetime", 0.35)), 0.05, 3.0)
	# Event clocks are monotonic. Seek to the visible lifetime instead of scanning history.
	var clock_key := "sim_time" if domain == "simulation" else "time"
	var cutoff := (sim_time if domain == "simulation" else time) - lifetime
	var low := 0
	var high := timeline.size()
	while low < high:
		var middle := (low + high) / 2
		if float(timeline[middle].get(clock_key, timeline[middle].get("time", 0))) < cutoff:
			low = middle + 1
		else: high = middle
	for index in range(low, timeline.size()):
		var event: Dictionary = timeline[index]
		if float(event.get("time", 0.0)) > time + 0.000001:
			break
		if event.get("type", "") not in ["split", "contact"]: continue
		var age := sim_time - float(event.get("sim_time", event.get("time", 0))) if domain == "simulation" else time - float(event.get("time", 0))
		if age < 0 or age > lifetime or not event.get("position") is Array:
			continue
		var point: Vector2 = projector.call(event["position"])
		if event.get("type", "") == "split":
			_burst(event, index, point, age, lifetime)
		elif event.get("type", "") == "contact" and str(event.get("phase", "enter")) == "enter" and bool(settings.get("ring", true)):
			# Resting contacts can chatter at solver frequency. Show their latest ripple per pair.
			# The full contact/audio/Take ledger is unaffected by this visual coalescing.
			var key := str(event.get("id", "")) + "|" + str(event.get("other_id", ""))
			var ring := {"position": point, "radius": 5 + age * 65, "alpha": (1 - age / lifetime) * 0.6}
			if ring_indices.has(key): rings[ring_indices[key]] = ring
			else:
				ring_indices[key] = rings.size()
				rings.append(ring)
		if event.get("type", "") == "split" and bool(settings.get("flash", true)):
			var flash_age := time - float(event.get("time", 0))
			if flash_age < 0.08:
				flashes.append({"position": point, "radius": 28.0, "alpha": (1 - flash_age / 0.08) * 0.65})
	if bool(settings.get("trail_enabled", true)):
		_make_trails(time, sim_time, projector, states, definitions)
	_update_batches()
	queue_redraw()


## Independent per-event seeds keep effects from disturbing the simulation RNG.
func _burst(event: Dictionary, index: int, point: Vector2, age: float, lifetime: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(event.get("seed", str(event.get("event_id", str(index))).hash()))
	var count := clampi(int(settings.get("count", 12)), 0, 64)
	var speed := clampf(float(settings.get("speed", 130)), 10, 800)
	var color := Color(str(settings.get("color", "#baf7d0")))
	for particle in count:
		var velocity := Vector2.from_angle(rng.randf_range(0, TAU)) * speed * rng.randf_range(0.4, 1.0)
		var size := rng.randf_range(1.5, 4.0)
		particles.append({"position": point + velocity * age + Vector2(0, 60) * age * age,
			"size": size * (1 - age / lifetime), "color": Color(color, 1 - age / lifetime)})


## Build trails from recorded poses, or from bounded live history before a take exists.
func _make_trails(time: float, sim_time: float, projector: Callable, states: Array, definitions: Dictionary) -> void:
	var seconds := clampf(float(settings.get("trail_seconds", 0.25)), 0.03, 2.0)
	var domain := str(settings.get("time_domain", "simulation"))
	var now := sim_time if domain == "simulation" else time
	var frames: Array = take.get("frames", [])
	if frames.is_empty():
		var projected: Array = []
		for state in states:
			projected.append({"id": state["id"], "screen": projector.call(state["position"])})
		history.append({"time": time, "sim_time": sim_time, "states": projected})
		while history.size() > 500 or (not history.is_empty() and time - float(history[0]["time"]) > 3):
			history.pop_front()
		frames = history
	var by_id: Dictionary = {}
	var seen_times: Dictionary = {}
	var low := 0
	var high := frames.size()
	while low < high:
		var middle := (low + high) / 2
		if float(frames[middle]["time"]) <= time + 0.000001:
			low = middle + 1
		else:
			high = middle
	for frame_index in range(low - 1, -1, -1):
		var frame: Dictionary = frames[frame_index]
		if float(frame["time"]) > time + 0.000001:
			continue
		var clock := float(frame.get("sim_time", frame["time"])) if domain == "simulation" else float(frame["time"])
		if now - clock > seconds:
			break
		var key := int(clock * 60)
		if seen_times.has(key):
			continue
		seen_times[key] = true
		for state in frame["states"]:
			var id := str(state["id"])
			if definitions.get(id, {}).get("physics", {}).get("mode", "dynamic") != "dynamic":
				continue
			if not by_id.has(id): by_id[id] = []
			var point: Vector2 = state["screen"] if state.has("screen") else projector.call(state["position"])
			if by_id[id].is_empty() or point != by_id[id].back(): by_id[id].append(point)
	for id in by_id:
		if by_id[id].size() >= 2:
			trails.append(PackedVector2Array(by_id[id]))


## Draw a clean overlay which can be rendered at any output resolution.
func _draw() -> void:
	var segments := PackedVector2Array()
	for line in trails:
		for index in range(1, line.size()):
			segments.append(line[index - 1])
			segments.append(line[index])
	if not segments.is_empty(): draw_multiline(segments, Color(0.45, 0.85, 0.72, 0.22), 2.5, true)

## No circular effects are dropped; storage expands to the actual visible count.
func _update_batches() -> void:
	if not is_instance_valid(ring_batch): return
	ring_batch.update_circles(rings, "ring")
	particle_batch.update_circles(particles, "particle")
	flash_batch.update_circles(flashes, "flash")


## Expose effect counts and time domains to the debugging panel.
func get_report() -> Dictionary:
	return {"particles": particles.size(), "rings": rings.size(), "trails": trails.size(), "flashes": flashes.size(),
		"time": current_time, "sim_time": current_sim_time, "space": "screen", "time_domain": settings.get("time_domain", "simulation")}
