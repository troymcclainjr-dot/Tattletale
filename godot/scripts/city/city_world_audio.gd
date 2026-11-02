extends Node3D
## One bounded pool per neighborhood. World events use distance/panning; UI and
## direct player feedback retain their existing local players. No footsteps.
const MAX_VOICES := 12
const HORN_PATH := "res://assets/audio/vehicle_horn.wav"
const SIREN_PATH := "res://assets/audio/sfx_siren.wav"
const CONTACT_PATH := "res://assets/audio/sfx_door.wav"
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
var _siren: AudioStream
var _contact: AudioStream
var _focused := true
var _horn_wait := 0.0
var _emergency_wait := 0.0
var _contact_wait := 0.0
var _emergency_source: WeakRef
var _emergency_voice := -1
var _emergency_serial := -1
var dropped_muted := 0

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

func _process(delta: float) -> void:
	sync_pause()
	if not _focused or not _audible():
		_stop_all()
		return
	if _paused:
		return
	_horn_wait = maxf(0.0, _horn_wait - delta)
	_emergency_wait = maxf(0.0, _emergency_wait - delta)
	_contact_wait = maxf(0.0, _contact_wait - delta)
	if _emergency_voice < 0:
		return
	# Serial ownership prevents a reused gameplay voice from following a cruiser.
	if _serials[_emergency_voice] != _emergency_serial:
		_clear_emergency()
		return
	var source := _emergency_source.get_ref() as Node3D if _emergency_source != null else null
	var voice := voices[_emergency_voice]
	if not is_instance_valid(source) or not source.is_inside_tree():
		voice.stop()
		_clear_emergency()
		return
	if source.global_position.distance_squared_to(_listener_position()) > 70.0 * 70.0:
		voice.stop()
		_clear_emergency()
		return
	voice.global_position = source.global_position + Vector3.UP

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		_focused = false
		_stop_all()
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN]:
		_focused = true

func _audible() -> bool:
	for bus_name in [&"Master", &"SFX"]:
		var index := AudioServer.get_bus_index(bus_name)
		if index >= 0 and (AudioServer.is_bus_mute(index) or AudioServer.get_bus_volume_db(index) <= -70.0):
			return false
	return true

func _clear_emergency() -> void:
	_emergency_source = null
	_emergency_voice = -1
	_emergency_serial = -1

func _stop_all() -> void:
	for voice in voices:
		if is_instance_valid(voice):
			voice.stop()
	_clear_emergency()

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
	if _paused or not _focused:
		dropped_paused += 1
		return -1
	if not _audible():
		dropped_muted += 1
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
	if _horn_wait > 0.0:
		return -1
	if _horn == null and ResourceLoader.exists(HORN_PATH):
		_horn = load(HORN_PATH) as AudioStream
	var index := play_world(_horn, at, 60.0, -10.0, 7.0, "horn")
	if index >= 0:
		_horn_wait = 0.75
	return index

## A soft non-tonal handling sound on a successful mount/dismount, never a pedal timer.
func bicycle_contact(at: Vector3) -> int:
	if _contact_wait > 0.0:
		return -1
	if _contact == null and ResourceLoader.exists(CONTACT_PATH):
		_contact = load(CONTACT_PATH) as AudioStream
	var index := play_world(_contact, at, 14.0, -20.0, 2.5, "bicycle_contact")
	if index >= 0:
		voices[index].pitch_scale = 0.85
		_contact_wait = 0.4
	return index

## Safe to request during a real response tick. One short phrase at most every
## eight seconds across the neighborhood, following the actual responding car.
func emergency(source: Node3D) -> int:
	if _emergency_wait > 0.0 or not is_instance_valid(source) or not source.is_inside_tree():
		return -1
	if _siren == null and ResourceLoader.exists(SIREN_PATH):
		_siren = load(SIREN_PATH) as AudioStream
	var index := play_world(_siren, source.global_position + Vector3.UP, 70.0, -17.0, 9.0, "emergency")
	if index >= 0:
		_emergency_wait = 8.0
		_emergency_source = weakref(source)
		_emergency_voice = index
		_emergency_serial = _serials[index]
	return index

func stop_emergency(source: Node3D) -> void:
	if _emergency_source == null or _emergency_source.get_ref() != source:
		return
	if _emergency_voice >= 0 and _serials[_emergency_voice] == _emergency_serial:
		voices[_emergency_voice].stop()
	_clear_emergency()

func get_status() -> Dictionary:
	var playing := 0
	for voice in voices:
		playing += int(voice.playing)
	return {"voices": voices.size(), "max_voices": MAX_VOICES, "playing": playing,
		"played": played, "reused": reused, "dropped_far": dropped_far,
		"dropped_paused": dropped_paused, "dropped_muted": dropped_muted,
		"paused": _paused, "focused": _focused,
		"events": event_counts.duplicate(), "last_event": last_event.duplicate()}

func _exit_tree() -> void:
	for voice in voices:
		if is_instance_valid(voice):
			voice.stop()
			voice.stream = null
	_horn = null
	_siren = null
	_contact = null
	_clear_emergency()
