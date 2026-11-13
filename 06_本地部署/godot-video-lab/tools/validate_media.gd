extends SceneTree
## Validate replay lifecycle, backward seek, hold clocks, reproducible effects and audio.

var results: Dictionary = {}


## Start asynchronous checks after the test scene tree is ready.
func _initialize() -> void:
	Engine.max_fps = 60
	_run.call_deferred()


## Construct a split fixture independent of the live physics implementation.
func _run() -> void:
	var doc := {"presentation": {"audio": {"preset": "wood", "volume_db": -12, "min_interval": 0.035},
		"effects": {"enabled": true, "count": 12, "lifetime": 0.35, "time_domain": "simulation"}}}
	var store = load("res://src/takes/take_store.gd").new()
	store.begin(doc)
	var definitions := {"parent": {"shape": {"primitive": "circle", "radius": 18}},
		"child_A": {"shape": {"primitive": "circle", "radius": 18}}, "child_B": {"shape": {"primitive": "circle", "radius": 18}}}
	store.append(0.0, 0.0, [_pose("parent", 100)], definitions)
	store.append(0.1, 0.1, [_pose("parent", 120)], definitions)
	store.append(0.2, 0.2, [_pose("child_A", 110), _pose("child_B", 140)], definitions)
	store.append(0.2, 0.2, [_pose("child_A", 111), _pose("child_B", 141)], definitions)
	store.append(0.3, 0.2, [_pose("child_A", 111), _pose("child_B", 141)], definitions)
	var contact := {"type": "contact", "id": "parent", "other_id": "floor", "phase": "enter", "event_id": "contact_1", "time": 0.0, "sim_time": 0.0, "position": [120, 110]}
	var split := {"type": "split", "event_id": "split_1", "parent": "parent", "children": ["child_A", "child_B"], "time": 0.2, "sim_time": 0.2, "position": [120, 110], "seed": 123}
	store.add_event(contact)
	store.add_event(split)
	results["same_time_replaces_frame"] = store.get_data()["frames"].size() == 4
	results["parent_before_split"] = store.sample(0.19)["states"][0]["id"] == "parent"
	results["children_at_split"] = store.sample(0.2)["states"].size() == 2 and store.sample(0.2)["states"][0]["id"] == "child_A"
	var forward: Dictionary = store.sample(0.25)
	store.sample(0.05)
	results["backward_seek_stable"] = JSON.stringify(forward) == JSON.stringify(store.sample(0.25))
	results["hold_physics_clock"] = is_equal_approx(float(store.sample(0.3)["sim_time"]), 0.2)
	var take_path := "res://outputs/media_test.take.json"
	results["save_ok"] = store.save(take_path) == OK
	var restored = load("res://src/takes/take_store.gd").new()
	results["load_ok"] = restored.load_take(take_path) == OK
	var restored_states: Array = restored.sample(0.25)["states"]
	results["restore_lifecycle"] = restored_states.size() == 2 and restored_states[0]["id"] == "child_A" and is_equal_approx(float(restored_states[0]["position"][0]), 111.0) and restored_states[1]["id"] == "child_B"
	var bad: Dictionary = store.get_data().duplicate(true)
	bad["definitions"].erase("child_B")
	var bad_file := FileAccess.open("res://outputs/media_invalid.take.json", FileAccess.WRITE)
	bad_file.store_string(JSON.stringify(bad))
	bad_file.close()
	results["invalid_reference_rejected"] = restored.load_take("res://outputs/media_invalid.take.json") == ERR_INVALID_DATA
	var fx = load("res://src/presentation/effects.gd").new()
	root.add_child(fx)
	fx.configure(doc)
	fx.set_take(store.get_data())
	fx.set_timeline(store.get_data()["events"])
	var projector := func(position: Array) -> Vector2: return Vector2(position[0], position[1])
	fx.present(0.25, 0.25, projector, forward["states"], definitions)
	var particle_signature := JSON.stringify(fx.particles)
	fx.present(0.1, 0.1, projector, store.sample(0.1)["states"], definitions)
	fx.present(0.25, 0.25, projector, forward["states"], definitions)
	results["particles_seek_reproducible"] = particle_signature == JSON.stringify(fx.particles) and fx.particles.size() == 12
	fx.present(0.3, 0.25, projector, forward["states"], definitions)
	results["particles_hold_with_sim_clock"] = particle_signature == JSON.stringify(fx.particles)
	var audio = load("res://src/presentation/audio.gd").new()
	root.add_child(audio)
	audio.configure(doc)
	audio.consume(contact)
	audio.consume(contact)
	var later: Dictionary = contact.duplicate(true)
	later["event_id"] = "contact_2"
	later["time"] = 0.04
	audio.consume(later)
	results["audio_zero_time_and_dedup"] = audio.get_report()["played"] == 2 and audio.get_report()["skipped"] == 1
	var wave_reference: Dictionary = {}
	for preset in ["wood", "bell", "click"]:
		var values: Array = []
		for sample in [0, 1, 48, 200, 1000]: values.append(audio._wave(float(sample) / 48000, preset, 1.0))
		wave_reference[preset] = values
	audio.stop_all()
	results["stop_clears_voices"] = audio.get_report()["voices"] == 0
	var asset_path := "res://outputs/media_import_source.wav"
	_write_wav_fixture(asset_path)
	var asset_doc: Dictionary = doc.duplicate(true)
	asset_doc["presentation"]["audio"]["wav_path"] = asset_path
	asset_doc["presentation"]["audio"]["pitch"] = 2.0
	audio.configure(asset_doc)
	results["wav_asset_loaded"] = audio.last_error.is_empty() and audio.imported_clip != null and audio.get_report()["wav"].get("sample_rate", 0) == 22050
	audio.audition()
	results["wav_asset_playback_pitch"] = audio.get_report()["played"] == 3 and is_equal_approx(audio.voices[-1].pitch_scale, 2.0) and is_equal_approx(audio.imported_clip.get_length(), 0.12)
	audio.stop_all()
	var damaged := FileAccess.get_file_as_bytes(asset_path)
	damaged.encode_u16(20, 3)
	var float_file := FileAccess.open("res://outputs/media_unsupported_float.wav", FileAccess.WRITE)
	float_file.store_buffer(damaged)
	float_file.close()
	asset_doc["presentation"]["audio"]["wav_path"] = "res://outputs/media_unsupported_float.wav"
	audio.configure(asset_doc)
	audio.audition()
	results["unsupported_wav_no_fallback"] = not audio.last_error.is_empty() and audio.imported_clip == null and audio.get_report()["played"] == 3
	var formats_ok := true
	for width in [1, 2, 3, 4]:
		for channels in [1, 2]:
			var pcm_path := "res://outputs/media_pcm_%d_%d.wav" % [width * 8, channels]
			_write_pcm_fixture(pcm_path, width, channels)
			asset_doc["presentation"]["audio"]["wav_path"] = pcm_path
			audio.configure(asset_doc)
			formats_ok = formats_ok and audio.last_error.is_empty() and audio.imported_clip != null
	results["all_pcm_widths_and_channels_loaded"] = formats_ok
	var long_path := "res://outputs/media_long_mute.wav"
	_write_wav_fixture(long_path, 2.0)
	asset_doc["presentation"]["audio"].merge({"wav_path": long_path, "pitch": 1.0, "enabled": true}, true)
	audio.configure(asset_doc)
	audio.audition()
	var active_voice: AudioStreamPlayer = audio.voices[-1]
	await create_timer(0.08).timeout
	var was_playing := active_voice.playing
	asset_doc["presentation"]["audio"]["enabled"] = false
	audio.configure(asset_doc)
	results["disable_stops_existing_long_wav"] = was_playing and not active_voice.playing and audio.voices.is_empty() and audio.get_report()["voices"] == 0
	var scene: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/workbench_2d.json"))
	scene["presentation"]["audio"].merge({"wav_path": long_path, "pitch": 1.0, "enabled": true}, true)
	var session = load("res://src/runtime/scene_session.gd").new()
	root.add_child(session)
	session.load_document(scene)
	var seek_failed: bool = not session.seek(0) and not session.last_error.is_empty()
	session.load_document(scene)
	results["document_load_clears_old_runtime_error"] = seek_failed and session.last_error.is_empty()
	seek_failed = not session.seek(0) and not session.last_error.is_empty()
	session.take.begin(scene)
	var states: Array = session.stage.world.capture_state()
	var scene_definitions: Dictionary = session.stage.world.get_definitions()
	session.take.append(0, 0, states, scene_definitions)
	session.take.append(2, 2, states, scene_definitions)
	session.take.add_event({"type": "contact", "id": "ball_A", "other_id": "floor", "phase": "enter", "time": 0.01, "strength": 1.0})
	results["successful_seek_clears_old_runtime_error"] = seek_failed and session.seek(0) and session.last_error.is_empty()
	session.play()
	await create_timer(0.08).timeout
	var replay_voice: AudioStreamPlayer = session.audio.voices[-1] if not session.audio.voices.is_empty() else null
	var replay_was_playing := is_instance_valid(replay_voice) and replay_voice.playing
	session.pause()
	results["replay_pause_stops_existing_long_wav"] = replay_was_playing and not replay_voice.playing and session.audio.voices.is_empty() and session.audio.get_report()["voices"] == 0 and not session.replay_playing
	session.queue_free()
	audio.queue_free()
	fx.queue_free()
	await process_frame
	# The audio thread releases playback resources in real time, even with --fixed-fps.
	var release_deadline := Time.get_ticks_msec() + 300
	while Time.get_ticks_msec() < release_deadline:
		await process_frame
	var passed := true
	for value in results.values(): passed = passed and bool(value)
	var report := {"passed": passed, "checks": results, "wave_reference": wave_reference}
	var file := FileAccess.open("res://outputs/media_components_validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("MEDIA_COMPONENTS " + JSON.stringify(report))
	quit(0 if passed else 1)


## Keep every fixture pose compatible with both the recorder and world adapters.
func _pose(id: String, x: float) -> Dictionary:
	return {"id": id, "position": [x, 110.0], "rotation": 0.0, "velocity": [0.0, 0.0], "color": "#22c55e", "generation": 0}


## Generate an actual 22050 Hz mono PCM asset for both preview and offline tests.
func _write_wav_fixture(path: String, duration: float = 0.12) -> void:
	var samples := int(round(duration * 22050.0))
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	for index in samples:
		bytes.encode_s16(index * 2, int(sin(TAU * 500 * index / 22050.0) * 0.4 * 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	wav.stereo = false
	wav.data = bytes
	wav.save_to_wav(ProjectSettings.globalize_path(path))


## Cover all advertised integer sample widths and preserve different stereo channels.
func _write_pcm_fixture(path: String, width: int, channels: int) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	var count := 2646 * width * channels
	file.store_buffer("RIFF".to_ascii_buffer())
	file.store_32(36 + count)
	file.store_buffer("WAVEfmt ".to_ascii_buffer())
	file.store_32(16)
	file.store_16(1)
	file.store_16(channels)
	file.store_32(22050)
	file.store_32(22050 * width * channels)
	file.store_16(width * channels)
	file.store_16(width * 8)
	file.store_buffer("data".to_ascii_buffer())
	file.store_32(count)
	for index in 2646:
		for channel in channels:
			var value := sin(TAU * (500 + channel * 250) * index / 22050.0) * 0.4
			if width == 1:
				file.store_8(int(value * 127) + 128)
			else:
				var sample := int(value * (pow(2, width * 8 - 1) - 1))
				for byte_index in width:
					file.store_8((sample >> (8 * byte_index)) & 255)
