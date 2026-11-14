extends Node3D
## Native 3D adapter; orthographic and perspective views share the same physical world.

signal event_logged(event: Dictionary)
const Rules = preload("res://src/mechanisms/contact_rules.gd")
const Primitive = preload("res://src/physics/primitive_3d.gd")
const ContactAnchor = preload("res://src/physics/contact_anchor.gd")
var document: Dictionary = {}
var records: Dictionary = {}
var definitions: Dictionary = {}
var playback := false
var dimensions := 3
var runner: Node
var camera: Camera3D
var environment: WorldEnvironment
var light: DirectionalLight3D
var debug_enabled := false
var selected_id := ""
var initial_dynamic := 0


## Configure initial data before entering the scene tree.
func setup(doc: Dictionary, replay: bool = false) -> void:
	document = doc.duplicate(true)
	playback = replay


## Create the camera, lighting, rule component and object instances.
func _ready() -> void:
	environment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b9c8e3")
	environment.environment.ambient_light_energy = 0.65
	add_child(environment)
	light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-58, -25, 0)
	light.light_energy = 1.5
	add_child(light)
	camera = Camera3D.new()
	add_child(camera)
	camera.current = true
	runner = Rules.new()
	runner.setup(self, document)
	add_child(runner)
	for spec in document.get("objects", []): create_object(spec, -1000)
	initial_dynamic = dynamic_count()
	apply_presentation(document)


## Use matching sphere/box meshes and collision shapes for every object.
func create_object(value: Dictionary, born: float) -> void:
	var spec := value.duplicate(true)
	var id := str(spec["id"])
	spec["root_id"] = spec.get("root_id", id)
	spec["generation"] = int(spec.get("generation", 0))
	definitions[id] = spec
	var physics: Dictionary = spec.get("physics", {})
	var mode := str(physics.get("mode", "dynamic"))
	var body: Node3D
	if playback: body = Node3D.new()
	elif mode == "sensor": body = Area3D.new()
	elif mode == "static": body = StaticBody3D.new()
	else: body = RigidBody3D.new()
	body.name = "Body_" + id
	body.set_meta("object_id", id)
	body.position = _vector(spec.get("transform", {}).get("position", [0, 4, 0]))
	var rotation: Variant = spec.get("transform", {}).get("rotation_degrees", [0, 0, 0])
	body.rotation_degrees = _vector(rotation) if rotation is Array else Vector3(0, 0, float(rotation))
	var geometry := Primitive.build(spec.get("shape", {}))
	if not playback:
		body.collision_layer = int(physics.get("collision_layer", 1 if mode == "dynamic" else 2))
		body.collision_mask = int(physics.get("collision_mask", 3))
		var collider := CollisionShape3D.new()
		collider.shape = geometry["shape"]
		body.add_child(collider)
	if body is RigidBody3D:
		body.mass = maxf(0.001, float(physics.get("mass", 1)))
		body.gravity_scale = 0
		body.constant_force = _vector(document.get("world", {}).get("gravity", [0, -9.8, 0])) * body.mass
		body.linear_velocity = _vector(physics.get("velocity", [0, 0, 0]))
		body.angular_velocity = _vector(physics.get("angular_velocity", [0, 0, 0])) if physics.get("angular_velocity", []) is Array else Vector3.ZERO
		body.linear_damp = float(physics.get("linear_damp", 0.05))
		body.angular_damp = float(physics.get("angular_damp", 0.08))
		body.contact_monitor = true
		body.max_contacts_reported = 32
		body.continuous_cd = bool(physics.get("ccd", true))
		var material := PhysicsMaterial.new()
		material.bounce = clampf(float(physics.get("material", {}).get("restitution", 0.65)), 0, 1)
		material.friction = clampf(float(physics.get("material", {}).get("friction", 0.4)), 0, 1)
		body.physics_material_override = material
	var visual := MeshInstance3D.new()
	visual.mesh = geometry["mesh"]
	visual.material_override = StandardMaterial3D.new()
	body.add_child(visual)
	var outline := Primitive.debug_mesh(geometry["shape"])
	body.add_child(outline)
	records[id] = {"spec": spec, "body": body, "visual": visual, "outline": outline, "born": born}
	add_child(body)
	_update_material(id)
	if not playback:
		emit_event({"type": "birth", "id": id, "parent": spec.get("parent", ""), "position": object_position(id), "generation": spec["generation"], "time": maxf(0, born)})


