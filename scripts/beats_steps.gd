extends RefCounted
## The music: --do steps (main.gd hands every step that starts with music: here).
## The beat clock is conductor.gd, the gibberish voice rap_voice.gd.
##
##   music:state                       the mixer (rate, latency, device), the buses, and each beat: its
##                                     tempo, its audio and how that loops
##   music:play:<id>[:<bar>]           play a beat (from that bar of its loop); music:stop fades it out
##   music:live / music:stepped        the clock from the audio, or 1/60 s a frame (a picture run
##                                     starts stepped; music:live before video:shoot puts the take on the audio)
##   music:bars:<n>                    let n bars go by
##   music:rap:<who>:<line>[:<bar>]    a test line (assets/beats/test_lines.json: steady, run, offbeat,
##                                     slow) from that character on the next bar (or that bar), his mouth
##                                     with it if he is here (e is the lead)
##   music:timing:<id>:<bars>[:<line>[:<who>]]
##                                     play the beat live for that many bars, the line (if given) on every
##                                     bar after the first, and print when each beat and each syllable
##                                     sounded against when the clock said, and how late the frame that
##                                     showed each beat was, in ms; then the clock against the wall clock
##   music:timing:take:<seconds>       the music video's take, live, for that long (after music:live and
##                                     video:shoot): when each move prompt reached the ring against when
##                                     the clock said it was due
##   music:probe[:<id>]                the beat player's own reported position against the clock's (why the
##                                     clock counts the mixer's frames: see conductor.gd)
##   music:render:<id>:<bars>[:<line>[:<who>]]
##                                     what a player hears (the Master bus) for that many bars, the line
##                                     on every bar after the first, to render_<id>[_<line>_<who>].wav in
##                                     the art folder's shots/beats (beside the worktree; else beside the shot)
##
## How the sound is measured. The music bus and the voice bus each get a capture
## (AudioEffectCapture, which sees the sound before the bus's volume and mute),
## both emptied while the mixer is held between two chunks, when the beat's
## position P0 is read: frame i of either capture is then song time
## P0 + (i - 64) / rate (64: the mixer's lookahead). Each beat is found in the
## music capture by lining up the beat's own audio (from its file) against it;
## each syllable in the voice capture by lining up its own file, played at its
## pitch from where it was started. What is printed is how far each one is from
## where the clock put it.

const LINES := "res://assets/beats/test_lines.json"
const ART := "artifacts/flat-pivot-20261112/shots/beats"      # under the folder that holds the worktree


static func step(main: Node, bits: PackedStringArray) -> void:
	var c: Node = main._conductor
	var what := bits[1] if bits.size() > 1 else "state"
	match what:
		"state":
			_state(c)
		"play":
			var ok: bool = c.play(bits[2], int(bits[3]) if bits.size() > 3 else 0)
			print("[shot] music: %s" % ("playing %s, %s (%d BPM, %d bars, swing %.2f) from %.3f s, the clock %s" % [c.id, c.name_of(c.id), c.bpm, c.bars,
				c.swing, c.started_at, "stepped" if c.stepped else "from the audio"] if ok else "no beat called %s" % bits[2]))
		"stop":
			c.stop(1.0)
			print("[shot] music: fading out")
		"live":
			c.stepped = false
			print("[shot] music: the clock follows the audio")
		"stepped":
			c.stepped = true
			print("[shot] music: the clock steps 1/60 s a frame")
		"bars":
			await _bars(main, c, float(bits[2]) if bits.size() > 2 else 1.0)
		"rap":
			_rap(main, c, bits)
		"timing":
			if bits.size() > 2 and bits[2] == "take":
				await _take_timing(main, c, float(bits[3]) if bits.size() > 3 else 8.0)
			else:
				await _timing(main, c, bits)
		"render":
			await _render(main, c, bits)
		"probe":
			await _probe(main, c, bits[2] if bits.size() > 2 else "iron")
		_:
			print("[shot] music: no step %s" % what)


