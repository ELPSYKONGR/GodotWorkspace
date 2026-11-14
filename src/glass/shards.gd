extends MultiMeshInstance2D
## Instanced, analytically evaluated visual shards; no extra native rigid bodies are created.

## A single triangle mesh and material serve every visible shard.
func _init() -> void:
	multimesh=MultiMesh.new()
	multimesh.transform_format=MultiMesh.TRANSFORM_2D
	multimesh.use_colors=true
	var mesh_data: Array=[]
	mesh_data.resize(Mesh.ARRAY_MAX)
	mesh_data[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(0,-1,0),Vector3(-0.85,0.6,0),Vector3(0.85,0.6,0)])
	mesh_data[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2(0.5,0),Vector2(0,1),Vector2(1,1)])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,mesh_data)
	multimesh.mesh=mesh
	var mat := ShaderMaterial.new()
	mat.shader=preload("res://src/glass/shard.gdshader")
	material=mat

## Event seeds, explicit simulation time and fixed lifetimes guarantee backwards seeking.
func present(events: Array, time: float) -> void:
	var instances: Array=[]
	for index in range(events.size()-1,-1,-1):
		var event: Dictionary=events[index]
		var age := time-float(event.get("sim_time",event.get("time",0)))
		if age>2.4: break
		if age<0 or event.get("type","")!="glass_break": continue
		var rng := RandomNumberGenerator.new()
		rng.seed=int(event.get("seed",str(event["id"]).hash()))
		var origin := Vector2(float(event["origin"][0]),float(event["origin"][1]))
		var rotation := float(event.get("rotation",0))
		var shape: Dictionary=event["shape"]
		for piece in int(event.get("pieces",48)):
			var position: Vector2
			if shape.get("primitive","")=="arc":
				position=Vector2.from_angle(deg_to_rad(rng.randf_range(float(shape["start_degrees"]),float(shape["end_degrees"]))))*sqrt(rng.randf_range(pow(float(shape["inner_radius"]),2),pow(float(shape["outer_radius"]),2)))
			else:
				var size: Array=shape.get("size",[180,22])
				position=Vector2(rng.randf_range(-0.5,0.5)*float(size[0]),rng.randf_range(-0.5,0.5)*float(size[1]))
			position=origin+position.rotated(rotation)
			var velocity := Vector2.from_angle(rng.randf_range(0,TAU))*rng.randf_range(45,190)
			var spin := rng.randf_range(-5,5)
			var radius := rng.randf_range(4,12)
			position+=velocity*age+Vector2(0,160)*age*age
			var color := Color(str(event.get("color","#53c7df")))
			color.a=clampf((2.4-age)*1.4,0,1)
			instances.append({"position":position,"rotation":spin*age+piece,"radius":radius,"color":color})
	if multimesh.instance_count<instances.size(): multimesh.instance_count=maxi(64,maxi(instances.size(),multimesh.instance_count*2))
	multimesh.visible_instance_count=instances.size()
	for i in instances.size():
		var item: Dictionary=instances[i]
		multimesh.set_instance_transform_2d(i,Transform2D(item["rotation"],Vector2.ONE*item["radius"],0,item["position"]))
		multimesh.set_instance_color(i,item["color"])
