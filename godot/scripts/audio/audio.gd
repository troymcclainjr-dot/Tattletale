extends Node
## Audio autoload: the 90 BPM beat and every sound effect (audio.js).
##
## CONTRACT. Gameplay calls only these functions. Keep the signatures.
##
## sfx names: shutter, click, tick, buzz, honk, door, pickup, win, siren, whistle,
## snore (arg = loudness multiplier, default 1), hangup, busy, cuffs, cash, knock, step,
## dtmf (arg = key as a String: "0".."9", "*", "#").
##
## HOW IT WORKS. The sound is not hand-made here: tools/audio/render_audio.py renders audio.js
## offline into assets/audio/ (music.wav is one seamless 4-bar loop, sfx_<name>.wav one file per
## effect, sfx_dtmf_<key>.wav one per key; "*" is star and "#" is hash). This node plays them:
## the loop on a "Music" bus, the effects from a small pool of players on an "SFX" bus. Both buses
## are created here at runtime, so project.godot stays untouched.
##
## LEVELS. audio.js has master .8, music bus .3, sfx bus .7. The WAVs already contain the master
## .8 (and each sound's own peak), so the buses carry the other two, exactly the JS numbers, and the
## final level is what the web game plays. The video is not routed through any of this, like the JS.
## Re-render with `python godot/tools/audio/render_audio.py`, then `godot_run.py --import`.


const AUDIO_DIR := "res://assets/audio/"
const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"
const MUSIC_GAIN := 0.3  # js: musicG.gain.value (0 when music is off)
const SFX_GAIN := 0.7  # js: sfxG.gain.value
const VOICES := 16  # sounds that can overlap before the oldest one is cut off

const SFX_NAMES := ["shutter", "click", "tick", "buzz", "honk", "door", "pickup", "win", "siren",
		"whistle", "snore", "hangup", "busy", "cuffs", "cash", "knock", "step"]
const DTMF_KEYS := {"0": "0", "1": "1", "2": "2", "3": "3", "4": "4", "5": "5", "6": "6", "7": "7",
		"8": "8", "9": "9", "*": "star", "#": "hash"}

var _music: AudioStreamPlayer
var _voices: Array[AudioStreamPlayer] = []
var _voice_serial: Array[int] = []  # which sfx() call each voice last played (higher = newer)
var _serial := 0
var _sfx := {}  # "click" -> AudioStreamWAV, "dtmf_5" -> AudioStreamWAV, ...
var _started := false
var _music_on := true
var _paused := false
var _warned := {}


func _ready() -> void:
	# The tree's pause flag must not touch us: set_paused() is the only thing that pauses the sound.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_bus(MUSIC_BUS, MUSIC_GAIN)
	_make_bus(SFX_BUS, SFX_GAIN)
	AudioServer.set_bus_mute(AudioServer.get_bus_index(MUSIC_BUS), not _music_on)

	var loop := _load_wav("music")
	if loop != null:
		# One WAV = one whole loop: wrap from the last sample to the first.
		loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
		loop.loop_begin = 0
		loop.loop_end = roundi(loop.get_length() * loop.mix_rate)
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	_music.stream = loop
	_music.bus = MUSIC_BUS
	add_child(_music)

	for n in SFX_NAMES:
		_sfx[n] = _load_wav("sfx_" + n)
	for k in DTMF_KEYS:
		_sfx["dtmf_" + k] = _load_wav("sfx_dtmf_" + DTMF_KEYS[k])
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.name = "Voice%d" % i
		p.bus = SFX_BUS
		add_child(p)
		_voices.append(p)
		_voice_serial.append(0)


## Start the music loop (idempotent). The JS calls this on the first Start click.
func start() -> void:
	if _started:
		return
	_started = true
	if _music.stream == null:
		_warn_once("music", "Audio.start(): music.wav is missing or not imported (run tools/audio/render_audio.py, then godot_run.py --import)")
		return
	_music.play()
	_music.stream_paused = _paused


@warning_ignore("shadowed_variable_base_class")
func sfx(name: String, arg = null) -> void:
	var key := name
	var db := 0.0
	if name == "dtmf":
		key = "dtmf_" + _dtmf_key(arg)  # js: an unknown key falls back to "1"
	elif name == "snore":
		var loud := float(arg) if arg != null else 0.0
		db = linear_to_db(loud if loud > 0.0 else 1.0)  # js: L = arg || 1, scales the gain peak
	var stream: AudioStreamWAV = _sfx.get(key)
	if stream == null:
		_warn_once(key, "Audio.sfx(): unknown or missing sound '%s'" % name)
		return
	var i := _pick_voice()
	var p := _voices[i]
	p.stream = stream
	p.volume_db = db
	p.play()
	p.stream_paused = _paused  # a sound asked for during a pause starts when the pause ends
	_serial += 1
	_voice_serial[i] = _serial


## The M key. The beat keeps running while it is off (like the JS), you just can't hear it.
func set_music(on: bool) -> void:
	_music_on = on
	var bus := AudioServer.get_bus_index(MUSIC_BUS)
	if bus != -1:
		AudioServer.set_bus_mute(bus, not on)


## Pause everything (P key / window hidden), resume on false.
func set_paused(on: bool) -> void:
	_paused = on
	_music.stream_paused = on
	for p in _voices:
		p.stream_paused = on


## Stop and drop every stream on quit, so nothing is still playing when the engine frees them.
func _exit_tree() -> void:
	if _music:
		_music.stop()
		_music.stream = null
	for p in _voices:
		p.stop()
		p.stream = null
	_sfx.clear()


func _make_bus(bus_name: StringName, gain: float) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	if i == -1:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_send(i, &"Master")
	AudioServer.set_bus_volume_db(i, linear_to_db(gain))


func _load_wav(stem: String) -> AudioStreamWAV:
	var path := AUDIO_DIR + stem + ".wav"
	if not ResourceLoader.exists(path):
		_warn_once(stem, "Audio: %s is missing (run tools/audio/render_audio.py, then godot_run.py --import)" % path)
		return null
	return load(path) as AudioStreamWAV


## A voice that is not playing (a held one counts as busy); if every voice is busy, the oldest one.
func _pick_voice() -> int:
	var oldest := 0
	for i in _voices.size():
		if not _voices[i].playing and not _voices[i].stream_paused:
			return i
		if _voice_serial[i] < _voice_serial[oldest]:
			oldest = i
	return oldest


func _dtmf_key(arg) -> String:
	var k := str(int(arg)) if (arg is float and arg == floorf(arg)) else str(arg)
	return k if DTMF_KEYS.has(k) else "1"


func _warn_once(key: String, msg: String) -> void:
	if not _warned.has(key):
		_warned[key] = true
		push_warning(msg)