## The beat player's own reported position against the clock's (the mixer's
## frame count), live for 45 frames: the steps it moves in, in frames of the
## file, and how far ahead of the count it reads.
static func _probe(main: Node, c: Node, beat_id: String) -> void:
	var was_stepped: bool = c.stepped
	c.stepped = false
	if not c.play(beat_id, 0):
		c.stepped = was_stepped
		return
	var rate: float = c._stream_of(beat_id).mix_rate
	var moves := {}
	var ahead: Array = []
	var last := -1.0
	for i in 45:
		await main.get_tree().process_frame
		AudioServer.lock()
		var raw: float = c._player.get_playback_position()
		var counted: float = c.next_mix_time()
		AudioServer.unlock()
		if raw != last:
			if last >= 0.0:
				var d := roundi((raw - last) * rate)
				moves[d] = int(moves.get(d, 0)) + 1
			last = raw
			ahead.append((raw - counted) * 1000.0)
	c.stop(0.0)
	c.stepped = was_stepped
	print("[shot] music: probe %s: the player's own position moved in steps of %s frames of the file (step: how often); it read ahead of the mixer's count by %s" % [
		beat_id, moves, _stats(ahead)])


static func _state(c: Node) -> void:
	print("[shot] music: mixer %d Hz, output latency %.1f ms (as the driver reports it), device '%s', driver %s; clock %s" % [
		AudioServer.get_mix_rate(), AudioServer.get_output_latency() * 1000.0, AudioServer.get_output_device(),
		String(ProjectSettings.get_setting("audio/driver/driver", "?")), "stepped" if c.stepped else "from the audio"])
	var buses := PackedStringArray()
	for i in AudioServer.bus_count:
		buses.append("%s %.1f dB%s" % [AudioServer.get_bus_name(i), AudioServer.get_bus_volume_db(i), " muted" if AudioServer.is_bus_mute(i) else ""])
	print("[shot] music: buses: %s; MUSIC %.2f" % [", ".join(buses), c.volume])
	for beat_id: String in c.beats():
		var s: Dictionary = c.sheet_of(beat_id)
		var stream: AudioStreamWAV = c._stream_of(beat_id)
		if stream == null:
			print("[shot] music: %s: no audio" % beat_id)
			continue
		var frames := stream.data.size() >> 1
		var grid := float(s.get("bars", 4)) * 4.0 * 60.0 / float(s.get("bpm", 92))
		print("[shot] music: %s '%s' (%s) %d BPM, %d bars, swing %.2f: %d frames at %d Hz, %.5f s (the grid's %.5f s); loop %s %d .. %d; %s" % [
			beat_id, c.name_of(beat_id), String(s.get("mood", "")), int(s.get("bpm", 0)), int(s.get("bars", 0)), float(s.get("swing", 0.0)),
			frames, stream.mix_rate, frames / float(stream.mix_rate), grid, ["off", "forward", "ping-pong", "backward"][stream.loop_mode],
			stream.loop_begin, stream.loop_end, ["8-bit", "16-bit", "IMA ADPCM", "QOA"][stream.format]])


static func _bars(main: Node, c: Node, n: float) -> void:
	if not c.playing:
		print("[shot] music: nothing is playing")
		return
	var until: float = c.time + n * 4.0 * c.spb
	var guard := Time.get_ticks_msec() + int((n * 4.0 * c.spb * 4.0 + 5.0) * 1000.0)
	while c.playing and c.time < until and Time.get_ticks_msec() < guard:
		await main.get_tree().process_frame
	print("[shot] music: bar %d, step %.2f (beat %.3f, %.3f s)" % [c.bar, c.step, c.beat, c.time])


static func _line(id: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(LINES)) if FileAccess.file_exists(LINES) else null
	if data is Dictionary:
		return (data as Dictionary).get("lines", {}).get(id, {})
	return {}


## Whose mouth moves: the lead for e, else someone here of that name.
static func _actor_for(main: Node, who: String) -> Node3D:
	if who == "e":
		return main._actor
	for member: Dictionary in main._cast.get(main._place, []):
		if String(member["actor"].name).to_lower() == who.to_lower():
			return member["actor"]
	return null


static func _rap(main: Node, c: Node, bits: PackedStringArray) -> void:
	var who := bits[2] if bits.size() > 2 else "e"
	var line := _line(bits[3] if bits.size() > 3 else "steady")
	if line.is_empty() or not c.playing:
		print("[shot] music: rap needs a beat playing and a line from test_lines.json")
		return
	var at_bar := int(bits[4]) if bits.size() > 4 else int(c.bar) + 1
	var actor := _actor_for(main, who)
	c.voice.rap(who, line["syl"], at_bar, actor)
	print("[shot] music: %s raps '%s' on bar %d (%d syllables)%s" % [who, line["text"], at_bar, (line["syl"] as Array).size(),
		"" if actor else "; nobody of that name here to move a mouth"])


