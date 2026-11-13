extends Node2D
## Native 2D world adapter; playback uses data-only visuals without physics bodies.

signal event_logged(event: Dictionary)
const Rules = preload("res://src/mechanisms/contact_rules.gd")
const ContactAnchor = preload("res://src/physics/contact_anchor.gd")
var document: Dictionary = {}
var records: Dictionary = {}
var definitions: Dictionary = {}
var playback := false
var dimensions := 2
var runner: Node
var debug_enabled := false
var selected_id := ""
var initial_dynamic := 0


## Accept immutable initial scene data before entering the scene tree.
func setup(doc: Dictionary, replay: bool = false) -> void:
	document = doc.duplicate(true)
	playback = replay


## Construct objects and the shared contact-rule component.
func _ready() -> void:
	runner = Rules.new()
	runner.setup(self, document)
	add_child(runner)
	for spec in document.get("objects", []):
		create_object(spec, -1000.0)
	initial_dynamic = dynamic_count()


## Build a circle/box/sensor from the same geometry that is drawn on screen.
func create_object(value: Dictionary, born: float) -> void:
	var spec := value.duplicate(true)
	var id := str(spec["id"])
	spec["root_id"] = spec.get("root_id", id)
	spec["generation"] = int(spec.get("generation", 0))
	definitions[id] = spec
	var xy: Array = spec.get("transform", {}).get("position", [360, 400])
	var record := {"spec": spec, "born": born, "position": Vector2(float(xy[0]), float(xy[1])),
		"rotation": deg_to_rad(float(spec.get("transform", {}).get("rotation_degrees", 0)))}
	if not playback:
		var physics: Dictionary = spec.get("physics", {})
		var mode := str(physics.get("mode", "dynamic"))
		var body: CollisionObject2D
		if mode == "sensor": body = Area2D.new()
		elif mode == "static": body = StaticBody2D.new()
		else: body = RigidBody2D.new()
		body.name = "Body_" + id
		body.set_meta("object_id", id)
		body.position = record["position"]
		body.rotation = record["rotation"]
		body.collision_layer = int(physics.get("collision_layer", 1 if mode == "dynamic" else 2))
		body.collision_mask = int(physics.get("collision_mask", 3))
		var collider := CollisionShape2D.new()
		var shape: Dictionary = spec.get("shape", {})
		if shape.get("primitive", "circle") == "circle":
			var circle := CircleShape2D.new()
			circle.radius = maxf(1, float(shape.get("radius", 18)))
			collider.shape = circle
		else:
			var box := RectangleShape2D.new()
			box.size = _size(spec)
			collider.shape = box
		body.add_child(collider)
		if body is RigidBody2D:
			body.mass = maxf(0.001, float(physics.get("mass", 1)))
			var velocity: Array = physics.get("velocity", [0, 0])
			body.linear_velocity = Vector2(float(velocity[0]), float(velocity[1]))
			body.angular_velocity = float(physics.get("angular_velocity", 0))
			body.can_sleep = false
			body.contact_monitor = true
			body.max_contacts_reported = 32
			body.continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE if physics.get("ccd", true) else RigidBody2D.CCD_MODE_DISABLED
			var gravity: Array = document.get("world", {}).get("gravity", [0, 450])
			body.gravity_scale = 0
			body.constant_force = Vector2(float(gravity[0]), float(gravity[1])) * body.mass
			body.linear_damp = float(physics.get("linear_damp", 0))
			var material := PhysicsMaterial.new()
			material.bounce = clampf(float(physics.get("material", {}).get("restitution", 0.88)), 0, 1)
			material.friction = clampf(float(physics.get("material", {}).get("friction", 0.03)), 0, 1)
			body.physics_material_override = material
		record["body"] = body
		add_child(body)
	records[id] = record
	if not playback:
		emit_event({"type": "birth", "id": id, "parent": spec.get("parent", ""), "position": xy, "generation": spec["generation"], "time": maxf(0, born)})
	queue_redraw()


## Remove one active object while retaining its definition for recorded lifecycle data.
func remove_object(id: String) -> void:
	if not records.has(id): return
	var record: Dictionary = records[id]
	if record.has("body"):
		remove_child(record["body"])
		record["body"].queue_free()
	records.erase(id)
	queue_redraw()


