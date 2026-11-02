extends Node3D
## Sparse original one-shots. Three reserved voices never steal gameplay audio.
## No per-resident players, speech, footsteps, or continuous ambience loops.
const AUDIO_DIR := "res://assets/audio/"
const MAX_VOICES := 3
const BIRD_RANGE := 42.0
const COURT_RANGE := 28.0
const UPDATE_INTERVAL := 0.5

var level: Node3D
var voices: Array[AudioStreamPlayer3D] = []
var _streams: Dictionary = {}
var _green_anchors: Array[Vector3] = []
var _rng := RandomNumberGenerator.new()
var _accum := 0.0
var _air_wait := 11.0
var _bird_wait := 7.0
var _court_wait := 0.0
var _focused := true
var _blocked := true
var played: Dictionary = {"air": 0, "bird": 0, "court_bounce": 0}
var dropped_far := 0

static func ensure(owner_level: Node3D) -> Node3D:
	var existing := owner_level.get_node_or_null("NeighborhoodAudio") as Node3D
	if existing != null:
		return existing
	var helper: Node3D = load("res://scripts/city/city_neighborhood_audio.gd").new()
	helper.name = "NeighborhoodAudio"
	owner_level.add_child(helper)
	helper.setup(owner_level)
	return helper

func setup(owner_level: Node3D) -> void:
	level = owner_level
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not voices.is_empty():
		return
	_rng.seed = 11012026
	for stem in ["air", "bird_1", "bird_2", "court_bounce"]:
		var path: String = AUDIO_DIR + "neighborhood_" + str(stem) + ".wav"
		if ResourceLoader.exists(path):
			_streams[stem] = load(path) as AudioStream
	for index in MAX_VOICES:
		var voice := AudioStreamPlayer3D.new()
		voice.name = "NeighborhoodVoice_%d" % index
		voice.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
		voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
		voice.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		voice.max_db = -12.0
		add_child(voice)
		voices.append(voice)
	# Small, fixed anchors from authored greens. Never scan NPCs or vegetation.
	var data: Dictionary = level.get("level_data")
	for park in data.get("parks", []):
		var polygon: Array = park.get("polygon", [])
		for index in range(0, polygon.size(), maxi(1, ceili(polygon.size() / 4.0))):
			var p: Array = polygon[index]
			if p.size() == 3 and _green_anchors.size() < 128:
				_green_anchors.append(Vector3(float(p[0]), float(p[1]) + 4.0, float(p[2])))

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		_focused = false
		_stop_all()
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN]:
		_focused = true

func _suspended() -> bool:
	return not _focused or not is_instance_valid(level) or get_tree().paused or level.get("paused") == true or level.get("ready_to_play") != true

func _audible() -> bool:
	for bus_name in [&"Master", &"SFX"]:
		var index := AudioServer.get_bus_index(bus_name)
		if index >= 0 and (AudioServer.is_bus_mute(index) or AudioServer.get_bus_volume_db(index) <= -70.0):
			return false
	return true

func _process(delta: float) -> void:
	var suspended := _suspended() or not _audible()
	if suspended:
		if not _blocked:
			_stop_all()
		_blocked = true
		_accum = 0.0
		return
	_blocked = false
	_court_wait = maxf(0.0, _court_wait - delta)
	_accum += delta
	if _accum < UPDATE_INTERVAL:
		return
	var elapsed := _accum
	_accum = 0.0
	var daytime := _daytime()
	if not daytime and voices.size() > 1:
		voices[1].stop()
	_air_wait -= elapsed
	_bird_wait -= elapsed
	if _air_wait <= 0.0:
		_air_wait = _rng.randf_range(32.0, 56.0)
		var angle := _rng.randf_range(-PI, PI)
		var at := _listener_position() + Vector3(cos(angle) * 25.0, 7.0, sin(angle) * 25.0)
		_play(0, "air", at, 100.0, -20.0 if daytime else -26.0, 28.0, "air")
	if _bird_wait <= 0.0:
		_bird_wait = _rng.randf_range(19.0, 38.0)
		if daytime:
			var anchor := _nearby_green()
			if anchor.is_finite():
				_play(1, "bird_%d" % _rng.randi_range(1, 2), anchor, BIRD_RANGE, -14.0, 12.0, "bird")

func _daytime() -> bool:
	var clock: Node = level.get("world_time") if is_instance_valid(level) else null
	if clock == null:
		return true
	var minute: float = float(clock.get("minute_of_day"))
	return minute >= 360.0 and minute < 1200.0

func _listener_position() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		return camera.global_position
	var player: Node3D = level.get("player") if is_instance_valid(level) else null
	return player.global_position if is_instance_valid(player) else global_position

func _nearby_green() -> Vector3:
	var listener := _listener_position()
	var selected := Vector3.INF
	var candidates := 0
	# Reservoir sampling keeps calls among real nearby greens, without always
	# repeating from the closest tree or creating a candidate array each tick.
	for anchor in _green_anchors:
		if listener.distance_squared_to(anchor) < BIRD_RANGE * BIRD_RANGE:
			candidates += 1
			if _rng.randi_range(1, candidates) == 1:
				selected = anchor
	return selected

## Call only for a real world action; no scheduled spectator/porch noises.
func play_activity(kind: String, at: Vector3, strength := 1.0) -> bool:
	if kind != "court_bounce" or _court_wait > 0.0:
		return false
	if not is_finite(strength):
		return false
	var db := -12.0 + linear_to_db(clampf(strength, 0.25, 1.0))
	if _play(2, "court_bounce", at, COURT_RANGE, db, 5.0, kind):
		_court_wait = 0.18
		return true
	return false

func _play(index: int, stem: String, at: Vector3, range_m: float, db: float, near_m: float, tag: String) -> bool:
	if _suspended() or not _audible() or not at.is_finite() or index >= voices.size():
		return false
	if at.distance_squared_to(_listener_position()) > range_m * range_m:
		dropped_far += 1
		return false
	var stream: AudioStream = _streams.get(stem)
	var voice := voices[index]
	if stream == null or voice.playing:
		return false
	voice.stream = stream
	voice.global_position = at
	voice.volume_db = db
	# Small natural variation without new samples, added voices or longer tails.
	voice.pitch_scale = _rng.randf_range(0.96, 1.04) if tag != "air" else 1.0
	voice.unit_size = near_m
	voice.max_distance = range_m
	voice.play()
	_blocked = false
	played[tag] = int(played.get(tag, 0)) + 1
	return true

func _stop_all() -> void:
	for voice in voices:
		if is_instance_valid(voice):
			voice.stop()

func get_status() -> Dictionary:
	var playing := 0
	for voice in voices:
		playing += int(voice.playing)
	return {"max_voices": MAX_VOICES, "voices": voices.size(), "playing": playing,
		"cached_streams": _streams.size(), "green_anchors": _green_anchors.size(),
		"played": played.duplicate(), "dropped_far": dropped_far,
		"suspended": _suspended(), "daytime": _daytime()}

func _exit_tree() -> void:
	_stop_all()
	for voice in voices:
		voice.stream = null
	_streams.clear()
