extends Node2D
## Persistent glass pane, attached cracks and remaining-hit typography, driven by recorded state.
const Geometry = preload("res://src/glass/geometry.gd")
static var font_resource: SystemFont
static var white_texture: ImageTexture
static var glass_material: ShaderMaterial
var spec: Dictionary = {}
var selected := false
var last_selected := false
var remaining := 1
var total := 1
var marks: Array = []
var clock := 0.0
var last_hit := -1000.0
var number: Label
var pane: Polygon2D
var outline := PackedVector2Array()

## Build geometry and text once per original glass object.
func setup(value: Dictionary) -> void:
	spec=value
	total=int(spec["glass"]["hits"])
	remaining=total
	outline=Geometry.polygon(spec["shape"])
	pane=Polygon2D.new()
	if white_texture==null:
		var image := Image.create(1,1,false,Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		white_texture=ImageTexture.create_from_image(image)
	pane.texture=white_texture
	pane.polygon=outline
	pane.show_behind_parent=true
	var uv := PackedVector2Array()
	for point in outline: uv.append(point/720.0+Vector2.ONE*0.5)
	pane.uv=uv
	pane.color=Color(str(spec.get("appearance",{}).get("color","#53c7df")))
	if glass_material==null:
		glass_material=ShaderMaterial.new()
		glass_material.shader=preload("res://src/glass/glass.gdshader")
	pane.material=glass_material
	add_child(pane)
	number=Label.new()
	number.add_theme_font_override("font",number_font())
	number.add_theme_font_size_override("font_size",int(spec["glass"].get("font_size",24)))
	number.add_theme_constant_override("outline_size",5)
	number.add_theme_color_override("font_outline_color",Color("182536"))
	number.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	number.size=Vector2(120,50)
	var anchor := Vector2.ZERO
	if spec["shape"].get("primitive","")=="arc":
		anchor=Vector2.from_angle(deg_to_rad((float(spec["shape"]["start_degrees"])+float(spec["shape"]["end_degrees"]))*0.5))*(float(spec["shape"]["inner_radius"])+float(spec["shape"]["outer_radius"]))*0.5
	number.position=anchor-Vector2(60,22)
	number.pivot_offset=Vector2(60,22)
	number.z_index=2
	add_child(number)

## Explicit clocks keep seeking and independent production deterministic.
func present(state: Dictionary, time: float) -> void:
	var dirty := remaining!=int(state.get("glass_remaining",total)) or selected!=last_selected
	last_selected=selected
	var tint := Color(str(spec.get("appearance",{}).get("color","#53c7df")))
	if pane.color!=tint:
		pane.color=tint
		dirty=true
	remaining=int(state.get("glass_remaining",total))
	marks=state.get("glass_marks",[])
	clock=time
	last_hit=float(state.get("glass_hit_time",-1000))
	number.text=str(remaining)
	var age := maxf(0,time-last_hit)
	number.scale=Vector2.ONE*(1+0.16*exp(-age*12)*cos(age*24))
	number.modulate=Color.WHITE.lerp(Color("ffe99f"),exp(-age*10))
	if dirty: queue_redraw()

## Clip deterministic branching cracks to the intact original pane polygon.
func _draw() -> void:
	if outline.is_empty(): return
	var edge := Color("ffcc55") if selected else Color(str(spec.get("appearance",{}).get("color","#53c7df"))).lightened(0.6)
	var closed := outline.duplicate()
	closed.append(outline[0])
	draw_polyline(closed,edge,2,true)
	var lines := PackedVector2Array()
	for mark in marks:
		var rng := RandomNumberGenerator.new()
		rng.seed=int(mark["seed"])
		var origin := Vector2(float(mark["point"][0]),float(mark["point"][1]))
		for branch in 5:
			var direction := Vector2.from_angle(rng.randf_range(0,TAU))
			var previous := origin
			for step in 4:
				var point := previous+direction.rotated(rng.randf_range(-0.65,0.65))*rng.randf_range(6,15)
				if not Geometry2D.is_point_in_polygon(point,outline): break
				lines.append(previous)
				lines.append(point)
				if step==2:
					var tip := point+direction.rotated(0.8)*12
					if Geometry2D.is_point_in_polygon(tip,outline):
						lines.append(point)
						lines.append(tip)
				previous=point

	if not lines.is_empty(): draw_multiline(lines,Color(0.93,0.99,1,0.62),1.15,true)

## Share font glyph caches across all panes and the central HUD.
static func number_font() -> SystemFont:
	if font_resource==null:
		font_resource=SystemFont.new()
		font_resource.font_names=PackedStringArray(["Impact","Bahnschrift","Arial"])
	return font_resource
