extends RefCounted
## Long-world and camera controls; bounds are navigation data, real walls remain explicit objects.
const F = preload("res://src/ui/form_helpers.gd")

## Reuse the normal command/draft path for both loaded scenes and newly drawn scenes.
static func build(parent: Node, doc: Dictionary, send: Callable, pending: RefCounted, selected: String) -> void:
	if doc["world"]["dimension"] != "2d":
		F.text(parent, "纵向跟随、世界缩略图和轮廓绘制用于二维场景。正交三维/透视三维镜头仍在渲染页设置；逐物体材质和特效支持三维。")
		return
	F.text(parent, "世界可以长于画幅。范围用于镜头/编辑导航，不产生隐形地板；原有地面需要移动、删除或同步到新边界。")
	var area: Array = doc["world"].get("bounds_2d", [0, 0, 720, 1280])
	var bounds: Array = []
	for i in 4: bounds.append(F.number(parent, ["世界起点 X", "世界起点 Y", "世界宽度", "世界高度"][i], float(area[i]), 1 if i > 1 else -100000, 100000, 1))
	var camera: Dictionary = F.value(doc, "presentation.render.camera", {})
	var mode := F.choice(parent, "二维镜头模式", ["fixed", "follow_y"], str(camera.get("mode", "fixed")))
	var target := F.line(parent, "跟随根物体 ID", str(camera.get("target_root", selected)))
	var lineage := F.check(parent, "原球分裂后继续跟随存活子孙（选择最低者）", camera.get("on_split", "lowest_descendant") == "lowest_descendant")
	var down := F.check(parent, "镜头只向下移动", bool(camera.get("only_down", true)))
	var limit := F.check(parent, "镜头限制在世界范围内", bool(camera.get("limit_world", true)))
	var framing := F.number(parent, "目标构图位置 / 高度比例", float(camera.get("framing_y", 0.42)), 0, 1, 0.01)
	var top := F.number(parent, "死区上边 / 高度比例", float(camera.get("dead_zone_top", 0.32)), 0, 1, 0.01)
	var bottom := F.number(parent, "死区下边 / 高度比例", float(camera.get("dead_zone_bottom", 0.58)), 0, 1, 0.01)
	var smoothing := F.number(parent, "平滑时间 / 秒（0为立即）", float(camera.get("smooth_seconds", 0.18)), 0, 10, 0.01)
	var position: Array = camera.get("position_2d", [0, 0])
	var x := F.number(parent, "固定镜头左侧 X", float(position[0]), -100000, 100000, 1)
	var y := F.number(parent, "固定镜头顶部 Y", float(position[1]), -100000, 100000, 1)
	var controls: Array = bounds + [mode, target, lineage, down, limit, framing, top, bottom, smoothing, x, y]
	var changes := func() -> Dictionary:
		for field in controls:
			if field is SpinBox: field.apply()
		var updated := camera.duplicate(true)
		updated.merge({"mode": F.selected(mode), "target_root": target.text, "on_split": "lowest_descendant" if lineage.button_pressed else "stop", "only_down": down.button_pressed, "limit_world": limit.button_pressed, "framing_y": framing.value, "dead_zone_top": top.value, "dead_zone_bottom": bottom.value, "smooth_seconds": smoothing.value, "position_2d": [x.value, y.value]}, true)
		return {"world.bounds_2d": [bounds[0].value, bounds[1].value, bounds[2].value, bounds[3].value], "presentation.render.camera": updated}
	var apply := func(): send.call("scene.patch", {"changes": changes.call()})
	F.button(parent, "应用世界与镜头", apply)
	pending.register("world_camera", controls, apply)
	F.button(parent, "同步标准地面/侧墙到新世界边界", func():
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
	F.text(parent, "同步仅更新未锁定的标准floor / wall_left / wall_right矩形，保留其它障碍。镜头死区内保持不动，超出后向构图位置平滑；全部后代消失时保持最后镜头。")
	F.button(parent, "返回镜头视图", func(): send.call("camera.return_view", {}))
