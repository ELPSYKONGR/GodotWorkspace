extends SceneTree
## Exercise integrated concave colliders, birth exclusion and local visual behavior.
const Native2D = preload("res://src/physics/world_2d.gd")
const Native3D = preload("res://src/physics/world_3d.gd")
const Effects = preload("res://src/presentation/effects.gd")
const Style = preload("res://src/document/object_style.gd")
var checks: Dictionary = {}
var contacts: Array = []

## Begin after the native tree is available.
func _initialize() -> void:
	_run.call_deferred()

## Use the actual World adapter, not a second collision implementation.
func _run() -> void:
	Engine.physics_ticks_per_second = 120
	var l_shape := {"primitive":"polygon", "points":[[-60,-60],[60,-60],[60,-20],[-20,-20],[-20,60],[-60,60]]}
	var u_shape := {"primitive":"polygon", "points":[[-120,-120],[-80,-120],[-80,80],[80,80],[80,-120],[120,-120],[120,120],[-120,120]]}
	var doc := {"world":{"dimension":"2d", "gravity":[0,450], "physics_hz":120}, "objects":[
		{"id":"L", "shape":l_shape, "transform":{"position":[200,100]}, "physics":{"mode":"dynamic", "material":{"restitution":0,"friction":0.2}}},
		{"id":"U", "shape":u_shape, "transform":{"position":[650,400]}, "physics":{"mode":"static"}},
		{"id":"ball", "shape":{"primitive":"circle","radius":12}, "transform":{"position":[650,180]}, "physics":{"mode":"dynamic", "material":{"restitution":0,"friction":0.2}}},
		{"id":"floor", "shape":{"primitive":"rectangle","size":[1000,20]}, "transform":{"position":[450,580]}, "physics":{"mode":"static"}}
	], "presentation":{"render":{}}, "mechanisms":[]}
	var world = Native2D.new()
	world.setup(doc, false)
	world.event_logged.connect(func(event):
		if event.get("type", "") == "contact" and event.get("phase", "") == "enter": contacts.append(event))
	root.add_child(world)
	await physics_frame
	# Birth placement normally rebuilds this broad phase before querying candidate circles.
	world.birth_space.rebuild(world.records)
	checks["birth_circle_fits_u_notch"] = world._space_free(Vector2(650,400), 12, "ball")
	checks["birth_circle_rejects_u_solid_side"] = not world._space_free(Vector2(550,400), 12, "ball")
	var greatest_y := -INF
	for tick in 360:
		await physics_frame
		for point in preload("res://src/document/shape_geometry.gd").polygon(l_shape): greatest_y = maxf(greatest_y, (world.records["L"]["body"].global_transform * point).y)
	var floor_contact := false
	var u_contact := false
	var inside_anchor := false
	for event in contacts:
		var pair := [event["id"],event["other_id"]]
		if "L" in pair and "floor" in pair: floor_contact = true
		if "ball" in pair and "U" in pair:
			u_contact = true
			inside_anchor = inside_anchor or absf(float(event["position"][1]) - 480) < 0.001
	checks["dynamic_l_contacts_floor_without_pass_through"] = floor_contact and greatest_y < 575
	checks["ball_enters_actual_u_notch_and_contacts_inner_floor"] = u_contact and world.records["ball"]["body"].position.y > 400 and world.records["ball"]["body"].position.y < 480 and inside_anchor
	checks["concave_contours_remain_one_body_each"] = world.records["L"]["body"].get_child_count() > 1 and world.records["U"]["body"].get_child_count() > 1 and world.records.size() == 4
	root.remove_child(world); world.queue_free()
	await process_frame
	_test_effects()
	await _test_3d()
	checks["passed"] = not checks.values().has(false)
	FileAccess.open("res://outputs/polygon_styles_validation.json", FileAccess.WRITE).store_string(JSON.stringify(checks, "\t"))
	print("POLYGON_STYLES ", JSON.stringify(checks))
	quit(0 if checks["passed"] else 1)

