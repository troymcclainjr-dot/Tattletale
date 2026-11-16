extends RefCounted
## The song: --do steps (main.gd hands every step that starts with song: here): write a song, sing it at the
## booth mic, measure and record it. songs.gd is the notebook and the mic; song_sheet.gd the page; song_score.gd
## the score. Every line printed starts "[shot] song:".
##
##   writing (on the page he left; it is the save's song_draft):
##   song:new[:<beat>]                   a fresh page on that beat (the first there is)
##   song:beat:<id>                      the page's beat
##   song:hook:<name>                    the hook (both halves): block, up, cost, county, home, screen, tape, walk
##   song:verse:<1|2>:<c+c+c+c>          a verse's four cards by id ("-" leaves that slot as it is)
##   song:card:<1|2>:<n>:<id>[:<word>]   one card (n 1 to 4), its slot word if it has one
##   song:word:<1|2>:<n>:<word>          the word in that card's slot (rules/words.json ids)
##   song:out:<hook|1|2>[:<n>]           take a card (or the hook) out
##   song:title[:<n>|<text>]             the title: the nth of those built from the hook (1), or that text
##   song:fill:<seed>[:<only>]           every empty slot filled from the seed; only: any, mine (no cap), starter,
##                                       earned, true (earned and a claim), cap
##   song:save                           SAVE THE SONG: it waits at the booth mic
##   song:sheet                          the page, the songs waiting, every song recorded, the true bars put out
##   song:score                          the page's read and the last recorded song's score, the line that most
##                                       helped and most hurt
##   the notebook on screen:
##   song:open, song:row:<n> (0 beat, 1 hook, 2-5 verse 1, 6-9 verse 2, 10 title, 11 save), song:list (Enter
##   on the row), song:point:<k> (the list's kth), song:pick:<k> (put it in), song:left, song:right, song:hear,
##   song:del, song:esc (as Esc), song:close
##   at the mic:
##   song:auto:<skill>[:<seed>]          the player of the next take (and of one running): 0 .. 1, as video:auto
##   song:mic                            he steps up to the booth mic (to the studio first): the song waiting is sung
##   song:until:<bar>[:<step>]           the take on, stepped, to that bar of the song (1 the first sung, 0 the count-in)
##   song:untilmiss[:<frames>]          the take on, stepped, to its next MISS (and that many frames more: 6)
##   song:end                            on to the end: recorded, the score up
##   song:enter / song:stop              Enter on the score / Esc during the take
##   song:snap:<name>                    a picture of the screen as it is, beside the --shot file
##   proof:
##   song:steps                          (after song:mic, stepped) every syllable's step: the voice's schedule against
##                                       the take's and the grid's, then the take run to its end: the frame each was
##                                       reached on against its step, and every press the auto player made
##   song:timing[:<bars>[:<skill>]]      the song waiting sung live (the clock from the audio) for that many bars (12),
##                                       and each syllable as it sounded on the Voice bus against its step, in ms
##   song:render[:<bars>[:<skill>]]      what a player hears (Master), count-in and that many bars (12: verse 1 and
##                                       the hook) live, to song_<title>.wav beside the --shot file
##   song:video                          what the next music video gets from its song: the cap on swagger, the comments

const BeatsSteps := preload("res://scripts/beats_steps.gd")
const Sheet := preload("res://scripts/song_sheet.gd")
const Score := preload("res://scripts/song_score.gd")
const SongVideo := preload("res://scripts/song_video.gd")
const Bars := preload("res://scripts/bars.gd")


