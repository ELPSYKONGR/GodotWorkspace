extends RefCounted
## Convert actual contact episodes into durable pane damage and one deferred break event.
var world: Node
var seen: Dictionary = {}

## Count ball contacts only once per pane and native contact episode.
func consume(event: Dictionary) -> void:
	for id in [str(event["id"]),str(event["other_id"])]:
		if not world.records.has(id): continue
		var record: Dictionary = world.records[id]
		var spec: Dictionary = record["spec"]
		if not spec.has("glass") or int(record.get("glass_remaining",0))<=0: continue
		var other := str(event["other_id"]) if id==str(event["id"]) else str(event["id"])
		if not "ball" in world.definitions.get(other,{}).get("tags",[]): continue
		if not world.records.has(other) or world.records[other]["spec"].get("physics",{}).get("mode","dynamic")!="dynamic": continue
		var key: String = id+":"+str(event["contact_episode_id"])
		if seen.has(key): continue
		seen[key]=true
		record["glass_remaining"]-=1
		record["glass_hit_time"]=float(event["time"])
		var local: Vector2 = (world.project_point(event["position"])-world._position(id)).rotated(-world._rotation(id))
		var mark := {"point":[local.x,local.y],"seed":key.hash()}
		record["glass_marks"].append(mark)
		if record["glass_marks"].size()>24: record["glass_marks"].pop_front()
		world.emit_event({"type":"glass_hit","contact_episode_id":event["contact_episode_id"],"id":id,"position":event["position"],"remaining":record["glass_remaining"],"total":spec["glass"]["hits"],"time":event["time"]})
		if record["glass_remaining"]==0: world._commit_glass_break.call_deferred(id,event["position"])

## Remove only the intact static collider; flying shards are explicitly visual, not rigid bodies.
func commit(id: String, point: Array) -> void:
	if not world.records.has(id): return
	if not world.can_process():
		world.get_tree().process_frame.connect(world._commit_glass_break.bind(id,point),CONNECT_ONE_SHOT)
		return
	var spec: Dictionary = world.records[id]["spec"]
	var position: Array = world.object_position(id)
	var rotation: float = world._rotation(id)
	world.remove_object(id)
	world.emit_event({"type":"glass_break","id":id,"position":point,"origin":position,"rotation":rotation,"shape":spec["shape"].duplicate(true),"color":spec.get("appearance",{}).get("color","#53c7df"),"pieces":int(spec["glass"].get("shards",48)),"time":world.runner.elapsed})