# ------------------------------------------------------------------- measuring

static func _capture(bus_name: String) -> Dictionary:
	var effect := AudioEffectCapture.new()
	effect.buffer_length = 40.0
	var bus: int = AudioServer.get_bus_index(bus_name)
	AudioServer.add_bus_effect(bus, effect)
	return {"bus": bus, "effect": effect}


static func _drop(caps: Array) -> void:
	for cap: Dictionary in caps:
		var bus: int = cap["bus"]
		for i in range(AudioServer.get_bus_effect_count(bus) - 1, -1, -1):
			if AudioServer.get_bus_effect(bus, i) == cap["effect"]:
				AudioServer.remove_bus_effect(bus, i)


static func _mono(frames: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(frames.size())
	for i in frames.size():
		out[i] = 0.5 * (frames[i].x + frames[i].y)
	return out


## A 16-bit mono AudioStreamWAV's sample at a position in frames (a fraction is
## read between two), round the file if `loop`.
static func _sample(pcm: PackedByteArray, frames: int, at: float, loop: bool) -> float:
	var i := floori(at)
	var f := at - i
	if loop:
		i = posmod(i, frames)
	elif i < 0 or i >= frames:
		return 0.0
	var a := pcm.decode_s16(2 * i) / 32768.0
	var j := posmod(i + 1, frames) if loop else i + 1
	var b := pcm.decode_s16(2 * j) / 32768.0 if j < frames else 0.0
	return a + (b - a) * f


static func _score(cap: PackedFloat32Array, s0: int, tpl: PackedFloat32Array, tt: float) -> float:
	var dot := 0.0
	var ee := 0.0
	for k in tpl.size():
		var v := cap[s0 + k]
		dot += v * tpl[k]
		ee += v * v
	return dot / sqrt(maxf(ee * tt, 1e-20))


## Where tpl lines up best with cap, as a lag in frames from i0 (within r either
## side: every second frame, then every frame round the best, then to a fraction
## of a frame): [lag, match 0..1, at the edge of the search].
static func _align(cap: PackedFloat32Array, i0: int, tpl: PackedFloat32Array, r: int) -> Array:
	var w := tpl.size()
	if i0 - r - 6 < 0 or i0 + r + 6 + w > cap.size():
		return [0.0, -1.0, false]
	var tt := 0.0
	for k in w:
		tt += tpl[k] * tpl[k]
	if tt <= 1e-12:
		return [0.0, -1.0, false]
	var best := -2.0
	var best_l := 0
	var l := -r
	while l <= r:
		var sc := _score(cap, i0 + l, tpl, tt)
		if sc > best:
			best = sc
			best_l = l
		l += 2
	var fine := {}
	for d in range(-3, 4):
		fine[best_l + d] = _score(cap, i0 + best_l + d, tpl, tt)
	var top := best_l
	for at: int in fine:
		if float(fine[at]) > float(fine[top]):
			top = at
	var frac := 0.0
	if fine.has(top - 1) and fine.has(top + 1):
		var den: float = float(fine[top - 1]) - 2.0 * float(fine[top]) + float(fine[top + 1])
		if den != 0.0:
			frac = 0.5 * (float(fine[top - 1]) - float(fine[top + 1])) / den
	return [top + frac, float(fine[top]), absi(top) >= r - 1]


static func _stats(values: Array) -> String:
	if values.is_empty():
		return "none"
	var sum := 0.0
	var worst := 0.0
	for v: float in values:
		sum += v
		if absf(v) > absf(worst):
			worst = v
	return "mean %+.2f ms, worst %+.2f ms (%d)" % [sum / values.size(), worst, values.size()]


static func _timing(main: Node, c: Node, bits: PackedStringArray) -> void:
	var beat_id := bits[2] if bits.size() > 2 else "iron"
	var n_bars := maxi(int(bits[3]) if bits.size() > 3 else 4, 2)
	var line := _line(bits[4]) if bits.size() > 4 else {}
	var who := bits[5] if bits.size() > 5 else "e"
	var was_stepped: bool = c.stepped
	c.stepped = false
	var caps := [_capture("Music"), _capture("Voice")]
	if not c.play(beat_id, 0):
		print("[shot] music: no beat called %s" % beat_id)
		_drop(caps)
		c.stepped = was_stepped
		return
	var rate := AudioServer.get_mix_rate()
	var shown: Array = []                 # [beat, the clock's time on the frame it was reached]
	var on_beat := func(n: int) -> void: shown.append([n, float(c.time)])
	c.beat_hit.connect(on_beat)
	c.voice.journal = []
	c.voice.keep_journal = true
	if not line.is_empty():
		for b in range(1, n_bars):
			c.voice.rap(who, line["syl"], b, _actor_for(main, who))
	await main.get_tree().process_frame
	AudioServer.lock()
	for cap: Dictionary in caps:
		(cap["effect"] as AudioEffectCapture).clear_buffer()
	var p0: float = c.next_mix_time()
	AudioServer.unlock()
	var got_music := PackedVector2Array()
	var got_voice := PackedVector2Array()
	var music_cap: AudioEffectCapture = caps[0]["effect"]
	var voice_cap: AudioEffectCapture = caps[1]["effect"]
	var wall: Array = []                  # [wall seconds, the clock] each frame once it is heard
	var end: float = n_bars * 4.0 * c.spb + 0.3
	var guard := Time.get_ticks_msec() + int((end + 5.0) * 1000.0)
	while c.time < end and Time.get_ticks_msec() < guard:
		await main.get_tree().process_frame
		var k := music_cap.get_frames_available()
		if k > 0:
			got_music.append_array(music_cap.get_buffer(k))
		k = voice_cap.get_frames_available()
		if k > 0:
			got_voice.append_array(voice_cap.get_buffer(k))
		if c.heard and (wall.is_empty() or int(c.at_usec) / 1000000.0 > float(wall[-1][0])):
			wall.append([int(c.at_usec) / 1000000.0, float(c.time)])
	c.beat_hit.disconnect(on_beat)
	c.voice.keep_journal = false
	c.stop(0.0)
	_drop(caps)
	c.stepped = was_stepped

	var music := _mono(got_music)
	var voice := _mono(got_voice)
	print("[shot] music: timing %s (%d BPM, swing %.2f), %d bars from the audio; mixer %d Hz; captured %d and %d frames (%.3f s) from song time %.4f s" % [
		beat_id, c.bpm, c.swing, n_bars, rate, music.size(), voice.size(), music.size() / rate, p0])
	# Each beat in the sound, against the grid.
	var stream: AudioStreamWAV = c._stream_of(beat_id)
	var pcm := stream.data
	var frames := pcm.size() >> 1
	var heard_ms: Array = []
	var shown_ms: Array = []
	var out := PackedStringArray()
	for n in n_bars * 4:
		var t: float = n * c.spb
		var j: float = (t - p0) * rate + c.LOOKAHEAD
		var i0 := floori(j - 0.004 * rate)
		var tpl := PackedFloat32Array()
		tpl.resize(int(0.02 * rate))
		for k in tpl.size():
			var song: float = p0 + (i0 + k - c.LOOKAHEAD) / rate
			tpl[k] = _sample(pcm, frames, fposmod(song, c._loop) * stream.mix_rate, true)
		var found := _align(music, i0, tpl, int(0.006 * rate))
		var late := "-"
		for e: Array in shown:
			if int(e[0]) == n:
				late = "%+.1f" % ((float(e[1]) - t) * 1000.0)
				shown_ms.append((float(e[1]) - t) * 1000.0)
		if float(found[1]) < 0.0:
			out.append("%d: not in the capture, shown %s" % [n, late])
			continue
		var ms: float = float(found[0]) / rate * 1000.0
		heard_ms.append(ms)
		out.append("%d: %+.2f%s (%.2f), shown %s" % [n, ms, " EDGE" if found[2] else "", found[1], late])
	print("[shot] music: each beat, sounded against the clock in ms (how well it matched), and how late the frame that showed it was:")
	for i in range(0, out.size(), 4):
		print("[shot] music:   " + ";  ".join(out.slice(i, i + 4)))
	# Each syllable, in the voice capture, against its step.
	var sung_ms: Array = []
	var journal: Array = c.voice.journal
	if not journal.is_empty():
		print("[shot] music: each syllable (%s, '%s'), sounded against its step in ms (how well it matched):" % [who, line.get("text", "")])
		out = PackedStringArray()
		for e: Dictionary in journal:
			var syl_stream: AudioStreamWAV = e["stream"]
			var spcm := syl_stream.data
			var sframes := spcm.size() >> 1
			var pitch: float = e["pitch"]
			var start: float = (float(e["next_mix"]) - p0) * rate + c.LOOKAHEAD      # the capture frame it began on
			var j: float = (float(e["t"]) - p0) * rate + c.LOOKAHEAD
			var i0 := floori(j - 0.008 * rate)
			var tpl := PackedFloat32Array()
			tpl.resize(int(0.02 * rate))
			for k in tpl.size():
				var in_file: float = float(e["from"]) + (i0 + k - start) * pitch / rate
				tpl[k] = _sample(spcm, sframes, in_file * syl_stream.mix_rate, false)
			var found := _align(voice, i0, tpl, int(0.012 * rate))
			var bar_step := ""
			var b_at := floorf(float(e["t"]) / (4.0 * c.spb))
			bar_step = "bar %d" % b_at
			if float(found[1]) < 0.0:
				out.append("'%s' %s: not in the capture" % [e["text"], bar_step])
				continue
			var ms: float = float(found[0]) / rate * 1000.0
			sung_ms.append(ms)
			out.append("'%s' %+.2f%s (%.2f)" % [e["text"], ms, " EDGE" if found[2] else "", found[1]])
		for i in range(0, out.size(), 6):
			print("[shot] music:   " + ";  ".join(out.slice(i, i + 6)))
	# The clock against the wall clock: a straight line through it, and how far it strays.
	var drift := "too few frames"
	if wall.size() > 10:
		var mx := 0.0
		var my := 0.0
		for p: Array in wall:
			mx += float(p[0])
			my += float(p[1])
		mx /= wall.size()
		my /= wall.size()
		var sxy := 0.0
		var sxx := 0.0
		for p: Array in wall:
			sxy += (float(p[0]) - mx) * (float(p[1]) - my)
			sxx += (float(p[0]) - mx) * (float(p[0]) - mx)
		var slope := sxy / sxx
		var sq := 0.0
		var worst := 0.0
		for p: Array in wall:
			var r := float(p[1]) - (my + slope * (float(p[0]) - mx))
			sq += r * r
			worst = maxf(worst, absf(r))
		drift = "%.5f s of music a second; off a straight line by %.2f ms RMS, %.2f ms at worst, over %d frames" % [slope, sqrt(sq / wall.size()) * 1000.0, worst * 1000.0, wall.size()]
	print("[shot] music: summary: beats sounded %s; syllables %s; the frame showing a beat late by %s; the clock against the wall: %s" % [
		_stats(heard_ms), _stats(sung_ms), _stats(shown_ms), drift])


## The take's move prompts: when each reached the ring against when it was due.
static func _take_timing(main: Node, c: Node, seconds: float) -> void:
	var video: Node = main._video
	var take: Node = video._take
	if take == null:
		print("[shot] music: no take is running (video:shoot first)")
		return
	if c.stepped:
		print("[shot] music: the clock is stepped; put music:live before video:shoot")
		return
	var reached := {}                     # prompt index: [the take's time on the frame it reached the ring, when it was due, its beat]
	var shown: Array = []
	var shown_n: Array = []
	var on_beat := func(n: int) -> void:
		shown.append((float(c.time) - n * float(c.spb)) * 1000.0)
		shown_n.append(n)
	c.beat_hit.connect(on_beat)
	var take_beat: float = take.BEAT
	var prompts: Array = take.prompts     # the same dictionaries: their grades are filled in as he presses
	var offsets: Array = []               # each frame its beat plays: the clock's time less the take's, in ms (the take began with the beat: 0)
	video._live = true
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until and is_instance_valid(take) and not take.done:
		await main.get_tree().process_frame
		if not is_instance_valid(take):
			break
		if c.playing and c.id == take.beat_id:
			offsets.append((float(c.time) - float(take.time)) * 1000.0)
		var b: float = take.beat()
		for i in prompts.size():
			var p: Dictionary = prompts[i]
			if not reached.has(i) and b >= float(p["beat"]):
				reached[i] = [float(take.time), float(p["beat"]) * take_beat, float(p["beat"])]
	video._live = false
	c.beat_hit.disconnect(on_beat)
	var late_ms: Array = []
	var out := PackedStringArray()
	for i: int in reached:
		var r: Array = reached[i]
		var p: Dictionary = prompts[i]
		late_ms.append((float(r[0]) - float(r[1])) * 1000.0)
		out.append("beat %.0f %+.1f %s" % [float(r[2]), late_ms[-1], String(p["grade"]) if String(p["grade"]) != "" else String(p["state"])])
	print("[shot] music: take on %s at %d BPM (a beat %.4f s, the take's %.4f s), %.1f s live; each move prompt reaching the ring, against when it was due, in ms:" % [
		c.id, c.bpm, c.spb, take_beat, seconds])
	for i in range(0, out.size(), 6):
		print("[shot] music:   " + ";  ".join(out.slice(i, i + 6)))
	var worst := 0
	for i in shown.size():
		if absf(float(shown[i])) > absf(float(shown[worst])):
			worst = i
	print("[shot] music: summary: prompts reached the ring late by %s; beats shown late by %s%s; while its beat played, the clock's time less the take's: %s" % [
		_stats(late_ms), _stats(shown), " (the worst on beat %d)" % shown_n[worst] if not shown.is_empty() else "", _stats(offsets)])


# ------------------------------------------------------------------ recording

static func _render(main: Node, c: Node, bits: PackedStringArray) -> void:
	var beat_id := bits[2] if bits.size() > 2 else "iron"
	var n_bars := maxi(int(bits[3]) if bits.size() > 3 else 4, 1)
	var line_id := bits[4] if bits.size() > 4 else ""
	var who := bits[5] if bits.size() > 5 else "e"
	var line := _line(line_id) if line_id != "" else {}
	if c.sheet_of(beat_id).is_empty() or c._stream_of(beat_id) == null:
		print("[shot] music: no beat called %s" % beat_id)
		return
	var root := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()
	var folder := root.path_join(ART)
	if not DirAccess.dir_exists_absolute(folder):
		folder = String(main._shot_path).get_base_dir()
	var path := folder.path_join("render_%s%s.wav" % [beat_id, "" if line.is_empty() else "_%s_%s" % [line_id, who]])
	var was_stepped: bool = c.stepped
	var was_volume: float = c.volume
	c.stepped = false
	c.set_volume(1.0)
	var rec := AudioEffectRecord.new()
	rec.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(0, rec)
	await main.get_tree().process_frame
	AudioServer.lock()               # the recording and the beat begin on the same chunk
	rec.set_recording_active(true)
	c.play(beat_id, 0)
	AudioServer.unlock()
	if not line.is_empty():
		for b in range(1, n_bars):
			c.voice.rap(who, line["syl"], b, _actor_for(main, who))
	var end: float = n_bars * 4.0 * c.spb
	var guard := Time.get_ticks_msec() + int((end + 5.0) * 1000.0)
	while c.time < end and Time.get_ticks_msec() < guard:
		await main.get_tree().process_frame
	c.stop(0.0)
	for i in 20:                     # what is still ringing
		await main.get_tree().process_frame
	rec.set_recording_active(false)
	var wav := rec.get_recording()
	for i in range(AudioServer.get_bus_effect_count(0) - 1, -1, -1):
		if AudioServer.get_bus_effect(0, i) == rec:
			AudioServer.remove_bus_effect(0, i)
	c.set_volume(was_volume)
	c.stepped = was_stepped
	var err := wav.save_to_wav(path) if wav else ERR_CANT_CREATE
	print("[shot] music: %s %s (%.2f s, %d Hz, %s)" % ["recorded" if err == OK else "FAILED to record", path,
		wav.get_length() if wav else 0.0, wav.mix_rate if wav else 0, "the beat alone" if line.is_empty() else "%s rapping '%s' on bars 1 to %d" % [who, line["text"], n_bars - 1]])
