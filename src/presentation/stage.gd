extends Node2D
## Clean video stage shared by the workbench preview and independent renderer.
var world: Node
var effects: Node2D
var captions: Node2D
var document: Dictionary = {}
var scale_factor := 1.0
signal event_logged(event: Dictionary)

## A playback stage contains display objects only, never active rigid bodies.
func setup(doc: Dictionary, playback: bool, output_scale: float = 1.0) -> void:
	document = doc.duplicate(true)
	scale_factor = output_scale
	scale = Vector2.ONE * output_scale
	# The Compatibility backend has no 2D MSAA; smooth primitives in their draw code.
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		get_viewport().msaa_2d = Viewport.MSAA_4X
	get_viewport().msaa_3d = Viewport.MSAA_4X
	var file := "world_3d.gd" if doc["world"]["dimension"] == "3d" else "world_2d.gd"
	world = load("res://src/physics/" + file).new()
	world.event_logged.connect(func(event): event_logged.emit(event))
	world.setup(doc, playback)
	add_child(world)
	effects = load("res://src/presentation/effects.gd").new()
	effects.z_index = 10
	add_child(effects)
	apply_presentation(doc)

## Rebuild only visual resources; recorded or active motion remains unchanged.
func apply_presentation(doc: Dictionary) -> void:
	document = doc.duplicate(true)
	world.apply_presentation(doc)
	effects.configure(doc)
	if is_instance_valid(captions):
		remove_child(captions)
		captions.queue_free()
	captions = Node2D.new()
	captions.z_index = 20
	add_child(captions)
	for item in doc.get("presentation", {}).get("captions", []):
		var label := Label.new()
		label.text = str(item.get("text", ""))
		var xy: Array = item.get("position", [44, 54])
		label.position = Vector2(float(xy[0]), float(xy[1]))
		label.size.x = 640
		var font := SystemFont.new()
		font.font_names = PackedStringArray([str(item.get("font_family", "Microsoft YaHei")), "Noto Sans CJK SC"])
		label.add_theme_font_override("font", font)
		label.add_theme_font_size_override("font_size", int(item.get("font_size", 44)))
		label.add_theme_color_override("font_color", Color(str(item.get("color", "#edf5ff"))))
		captions.add_child(label)

## Project 3D points back to the common 720x1280 presentation coordinate space.
func project_point(position: Array) -> Vector2:
	return world.project_point(position) / (scale_factor if document["world"]["dimension"] == "3d" else 1.0)

## Evaluate analytic effects from explicit time rather than render wall-clock time.
func present(time: float, sim_time: float, events: Array, take: Dictionary = {}) -> void:
	effects.set_timeline(events)
	if not take.is_empty(): effects.set_take(take)
	# Live trails only need dynamic positions, not velocities/colors or static-body poses.
	var trail_states: Array = []
	if effects.settings.get("enabled", true) and effects.settings.get("trail_enabled", true) and take.is_empty():
		for id in world.records:
			if world.records[id]["spec"].get("physics", {}).get("mode", "dynamic") == "dynamic":
				var body = world.records[id].get("body")
				if (body is RigidBody2D or body is RigidBody3D) and body.sleeping: continue
				trail_states.append({"id": id, "position": world.object_position(id)})
	# Effects only read definitions; do not deep-copy retired generations every rendered frame.
	effects.present(time, sim_time, project_point, trail_states, world.definitions)
	if world.has_method("present_glass"): world.present_glass(sim_time,events)
