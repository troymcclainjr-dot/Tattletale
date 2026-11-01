extends Node3D
## One bounded pool per neighborhood. World events use distance/panning; UI and
## direct player feedback retain their existing local players. No footsteps.
const MAX_VOICES := 12
const HORN_PATH := "res://assets/audio/sfx_honk.wav"
var level: Node3D
var voices: Array[AudioStreamPlayer3D] = []
var _serials: Array[int] = []
var _serial := 0
var _paused := false
var played := 0
var reused := 0
var dropped_far := 0
var dropped_paused := 0
var event_counts: Dictionary = {}
var last_event: Dictionary = {}
var _horn: AudioStream

static func ensure(owner_level: Node3D) -> Node3D:
	var existing := owner_level.get_node_or_null("CityWorldAudio") as Node3D
	if existing != null:
		return existing
	var pool: Node3D = load("res://scripts/city/city_world_audio.gd").new()
	pool.name = "CityWorldAudio"
	owner_level.add_child(pool)
	pool.setup(owner_level)
	return pool

func setup(owner_level: Node3D) -> void:
	level = owner_level
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not voices.is_empty():
		return
	for index in MAX_VOICES:
		var voice := AudioStreamPlayer3D.new()
		voice.name = "WorldVoice_%02d" % index
		voice.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
		voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
		voice.max_db = 0.0
		voice.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(voice)
		voices.append(voice)
		_serials.append(0)

func _process(_delta: float) -> void:
	sync_pause()

func sync_pause() -> void:
	var paused: bool = get_tree().paused or (is_instance_valid(level) and level.get("paused") == true)
	if paused == _paused and not paused:
		return
	# 3D play() starts on the next audio/physics update. Reapply the pause
	# bit so a just-scheduled voice cannot begin after a menu was opened.
	_paused = paused
	for voice in voices:
		voice.stream_paused = paused

func _listener_position() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		return camera.global_position
	var explorer: Node3D = level.get("player") if is_instance_valid(level) else null
	return explorer.global_position if is_instance_valid(explorer) else global_position

func play_world(stream: AudioStream, at: Vector3, range_m := 65.0, volume := -7.0, near_m := 5.0, tag := "world") -> int:
	if stream == null or not at.is_finite() or voices.is_empty():
		return -1
	sync_pause()
	if _paused:
		dropped_paused += 1
		return -1
	range_m = clampf(range_m, 1.0, 150.0)
	if at.distance_squared_to(_listener_position()) > range_m * range_m:
		dropped_far += 1
		return -1
	var selected := -1
	var oldest := 0
	for index in voices.size():
		if not voices[index].playing:
			selected = index
			break
		if _serials[index] < _serials[oldest]:
			oldest = index
	if selected < 0:
		selected = oldest
		reused += 1
	var voice := voices[selected]
	voice.stop()
	voice.stream = stream
	voice.global_position = at
	voice.max_distance = range_m
	voice.unit_size = clampf(near_m, 1.0, 15.0)
	voice.volume_db = clampf(volume, -40.0, 0.0)
	voice.pitch_scale = 1.0
	voice.stream_paused = false
	voice.play()
	_serial += 1
	_serials[selected] = _serial
	played += 1
	event_counts[tag] = int(event_counts.get(tag,0)) + 1
	last_event = {"tag": tag, "position": at, "voice": selected, "range_m": range_m, "serial": _serial}
	return selected

func honk(at: Vector3) -> int:
	if _horn == null and ResourceLoader.exists(HORN_PATH):
		_horn = load(HORN_PATH) as AudioStream
	return play_world(_horn, at, 65.0, -6.0, 8.0, "horn")

func get_status() -> Dictionary:
	var playing := 0
	for voice in voices:
		playing += int(voice.playing)
	return {"voices": voices.size(), "max_voices": MAX_VOICES, "playing": playing,
		"played": played, "reused": reused, "dropped_far": dropped_far,
		"dropped_paused": dropped_paused, "paused": _paused,
		"events": event_counts.duplicate(), "last_event": last_event.duplicate()}

func _exit_tree() -> void:
	for voice in voices:
		if is_instance_valid(voice):
			voice.stop()
			voice.stream = null
	_horn = null
