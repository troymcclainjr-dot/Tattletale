extends Node
const Ambience := preload("res://scripts/city/city_neighborhood_audio.gd")
const Clock := preload("res://scripts/city/city_world_time.gd")

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
	arena.world_time = Clock.new()
	arena.add_child(arena.world_time)
	var audio = Ambience.ensure(arena)
	audio.set_process(false)
	check(audio == Ambience.ensure(arena), "setup is idempotent")
	check(audio.get_status().voices == 3 and audio.get_status().cached_streams == 4, "bounded pool caches four imported streams")
	check(audio.play_activity("court_bounce", Vector3(0, 0, 2)), "actual nearby bounce is accepted")
	check(not audio.play_activity("court_bounce", Vector3.ZERO), "immediate repeated contact is rate limited")
	audio._stop_all()
	audio._court_wait = 0.0
	check(not audio.play_activity("court_bounce", Vector3(0, 0, 100)), "remote contact is culled before playback")
	check(not audio.play_activity("conversation", Vector3.ZERO), "spectator chatter is not synthesized")
	arena.paused = true
	audio._process(0.5)
	check(not audio.play_activity("court_bounce", Vector3.ZERO), "level pause rejects fresh audio")
	check(audio.get_status().playing == 0, "pause stops transients without a resume backlog")
	arena.paused = false
	get_tree().paused = true
	check(not audio.play_activity("court_bounce", Vector3.ZERO), "tree pause rejects audio")
	get_tree().paused = false
	audio._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not audio.play_activity("court_bounce", Vector3.ZERO), "focus loss rejects audio")
	audio._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	for bus_name in [&"Master", &"SFX"]:
		var index := AudioServer.get_bus_index(bus_name)
		AudioServer.set_bus_mute(index, true)
		check(not audio.play_activity("court_bounce", Vector3.ZERO), str(bus_name) + " mute rejects events")
		AudioServer.set_bus_mute(index, false)
	arena.world_time.set_time(23 * 60)
	audio._bird_wait = 0.0
	audio._air_wait = 100.0
	audio._process(0.5)
	check(audio.played.bird == 0, "night suppresses bird calls")
	arena.world_time.set_time(9 * 60)
	audio._bird_wait = 0.0
	audio._process(0.5)
	check(audio.played.bird == 1, "daytime bird uses an authored nearby green")
	audio._stop_all()
	arena.player.position = Vector3(300, 0, 300)
	audio._bird_wait = 0.0
	audio._process(0.5)
	check(audio.played.bird == 1, "no green nearby means no floating bird calls")
	print("NEIGHBORHOOD_AUDIO_SMOKE failures=%d" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
