extends SceneTree
## Tests the Audio autoload (scripts/audio/audio.gd) against the rendered WAVs. Headless is fine:
##   python godot/tools/godot_run.py --import          # once, after (re)rendering the WAVs
##   python godot/tools/godot_run.py --timeout 180 -- --headless --audio-driver Dummy --script res://tools/audio/test_audio.gd
## Prints "ok" / "FAIL" per check and exits 1 on any failure. It takes about 25 seconds because it
## really plays the sounds (the Dummy driver mixes in real time) and records the Master bus.
##
## What it checks: the buses and the loop settings; that every sfx name and every dtmf key plays
## the right file on the SFX bus and plays to its end; snore volume; overlapping and the voice
## cap; that the final level on the Master bus is the JS level (sfx = file x .7, music = file x .3);
## that the loop wraps sample-exactly; that start() is idempotent; set_music() and set_paused();
## and that nothing in audio.gd logs an error or warning.

const SFX := ["shutter", "click", "tick", "buzz", "honk", "door", "pickup", "win", "siren", "whistle",
		"snore", "hangup", "busy", "cuffs", "cash", "knock", "step"]
const KEYS := {"0": "0", "1": "1", "2": "2", "3": "3", "4": "4", "5": "5", "6": "6", "7": "7", "8": "8",
		"9": "9", "*": "star", "#": "hash"}
const RATE := 44100.0
const LOOP_FRAMES := 470400

var fails := 0
var audio: Node
var cap: AudioEffectCapture
var log_catch := LogCatch.new()


## Collects every engine error and warning printed while the test runs.
class LogCatch extends Logger:
	var lines: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		lines.append("%s:%d %s: %s %s (type %d)" % [file, line, function, code, rationale, error_type])


func _initialize() -> void:
	OS.add_logger(log_catch)
	_run()


func check(ok: bool, what: String) -> void:
	print("  ok    " if ok else "  FAIL  ", what)
	if not ok:
		fails += 1


