extends RefCounted
## Long-world and camera controls; bounds are navigation data, real walls remain explicit objects.
const F = preload("res://src/ui/form_helpers.gd")

## Reuse the normal command/draft path for both loaded scenes and newly drawn scenes.
static func build(parent: Node, doc: Dictionary, send: Callable, pending: RefCounted, selected: String) -> void:
	var physics := F.section(parent, "世界物理", false)
	var hz := F.number(physics, "物理频率 / Hz", float(F.value(doc, "world.physics_hz", 120)), 60, 480, 30)
	var gravity: Array = doc["world"].get("gravity", [0, 450])
	var g := F.number(physics, "重力 Y", float(gravity[1]), -2000, 2000, 0.1)
	g.tooltip_text = "二维向下为正（px/s²）；三维向上为正（m/s²）"
	var apply_physics := func():
		hz.apply(); g.apply()
		var updated: Array = gravity.duplicate()
		updated[1] = g.value
		send.call("scene.patch", {"changes": {"world.physics_hz": int(hz.value), "world.gravity": updated}})
	F.button(physics, "应用世界物理", apply_physics)
	pending.register("world_physics", [hz, g], apply_physics)
	if doc["world"]["dimension"] != "2d":
		F.text(parent, "三维相机在“画面”中设置。")
		return
	var world := F.section(parent, "世界范围")
	world.tooltip_text = "范围用于镜头和导航，不产生隐形墙壁或地板；可在边界工具中同步现有标准墙壁"
	var area: Array = doc["world"].get("bounds_2d", [0, 0, 720, 1280])
	var bounds: Array = []
	for i in 4: bounds.append(F.number(world, ["起点 X", "起点 Y", "宽度 / px", "高度 / px"][i], float(area[i]), 1 if i > 1 else -100000, 100000, 1))
	var camera: Dictionary = F.value(doc, "presentation.render.camera", {})
	var lens := F.section(parent, "镜头")
	var mode := F.choice(lens, "模式", ["fixed", "follow_y"], str(camera.get("mode", "fixed")))
	var following := VBoxContainer.new()
	lens.add_child(following)
	var target_id := str(camera.get("target_root", selected))
	var ids: Array = [""]
	var names: Dictionary = {"": "自动（首个动态物体）"}
	for spec in doc.get("objects", []):
		var id := str(spec["id"])
		ids.append(id)
		names[id] = "%s · %s" % [spec.get("name", id), id]
	if not target_id in ids:
		ids.append(target_id)
		names[target_id] = "缺失物体 · " + target_id
	var target := F.choice(following, "跟随物体", ids, target_id)
	target.fit_to_longest_item = false
	target.clip_text = true
	target.tooltip_text = "按名称和 ID 选择初始物体；点击应用世界与镜头后生效"
	for index in target.item_count: target.set_item_text(index, names[ids[index]])
	var lineage := F.check(following, "分裂后跟随子球", camera.get("on_split", "lowest_descendant") == "lowest_descendant")
	lineage.tooltip_text = "沿原球谱系选择最低的存活后代；后代消失时保持最后镜头"
	var down := F.check(following, "只向下移动", bool(camera.get("only_down", true)))
	var limit := F.check(lens, "限制在世界范围", bool(camera.get("limit_world", true)))
	var warning := VBoxContainer.new()
	lens.add_child(warning)
	F.text(warning, "世界高度不超过画面，镜头无法下移。增加世界高度，或允许镜头越界。").add_theme_color_override("font_color", Color("ffcf8d"))
	var detail := F.section(following, "构图与平滑", false)
	var framing := F.number(detail, "构图高度比例", float(camera.get("framing_y", 0.42)), 0, 1, 0.01)
	var top := F.number(detail, "死区上边比例", float(camera.get("dead_zone_top", 0.32)), 0, 1, 0.01)
	var bottom := F.number(detail, "死区下边比例", float(camera.get("dead_zone_bottom", 0.58)), 0, 1, 0.01)
	var smoothing := F.number(detail, "平滑时间 / s", float(camera.get("smooth_seconds", 0.18)), 0, 10, 0.01)
	var fixed := VBoxContainer.new()
	lens.add_child(fixed)
	var position: Array = camera.get("position_2d", [0, 0])
	var x := F.number(fixed, "镜头左侧 X", float(position[0]), -100000, 100000, 1)
	var y := F.number(fixed, "镜头顶部 Y", float(position[1]), -100000, 100000, 1)
	var controls: Array = bounds + [mode, target, lineage, down, limit, framing, top, bottom, smoothing, x, y]
	var changes := func() -> Dictionary:
		for field in controls:
			if field is SpinBox: field.apply()
		var updated := camera.duplicate(true)
		updated.merge({"mode": F.selected(mode), "target_root": F.selected(target), "on_split": "lowest_descendant" if lineage.button_pressed else "stop", "only_down": down.button_pressed, "limit_world": limit.button_pressed, "framing_y": framing.value, "dead_zone_top": top.value, "dead_zone_bottom": bottom.value, "smooth_seconds": smoothing.value, "position_2d": [x.value, y.value]}, true)
		return {"world.bounds_2d": [bounds[0].value, bounds[1].value, bounds[2].value, bounds[3].value], "presentation.render.camera": updated}
	var apply := func(): send.call("scene.patch", {"changes": changes.call()})
	F.button(warning, "允许越界跟随", func():
		limit.button_pressed = false
		apply.call()).tooltip_text = "关闭镜头世界限制并应用当前世界与镜头设置；物理墙壁保持原位"
	F.button(parent, "应用世界与镜头", apply)
	pending.register("world_camera", controls, apply)
	var visibility := func():
		following.visible = F.selected(mode) == "follow_y"
		fixed.visible = not following.visible
		warning.visible = following.visible and limit.button_pressed and bounds[3].value <= 1280
	mode.item_selected.connect(func(_index): visibility.call())
	limit.toggled.connect(func(_value): visibility.call())
	bounds[3].value_changed.connect(func(_value): visibility.call())
	visibility.call()
	var tools := F.section(parent, "边界工具", false)
	F.button(tools, "同步地面与侧墙", func():
		var updates: Dictionary = changes.call()
		var objects: Array = doc["objects"].duplicate(true)
		var a: Array = updates["world.bounds_2d"]
		for spec in objects:
			if spec.get("physics", {}).get("mode", "dynamic") != "static" or F.value(spec, "editor.locked", false) or spec["shape"].get("primitive", "") != "rectangle": continue
			var size: Array = spec["shape"]["size"]
			match str(F.value(spec, "editor.boundary_role", spec["id"])):
				"floor": size[0] = a[2]; spec["transform"]["position"] = [a[0] + a[2] / 2, a[1] + a[3] - size[1] / 2]
				"wall_left": size[1] = a[3]; spec["transform"]["position"] = [a[0] + size[0] / 2, a[1] + a[3] / 2]
				"wall_right": size[1] = a[3]; spec["transform"]["position"] = [a[0] + a[2] - size[0] / 2, a[1] + a[3] / 2]
		updates["objects"] = objects
		send.call("scene.patch", {"changes": updates}))
	tools.tooltip_text = "同步只更新未锁定的标准 floor / wall_left / wall_right 矩形，保留其它障碍"
	F.button(tools, "返回镜头视图", func(): send.call("camera.return_view", {}))
