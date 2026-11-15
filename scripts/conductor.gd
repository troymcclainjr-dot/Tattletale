extends Node
## The beat clock (main.gd's `_conductor`). It plays one beat, an instrumental
## loop made in code by beats_make.py (assets/beats/<id>.json is its sheet, the
## audio is beside it), and says where in it the music is. Everything that moves
## to the music reads it; only the booth, the video take and the music: steps
## tell it what to play.
##
##   play(id, from_bar := 0)      a beat from the top, or from a bar of its loop (a section's start)
##   stop(fade_beats := 1.0)      fade out over that many beats and stop
##   playing, id, sheet, bpm, bars, swing, spb (seconds a beat)
##   time      seconds of song since the loop's first bar, counting on across loops
##   beat      beats since the loop began (time / spb), a float
##   bar       whole bars since the loop began; loop_bar is the bar within the loop
##   step      the sixteenth within the bar, 0 .. 16, a float, with the beat's swing
##   time_of(bar, step) -> float  when that bar and step sound, in `time`'s seconds
##   beat_hit(n), bar_hit(n)      as each beat and each bar is heard
##   voice     rap_voice.gd, the gibberish voice, which sounds on this clock
##   beats(), sheet_of(id), name_of(id)    the beats there are, in assets/beats/index.json's order
##
## Where `time` comes from. Live: from the beat's own audio, never from adding
## up frame times. It is the beat's playback position, plus the time since the
## mixer last ran, less the output latency and the 64 frames every sound is held
## back by in the mixer (AudioServer's lookahead); it never goes backwards. The
## position is counted in the mixer's own frames since the beat began (a capture
## on the Music bus counts every frame made), because the player's reported
## position only moves in its resampler's blocks (128 frames of the file, 2.9 ms),
## too coarse to start a syllable on the beat's very sample. In a scripted picture run (`stepped`, set by
## scripted()) it moves on 1/60 s a frame instead, as combat.gd's time does
## there, so the same steps give the same pictures and the same video take. The
## audio still plays then, silenced (Master is muted in picture runs), so the
## music: steps can switch to live and measure it or record it.
##
## Swing: the off-beat sixteenths start late, at 1 + swing / 2 of the way into
## their pair (0 straight, 0.67 a triplet feel, 1 dotted). beats_make.py puts
## its notes down by the same rule.

signal beat_hit(n: int)
signal bar_hit(n: int)

const RapVoice := preload("res://scripts/rap_voice.gd")
const DIR := "res://assets/beats/"
const LOOKAHEAD := 64.0           # frames: AudioServer holds every sound back by this much
const FALLBACK_BPM := 92.0        # paper_actor.gd's BEAT, while nothing plays
const VOICE_DB := -4.0            # the voice's bus against the music's: about 5 LU under the beat, clear in its own band
const HEADROOM := 3.0             # dB both buses sit under the MUSIC setting: a beat (-1.5 dBTP) and a line over it stay under 0 dBTP

var playing := false
var id := ""
var sheet := {}
var bpm := FALLBACK_BPM
var bars := 4
var swing := 0.0
var spb := 60.0 / FALLBACK_BPM
var time := 0.0
var beat := 0.0
var bar := 0
var loop_bar := 0
var step := 0.0
var started_at := 0.0             # `time` when play() began (a section's start)
var stepped := false              # 1/60 s a frame (picture runs) instead of the audio
var heard := false                # live: the music has reached the speakers
var volume := 0.8                 # the MUSIC setting, 0 .. 1
var voice: Node
var at_usec := 0                  # Time.get_ticks_usec() when `time` was last worked out (the music: steps measure with it)

var _player: AudioStreamPlayer
var _counter: AudioEffectCapture  # on the Music bus: counts every frame the mixer makes
var _f0 := 0                      # the count when the beat began: its first frame is the next one made
var _sheets := {}
var _streams := {}
var _order: Array = []
var _loop := 1.0                  # seconds the loop lasts on the grid
var _last_beat := -1
var _fade_from := -1.0            # the time a fade-out began, or -1
var _fade_len := 0.0


func _ready() -> void:
	process_priority = -10        # before the scripts that read it each frame
	bus("Music")
	bus("Voice")
	_player = AudioStreamPlayer.new()
	_player.name = "Beat"
	_player.bus = "Music"
	add_child(_player)
	_counter = AudioEffectCapture.new()
	_counter.buffer_length = 0.05      # never read: only its counts are
	AudioServer.add_bus_effect(bus("Music"), _counter)
	voice = RapVoice.new()
	voice.name = "Voice"
	voice.clock = self
	add_child(voice)
	set_volume(volume)


