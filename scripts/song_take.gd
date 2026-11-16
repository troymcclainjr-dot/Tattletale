extends CanvasLayer
## A written song sung at the booth mic (songs.gd starts it when he steps up with one waiting): a count-in
## bar, then verse 1, the hook, verse 2, the hook on the beat's clock, each card two bars (a line a bar),
## 24 bars sung. The voice raps every line on its bar (rap_voice.gd, his mouth with it); the couplet being
## sung is on screen with each syllable lighting as it sounds, the next one under it (song_lyrics.gd).
##
## He presses Space on the strong syllables (stress 2), judged as the music video's moves are
## (video_take.gd; songs.json "take"): the nearest strong syllable still due within `good` seconds is a hit,
## within `perfect` a PERFECT (worth perfect_value, a GOOD good_value); one let pass `good` seconds is a MISS;
## a press with none due is OFF BEAT. Flow is 100 x points / judged, less `flub` an OFF BEAT. A strong
## syllable not yet hit `grace` seconds after its step is sounded duck_db softer (an AudioEffectAmplify of
## this take's on the Voice bus) until it is hit or `duck_for` seconds have gone; a MISS slips his face to
## slip_face for slip_beats beats.
##
## Esc stops the take: nothing recorded, the song still waiting. At the end the song is recorded
## (player_state.gd record_song, its sheet with the score: song_score.gd) and the score is shown until
## Enter. Either way `finished(recorded)`; songs.gd then steps him away from the mic.

signal finished(recorded: bool)

const Sheet := preload("res://scripts/song_sheet.gd")
const Score := preload("res://scripts/song_score.gd")
const Lyrics := preload("res://scripts/song_lyrics.gd")
const FONT := preload("res://assets/fonts/Bungee-Regular.ttf")
const PAPER := Color("#f6f1e3")
const TICKET := Color("#f2d24a")
const INK := Color("#1c1a22")
const FAINT := Color(0.96, 0.94, 0.89, 0.5)
const SHADE := Color(14 / 255.0, 20 / 255.0, 40 / 255.0, 0.94)
const SHORT := Color("#e2483a")

var main: Node
var sheet := {}               # the song (the save's song_written[0])
var running := false
var auto := -1.0              # a --do step's player, 0 .. 1 (below 0: the keys)
var seed_value := 0
var plan: Array = []          # each line sung: {"row", "i", "line", "bar", "id", "text", "syl", "times", "marks", "key"}
var strong: Array = []        # each strong syllable: {"t", "p" (its line in plan), "k", "state" ("due", "hit", "miss"), "grade"}
var take := {}                # {"points", "judged", "flubs", "perfect", "good", "missed", "lines": {key: {"points", "judged", "flubs"}}}
var result := {}              # the score, once recorded
var count_bar := 0            # the count-in bar (the clock's bars)
var start_bar := 0            # the first bar sung
var end_t := 0.0              # the clock's time it is over
var presses: Array = []       # each press: {"t" (the clock's), "grade", "gap"}

var _set := {}                # songs.json "take"
var _words := {}
var _rng := RandomNumberGenerator.new()
var _quarter := -1
var _duck: AudioEffectAmplify
var _slip_until := -1.0
var _section := ""
var _shown_card := -1
var _judge_t := 99.0
var _root: Control
var _top: Array = []          # the REC line and the flow, hidden while the score is up
var _rec: Label
var _flow: Label
var _counts: Label
var _count: Label
var _judge: Label
var _lyrics: Control
var _next: Control
var _lyric_box: PanelContainer
var _panel: PanelContainer
var _score_rows := {}         # part: [bar back, bar, value]
var _score_title: Label
var _total: Label
var _helped: Label
var _helped_why: Label
var _hurt: Label
var _hurt_why: Label


func _init() -> void:
	layer = 9
	visible = false


