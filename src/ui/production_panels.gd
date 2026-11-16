extends RefCounted
## Rendering, recording and production controls share the command entry point.
const F = preload("res://src/ui/form_helpers.gd")


# Edit presentation-only fields without touching the physical scene data.
static func rendering(parent: Node, doc: Dictionary, send: Callable, pending: RefCounted = null) -> void:
	var text_section := F.section(parent, "文字")
	var captions: Array = F.value(doc, "presentation.captions", [])
	var title: Dictionary = captions[0] if not captions.is_empty() else {"id": "main_title", "position": [44, 54]}
	var subtitle: Dictionary = captions[1] if captions.size() > 1 else {"id": "subtitle", "position": [44, 130]}
	var title_text := F.line(text_section, "标题", str(title.get("text", "碰撞之后，一变二")))
	var subtitle_text := F.line(text_section, "副标题", str(subtitle.get("text", "")))
	var font := F.line(text_section, "字体", str(title.get("font_family", "Microsoft YaHei")))
	var title_size := F.number(text_section, "标题字号", float(title.get("font_size", 44)), 8, 120, 1)
	var subtitle_size := F.number(text_section, "副标题字号", float(subtitle.get("font_size", 23)), 8, 100, 1)
	var text_color := F.color(text_section, "文字颜色", str(title.get("color", "#edf5ff")))
	var data: Dictionary = F.value(doc, "presentation.render", {})
	var background := F.color(parent, "背景颜色", str(data.get("background", "#101827")))
	var neon: Dictionary = data.get("neon", {})
	var neon_section := F.section(parent, "全局荧光", false)
	neon_section.get_parent().visible = doc["world"]["dimension"] == "2d"
	var neon_enabled := F.check(neon_section, "启用二维荧光材质", bool(neon.get("enabled", false)))
	var glow_width := F.number(neon_section, "光晕范围 / px", float(neon.get("glow_width", 18)), 1, 64, 1)
	var glow_strength := F.number(neon_section, "光晕强度", float(neon.get("glow_strength", 0.9)), 0, 2, 0.05)
	var highlight_size := F.number(neon_section, "高光大小", float(neon.get("highlight_size", 0.3)), 0, 1, 0.05)
	var highlight_strength := F.number(neon_section, "高光强度", float(neon.get("highlight_strength", 1.1)), 0, 3, 0.05)
	var apply_neon := func():
		for field in [glow_width, glow_strength, highlight_size, highlight_strength]: field.apply()
		send.call("scene.patch", {"changes": {"presentation.render.neon": {"enabled": neon_enabled.button_pressed, "glow_width": glow_width.value, "glow_strength": glow_strength.value, "highlight_size": highlight_size.value, "highlight_strength": highlight_strength.value}}})
	F.button(neon_section, "应用荧光", apply_neon)
	if pending != null: pending.register("neon", [neon_enabled, glow_width, glow_strength, highlight_size, highlight_strength], apply_neon)
	var pbr := F.section(parent, "三维材质与光照", false)
	pbr.get_parent().visible = doc["world"]["dimension"] == "3d"
	var roughness := F.number(pbr, "粗糙度", float(data.get("roughness", 0.35)), 0, 1, 0.01)
	var metallic := F.number(pbr, "金属度", float(data.get("metallic", 0.15)), 0, 1, 0.01)
	var shadows := F.check(pbr, "阴影", bool(data.get("shadows", true)))
	var light_energy := F.number(pbr, "灯光强度", float(data.get("light_energy", 1.5)), 0, 16, 0.05)
	var camera_section := F.section(parent, "三维相机", false)
	camera_section.get_parent().visible = doc["world"]["dimension"] == "3d"
	var projection := F.choice(camera_section, "投影", ["orthogonal", "perspective"], str(F.value(data, "camera.projection", "orthogonal")))
	var camera_size := F.number(camera_section, "正交范围", float(F.value(data, "camera.size", 23)), 3, 100, 0.5)
	var fov := F.number(camera_section, "透视视角 / °", float(F.value(data, "camera.fov", 46)), 1, 170, 0.1)
	var camera_position: Array = F.value(data, "camera.position", [13, 15, 20])
	var camera_target: Array = F.value(data, "camera.target", [0, 2.3, 0])
	var position_fields: Array[SpinBox] = []
	var target_fields: Array[SpinBox] = []
	for index in 3:
		position_fields.append(F.number(camera_section, "相机位置 " + ["X", "Y", "Z"][index], float(camera_position[index]), -1000, 1000, 0.1))
		target_fields.append(F.number(camera_section, "相机目标 " + ["X", "Y", "Z"][index], float(camera_target[index]), -1000, 1000, 0.1))
	var helpers := F.section(parent, "预览辅助", false)
	var debug := F.check(helpers, "显示碰撞辅助", bool(data.get("debug", false)))
	debug.tooltip_text = "仅预览，不进入导出视频"
	var caption_changes := func() -> Dictionary:
		var updated: Array = captions.duplicate(true)
		var a: Dictionary = title.duplicate(true)
		var b: Dictionary = subtitle.duplicate(true)
		a.merge({"text": title_text.text, "font_family": font.text, "font_size": int(title_size.value), "color": "#" + text_color.color.to_html()}, true)
		b.merge({"text": subtitle_text.text, "font_family": font.text, "font_size": int(subtitle_size.value), "color": "#9cb2cc"}, true)
		if updated.is_empty(): updated.append(a)
		else: updated[0] = a
		if updated.size() < 2: updated.append(b)
		else: updated[1] = b
		return {"presentation.captions": updated}
	var visual_changes := func() -> Dictionary:
		var position: Array = []
		var target: Array = []
		for index in 3:
			position.append(position_fields[index].value)
			target.append(target_fields[index].value)
		return {"presentation.render.background": "#" + background.color.to_html(), "presentation.render.roughness": roughness.value, "presentation.render.metallic": metallic.value, "presentation.render.shadows": shadows.button_pressed, "presentation.render.light_energy": light_energy.value, "presentation.render.camera.projection": F.selected(projection), "presentation.render.camera.size": camera_size.value, "presentation.render.camera.fov": fov.value, "presentation.render.camera.position": position, "presentation.render.camera.target": target, "presentation.render.debug": debug.button_pressed}
	var caption_controls: Array = [title_text, subtitle_text, font, title_size, subtitle_size, text_color]
	var visual_controls: Array = [background, roughness, metallic, shadows, light_energy, projection, camera_size, fov, debug] + position_fields + target_fields
	F.button(parent, "应用画面", func():
		for field in caption_controls + visual_controls:
			if field is SpinBox: field.apply()
		var changes: Dictionary = caption_changes.call()
		changes.merge(visual_changes.call())
		send.call("scene.patch", {"changes": changes}))
	if pending != null:
		pending.register("captions", caption_controls, func(): send.call("scene.patch", {"changes": caption_changes.call()}))
		pending.register("render", visual_controls, func(): send.call("scene.patch", {"changes": visual_changes.call()}))


