extends RefCounted
## Reject malformed glass state/event extensions before replay reaches drawing or shard allocation.

## Finite numeric data only; JSON strings cannot impersonate counters or coordinates.
static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

## Glass metadata uses 2D local or world coordinates.
static func vector(value: Variant) -> bool:
	return value is Array and value.size()==2 and number(value[0]) and number(value[1])

## Static panes must be original validated scene objects, not unvalidated replay-only geometry.
static func definition_valid(definition: Dictionary, scene: Dictionary) -> bool:
	for spec in scene.get("objects",[]):
		if spec.get("id","")==definition.get("id",""):
			return spec.get("glass")==definition.get("glass") and spec.get("shape")==definition.get("shape")
	return false

## Restore only bounded damage counters and finite crack marks attached to a known pane.
static func state_valid(state: Dictionary, definition: Dictionary) -> bool:
	if not definition.has("glass"): return true
	if not number(state.get("glass_remaining")) or float(state["glass_remaining"])!=floor(float(state["glass_remaining"])): return false
	if int(state["glass_remaining"])<0 or int(state["glass_remaining"])>int(definition["glass"]["hits"]): return false
	if not number(state.get("glass_hit_time")) or not state.get("glass_marks") is Array or state["glass_marks"].size()>24: return false
	for mark in state["glass_marks"]:
		if not mark is Dictionary or not vector(mark.get("point")) or not number(mark.get("seed")): return false
	return true

## All shard allocation inputs must originate from a validated pane definition.
static func event_valid(event: Dictionary, definitions: Dictionary) -> bool:
	if event.get("type","") not in ["glass_hit","glass_break"]: return true
	var id := str(event.get("id",""))
	if not number(event.get("sim_time",event.get("time"))) or float(event.get("sim_time",event.get("time",0)))<0: return false
	if not definitions.has(id) or not definitions[id].has("glass") or not vector(event.get("position")): return false
	if event["type"]=="glass_hit":
		return number(event.get("remaining")) and float(event["remaining"])==floor(float(event["remaining"])) and float(event["remaining"])>=0 and float(event["remaining"])<=float(definitions[id]["glass"]["hits"]) and event.get("total")==definitions[id]["glass"]["hits"]
	if not vector(event.get("origin")) or not number(event.get("rotation")) or event.get("shape")!=definitions[id]["shape"]: return false
	if not number(event.get("pieces")) or float(event["pieces"])!=floor(float(event["pieces"])) or float(event["pieces"])<1 or float(event["pieces"])>256: return false
	if not event.get("color") is String: return false
	return Color.from_string(event["color"],Color(-1,-1,-1,-1)).a>=0

## Capture independent damage arrays alongside an ordinary physical pose.
static func capture_damage(state: Dictionary, record: Dictionary) -> void:
	if not record["spec"].has("glass"): return
	for key in ["glass_remaining","glass_marks","glass_hit_time"]:
		state[key]=record[key].duplicate(true) if record[key] is Array else record[key]

## Replaying damage state never runs a contact rule or changes native physics.
static func restore_damage(state: Dictionary, record: Dictionary) -> void:
	if not record["spec"].has("glass"): return
	for key in ["glass_remaining","glass_marks","glass_hit_time"]:
		if state.has(key): record[key]=state[key].duplicate(true) if state[key] is Array else state[key]