func setup(main_node: Node) -> void:
	main = main_node
	_set = Score.data("take")
	_words = Score.data("words")
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var rec_box := HBoxContainer.new()
	rec_box.position = Vector2(34, 30)
	rec_box.add_theme_constant_override("separation", 12)
	_root.add_child(rec_box)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(18, 18)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var red := StyleBoxFlat.new()
	red.bg_color = Color("#e8392b")
	red.set_corner_radius_all(9)
	red.set_border_width_all(2)
	red.border_color = Color.BLACK
	dot.add_theme_stylebox_override("panel", red)
	rec_box.add_child(dot)
	_rec = _label(20, PAPER)
	rec_box.add_child(_rec)
	_top.append(rec_box)
	var right := VBoxContainer.new()
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right.offset_left = -420.0
	right.offset_right = -34.0
	right.offset_top = 22.0
	right.add_theme_constant_override("separation", 0)
	_root.add_child(right)
	_flow = _label(26, TICKET)
	_flow.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_flow)
	_counts = _label(15, FAINT)
	_counts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_counts)
	_top.append(right)
	_count = _label(150, TICKET)
	_count.set_anchors_preset(Control.PRESET_CENTER)
	_count.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_count.grow_vertical = Control.GROW_DIRECTION_BOTH
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.add_theme_constant_override("outline_size", 14)
	_root.add_child(_count)

	_lyric_box = PanelContainer.new()
	_lyric_box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_lyric_box.offset_left = 60.0
	_lyric_box.offset_right = -60.0
	_lyric_box.offset_top = -268.0
	_lyric_box.offset_bottom = -52.0
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.02, 0.02, 0.05, 0.62)
	back.set_corner_radius_all(12)
	back.content_margin_top = 8.0
	back.content_margin_bottom = 6.0
	_lyric_box.add_theme_stylebox_override("panel", back)
	_lyric_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_lyric_box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_lyric_box.add_child(col)
	_judge = _label(26, TICKET)
	_judge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_judge)
	_lyrics = Lyrics.new()
	_lyrics.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_lyrics)
	_next = Lyrics.new()
	_next.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_next.gap = 2.0
	_next.marks = false
	col.add_child(_next)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(1060, 0)
	var box := StyleBoxFlat.new()
	box.bg_color = SHADE
	box.set_corner_radius_all(16)
	box.set_border_width_all(4)
	box.border_color = Color("#14203f")
	box.content_margin_left = 34.0
	box.content_margin_right = 34.0
	box.content_margin_top = 22.0
	box.content_margin_bottom = 22.0
	_panel.add_theme_stylebox_override("panel", box)
	_panel.visible = false
	_root.add_child(_panel)
	var pc := VBoxContainer.new()
	pc.add_theme_constant_override("separation", 10)
	_panel.add_child(pc)
	_score_title = _label(30, TICKET)
	pc.add_child(_score_title)
	for part: String in Score.PARTS:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 16)
		pc.add_child(line)
		var name_label := _label(20, PAPER)
		name_label.text = _w(part)
		name_label.custom_minimum_size = Vector2(250, 0)
		line.add_child(name_label)
		var meter := ColorRect.new()
		meter.color = Color(1, 1, 1, 0.12)
		meter.custom_minimum_size = Vector2(0, 18)
		meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(meter)
		var bar := ColorRect.new()
		bar.color = TICKET
		meter.add_child(bar)
		var value := _label(24, PAPER)
		value.custom_minimum_size = Vector2(70, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(value)
		_score_rows[part] = [meter, bar, value]
	_total = _label(40, TICKET)
	pc.add_child(_total)
	_helped = _label(18, PAPER)
	_helped.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pc.add_child(_helped)
	_helped_why = _label(15, FAINT)
	pc.add_child(_helped_why)
	_hurt = _label(18, PAPER)
	_hurt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pc.add_child(_hurt)
	_hurt_why = _label(15, FAINT)
	pc.add_child(_hurt_why)
	var done := _label(18, FAINT)
	done.text = _w("done")
	done.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pc.add_child(done)


## The take or its score is on screen (the face and the booth's REC are this take's).
func showing() -> bool:
	return running or (visible and _panel.visible)


# ------------------------------------------------------------------ the take

## Sing `song` (a written sheet): the beat from the bar before its verse, every line handed to the voice.
func start(song: Dictionary) -> bool:
	var c: Node = main._conductor
	var beat := String(song.get("beat", ""))
	if c.sheet_of(beat).is_empty():
		var all: Array = c.beats()
		beat = String(all[0]) if not all.is_empty() else ""
	var beat_sheet: Dictionary = c.sheet_of(beat)
	if beat_sheet.is_empty():
		return false
	sheet = song
	var bars := maxi(int(beat_sheet.get("bars", 4)), 1)
	var verse := 0
	for s: Dictionary in beat_sheet.get("sections", []):
		if String(s.get("name", "")) == "verse":
			verse = int(s.get("bar", 0))
	count_bar = posmod(verse - 1, bars)
	start_bar = count_bar + 1
	if not c.play(beat, count_bar):
		return false
	_rng.seed = seed_value
	_quarter = -1
	plan = []
	strong = []
	presses = []
	result = {}
	take = {"points": 0.0, "judged": 0, "flubs": 0, "perfect": 0, "good": 0, "missed": 0, "lines": {}}
	var who := String(Score.data("song").get("who", "e"))
	var n := 0
	for p: Dictionary in Sheet.performed(sheet):
		var e: Dictionary = p["card"]
		var lines: Array = e.get("lines", [])
		for l in 2:
			var bar := start_bar + n
			n += 1
			if l >= lines.size():
				continue
			var line: Dictionary = lines[l]
			var syl: Array = []
			for s: Variant in line.get("syl", []):         # whole numbers again (a sheet from the save has floats)
				syl.append([int(s[0]), String(s[1]), int(s[2])])
			var times: Array = []
			var marks: Array = []
			for s: Array in syl:
				times.append(float(c.time_of(bar, float(s[0]))))
				marks.append("")
			var key := "%s:%d:%d" % [String(p["row"]), int(p["i"]), l]
			plan.append({"row": p["row"], "i": p["i"], "line": l, "bar": bar, "id": String(e.get("id", "")), "text": String(line.get("text", "")),
				"syl": syl, "times": times, "marks": marks, "key": key})
			for k in syl.size():
				if int(syl[k][2]) == 2:
					strong.append({"t": float(times[k]), "p": plan.size() - 1, "k": k, "state": "due", "grade": ""})
			c.voice.rap(who, syl, bar, main._actor)
	end_t = float(c.time_of(start_bar + n, 0.0))
	_add_duck()
	if main._actor.face:
		main._actor.face.talking = false      # his mouth moves with the voice alone
	_section = ""
	_shown_card = -1
	_slip_until = -1.0
	_panel.visible = false
	_lyric_box.visible = true
	for c2: Control in _top:
		c2.visible = true
	running = true
	visible = true
	_show()
	print("[use] mic: singing '%s' on %s: count-in bar %d, bars %d to %d, %d strong syllables" % [String(sheet.get("title", "")), beat, count_bar, start_bar, start_bar + n - 1, strong.size()])
	return true


## Space: a press, judged against the clock now.
func press() -> void:
	if not running:
		return
	var c: Node = main._conductor
	var now: float = c.time
	if now < float(c.time_of(count_bar, 0.0)) or now > end_t + 0.5:
		return
	var good := float(_set.get("good", 0.32))
	var best: Dictionary = {}
	var gap := INF
	for s: Dictionary in strong:
		if s["state"] == "due":
			var d := absf(float(s["t"]) - now)
			if d < gap:
				gap = d
				best = s
	if not best.is_empty() and gap <= good:
		var perfect := gap <= float(_set.get("perfect", 0.14))
		var value := float(_set.get("perfect_value", 1.0)) if perfect else float(_set.get("good_value", 0.6))
		best["state"] = "hit"
		best["grade"] = "perfect" if perfect else "good"
		plan[int(best["p"])]["marks"][int(best["k"])] = best["grade"]
		take["points"] = float(take["points"]) + value
		take["judged"] = int(take["judged"]) + 1
		take[best["grade"]] = int(take[best["grade"]]) + 1
		var l := _line_of(String(plan[int(best["p"])]["key"]))
		l["points"] = float(l["points"]) + value
		l["judged"] = int(l["judged"]) + 1
		presses.append({"t": now, "grade": best["grade"], "gap": float(best["t"]) - now})
		_judged(_w(String(best["grade"])), TICKET if perfect else PAPER)
	else:
		take["flubs"] = int(take["flubs"]) + 1
		var p := _plan_at(now)
		if p >= 0:
			var l := _line_of(String(plan[p]["key"]))
			l["flubs"] = int(l["flubs"]) + 1
		presses.append({"t": now, "grade": "flub", "gap": 0.0})
		_judged(_w("flub"), SHORT)


## A frame of the take: the auto player, the misses, the duck, his face, the screen; over at the end.
func tick() -> void:
	if not running:
		return
	var c: Node = main._conductor
	if not c.playing:
		stop_take()
		return
	var now: float = c.time
	if auto >= 0.0:
		_auto_play(now)
	var good := float(_set.get("good", 0.32))
	for s: Dictionary in strong:
		if s["state"] == "due" and now > float(s["t"]) + good:
			s["state"] = "miss"
			s["grade"] = "miss"
			plan[int(s["p"])]["marks"][int(s["k"])] = "miss"
			take["judged"] = int(take["judged"]) + 1
			take["missed"] = int(take["missed"]) + 1
			var l := _line_of(String(plan[int(s["p"])]["key"]))
			l["judged"] = int(l["judged"]) + 1
			_judged(_w("miss"), SHORT)
			_slip(now)
	var duck := false
	var grace := float(_set.get("grace", 0.03))
	var duck_for := float(_set.get("duck_for", 0.3))
	for s: Dictionary in strong:
		if s["state"] != "hit" and now > float(s["t"]) + grace and now < float(s["t"]) + duck_for:
			duck = true
	if _duck:
		_duck.volume_db = float(_set.get("duck_db", -10.0)) if duck else 0.0
	if _slip_until >= 0.0 and now >= _slip_until:
		_slip_until = -1.0
		_face(_section_face())
	if now >= end_t:
		_finish()
		return
	_show()


## Esc during the take: it stops, nothing is recorded, the song waits.
func stop_take() -> void:
	if not running:
		return
	running = false
	main._conductor.voice.stop()
	_drop_duck()
	visible = false
	if main._video and main._video.has_method("toast"):
		main._video.toast(_w("stopped").replace("{title}", String(sheet.get("title", ""))))
	print("[use] mic: take stopped; '%s' still waiting" % String(sheet.get("title", "")))
	finished.emit(false)


## The end of the song: recorded with its score, and the score on screen.
func _finish() -> void:
	running = false
	_drop_duck()
	var state: RefCounted = main._state
	Sheet.refresh(state, sheet)
	result = Score.score(state, sheet, take)
	sheet["score"] = result
	sheet["recorded"] = int(main._day) + 1
	sheet["take"] = {"perfect": take["perfect"], "good": take["good"], "missed": take["missed"], "flubs": take["flubs"], "auto": auto}
	for k in (state.song_written as Array).size():
		if is_same(state.song_written[k], sheet):
			state.song_written.remove_at(k)
			break
	state.record_song(String(sheet.get("beat", "")), sheet)
	var caps := 0
	for c: Dictionary in Sheet.cards(sheet):
		if String(c["card"].get("standing", "")) == "cap":
			caps += 1
	if caps > 0:
		state.deed("cap_used", caps)      # bars: a deed (deeds.json)
	main._save_game()
	main._conductor.stop(2.0)
	_lyric_box.visible = false
	_count.text = ""
	_show_score()
	print("[use] mic: '%s' recorded (song %d): %s" % [String(sheet.get("title", "")), int(state.songs), Score.line(result)])


## Enter on the score: done.
func close_score() -> void:
	if not _panel.visible:
		return
	_panel.visible = false
	visible = false
	finished.emit(true)


## Fast-forward the take on the stepped clock to `t` (a --do step): each step is what a picture-run frame does.
func run_to(t: float) -> void:
	var c: Node = main._conductor
	var n := 0
	while running and c.playing and float(c.time) < t:
		c._process(1.0 / 60.0)
		c.voice._process(1.0 / 60.0)
		tick()
		n += 1
		if n % 240 == 0:
			await main.get_tree().process_frame


# ------------------------------------------------------------------ the auto player

## A --do step's player at `auto` skill, as video_take.gd's: 1 hits every strong syllable on its step, 0
## presses nothing; between, each one is pressed (or not) and how far off is decided two beats ahead, seeded.
func _auto_play(now: float) -> void:
	var c: Node = main._conductor
	var s := clampf(auto, 0.0, 1.0)
	var ahead := 2.0 * float(c.spb)
	for one: Dictionary in strong:
		if one["state"] != "due":
			continue
		if not one.has("auto"):
			if float(one["t"]) - now > ahead:
				continue
			var press_it := _rng.randf() < pow(s, 0.7)
			var err := _rng.randfn(0.0, (1.0 - s) * 0.2)
			one["auto"] = {"press": press_it, "at": float(one["t"]) + err}
		var plan_one: Dictionary = one["auto"]
		if plan_one["press"] and now >= float(plan_one["at"]):
			plan_one["press"] = false
			press()
	var q := floori(float(c.beat) * 4.0)
	if now >= float(c.time_of(start_bar, 0.0)) and now < end_t and q != _quarter:
		_quarter = q
		if _rng.randf() < (1.0 - s) * 0.035:
			press()


# ------------------------------------------------------------------ the screen

func _show() -> void:
	var c: Node = main._conductor
	var now: float = c.time
	_lyrics.now = now
	_next.now = now
	var p := _plan_at(now)
	var card := -1 if p < 0 else p >> 1
	if now < float(c.time_of(start_bar, 0.0)):
		card = 0
	var section := _section_of(card)
	_rec.text = "%s   %s   %s" % [_w("rec"), String(sheet.get("title", "")), _w(section) if section != "" else ""]
	if section != _section:
		_section = section
		if _slip_until < 0.0:
			_face(_section_face())
	var judged := int(take["judged"])
	_flow.text = "%s  %s" % [_w("flow"), str(Score.flow_of(take)) if judged > 0 else "-"]
	_counts.text = "%s %d   %s %d   %s %d   %s %d" % [_w("perfect"), int(take["perfect"]), _w("good"), int(take["good"]), _w("miss"), int(take["missed"]), _w("flub"), int(take["flubs"])]
	var b: float = c.beat - float(count_bar) * 4.0
	_count.text = str(floori(b) + 1) if b >= 0.0 and b < 4.0 else ""
	_count.modulate.a = 1.0 - fposmod(b, 1.0) * 0.7
	if card != _shown_card:
		_shown_card = card
		_lyrics.set_rows(_rows_of(card, 30, false))
		_next.set_rows(_rows_of(card + 1, 19, true))
	main._bar_note.text = _w("mic_keys")
	_judge_t += 1.0 / 60.0 if c.stepped else get_process_delta_time()
	_judge.modulate.a = clampf(1.0 - (_judge_t - 0.35) / 0.4, 0.0, 1.0)


func _rows_of(card: int, size: int, dim: bool) -> Array:
	var out: Array = []
	for p in [card * 2, card * 2 + 1]:
		if p < 0 or p >= plan.size():
			continue
		var line: Dictionary = plan[p]
		var r := Lyrics.row({"text": line["text"], "syl": line["syl"]}, int(line["bar"]), main._conductor, size, dim)
		r["marks"] = line["marks"]
		out.append(r)
	return out


func _show_score() -> void:
	_score_title.text = _w("recorded").replace("{title}", String(sheet.get("title", "")))
	for part: String in Score.PARTS:
		var row: Array = _score_rows[part]
		var v := int(result.get(part, 0))
		(row[2] as Label).text = str(v)
		(row[1] as ColorRect).color = SHORT if v < int(Score.data("score").get("levels", {}).get("low", 40)) else TICKET
		(row[1] as ColorRect).set_meta("value", v)
	_total.text = "%s  %d" % [_w("total"), int(result.get("total", 0))]
	var why: Dictionary = _words.get("why", {})
	var helped: Dictionary = result.get("helped", {})
	var hurt: Dictionary = result.get("hurt", {})
	_helped.text = "%s   \"%s\"" % [_w("helped"), String(helped.get("text", "")).to_upper()] if not helped.is_empty() else ""
	_helped_why.text = "%s   %s" % [Sheet.where(String(helped.get("row", "")), int(helped.get("i", 0)), _words), String(why.get(String(helped.get("why", "")), ""))] if not helped.is_empty() else ""
	_hurt.text = "%s   \"%s\"" % [_w("hurt"), String(hurt.get("text", "")).to_upper()] if not hurt.is_empty() else ""
	_hurt_why.text = "%s   %s" % [Sheet.where(String(hurt.get("row", "")), int(hurt.get("i", 0)), _words), String(why.get(String(hurt.get("why", "")), ""))] if not hurt.is_empty() else ""
	_hurt.add_theme_color_override("font_color", SHORT.lightened(0.25))
	main._bar_note.text = ""          # the panel says ENTER  DONE
	for c2: Control in _top:
		c2.visible = false
	_panel.visible = true
	visible = true


func _process(_delta: float) -> void:
	if running:
		tick()
	if _panel.visible:
		for part: String in _score_rows:
			var row: Array = _score_rows[part]
			var back: ColorRect = row[0]
			(row[1] as ColorRect).size = Vector2(back.size.x * int((row[1] as ColorRect).get_meta("value", 0)) / 100.0, back.size.y)


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.pressed or event.echo:
		return
	if running:
		get_viewport().set_input_as_handled()        # Space and Esc are the take's; Left / Right do not change the beat
		match event.physical_keycode:
			KEY_SPACE:
				press()
			KEY_ESCAPE:
				stop_take()
	elif _panel.visible:
		get_viewport().set_input_as_handled()
		if event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE]:
			close_score()