## The index of the bus of that name, made (sending to Master) if there is none.
static func bus(bus_name: String) -> int:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_send(i, "Master")
	return i


## A picture run: the clock steps 1/60 s a frame and nothing is heard (Master
## is muted; effects on the buses still get the sound, to measure or record).
func scripted() -> void:
	stepped = true
	AudioServer.set_bus_mute(0, true)


## The MUSIC setting, 0 .. 1: the music and the voice, as the square of it (so
## even steps sound even).
func set_volume(level: float) -> void:
	volume = clampf(level, 0.0, 1.0)
	var db := 40.0 * log(maxf(volume, 0.0001)) / log(10.0) - HEADROOM
	AudioServer.set_bus_volume_db(bus("Music"), db)
	AudioServer.set_bus_volume_db(bus("Voice"), db + VOICE_DB)
	AudioServer.set_bus_mute(bus("Music"), volume < 0.01)
	AudioServer.set_bus_mute(bus("Voice"), volume < 0.01)


# ------------------------------------------------------------------ the beats

## The beats there are, by id, in the order to offer them.
func beats() -> Array:
	if _order.is_empty():
		var data: Variant = _json(DIR + "index.json")
		if data is Dictionary:
			_order = Array((data as Dictionary).get("beats", []))
		if _order.is_empty():
			for file: String in DirAccess.get_files_at(DIR):
				if file.ends_with(".json") and file != "index.json":
					_order.append(file.get_basename())
	return _order


func sheet_of(beat_id: String) -> Dictionary:
	if not _sheets.has(beat_id):
		var data: Variant = _json(DIR + beat_id + ".json")
		_sheets[beat_id] = data if data is Dictionary else {}
	return _sheets[beat_id]


## Its name, for people: "IRON BLOCK".
func name_of(beat_id: String) -> String:
	return String(sheet_of(beat_id).get("name", beat_id.to_upper()))


## The bar a section of it starts on ("verse", "hook"), or 0.
func section_bar(section: String) -> int:
	for s: Dictionary in sheet.get("sections", []):
		if String(s.get("name", "")) == section:
			return int(s.get("bar", 0))
	return 0


static func _json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _stream_of(beat_id: String) -> AudioStreamWAV:
	if not _streams.has(beat_id):
		var path := DIR + String(sheet_of(beat_id).get("file", beat_id + ".wav"))
		var stream: AudioStreamWAV = load(path) as AudioStreamWAV if ResourceLoader.exists(path) else null
		if stream:           # the whole file loops, its last frame too (the importer's loop end of -1 leaves that one out)
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
		_streams[beat_id] = stream
	return _streams[beat_id]


# ------------------------------------------------------------- play and stop

## Play a beat from the top, or from a bar of its loop. False if there is no such beat.
func play(beat_id: String, from_bar := 0) -> bool:
	var s := sheet_of(beat_id)
	var stream := _stream_of(beat_id)
	if s.is_empty() or stream == null:
		push_warning("No beat called %s" % beat_id)
		return false
	voice.stop()
	id = beat_id
	sheet = s
	bpm = float(s.get("bpm", FALLBACK_BPM))
	bars = maxi(int(s.get("bars", 4)), 1)
	swing = clampf(float(s.get("swing", 0.0)), 0.0, 1.0)
	spb = 60.0 / bpm
	_loop = bars * 4.0 * spb
	started_at = posmod(from_bar, bars) * 4.0 * spb
	time = started_at
	_fade_from = -1.0
	heard = stepped
	_player.stream = stream
	_player.volume_db = 0.0
	AudioServer.lock()                # it starts on the next chunk the mixer makes: count from there
	_player.play(started_at)
	_f0 = _made()
	AudioServer.unlock()
	playing = true
	_derive()
	_last_beat = floori(beat + 0.000001) - 1
	if heard:
		_emit()
	return true


## Fade out over that many beats (0: at once) and stop.
func stop(fade_beats := 1.0) -> void:
	if not playing:
		return
	if fade_beats <= 0.0:
		_end()
	elif _fade_from < 0.0:
		_fade_from = time
		_fade_len = fade_beats * spb


func _end() -> void:
	_player.stop()
	playing = false
	_fade_from = -1.0
	voice.stop()


