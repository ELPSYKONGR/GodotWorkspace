extends SceneTree
## Verify independent visible effects, immediate inspector commands and saved preferences.
const Document = preload("res://src/document/scene_document.gd")
var checks: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

## Locate actual checkboxes after each command rebuilds the inspector.
func _button(node: Node, caption: String) -> Button:
	if node is Button and node.text == caption: return node
	for child in node.get_children():
		var found := _button(child, caption)
		if found != null: return found
	return null

func _run() -> void:
	var fx = load("res://src/presentation/effects.gd").new()
	root.add_child(fx)
	var settings := {"enabled": true, "particles_enabled": true, "impact_particles": true, "impact_flash": true, "trail_enabled": true, "ring": true, "flash": true, "count": 3, "lifetime": 0.35}
	var doc := {"presentation": {"effects": settings}}
	var events := [{"type": "split", "time": 0.2, "sim_time": 0.2, "position": [100, 100], "seed": 1}, {"type": "contact", "phase": "enter", "time": 0.21, "sim_time": 0.21, "id": "a", "other_id": "b", "position": [110, 100], "seed": 2}, {"type": "contact", "phase": "enter", "time": 0.22, "sim_time": 0.22, "id": "a", "other_id": "b", "position": [115, 100], "seed": 3}]
	fx.set_timeline(events)
	fx.set_take({"frames": [{"time": 0.1, "states": [{"id": "a", "position": [50, 100]}]}, {"time": 0.24, "states": [{"id": "a", "position": [100, 100]}]}]})
	var projector := func(point: Array) -> Vector2: return Vector2(point[0], point[1])
	var definitions := {"a": {"physics": {"mode": "dynamic"}}}
	fx.configure(doc)
	fx.present(0.24, 0.24, projector, [], definitions)
	checks["all_effect_types_visible"] = fx.particles.size() == 6 and fx.rings.size() == 1 and fx.flashes.size() == 2 and fx.trails.size() == 1
	for field in ["particles_enabled", "impact_particles", "impact_flash", "ring", "flash", "trail_enabled", "enabled"]:
		var copy := settings.duplicate(true)
		copy[field] = false
		fx.configure({"presentation": {"effects": copy}})
		fx.present(0.24, 0.24, projector, [], definitions)
		match field:
			"particles_enabled", "impact_particles": checks[field + "_independent"] = fx.particles.size() == 3 and fx.rings.size() == 1 and fx.flashes.size() == 2
			"impact_flash", "flash": checks[field + "_independent"] = fx.flashes.size() == 1 and fx.particles.size() == 6
			"ring": checks["ring_independent"] = fx.rings.is_empty() and fx.particles.size() == 6
			"trail_enabled": checks["trail_independent"] = fx.trails.is_empty() and fx.particles.size() == 6
			"enabled": checks["master_clears_every_batch"] = fx.trails.is_empty() and fx.particles.is_empty() and fx.rings.is_empty() and fx.flashes.is_empty() and fx.particle_batch.multimesh.visible_instance_count == 0
	fx.configure(doc)
	fx.present(0.24, 0.24, projector, [], definitions)
	var expected := JSON.stringify(fx.particles)
	fx.present(0.1, 0.1, projector, [], definitions)
	fx.present(0.24, 0.24, projector, [], definitions)
	checks["collision_particles_rewind_deterministic"] = expected == JSON.stringify(fx.particles)
	var dense: Array = []
	for index in 50: dense.append({"type": "contact", "phase": "enter", "time": 0.2 + index * 0.0001, "sim_time": 0.2 + index * 0.0001, "id": str(index), "other_id": "wall", "position": [100, 100]})
	fx.set_timeline(dense)
	fx.present(0.24, 0.24, projector, [], definitions)
	checks["contact_bursts_bounded_without_dropping_ledger"] = fx.particles.size() == 16 * 3 and fx.timeline.size() == 50
	var legacy := settings.duplicate(true)
	for field in ["particles_enabled", "impact_particles", "impact_flash"]: legacy.erase(field)
	fx.configure({"presentation": {"effects": legacy}})
	fx.set_timeline(events)
	fx.present(0.24, 0.24, projector, [], definitions)
	checks["legacy_defaults_keep_old_effects"] = fx.particles.size() == 3 and fx.flashes.size() == 1
	var host = load("res://src/ui/workbench.gd").new()
	root.add_child(host)
	await process_frame
	host.service.execute({"op": "simulation.play"})
	var body: Node = host.session.stage.world.records["ball_A"]["body"]
	var physical_hash := Document.simulation_hash(host.service.document)
	var all_independent := true
	for item in [["拖影", "trail_enabled"], ["撞击光圈", "ring"], ["撞击闪光", "impact_flash"], ["碰撞粒子", "impact_particles"], ["分裂粒子", "particles_enabled"], ["分裂闪光", "flash"]]:
		var control := _button(host.panel.pages["特效"], item[0]) as CheckBox
		var next := not control.button_pressed
		control.button_pressed = next
		all_independent = all_independent and host.service.document["presentation"]["effects"][item[1]] == next
	checks["all_checkbox_commands_immediate_and_distinct"] = all_independent
	checks["switches_preserve_physics_body_and_mode"] = body == host.session.stage.world.records["ball_A"]["body"] and host.session.mode == "playing" and physical_hash == Document.simulation_hash(host.service.document)
	var preferences: Dictionary = host.service.document["presentation"]["effects"].duplicate(true)
	(_button(host.panel.pages["特效"], "特效总开关") as CheckBox).button_pressed = false
	(_button(host.panel.pages["特效"], "特效总开关") as CheckBox).button_pressed = true
	checks["master_retains_individual_preferences"] = preferences == host.service.document["presentation"]["effects"]
	var result: Dictionary = host.service.execute({"op": "scene.save", "args": {"path": "res://outputs/effects_saved.json"}})
	checks["saved_scene_keeps_all_switches"] = result["ok"] and Document.load_file("res://outputs/effects_saved.json")["document"]["presentation"]["effects"] == preferences
	var invalid: Dictionary = host.service.document.duplicate(true)
	invalid["presentation"]["effects"]["impact_particles"] = "false"
	checks["non_boolean_switch_rejected"] = not Document.validate(invalid).is_empty()
	checks["passed"] = not checks.values().has(false)
	var file := FileAccess.open("res://outputs/effect_switches_validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(checks, "\t"))
	print("EFFECT_SWITCHES ", JSON.stringify(checks))
	for child in root.get_children(): child.queue_free()
	var deadline := Time.get_ticks_msec() + 100
	while Time.get_ticks_msec() < deadline: await process_frame
	quit(0 if checks["passed"] else 1)
