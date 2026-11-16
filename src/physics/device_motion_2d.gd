extends RefCounted
## Fixed-step motor drives native AnimatableBody2D colliders; visuals read their real poses.
var elapsed := 0.0

## Compute a driven pose about a local pivot, anchored to the saved initial transform.
static func pose(spec: Dictionary, time: float) -> Transform2D:
	var motion: Dictionary = spec.get("motion", {})
	var base: Array = spec["transform"]["position"]
	var origin := Vector2(float(base[0]), float(base[1]))
	var initial := deg_to_rad(float(spec["transform"].get("rotation_degrees", 0)))
	var angle := initial
	var offset := Vector2.ZERO
	var phase := deg_to_rad(float(motion.get("phase_degrees", 0)))
	var wave := sin(TAU * time / float(motion.get("period_seconds", 4)) + phase) - sin(phase)
	match motion.get("type", "rotor"):
		"rotor": angle += deg_to_rad(float(motion.get("speed_degrees", 60))) * time
		"swing": angle += deg_to_rad(float(motion.get("amplitude_degrees", 45))) * wave
		"slider": offset = Vector2.from_angle(deg_to_rad(float(motion.get("direction_degrees", 0)))) * float(motion.get("travel", 180)) * 0.5 * wave
	var point: Array = motion.get("pivot", [0, 0])
	var pivot := Vector2(float(point[0]), float(point[1]))
	return Transform2D(angle, origin + offset + pivot.rotated(initial) - pivot.rotated(angle))

## Called only when the session schedules a real solver step; pause and hit-stop freeze it.
func advance(records: Dictionary, delta: float) -> void:
	elapsed += delta
	for record in records.values():
		var body = record.get("body")
		if not body is AnimatableBody2D: continue
		var previous := pose(record["spec"], elapsed - delta)
		var next := pose(record["spec"], elapsed)
		record["motor_velocity"] = (next.origin - previous.origin) / delta
		record["motor_angular_velocity"] = angle_difference(previous.get_rotation(), next.get_rotation()) / delta
		body.transform = next