## Native contact lists are the sole source of contact eligibility.
func contact_pairs() -> Dictionary:
	var pairs: Dictionary = {}
	for id in records:
		var record: Dictionary = records[id]
		var body = record.get("body")
		var others: Array = []
		if body is RigidBody2D: others = body.get_colliding_bodies()
		elif body is Area2D: others = body.get_overlapping_bodies()
		for other in others:
			var other_id := str(other.get_meta("object_id", ""))
			if other_id.is_empty() or not records.has(other_id): continue
			var ids: Array = [str(id), other_id]
			ids.sort()
			var pair: Dictionary = ContactAnchor.for_2d(records, ids[0], ids[1])
			pair.merge({"a": ids[0], "b": ids[1]})
			pairs["%s|%s" % ids] = pair
	return pairs


## Advance rule evaluation at fixed physics frequency.
func _physics_process(_delta: float) -> void:
	if not playback:
		runner.step()
	queue_redraw()


## Return compact poses including static objects for complete playback reconstruction.
func capture_state() -> Array:
	var result: Array = []
	for id in records:
		var record: Dictionary = records[id]
		result.append({"id": id, "position": object_position(id), "rotation": _rotation(id),
			"velocity": object_velocity(id), "color": _color(record["spec"]).to_html(), "generation": record["spec"].get("generation", 0)})
	return result


## Return all definitions, including retired parents, for Take metadata.
func get_definitions() -> Dictionary:
	return definitions.duplicate(true)


## Restore only recorded display objects; no colliders or mechanisms run in playback.
func apply_state(states: Array, all_definitions: Dictionary) -> void:
	if not playback: return
	var keep: Dictionary = {}
	for state in states:
		var id := str(state["id"])
		keep[id] = true
		if not records.has(id) and all_definitions.has(id): create_object(all_definitions[id], 0)
		if not records.has(id): continue
		records[id]["position"] = Vector2(float(state["position"][0]), float(state["position"][1]))
		records[id]["rotation"] = float(state["rotation"])
	for id in records.keys():
		if not keep.has(id): remove_object(id)
	queue_redraw()


## Update presentation without replacing any physical body.
func apply_presentation(doc: Dictionary) -> void:
	document["presentation"] = doc.get("presentation", {}).duplicate(true)
	document["objects"] = doc.get("objects", []).duplicate(true)
	for incoming in doc.get("objects", []):
		for id in records:
			if records[id]["spec"].get("root_id", id) == incoming["id"]:
				records[id]["spec"]["appearance"] = incoming.get("appearance", {}).duplicate(true)
	queue_redraw()


## Set editor-only selection and collider overlays.
func set_debug(enabled: bool, selected: String = "") -> void:
	debug_enabled = enabled
	selected_id = selected
	queue_redraw()


## Hit-test the same shapes as the visible and physical objects.
func pick(point: Vector2) -> String:
	var ids := records.keys()
	ids.reverse()
	for id in ids:
		var local := (point - _position(id)).rotated(-_rotation(id))
		var spec: Dictionary = records[id]["spec"]
		if spec.get("shape", {}).get("primitive", "") == "circle":
			if local.length() <= float(spec["shape"].get("radius", 18)): return id
		elif Rect2(-_size(spec) / 2, _size(spec)).has_point(local): return id
	return ""


## Convert a logical pointer position to scene placement coordinates.
func placement_position(point: Vector2, _id: String = "") -> Array:
	return project_array(point)


## Project a world event into the fixed 720x1280 stage.
func project_point(position: Array) -> Vector2:
	return Vector2(float(position[0]), float(position[1])) if position.size() >= 2 else Vector2.ZERO


## Report independent counts without copying the full event log each frame.
func get_report() -> Dictionary:
	return {"active": dynamic_count(), "objects": records.size(), "contacts": runner.contacts, "splits": runner.splits,
		"retired": runner.retired, "births": initial_dynamic + runner.births, "ledger_ok": playback or initial_dynamic + runner.births == dynamic_count() + runner.retired,
		"physics_tick": runner.physics_tick, "rejections": runner.rejections, "playback": playback}


