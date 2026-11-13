extends Node2D
## Real rigid-body probe. Call setup() before add_child(); all coordinates use 720x1280.

signal event_logged(event: Dictionary)

var config: Dictionary = {}
var balls: Dictionary = {}
var pending: Dictionary = {}
var retired_ids: Dictionary = {}
var events: Array[Dictionary] = []
var wall_rects: Array[Rect2] = []
var rng := RandomNumberGenerator.new()
var bounds := Rect2(44, 246, 632, 890)
var base_color := Color("22c55e")
var elapsed := 0.0
var radius := 18.0
var protection := 0.08
var capacity := 48
var children_per_split := 2
var next_id := 0
var births := 0
var retired := 0
var splits := 0
var max_generation := 0
var initial_count := 0
var duplicate_parent_splits := 0
var contact_counts: Dictionary = {}
var split_source_counts: Dictionary = {}
var flush_queued := false
var built := false


## Accepts scene data before the node is added to the running tree.
func setup(value: Dictionary) -> void:
	config = value.duplicate(true)
	if is_inside_tree() and not built:
		_build()


## Creates the physics world once the node enters the scene tree.
func _ready() -> void:
	_build()


## Converts the configuration into static walls and initial rigid bodies.
func _build() -> void:
	if built:
		return
	built = true
	rng.seed = int(config.get("seed", 20261113))
	radius = clampf(float(config.get("radius", 18.0)), 5.0, 36.0)
	protection = maxf(0.0, float(config.get("protection", 0.08)))
	capacity = clampi(int(config.get("max_balls", 48)), 4, 256)
	children_per_split = clampi(int(config.get("split_children", 2)), 2, 6)
	base_color = Color(str(config.get("color", "#22c55e")))
	var thickness := 14.0
	wall_rects = [
		Rect2(bounds.position - Vector2(thickness / 2, thickness / 2), Vector2(thickness, bounds.size.y + thickness)),
		Rect2(Vector2(bounds.end.x - thickness / 2, bounds.position.y - thickness / 2), Vector2(thickness, bounds.size.y + thickness)),
		Rect2(bounds.position - Vector2(thickness / 2, thickness / 2), Vector2(bounds.size.x + thickness, thickness)),
		Rect2(Vector2(bounds.position.x - thickness / 2, bounds.end.y - thickness / 2), Vector2(bounds.size.x + thickness, thickness))]
	var wall_names := ["wall_left", "wall_right", "wall_top", "wall_floor"]
	for wall_index in wall_rects.size():
		var rect: Rect2 = wall_rects[wall_index]
		var wall := StaticBody2D.new()
		wall.name = wall_names[wall_index]
		wall.position = rect.get_center()
		wall.collision_layer = 2
		wall.collision_mask = 1
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		var collider := CollisionShape2D.new()
		collider.shape = shape
		wall.add_child(collider)
		add_child(wall)
	var spawns: Array = config.get("spawns", [
		{"position": [240, 420], "velocity": [175, 65]},
		{"position": [480, 420], "velocity": [-175, 65]},
		{"position": [180, 1000], "velocity": [140, 120]}])
	for item in spawns:
		var xy: Array = item.get("position", [360, 400])
		var velocity: Array = item.get("velocity", [0, 100])
		_spawn(Vector2(float(xy[0]), float(xy[1])), Vector2(float(velocity[0]), float(velocity[1])), 0, -1, true)
	initial_count = balls.size()


## Registers one real rigid body and records its parent and generation.
func _spawn(point: Vector2, velocity: Vector2, generation: int, parent: int, seed_ball := false) -> int:
	var id := next_id
	next_id += 1
	var body := RigidBody2D.new()
	body.name = "Ball_%d" % id
	body.set_meta("ball_id", id)
	body.position = _inside(point)
	body.linear_velocity = velocity
	body.mass = 1.0
	body.can_sleep = false
	body.contact_monitor = true
	body.max_contacts_reported = 16
	body.continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	body.collision_layer = 1
	body.collision_mask = 3
	var default_gravity := float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))
	body.gravity_scale = float(config.get("gravity", 450.0)) / maxf(0.001, default_gravity)
	var material := PhysicsMaterial.new()
	material.bounce = clampf(float(config.get("restitution", 0.88)), 0, 1)
	material.friction = 0.03
	body.physics_material_override = material
	var circle := CircleShape2D.new()
	circle.radius = radius
	var collider := CollisionShape2D.new()
	collider.shape = circle
	body.add_child(collider)
	body.body_entered.connect(_contact.bind(id))
	body.body_exited.connect(_contact_ended.bind(id))
	balls[id] = {"body": body, "generation": generation, "born": elapsed - protection if seed_ball else elapsed, "contacts": {}}
	add_child(body)
	births += 1
	max_generation = maxi(max_generation, generation)
	_log({"type": "birth", "id": id, "parent": parent, "generation": generation, "position": [body.position.x, body.position.y]})
	return id


