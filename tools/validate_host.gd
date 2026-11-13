extends SceneTree
## Exercise the actual preview host: real split -> frozen physics -> automatic JSON reload.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var path := "res://scratch/host_test.json"
	DirAccess.make_dir_recursive_absolute("res://scratch")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/demo_2d.json"))
	data["spawns"] = [{"position": [180, 1080], "velocity": [0, 150]}]
	data["hitstop_seconds"] = 0.12
	_write(path, data)
	var host = load("res://scripts/main.gd").new()
	host.config_path = path
	root.add_child(host)
	for frame in range(180):
		await process_frame
		if paused: break
	var paused_detected := paused
	var elapsed_before: float = host.probe.elapsed
	var points := _positions(host.probe)
	await process_frame
	var frozen: bool = paused_detected and host.probe.elapsed == elapsed_before and _positions(host.probe) == points
	# Native wall-clock timestamp resolution is seconds; let one real second elapse before editing.
	await create_timer(1.2, true, false, true).timeout
	data["title"] = "自动重载验证通过"
	data["title_size"] = 52
	data["color"] = "#3b82f6"
	_write(path, data)
	await create_timer(0.8, true, false, true).timeout
	var reloaded: bool = host.config.get("title", "") == data["title"] and host.config.get("title_size", 0) == 52
	var result := {"hitstop_triggered_by_real_split": paused_detected, "positions_and_physics_time_frozen": frozen,
		"automatic_config_reload": reloaded, "passed": frozen and reloaded}
	var file := FileAccess.open("res://outputs/host_validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	print("HOST_VALIDATION " + JSON.stringify(result))
	quit(0 if result["passed"] else 1)


func _write(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))


func _positions(probe: Node) -> Dictionary:
	var positions: Dictionary = {}
	for id in probe.balls:
		positions[id] = probe.balls[id]["body"].position
	return positions
