extends RefCounted
## Shared polygon geometry for glass drawing, compound native colliders and picking.
static func polygon(shape: Dictionary) -> PackedVector2Array:
	var points := PackedVector2Array()
	if shape.get("primitive", "") != "arc":
		var size: Array = shape.get("size", [180, 22])
		var half := Vector2(float(size[0]), float(size[1])) / 2
		return PackedVector2Array([-half, Vector2(half.x,-half.y), half, Vector2(-half.x,half.y)])
	var start := deg_to_rad(float(shape.get("start_degrees", 0)))
	var span := deg_to_rad(float(shape.get("end_degrees", 45))-float(shape.get("start_degrees",0)))
	var steps := maxi(2, ceili(absf(span)/deg_to_rad(6)))
	for i in steps+1: points.append(Vector2.from_angle(start+span*i/steps)*float(shape["outer_radius"]))
	for i in range(steps,-1,-1): points.append(Vector2.from_angle(start+span*i/steps)*float(shape["inner_radius"]))
	return points

## Every quad spans six degrees or less and is convex, suitable for native collision shapes.
static func colliders(shape: Dictionary) -> Array:
	var outline := polygon(shape)
	var steps := outline.size()/2-1
	var result: Array = []
	for i in steps:
		var collider := CollisionShape2D.new()
		var convex := ConvexPolygonShape2D.new()
		convex.points = PackedVector2Array([outline[i],outline[i+1],outline[outline.size()-2-i],outline[outline.size()-1-i]])
		collider.shape = convex
		result.append(collider)
	return result

## Find the nearest polygon boundary; positions remain explicitly geometry estimates.
static func closest(shape: Dictionary, point: Vector2) -> Vector2:
	var points := polygon(shape)
	var best := points[0]
	var distance := INF
	for i in points.size():
		var candidate := Geometry2D.get_closest_point_to_segment(point,points[i],points[(i+1)%points.size()])
		if candidate.distance_squared_to(point)<distance:
			best=candidate
			distance=candidate.distance_squared_to(point)
	return best