static func step(main: Node, bits: PackedStringArray) -> void:
	var songs: Node = main._songs
	var state: RefCounted = main._state
	var what := bits[1] if bits.size() > 1 else "sheet"
	var nb: CanvasLayer = songs.notebook
	match what:
		"new":
			var beat := bits[2] if bits.size() > 2 else ""
			if beat == "" or main._conductor.sheet_of(beat).is_empty():
				beat = String(main._conductor.beats()[0])
			state.song_draft = Sheet.blank(beat, int(main._day) + 1)
			_said(main, "a fresh page on %s" % beat)
		"beat":
			_draft(main)["beat"] = bits[2]
			_said(main, "beat %s" % bits[2])
		"hook":
			Sheet.put(state, _draft(main), "hook", 0, "hook_%s_a" % bits[2])
			_said(main, "hook %s, title '%s'" % [bits[2], _draft(main).get("title", "")])
		"verse":
			var row := "verse" + bits[2]
			var ids := bits[3].split("+")
			for i in mini(ids.size(), 4):
				if ids[i] != "-" and ids[i] != "":
					Sheet.put(state, _draft(main), row, i, ids[i])
			_said(main, "%s: %s" % [row, bits[3]])
		"card":
			Sheet.put(state, _draft(main), "verse" + bits[2], int(bits[3]) - 1, bits[4], bits[5] if bits.size() > 5 else "")
			_said(main, "verse %s card %s: %s" % [bits[2], bits[3], bits[4]])
		"word":
			Sheet.set_word(state, _draft(main), "verse" + bits[2], int(bits[3]) - 1, bits[4])
			var e := Sheet.at(_draft(main), "verse" + bits[2], int(bits[3]) - 1)
			_said(main, "verse %s card %s: slot word %s: %s" % [bits[2], bits[3], e.get("slot", ""), " / ".join(PackedStringArray((e.get("lines", []) as Array).map(func(l: Dictionary) -> String: return String(l["text"]))))])
		"out":
			Sheet.take_out(_draft(main), "hook" if bits[2] == "hook" else "verse" + bits[2], int(bits[3]) - 1 if bits.size() > 3 else 0)
			_said(main, "took out %s %s" % [bits[2], bits[3] if bits.size() > 3 else ""])
		"title":
			var all := Sheet.titles(_draft(main))
			var want := bits[2] if bits.size() > 2 else "1"
			_draft(main)["title"] = String(all[clampi(int(want) - 1, 0, all.size() - 1)]) if want.is_valid_int() and not all.is_empty() else want.to_upper()
			_said(main, "title '%s' (of %s)" % [_draft(main)["title"], all])
		"fill":
			var draft := _draft(main)
			Sheet.fill(state, draft, int(bits[2]) if bits.size() > 2 else 1, bits[3] if bits.size() > 3 else "any")
			_said(main, "filled from seed %s (%s): %d of 10 cards, '%s'" % [bits[2] if bits.size() > 2 else "1", bits[3] if bits.size() > 3 else "any", Sheet.filled(draft), draft.get("title", "")])
		"save":
			if nb.is_open():
				nb.save()
			else:
				nb.sheet = _draft(main)
				nb.visible = true
				var ok: bool = nb.save()
				nb.visible = false
				if not ok:
					_said(main, "not saved: the page is not full (%d of 10 cards, title '%s')" % [Sheet.filled(_draft(main)), _draft(main).get("title", "")])
			_said(main, "%d waiting at the mic" % (state.song_written as Array).size())
		"sheet":
			_print_sheets(main)
		"score":
			_print_score(main)
		"open":
			songs.open_notebook()
			await _frames(main, 3)
			_said(main, "notebook open: row %d, %d cards on its list" % [nb.row, nb.items.size()])
		"row":
			nb.select_row(int(bits[2]))
			await _frames(main, 2)
			_said(main, "row %d: %d on its list" % [nb.row, nb.items.size()])
		"list":
			nb.enter()
			await _frames(main, 2)
			_said(main, "the list (%d), at %d" % [nb.items.size(), nb.pick])
		"point":
			nb.point(int(bits[2]))
			await _frames(main, 3)
			_said(main, "pointing at %d: %s" % [nb.pick, nb.items[nb.pick] if nb.pick < nb.items.size() else "nothing"])
		"pick":
			nb.point(int(bits[2]))
			nb.choose(nb.pick)
			await _frames(main, 2)
			_said(main, "picked; now on row %d" % nb.row)
		"left", "right":
			nb.change(-1 if what == "left" else 1)
			await _frames(main, 2)
		"del":
			nb.take_out()
		"hear":
			nb.hear()
			_said(main, "hearing from bar %d (%d lines; the beat %s at %.3f s)" % [int(main._conductor.bar) + 1, nb._hear_rows.size(), "playing" if main._conductor.playing else "stopped", main._conductor.time])
		"esc":
			var press := InputEventKey.new()
			press.physical_keycode = KEY_ESCAPE
			press.keycode = KEY_ESCAPE
			press.pressed = true
			if nb.is_open():
				nb._unhandled_key_input(press)
			else:
				songs.take._unhandled_key_input(press)
			await _frames(main, 2)
		"close":
			nb.close()
		"auto":
			songs.auto = float(bits[2])
			if bits.size() > 3:
				songs.seed_value = int(bits[3])
			songs.take.auto = songs.auto
			_said(main, "the auto player at skill %.2f, seed %d" % [songs.auto, songs.seed_value])
		"mic":
			await _to_mic(main)
			_said(main, "at the mic: %s" % ("singing '%s'" % songs.take.sheet.get("title", "") if songs.take.running else "a freestyle (nothing written waiting)"))
		"until":
			var take: CanvasLayer = songs.take
			if not take.running:
				_said(main, "no take running")
				return
			var t: float = main._conductor.time_of(take.start_bar + int(bits[2]) - 1, float(bits[3]) if bits.size() > 3 else 0.0)
			await take.run_to(t)
			_said(main, "bar %d step %.2f (%.3f s): %s; flow so far %d (%d judged, %d perfect, %d good, %d missed, %d off beat)" % [int(main._conductor.bar) - take.start_bar + 1,
				main._conductor.step, main._conductor.time, "running" if take.running else "over", Score.flow_of(take.take), take.take["judged"], take.take["perfect"], take.take["good"], take.take["missed"], take.take["flubs"]])
		"untilmiss":
			var take: CanvasLayer = songs.take
			var was := int(take.take.get("missed", 0))
			var n := 0
			while take.running and int(take.take["missed"]) == was and n < 60 * 120:
				await take.run_to(float(main._conductor.time) + 1.0 / 60.0)
				n += 1
			await take.run_to(float(main._conductor.time) + float(bits[2]) / 60.0 if bits.size() > 2 else float(main._conductor.time) + 0.1)
			_said(main, "a miss at %.3f s (bar %d of the song): %s" % [main._conductor.time, int(main._conductor.bar) - take.start_bar + 1, take.take])
		"end":
			var take: CanvasLayer = songs.take
			if take.running:
				await take.run_to(take.end_t + 0.05)
			await _frames(main, 2)
			_said(main, "the take is over: %s" % Score.line(take.result))
		"enter":
			songs.take.close_score()
			await _frames(main, 2)
		"stop":
			songs.take.stop_take()
			await _frames(main, 2)
		"snap":
			if main._performing:
				main._bar = 1.0                  # the black bars all the way in (a fast-forwarded take has had few frames to slide them)
			if main._video:
				main._video._toast_t = 99.0      # no note left over from the steps before
			await _frames(main, 3)
			await RenderingServer.frame_post_draw
			var path: String = String(main._shot_path).get_base_dir().path_join((bits[2] if bits.size() > 2 else "song") + ".png")
			var err := main.get_viewport().get_texture().get_image().save_png(path)
			print("[shot] song: %s %s" % ["saved" if err == OK else "FAILED", path])
		"steps":
			await _stepped(main)
		"timing":
			await _timing(main, int(bits[2]) if bits.size() > 2 else 12, float(bits[3]) if bits.size() > 3 else 1.0)
		"render":
			await _render(main, int(bits[2]) if bits.size() > 2 else 12, float(bits[3]) if bits.size() > 3 else 0.85)
		"video":
			var sheet := SongVideo.sheet_now()
			if sheet.is_empty():
				_said(main, "the next video's song has no written sheet: its numbers are as without the notebook")
			else:
				_said(main, "the next video is for '%s' (total %d): swagger capped at %d; tags %s; comments %s" % [sheet["title"], int(sheet["score"]["total"]),
					SongVideo.cap_of(int(sheet["score"]["total"])), SongVideo.tags(sheet), SongVideo.comments(sheet).map(func(c: Dictionary) -> String: return "@%s: %s" % [c["who"], c["text"]])])
		_:
			_said(main, "no step %s" % what)
	if nb.is_open() and what in ["new", "beat", "hook", "verse", "card", "word", "out", "title", "fill"]:
		nb.sheet = _draft(main)          # the notebook on screen shows the page as the step left it
		nb._changed()
		await _frames(main, 2)


