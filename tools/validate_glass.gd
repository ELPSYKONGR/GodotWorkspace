extends SceneTree
## Native glass damage, reversible Take state, UI fields and instance-rendering regressions.
const Document=preload("res://src/document/scene_document.gd")
var results: Dictionary={}

## Defer construction until native scene services are available.
func _initialize() -> void:
	_run.call_deferred()

## Exercise real impacts rather than injecting fake damage events.
func _run() -> void:
	var loaded := Document.load_file("res://config/workbench_glass.json")
	results["demo_schema_valid"]=loaded["ok"]
	if not loaded["ok"]: print(loaded);quit(2);return
	var doc: Dictionary=loaded["document"]
	var invalid := doc.duplicate(true)
	invalid["objects"][1]["glass"]["hits"]=1.5
	results["fractional_hits_rejected"]=not Document.validate(invalid).is_empty()
	invalid=doc.duplicate(true)
	invalid["objects"][1]["shape"]["outer_radius"]=1e20
	results["unbounded_arc_rejected"]=not Document.validate(invalid).is_empty()
	var session=load("res://src/runtime/scene_session.gd").new()
	root.add_child(session)
	session.load_document(doc)
	session.start_recording()
	for frame in 3000:
		await process_frame
		if session.time>=12: break
	session.stop_recording()
	var data: Dictionary=session.take.get_data()
	var native: Dictionary={}
	var damaged: Dictionary={}
	var remaining: Dictionary={}
	var broken: Dictionary={}
	var correct := true
	var first_break := -1.0
	var crack: Dictionary={}
	for event in data["events"]:
		if event["type"]=="contact" and event["phase"]=="enter":
			for id in [event["id"],event["other_id"]]: native[str(id)+":"+str(event["contact_episode_id"])]=true
		if event["type"]=="glass_hit":
			var key := str(event["id"])+":"+str(event["contact_episode_id"])
			correct=correct and native.has(key) and not damaged.has(key)
			damaged[key]=true
			var before: int=int(remaining.get(event["id"],event["total"]))
			correct=correct and int(event["remaining"])==before-1 and int(event["remaining"])>=0
			remaining[event["id"]]=event["remaining"]
			if crack.is_empty() and int(event["remaining"])>0: crack=event
		if event["type"]=="glass_break":
			correct=correct and not broken.has(event["id"]) and int(remaining.get(event["id"],-1))==0
			broken[event["id"]]=true
			if first_break<0: first_break=event["time"]
	results["native_episode_decrements_exactly_once"]=correct and damaged.size()>=8
	results["zero_hits_breaks_once"]=broken.size()>=2
	results["visual_shards_do_not_create_dynamic_bodies"]=session.stage.world.dynamic_count()==1 and session.stage.world.get_report()["ledger_ok"]
	results["ball_uses_one_multimesh_instance"]=session.stage.world.ball_batch.multimesh.visible_instance_count==1
	results["save_take"]=session.take.save("res://outputs/glass_validation.take.json")==OK
	var restored=load("res://src/takes/take_store.gd").new()
	results["load_take"]=restored.load_take("res://outputs/glass_validation.take.json")==OK
	session.seek(first_break+0.15)
	results["break_removes_recorded_collider_visual"]=not session.stage.world.records.has("glass_1")
	var shards: MultiMesh=session.stage.world.glass_view.shards.multimesh
	results["break_shards_instanced"]=shards.visible_instance_count==64
	var pose := shards.get_instance_transform_2d(0)
	session.seek(0)
	results["rewind_restores_intact_pane"]=session.stage.world.records.has("glass_1") and session.stage.world.records["glass_1"]["glass_remaining"]==1
	session.seek(first_break+0.15)
	results["shard_seek_is_deterministic"]=pose==shards.get_instance_transform_2d(0)
	if not crack.is_empty():
		session.seek(float(crack["time"])+0.02)
		var pane: Dictionary=session.stage.world.records[crack["id"]]
		results["cracks_and_counter_restore"]=pane["glass_marks"].size()>0 and pane["glass_remaining"]==crack["remaining"]
	results["central_counter_bound_to_actual_damage"]=not crack.is_empty() and session.stage.world.glass_view.counter.text==str(int(crack["remaining"]))
	var malformed := data.duplicate(true)
	malformed["frames"][0]["states"][1]["glass_remaining"]=-1
	results["invalid_damage_state_rejected"]=not restored._valid(malformed)
	malformed=data.duplicate(true)
	for event in malformed["events"]:
		if event["type"]=="glass_break": event["pieces"]=1000000;break
	results["oversized_shard_event_rejected"]=not restored._valid(malformed)
	root.remove_child(session)
	session.queue_free()
	await process_frame
	# A sensor tagged as a ball overlaps panes but must never inflict physical damage.
	var sensor_doc := doc.duplicate(true)
	sensor_doc["objects"][0]["physics"]["mode"]="sensor"
	sensor_doc["objects"][0]["transform"]["position"]=[360,445]
	var sensor_world=load("res://src/physics/world_2d.gd").new()
	sensor_world.setup(sensor_doc)
	root.add_child(sensor_world)
	PhysicsServer2D.set_active(true)
	var sensor_events: Array=[]
	sensor_world.event_logged.connect(func(event): sensor_events.append(event))
	for tick in 24: await physics_frame
	results["sensor_overlap_does_not_damage_glass"]=sensor_events.any(func(event):return event["type"]=="contact") and not sensor_events.any(func(event):return event["type"]=="glass_hit")
	root.remove_child(sensor_world)
	sensor_world.queue_free()
	await process_frame
	var held=load("res://src/runtime/scene_session.gd").new()
	root.add_child(held)
	held.load_document(doc)
	var pause_flag := {"paused":false}
	held.event_logged.connect(func(event):
		if event["type"]=="glass_hit" and event["remaining"]==0 and not pause_flag["paused"]:
			pause_flag["paused"]=true
			held.pause()
	)
	held.play()
	for frame in 400:
		await process_frame
		if pause_flag["paused"]: break
	for frame in 3: await process_frame
	results["pause_holds_deferred_glass_retirement"]=pause_flag["paused"] and held.stage.world.records.has("glass_1")
	held.play()
	for frame in 4: await process_frame
	results["resume_commits_queued_break_once"]=not held.stage.world.records.has("glass_1") and held.events.filter(func(event):return event["type"]=="glass_break" and event["id"]=="glass_1").size()==1
	root.remove_child(held)
	held.queue_free()
	await process_frame
	var service=load("res://src/commands/command_service.gd").new()
	service.initialize(doc,func(_op,_args): return {"ok":false})
	var panel=load("res://src/ui/object_panel.gd").new()
	root.add_child(panel)
	panel.command_requested.connect(func(op,args): service.execute({"op":op,"args":args}))
	panel.sync_document(doc,"glass_1")
	panel.fields["glass_hits"].get_line_edit().text="7"
	panel._apply()
	results["inspector_commits_hit_count_and_preserves_angles"]=service.document["objects"][1]["glass"]["hits"]==7 and is_equal_approx(float(service.document["objects"][1]["shape"]["start_degrees"]),float(doc["objects"][1]["shape"]["start_degrees"]))
	service.execute({"op":"history.undo"})
	results["glass_edit_is_undoable"]=service.document["objects"][1]["glass"]["hits"]==1
	results["passed"]=not results.values().has(false)
	var file := FileAccess.open("res://outputs/glass_validation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"\t"))
	print("GLASS_VALIDATION ",JSON.stringify(results))
	for child in root.get_children(): child.queue_free()
	var cleanup_until := Time.get_ticks_msec()+100
	while Time.get_ticks_msec()<cleanup_until: await process_frame
	quit(0 if results["passed"] else 1)
