extends SceneTree
## Isolated feasibility check, not a workbench feature. Compile concave outlines and run native physics.
var l_contacts := 0
var u_contacts := 0


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	_run.call_deferred()


## Use one body with several convex fixtures, preserving the original concave outline.
func polygon_body(points: PackedVector2Array, dynamic: bool, position: Vector2) -> PhysicsBody2D:
	var body: PhysicsBody2D = RigidBody2D.new() if dynamic else StaticBody2D.new()
	body.position = position
	for part in Geometry2D.decompose_polygon_in_convex(points):
		var shape := ConvexPolygonShape2D.new()
		shape.points = part
		var collider := CollisionShape2D.new()
		collider.shape = shape
		body.add_child(collider)
	var material := PhysicsMaterial.new()
	material.friction = 0.2
	material.bounce = 0.15
	body.physics_material_override = material
	if body is RigidBody2D:
		body.mass = 1.0
		body.gravity_scale = 0
		body.constant_force = Vector2(0, 450) * body.mass
		body.continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
		body.contact_monitor = true
		body.max_contacts_reported = 32
	root.add_child(body)
	return body


## Compute signed-outline area magnitude for decomposition conservation checks.
func area(points: PackedVector2Array) -> float:
	var result := 0.0
	for index in points.size(): result += points[index].cross(points[(index + 1) % points.size()])
	return absf(result) * 0.5


## Exercise L-shaped dynamic and U-shaped static objects without altering their solved poses.
func _run() -> void:
	var l_points := PackedVector2Array([Vector2(-60,-60),Vector2(60,-60),Vector2(60,-20),Vector2(-20,-20),Vector2(-20,60),Vector2(-60,60)])
	var u_points := PackedVector2Array([Vector2(-120,-120),Vector2(-80,-120),Vector2(-80,80),Vector2(80,80),Vector2(80,-120),Vector2(120,-120),Vector2(120,120),Vector2(-120,120)])
	var parts_l := Geometry2D.decompose_polygon_in_convex(l_points)
	var parts_u := Geometry2D.decompose_polygon_in_convex(u_points)
	var area_l := 0.0
	var area_u := 0.0
	for part in parts_l: area_l += area(part)
	for part in parts_u: area_u += area(part)
	var l_body := polygon_body(l_points, true, Vector2(200, 100)) as RigidBody2D
	var u_body := polygon_body(u_points, false, Vector2(650, 400))
	var floor_body := StaticBody2D.new()
	floor_body.position = Vector2(350, 580)
	var floor_shape := RectangleShape2D.new()
	floor_shape.size = Vector2(900, 20)
	var floor_collider := CollisionShape2D.new()
	floor_collider.shape = floor_shape
	floor_body.add_child(floor_collider)
	root.add_child(floor_body)
	l_body.body_entered.connect(func(body):
		if body == floor_body: l_contacts += 1)
	var ball := RigidBody2D.new()
	ball.position = Vector2(650, 180)
	ball.gravity_scale = 0
	ball.constant_force = Vector2(0, 450)
	ball.continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	ball.contact_monitor = true
	ball.max_contacts_reported = 16
	var circle := CircleShape2D.new()
	circle.radius = 12
	var ball_collider := CollisionShape2D.new()
	ball_collider.shape = circle
	ball.add_child(ball_collider)
	root.add_child(ball)
	ball.body_entered.connect(func(body):
		if body == u_body: u_contacts += 1)
	var greatest_y := -INF
	for tick in 360:
		await physics_frame
		for point in l_points: greatest_y = maxf(greatest_y, (l_body.global_transform * point).y)
	var checks := {
		"l_has_multiple_convex_fixtures": parts_l.size() > 1,
		"u_has_multiple_convex_fixtures": parts_u.size() > 1,
		"l_area_preserved": absf(area_l - area(l_points)) < 0.001,
		"u_area_preserved": absf(area_u - area(u_points)) < 0.001,
		"l_reached_native_floor_contact": l_contacts > 0,
		"l_no_floor_pass_through_in_sample": greatest_y < 575,
		"ball_entered_u_opening": ball.position.y > 400,
		"ball_contacts_actual_u_body": u_contacts > 0,
		"ball_remains_above_u_inner_floor": ball.position.y < 480
	}
	var passed := true
	for value in checks.values(): passed = passed and bool(value)
	var report := {"scope": "isolated_native_feasibility", "integrated_into_workbench": false,
		"engine": Engine.get_version_info(), "physics_ticks": 360, "checks": checks, "passed": passed,
		"l_convex_parts": parts_l.size(), "u_convex_parts": parts_u.size(),
		"l_original_area": area(l_points), "l_compiled_area": area_l,
		"u_original_area": area(u_points), "u_compiled_area": area_u,
		"l_floor_contacts": l_contacts, "u_ball_contacts": u_contacts,
		"l_max_vertex_y": greatest_y, "ball_final_y": ball.position.y}
	var report_path := "user://native-shape-validation.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="): report_path = argument.trim_prefix("--report=")
	var output := FileAccess.open(report_path, FileAccess.WRITE)
	if output == null:
		push_error("Unable to write native shape report: " + report_path)
		quit(2)
		return
	output.store_string(JSON.stringify(report, "  "))
	output.close()
	print(JSON.stringify(report))
	quit(0 if passed else 1)
