extends Node
## Evaluates native contacts and commits body replacement after contact callbacks finish.

var world: Node
var document: Dictionary = {}
var rules: Dictionary = {}
var previous_pairs: Dictionary = {}
var assigned_rules: Dictionary = {}
var pending: Dictionary = {}
var physics_tick := 0
var elapsed := 0.0
var contacts := 0
var splits := 0
var retired := 0
var births := 0
var rejections := 0
var episode := 0
var child_serial := 0
var flush_queued := false
var placement_retry_after: Dictionary = {}
var active_dynamics := 0
const CONTACT_GRACE_SECONDS := 1.0 / 30.0


## Bind the world adapter and build the rule lookup from scene data.
func setup(owner_world: Node, doc: Dictionary) -> void:
	world = owner_world
	document = doc
	for rule in doc.get("mechanisms", []):
		rules[str(rule.get("id", ""))] = rule


## Poll actual current engine contacts; signals alone miss protection-expiry contacts.
func step() -> void:
	physics_tick += 1
	active_dynamics = world.dynamic_count()
	elapsed = physics_tick / float(document.get("world", {}).get("physics_hz", 120))
	var current: Dictionary = world.contact_pairs()
	for key in current:
		var pair: Dictionary = current[key]
		pair["last_seen_tick"] = physics_tick
		if not previous_pairs.has(key):
			pair["rejected"] = {}
			pair["capacity_blocked"] = {}
			episode += 1
			pair["episode"] = episode
			contacts += 1
			_contact_event(pair, "enter")
			pair["phase"] = "enter"
		else:
			pair["rejected"] = previous_pairs[key]["rejected"]
			pair["capacity_blocked"] = previous_pairs[key]["capacity_blocked"]
			pair["position"] = previous_pairs[key].get("position", [])
			pair["position_source"] = previous_pairs[key].get("position_source", "body_centers_estimate")
			pair["episode"] = previous_pairs[key]["episode"]
			pair["phase"] = "stay"
		_evaluate(str(pair["a"]), str(pair["b"]), pair)
		_evaluate(str(pair["b"]), str(pair["a"]), pair)
	for key in previous_pairs:
		if not current.has(key):
			# Stabilize 2D contact episodes over one 30fps interval; never evaluate absent contacts.
			var grace := int(float(document.get("world", {}).get("physics_hz", 120)) * CONTACT_GRACE_SECONDS) if world.dimensions == 2 else 0
			if physics_tick - int(previous_pairs[key].get("last_seen_tick", 0)) <= grace:
				current[key] = previous_pairs[key]
			else: _contact_event(previous_pairs[key], "exit")
	previous_pairs = current
	if not pending.is_empty() and not flush_queued:
		flush_queued = true
		_commit.call_deferred()


## Emit one event per pair and episode; preserve the geometry estimate's explicit source.
func _contact_event(pair: Dictionary, phase: String) -> void:
	_update_anchor(pair)
	var a := str(pair["a"])
	var b := str(pair["b"])
	world.emit_event({"type": "contact", "phase": phase, "id": a, "body_id": a,
		"other_id": b, "contact_episode_id": pair["episode"], "position": pair["position"],
		"position_source": pair.get("position_source", "body_centers_estimate"), "normal": null, "impulse": null,
		"source_kind": world.source_kind(b), "time": elapsed, "sim_tick": physics_tick})


## Evaluate each body against the same contact snapshot before any removals occur.
func _evaluate(id: String, other_id: String, pair: Dictionary) -> void:
	if not world.records.has(id) or pending.has(id):
		return
	# A sole split rule denied at full capacity cannot change until the population changes.
	if pair["capacity_blocked"].get(id, -1) == active_dynamics: return
	var record: Dictionary = world.records[id]
	var spec: Dictionary = record["spec"]
	if spec.get("physics", {}).get("mode", "dynamic") != "dynamic":
		return
	# Descendants inherit their root's rule list; resolve/sort it once per root.
	var root_id := str(spec.get("root_id", id))
	if not assigned_rules.has(root_id):
		var resolved: Array = []
		for rule_id in spec.get("mechanisms", []):
			if rules.has(str(rule_id)): resolved.append(rules[str(rule_id)])
		resolved.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.get("priority", 0)) > int(b.get("priority", 0)))
		assigned_rules[root_id] = resolved
	var assigned: Array = assigned_rules[root_id]
	for rule in assigned:
		var rule_id := str(rule.get("id", ""))
		if not bool(rule.get("enabled", true)):
			continue
		var kind := str(rule.get("type", ""))
		if kind not in ["split_on_contact", "despawn_on_contact"]:
			continue
		var trigger: Dictionary = rule.get("trigger", {})
		if pair.get("phase", "enter") not in trigger.get("phases", ["enter", "stay"]) and not bool(trigger.get("recheck_active_after_birth_guard", false)):
			continue
		var conditions: Dictionary = rule.get("conditions", {})
		var wanted: Array = conditions.get("other_tags_any", [])
		var other_tags: Array = world.definitions.get(other_id, {}).get("tags", [])
		var matches := wanted.is_empty()
		for tag in wanted:
			matches = matches or tag in other_tags
		var reason := ""
		if not matches:
			reason = "tag_mismatch"
		elif kind == "split_on_contact" and int(spec.get("generation", 0)) > 0 and not bool(rule.get("params", {}).get("children_can_split", true)):
			reason = "children_split_disabled"
		elif elapsed - float(record.get("born", -1000)) < float(conditions.get("newborn_guard_seconds", 0.08)):
			reason = "newborn_guard"
		elif bool(conditions.get("require_minimum_impact", false)):
			reason = "impact_metric_unavailable"
		elif kind == "split_on_contact" and spec.get("shape", {}).get("primitive", "") not in ["circle", "sphere"]:
			reason = "split_requires_ball"
		if not reason.is_empty():
			_reject(id, str(rule_id), reason, pair)
			continue
		if kind == "split_on_contact":
			var count := int(rule.get("params", {}).get("children_total", 2))
			if active_dynamics - 1 + count > int(document.get("world", {}).get("max_dynamic_bodies", 48)):
				_reject(id, rule_id, "capacity_limit", pair)
				if assigned.size() == 1: pair["capacity_blocked"][id] = active_dynamics
				continue
			# Failed geometry searches retry at 20Hz, while native contacts still run every tick.
			if elapsed < float(placement_retry_after.get(id, 0)): continue
		pending[id] = {"rule": rule, "pair": pair.duplicate()}
		break