# ----------------------------------------------------------------- the clock

func _process(_delta: float) -> void:
	if not playing:
		return
	if stepped:
		time += 1.0 / 60.0
	else:
		var t := audio_time()
		if not heard and t >= started_at:
			heard = true
		if t > time:
			time = t
	at_usec = Time.get_ticks_usec()
	_derive()
	if heard:
		_emit()
	if _fade_from >= 0.0:
		var k := clampf((time - _fade_from) / maxf(_fade_len, 0.001), 0.0, 1.0)
		_player.volume_db = linear_to_db(maxf(1.0 - k, 0.0001))
		if k >= 1.0:
			_end()


## The song time being heard now, from the audio: the beat's position (in the
## mixer's frames since it began), plus the time since the mixer last ran, less
## the output latency and the mixer's lookahead.
func audio_time() -> float:
	AudioServer.lock()
	var made := _made()
	var since := AudioServer.get_time_since_last_mix()
	AudioServer.unlock()
	var rate := AudioServer.get_mix_rate()
	return started_at + (made - _f0 - LOOKAHEAD) / rate + since - AudioServer.get_output_latency()


## The song time the mixer will start its next chunk at. Call it between
## AudioServer.lock() and unlock(), when the mixer is between two chunks: a
## sound started then begins on that chunk's first sample, as the beat does.
func next_mix_time() -> float:
	return started_at + (_made() - _f0) / AudioServer.get_mix_rate()


## Frames the mixer has made since the game began (under AudioServer.lock()).
func _made() -> int:
	return _counter.get_pushed_frames() + _counter.get_discarded_frames()


func _derive() -> void:
	beat = time / spb
	bar = floori(beat / 4.0)
	loop_bar = posmod(bar, bars)
	step = _swung(fposmod(beat, 4.0) * 4.0)


func _emit() -> void:
	var b := floori(beat + 0.000001)
	if b - _last_beat > 8:          # after a long stall, only the latest
		_last_beat = b - 1
	while _last_beat < b:
		_last_beat += 1
		beat_hit.emit(_last_beat)
		if posmod(_last_beat, 4) == 0:
			bar_hit.emit(floori(_last_beat / 4.0))


## The sixteenth within the bar for a straight position u (0 .. 16 sixteenths).
func _swung(u: float) -> float:
	var pair := floorf(u / 2.0)
	var r := u - 2.0 * pair
	var odd := 1.0 + 0.5 * swing
	if r < odd:
		return 2.0 * pair + r / odd
	return 2.0 * pair + 1.0 + (r - odd) / (2.0 - odd)


## When (bar, step) sounds, in `time`'s seconds: the bar counted from the
## loop's first, the step the sixteenth within it (a fraction runs on evenly
## through that sixteenth).
func time_of(at_bar: float, at_step: float) -> float:
	var s := at_bar * 16.0 + at_step
	var whole := floorf(s)
	return lerpf(_straight(whole), _straight(whole + 1.0), s - whole) * spb / 4.0


## Where sixteenth n (from the loop's start) begins, in straight sixteenths.
func _straight(n: float) -> float:
	var pair := floorf(n / 2.0)
	return 2.0 * pair + (n - 2.0 * pair) * (1.0 + 0.5 * swing)


# ----------------------------------------------------------- for the booth

## The booth's seconds: since the beat began, or `fallback` while none plays.
func clock(fallback: float) -> float:
	return time - started_at if playing else fallback


## Keep him dancing on this beat: paper_actor.gd counts beats itself in walk();
## this sets its count so that after the walk it is this clock's.
func lead(actor: Node3D, delta: float, on: bool) -> void:
	if on and playing:
		actor._beat = beat - delta / actor.BEAT


## At the booth microphone: the beat asked for (or the last one played, or the
## first there is) from the top; off, it fades out.
func booth(on: bool, beat_id := "") -> void:
	if not on:
		stop(1.0)
		return
	var want := beat_id if beat_id != "" else id
	if want == "" and not beats().is_empty():
		want = String(beats()[0])
	if want != "":
		play(want, 0)


## A key at the booth: Left or Right plays the beat before or after this one,
## from the top. True if it was one of those.
func key(code: int) -> bool:
	if code != KEY_LEFT and code != KEY_RIGHT:
		return false
	var all := beats()
	if all.is_empty():
		return true
	play(String(all[posmod(all.find(id) + (1 if code == KEY_RIGHT else -1), all.size())]), 0)
	return true
