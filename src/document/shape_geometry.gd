extends RefCounted
## Shared source contours for validation, rendering, picking and native collision compilation.

## Convert a validated simple polygon to local coordinates; no scene nodes are created.
static func polygon(shape: Dictionary) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in shape.get("points", []): result.append(Vector2(float(point[0]), float(point[1])))
	return result

## Reject malformed/self-intersecting/degenerate contours before committing a scene edit.
static func validate(shape: Dictionary) -> PackedStringArray:
	var points: Variant = shape.get("points", [])
	if not points is Array or points.size() < 3 or points.size() > 128: return PackedStringArray(["多边形需要3～128个顶点"])
	for point in points:
		if not point is Array or point.size() != 2: return PackedStringArray(["轮廓顶点需要二维坐标"])
		for number in point:
			if not (number is int or number is float) or not is_finite(float(number)) or absf(float(number)) > 100000: return PackedStringArray(["轮廓坐标需要±100000内有限数值"])
	var contour := polygon(shape)
	for i in contour.size():
		for j in range(i + 1, contour.size()):
			if contour[i].distance_to(contour[j]) < 1: return PackedStringArray(["轮廓顶点重合或间距小于1"])
			if j == i + 1 or (i == 0 and j == contour.size() - 1): continue
			if _intersects(contour[i], contour[(i + 1) % contour.size()], contour[j], contour[(j + 1) % contour.size()]): return PackedStringArray(["轮廓自相交或边重叠"])
	var area := 0.0
	for i in contour.size(): area += contour[i].cross(contour[(i + 1) % contour.size()])
	if absf(area) < 2 or Geometry2D.decompose_polygon_in_convex(contour).is_empty(): return PackedStringArray(["轮廓面积不足或无法凸分解"])
	return PackedStringArray()

## Include collinear touching edges, which a crossing-only test would miss.
static func _intersects(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	if Geometry2D.segment_intersects_segment(a, b, c, d) != null: return true
	for pair in [[a, c, d], [b, c, d], [c, a, b], [d, a, b]]:
		if pair[0].distance_to(Geometry2D.get_closest_point_to_segment(pair[0], pair[1], pair[2])) < 0.00001: return true
	return false

## Return an exact local polygon AABB for conservative broad-phase queries and minimaps.
static func bounds(shape: Dictionary) -> Rect2:
	var points := polygon(shape)
	var box := Rect2(points[0], Vector2.ZERO)
	for point in points: box = box.expand(point)
	return box

## Project a point to the nearest actual edge without filling concave notches.
static func closest(shape: Dictionary, point: Vector2) -> Vector2:
	var points := polygon(shape)
	var result := points[0]
	for i in points.size():
		var candidate := Geometry2D.get_closest_point_to_segment(point, points[i], points[(i + 1) % points.size()])
		if candidate.distance_squared_to(point) < result.distance_squared_to(point): result = candidate
	return result
