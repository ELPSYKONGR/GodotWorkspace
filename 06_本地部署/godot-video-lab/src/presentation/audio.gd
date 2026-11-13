extends Node
## Procedural sound preview; the offline mixer uses the same three synthesis formulas.

var settings: Dictionary = {}
var voices: Array[AudioStreamPlayer] = []
var seen: Dictionary = {}
var last_time := -1000.0
var played := 0
var skipped := 0
var last_error := ""
var imported_clip: AudioStreamWAV
var imported_info: Dictionary = {}
const SAMPLE_RATE := 48000


## Apply sound parameters independently from the physical world.
func configure(doc: Dictionary) -> void:
	settings = doc.get("presentation", {}).get("audio", {}).duplicate(true)
	if not bool(settings.get("enabled", true)):
		stop_all()
	last_error = ""
	imported_clip = null
	imported_info.clear()
	var path := str(settings.get("wav_path", "")).strip_edges()
	if not path.is_empty():
		_load_wav(path)


## Play one sample immediately without consuming a collision event.
func audition() -> void:
	_play(1.0)


## Consume paired contact notifications once and rate-limit only audible voices.
func consume(event: Dictionary) -> void:
	if not bool(settings.get("enabled", true)) or event.get("type", "") not in ["contact", "split"]:
		return
	if event.get("type", "") == "contact" and str(event.get("phase", "enter")) != "enter":
		return
	var time := float(event.get("time", 0))
	var key := _event_key(event)
	if seen.has(key) or time - last_time + 0.000001 < float(settings.get("min_interval", 0.035)):
		skipped += 1
		return
	seen[key] = true
	last_time = time
	_play(clampf(float(event.get("strength", 1.0)), 0.25, 1.4))


## Clear old voices and event cursors when seeking or restarting playback.
func stop_all() -> void:
	for voice in voices:
		if is_instance_valid(voice):
			voice.stop()
			voice.stream = null
			voice.queue_free()
	voices.clear()
	seen.clear()
	last_time = -1000


## Materialize a short stereo PCM stream and keep a bounded number of voices.
func _play(strength: float) -> void:
	if not bool(settings.get("enabled", true)) or not last_error.is_empty():
		return
	# A newly started voice may not report playing until the audio server updates.
	voices = voices.filter(func(voice): return is_instance_valid(voice))
	if voices.size() >= clampi(int(settings.get("max_voices", 16)), 1, 32):
		skipped += 1
		return
	var pitch := clampf(float(settings.get("pitch", 1.0)), 0.25, 4.0)
	var wav: AudioStreamWAV = imported_clip
	if wav == null:
		var preset := str(settings.get("preset", "wood"))
		var duration := 0.24 if preset == "bell" else (0.035 if preset == "click" else 0.09)
		var bytes := PackedByteArray()
		bytes.resize(int(duration * SAMPLE_RATE) * 4)
		for index in int(duration * SAMPLE_RATE):
			var value := clampf(_wave(float(index) / SAMPLE_RATE, preset, pitch) * strength * 0.70710678, -1, 1)
			var sample := int(value * 32767)
			bytes.encode_s16(index * 4, sample)
			bytes.encode_s16(index * 4 + 2, sample)
		wav = AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = SAMPLE_RATE
		wav.stereo = true
		wav.data = bytes
	var voice := AudioStreamPlayer.new()
	voice.stream = wav
	voice.volume_db = clampf(float(settings.get("volume_db", -12)), -60, 0)
	if imported_clip != null:
		voice.pitch_scale = pitch
		voice.volume_db += linear_to_db(strength)
	voice.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(voice)
	voices.append(voice)
	voice.finished.connect(voice.queue_free)
	voice.play()
	played += 1


## Accept integer PCM assets only; never replace a broken asset with a synthetic tone.
func _load_wav(path: String) -> void:
	if not path.is_absolute_path() and not path.begins_with("res://") and not path.begins_with("user://"):
		path = "res://" + path
	if not FileAccess.file_exists(path):
		last_error = "WAV文件不存在：" + path
		return
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 12 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF" or bytes.slice(8, 12).get_string_from_ascii() != "WAVE":
		last_error = "WAV读取失败或非RIFF/WAVE文件：" + path
		return
	var format: Dictionary = {}
	var has_data := false
	var offset := 12
	while offset + 8 <= bytes.size():
		var kind := bytes.slice(offset, offset + 4).get_string_from_ascii()
		var count := int(bytes.decode_u32(offset + 4))
		var start := offset + 8
		if count > bytes.size() - start:
			last_error = "WAV区块长度损坏：" + path
			return
		if kind == "fmt " and count >= 16:
			format = {"encoding": bytes.decode_u16(start), "channels": bytes.decode_u16(start + 2), "sample_rate": bytes.decode_u32(start + 4), "bits": bytes.decode_u16(start + 14)}
		elif kind == "data":
			has_data = count > 0
		offset = start + count + count % 2
	if not has_data or format.get("encoding", 0) != 1 or format.get("channels", 0) not in [1, 2] or format.get("bits", 0) not in [8, 16, 24, 32] or int(format.get("sample_rate", 0)) < 8000 or int(format.get("sample_rate", 0)) > 192000:
		last_error = "仅支持8～192kHz、单/双声道、8/16/24/32-bit整数PCM WAV"
		return
	imported_clip = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(path))
	if imported_clip == null:
		last_error = "Godot无法载入该PCM WAV：" + path
		return
	imported_clip.loop_mode = AudioStreamWAV.LOOP_DISABLED
	imported_info = format
	imported_info["path"] = path
	imported_info["duration"] = imported_clip.get_length()


## Keep these formulas matched to tools/mix_take.py for preview/production parity.
func _wave(time: float, preset: String, pitch: float) -> float:
	var frequency := (1046.5 if preset == "bell" else (1400.0 if preset == "click" else 650.0)) * pitch
	var decay := 18.0 if preset == "bell" else (180.0 if preset == "click" else 55.0)
	var carrier := sin(TAU * frequency * time)
	if preset == "wood": carrier = (carrier + 0.32 * sin(TAU * frequency * 2.73 * time)) / 1.32
	elif preset == "bell": carrier = (carrier + 0.35 * sin(TAU * frequency * 2.01 * time)) / 1.35
	return 0.72 * carrier * exp(-time * decay) * (1 - exp(-time * 1000))


## Contact episodes distinguish genuine later impacts from dual body callbacks.
func _event_key(event: Dictionary) -> String:
	if event.has("contact_episode_id"):
		return str(event["contact_episode_id"])
	if event.get("type", "") == "contact":
		var pair := [str(event.get("id", event.get("body_id", ""))), str(event.get("other_id", ""))]
		pair.sort()
		return "%s:%s:%d" % [pair[0], pair[1], int(float(event.get("time", 0)) * 1000000)]
	return str(event.get("event_id", "split:" + str(event.get("parent", ""))))


## Expose actual preview activity to the debug panel.
func get_report() -> Dictionary:
	var active := 0
	for voice in voices:
		if is_instance_valid(voice) and voice.playing: active += 1
	return {"played": played, "skipped": skipped, "voices": active, "enabled": settings.get("enabled", true), "preset": settings.get("preset", "wood"), "wav": imported_info, "error": last_error}
