extends Node
## The gibberish voice (the conductor's `voice`): a line of a bar card sounded
## as rhythmic, pitched vowel sounds on the beat clock, while the real words are
## on screen. It is not speech and not anyone's voice: each syllable is one of
## beats_make.py's synthesised syllables (assets/beats/voice/, voice.json).
##
##   voice.rap(who, syl, bar, actor := null)   sound a line: each syllable on its step of `bar`
##   voice.stop()                              drop everything still to come
##   voice.busy() -> bool
##   signal sung(who, index, text)             as each syllable's beat point is reached
##
## `syl` is the bar cards' format exactly: [[step, "syllable", stress], ...],
## the step 0 .. 15 (sixteenths of the bar, the beat's swing applied), the
## stress 0 weak, 1 medium, 2 strong. A syllable's sound is picked from its
## text: its vowel (a e i o u, y as i, a few spellings such as "ee" or "ow"
## read as they sound), how it starts (straight into the vowel; a burst for a
## hard consonant; a hiss for s, f, h, z, th; a hum for m, n, l, r, w, v), and
## short or long by the time to the next one. Its pitch is the character's
## register (voice.json "characters": low, mid or high, and semitones off it)
## with the stress on top (a strong syllable higher and louder, a weak one
## lower and softer), falling a little through the line. The actor's mouth
## (paper_face.gd) shows each vowel as it sounds, closed between syllables.
##
## Timing: a syllable starts on the very sample its step falls on. Each file
## opens with PAD seconds of silence. While AudioServer is locked (the mixer
## between two chunks) the beat's position P at the next chunk is read, and the
## syllable is started `at - (T - P) * pitch` into its file (T its step, `at`
## its beat point in the file), so the beat and the syllable leave the same mix
## in step. In a stepped (scripted) run nothing sounds; the mouth still moves
## on the clock.

signal sung(who: String, index: int, text: String)

const DIR := "res://assets/beats/voice/"
const AHEAD := 0.075           # at most this long before its step a syllable is handed to the mixer
const POOL := 8                # players, used in turn
const STRESS_ST := [-0.7, 0.4, 2.0]      # semitones each stress adds
const STRESS_DB := [-3.0, -0.5, 2.0]
const FALL := 1.2              # semitones the pitch falls over a line
const VOWEL_MOUTH := {"a": "mouth_ah", "e": "mouth_ee", "i": "mouth_ee", "o": "mouth_oh", "u": "mouth_oh"}
const SPELLINGS := [["igh", "a"], ["oo", "u"], ["ee", "i"], ["ea", "i"], ["ou", "a"], ["ow", "o"], ["ai", "e"], ["ay", "e"], ["oy", "o"]]

var clock: Node                # conductor.gd
var level_db := 0.0
var keep_journal := false      # the music: steps keep each syllable handed over in `journal`
var journal: Array = []        # {"t", "file", "stream", "pitch", "from", "next_mix", "text", "who"}

var _data := {}
var _streams := {}
var _players: Array = []
var _next := 0
var _lines: Array = []         # {"who", "actor", "syl": [...], "i" (next to hand over), "shown" (last reached), "mouth"}


func _ready() -> void:
	process_priority = -9      # after the conductor
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.name = "Syllable%d" % i
		p.bus = "Voice"
		add_child(p)
		_players.append(p)
	var path := DIR + "voice.json"
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	_data = data if data is Dictionary else {}


## Sound a line, each syllable on its step of bar `at_bar` (in the clock's bars).
func rap(who: String, syl: Array, at_bar: int, actor: Node3D = null) -> void:
	if _data.is_empty() or clock == null or syl.is_empty():
		return
	var chars: Dictionary = _data.get("characters", {})
	var c: Dictionary = chars.get(who, chars.get("default", {"register": "mid", "pitch": 0.0, "gain": 0.0}))
	var samples: Dictionary = _data.get("samples", {})
	var out: Array = []
	var n := syl.size()
	for i in n:
		var entry: Array = syl[i]
		var t: float = clock.time_of(at_bar, float(entry[0]))
		var t_next: float = clock.time_of(at_bar, float(syl[i + 1][0])) if i + 1 < n else t + 2.0 * float(clock.spb)
		var text := String(entry[1])
		var stress := clampi(int(entry[2]), 0, 2)
		var vowel := vowel_of(text)
		var onset := onset_of(text)
		var file := "%s_%s_%s_%s" % [String(c.get("register", "mid")), vowel, onset, "l" if t_next - t >= 0.3 else "s"]
		if not samples.has(file):
			continue
		var sample: Dictionary = samples[file]
		var st := float(c.get("pitch", 0.0)) + float(STRESS_ST[stress]) - FALL * i / maxf(n - 1, 1) + 0.1 * (posmod(text.hash() + 31 * i, 7) - 3)
		var pitch := pow(2.0, st / 12.0)
		var first := text.to_lower().substr(0, 1)
		out.append({"t": t, "text": text, "file": file, "stream": _stream(String(sample["file"])), "at": float(sample["at"]),
			"lead": float(sample["lead"]) / pitch, "pitch": pitch, "db": float(c.get("gain", 0.0)) + float(STRESS_DB[stress]),
			"mouth": VOWEL_MOUTH.get(vowel, "mouth_ah"), "lips": "mouth_small" if first in ["m", "b", "p"] else ("mouth_ff" if first in ["f", "v"] else ""),
			"until": t + 0.8 * minf(t_next - t, float(sample["after"]) / pitch)})
	if not out.is_empty():
		_lines.append({"who": who, "actor": actor, "syl": out, "i": 0, "shown": -1, "mouth": ""})


