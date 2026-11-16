extends Node2D
## Rebuild screen-space bursts, rings and trails directly from event age.

var settings: Dictionary = {}
var global_settings: Dictionary = {}
var initial_objects: Dictionary = {}
var trail_colors: Array = []
const Style = preload("res://src/document/object_style.gd")
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
	global_settings = settings
	initial_objects.clear()
	for spec in doc.get("objects", []): initial_objects[spec["id"]] = spec
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
	trail_colors.clear()
	settings = global_settings
	if not bool(settings.get("enabled", true)):
		_update_batches()
		queue_redraw()
		return
	var domain := str(settings.get("time_domain", "simulation"))
	var ring_indices: Dictionary = {}
	var impacts: Dictionary = {}
	var lifetime := clampf(float(settings.get("lifetime", 0.35)), 0.05, 3.0)
	# Event clocks are monotonic. Seek to the visible lifetime instead of scanning history.
	var clock_key := "sim_time" if domain == "simulation" else "time"
	var cutoff := minf(sim_time, time) - 3.0
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
		for variant in _variants(event, definitions):
			settings = variant
			lifetime = clampf(float(settings.get("lifetime", 0.35)), 0.05, 3.0)
			domain = str(settings.get("time_domain", "simulation"))
			var age := sim_time - float(event.get("sim_time", event.get("time", 0))) if domain == "simulation" else time - float(event.get("time", 0))
			if age < 0 or age > lifetime or not event.get("position") is Array or not settings.get("enabled", true): continue
			var point: Vector2 = projector.call(event["position"])
			var key := str(event.get("id", "")) + "|" + str(event.get("other_id", "")) + JSON.stringify(settings, "", true)
			if event.get("type", "") == "split" and settings.get("particles_enabled", true): _burst(event, index, point, age, lifetime)
			if event.get("type", "") == "contact" and event.get("phase", "enter") == "enter":
				if settings.get("impact_particles", false) or settings.get("impact_flash", false): impacts[key] = {"event": event, "index": index, "point": point, "age": age, "settings": settings}
				if settings.get("ring", true):
					var ring := {"position": point, "radius": 5 + age * 65, "alpha": (1 - age / lifetime) * 0.6, "color": Color(Color(str(settings.get("color", "#99e6cc"))), (1 - age / lifetime) * 0.6)}
					if ring_indices.has(key): rings[ring_indices[key]] = ring
					else: ring_indices[key] = rings.size(); rings.append(ring)
			if event.get("type", "") == "split" and settings.get("flash", true):
				var flash_age := time - float(event.get("time", 0))
				if flash_age < 0.08: flashes.append({"position": point, "radius": 28.0, "alpha": (1 - flash_age / 0.08) * 0.65, "color": Color(Color(str(settings.get("color", "#ccffe6"))), (1 - flash_age / 0.08) * 0.65)})
	# Keep new contact feedback bounded independently of the complete event/physics ledger.
	var contact_bursts := 0
	var impact_values := impacts.values()
	impact_values.sort_custom(func(a, b): return a["index"] > b["index"])
	for impact in impact_values:
		if contact_bursts >= 16: break
		contact_bursts += 1
		settings = impact["settings"]
		lifetime = clampf(float(settings.get("lifetime", 0.35)), 0.05, 3.0)
		if settings.get("impact_particles", false): _burst(impact["event"], impact["index"], impact["point"], impact["age"], lifetime)
		var flash_age := time - float(impact["event"].get("time", 0))
		if settings.get("impact_flash", false) and flash_age < 0.08:
			flashes.append({"position": impact["point"], "radius": 14.0, "alpha": (1 - flash_age / 0.08) * 0.45, "color": Color(Color(str(settings.get("color", "#ccffe6"))), (1 - flash_age / 0.08) * 0.45)})
	settings = global_settings
	_make_trails(time, sim_time, projector, states, definitions)
	_update_batches()
	queue_redraw()

## Each contact participant may contribute its own effect; identical inherited presets coalesce.
func _variants(event: Dictionary, definitions: Dictionary) -> Array:
	var result: Array = []
	for key in (["id", "other_id"] if event.get("type", "") == "contact" else ["id"]):
		var value := Style.effects(Style.definition(str(event.get(key, "")), definitions, initial_objects), global_settings)
		if not result.has(value): result.append(value)
	return result


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
	var seconds := 2.0
	var domain := str(settings.get("time_domain", "simulation"))
	var frames: Array = take.get("frames", [])
	if frames.is_empty():
		var projected: Array = []
		for state in states:
			# Keep world anchors, so a later camera move reprojects the whole trail consistently.
			projected.append({"id": state["id"], "position": state["position"]})
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
		# A local simulation-clock trail must survive a global presentation-clock hit-stop.
		if time - float(frame["time"]) > seconds and sim_time - float(frame.get("sim_time", frame["time"])) > seconds:
			break
		var key := int(clock * 60)
		if seen_times.has(key):
			continue
		seen_times[key] = true
		for state in frame["states"]:
			var id := str(state["id"])
			var local := Style.effects(Style.definition(id, definitions, initial_objects), global_settings)
			if not local.get("enabled", true) or not local.get("trail_enabled", true): continue
			var age := sim_time - float(frame.get("sim_time", frame["time"])) if local.get("time_domain", "simulation") == "simulation" else time - float(frame["time"])
			if age > float(local.get("trail_seconds", 0.25)): continue
			if definitions.get(id, {}).get("physics", {}).get("mode", "dynamic") != "dynamic":
				continue
			if not by_id.has(id): by_id[id] = []
			var point: Vector2 = state["screen"] if state.has("screen") else projector.call(state["position"])
			if by_id[id].is_empty() or point != by_id[id].back(): by_id[id].append(point)
	for id in by_id:
		if by_id[id].size() >= 2:
			trails.append(PackedVector2Array(by_id[id]))
			var local := Style.effects(Style.definition(id, definitions, initial_objects), global_settings)
			trail_colors.append(Color(Color(str(local.get("color", "#73d9b8"))), 0.22))


## Draw a clean overlay which can be rendered at any output resolution.
func _draw() -> void:
	for i in trails.size():
		var line: PackedVector2Array = trails[i]
		var segments := PackedVector2Array()
		for index in range(1, line.size()):
			segments.append(line[index - 1])
			segments.append(line[index])
		if not segments.is_empty(): draw_multiline(segments, trail_colors[i], 2.5, true)

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
