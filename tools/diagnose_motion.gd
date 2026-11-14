extends SceneTree
## Compare rendering cadence with actual simulation advancement around native contacts.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var seconds := 12.0
	var output := "res://outputs/motion_diagnostic.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="): seconds = float(arg.get_slice("=", 1))
		elif arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	var host = load("res://src/ui/workbench.gd").new()
	root.add_child(host)
	await process_frame
	var timeline: Array = []
	var started := Time.get_ticks_usec()
	host.session.event_logged.connect(func(event: Dictionary):
		if timeline.size() < 120 and (event.get("type", "") == "split" or (event.get("type", "") == "contact" and event.get("phase", "") == "enter")):
			timeline.append({"wall_seconds": (Time.get_ticks_usec() - started) / 1000000.0, "type": event["type"], "id": event.get("id", ""), "sim_time": host.session.sim_time, "film_time": host.session.time, "hold_ticks": host.session._hold_ticks}))
	host.session.play()
	var frames: Array = []
	var previous := Time.get_ticks_usec()
	var previous_sim := 0.0
	var freeze_ms := 0.0
	var freezes: Array = []
	var held_frames := 0
	while Time.get_ticks_usec() - started < seconds * 1000000:
		await process_frame
		var now := Time.get_ticks_usec()
		var frame_ms := (now - previous) / 1000.0
		frames.append(frame_ms)
		if host.session.sim_time == previous_sim:
			freeze_ms += frame_ms
		else:
			if freeze_ms >= 25: freezes.append(freeze_ms)
			freeze_ms = 0
		if host.session._last_hold: held_frames += 1
		previous_sim = host.session.sim_time
		previous = now
	if freeze_ms >= 25: freezes.append(freeze_ms)
	var total_ms := 0.0
	for value in frames: total_ms += value
	frames.sort()
	freezes.sort()
	var report := {"wall_seconds": total_ms / 1000.0, "render_fps": frames.size() * 1000.0 / total_ms, "render_max_ms": frames.back(), "render_p95_ms": frames[int(frames.size() * 0.95)], "render_frames_over_33ms": frames.filter(func(value): return value > 33.34).size(), "sim_seconds": host.session.sim_time, "film_seconds": host.session.time, "intentional_hold_seconds": host.session.time - host.session.sim_time, "held_render_frames": held_frames, "motion_freezes_ms": freezes, "timeline": timeline, "world": host.session.stage.world.get_report()}
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("MOTION_DIAGNOSTIC ", JSON.stringify(report))
	quit()
