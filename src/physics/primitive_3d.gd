extends RefCounted
## Build matching primitive geometry and configure its basic material.


## Derive both the collider and the mesh from one shape description.
static func build(spec: Dictionary) -> Dictionary:
	if spec.get("primitive", "sphere") == "sphere":
		var shape := SphereShape3D.new()
		shape.radius = maxf(0.02, float(spec.get("radius", 0.44)))
		var mesh := SphereMesh.new()
		mesh.radius = shape.radius
		mesh.height = shape.radius * 2
		mesh.radial_segments = 24
		mesh.rings = 12
		return {"shape": shape, "mesh": mesh}
	var size: Array = spec.get("size", [0.85, 0.65, 0.75])
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(0.02, float(size[0])), maxf(0.02, float(size[1])), maxf(0.02, float(size[2])))
	var mesh := BoxMesh.new()
	mesh.size = shape.size
	return {"shape": shape, "mesh": mesh}


## Apply appearance and selection without altering solver geometry.
static func update_material(material: StandardMaterial3D, color: Color, render: Dictionary, selected: bool) -> void:
	material.albedo_color = color
	material.metallic = clampf(float(render.get("metallic", 0.15)), 0, 1)
	material.roughness = clampf(float(render.get("roughness", 0.35)), 0, 1)
	material.emission_enabled = selected or float(render.get("emission", 0)) > 0
	material.emission = Color("fbbf24") if selected else color
	material.emission_energy_multiplier = 0.35 if selected else float(render.get("emission", 0))


## Draw collider outlines from the very same primitive shape dimensions.
static func debug_mesh(shape: Shape3D) -> MeshInstance3D:
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	if shape is SphereShape3D:
		for axis in 3:
			for index in 32:
				for endpoint in 2:
					var angle := TAU * (index + endpoint) / 32
					var point: Vector3 = Vector3(cos(angle), sin(angle), 0) * shape.radius
					if axis == 1: point = Vector3(point.x, 0, point.y)
					elif axis == 2: point = Vector3(0, point.x, point.y)
					lines.surface_add_vertex(point)
	else:
		var half: Vector3 = shape.size / 2
		for axis in 3:
			for first in [-1, 1]:
				for second in [-1, 1]:
					var point := half
					point[(axis + 1) % 3] *= first
					point[(axis + 2) % 3] *= second
					point[axis] = -half[axis]
					lines.surface_add_vertex(point)
					point[axis] = half[axis]
					lines.surface_add_vertex(point)
	lines.surface_end()
	var visual := MeshInstance3D.new()
	visual.mesh = lines
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("fbbf24")
	material.no_depth_test = true
	visual.material_override = material
	visual.visible = false
	return visual


## Find complete sphere arrangements using the same sphere/box dimensions as the colliders.
static func find_birth_positions(world: Node, id: String, count: int, radius: float) -> Array:
	var center: Vector3 = world.records[id]["body"].position
	var ring := radius * 1.08 / sin(PI / count)
	for offset in [Vector3.ZERO, Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD]:
		for phase in 12:
			var result: Array = []
			for index in count:
				var angle := phase * PI / 12 + TAU * index / count
				var point: Vector3 = center + offset * radius * 0.6 + Vector3(cos(angle), 0, sin(angle)) * ring
				if not _space_free(world, point, radius, id): break
				result.append([point.x, point.y, point.z])
			if result.size() == count: return result
	return []


## Reject occupied candidate points, including recently created bodies not yet solved.
static func _space_free(world: Node, point: Vector3, radius: float, ignored: String) -> bool:
	for id in world.records:
		if id == ignored or world.source_kind(id) == "sensor": continue
		var body: Node3D = world.records[id]["body"]
		var local := body.global_transform.affine_inverse() * point
		var shape: Dictionary = world.records[id]["spec"].get("shape", {})
		if shape.get("primitive", "") == "sphere":
			if local.length() < radius + float(shape.get("radius", 0.44)) + 0.001: return false
		else:
			var size: Array = shape.get("size", [1, 1, 1])
			var half := Vector3(float(size[0]), float(size[1]), float(size[2])) / 2
			if local.distance_to(local.clamp(-half, half)) < radius + 0.001: return false
	return true