## Inspect rendered effect data and colors, including root edits after a recorded split.
func _test_effects() -> void:
	var local := {"mode":"custom", "count":3, "color":"#ff0000", "flash":true, "trail_enabled":true, "trail_seconds":0.3, "time_domain":"simulation"}
	var ball := {"id":"ball", "appearance":{"effects":local}, "physics":{"mode":"dynamic"}}
	var child := {"id":"child", "root_id":"ball", "physics":{"mode":"dynamic"}}
	var wall := {"id":"wall", "physics":{"mode":"static"}}
	var definitions := {"ball":ball,"child":child,"wall":wall}
	var doc := {"objects":[ball,wall], "presentation":{"effects":{"enabled":true,"count":7,"trail_enabled":false,"ring":false,"flash":false,"time_domain":"presentation"}}}
	var fx = Effects.new()
	root.add_child(fx)
	fx.configure(doc)
	fx.set_timeline([{"type":"split","id":"child","position":[30,40],"time":1.0,"sim_time":0.5,"seed":1}])
	var project := func(point): return Vector2(float(point[0]),float(point[1])) - Vector2(0,100)
	fx.present(1.05,0.55,project,[],definitions)
	checks["descendant_uses_root_custom_particle_count_and_color"] = fx.particles.size() == 3 and fx.particles[0]["color"].r == 1 and fx.particles[0]["color"].g == 0
	checks["local_flash_color_and_batch_population"] = fx.flashes.size() == 1 and fx.flashes[0]["color"].r == 1 and fx.flashes[0]["color"].g == 0 and fx.flash_batch.multimesh.visible_instance_count == 1
	# The headless dummy renderer cannot read instance colors back; verify with a real GPU too.
	if DisplayServer.get_name() != "headless": checks["gpu_flash_color_readback"] = fx.flash_batch.multimesh.get_instance_color(0).r > 0.99 and fx.flash_batch.multimesh.get_instance_color(0).g < 0.01
	fx.set_timeline([{"type":"contact","phase":"enter","id":"child","other_id":"wall","position":[30,40],"time":1.0,"sim_time":0.5,"seed":1}])
	local["impact_particles"] = true
	fx.configure(doc)
	fx.present(1.05,0.55,project,[],definitions)
	checks["contact_participants_resolve_independent_effects"] = fx.particles.size() == 3
	var same := ball.duplicate(true); same["id"] = "other"
	doc["objects"].append(same); definitions["other"] = same
	fx.configure(doc)
	fx.set_timeline([{"type":"contact","phase":"enter","id":"ball","other_id":"other","position":[30,40],"time":1.0,"sim_time":0.5}])
	fx.present(1.05,0.55,project,[],definitions)
	checks["identical_participant_presets_coalesce"] = fx.particles.size() == 3
	fx.set_timeline([])
	fx.set_take({"frames":[{"time":0.9,"sim_time":0.4,"states":[{"id":"child","position":[0,500]}]}, {"time":3.0,"sim_time":0.5,"states":[{"id":"child","position":[10,510]}]}]})
	fx.present(3.0,0.5,project,[],definitions)
	checks["local_simulation_trail_survives_global_presentation_hold"] = fx.trails.size() == 1 and fx.trails[0].size() == 2 and fx.trails[0][0] == Vector2(10,410) and fx.trail_colors[0].r == 1
	var material := Style.material({"appearance":{"material":{"mode":"inherit","roughness":0.9}}},{"roughness":0.2})
	checks["inherit_ignores_dormant_custom_material"] = material["roughness"] == 0.2
	doc["presentation"]["effects"]["enabled"] = false
	fx.configure(doc); fx.present(3.0,0.5,project,[],definitions)
	checks["global_master_disables_all_local_effects"] = fx.particles.is_empty() and fx.trails.is_empty() and fx.rings.is_empty()
	fx.queue_free()

## Verify both the native static material and the actual visual resource in 3D.
func _test_3d() -> void:
	var doc := {"world":{"dimension":"3d","gravity":[0,-9.8,0]}, "objects":[{"id":"wall", "shape":{"primitive":"box","size":[3,1,3]}, "transform":{"position":[0,0,0]}, "physics":{"mode":"static","material":{"friction":0.17,"restitution":0.36}}, "appearance":{"material":{"mode":"custom","roughness":0.77,"metallic":0.12,"emission":1.4}}}], "presentation":{"render":{"roughness":0.1}}, "mechanisms":[]}
	var world = Native3D.new()
	world.setup(doc,false); root.add_child(world)
	await process_frame
	var body: StaticBody3D = world.records["wall"]["body"]
	var material: StandardMaterial3D = world.records["wall"]["visual"].material_override
	checks["static_3d_material_consumes_explicit_values"] = is_equal_approx(body.physics_material_override.friction,0.17) and is_equal_approx(body.physics_material_override.bounce,0.36)
	checks["local_3d_pbr_and_emission_reach_visual_resource"] = is_equal_approx(material.roughness,0.77) and is_equal_approx(material.metallic,0.12) and material.emission_enabled and is_equal_approx(material.emission_energy_multiplier,1.4)
	world.queue_free()
	await process_frame
