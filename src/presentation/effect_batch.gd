extends MultiMeshInstance2D
## Render all circles in one instanced draw while preserving per-event geometry/color.

func _init() -> void:
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	multimesh.mesh = quad
	var shader_material := ShaderMaterial.new()
	shader_material.shader = preload("res://src/presentation/effect_circle.gdshader")
	material = shader_material

## Grow storage geometrically; draw only the current live count, with no effect truncation.
func update_circles(items: Array, kind: String) -> void:
	if multimesh.instance_count < items.size():
		multimesh.instance_count = maxi(items.size(), maxi(64, multimesh.instance_count * 2))
	multimesh.visible_instance_count = items.size()
	for index in items.size():
		var item: Dictionary = items[index]
		var radius := maxf(0.05, float(item.get("size", item.get("radius", 1))))
		var extent := radius + 1
		multimesh.set_instance_transform_2d(index, Transform2D(0, Vector2.ONE * extent, 0, item["position"]))
		var tint: Color = item.get("color", Color(0.6, 0.9, 0.8, item.get("alpha", 1)))
		if kind == "flash" and not item.has("color"): tint = Color(0.8, 1.0, 0.9, item["alpha"])
		multimesh.set_instance_color(index, tint)
		multimesh.set_instance_custom_data(index, Color(radius / extent, maxf(0, radius - 1.4) / extent if kind == "ring" else 0, 0, 0))