## Keeps newly created ball centers inside the wall boundaries.
func _inside(point: Vector2) -> Vector2:
	var padding := radius + 8.0
	return Vector2(clampf(point.x, bounds.position.x + padding, bounds.end.x - padding), clampf(point.y, bounds.position.y + padding, bounds.end.y - padding))


## Records an engine-reported contact and schedules an eligible replacement.
func _contact(other: Node, id: int) -> void:
	# Both signal and polling use the same contact gate: only current engine contacts qualify.
	if not balls.has(id):
		return
	var record: Dictionary = balls[id]
	var source := {"kind": "ball" if other.has_meta("ball_id") else "wall", "name": str(other.name),
		"id": int(other.get_meta("ball_id", -1))}
	var key := str(other.get_instance_id())
	var eligible := elapsed - float(record["born"]) + 0.000001 >= protection
	if not record["contacts"].has(key):
		record["contacts"][key] = source
		var kind: String = source["kind"]
		contact_counts[kind] = int(contact_counts.get(kind, 0)) + 1
		_log({"type": "contact", "id": id, "other": source, "eligible": eligible})
	if eligible:
		if not pending.has(id):
			pending[id] = {}
		pending[id][key] = source
		_queue_flush()


## Clears contacts that ended during the short newborn protection window.
func _contact_ended(other: Node, id: int) -> void:
	# Removing a protected contact prevents a later in-air split when its protection expires.
	if balls.has(id):
		balls[id]["contacts"].erase(str(other.get_instance_id()))


## Retries current contacts when newborn protection expires and updates drawing.
func _physics_process(delta: float) -> void:
	elapsed += delta
	for id in balls.keys():
		var record: Dictionary = balls[id]
		var body: RigidBody2D = record["body"]
		for other in body.get_colliding_bodies():
			_contact(other, id)
	_queue_flush()
	queue_redraw()


## Defers body replacement until the physics server finishes contact callbacks.
func _queue_flush() -> void:
	if not pending.is_empty() and not flush_queued:
		flush_queued = true
		_flush_splits.call_deferred()


## Replaces each eligible parent once, respecting the active-body capacity.
func _flush_splits() -> void:
	flush_queued = false
	var ids: Array = pending.keys()
	var sources: Dictionary = pending.duplicate(true)
	pending.clear()
	ids.sort()
	for id in ids:
		if not balls.has(id) or balls.size() >= capacity:
			continue
		var record: Dictionary = balls[id]
		var body: RigidBody2D = record["body"]
		var point := body.position
		var velocity := body.linear_velocity
		var generation := int(record["generation"]) + 1
		balls.erase(id)
		remove_child(body)
		body.queue_free()
		if retired_ids.has(id):
			duplicate_parent_splits += 1
		retired_ids[id] = true
		retired += 1
		splits += 1
		_log({"type": "retire", "id": id, "reason": "split", "generation": int(record["generation"])})
		var count := mini(children_per_split, capacity - balls.size())
		var child_ids: Array[int] = []
		var phase := rng.randf_range(0, TAU)
		var ring := radius * 1.07 / sin(PI / float(count))
		for index in count:
			var direction := Vector2.from_angle(phase + TAU * index / float(count))
			child_ids.append(_spawn(point + direction * ring, velocity * 0.45 + direction * 150, generation, id))
		var split_sources: Array = sources[id].values()
		for source in split_sources:
			var kind: String = source["kind"]
			split_source_counts[kind] = int(split_source_counts.get(kind, 0)) + 1
		_log({"type": "split", "parent": id, "children": child_ids, "generation": generation,
			"position": [point.x, point.y], "sources": split_sources})
	queue_redraw()


## Keeps an auditable event ledger and forwards events to the preview host.
func _log(event: Dictionary) -> void:
	event["time"] = elapsed
	events.append(event)
	event_logged.emit(event)


## Renders walls and bodies using their actual physics positions.
func _draw() -> void:
	draw_rect(bounds, Color("0c1722"))
	for rect in wall_rects:
		draw_rect(rect, Color("42667d"))
	var fade := clampf(float(config.get("generation_fade", 0.2)), 0, 0.6)
	for record in balls.values():
		var body: RigidBody2D = record["body"]
		var tint := 0.85 * (1.0 - pow(1.0 - fade, int(record["generation"])))
		var color := base_color.lerp(Color.WHITE, tint)
		draw_circle(body.position, radius, color)
		if bool(config.get("debug_colliders", false)):
			draw_circle(body.position, radius, Color.WHITE, false, 1.0)


## Exposes counters and raw events for independent acceptance checks.
func get_report() -> Dictionary:
	return {"mode": "2d", "physics": "Godot RigidBody2D", "elapsed": elapsed, "initial_count": initial_count,
		"active": balls.size(), "births": births, "retired": retired, "splits": splits, "max_generation": max_generation,
		"max_balls": capacity, "ledger_ok": births == retired + balls.size(), "duplicate_parent_splits": duplicate_parent_splits,
		"contact_counts": contact_counts.duplicate(), "split_source_counts": split_source_counts.duplicate(),
		"active_ids": balls.keys(), "retired_ids": retired_ids.keys(), "events": events.duplicate(true)}