func near(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol


## The SFX-bus players that are playing (also the held ones, if include_held).
func voices(include_held := false) -> Array[AudioStreamPlayer]:
	var out: Array[AudioStreamPlayer] = []
	for c in audio.get_children():
		var p := c as AudioStreamPlayer
		if p != null and p.bus == &"SFX" and (p.playing or (include_held and p.stream_paused)):
			out.append(p)
	return out


## File name of the sound the only playing voice has, or "" if it is not exactly one.
func only_voice_file() -> String:
	var v := voices()
	return v[0].stream.resource_path.get_file() if v.size() == 1 else ""


func music_player() -> AudioStreamPlayer:
	return audio.get_node("Music") as AudioStreamPlayer


func stop_voices() -> void:
	for p in voices(true):
		p.stop()


## Records n Master-bus frames (stereo) from the capture effect.
func record(frames: int) -> PackedVector2Array:
	cap.clear_buffer()
	var got := PackedVector2Array()
	var t0 := Time.get_ticks_msec()
	while got.size() < frames and Time.get_ticks_msec() - t0 < 1000.0 * (frames / RATE) * 3.0 + 3000.0:
		await process_frame
		var n := cap.get_frames_available()
		if n > 0:
			got.append_array(cap.get_buffer(n))
	if got.size() > frames:
		got.resize(frames)
	return got


func peak_of(buf: PackedVector2Array) -> float:
	var m := 0.0
	for v in buf:
		m = maxf(m, maxf(absf(v.x), absf(v.y)))
	return m


func file_samples(stem: String) -> PackedFloat32Array:
	var d: PackedByteArray = (load("res://assets/audio/%s.wav" % stem) as AudioStreamWAV).data
	var out := PackedFloat32Array()
	out.resize(d.size() / 2)
	for i in out.size():
		out[i] = d.decode_s16(i * 2) / 32767.0  # Godot's own int16 -> float scale
	return out


func file_peak(stem: String) -> float:
	var m := 0.0
	for x in file_samples(stem):
		m = maxf(m, absf(x))
	return m


## Where in the (looped) file does the recording start? Finds the offset o so that
## rec[i] == ref[(o + i) % N] * gain around the loudest sample from index `from` on, or -1.
func locate(rec: PackedVector2Array, ref: PackedFloat32Array, gain: float, from: int) -> int:
	var k0 := from
	var best := 0.0
	for i in range(from, rec.size()):
		if absf(rec[i].x) > best:
			best = absf(rec[i].x)
			k0 = i
	var target := rec[k0].x / gain
	var n := ref.size()
	for o in n:
		if absf(ref[o] - target) < 2e-6:
			var ok := true
			for d in range(-24, 24):
				var i := k0 + d
				if i >= 0 and i < rec.size() and absf(ref[(o + d + n) % n] * gain - rec[i].x) > 2e-6:
					ok = false
					break
			if ok:
				return posmod(o - k0, n)
	return -1


func _run() -> void:
	await process_frame
	audio = root.get_node_or_null("Audio")
	if audio == null:  # not registered as an autoload: test a private copy
		audio = load("res://scripts/audio/audio.gd").new()
		audio.name = "Audio"
		root.add_child(audio)
		await process_frame
	cap = AudioEffectCapture.new()
	cap.buffer_length = 2.0
	AudioServer.add_bus_effect(0, cap)  # Master: sees the Music and SFX buses after their gains
	print("mix rate ", AudioServer.get_mix_rate(), " Hz, output driver ", AudioServer.get_driver_name())

	print("buses and streams")
	var mi := AudioServer.get_bus_index("Music")
	var si := AudioServer.get_bus_index("SFX")
	check(mi != -1 and si != -1, "Music and SFX buses exist")
	check(near(AudioServer.get_bus_volume_db(mi), linear_to_db(0.3), 0.001), "Music bus gain 0.3 (js musicG)")
	check(near(AudioServer.get_bus_volume_db(si), linear_to_db(0.7), 0.001), "SFX bus gain 0.7 (js sfxG)")
	check(AudioServer.get_bus_send(mi) == &"Master" and AudioServer.get_bus_send(si) == &"Master", "both buses send to Master")
	check(not AudioServer.is_bus_mute(mi), "music on by default")
	var loop := music_player().stream as AudioStreamWAV
	check(loop != null and loop.loop_mode == AudioStreamWAV.LOOP_FORWARD and loop.loop_begin == 0 and loop.loop_end == LOOP_FRAMES, "music.wav loops forward over all 470400 samples")
	check(loop != null and loop.format == AudioStreamWAV.FORMAT_16_BITS and loop.mix_rate == 44100 and not loop.stereo, "music.wav is 16-bit mono 44.1 kHz PCM (not QOA)")
	check(near(loop.get_length(), 4 * 4 * 60.0 / 90.0, 0.0001), "music loop is 4 bars at 90 BPM (10.667 s)")
	check(not music_player().playing, "music does not play before start()")

	print("every sfx name plays its file on the SFX bus")
	for n in SFX:
		stop_voices()
		audio.sfx(n)
		check(only_voice_file() == "sfx_%s.wav" % n, "sfx(\"%s\") -> sfx_%s.wav" % [n, n])
	for k in KEYS:
		stop_voices()
		audio.sfx("dtmf", k)
		check(only_voice_file() == "sfx_dtmf_%s.wav" % KEYS[k], "sfx(\"dtmf\", \"%s\") -> sfx_dtmf_%s.wav" % [k, KEYS[k]])
	stop_voices()
	audio.sfx("dtmf")
	check(only_voice_file() == "sfx_dtmf_1.wav", "dtmf with no key falls back to 1 (like the JS)")
	stop_voices()
	audio.sfx("dtmf", "x")
	check(only_voice_file() == "sfx_dtmf_1.wav", "dtmf with an unknown key falls back to 1")
	stop_voices()
	audio.sfx("dtmf", 5)
	check(only_voice_file() == "sfx_dtmf_5.wav", "dtmf with the number 5 plays key 5")

	print("snore loudness")
	stop_voices()
	audio.sfx("snore")
	check(near(voices()[0].volume_db, 0.0, 0.001), "snore default = x1")
	stop_voices()
	audio.sfx("snore", 1.6)
	check(near(voices()[0].volume_db, linear_to_db(1.6), 0.001), "snore 1.6 = x1.6 (+4.08 dB)")
	stop_voices()
	audio.sfx("snore", 0)
	check(near(voices()[0].volume_db, 0.0, 0.001), "snore 0 = x1 (js: arg || 1)")
	stop_voices()
	audio.sfx("click")
	check(near(voices()[0].volume_db, 0.0, 0.001), "a voice used after a snore is back at 0 dB")

	print("overlap and the voice cap")
	stop_voices()
	for i in 5:
		audio.sfx("click")
	check(voices().size() == 5, "5 sounds at once = 5 voices")
	for i in 30:
		audio.sfx("siren")
	check(voices().size() == 16, "30 sounds at once = 16 voices (the oldest are cut, no error)")
	stop_voices()
	for n in SFX.slice(0, 16):
		audio.sfx(n)
	audio.sfx("step")  # the 17th at once
	var playing_files: Array[String] = []
	for v in voices():
		playing_files.append(v.stream.resource_path.get_file())
	check(playing_files.size() == 16 and "sfx_step.wav" in playing_files and not "sfx_shutter.wav" in playing_files and "sfx_knock.wav" in playing_files, "the 17th sound takes the oldest voice (shutter), not a newer one")
	stop_voices()

	print("final level on the Master bus")
	await process_frame
	audio.sfx("tick")
	var rec := await record(int(0.25 * RATE))
	var want := file_peak("sfx_tick") * 0.7
	check(near(peak_of(rec), want, want * 0.02), "tick peak %.4f = file %.4f x .7 (real Chrome render of audio.js: 0.1096)" % [peak_of(rec), want])
	stop_voices()
	audio.sfx("snore", 1.6)
	rec = await record(int(1.6 * RATE))
	want = file_peak("sfx_snore") * 0.7 * 1.6
	check(near(peak_of(rec), want, want * 0.03), "snore x1.6 peak %.4f = file x .7 x 1.6 = %.4f" % [peak_of(rec), want])
	stop_voices()

	print("music: start(), idempotence, level, loop")
	audio.start()
	await process_frame
	check(music_player().playing, "start() starts the loop")
	rec = await record(LOOP_FRAMES)  # exactly one loop, so the mean square is the file's whatever the start
	var ref := file_samples("music")
	check(ref.size() == LOOP_FRAMES, "music.wav has %d samples" % ref.size())
	var ss := 0.0
	for x in ref:
		ss += x * x
	var want_rms := sqrt(ss / ref.size()) * 0.3
	ss = 0.0
	for v in rec:
		ss += v.x * v.x
	var got_rms := sqrt(ss / rec.size())
	check(near(got_rms, want_rms, want_rms * 0.03), "music RMS %.5f = file RMS x .3 = %.5f" % [got_rms, want_rms])
	var pos0 := music_player().get_playback_position()
	audio.start()
	audio.start()
	await create_timer(0.3).timeout
	var pos1 := music_player().get_playback_position()
	check(music_player().playing and (pos1 > pos0 or pos1 < pos0 - 5.0), "calling start() again does not restart the loop (%.2f s -> %.2f s)" % [pos0, pos1])

	# Jump to 0.35 s before the end and record 1 s across the wrap; every recorded sample must be
	# the file's sample x .3 in order, wrapping from the last sample to the first.
	var finished_seen := [false]
	music_player().finished.connect(func(): finished_seen[0] = true)
	music_player().seek(10.6667 - 0.35)
	rec = await record(int(1.0 * RATE))
	check(music_player().playing and not finished_seen[0], "the loop wraps and keeps playing")
	var off := locate(rec, ref, 0.3, 2048)
	check(off != -1, "the recording is found in the file (starts %.4f s into the loop)" % (off / RATE))
	if off != -1:
		# The first mix buffer or two after seek() still come from the old position: skip 2048 samples.
		# The one sample at the wrap may differ by 1 LSB x .3 (Godot interpolates the last frame towards the padding).
		var bad := 0
		var maxerr := 0.0
		var wrapped_at := -1
		for i in range(2048, rec.size()):
			var j := (off + i) % LOOP_FRAMES
			if j == 0:
				wrapped_at = i
			var e := absf(ref[j] * 0.3 - rec[i].x)
			maxerr = maxf(maxerr, e)
			if e > (1.1e-5 if (j == 0 or j == LOOP_FRAMES - 1) else 2e-6):
				bad += 1
		check(wrapped_at != -1 and bad == 0, "%d samples across the wrap match the file x .3 (the wrap is %.3f s in, max error %s)" % [rec.size() - 2048, wrapped_at / RATE, maxerr])

	print("set_music()")
	audio.set_music(false)
	check(AudioServer.is_bus_mute(mi) and music_player().playing, "off: Music bus muted, the beat keeps running")
	rec = await record(int(0.2 * RATE))
	check(peak_of(rec) < 1e-6, "off: silence on the Master bus (peak %.7f)" % peak_of(rec))
	var p_off := music_player().get_playback_position()
	await create_timer(0.3).timeout
	check(music_player().get_playback_position() != p_off, "off: the loop position still moves")
	audio.set_music(true)
	check(not AudioServer.is_bus_mute(mi) and near(AudioServer.get_bus_volume_db(mi), linear_to_db(0.3), 0.001), "on: unmuted at 0.3")
	rec = await record(int(0.5 * RATE))
	check(peak_of(rec) > 0.001, "on: the music is back on the Master bus (peak %.4f)" % peak_of(rec))

	print("set_paused()")
	stop_voices()
	audio.sfx("siren")
	await create_timer(0.2).timeout
	audio.set_paused(true)
	await create_timer(0.1).timeout
	var frozen := music_player().get_playback_position()
	await create_timer(0.4).timeout
	check(not music_player().playing and music_player().stream_paused, "paused: the loop stops")
	check(near(music_player().get_playback_position(), frozen, 0.001), "paused: loop position frozen at %.3f s" % frozen)
	check(voices().size() == 0 and voices(true).size() == 1, "paused: the siren is held, not dropped")
	rec = await record(int(0.2 * RATE))
	check(peak_of(rec) < 1e-6, "paused: silence on the Master bus (peak %.7f)" % peak_of(rec))
	audio.sfx("click")
	check(voices(true).size() == 2 and voices().size() == 0, "a sound asked for while paused waits for the resume")
	audio.set_paused(false)
	await create_timer(0.3).timeout
	check(music_player().playing and not near(music_player().get_playback_position(), frozen, 0.01), "resumed: the loop moves again")
	check(voices().size() >= 1, "resumed: the siren and the click play")
	stop_voices()

	print("all %d sounds play to the end" % (SFX.size() + KEYS.size()))
	audio.set_music(false)
	music_player().stop()
	var all: Array = []
	for n in SFX:
		all.append([n, null])
	for k in KEYS:
		all.append(["dtmf", k])
	for batch in [all.slice(0, 15), all.slice(15)]:
		stop_voices()
		for e in batch:
			audio.sfx(e[0], e[1])
		check(voices().size() == batch.size(), "%d started together" % batch.size())
		await create_timer(2.9).timeout  # the siren is 2.6 s
		check(voices().size() == 0, "all of them finished by themselves")

	print("log")
	var mine: Array[String] = []
	var others: Array[String] = []
	for l in log_catch.lines:
		(mine if "audio" in l.to_lower() else others).append(l)
	check(mine.is_empty(), "no error or warning from the audio code")
	for l in mine:
		print("        ", l)
	if not others.is_empty():
		print("  note  %d other engine message(s) not from the audio code (first: %s)" % [others.size(), others[0]])

	print("RESULT: ", "ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails else 0)
