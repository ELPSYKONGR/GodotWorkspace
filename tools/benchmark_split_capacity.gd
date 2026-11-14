extends SceneTree
## Real-GPU split growth and full-load timing; run only in an isolated workbench copy.
var rows: Array = []
var checkpoints: Array = []

## Wait for the tree before creating the normal workbench and its native viewport.
func _initialize() -> void:
	_run.call_deferred()

## Measure real wall-clock frames during natural growth and optional synthetic slot recycling.
func _run() -> void:
	if DisplayServer.get_name() == "headless": push_error("Capacity timing requires a real GPU window"); quit(2); return
	var limit := 256
	var frame_cap := 60
	var grow_seconds := 40.0
	var hold_seconds := 20.0
	var label := "capacity"
	var vsync := -1
	var bridge_updates := true
	var recycle_interval := 0.0
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=", true, 1)
		if pair.size() != 2: continue
		match pair[0]:
			"limit": limit = int(pair[1])
			"frame-cap": frame_cap = int(pair[1])
			"grow-seconds": grow_seconds = float(pair[1])
			"hold-seconds": hold_seconds = float(pair[1])
			"label": label = pair[1].validate_filename()
			"vsync": vsync = int(pair[1])
			"bridge": bridge_updates = pair[1] != "false"
			"recycle-interval": recycle_interval = float(pair[1])
	var host = load("res://src/ui/workbench.gd").new()
	root.add_child(host)
	await process_frame
	if host.service.document["world"]["dimension"] != "2d": push_error("This benchmark is for the current 2D scene"); quit(2); return
	var applied: Dictionary = host.service.execute({"op": "scene.patch", "args": {"changes": {"world.max_dynamic_bodies": limit}}})
	if not applied.get("ok", false): push_error(str(applied)); quit(2); return
	var split_enabled := false
	for rule in host.service.document["mechanisms"]:
		if rule.get("type", "") == "split_on_contact" and rule.get("enabled", true): split_enabled = true
		if rule.get("type", "") == "hit_stop_on_event" and rule.get("enabled", true): push_error("Disable intentional hit-stop for a continuous-motion capacity test"); quit(2); return
	if not split_enabled: push_error("Split mechanism must be enabled"); quit(2); return
	Engine.max_fps = frame_cap
	if vsync >= 0: DisplayServer.window_set_vsync_mode(vsync)
	elif frame_cap > 60: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if not bridge_updates: host.set_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	host.session.play()
	var world: Node = host.session.stage.world
	var fixed_count := 0
	for spec in host.service.document["objects"]:
		if spec.get("physics", {}).get("mode", "dynamic") != "dynamic": fixed_count += 1
	var started := Time.get_ticks_usec()
	var previous := started
	var previous_sim := 0.0
	var previous_splits := 0
	var reached_at := -1.0
	var next_checkpoint := 1.0
	var peak := 0
	var next_recycle := 0.0
	var recycled := 0
	var reached_splits := -1
	while true:
		await process_frame
		var now := Time.get_ticks_usec()
		var elapsed := (now - started) / 1000000.0
		var count: int = world.records.size() - fixed_count
		var splits: int = world.runner.splits
		var frame_ms := (now - previous) / 1000.0
		peak = maxi(peak, count)
		if count >= limit and reached_at < 0:
			reached_at = elapsed
			reached_splits = splits
		if recycle_interval > 0 and count >= limit and elapsed >= next_recycle:
			# Synthetic load only: retire one ball, then let real contacts split back into the slot.
			for id in world.records:
				if world.records[id]["spec"].get("physics", {}).get("mode", "dynamic") == "dynamic":
					world.remove_object(id)
					world.runner.retired += 1
					world.emit_event({"type": "retire", "id": id, "reason": "capacity_stress_recycle"})
					recycled += 1
					break
			count = world.records.size() - fixed_count
			next_recycle = elapsed + recycle_interval
		if elapsed >= 1: rows.append([elapsed, frame_ms, count, splits - previous_splits, host.session.sim_time - previous_sim])
		if elapsed >= next_checkpoint:
			var visible := 0
			for id in world.records:
				if world.records[id]["spec"].get("physics", {}).get("mode", "dynamic") == "dynamic" and Rect2(0, 0, 720, 1280).has_point(world._position(id)): visible += 1
			checkpoints.append({"seconds": elapsed, "active": count, "onscreen_centers": visible, "splits": splits, "sim_time": host.session.sim_time, "film_time": host.session.time})
			print("CAPACITY_PROGRESS ", label, " ", elapsed, " balls=", count, " splits=", splits)
			next_checkpoint += 1
		previous = now
		previous_sim = host.session.sim_time
		previous_splits = splits
		if reached_at >= 0 and elapsed - reached_at >= hold_seconds: break
		if reached_at < 0 and elapsed >= grow_seconds: break
	var growth: Array = []
	var full: Array = []
	var split_frames: Array = []
	for row in rows:
		if reached_at < 0 or row[0] <= reached_at: growth.append(row[1])
		else: full.append(row[1])
		if row[3] > 0: split_frames.append(row[1])
	var all: Array = []
	for row in rows: all.append(row[1])
	var report := {"label": label, "limit": limit, "peak_active": peak, "reached_limit": reached_at >= 0, "reached_at_seconds": reached_at, "frame_cap": frame_cap, "vsync_mode": DisplayServer.window_get_vsync_mode(), "screen_refresh_hz": DisplayServer.screen_get_refresh_rate(), "renderer": RenderingServer.get_current_rendering_method(), "physics_hz": Engine.physics_ticks_per_second, "warmup_seconds": 1, "split_enabled": split_enabled, "world": world.get_report(), "overall": _stats(all), "growth": _stats(growth), "at_limit": _stats(full), "frames_with_split_commits": _stats(split_frames), "checkpoints": checkpoints, "settings": host.service.document, "row_columns": ["elapsed_seconds", "frame_ms", "active", "split_commits", "sim_delta"], "rows": rows}
	var directory := "res://outputs/split_capacity"
	report["bridge_updates"] = bridge_updates
	report["recycle_interval"] = recycle_interval
	report["synthetically_retired"] = recycled
	report["split_commits_after_first_reaching_limit"] = world.runner.splits - reached_splits if reached_splits >= 0 else 0
	DirAccess.make_dir_recursive_absolute(directory)
	var output := FileAccess.open(directory.path_join(label + ".json"), FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	print("CAPACITY_RESULT ", JSON.stringify({"label": label, "peak": peak, "reached": reached_at, "overall": report["overall"], "at_limit": report["at_limit"]}))
	await RenderingServer.frame_post_draw
	host.viewport.get_texture().get_image().save_png(directory.path_join(label + ".png"))
	quit()

## Preserve strict frame-budget results separately from averages and pacing percentiles.
func _stats(values: Array) -> Dictionary:
	if values.is_empty(): return {"frames": 0}
	values.sort()
	var total := 0.0
	var tail := 0.0
	var tail_count := maxi(1, int(ceil(values.size() * 0.01)))
	for value in values: total += value
	for index in range(values.size() - tail_count, values.size()): tail += values[index]
	return {"frames": values.size(), "seconds": total / 1000, "average_fps": values.size() * 1000.0 / total, "one_percent_low_fps": tail_count * 1000.0 / tail, "p95_ms": values[mini(values.size() - 1, int(values.size() * 0.95))], "p99_ms": values[mini(values.size() - 1, int(values.size() * 0.99))], "max_ms": values.back(), "over_16_67ms": values.filter(func(value): return value > 1000.0 / 60).size(), "over_33_34ms": values.filter(func(value): return value > 1000.0 / 30).size(), "strict_60fps_budget": values.back() <= 1000.0 / 60}