static func _said(_main: Node, text: String) -> void:
	print("[shot] song: " + text)


static func _frames(main: Node, n: int) -> void:
	for i in n:
		await main.get_tree().process_frame


## The page being written (a fresh one if there is none).
static func _draft(main: Node) -> Dictionary:
	var state: RefCounted = main._state
	if (state.song_draft as Dictionary).is_empty():
		state.song_draft = Sheet.blank(String(main._conductor.beats()[0]), int(main._day) + 1)
	return state.song_draft


## To the studio and up to the booth mic, as E there does.
static func _to_mic(main: Node) -> void:
	if main._place != "studio":
		main._travel_to("studio", true)
		await _frames(main, 2)
	main._start_perform(main._building.mic.to)
	await _frames(main, 1)


static func _print_sheets(main: Node) -> void:
	var state: RefCounted = main._state
	_said(main, "the page: " + "\n[shot] song:   ".join(Sheet.describe(state.song_draft)))
	var waiting: Array = state.song_written
	_said(main, "%d waiting at the mic" % waiting.size())
	for s: Dictionary in waiting:
		_said(main, "  waiting: " + "\n[shot] song:   ".join(Sheet.describe(s)))
	_said(main, "%d songs recorded (songs %d, song_beats %s), %d sheets:" % [state.songs, state.songs, state.song_beats, (state.song_sheets as Array).size()])
	for n in (state.song_sheets as Array).size():
		_said(main, "  song %d: %s" % [n + 1, "\n[shot] song:   ".join(Sheet.describe(state.song_sheets[n]))])
	var trues := Sheet.true_bars(state)
	_said(main, "true bars put out: %d%s" % [trues.size(), "" if trues.is_empty() else ": " + "; ".join(PackedStringArray(trues.map(func(t: Dictionary) -> String:
		return "song %d %s (%s)" % [t["song"], t["card"], t["deed"]])))])