## Find a complete non-overlapping child arrangement, never clamp children through walls.
func birth_positions(id: String, count: int, radius: float) -> Array:
	var center := _position(id)
	var ring := radius * 1.08 / sin(PI / count)
	for offset in [Vector2.ZERO, Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		for phase_index in 12:
			var result: Array = []
			for index in count:
				var point: Vector2 = center + offset * radius * 0.6 + Vector2.from_angle(phase_index * PI / 12 + TAU * index / count) * ring
				if not _space_free(point, radius, id): break
				result.append(project_array(point))
			if result.size() == count: return result
	return []


## Test a candidate circle against the configured circle/rotated-box geometry.
func _space_free(point: Vector2, radius: float, ignored: String) -> bool:
	for id in records:
		if id == ignored or source_kind(id) == "sensor": continue
		var spec: Dictionary = records[id]["spec"]
		var local := (point - _position(id)).rotated(-_rotation(id))
		if spec.get("shape", {}).get("primitive", "") == "circle":
			if local.length() < radius + float(spec["shape"].get("radius", 18)) + 0.05: return false
		else:
			var half := _size(spec) / 2
			if local.distance_to(local.clamp(-half, half)) < radius + 0.05: return false
	return true


## Apply configurable gameplay ejection independently of the native bounce material.
func child_velocity(center: Array, point: Array, velocity: Array, speed: float) -> Array:
	var direction := (project_point(point) - project_point(center)).normalized()
	return project_array(project_point(velocity) + direction * speed)


## Draw bodies at their actual solver poses, or the selected recorded poses.
func _draw() -> void:
	var render: Dictionary = document.get("presentation", {}).get("render", {})
	draw_rect(Rect2(0, 0, 720, 1280), Color(str(render.get("background", "#0c1722"))))
	for id in records:
		var spec: Dictionary = records[id]["spec"]
		draw_set_transform(_position(id), _rotation(id))
		var circle: bool = spec.get("shape", {}).get("primitive", "") == "circle"
		if circle: draw_circle(Vector2.ZERO, float(spec["shape"].get("radius", 18)), _color(spec))
		else: draw_rect(Rect2(-_size(spec) / 2, _size(spec)), _color(spec))
		if debug_enabled or id == selected_id or bool(render.get("outline", false)):
			var tint := Color("fbbf24") if id == selected_id else Color(1, 1, 1, 0.5)
			if circle: draw_circle(Vector2.ZERO, float(spec["shape"].get("radius", 18)), tint, false, 2)
			else: draw_rect(Rect2(-_size(spec) / 2, _size(spec)), tint, false, 2)
	draw_set_transform(Vector2.ZERO)


## Small adapter helpers expose a dimension-neutral interface to the rule component.
func _position(id: String) -> Vector2:
	return records[id]["body"].position if records[id].has("body") else records[id]["position"]
func _rotation(id: String) -> float: # Read the current native or playback angle.
	return records[id]["body"].rotation if records[id].has("body") else float(records[id]["rotation"])
func object_position(id: String) -> Array: # Expose a JSON-compatible position to mechanisms.
	return project_array(_position(id))
func object_velocity(id: String) -> Array: # Read actual motion for child spawning.
	var body = records[id].get("body")
	return project_array(body.linear_velocity) if body is RigidBody2D else [0.0, 0.0]
func dynamic_count() -> int: # Count active dynamics for transactional capacity checks.
	var count := 0
	for record in records.values():
		if record["spec"].get("physics", {}).get("mode", "dynamic") == "dynamic": count += 1
	return count
func source_kind(id: String) -> String: # Classify contact participants for the event ledger.
	var spec: Dictionary = definitions.get(id, {})
	return "sensor" if spec.get("physics", {}).get("mode", "") == "sensor" else ("ball" if spec.get("shape", {}).get("primitive", "") == "circle" else "box")
func emit_event(event: Dictionary) -> void: # Forward committed physics and mechanism events.
	event_logged.emit(event)
func project_array(value: Vector2) -> Array: # Convert native vectors to serializable coordinates.
	return [value.x, value.y]
func _size(spec: Dictionary) -> Vector2: # Read the rectangle extent from scene data.
	var size: Array = spec.get("shape", {}).get("size", [60, 20])
	return Vector2(maxf(1, float(size[0])), maxf(1, float(size[1])))
func _color(spec: Dictionary) -> Color: # Apply the current generation's appearance.
	var appearance: Dictionary = spec.get("appearance", {})
	for initial in document.get("objects", []):
		if initial["id"] == spec.get("root_id", spec["id"]): appearance = initial.get("appearance", {})
	var color := Color(str(appearance.get("color", "#22c55e")))
	var fade := float(appearance.get("generation_color", {}).get("fade", 0.2))
	return color.lerp(Color.WHITE, 0.85 * (1 - pow(1 - clampf(fade, 0, 0.6), int(spec.get("generation", 0)))))