## Remove an active body but keep its serialized definition.
func remove_object(id: String) -> void:
	if not records.has(id): return
	var body: Node = records[id]["body"]
	remove_child(body)
	body.queue_free()
	records.erase(id)


## Gather current solver contacts and sensor overlaps into stable object pairs.
func contact_pairs() -> Dictionary:
	var result: Dictionary = {}
	for id in records:
		var body = records[id]["body"]
		var others: Array = []
		if body is RigidBody3D: others = body.get_colliding_bodies()
		elif body is Area3D: others = body.get_overlapping_bodies()
		for other in others:
			var other_id := str(other.get_meta("object_id", ""))
			if other_id.is_empty() or not records.has(other_id): continue
			var ids: Array = [str(id), other_id]
			ids.sort()
			var key := "%s|%s" % ids
			if result.has(key): continue
			var pair: Dictionary = ContactAnchor.for_3d(records, ids[0], ids[1])
			pair.merge({"a": ids[0], "b": ids[1]})
			result[key] = pair
	return result


## Evaluate mechanisms once per physical tick, never during replay.
func _physics_process(_delta: float) -> void:
	if not playback: runner.step()


## Capture real body poses with quaternion rotations for robust interpolation.
func capture_state() -> Array:
	var result: Array = []
	for id in records:
		var q: Quaternion = records[id]["body"].quaternion
		result.append({"id": id, "position": object_position(id), "rotation": [q.x, q.y, q.z, q.w],
			"velocity": object_velocity(id), "color": _color(records[id]["spec"]).to_html(), "generation": records[id]["spec"].get("generation", 0)})
	return result


## Return known object definitions including retired generations.
func get_definitions() -> Dictionary:
	return definitions.duplicate(true)


## Restore pure display nodes to the exact recorded lifecycle and pose.
func apply_state(states: Array, all_definitions: Dictionary) -> void:
	if not playback: return
	var keep: Dictionary = {}
	for state in states:
		var id := str(state["id"])
		keep[id] = true
		if not records.has(id) and all_definitions.has(id): create_object(all_definitions[id], 0)
		if not records.has(id): continue
		var body: Node3D = records[id]["body"]
		body.position = _vector(state["position"])
		var q: Array = state["rotation"]
		body.quaternion = Quaternion(float(q[0]), float(q[1]), float(q[2]), float(q[3])).normalized()
	for id in records.keys():
		if not keep.has(id): remove_object(id)


## Apply materials, background, lights and camera without changing physical state.
func apply_presentation(doc: Dictionary) -> void:
	document["presentation"] = doc.get("presentation", {}).duplicate(true)
	document["objects"] = doc.get("objects", []).duplicate(true)
	var render: Dictionary = document["presentation"].get("render", {})
	environment.environment.background_color = Color(str(render.get("background", "#101827")))
	light.shadow_enabled = bool(render.get("shadows", true))
	light.light_energy = float(render.get("light_energy", 1.5))
	var view: Dictionary = render.get("camera", {})
	camera.position = _vector(view.get("position", [13, 15, 20]))
	camera.size = float(view.get("size", 23))
	camera.fov = float(view.get("fov", 46))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL if view.get("projection", "orthographic") in ["orthographic", "orthogonal"] else Camera3D.PROJECTION_PERSPECTIVE
	camera.look_at(_vector(view.get("target", [0, 2.3, 0])))
	for incoming in doc.get("objects", []):
		for id in records:
			if records[id]["spec"].get("root_id", id) == incoming["id"]:
				records[id]["spec"]["appearance"] = incoming.get("appearance", {}).duplicate(true)
	for id in records: _update_material(id)


## Highlight selection without touching collision shapes or motion.
func set_debug(enabled: bool, selected: String = "") -> void:
	if debug_enabled == enabled and selected_id == selected: return
	debug_enabled = enabled
	selected_id = selected
	for id in records: _update_material(id)


## Ray-test visible sphere/box meshes, including edit and replay modes without colliders.
func pick(point: Vector2) -> String:
	var ray_start := camera.project_ray_origin(point)
	var ray_end := ray_start + camera.project_ray_normal(point) * 1000
	var selected := ""
	var nearest := INF
	for id in records:
		var body: Node3D = records[id]["body"]
		var inverse := body.global_transform.affine_inverse()
		var spec: Dictionary = records[id]["spec"]
		var shape: Dictionary = spec.get("shape", {})
		var half := Vector3.ONE * float(shape.get("radius", 0.44)) if shape.get("primitive", "") == "sphere" else _vector(shape.get("size", [1, 1, 1])) / 2
		var hit: Variant = AABB(-half, half * 2).intersects_segment(inverse * ray_start, inverse * ray_end)
		if shape.get("primitive", "") == "sphere":
			var hits := Geometry3D.segment_intersects_sphere(inverse * ray_start, inverse * ray_end, Vector3.ZERO, half.x)
			hit = hits[0] if not hits.is_empty() else null
		if hit != null:
			var distance := ray_start.distance_to(body.global_transform * hit)
			if distance < nearest:
				nearest = distance
				selected = id
	return selected


