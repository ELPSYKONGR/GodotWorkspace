extends RefCounted
## Rendering, recording and production controls share the command entry point.
const F = preload("res://src/ui/form_helpers.gd")


# Edit presentation-only fields without touching the physical scene data.
static func rendering(parent: Node, doc: Dictionary, send: Callable) -> void:
	F.text(parent, "表现参数可复用已有轨迹；保存后立即预览。高级渲染后端在生产页选择。")
	var captions: Array = F.value(doc, "presentation.captions", [])
	var title: Dictionary = captions[0] if not captions.is_empty() else {"id": "main_title", "position": [44, 54]}
	var subtitle: Dictionary = captions[1] if captions.size() > 1 else {"id": "subtitle", "position": [44, 130]}
	var title_text := F.line(parent, "标题", str(title.get("text", "碰撞之后，一变二")))
	var subtitle_text := F.line(parent, "副标题", str(subtitle.get("text", "")))
	var font := F.line(parent, "系统字体", str(title.get("font_family", "Microsoft YaHei")))
	var title_size := F.number(parent, "标题字号", float(title.get("font_size", 44)), 8, 120, 1)
	var subtitle_size := F.number(parent, "副标题字号", float(subtitle.get("font_size", 23)), 8, 100, 1)
	var text_color := F.color(parent, "文字颜色", str(title.get("color", "#edf5ff")))
	var data: Dictionary = F.value(doc, "presentation.render", {})
	var background := F.color(parent, "背景颜色", str(data.get("background", "#101827")))
	var neon: Dictionary = data.get("neon", {})
	F.text(parent, "二维荧光与球面高光：不改变碰撞，可复用轨迹。颜色沿用物体颜色。")
	var neon_enabled := F.check(parent, "启用二维荧光材质", bool(neon.get("enabled", false)))
	var glow_width := F.number(parent, "光晕范围（像素）", float(neon.get("glow_width", 18)), 1, 64, 1)
	var glow_strength := F.number(parent, "光晕强度", float(neon.get("glow_strength", 0.9)), 0, 2, 0.05)
	var highlight_size := F.number(parent, "小球高光大小", float(neon.get("highlight_size", 0.3)), 0, 1, 0.05)
	var highlight_strength := F.number(parent, "小球高光强度", float(neon.get("highlight_strength", 1.1)), 0, 3, 0.05)
	F.button(parent, "应用二维荧光材质", func():
		for field in [glow_width, glow_strength, highlight_size, highlight_strength]: field.apply()
		send.call("scene.patch", {"changes": {"presentation.render.neon": {"enabled": neon_enabled.button_pressed, "glow_width": glow_width.value, "glow_strength": glow_strength.value, "highlight_size": highlight_size.value, "highlight_strength": highlight_strength.value}}}))
	var roughness := F.number(parent, "三维粗糙度", float(data.get("roughness", 0.35)), 0, 1, 0.01)
	var metallic := F.number(parent, "三维金属度", float(data.get("metallic", 0.15)), 0, 1, 0.01)
	var shadows := F.check(parent, "三维阴影", bool(data.get("shadows", true)))
	F.text(parent, "下列光照和相机字段仅影响三维场景，不改变物理轨迹。三维默认Y向上。")
	var light_energy := F.number(parent, "灯光能量", float(data.get("light_energy", 1.5)), 0, 16, 0.05)
	var projection := F.choice(parent, "三维投影", ["orthogonal", "perspective"], str(F.value(data, "camera.projection", "orthogonal")))
	var camera_size := F.number(parent, "正交相机范围", float(F.value(data, "camera.size", 23)), 3, 100, 0.5)
	var fov := F.number(parent, "透视FOV（度）", float(F.value(data, "camera.fov", 46)), 1, 170, 0.1)
	var camera_position: Array = F.value(data, "camera.position", [13, 15, 20])
	var camera_target: Array = F.value(data, "camera.target", [0, 2.3, 0])
	var position_fields: Array[SpinBox] = []
	var target_fields: Array[SpinBox] = []
	for index in 3:
		position_fields.append(F.number(parent, "相机位置 " + ["X", "Y", "Z"][index], float(camera_position[index]), -1000, 1000, 0.1))
		target_fields.append(F.number(parent, "相机目标 " + ["X", "Y", "Z"][index], float(camera_target[index]), -1000, 1000, 0.1))
	var debug := F.check(parent, "调试高亮/碰撞辅助（不导出）", bool(data.get("debug", false)))
	F.button(parent, "应用渲染与文字", func():
		var updated: Array = captions.duplicate(true)
		var a: Dictionary = title.duplicate(true)
		var b: Dictionary = subtitle.duplicate(true)
		a.merge({"text": title_text.text, "font_family": font.text, "font_size": int(title_size.value), "color": "#" + text_color.color.to_html()}, true)
		b.merge({"text": subtitle_text.text, "font_family": font.text, "font_size": int(subtitle_size.value), "color": "#9cb2cc"}, true)
		if updated.is_empty(): updated.append(a)
		else: updated[0] = a
		if updated.size() < 2: updated.append(b)
		else: updated[1] = b
		var position: Array = []
		var target: Array = []
		for index in 3:
			position.append(position_fields[index].value)
			target.append(target_fields[index].value)
		send.call("scene.patch", {"changes": {"presentation.captions": updated, "presentation.render.background": "#" + background.color.to_html(), "presentation.render.roughness": roughness.value, "presentation.render.metallic": metallic.value, "presentation.render.shadows": shadows.button_pressed, "presentation.render.light_energy": light_energy.value, "presentation.render.camera.projection": F.selected(projection), "presentation.render.camera.size": camera_size.value, "presentation.render.camera.fov": fov.value, "presentation.render.camera.position": position, "presentation.render.camera.target": target, "presentation.render.debug": debug.button_pressed}})
	)


