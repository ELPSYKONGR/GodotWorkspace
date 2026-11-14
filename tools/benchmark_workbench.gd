extends SceneTree
## Measure real GPU workbench frame intervals without fixed simulation time or synthetic FPS.
var samples: Array = []
var process_cost: Array = []
var physics_cost: Array = []
var worst: Array = []

## Run only in an independent project copy: the host owns its local command inbox.
func _initialize() -> void:
	_run.call_deferred()

## Exercise actual window/GPU/physics timing; --record also measures capture overhead.
func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Performance measurements require a real GPU window, not headless mode.")
		quit(2)
		return
	var seconds := 25.0
	var take_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="): seconds = clampf(arg.get_slice("=", 1).to_float(), 5, 60)
		elif arg.begins_with("--take="): take_path = arg.trim_prefix("--take=")
	var host = load("res://src/ui/workbench.gd").new()
	root.add_child(host)
	await process_frame
	if not take_path.is_empty():
		var loaded: Dictionary = host.service.execute({"op": "take.load", "args": {"path": take_path}})
		if not loaded.get("ok", false): push_error(str(loaded)); quit(2); return
		host.session.play()
	elif "--record" in OS.get_cmdline_user_args(): host.session.start_recording()
	else: host.session.play()
	var start := Time.get_ticks_usec()
	var previous := start
	var next_log := 3.0
	while Time.get_ticks_usec() - start < int(seconds * 1000000):
		await process_frame
		var now := Time.get_ticks_usec()
		var elapsed := (now - start) / 1000000.0
		if elapsed > 1:
			var frame_ms := (now - previous) / 1000.0
			samples.append(frame_ms)
			worst.append({"at_seconds": elapsed, "frame_ms": frame_ms, "active": host.session.stage.world.dynamic_count()})
			worst.sort_custom(func(a, b): return a["frame_ms"] > b["frame_ms"])
			if worst.size() > 5: worst.pop_back()
			process_cost.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000)
			physics_cost.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000)
		previous = now
		if elapsed >= next_log:
			print("BENCH ", elapsed, " ", JSON.stringify(host.session.stage.world.get_report()))
			next_log += 3
	samples.sort()
	process_cost.sort()
	physics_cost.sort()
	var report := {"frames": samples.size(), "mean_ms": _mean(samples), "p95_ms": samples[int(samples.size() * 0.95)], "p99_ms": samples[int(samples.size() * 0.99)], "max_ms": samples.back(), "process_p95_ms": process_cost[int(process_cost.size() * 0.95)], "physics_p95_ms": physics_cost[int(physics_cost.size() * 0.95)], "over_33ms": samples.filter(func(x): return x > 33.34).size(), "world": host.session.stage.world.get_report()}
	report.merge({"average_fps": 1000.0 / report["mean_ms"], "target_fps": 60, "physics_hz": Engine.physics_ticks_per_second, "mode": host.session.mode, "seconds": seconds, "warmup_seconds": 1, "worst_frames": worst, "renderer": RenderingServer.get_current_rendering_method(), "all_frames_within_16_67ms": samples.back() <= 1000.0 / 60})
	var file := FileAccess.open("res://outputs/performance_benchmark.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("PERFORMANCE ", JSON.stringify(report))
	await RenderingServer.frame_post_draw
	host.viewport.get_texture().get_image().save_png("res://outputs/performance_preview.png")
	quit()

## Derive FPS from measured wall-clock frame intervals, not a fixed-fps simulation flag.
func _mean(values: Array) -> float:
	var total := 0.0
	for value in values: total += value
	return total / max(1, values.size())
