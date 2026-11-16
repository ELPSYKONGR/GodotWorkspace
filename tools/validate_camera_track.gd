extends SceneTree
## Verify camera behavior against known poses, including lineage, death, hit-stop and random seeking.
const Camera = preload("res://src/presentation/camera_track_2d.gd")
const Document = preload("res://src/document/scene_document.gd")
var checks: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

## Known fixture poses isolate camera errors from native solver variance.
func _run() -> void:
	var doc: Dictionary = Document.load_file("res://config/workbench_long.json")["document"]
	checks["long_scene_valid"] = Document.validate(doc).is_empty()
	var camera = Camera.new()
	camera.configure(doc)
	var definitions := {"ball_A": {"root_id": "ball_A"}, "child_1": {"root_id": "ball_A", "parent": "ball_A"}, "child_2": {"root_id": "ball_A", "parent": "ball_A"}, "grandchild": {"root_id": "ball_A", "parent": "child_2"}, "unrelated": {"root_id": "unrelated"}}
	var origin: Dictionary = camera.initial()
	var still: Dictionary = camera.solve(origin, 1, [_pose("ball_A", 600)], definitions)
	checks["dead_zone_holds_view"] = still["top"] == Vector2.ZERO
	var moved: Dictionary = camera.solve(still, 1.1, [_pose("ball_A", 1600)], definitions)
	checks["smooth_moves_partway_toward_framing"] = moved["top"].y > 0 and moved["top"].y < 1600 - 1280 * 0.42
	var held: Dictionary = camera.solve(moved, 1.1, [_pose("ball_A", 1800)], definitions)
	checks["hit_stop_freezes_camera"] = held["top"] == moved["top"]
	var upward: Dictionary = camera.solve(moved, 2, [_pose("ball_A", 0)], definitions)
	checks["down_only_rejects_upward_motion"] = upward["top"] == moved["top"]
	var split: Dictionary = camera.solve(moved, 2, [_pose("child_1", 2200), _pose("child_2", 2400), _pose("unrelated", 16000)], definitions)
	checks["retired_parent_follows_lowest_related_child"] = split["target"] == "child_2" and split["top"].y < 3000
	var grandchild: Dictionary = camera.solve(split, 3, [_pose("grandchild", 3300)], definitions)
	checks["lineage_survives_multiple_generations"] = grandchild["target"] == "grandchild"
	var lost: Dictionary = camera.solve(grandchild, 4, [_pose("unrelated", 16000)], definitions)
	checks["extinct_lineage_holds_last_view"] = lost["top"] == grandchild["top"] and camera.status.contains("无存活")
	camera.settings["only_down"] = false
	checks["upward_follow_can_be_enabled"] = camera.solve(moved, 2, [_pose("ball_A", 0)], definitions)["top"].y < moved["top"].y
	camera.settings["smooth_seconds"] = 0
	checks["zero_smoothing_snaps"] = is_equal_approx(camera.solve(origin, 1, [_pose("ball_A", 2000)], definitions)["top"].y, 2000 - 1280 * 0.42)
	checks["world_limit_clamps_view_not_body"] = camera.solve(origin, 1, [_pose("ball_A", 50000)], definitions)["top"].y == 18720
	checks["world_boundary_has_explicit_reason"] = camera.blocked_reason == "world_edge"
	camera.settings["limit_world"] = false
	checks["open_world_can_follow_beyond_bounds"] = camera.solve(origin, 1, [_pose("ball_A", 50000)], definitions)["top"].y > 20000
	checks["open_world_clears_boundary_reason"] = camera.blocked_reason.is_empty()
	camera.settings["on_split"] = "stop"
	checks["split_continuation_can_be_disabled"] = camera.solve(origin, 1, [_pose("child_1", 3000)], definitions)["top"] == Vector2.ZERO
	camera.configure(doc)
	var take := {"frames": [], "definitions": definitions}
	for i in 241:
		take["frames"].append({"time": i / 120.0, "sim_time": i / 120.0, "states": [_pose("ball_A" if i < 120 else "child_1", 400 + i * 15)]})
	var sequential: Dictionary = {}
	for i in 241:
		camera.sample(i / 120.0, take)
		sequential[i] = camera.state["top"]
	camera.configure(doc)
	var seek_ok := true
	for i in [220, 13, 170, 5, 240, 0, 120, 220]:
		camera.sample(i / 120.0, take)
		seek_ok = seek_ok and camera.state["top"].is_equal_approx(sequential[i])
	checks["random_seek_matches_forward_camera_track"] = seek_ok
	var malformed := doc.duplicate(true)
	malformed["presentation"]["render"]["camera"]["smooth_seconds"] = NAN
	checks["nonfinite_camera_rejected"] = not Document.validate(malformed).is_empty()
	malformed = doc.duplicate(true)
	malformed["presentation"]["render"]["camera"]["dead_zone_top"] = 0.8
	checks["reversed_dead_zone_rejected"] = not Document.validate(malformed).is_empty()
	checks["passed"] = not checks.values().has(false)
	DirAccess.make_dir_recursive_absolute("res://outputs")
	FileAccess.open("res://outputs/camera_track_validation.json", FileAccess.WRITE).store_string(JSON.stringify(checks, "\t"))
	print("CAMERA_TRACK ", JSON.stringify(checks))
	quit(0 if checks["passed"] else 1)

## A pose contains a real world position; camera output never writes back to it.
func _pose(id: String, y: float) -> Dictionary:
	return {"id": id, "position": [360, y]}