func busy() -> bool:
	return not _lines.is_empty()


## Drop every line still to come (what is sounding rings out) and let the mouths go.
func stop() -> void:
	for line: Dictionary in _lines:
		_mouth(line, "")
	_lines.clear()


## The vowel a syllable sounds, from its spelling.
static func vowel_of(text: String) -> String:
	var s := text.to_lower()
	for pair: Array in SPELLINGS:
		if s.contains(String(pair[0])):
			return String(pair[1])
	for ch in s:
		if ch in "aeiou":
			return ch
	return "i" if s.contains("y") else "a"


## How a syllable starts: v (straight into the vowel), k (a burst), s (a hiss), m (a hum).
static func onset_of(text: String) -> String:
	var s := text.to_lower().lstrip("'\"-(")
	if s.is_empty() or s[0] in "aeiou":
		return "v"
	if s.begins_with("th") or s[0] in "szfh":
		return "s"
	if s[0] in "mnlrwyv":
		return "m"
	return "k"


func _stream(file: String) -> AudioStream:
	if not _streams.has(file):
		_streams[file] = load(DIR + file)
	return _streams[file]


func _process(_delta: float) -> void:
	if _lines.is_empty():
		return
	if clock == null or not clock.playing:
		stop()
		return
	if not clock.stepped:
		_hand_over()
	_show()


## Start every syllable whose step is about to come, sample-exact against the beat.
func _hand_over() -> void:
	AudioServer.lock()
	var p: float = clock.next_mix_time()
	for line: Dictionary in _lines:
		var syl: Array = line["syl"]
		while int(line["i"]) < syl.size():
			var s: Dictionary = syl[int(line["i"])]
			var ahead: float = float(s["t"]) - p
			if ahead > minf(AHEAD, float(s["at"]) / float(s["pitch"]) - 0.002):
				break
			line["i"] = int(line["i"]) + 1
			var from: float = float(s["at"]) - ahead * float(s["pitch"])
			if from > float(s["at"]) + 0.08:
				continue                # far too late (the game stalled): let it go
			var player: AudioStreamPlayer = _players[_next]
			_next = (_next + 1) % POOL
			player.stream = s["stream"]
			player.pitch_scale = float(s["pitch"])
			player.volume_db = float(s["db"]) + level_db
			player.play(maxf(from, 0.0))
			if keep_journal:
				journal.append({"t": float(s["t"]), "file": String(s["file"]), "stream": s["stream"], "pitch": float(s["pitch"]),
					"from": maxf(from, 0.0), "next_mix": p, "text": String(s["text"]), "who": String(line["who"])})
	AudioServer.unlock()


## The mouths, on the clock: lips for an m, b, p, f or v as it starts, then the
## vowel while it sounds, closed after; and `sung` as each syllable is reached.
func _show() -> void:
	var now: float = clock.time
	for line: Dictionary in _lines.duplicate():
		var syl: Array = line["syl"]
		var k := -1
		for j in syl.size():
			if now >= float(syl[j]["t"]) - float(syl[j]["lead"]) - 0.02:
				k = j
			else:
				break
		var shape := ""
		if k >= 0:
			var s: Dictionary = syl[k]
			if now < float(s["t"]):
				shape = String(s["lips"]) if String(s["lips"]) != "" else String(s["mouth"])
			elif now < float(s["until"]):
				shape = String(s["mouth"])
			else:
				shape = "mouth_small"
			while int(line["shown"]) < k and now >= float(syl[int(line["shown"]) + 1]["t"]):
				line["shown"] = int(line["shown"]) + 1
				sung.emit(String(line["who"]), int(line["shown"]), String(syl[int(line["shown"])]["text"]))
		if k == syl.size() - 1 and now > float(syl[k]["until"]) + 0.15:
			_mouth(line, "")
			_lines.erase(line)
		else:
			_mouth(line, shape)


func _mouth(line: Dictionary, shape: String) -> void:
	var actor: Node3D = line["actor"]
	if actor == null or not is_instance_valid(actor) or actor.face == null or String(line["mouth"]) == shape:
		return
	line["mouth"] = shape
	actor.face.hold_mouth(shape)
