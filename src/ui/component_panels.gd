extends RefCounted
## Mechanism, sound and analytic-effect inspectors emit document patches only.
const F = preload("res://src/ui/form_helpers.gd")


# Edit rule parameters together with the world's collision-related settings.
static func mechanisms(parent: Node, doc: Dictionary, send: Callable) -> void:
	F.text(parent, "真实接触驱动规则。分裂移除原球，数量表示子球总数。容量或出生空间不足时在调试页显示拒绝原因。")
	var rules: Array = doc.get("mechanisms", []).duplicate(true)
	var split: Dictionary = {"id": "split_ball", "type": "split_on_contact", "enabled": true, "conditions": {}, "params": {}}
	var hit: Dictionary = {"id": "split_hitstop", "type": "hit_stop_on_event", "enabled": true, "params": {}}
	for rule in rules:
		if rule.get("type", "") == "split_on_contact": split = rule
		elif rule.get("type", "") == "hit_stop_on_event": hit = rule
	var active := F.check(parent, "启用分裂规则", bool(split.get("enabled", true)))
	var children := F.number(parent, "子球总数（2～100）", float(F.value(split, "params.children_total", 2)), 2, 100, 1)
	F.text(parent, "子球总数必须连同其它活动物体一起容纳在上限内。例如1→100至少需要100个容量，还需足够出生空间；不足时保留原球并显示原因。")
	var children_can_split := F.check(parent, "子球继续分裂", bool(F.value(split, "params.children_can_split", true)))
	F.text(parent, "关闭后仅初始球可分裂；开启后子球可继续分裂，仍受数量上限和出生空间保护限制。")
	var protection := F.number(parent, "新生保护（秒）", float(F.value(split, "conditions.newborn_guard_seconds", 0.08)), 0, 2, 0.01)
	var maximum := F.number(parent, "最大动态物体数", float(F.value(doc, "world.max_dynamic_bodies", 48)), 2, 256, 1)
	var targets: Array = F.value(split, "conditions.other_tags_any", ["ball", "boundary"])
	var walls := F.check(parent, "撞地面/墙壁触发", "boundary" in targets)
	var balls := F.check(parent, "撞其他球触发", "ball" in targets)
	var hold := F.check(parent, "启用分裂顿帧", bool(hit.get("enabled", true)))
	var seconds := F.number(parent, "顿帧（秒）", float(F.value(hit, "params.seconds", 0.06)), 0, 0.5, 0.01)
	var hz := F.number(parent, "物理频率（Hz）", float(F.value(doc, "world.physics_hz", 120)), 60, 480, 30)
	var gravity: Array = F.value(doc, "world.gravity", [0, 450])
	var is_3d: bool = F.value(doc, "world.dimension", "2d") == "3d"
	var g := F.number(parent, "重力Y（2D向下为正）", float(gravity[1]), -2000, 2000, 0.1)
	F.button(parent, "应用机制并重新模拟", func():
		for field in [children, protection, maximum, seconds, hz, g]: field.apply()
		var updated: Array = rules.duplicate(true)
		var s: Dictionary = split.duplicate(true)
		s["enabled"] = active.button_pressed
		if not s.has("conditions"): s["conditions"] = {}
		if not s.has("params"): s["params"] = {}
		s["conditions"]["newborn_guard_seconds"] = protection.value
		var tags: Array = []
		if walls.button_pressed: tags.append("boundary")
		if balls.button_pressed: tags.append("ball")
		s["conditions"]["other_tags_any"] = tags
		s["params"]["children_total"] = int(children.value)
		s["params"]["children_can_split"] = children_can_split.button_pressed
		var h: Dictionary = hit.duplicate(true)
		h["enabled"] = hold.button_pressed
		h["params"] = {"seconds": seconds.value, "same_batch_policy": "maximum"}
		updated = updated.filter(func(rule): return rule.get("type", "") not in ["split_on_contact", "hit_stop_on_event"])
		updated.append(s)
		updated.append(h)
		send.call("scene.patch", {"changes": {"mechanisms": updated, "world.max_dynamic_bodies": int(maximum.value), "world.physics_hz": int(hz.value), "world.gravity": [0, g.value, 0] if is_3d else [0, g.value]}})
	)


