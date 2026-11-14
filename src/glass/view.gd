extends Node2D
## Shared live/replay glass surfaces, central hit counter and instanced visual shard layer.
const Surface=preload("res://src/glass/surface.gd")
var world: Node
var surfaces: Dictionary={}
var shards: MultiMeshInstance2D
var counter: Label
var caption: Label
var enabled := false
var backdrop_enabled := false
var clock := 0.0

## Allocate one shard batch and one central HUD, independent of pane count.
func _ready() -> void:
	enabled=world.document.get("objects",[]).any(func(spec): return spec.has("glass"))
	shards=load("res://src/glass/shards.gd").new()
	shards.z_index=4
	add_child(shards)
	counter=Label.new()
	counter.add_theme_font_override("font",Surface.number_font())
	counter.add_theme_font_size_override("font_size",72)
	counter.add_theme_constant_override("outline_size",5)
	counter.add_theme_color_override("font_outline_color",Color("101828"))
	counter.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	counter.position=Vector2(220,572)
	counter.size=Vector2(280,150)
	counter.pivot_offset=Vector2(140,40)
	counter.z_index=3
	add_child(counter)
	caption=counter.duplicate()
	caption.text="HITS LEFT"
	caption.position=Vector2(220,674)
	caption.add_theme_font_size_override("font_size",16)
	caption.add_theme_constant_override("outline_size",2)
	add_child(caption)
	counter.visible=false
	caption.visible=false

## State is restored from Take poses; no contact or damage logic runs in replay.
func present(time: float, events: Array) -> void:
	if not enabled: return
	clock=time
	var visible_ids: Dictionary={}
	for id in world.records:
		var record: Dictionary=world.records[id]
		if not record["spec"].has("glass"): continue
		visible_ids[id]=true
		if not surfaces.has(id):
			var surface=Surface.new()
			surface.setup(record["spec"])
			add_child(surface)
			surfaces[id]=surface
		var surface: Node2D=surfaces[id]
		surface.selected=world.selected_id==id
		surface.position=world._position(id)
		surface.rotation=world._rotation(id)
		surface.present(record,time)
	for id in surfaces.keys():
		if not visible_ids.has(id):
			surfaces[id].queue_free()
			surfaces.erase(id)
	var latest: Dictionary={}
	for i in range(events.size()-1,-1,-1):
		if float(events[i].get("sim_time",events[i].get("time",0)))>time+0.00001: continue
		if events[i].get("type","")=="glass_hit": latest=events[i];break
	counter.visible=bool(world.document.get("presentation",{}).get("glass_counter",false))
	if backdrop_enabled!=counter.visible:
		backdrop_enabled=counter.visible
		queue_redraw()
	caption.visible=counter.visible
	if counter.visible:
		var target := str(latest.get("id",""))
		if not world.records.has(target):
			for id in world.records:
				if world.records[id]["spec"].has("glass"): target=id;break
		var count: int=int(world.records.get(target,{}).get("glass_remaining",latest.get("remaining",0)))
		var age := maxf(0,time-float(latest.get("sim_time",latest.get("time",-1000))))
		counter.scale=Vector2.ONE*(1+0.1*exp(-age*12))
		counter.text=str(count)
		counter.add_theme_color_override("font_color",Color(str(world.definitions.get(target,{}).get("appearance",{}).get("color","#ffe7a3"))))
		if surfaces.is_empty():
			counter.text="CLEAR!"
			caption.visible=false
	shards.present(events,time)

## Deterministic star backdrop is optional and does not enter the physics world.
func _draw() -> void:
	if not world.document.get("presentation",{}).get("glass_counter",false): return
	var rng := RandomNumberGenerator.new()
	rng.seed=770601
	for i in 140:
		draw_circle(Vector2(rng.randf_range(0,720),rng.randf_range(0,1280)),rng.randf_range(0.5,1.4),Color(0.7,0.8,1,rng.randf_range(0.08,0.3)))
