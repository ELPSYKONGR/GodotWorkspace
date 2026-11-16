extends RefCounted
## Mechanism, sound and analytic-effect inspectors emit document patches only.
const F = preload("res://src/ui/form_helpers.gd")


# Edit rule parameters together with the world's collision-related settings.
static func mechanisms(parent: Node, doc: Dictionary, send: Callable, pending: RefCounted = null) -> void:
	parent.tooltip_text = "真实接触触发；成功分裂后原球移除。容量或出生空间不足时保留原球，原因见调试日志。"
	var rules: Array = doc.get("mechanisms", []).duplicate(true)
	var split: Dictionary = {"id": "split_ball", "type": "split_on_contact", "enabled": true, "conditions": {}, "params": {}}
	var hit: Dictionary = {"id": "split_hitstop", "type": "hit_stop_on_event", "enabled": false, "params": {}}
	for rule in rules:
		if rule.get("type", "") == "split_on_contact": split = rule
		elif rule.get("type", "") == "hit_stop_on_event": hit = rule
	var active := F.check(parent, "启用分裂规则", bool(split.get("enabled", true)))
	var children := F.number(parent, "每次子球总数", float(F.value(split, "params.children_total", 2)), 2, 100, 1)
	var children_can_split := F.check(parent, "子球继续分裂", bool(F.value(split, "params.children_can_split", true)))
	children_can_split.tooltip_text = "关闭后仅初始球分裂；开启后沿后代继续，仍受容量与空间限制"
	var targets: Array = F.value(split, "conditions.other_tags_any", ["ball", "boundary"])
	var walls := F.check(parent, "撞地面/墙壁触发", "boundary" in targets)
	var balls := F.check(parent, "撞其他球触发", "ball" in targets)
	var feedback := F.section(parent, "分裂顿帧", false)
	var hold := F.check(feedback, "启用分裂顿帧", bool(hit.get("enabled", false)))
	hold.tooltip_text = "每次分裂短暂停住物理运动；需要连续流畅运动时关闭"
	var seconds := F.number(feedback, "停顿时间 / s", float(F.value(hit, "params.seconds", 0.06)), 0, 0.5, 0.01)
	var limits := F.section(parent, "容量与保护", false)
	var protection := F.number(limits, "新生保护 / s", float(F.value(split, "conditions.newborn_guard_seconds", 0.08)), 0, 2, 0.01)
	var speed := F.number(limits, "最低碰撞速度", float(F.value(split, "conditions.minimum_collision_speed", 0)), 0, 100000, 0.1)
	speed.tooltip_text = "0 关闭阈值；二维 px/s，三维 m/s。相对速度近似值，不是冲量"
	var maximum := F.number(limits, "动态物体上限", float(F.value(doc, "world.max_dynamic_bodies", 48)), 2, 256, 1)
	var rule_changes := func() -> Dictionary:
		for field in [children, protection, speed, seconds]: field.apply()
		var updated: Array = rules.duplicate(true)
		var s: Dictionary = split.duplicate(true)
		s["enabled"] = active.button_pressed
		if not s.has("conditions"): s["conditions"] = {}
		if not s.has("params"): s["params"] = {}
		s["conditions"]["newborn_guard_seconds"] = protection.value
		if speed.value > 0 or s["conditions"].has("minimum_collision_speed"): s["conditions"]["minimum_collision_speed"] = speed.value
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
		return {"mechanisms": updated}
	var world_changes := func() -> Dictionary:
		maximum.apply()
		return {"world.max_dynamic_bodies": int(maximum.value)}
	F.button(parent, "应用机制", func():
		var changes: Dictionary = rule_changes.call()
		changes.merge(world_changes.call())
		send.call("scene.patch", {"changes": changes}))
	if pending != null:
		pending.register("mechanism_rules", [active, children, children_can_split, protection, speed, walls, balls, hold, seconds], func(): send.call("scene.patch", {"changes": rule_changes.call()}))
		pending.register("mechanism_world", [maximum], func(): send.call("scene.patch", {"changes": world_changes.call()}))


