extends Node
const WorldAudio := preload("res://scripts/city/city_world_audio.gd")
const Ambience := preload("res://scripts/city/city_neighborhood_audio.gd")

class Arena extends Node3D:
	var paused := false
	var ready_to_play := true
	var player: Node3D
	var world_time: Node
	var level_data := {"parks": [{"polygon": [[0, 0, 6], [4, 0, 6], [4, 0, 10]]}]}

var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
	print(("PASS " if ok else "FAIL ") + message)

func _run() -> void:
	G.built = false
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	var arena := Arena.new()
	add_child(arena)
	arena.player = Node3D.new()
	arena.add_child(arena.player)
	var pool = WorldAudio.ensure(arena)
	pool.set_process(false)
	var ambience = Ambience.ensure(arena)
	ambience.set_process(false)
	var source := Node3D.new()
	arena.add_child(source)
	source.position = Vector3(4, 0, 2)
	check(pool == WorldAudio.ensure(arena) and pool.voices.size() == 12, "world pool remains idempotent and bounded")
	check(pool.honk(Vector3(0, 0, 200)) == -1, "remote traffic does not consume horn cooldown")
	var horn: int = pool.honk(Vector3(2, 1, 0))
	check(horn >= 0 and pool.voices[horn].stream.resource_path.ends_with("vehicle_horn.wav"), "traffic uses shipped layered vehicle horn")
	check(pool.honk(Vector3(3, 1, 0)) == -1, "simultaneous traffic horns are rate limited")
	check(pool.bicycle_contact(Vector3(0, 0, 2)) >= 0, "successful bicycle handling has quiet local feedback")
	check(pool.bicycle_contact(Vector3(0, 0, 2)) == -1, "bicycle contact debounce prevents overlapping handling bursts")
	var siren: int = pool.emergency(source)
	check(siren >= 0 and pool.event_counts.get("emergency", 0) == 1, "real nearby responder receives one siren phrase")
	for i in 80:
		pool.emergency(source)
	check(pool.event_counts.get("emergency", 0) == 1, "response ticks cannot spam repeated sirens")
	source.position.x = 11.0
	pool._process(0.1)
	check(pool.voices[siren].global_position.is_equal_approx(source.global_position + Vector3.UP), "siren follows actual responding vehicle")
	pool.stop_emergency(source)
	check(pool._emergency_voice == -1 and not pool.voices[siren].playing, "arrived responder stops its siren immediately")
	pool._emergency_wait = 0.0
	siren = pool.emergency(source)
	source.position = Vector3(200, 0, 0)
	pool._process(0.1)
	check(not pool.voices[siren].playing and pool._emergency_voice == -1, "moving beyond emergency range releases source tracking")
	source.position = Vector3(2, 0, 0)
	pool._emergency_wait = 0.0
	siren = pool.emergency(source)
	source.free()
	pool._process(0.1)
	check(pool._emergency_voice == -1 and not pool.voices[siren].playing, "deleted responder leaves no orphan siren")
	var replacement_source := Node3D.new()
	arena.add_child(replacement_source)
	pool._stop_all()
	pool._emergency_wait = 0.0
	siren = pool.emergency(replacement_source)
	var tracked_serial: int = pool._emergency_serial
	for i in 24:
		pool.play_world(pool._siren, Vector3(7, 1, 0), 40.0, -20.0, 2.0, "reuse_fixture")
	check(pool._serials[siren] != tracked_serial, "saturated pool reuses the tracked emergency voice")
	var replacement_position: Vector3 = pool.voices[siren].global_position
	replacement_source.position = Vector3(15, 0, 0)
	pool._process(0.1)
	pool.stop_emergency(replacement_source)
	check(pool.voices[siren].global_position.is_equal_approx(replacement_position) and pool.voices[siren].playing, "old emergency ownership cannot move or stop a replacement gameplay voice")
	pool._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	pool._contact_wait = 0.0
	check(pool.bicycle_contact(Vector3.ZERO) == -1 and pool.get_status().playing == 0, "focus loss stops world transients and rejects new events")
	pool._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	check(pool.bicycle_contact(Vector3.ZERO) >= 0, "focus restore accepts fresh interactions")
	await get_tree().physics_frame
	await get_tree().process_frame
	arena.paused = true
	pool.sync_pause()
	check(pool.voices[0].stream_paused and pool.play_world(pool._contact, Vector3.ZERO) == -1, "pause freezes world voices and declines new events")
	arena.paused = false
	pool.sync_pause()
	check(not pool.voices[0].stream_paused, "resume restores world pool")
	for bus_name in [&"Master", &"SFX"]:
		var bus := AudioServer.get_bus_index(bus_name)
		var old_db := AudioServer.get_bus_volume_db(bus)
		AudioServer.set_bus_mute(bus, true)
		pool._process(0.1)
		check(pool.play_world(pool._contact, Vector3.ZERO) == -1 and pool.get_status().playing == 0, str(bus_name) + " mute prevents queued and playing world sounds")
		AudioServer.set_bus_mute(bus, false)
		AudioServer.set_bus_volume_db(bus, -80.0)
		check(pool.play_world(pool._contact, Vector3.ZERO) == -1, str(bus_name) + " zero gain rejects inaudible events")
		AudioServer.set_bus_volume_db(bus, old_db)
	check(ambience.play_activity("court_bounce", Vector3(0, 0, 2), 0.25), "gentle real ball contact is audible nearby")
	var soft_db: float = ambience.voices[2].volume_db
	ambience._stop_all()
	ambience._court_wait = 0.0
	check(ambience.play_activity("court_bounce", Vector3(0, 0, 2), 1.0), "hard real ball contact is accepted after debounce")
	check(ambience.voices[2].volume_db > soft_db + 10.0, "impact strength controls basketball volume")
	check(ambience.voices[2].pitch_scale >= 0.96 and ambience.voices[2].pitch_scale <= 1.04, "basketball timbre variation stays subtle")
	var sfx_bus := AudioServer.get_bus_index(&"SFX")
	AudioServer.set_bus_mute(sfx_bus, true)
	ambience._process(0.5)
	check(ambience.get_status().playing == 0, "mute clears active neighborhood sounds without a resume backlog")
	AudioServer.set_bus_mute(sfx_bus, false)
	var anchors := {}
	for i in 64:
		var anchor: Vector3 = ambience._nearby_green()
		check(ambience._green_anchors.has(anchor), "bird source stays on authored greenery")
		anchors[anchor] = true
	check(anchors.size() > 1, "bird phrases vary across nearby authored greens")
	check(pool.voices.size() == 12 and ambience.voices.size() == 3, "audio polish allocates no extra voice nodes")
	# Spatial play/stop commands cross physics/audio updates. Dispose of the
	# fixture while the tree is still running so pending playback can drain.
	pool._stop_all()
	ambience._stop_all()
	arena.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	print("AUDIO_POLISH_SMOKE failures=%d" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