# Provide explicit take recording, file and seek actions.
static func replay(parent: Node, send: Callable) -> void:
	var path := F.line(parent, "轨迹文件", "res://outputs/takes/latest.json")
	F.button(parent, "加载轨迹", func(): send.call("take.load", {"path": path.text}))
	F.button(parent, "保存当前轨迹", func(): send.call("take.save", {"path": path.text}))
	F.button(parent, "回到轨迹开头", func(): send.call("take.seek", {"time": 0.0}))
	parent.tooltip_text = "底部录制和时间轴用于记录与回放；物理修改后旧轨迹可能过期"


# Create an independent production request with explicit dimensions and backend.
static func production(parent: Node, send: Callable, doc: Dictionary = {}, pending: RefCounted = null) -> void:
	var preset: Dictionary = doc.get("export_preset", {})
	var initial_fps := int(preset.get("fps", 30))
	var size: Array = preset.get("resolution", [720, 1280])
	var fps := F.choice(parent, "输出FPS", ["30", "60"], str(initial_fps))
	var frames := F.number(parent, "输出帧数", float(preset.get("frames", float(preset.get("duration_seconds", 8)) * initial_fps)), 1, 3600, 1)
	var resolution := F.choice(parent, "竖屏尺寸", ["720x1280", "1080x1920"], "%dx%d" % [int(size[0]), int(size[1])])
	var duration := F.text(parent, "")
	var refresh := func(): duration.text = "视频时长  %.2f 秒" % (frames.value / int(F.selected(fps)))
	frames.value_changed.connect(func(_value): refresh.call())
	fps.item_selected.connect(func(_index): refresh.call())
	refresh.call()
	var advanced := F.section(parent, "高级导出", false)
	var name := F.line(advanced, "任务名称", "video_" + str(int(Time.get_unix_time_from_system())))
	var backend := F.choice(advanced, "渲染方式", ["gl_compatibility", "forward_plus"], str(preset.get("backend", "gl_compatibility")))
	backend.tooltip_text = "OpenGL 已验证；Vulkan 需驱动支持。高级后端只影响独立导出"
	if pending != null:
		pending.register("export", [fps, frames, resolution, backend], func():
			var dimensions: PackedStringArray = F.selected(resolution).split("x")
			var updated := preset.duplicate(true)
			updated.merge({"fps": int(F.selected(fps)), "frames": int(frames.value), "resolution": [int(dimensions[0]), int(dimensions[1])], "duration_seconds": frames.value / int(F.selected(fps)), "backend": F.selected(backend)}, true)
			send.call("scene.patch", {"changes": {"export_preset": updated}}))
	var export_button := F.button(parent, "开始导出", func():
		var dimensions: PackedStringArray = F.selected(resolution).split("x")
		send.call("render.enqueue", {"name": name.text, "fps": int(F.selected(fps)), "frames": int(frames.value), "width": int(dimensions[0]), "height": int(dimensions[1]), "backend": F.selected(backend)})
	)
	preload("res://src/ui/workbench_theme.gd").primary(export_button)
	export_button.add_to_group("export_controls")
	var cancel := F.button(parent, "取消导出", func(): send.call("render.cancel", {}))
	cancel.add_to_group("export_controls")
	cancel.set_meta("cancel", true)
	F.button(parent, "打开输出文件夹", func(): send.call("render.open_output", {}))