# Configure the shared real-time and offline short-sound presets.
static func audio(parent: Node, doc: Dictionary, send: Callable, pending: RefCounted = null) -> void:
	var data: Dictionary = F.value(doc, "presentation.audio", {})
	var enabled := F.check(parent, "启用碰撞音效", bool(data.get("enabled", true)))
	var preset := F.choice(parent, "音色", ["wood", "bell", "click"], str(data.get("preset", "wood")))
	var wav_path := F.line(parent, "自定义音频", str(data.get("wav_path", "")))
	wav_path.placeholder_text = "留空使用上方合成音"
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.wav ; PCM WAV音频"])
	dialog.current_dir = ProjectSettings.globalize_path("res://")
	dialog.file_selected.connect(func(path: String): wav_path.text = path)
	parent.add_child(dialog)
	F.button(parent, "选择 WAV", func(): dialog.popup_centered_ratio(0.65))
	var volume := F.number(parent, "音量（dB）", float(data.get("volume_db", -12)), -60, 0, 1)
	var pitch := F.number(parent, "音高倍率", float(data.get("pitch", 1)), 0.25, 4, 0.05)
	var advanced := F.section(parent, "混音与限流", false)
	var interval := F.number(advanced, "最短间隔 / s", float(data.get("min_interval", 0.035)), 0, 1, 0.005)
	var voices := F.number(advanced, "最大声部", float(data.get("max_voices", 16)), 1, 32, 1)
	var apply := func():
		for field in [volume, pitch, interval, voices]: field.apply()
		send.call("scene.patch", {"changes": {"presentation.audio": {"enabled": enabled.button_pressed, "preset": F.selected(preset), "wav_path": wav_path.text.strip_edges(), "volume_db": volume.value, "pitch": pitch.value, "min_interval": interval.value, "max_voices": int(voices.value), "sample_rate": 48000}}})
	F.button(parent, "应用音效", apply)
	if pending != null: pending.register("audio", [enabled, preset, wav_path, volume, pitch, interval, voices], apply)
	F.button(parent, "试听", func(): send.call("audio.audition", {})).tooltip_text = "试听已应用的音色"


# Expose analytic particle, flash, ring and trail settings.
static func effects(parent: Node, doc: Dictionary, send: Callable, pending: RefCounted = null) -> void:
	parent.tooltip_text = "开关立即生效；数值点击应用。三维场景的特效为画面叠加，不参与物理"
	var data: Dictionary = F.value(doc, "presentation.effects", {})
	var enabled := F.check(parent, "特效总开关", bool(data.get("enabled", true)))
	var trail := F.check(parent, "拖影", bool(data.get("trail_enabled", true)))
	var ring := F.check(parent, "撞击光圈", bool(data.get("ring", true)))
	var impact_flash := F.check(parent, "撞击闪光", bool(data.get("impact_flash", false)))
	var impact_particles := F.check(parent, "碰撞粒子", bool(data.get("impact_particles", false)))
	var particles := F.check(parent, "分裂粒子", bool(data.get("particles_enabled", true)))
	var flash := F.check(parent, "分裂闪光", bool(data.get("flash", true)))
	var parameters := F.section(parent, "粒子与拖尾参数", false)
	var count := F.number(parameters, "单次粒子数", float(data.get("count", 12)), 0, 64, 1)
	var lifetime := F.number(parameters, "寿命 / s", float(data.get("lifetime", 0.35)), 0.05, 3, 0.05)
	var speed := F.number(parameters, "扩散速度 / px/s", float(data.get("speed", 140)), 10, 800, 10)
	var trail_seconds := F.number(parameters, "拖尾长度 / s", float(data.get("trail_seconds", 0.2)), 0.03, 2, 0.01)
	var clock := F.choice(parameters, "时间依据", ["simulation", "presentation"], str(data.get("time_domain", "simulation")))
	for entry in [[enabled, "enabled"], [particles, "particles_enabled"], [impact_particles, "impact_particles"], [impact_flash, "impact_flash"], [trail, "trail_enabled"], [ring, "ring"], [flash, "flash"]]:
		var field: String = entry[1]
		(entry[0] as CheckBox).toggled.connect(func(value: bool): send.call("scene.patch", {"changes": {"presentation.effects." + field: value}}))
	var apply := func():
		for field in [count, lifetime, speed, trail_seconds]: field.apply()
		var updated := data.duplicate(true)
		updated.merge({"enabled": enabled.button_pressed, "particles_enabled": particles.button_pressed, "impact_particles": impact_particles.button_pressed, "impact_flash": impact_flash.button_pressed, "count": int(count.value), "lifetime": lifetime.value, "speed": speed.value, "trail_enabled": trail.button_pressed, "trail_seconds": trail_seconds.value, "ring": ring.button_pressed, "flash": flash.button_pressed, "time_domain": F.selected(clock)}, true)
		send.call("scene.patch", {"changes": {"presentation.effects": updated}})
	F.button(parent, "应用粒子与拖尾", apply)
	if pending != null: pending.register("effects", [enabled, particles, impact_particles, impact_flash, trail, ring, flash, count, lifetime, speed, trail_seconds, clock], apply)