## Limit repetitive diagnostics without hiding distinct rejection reasons.
func _reject(id: String, rule_id: String, reason: String, pair: Dictionary) -> void:
	var key := "%s:%s:%s" % [id, rule_id, reason]
	var rejected: Dictionary = pair.get("rejected", {})
	if rejected.has(key):
		return
	rejected[key] = true
	_update_anchor(pair)
	rejections += 1
	world.emit_event({"type": "rule_rejected", "id": id, "body_id": id, "rule_id": rule_id,
		"reason": reason, "position": pair.get("position", []), "time": elapsed, "sim_tick": physics_tick})

## Keep lazy 2D anchors current while preserving the existing 3D adapter interface.
func _update_anchor(pair: Dictionary) -> void:
	if pair.get("anchor_tick", -1) == physics_tick: return
	if world.has_method("contact_anchor") and world.records.has(pair["a"]) and world.records.has(pair["b"]):
		pair.merge(world.contact_anchor(pair), true)
		pair["anchor_tick"] = physics_tick


## Replace whole parents only after capacity and every child position pass validation.
func _commit() -> void:
	flush_queued = false
	if not world.can_process():
		_schedule_commit()
		return
	var started := Time.get_ticks_usec()
	var committed := 0
	var ids := pending.keys()
	ids.sort()
	for id in ids:
		# Keep each parent replacement atomic, but spread simultaneous parents over frames.
		if committed >= 4 or (committed > 0 and Time.get_ticks_usec() - started >= 2000): break
		var item: Dictionary = pending[id]
		pending.erase(id)
		committed += 1
		if not world.records.has(id):
			continue
		var rule: Dictionary = item["rule"]
		var record: Dictionary = world.records[id]
		if rule.get("type", "") == "despawn_on_contact":
			world.remove_object(id)
			retired += 1
			world.emit_event({"type": "retire", "id": id, "reason": "despawn", "time": elapsed})
			continue
		var params: Dictionary = rule.get("params", {})
		var count := clampi(int(params.get("children_total", 2)), 2, 100)
		var cap := int(document.get("world", {}).get("max_dynamic_bodies", 48))
		if world.dynamic_count() - 1 + count > cap:
			_reject(id, str(rule.get("id", "")), "capacity_limit", item["pair"])
			continue
		var radius := float(record["spec"].get("shape", {}).get("radius", 18.0))
		if params.get("size_policy", "same_size_gameplay") in ["conserve_volume", "conserve_area"]:
			radius /= pow(float(count), 1.0 / float(world.dimensions))
		if radius < (1.0 if world.dimensions == 2 else 0.02):
			_reject(id, str(rule.get("id", "")), "minimum_radius", item["pair"])
			continue
		var positions: Array = world.birth_positions(id, count, radius)
		if positions.size() != count:
			placement_retry_after[id] = elapsed + 0.05
			_reject(id, str(rule.get("id", "")), "birth_space_blocked", item["pair"])
			continue
		placement_retry_after.erase(id)
		var position: Array = world.object_position(id)
		var velocity: Array = world.object_velocity(id)
		var source: Dictionary = record["spec"].duplicate(true)
		var generation := int(source.get("generation", 0)) + 1
		world.remove_object(id)
		retired += 1
		world.emit_event({"type": "retire", "id": id, "reason": "split", "time": elapsed})
		var children: Array = []
		for index in count:
			child_serial += 1
			var child_id := "%s_child_%d" % [source.get("root_id", id), child_serial]
			while world.definitions.has(child_id):
				child_serial += 1
				child_id = "%s_child_%d" % [source.get("root_id", id), child_serial]
			var child := source.duplicate(true)
			child["id"] = child_id
			child["parent"] = id
			child["root_id"] = source.get("root_id", id)
			child["generation"] = generation
			child["shape"]["radius"] = radius
			child["transform"]["position"] = positions[index]
			child["physics"]["velocity"] = world.child_velocity(position, positions[index], velocity, float(params.get("ejection_speed", 100.0 if world.dimensions == 2 else 1.5)))
			child["physics"]["mass"] = float(source.get("physics", {}).get("mass", 1.0)) / count
			world.create_object(child, elapsed)
			births += 1
			children.append(child_id)
		splits += 1
		world.emit_event({"type": "split", "id": id, "parent": id, "children": children,
			"position": position, "generation": generation, "time": elapsed, "sim_tick": physics_tick})
	_schedule_commit()

## Resume remaining transactions on the next frame, including after a physical pause.
func _schedule_commit() -> void:
	if pending.is_empty() or flush_queued: return
	flush_queued = true
	get_tree().process_frame.connect(_commit, CONNECT_ONE_SHOT)
