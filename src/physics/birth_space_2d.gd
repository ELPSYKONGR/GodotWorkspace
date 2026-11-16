extends RefCounted
## Broad-phase grid for birth placement. Exact circle/rotated-box checks remain in World2D.
const CELL := 64.0
var cells: Dictionary = {}

## Insert conservative world-space bounds, so candidates cannot miss a collider.
func rebuild(records: Dictionary) -> void:
	cells.clear()
	for id in records:
		var record: Dictionary = records[id]
		var spec: Dictionary = record["spec"]
		if spec.get("physics", {}).get("mode", "dynamic") == "sensor": continue
		var body: Node2D = record["body"]
		var shape: Dictionary = spec.get("shape", {})
		var extent: Vector2
		if shape.get("primitive", "") == "circle":
			extent = Vector2.ONE * (float(shape.get("radius", 18)) + 0.05)
		elif shape.get("primitive","")=="arc":
			extent=Vector2.ONE*(float(shape["outer_radius"])+0.05)
		elif shape.get("primitive", "") == "polygon":
			extent = Vector2.ZERO
			for point in preload("res://src/document/shape_geometry.gd").polygon(shape): extent = extent.max(point.rotated(body.rotation).abs() + Vector2.ONE * 0.05)
		else:
			var size: Array = shape.get("size", [60, 20])
			var half := Vector2(maxf(1, float(size[0])), maxf(1, float(size[1]))) / 2
			var c := absf(cos(body.rotation))
			var s := absf(sin(body.rotation))
			extent = Vector2(c * half.x + s * half.y, s * half.x + c * half.y) + Vector2.ONE * 0.05
		for x in range(floori((body.position.x - extent.x) / CELL), floori((body.position.x + extent.x) / CELL) + 1):
			for y in range(floori((body.position.y - extent.y) / CELL), floori((body.position.y + extent.y) / CELL) + 1):
				var key := Vector2i(x, y)
				if not cells.has(key): cells[key] = []
				cells[key].append(id)

## Deduplicate objects spanning multiple cells before exact geometry tests.
func query(point: Vector2, radius: float) -> Array:
	var found: Dictionary = {}
	for x in range(floori((point.x - radius) / CELL), floori((point.x + radius) / CELL) + 1):
		for y in range(floori((point.y - radius) / CELL), floori((point.y + radius) / CELL) + 1):
			for id in cells.get(Vector2i(x, y), []): found[id] = true
	return found.keys()
