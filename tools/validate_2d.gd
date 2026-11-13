extends SceneTree
## Runs small, isolated fixtures against the actual Godot physics server.

const Probe = preload("res://scripts/probe_2d.gd")
var fixtures := [
	{"name": "floor", "source": "wall_floor", "spawns": [{"position": [360, 1020], "velocity": [0, 300]}]},
	{"name": "left_wall", "source": "wall_left", "spawns": [{"position": [120, 600], "velocity": [-300, 0]}]},
	{"name": "right_wall", "source": "wall_right", "spawns": [{"position": [600, 600], "velocity": [300, 0]}]},
	{"name": "ceiling", "source": "wall_top", "spawns": [{"position": [360, 320], "velocity": [0, -300]}]},
	{"name": "ball_pair", "source": "ball", "spawns": [
		{"position": [300, 600], "velocity": [200, 0]}, {"position": [420, 600], "velocity": [-200, 0]}]},
	{"name": "no_contact", "source": "none", "spawns": [{"position": [360, 600], "velocity": [0, 0]}]}
]
var fixture_index := -1
var current: Node
var results: Array = []
var complete := false


## Fixes the physics rate and starts the first isolated fixture.
func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	_next.call_deferred()


## Disposes the previous fixture or saves the final acceptance report.
func _next() -> void:
	if is_instance_valid(current):
		root.remove_child(current)
		current.queue_free()
	fixture_index += 1
	if fixture_index == fixtures.size():
		var passed := true
		for result in results:
			passed = passed and result["passed"]
		DirAccess.make_dir_recursive_absolute("res://outputs")
		var file := FileAccess.open("res://outputs/probe_2d_validation.json", FileAccess.WRITE)
		if file == null:
			push_error("Cannot write 2D acceptance report: %s" % FileAccess.get_open_error())
			complete = true
			quit(1)
			return
		file.store_string(JSON.stringify({"passed": passed, "physics_hz": 240, "fixtures": results}, "  "))
		file.close()
		print("2D_FIXTURES_PASSED=", passed)
		complete = true
		quit(0 if passed else 1)
		return
	current = Probe.new()
	current.setup({"gravity": 0, "radius": 18, "max_balls": 4, "split_children": 2, "protection": 0.05,
		"spawns": fixtures[fixture_index]["spawns"]})
	root.add_child(current)


## Checks contact provenance and the parent/child ledger after 0.8 simulation seconds.
func _process(_delta: float) -> bool:
	if complete or not is_instance_valid(current) or current.elapsed < 0.8:
		return false
	var fixture: Dictionary = fixtures[fixture_index]
	var report: Dictionary = current.get_report()
	var source_found: bool = fixture["source"] == "none" and report["splits"] == 0
	for event in report["events"]:
		if event["type"] != "split":
			continue
		for source in event["sources"]:
			if source["name"] == fixture["source"] or source["kind"] == fixture["source"]:
				source_found = true
	var no_retired_active := true
	for id in report["active_ids"]:
		no_retired_active = no_retired_active and not report["retired_ids"].has(id)
	var passed: bool = source_found and report["ledger_ok"] and no_retired_active and report["duplicate_parent_splits"] == 0
	results.append({"name": fixture["name"], "passed": passed, "expected_source": fixture["source"],
		"source_found": source_found, "no_retired_active": no_retired_active, "report": report})
	print(fixture["name"], ": ", passed, " splits=", report["splits"])
	_next()
	return false