# Configure the shared real-time and offline short-sound presets.
static func audio(parent: Node, doc: Dictionary, send: Callable) -> void:
	F.text(parent, "预览与离线混音使用相同程序化短音预设。限流只影响听觉，不丢弃物理事件。")
	var data: Dictionary = F.value(doc, "presentation.audio", {})
	var enabled := F.check(parent, "启用碰撞音效", bool(data.get("enabled", true)))
	var preset := F.choice(parent, "音色", ["wood", "bell", "click"], str(data.get("preset", "wood")))
	var wav_path := F.line(parent, "本地PCM WAV", str(data.get("wav_path", "")))
	wav_path.placeholder_text = "留空使用上方合成音"
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.wav ; PCM WAV音频"])
	dialog.current_dir = ProjectSettings.globalize_path("res://")
	dialog.file_selected.connect(func(path: String): wav_path.text = path)
	parent.add_child(dialog)
	F.button(parent, "浏览本地WAV文件", func(): dialog.popup_centered_ratio(0.65))
	var volume := F.number(parent, "音量（dB）", float(data.get("volume_db", -12)), -60, 0, 1)
	var pitch := F.number(parent, "音高倍率", float(data.get("pitch", 1)), 0.25, 4, 0.05)
	var interval := F.number(parent, "最短间隔（秒）", float(data.get("min_interval", 0.035)), 0, 1, 0.005)
	var voices := F.number(parent, "最大声部", float(data.get("max_voices", 16)), 1, 32, 1)
	F.button(parent, "应用音效", func(): send.call("scene.patch", {"changes": {"presentation.audio": {"enabled": enabled.button_pressed, "preset": F.selected(preset), "wav_path": wav_path.text.strip_edges(), "volume_db": volume.value, "pitch": pitch.value, "min_interval": interval.value, "max_voices": int(voices.value), "sample_rate": 48000}}}))
	F.button(parent, "试听当前已应用音色", func(): send.call("audio.audition", {}))


# Expose analytic particle, flash, ring and trail settings.
static func effects(parent: Node, doc: Dictionary, send: Callable) -> void:
	F.text(parent, "短效按事件种子与年龄重建，可往返寻帧。三维场景使用投影到画面的屏幕特效，不额外参与物理。")
	var data: Dictionary = F.value(doc, "presentation.effects", {})
	var enabled := F.check(parent, "特效总开关", bool(data.get("enabled", true)))
	var trail := F.check(parent, "拖影", bool(data.get("trail_enabled", true)))
	var ring := F.check(parent, "撞击光圈", bool(data.get("ring", true)))
	var impact_flash := F.check(parent, "撞击闪光", bool(data.get("impact_flash", false)))
	var impact_particles := F.check(parent, "碰撞粒子", bool(data.get("impact_particles", false)))
	var particles := F.check(parent, "分裂粒子", bool(data.get("particles_enabled", true)))
	var flash := F.check(parent, "分裂闪光", bool(data.get("flash", true)))
	var count := F.number(parent, "单次粒子数", float(data.get("count", 12)), 0, 64, 1)
	var lifetime := F.number(parent, "寿命（秒）", float(data.get("lifetime", 0.35)), 0.05, 3, 0.05)
	var speed := F.number(parent, "扩散速度（px/s）", float(data.get("speed", 140)), 10, 800, 10)
	var trail_seconds := F.number(parent, "拖尾长度（秒）", float(data.get("trail_seconds", 0.2)), 0.03, 2, 0.01)
	var clock := F.choice(parent, "特效时间域", ["simulation", "presentation"], str(data.get("time_domain", "simulation")))
	F.text(parent, "开关点击即生效；数值修改后点击下方应用。总开关关闭时保留各项选择。碰撞粒子会合并同一对物体的抖动接触，并限制同时喷溅数量。")
	for entry in [[enabled, "enabled"], [particles, "particles_enabled"], [impact_particles, "impact_particles"], [impact_flash, "impact_flash"], [trail, "trail_enabled"], [ring, "ring"], [flash, "flash"]]:
		var field: String = entry[1]
		(entry[0] as CheckBox).toggled.connect(func(value: bool): send.call("scene.patch", {"changes": {"presentation.effects." + field: value}}))
	F.button(parent, "应用粒子与拖尾", func():
		for field in [count, lifetime, speed, trail_seconds]: field.apply()
		var updated := data.duplicate(true)
		updated.merge({"enabled": enabled.button_pressed, "particles_enabled": particles.button_pressed, "impact_particles": impact_particles.button_pressed, "impact_flash": impact_flash.button_pressed, "count": int(count.value), "lifetime": lifetime.value, "speed": speed.value, "trail_enabled": trail.button_pressed, "trail_seconds": trail_seconds.value, "ring": ring.button_pressed, "flash": flash.button_pressed, "time_domain": F.selected(clock)}, true)
		send.call("scene.patch", {"changes": {"presentation.effects": updated}}))