static func _print_score(main: Node) -> void:
	var state: RefCounted = main._state
	var read := Score.read(state, state.song_draft)
	_said(main, "the page reads: coherence %d (rhymes on %d of %d, themes %d of %d, %d flows, %d repeats), authenticity %d (%s), freshness %d (%d used before)" % [
		int(read.get("coherence", 0)), int(read.get("rhymed", 0)), int(read.get("joins", 0)), int(read.get("themed", 0)), int(read.get("verse_cards", 0)),
		int(read.get("flows", 0)), int(read.get("repeats", 0)), int(read.get("authenticity", 0)), read.get("standing", {}), int(read.get("freshness", 0)), int(read.get("used_before", 0))])
	var sheets: Array = state.song_sheets
	if sheets.is_empty():
		return
	var last: Dictionary = sheets[-1]
	var s: Dictionary = last.get("score", {})
	_said(main, "song %d ('%s'): %s" % [sheets.size(), last.get("title", "a freestyle" if last.get("freestyle", false) else "?"), Score.line(s)])
	if s.has("standing"):
		_said(main, "  cards %s; rhymes on %d of %d, themes %d of %d, %d flows, %d repeats; %d used before; take %s" % [s["standing"], int(s["rhymed"]), int(s["joins"]),
			int(s["themed"]), int(s["verse_cards"]), int(s["flows"]), int(s["repeats"]), int(s["used_before"]), last.get("take", {})])
	for which: String in ["helped", "hurt"]:
		var h: Dictionary = s.get(which, {})
		if not h.is_empty():
			_said(main, "  most %s: %s %d line %d '%s' (%s, about %+.1f of the total)" % [which, h["row"], int(h["i"]) + 1, int(h["line"]) + 1, h["text"], h["why"], float(h["by"])])


# ------------------------------------------------------------------ proof

