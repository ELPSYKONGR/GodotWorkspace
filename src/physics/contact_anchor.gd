extends RefCounted
## Presentation anchors estimated from collider geometry, never solver contact points.


## Locate circle/box surfaces in the logical 2D world used by the physics adapter.
static func for_2d(records: Dictionary, a: String, b: String) -> Dictionary:
	var first: Dictionary = records[a]
	var second: Dictionary = records[b]
	var p: Vector2 = first["body"].position
	var q: Vector2 = second["body"].position
	var circle_a: bool = first["spec"]["shape"].get("primitive", "") == "circle"
	var circle_b: bool = second["spec"]["shape"].get("primitive", "") == "circle"
	var point := (p + q) * 0.5
	var source := "body_centers_estimate"
	if circle_a and circle_b:
		var direction := p.direction_to(q) if p != q else Vector2.RIGHT
		point = (p + direction * float(first["spec"]["shape"].get("radius", 18)) + q - direction * float(second["spec"]["shape"].get("radius", 18))) * 0.5
		source = "shape_surface_estimate"
	elif circle_a or circle_b:
		var circle: Dictionary = first if circle_a else second
		var box: Dictionary = second if circle_a else first
		var box_body: Node2D = box["body"]
		var local: Vector2 = (circle["body"].position - box_body.position).rotated(-box_body.rotation)
		var size: Array = box["spec"]["shape"].get("size", [60, 20])
		var half := Vector2(maxf(1, float(size[0])), maxf(1, float(size[1]))) * 0.5
		var closest := local.clamp(-half, half)
		if box["spec"]["shape"].get("primitive","")=="arc": closest=preload("res://src/glass/geometry.gd").closest(box["spec"]["shape"],local)
		if box["spec"]["shape"].get("primitive", "") == "polygon": closest=preload("res://src/document/shape_geometry.gd").closest(box["spec"]["shape"],local)
		if closest == local and box["spec"]["shape"].get("primitive", "") not in ["arc", "polygon"]:
			var axis := 0 if half.x - absf(local.x) < half.y - absf(local.y) else 1
			closest[axis] = half[axis] * (-1 if local[axis] < 0 else 1)
		point = box_body.position + closest.rotated(box_body.rotation)
		source = "shape_surface_estimate"
	return {"position": [point.x, point.y], "position_source": source}


## Estimate sphere surfaces and closest oriented-box surfaces in the 3D world.
static func for_3d(records: Dictionary, a: String, b: String) -> Dictionary:
	var first: Dictionary = records[a]
	var second: Dictionary = records[b]
	var p: Vector3 = first["body"].position
	var q: Vector3 = second["body"].position
	var sphere_a: bool = first["spec"]["shape"].get("primitive", "") == "sphere"
	var sphere_b: bool = second["spec"]["shape"].get("primitive", "") == "sphere"
	var point := (p + q) * 0.5
	var source := "body_centers_estimate"
	if sphere_a and sphere_b:
		var direction := p.direction_to(q) if p != q else Vector3.RIGHT
		point = (p + direction * float(first["spec"]["shape"].get("radius", 0.44)) + q - direction * float(second["spec"]["shape"].get("radius", 0.44))) * 0.5
		source = "shape_surface_estimate"
	elif sphere_a or sphere_b:
		var sphere: Dictionary = first if sphere_a else second
		var box: Dictionary = second if sphere_a else first
		var body: Node3D = box["body"]
		var local: Vector3 = body.transform.affine_inverse() * sphere["body"].position
		var size: Array = box["spec"]["shape"].get("size", [1, 1, 1])
		var half := Vector3(maxf(0.02, float(size[0])), maxf(0.02, float(size[1])), maxf(0.02, float(size[2]))) * 0.5
		var closest := local.clamp(-half, half)
		if closest == local:
			var gap := half - local.abs()
			var axis := 0 if gap.x < gap.y else 1
			if gap.z < gap[axis]: axis = 2
			closest[axis] = half[axis] * (-1 if local[axis] < 0 else 1)
		point = body.transform * closest
		source = "shape_surface_estimate"
	return {"position": [point.x, point.y, point.z], "position_source": source}
