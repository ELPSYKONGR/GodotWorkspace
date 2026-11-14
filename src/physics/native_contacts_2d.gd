extends RefCounted
## Maintain native contact membership from engine signals instead of polling every body each tick.
var pairs: Dictionary = {}

## Both rigid bodies and sensors expose these body signals.
func watch(body: CollisionObject2D, id: String) -> void:
	if body is RigidBody2D or body is Area2D:
		body.body_entered.connect(_enter.bind(id))
		body.body_exited.connect(_exit.bind(id))

## A pair can be reported by either side; keep it until both sides have ended.
func _enter(other: Node, id: String) -> void:
	var other_id := str(other.get_meta("object_id", ""))
	if other_id.is_empty(): return
	var a := id if id < other_id else other_id
	var b := other_id if id < other_id else id
	var key := a + "|" + b
	if not pairs.has(key): pairs[key] = {"a": a, "b": b, "sides": {}}
	pairs[key]["sides"][id] = true

## Exit signals remove only the reporting side of a contact pair.
func _exit(other: Node, id: String) -> void:
	var other_id := str(other.get_meta("object_id", ""))
	var key := (id + "|" + other_id) if id < other_id else (other_id + "|" + id)
	if not pairs.has(key): return
	pairs[key]["sides"].erase(id)
	if pairs[key]["sides"].is_empty(): pairs.erase(key)

## Deferred body retirement must not leave stale pairs if no exit signal is emitted.
func forget(id: String) -> void:
	for key in pairs.keys():
		if pairs[key]["a"] == id or pairs[key]["b"] == id: pairs.erase(key)
