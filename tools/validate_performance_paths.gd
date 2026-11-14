extends SceneTree
## Differential checks for accelerated geometry, native contacts, cached PCM and batched effects.
var results: Dictionary = {}

## Construct physics nodes after the tree is ready.
func _initialize() -> void:
	_run.call_deferred()

## Compare broad-phase queries against the previous exhaustive geometry algorithm.
func _brute(world: Node, point: Vector2, radius: float, ignored: String) -> bool:
	for id in world.records:
		if id == ignored or world.source_kind(id) == "sensor": continue
		var spec: Dictionary = world.records[id]["spec"]
		var local: Vector2 = (point - world._position(id)).rotated(-world._rotation(id))
		if spec["shape"].get("primitive", "") == "circle":
			if local.length() < radius + float(spec["shape"].get("radius", 18)) + 0.05: return false
		else:
			var half: Vector2 = world._size(spec) / 2
			if local.distance_to(local.clamp(-half, half)) < radius + 0.05: return false
	return true

## Independently poll engine membership, without relying on the new signal tracker.
func _polled(world: Node) -> Array:
	var pairs: Dictionary = {}
	for id in world.records:
		var body = world.records[id].get("body")
		var others: Array = []
		if body is RigidBody2D: others = body.get_colliding_bodies()
		elif body is Area2D: others = body.get_overlapping_bodies()
		for other in others:
			var other_id := str(other.get_meta("object_id", ""))
			if other_id.is_empty() or not world.records.has(other_id): continue
			var key: String = id + "|" + other_id if id < other_id else other_id + "|" + id
			pairs[key] = true
	var keys := pairs.keys()
	keys.sort()
	return keys

## Exercise the optimized paths without a shared workbench command inbox.
func _run() -> void:
	Engine.physics_ticks_per_second = 120
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/workbench_2d.json"))
	doc["mechanisms"] = []
	for spec in doc["objects"]: spec["mechanisms"] = []
	doc["objects"][0]["transform"]["position"] = [200, 1060]
	var world = load("res://src/physics/world_2d.gd").new()
	world.setup(doc)
	root.add_child(world)
	var tilted: Dictionary = doc["objects"][2].duplicate(true)
	tilted["id"] = "tilted"
	tilted["transform"] = {"position": [440, 650], "rotation_degrees": 37}
	world.create_object(tilted, 0)
	world.birth_space.rebuild(world.records)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261114
	var exact := true
	for index in 2000:
		var point := Vector2(rng.randf_range(-100, 850), rng.randf_range(-100, 1400))
		var radius := rng.randf_range(1, 60)
		exact = exact and world._space_free(point, radius, "ball_A") == _brute(world, point, radius, "ball_A")
	results["grid_matches_2000_exhaustive_queries_including_rotated_box"] = exact
	world.remove_object("tilted")
	world.birth_positions("ball_A", 2, 18)
	results["retirement_invalidates_grid"] = not world.birth_space.cells.values().any(func(ids): return "tilted" in ids)
	var matched := true
	var observed := false
	for tick in 120:
		await physics_frame
		await process_frame
		var native: Array = world.contact_pairs().keys()
		native.sort()
		var polled := _polled(world)
		matched = matched and native == polled
		observed = observed or not polled.is_empty()
	results["signals_equal_native_polling_over_120_ticks"] = matched and observed
	root.remove_child(world)
	world.queue_free()
	await process_frame
	var audio = load("res://src/presentation/audio.gd").new()
	root.add_child(audio)
	audio.configure(doc)
	var cached: AudioStreamWAV = audio.synthesized_clip
	audio.audition()
	audio.audition()
	results["repeated_impacts_reuse_pcm_resource"] = cached != null and cached == audio.synthesized_clip
	results["cached_pcm_equals_original_synthesis"] = cached.data == audio._synthesize("wood", 1.0, 1.0).data
	audio.stop_all()
	cached = null
	var fx = load("res://src/presentation/effects.gd").new()
	root.add_child(fx)
	fx.configure(doc)
	fx.set_timeline([
		{"type": "contact", "phase": "enter", "id": "a", "other_id": "b", "position": [100, 100], "time": 0.0, "sim_time": 0.0},
		{"type": "contact", "phase": "enter", "id": "a", "other_id": "b", "position": [101, 100], "time": 0.01, "sim_time": 0.01},
		{"type": "split", "position": [100, 100], "time": 0.02, "sim_time": 0.02, "seed": 42}])
	fx.present(0.03, 0.03, func(point): return Vector2(point[0], point[1]), [], {})
	results["repeated_pair_ripples_coalesced_only_visually"] = fx.rings.size() == 1
	results["all_particles_reach_instanced_renderer"] = fx.particles.size() == 12 and fx.particle_batch.multimesh.visible_instance_count == 12
	results["passed"] = not results.values().has(false)
	var file := FileAccess.open("res://outputs/performance_paths_validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	print("PERFORMANCE_PATHS ", JSON.stringify(results))
	for child in root.get_children(): child.queue_free()
	await process_frame
	await process_frame
	# The audio callback uses wall time, including when the test uses fixed engine time.
	var cleanup_until := Time.get_ticks_msec() + 100
	while Time.get_ticks_msec() < cleanup_until: await process_frame
	quit(0 if results["passed"] else 1)