# Provide explicit take recording, file and seek actions.
static func replay(parent: Node, send: Callable) -> void:
	F.text(parent, "先录制，再拖动下方时间轴。回放只恢复记录，不再次求解或触发分裂。拖动寻帧默认静音。")
	var path := F.line(parent, "轨迹文件", "res://outputs/takes/latest.json")
	F.button(parent, "从初始场景开始录制", func(): send.call("take.record", {}))
	F.button(parent, "停止录制并保存", func(): send.call("take.stop", {"path": path.text}))
	F.button(parent, "加载轨迹", func(): send.call("take.load", {"path": path.text}))
	F.button(parent, "保存当前轨迹", func(): send.call("take.save", {"path": path.text}))
	F.button(parent, "回到轨迹开头", func(): send.call("take.seek", {"time": 0.0}))
	F.text(parent, "时间轴下方显示成片时间与模拟时间。顿帧期间两者不同；物理参数变化后旧轨迹会标记为过期。成片逐帧默认30fps，提交生产任务后使用该任务FPS。")


# Create an independent production request with explicit dimensions and backend.
static func production(parent: Node, send: Callable) -> void:
	F.text(parent, "从已录制的轨迹生产干净画面＋离线混音。独立任务不会改变当前预览。名称不可与已有任务重复。")
	var name := F.line(parent, "任务名称", "video_" + str(int(Time.get_unix_time_from_system())))
	var fps := F.choice(parent, "输出FPS", ["30", "60"], "30")
	var frames := F.number(parent, "输出帧数", 240, 1, 3600, 1)
	var resolution := F.choice(parent, "竖屏尺寸", ["720x1280", "1080x1920"], "720x1280")
	var backend := F.choice(parent, "渲染后端", ["gl_compatibility", "forward_plus"], "gl_compatibility")
	F.text(parent, "gl_compatibility为已验证的OpenGL；forward_plus使用Vulkan，需显卡与驱动支持。帧数÷FPS为输出时长，不能超出轨迹。")
	F.button(parent, "提交视频生产任务", func():
		var dimensions: PackedStringArray = F.selected(resolution).split("x")
		send.call("render.enqueue", {"name": name.text, "fps": int(F.selected(fps)), "frames": int(frames.value), "width": int(dimensions[0]), "height": int(dimensions[1]), "backend": F.selected(backend)})
	)
	F.button(parent, "取消当前生产任务", func(): send.call("render.cancel", {}))
	F.button(parent, "打开输出文件夹", func(): send.call("render.open_output", {}))
