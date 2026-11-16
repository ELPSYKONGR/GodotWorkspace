extends Control
## Local-coordinate shape sketch; only source geometry leaves this control.
signal changed(shape: Dictionary)
signal message(text: String)
const Geometry = preload("res://src/document/shape_geometry.gd")
var shape: Dictionary = {}
var pending_points: Array = []
var tool := "select"
var vertex := -1
var drawing := false
var snap := true
var zoom := 1.0

## Size the local view without altering object transforms, units or source points.
func configure(value: Dictionary) -> void:
	shape = value.duplicate(true)
	if shape.get("primitive", "") == "arc":
		var contour: Array = []
		for point in preload("res://src/glass/geometry.gd").polygon(shape): contour.append([point.x, point.y])
		shape = {"primitive": "polygon", "points": contour}
	pending_points.clear()
	var extent := Vector2(240, 180)
	if shape.get("primitive", "") == "polygon":
		for point in Geometry.polygon(shape): extent = extent.max(point.abs())
	elif shape.get("primitive", "") == "circle": extent = Vector2.ONE * float(shape["radius"])
	elif shape.has("size"): extent = Vector2(float(shape["size"][0]), float(shape["size"][1])) / 2
	zoom = minf(1, minf(560 / maxf(1, extent.x * 2), 390 / maxf(1, extent.y * 2)))
	zoom = maxf(0.0001, zoom)
	queue_redraw()

## Mouse positions use the same local-to-view transform as contours and handles.
func local_point(point: Vector2) -> Vector2:
	var result := (point - size / 2) / zoom
	return result.snapped(Vector2.ONE * 16) if snap else result

## A completed loop is validated by the document before it can replace a real object.
func close_polygon() -> void:
	var candidate := {"primitive": "polygon", "points": pending_points.duplicate(true)}
	var errors := Geometry.validate(candidate)
	if not errors.is_empty(): message.emit("；".join(errors)); return
	shape = candidate
	pending_points.clear()
	tool = "select"
	changed.emit(shape)
	queue_redraw()

## Cancel only unfinished drawing; the dialog owns the original-object draft transaction.
func cancel_drawing() -> void:
	pending_points.clear()
	drawing = false
	vertex = -1
	queue_redraw()

## Draw real source geometry; invalid edits remain visible as a contour and cannot be committed.
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("101c28"))
	var step := maxf(8, 16 * zoom)
	# Grid and snapping share the local origin, including a non-integer viewport center.
	for i in range(floori(-size.x / (2 * step)), ceili(size.x / (2 * step)) + 1):
		var x := size.x / 2 + i * step
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color("203444"))
	for i in range(floori(-size.y / (2 * step)), ceili(size.y / (2 * step)) + 1):
		var y := size.y / 2 + i * step
		draw_line(Vector2(0, y), Vector2(size.x, y), Color("203444"))
	draw_line(Vector2(size.x / 2, 0), Vector2(size.x / 2, size.y), Color("496579"))
	draw_line(Vector2(0, size.y / 2), Vector2(size.x, size.y / 2), Color("496579"))
	draw_set_transform(size / 2, 0, Vector2.ONE * zoom)
	var color := Color("53d9a0")
	match shape.get("primitive", ""):
		"circle": draw_circle(Vector2.ZERO, float(shape["radius"]), color)
		"rectangle", "line":
			var extent := Vector2(float(shape["size"][0]), float(shape["size"][1]))
			draw_rect(Rect2(-extent / 2, extent), color)
		"polygon":
			var points := Geometry.polygon(shape)
			if Geometry.validate(shape).is_empty(): draw_colored_polygon(points, color)
			else: color = Color("f59388")
			var closed := points.duplicate(); closed.append(points[0])
			draw_polyline(closed, color.lightened(0.2), 2 / zoom, true)
			for point in points: draw_circle(point, 5 / zoom, Color("e0ffed"))
	if pending_points.size() > 1:
		var path := PackedVector2Array()
		for point in pending_points: path.append(Vector2(point[0], point[1]))
		draw_polyline(path, Color("f6c75d"), 2 / zoom, true)
	draw_set_transform(Vector2.ZERO)

## Draw circle/rectangle around the local origin; polygons and vertices use exact local points.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		grab_focus()
		if not event.pressed: drawing = false; vertex = -1; return
		var point := local_point(event.position)
		if tool == "polygon": pending_points.append([point.x, point.y]); queue_redraw()
		elif tool in ["circle", "rectangle"]: drawing = true; _draw_primitive(point)
		elif shape.get("primitive", "") == "polygon":
			var points := Geometry.polygon(shape)
			for i in points.size():
				if points[i].distance_to(point) * zoom < 12: vertex = i; break
	elif event is InputEventMouseMotion:
		if vertex >= 0:
			var point := local_point(event.position)
			shape["points"][vertex] = [point.x, point.y]
			changed.emit(shape); queue_redraw()
		elif drawing: _draw_primitive(local_point(event.position))
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER: close_polygon()
		elif event.keycode == KEY_ESCAPE: cancel_drawing()

## Parameters are derived from source dimensions, never a manually animated motion path.
func _draw_primitive(point: Vector2) -> void:
	shape = {"primitive": "circle", "radius": maxf(1, point.length())} if tool == "circle" else {"primitive": "rectangle", "size": [maxf(1, absf(point.x) * 2), maxf(1, absf(point.y) * 2)]}
	changed.emit(shape)
	queue_redraw()
