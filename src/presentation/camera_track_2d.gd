extends RefCounted
## One fixed-snapshot camera solver for live play, arbitrary Take seeking and video production.
var settings: Dictionary = {}
var bounds := Rect2(0, 0, 720, 1280)
var state: Dictionary = {}
var track: Array = []
var target_root := ""
var status := "固定镜头"

## Camera caches are disposable presentation data; a visual edit never changes native motion.
func configure(doc: Dictionary) -> void:
	settings = doc.get("presentation", {}).get("render", {}).get("camera", {}).duplicate(true)
	var area: Array = doc.get("world", {}).get("bounds_2d", [0, 0, 720, 1280])
	bounds = Rect2(float(area[0]), float(area[1]), float(area[2]), float(area[3]))
	target_root = str(settings.get("target_root", ""))
	if target_root.is_empty():
		for spec in doc.get("objects", []):
			if spec.get("physics", {}).get("mode", "dynamic") == "dynamic": target_root = str(spec["id"]); break
	state = initial()
	track.clear()

## Top-left camera coordinates are independent of every body's native transform.
func initial() -> Dictionary:
	var position: Array = settings.get("position_2d", [0, 0])
	return {"top": _limit(Vector2(float(position[0]), float(position[1]))), "target": "", "sim_time": 0.0}

## Integrate once per committed simulation snapshot; hit-stop has zero camera delta.
func advance(sim_time: float, states: Array, definitions: Dictionary) -> void:
	state = solve(state, sim_time, states, definitions)

## Resolve the previous committed camera sample, recomputing an amended final Take frame.
func sample(time: float, take: Dictionary) -> void:
	var frames: Array = take.get("frames", [])
	if frames.is_empty(): state = initial(); return
	var low := 0
	var high := frames.size() - 1
	while low < high:
		var middle := (low + high + 1) / 2
		if float(frames[middle]["time"]) <= time: low = middle
		else: high = middle - 1
	var start := mini(track.size(), low + 1)
	if start > 0: start -= 1
	track.resize(start)
	var previous: Dictionary = initial() if start == 0 else track[start - 1]
	for index in range(start, low + 1):
		previous = solve(previous, float(frames[index]["sim_time"]), frames[index]["states"], take.get("definitions", {}))
		track.append(previous)
	state = track[low]

## Stable root lineage selection survives parent retirement; unrelated balls never become targets.
func solve(previous: Dictionary, sim_time: float, states: Array, definitions: Dictionary) -> Dictionary:
	var result := previous.duplicate()
	result["sim_time"] = sim_time
	if settings.get("mode", "fixed") != "follow_y": return result
	var chosen: Dictionary = {}
	for pose in states:
		var id := str(pose["id"])
		var spec: Dictionary = definitions.get(id, {})
		if id == target_root: chosen = pose; break
		if settings.get("on_split", "lowest_descendant") == "stop" or str(spec.get("root_id", id)) != target_root: continue
		if chosen.is_empty() or float(pose["position"][1]) > float(chosen["position"][1]) or (pose["position"][1] == chosen["position"][1] and id < str(chosen["id"])): chosen = pose
	if chosen.is_empty():
		status = "跟随目标无存活对象，保持镜头：" + target_root
		return result
	result["target"] = str(chosen["id"])
	status = "跟随：" + result["target"] + " · 根谱系：" + target_root
	var top: Vector2 = previous["top"]
	var y := float(chosen["position"][1])
	var screen_y := (y - top.y) / 1280.0
	var desired := top.y
	if screen_y < float(settings.get("dead_zone_top", 0.32)) or screen_y > float(settings.get("dead_zone_bottom", 0.58)): desired = y - 1280 * float(settings.get("framing_y", 0.42))
	if settings.get("only_down", true): desired = maxf(top.y, desired)
	var delta := maxf(0, sim_time - float(previous["sim_time"]))
	var seconds := float(settings.get("smooth_seconds", 0.18))
	var next := desired if seconds == 0 else lerpf(top.y, desired, 1 - exp(-delta / seconds))
	result["top"] = _limit(Vector2(top.x, next))
	return result

## Clamp the viewing rectangle, never synthesize a physics wall or teleport a body.
func _limit(top: Vector2) -> Vector2:
	if not settings.get("limit_world", true): return top
	return top.clamp(bounds.position, bounds.position + (bounds.size - Vector2(720, 1280)).max(Vector2.ZERO))