# ------------------------------------------------------------------ small things

## The line sung at that time (its index in plan), -1 before the first.
func _plan_at(now: float) -> int:
	var c: Node = main._conductor
	var bar := floori(now / (4.0 * float(c.spb)) + 0.000001)
	var p := bar - start_bar
	if p < 0:
		return -1
	return mini(p, plan.size() - 1)


func _section_of(card: int) -> String:
	var order: Array = Sheet.ORDER
	var k := 0
	for part: String in order:
		var n := int(Sheet.SIZE[part])
		if card < k + n:
			return part
		k += n
	return String(order[-1])


## The face for the part being sung: songs.json take.faces, one a section in turn.
func _section_face() -> String:
	var faces: Array = _set.get("faces", ["focused"])
	var order: Array = Sheet.ORDER
	var k := 0
	var p := _plan_at(float(main._conductor.time))
	var card := maxi(p >> 1, 0)
	for n in order.size():
		k += int(Sheet.SIZE[order[n]])
		if card < k:
			return String(faces[n % faces.size()])
	return String(faces[0])


func _face(expression: String) -> void:
	if main._actor.face and main._actor.face.expression != expression:
		main._actor.face.set_expression(expression)


func _slip(now: float) -> void:
	_face(String(_set.get("slip_face", "nervous")))
	_slip_until = now + float(_set.get("slip_beats", 1.5)) * float(main._conductor.spb)


func _judged(text: String, colour: Color) -> void:
	_judge.text = text
	_judge.add_theme_color_override("font_color", colour)
	_judge_t = 0.0


func _line_of(key: String) -> Dictionary:
	var lines: Dictionary = take["lines"]
	if not lines.has(key):
		lines[key] = {"points": 0.0, "judged": 0, "flubs": 0}
	return lines[key]


func _add_duck() -> void:
	_drop_duck()
	_duck = AudioEffectAmplify.new()
	_duck.volume_db = 0.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Voice"), _duck)


func _drop_duck() -> void:
	if _duck == null:
		return
	var bus := AudioServer.get_bus_index("Voice")
	for i in range(AudioServer.get_bus_effect_count(bus) - 1, -1, -1):
		if AudioServer.get_bus_effect(bus, i) == _duck:
			AudioServer.remove_bus_effect(bus, i)
	_duck = null


func _w(key: String) -> String:
	return String(_words.get(key, key.to_upper()))


func _label(size: int, colour: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
