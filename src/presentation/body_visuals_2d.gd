extends Node2D
## Render-only subtree: camera movement here cannot move native collision bodies.
const Geometry = preload("res://src/document/shape_geometry.gd")
const Style = preload("res://src/document/object_style.gd")
var world: Node2D
var custom_batches: Dictionary = {}

## Batch custom materials by settings, retaining the existing shared default material path.
func _draw() -> void:
	if not is_instance_valid(world.ball_batch): return
	var render: Dictionary = world.document.get("presentation", {}).get("render", {})
	var plain: Array = []
	var balls: Array = []
	var walls: Array = []
	var groups: Dictionary = {}
	for id in world.records:
		var spec: Dictionary = world.records[id]["spec"]
		if spec.has("glass"): continue
		var material := Style.material(spec, render)
		var neon: Dictionary = material.get("neon", {})
		var glowing := bool(neon.get("enabled", false))
		var custom: bool = spec.get("appearance", {}).get("material", {}).get("mode", "inherit") == "custom"
		var key := JSON.stringify(neon, "", true) if custom and glowing else ""
		if not key.is_empty() and not groups.has(key): groups[key] = {"settings": neon, "balls": [], "walls": []}
		draw_set_transform(world._position(id), world._rotation(id))
		var circle: bool = spec["shape"].get("primitive", "") == "circle"
		var color: Color = world._color(spec)
		if circle:
			var item := {"position": world._position(id), "size": float(spec["shape"].get("radius", 18)), "color": color}
			if not glowing: plain.append(item)
			elif key.is_empty(): balls.append(item)
			else: groups[key]["balls"].append(item)
		elif spec["shape"].get("primitive", "") in ["polygon", "arc"]:
			var points: PackedVector2Array = Geometry.polygon(spec["shape"]) if spec["shape"]["primitive"] == "polygon" else world.GlassGeometry.polygon(spec["shape"])
			draw_colored_polygon(points, color)
			if glowing:
				points.append(points[0])
				draw_polyline(points, color.lightened(0.35), 2, true)
		else:
			var item := {"position": world._position(id), "rotation": world._rotation(id), "half_size": world._size(spec) / 2, "color": color}
			if not glowing: draw_rect(Rect2(-world._size(spec) / 2, world._size(spec)), color)
			elif key.is_empty(): walls.append(item)
			else: groups[key]["walls"].append(item)
		if world.debug_enabled or id == world.selected_id or render.get("outline", false):
			var tint := Color("fbbf24") if id == world.selected_id else Color(1, 1, 1, 0.5)
			if circle: draw_circle(Vector2.ZERO, float(spec["shape"].get("radius", 18)), tint, false, 2)
			elif spec["shape"].get("primitive", "") == "polygon":
				var points := Geometry.polygon(spec["shape"])
				points.append(points[0]); draw_polyline(points, tint, 2, true)
			else: draw_rect(Rect2(-world._size(spec) / 2, world._size(spec)), tint, false, 2)
	draw_set_transform(Vector2.ZERO)
	world.ball_batch.visible = true
	world.ball_batch.update_circles(plain, "ball")
	world.neon.present(balls, walls)
	for key in custom_batches.keys():
		if not groups.has(key):
			custom_batches[key].queue_free()
			custom_batches.erase(key)
	for key in groups:
		if not custom_batches.has(key):
			var batch := preload("res://src/presentation/neon_2d.gd").new()
			add_child(batch)
			batch.configure(groups[key]["settings"])
			custom_batches[key] = batch
		custom_batches[key].visible = true
		custom_batches[key].present(groups[key]["balls"], groups[key]["walls"])