## Place edited objects on their current-height XZ plane using the real camera ray.
func placement_position(point: Vector2, id: String = "") -> Array:
	var height := _position(id).y if records.has(id) else 0.5
	var hit: Variant = Plane(Vector3.UP, height).intersects_ray(camera.project_ray_origin(point), camera.project_ray_normal(point))
	return _array(hit) if hit is Vector3 else [0, height, 0]


## Convert a world event into logical stage coordinates for overlay effects.
func project_point(position: Array) -> Vector2:
	return camera.unproject_position(_vector(position))


## Report physical counters and escapes independently of visual settings.
func get_report() -> Dictionary:
	var escaped := 0
	for id in records:
		if _position(id).y < -3: escaped += 1
	return {"active": dynamic_count(), "objects": records.size(), "contacts": runner.contacts, "splits": runner.splits,
		"retired": runner.retired, "births": initial_dynamic + runner.births, "ledger_ok": playback or initial_dynamic + runner.births == dynamic_count() + runner.retired,
		"physics_tick": runner.physics_tick, "rejections": runner.rejections, "escaped": escaped, "playback": playback}


## Search whole free-space arrangements without moving children into existing geometry.
func birth_positions(id: String, count: int, radius: float) -> Array:
	return Primitive.find_birth_positions(self, id, count, radius)


## Adapter helpers keep the shared mechanism component independent of spatial dimension.
func child_velocity(center: Array, point: Array, velocity: Array, speed: float) -> Array:
	return _array(_vector(velocity) + (_vector(point) - _vector(center)).normalized() * speed)
func _position(id: String) -> Vector3: # Read the current native or playback position.
	return records[id]["body"].position
func object_position(id: String) -> Array: # Expose JSON-compatible coordinates to mechanisms.
	return _array(_position(id))
func object_velocity(id: String) -> Array: # Read actual motion for child spawning.
	var body = records[id]["body"]
	return _array(body.linear_velocity) if body is RigidBody3D else [0.0, 0.0, 0.0]
func dynamic_count() -> int: # Count active dynamics for transactional capacity checks.
	var count := 0
	for record in records.values():
		if record["spec"].get("physics", {}).get("mode", "dynamic") == "dynamic": count += 1
	return count
func source_kind(id: String) -> String: # Classify contact participants for the event ledger.
	var spec: Dictionary = definitions.get(id, {})
	return "sensor" if spec.get("physics", {}).get("mode", "") == "sensor" else ("ball" if spec.get("shape", {}).get("primitive", "") == "sphere" else "box")
func emit_event(event: Dictionary) -> void: # Forward committed physics and mechanism events.
	event_logged.emit(event)
func _array(value: Vector3) -> Array: # Convert native vectors to serializable coordinates.
	return [value.x, value.y, value.z]
func _vector(value: Array) -> Vector3: # Convert validated scene coordinates to native vectors.
	return Vector3(float(value[0]), float(value[1]), float(value[2])) if value.size() >= 3 else Vector3.ZERO
func _color(spec: Dictionary) -> Color: # Apply the current generation's appearance.
	var appearance: Dictionary = spec.get("appearance", {})
	for initial in document.get("objects", []):
		if initial["id"] == spec.get("root_id", spec["id"]): appearance = initial.get("appearance", {})
	var color := Color(str(appearance.get("color", "#22c55e")))
	var fade := clampf(float(appearance.get("generation_color", {}).get("fade", 0.2)), 0, 0.6)
	return color.lerp(Color.WHITE, 0.85 * (1 - pow(1 - fade, int(spec.get("generation", 0)))))
func _update_material(id: String) -> void: # Refresh visual resources without touching physical motion.
	var material: StandardMaterial3D = records[id]["visual"].material_override
	var render: Dictionary = document.get("presentation", {}).get("render", {})
	Primitive.update_material(material, _color(records[id]["spec"]), render, id == selected_id)
	records[id]["outline"].visible = debug_enabled or id == selected_id
