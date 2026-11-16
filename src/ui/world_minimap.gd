extends Control
## Editor-only world overview. It is outside the clean video viewport and cannot enter exports.
signal navigate(top: Vector2)
var bounds := Rect2(0, 0, 720, 1280)
var view := Rect2(0, 0, 720, 1280)
var objects: Array = []
var map_rect := Rect2()
var available := true

## Keep the map compact and use explicit click/drag navigation.
func _ready() -> void:
	custom_minimum_size = Vector2(180, 170)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "世界缩略图：编辑模式点击/拖动，定位画外物体；黄色框为当前画幅。"

## Read native poses, never alter bodies or the saved scene from a draw callback.
func update_world(stage: Node2D) -> void:
	available = stage.document["world"]["dimension"] == "2d"
	visible = available
	if not available: return
	bounds = stage.camera_track.bounds
	view.position = stage.view_top
	objects.clear()
	for id in stage.world.records:
		var record: Dictionary = stage.world.records[id]
		objects.append({"point": stage.world._position(id), "shape": record["spec"]["shape"], "angle": stage.world._rotation(id), "color": stage.world._color(record["spec"])})
	queue_redraw()

## Compress a long world vertically while keeping its width usable for navigation.
func _draw() -> void:
	if not available: return
	draw_rect(Rect2(Vector2.ZERO, size), Color("0d1723"))
	var uniform := minf((size.x - 20) / bounds.size.x, (size.y - 20) / bounds.size.y)
	var map_extent := bounds.size * uniform
	map_extent.x = maxf(map_extent.x, minf(140, size.x - 20))
	map_rect = Rect2((size - map_extent) / 2, map_extent)
	var factor := map_extent / bounds.size
	draw_rect(map_rect, Color("26394a"))
	for object in objects:
		var point: Vector2 = map_rect.position + (object["point"] - bounds.position) * factor
		var shape: Dictionary = object["shape"]
		if shape.get("primitive", "") == "circle": draw_circle(point, maxf(2, float(shape["radius"]) * minf(factor.x,factor.y)), object["color"])
		else:
			var points := PackedVector2Array()
			if shape.get("primitive", "") == "polygon": points = preload("res://src/document/shape_geometry.gd").polygon(shape)
			elif shape.get("primitive", "") == "arc": points = preload("res://src/glass/geometry.gd").polygon(shape)
			else:
				var extent: Array = shape.get("size", [40, 40])
				var half := Vector2(float(extent[0]), float(extent[1])) / 2
				points = PackedVector2Array([-half, Vector2(half.x,-half.y), half, Vector2(-half.x,half.y)])
			for i in points.size(): points[i] = point + points[i].rotated(object["angle"]) * factor
			draw_colored_polygon(points, object["color"])
	draw_rect(Rect2(map_rect.position + (view.position - bounds.position) * factor, view.size * factor), Color("f6c75d"), false, 2)

## Navigation uses the inverse map transform; hit testing/placement remain in the main view.
func _gui_input(event: InputEvent) -> void:
	if not available or map_rect.size.x <= 0: return
	if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed) or (event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		var point: Vector2 = (event.position - map_rect.position) / map_rect.size * bounds.size + bounds.position
		navigate.emit(point - view.size / 2)
		accept_event()