## Stepped (a picture run): the take's schedule, the voice's and the grid's, and the frames.
static func _stepped(main: Node) -> void:
	var c: Node = main._conductor
	var take: CanvasLayer = main._songs.take
	if not take.running or not c.stepped:
		_said(main, "steps: needs a take running on the stepped clock (song:mic in a picture run)")
		return
	# 1. Every syllable the voice holds against the take's own time for it and the grid's (worked out here from
	#    the tempo and swing, not with the clock's time_of).
	var lines: Array = c.voice._lines
	var worst_take := 0.0
	var worst_grid := 0.0
	var n := 0
	var short := 0
	for k in mini(lines.size(), take.plan.size()):
		var held: Array = lines[k]["syl"]
		var p: Dictionary = take.plan[k]
		if held.size() != (p["syl"] as Array).size():
			short += 1
			continue
		for j in held.size():
			var t := float(held[j]["t"])
			worst_take = maxf(worst_take, absf(t - float(p["times"][j])))
			var sixteenth := float(int(p["bar"]) * 16 + int(p["syl"][j][0]))
			var pair := floorf(sixteenth / 2.0)
			var straight := 2.0 * pair + (sixteenth - 2.0 * pair) * (1.0 + 0.5 * float(c.swing))
			worst_grid = maxf(worst_grid, absf(t - straight * 60.0 / float(c.bpm) / 4.0))
			n += 1
	_said(main, "steps: %d lines (%d of the take's), %d syllables held by the voice (%d lines not whole: a syllable with no sound file); against the take's time for each: worst %.6f ms; against the grid (bar x 16 + step, swing %.2f, %d BPM): worst %.6f ms" % [
		lines.size(), take.plan.size(), n, short, worst_take * 1000.0, c.swing, int(c.bpm), worst_grid * 1000.0])
	# 2. The take on to its end, a frame at a time: each syllable reached (the voice's `sung`) against its step.
	var reached: Array = []
	var on_sung := func(_who: String, _index: int, _text: String) -> void: reached.append(float(c.time))
	c.voice.sung.connect(on_sung)
	var all_t: Array = []
	for p: Dictionary in take.plan:
		all_t.append_array(p["times"])
	await take.run_to(take.end_t + 0.05)
	c.voice.sung.disconnect(on_sung)
	var late: Array = []
	for k in mini(reached.size(), all_t.size()):
		late.append((float(reached[k]) - float(all_t[k])) * 1000.0)
	_said(main, "steps: the frame each syllable was reached on, after its step: %s (a stepped frame is %.2f ms: nothing is heard in a stepped run)" % [BeatsSteps._stats(late), 1000.0 / 60.0])
	var gaps: Array = []
	for pr: Dictionary in take.presses:
		if String(pr["grade"]) != "flub":
			gaps.append(-float(pr["gap"]) * 1000.0)
	_said(main, "steps: presses %d (%s), each against its strong syllable: %s; %s" % [take.presses.size(), take.take, BeatsSteps._stats(gaps), Score.line(take.result)])


## Live: the song waiting, sung with the clock from the audio, the Voice bus captured.
static func _timing(main: Node, n_bars: int, skill: float) -> void:
	var c: Node = main._conductor
	var songs: Node = main._songs
	if (main._state.song_written as Array).is_empty():
		_said(main, "timing: no written song waiting")
		return
	var was_stepped: bool = c.stepped
	c.stepped = false
	songs.auto = skill
	var caps := [BeatsSteps._capture("Voice")]
	c.voice.journal = []
	c.voice.keep_journal = true
	await _to_mic(main)
	var take: CanvasLayer = songs.take
	if not take.running:
		_said(main, "timing: the take did not start")
		c.voice.keep_journal = false
		BeatsSteps._drop(caps)
		c.stepped = was_stepped
		return
	AudioServer.lock()
	(caps[0]["effect"] as AudioEffectCapture).clear_buffer()
	var p0: float = c.next_mix_time()
	AudioServer.unlock()
	var rate := AudioServer.get_mix_rate()
	var got := PackedVector2Array()
	var cap: AudioEffectCapture = caps[0]["effect"]
	var end: float = float(c.time_of(take.start_bar + n_bars, 0.0)) + 0.3
	var guard := Time.get_ticks_msec() + int((end - float(c.time) + 6.0) * 1000.0)
	while take.running and float(c.time) < end and Time.get_ticks_msec() < guard:
		await main.get_tree().process_frame
		var k := cap.get_frames_available()
		if k > 0:
			got.append_array(cap.get_buffer(k))
	c.voice.keep_journal = false
	var presses: Array = take.presses.duplicate()
	var judged: Dictionary = take.take.duplicate(true)
	var plan: Array = take.plan
	take.stop_take()
	BeatsSteps._drop(caps)
	c.stepped = was_stepped
	var voice := BeatsSteps._mono(got)
	_said(main, "timing: '%s' on %s (%d BPM, swing %.2f), live, count-in and %d bars sung, auto player %.2f; mixer %d Hz; captured %.3f s from song time %.4f s" % [
		take.sheet.get("title", ""), c.id, int(c.bpm), c.swing, n_bars, skill, int(rate), voice.size() / rate, p0])
	var sung_ms: Array = []
	var by_bar := {}
	for e: Dictionary in c.voice.journal:
		var syl_stream: AudioStreamWAV = e["stream"]
		var spcm := syl_stream.data
		var sframes := spcm.size() >> 1
		var pitch: float = e["pitch"]
		var start: float = (float(e["next_mix"]) - p0) * rate + c.LOOKAHEAD
		var j: float = (float(e["t"]) - p0) * rate + c.LOOKAHEAD
		var i0 := floori(j - 0.008 * rate)
		var tpl := PackedFloat32Array()
		tpl.resize(int(0.02 * rate))
		for k in tpl.size():
			var in_file: float = float(e["from"]) + (i0 + k - start) * pitch / rate
			tpl[k] = BeatsSteps._sample(spcm, sframes, in_file * syl_stream.mix_rate, false)
		var found := BeatsSteps._align(voice, i0, tpl, int(0.012 * rate))
		var bar := floori(float(e["t"]) / (4.0 * float(c.spb)) + 0.000001)
		var text := "'%s' -" % e["text"]
		if float(found[1]) >= 0.0:
			var ms: float = float(found[0]) / rate * 1000.0
			sung_ms.append(ms)
			text = "'%s' %+.2f%s" % [e["text"], ms, " EDGE" if found[2] else ""]
		if not by_bar.has(bar):
			by_bar[bar] = []
		by_bar[bar].append(text)
	_said(main, "timing: each syllable as it sounded on the Voice bus, against its step, in ms (- not found):")
	for bar: int in by_bar:
		var p: int = bar - int(take.start_bar)
		var where := ""
		if p >= 0 and p < plan.size():
			where = "%s %d line %d" % [plan[p]["row"], int(plan[p]["i"]) + 1, int(plan[p]["line"]) + 1]
		print("[shot] song:   bar %d (%s): %s" % [p + 1, where, ";  ".join(PackedStringArray(by_bar[bar]))])
	var gaps: Array = []
	for pr: Dictionary in presses:
		if String(pr["grade"]) != "flub":
			gaps.append(-float(pr["gap"]) * 1000.0)
	_said(main, "timing: summary: %d syllables handed to the voice, %d found: %s; the auto player's presses against their syllables (on frames): %s; judged %s" % [
		(c.voice.journal as Array).size(), sung_ms.size(), BeatsSteps._stats(sung_ms), BeatsSteps._stats(gaps), judged])


