extends RefCounted
## Compile one validated shape into colliders belonging to the same native body.
const Geometry = preload("res://src/document/shape_geometry.gd")

## Concave polygons retain their notch; convex pieces are fixtures, not independent shards.
static func colliders(shape: Dictionary) -> Array:
	if shape.get("primitive", "") == "arc": return preload("res://src/glass/geometry.gd").colliders(shape)
	var result: Array = []
	if shape.get("primitive", "") == "polygon":
		for piece in Geometry2D.decompose_polygon_in_convex(Geometry.polygon(shape)):
			var collider := CollisionShape2D.new()
			var convex := ConvexPolygonShape2D.new()
			convex.points = piece
			collider.shape = convex
			result.append(collider)
	else:
		var collider := CollisionShape2D.new()
		if shape.get("primitive", "circle") == "circle":
			var circle := CircleShape2D.new()
			circle.radius = float(shape.get("radius", 18))
			collider.shape = circle
		else:
			var rectangle := RectangleShape2D.new()
			var size: Array = shape.get("size", [60, 20])
			rectangle.size = Vector2(float(size[0]), float(size[1]))
			collider.shape = rectangle
		result.append(collider)
	return result
