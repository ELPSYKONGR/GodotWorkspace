extends SceneTree
## Validate fast-ball CCD in a fresh physics space, independent of geometry-query fixtures.

## Defer native creation until the SceneTree is initialized.
func _initialize() -> void:
	_run.call_deferred()

## At the inspector's maximum speed, a ball must not pass completely through the floor.
func _run() -> void:
	Engine.physics_ticks_per_second = 60
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/workbench_2d.json"))
	doc["world"]["physics_hz"] = 60
	doc["mechanisms"] = []
	for spec in doc["objects"]: spec["mechanisms"] = []
	doc["objects"][0]["transform"]["position"] = [360, 500]
	doc["objects"][0]["physics"]["velocity"] = [0, 5000]
	var world = load("res://src/physics/world_2d.gd").new()
	world.setup(doc)
	root.add_child(world)
	var body: RigidBody2D = world.records["ball_A"]["body"]
	var bounded := true
	var swept := false
	for tick in 18:
		await physics_frame
		bounded = bounded and body.position.y < 1150
		swept = swept or body.continuous_cd == RigidBody2D.CCD_MODE_CAST_SHAPE
	var report := {"fast_ball_uses_shape_ccd": swept, "fast_ball_stays_above_floor": bounded, "passed": swept and bounded}
	var file := FileAccess.open("res://outputs/fast_ccd_validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("FAST_CCD ", JSON.stringify(report))
	quit(0 if report["passed"] else 1)