## Live: what a player hears of the song waiting, count-in and n bars, to a WAV beside the --shot file.
static func _render(main: Node, n_bars: int, skill: float) -> void:
	var c: Node = main._conductor
	var songs: Node = main._songs
	var waiting: Array = main._state.song_written
	if waiting.is_empty():
		_said(main, "render: no written song waiting")
		return
	if main._place != "studio":
		main._travel_to("studio", true)
		await _frames(main, 2)
	var title := String(waiting[0].get("title", "song"))
	var slug := ""
	for ch in title.to_lower():
		slug += ch if Bars._alnum(ch.unicode_at(0)) else "_"
	var path: String = String(main._shot_path).get_base_dir().path_join("song_%s_%dbars_skill%d.wav" % [slug, n_bars, roundi(skill * 100.0)])
	var was_stepped: bool = c.stepped
	var was_volume: float = c.volume
	c.stepped = false
	c.set_volume(1.0)
	songs.auto = skill
	var rec := AudioEffectRecord.new()
	rec.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(0, rec)
	await _frames(main, 1)
	AudioServer.lock()               # the recording and the beat begin on the same chunk
	rec.set_recording_active(true)
	main._start_perform(main._building.mic.to)
	AudioServer.unlock()
	var take: CanvasLayer = songs.take
	var end: float = float(c.time_of(take.start_bar + n_bars, 0.0)) + 0.4
	var guard := Time.get_ticks_msec() + int((end - float(c.time) + 6.0) * 1000.0)
	while take.running and float(c.time) < end and Time.get_ticks_msec() < guard:
		await main.get_tree().process_frame
	var judged: Dictionary = take.take.duplicate(true)
	take.stop_take()
	await _frames(main, 20)          # what is still ringing
	rec.set_recording_active(false)
	var wav := rec.get_recording()
	for i in range(AudioServer.get_bus_effect_count(0) - 1, -1, -1):
		if AudioServer.get_bus_effect(0, i) == rec:
			AudioServer.remove_bus_effect(0, i)
	c.set_volume(was_volume)
	c.stepped = was_stepped
	var err := wav.save_to_wav(path) if wav else ERR_CANT_CREATE
	_said(main, "render: %s %s (%.2f s, %d Hz): '%s' on %s, count-in and %d bars, auto player %.2f: %s" % ["recorded" if err == OK else "FAILED to record", path,
		wav.get_length() if wav else 0.0, wav.mix_rate if wav else 0, title, c.id, n_bars, skill, judged])
