extends CanvasLayer
## The notebook (E on the yellow pad on the control room's coffee table; songs.gd): where he writes a song
## out of his bar cards (bars.gd) before he sings it at the booth mic.
##
## Left, the sheet: the beat, the hook, verse 1 and verse 2 (four cards each), the title, SAVE. Right, what
## can go in the row picked: the beats, the hooks, his cards (those that follow on from the card before
## first, Bars.follows, then the rest), the titles. Each card shows both its lines, whether it is his
## (STARTER, EARNED and by what, or CAP: a deed he has not done, which costs him authenticity), its rhyme
## family, its themes, its flow, TRUE if it claims a deed. Under both, how the song reads so far
## (song_score.gd read(): coherence, authenticity, freshness). Space hears a card: the voice raps it over
## the beat playing, the words lighting as they sound (song_lyrics.gd).
##
## Keys: on the sheet Up / Down pick a row, Enter (or a click) opens its list, Left / Right change the beat,
## the slot word or the title, Space hears, Delete takes the card out, Esc closes (the page is kept: the
## save's song_draft). On a list Up / Down, Enter (or a click) puts it in, Space hears, Esc or Tab goes back.
## Every word here is songs.json "words" (placeholders).
##
##   notebook.open(main)          closed()

signal closed

const Bars := preload("res://scripts/bars.gd")
const Sheet := preload("res://scripts/song_sheet.gd")
const Score := preload("res://scripts/song_score.gd")
const Lyrics := preload("res://scripts/song_lyrics.gd")
const FONT := preload("res://assets/fonts/Bungee-Regular.ttf")
const PAPER := Color("#f6f1e3")
const TICKET := Color("#f2d24a")
const INK := Color("#1c1a22")
const FAINT := Color(0.96, 0.94, 0.89, 0.5)
const SHADE := Color(14 / 255.0, 20 / 255.0, 40 / 255.0, 0.96)
const SHORT := Color("#e2483a")
const GREEN := Color("#3c9a55")
const ROWS := [
	{"kind": "beat", "row": "", "i": 0},
	{"kind": "hook", "row": "hook", "i": 0},
	{"kind": "card", "row": "verse1", "i": 0}, {"kind": "card", "row": "verse1", "i": 1},
	{"kind": "card", "row": "verse1", "i": 2}, {"kind": "card", "row": "verse1", "i": 3},
	{"kind": "card", "row": "verse2", "i": 0}, {"kind": "card", "row": "verse2", "i": 1},
	{"kind": "card", "row": "verse2", "i": 2}, {"kind": "card", "row": "verse2", "i": 3},
	{"kind": "title", "row": "", "i": 0},
	{"kind": "save", "row": "", "i": 0},
]

var main: Node
var sheet := {}               # the page (the save's song_draft while it is open)
var row := 0                  # ROWS
var focus := "sheet"          # "sheet" or "list"
var pick := 0                 # on the list
var items: Array = []         # the list: {"kind", "id", "group"} ("group": "follows", "rest"; a divider is {"kind": "divider"})

var _words := {}
var _title: Label
var _sub: Label
var _waiting: Label
var _rows_box: VBoxContainer
var _row_panels: Array = []
var _list_head: Label
var _list_sub: Label
var _scroll: ScrollContainer
var _list_box: VBoxContainer
var _tiles: Array = []        # one a list item (null for a divider)
var _meters := {}             # part: [bar back, bar, value label]
var _detail: Label
var _lyrics: Control
var _hear_label: Label
var _keys: Label
var _note: Label
var _note_t := 99.0
var _hear_rows: Array = []    # the lines being heard: [{"line", "bar"}]
var _scroll_to: Control       # the list item to bring into view once the list is laid out
var _scroll_wait := 0


func _init() -> void:
	layer = 12
	visible = false


func setup(main_node: Node) -> void:
	main = main_node
	_words = Score.data("words")
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 24.0
	panel.offset_top = 22.0
	panel.offset_right = -24.0
	panel.offset_bottom = -22.0
	var box := StyleBoxFlat.new()
	box.bg_color = SHADE
	box.set_corner_radius_all(16)
	box.set_border_width_all(4)
	box.border_color = Color("#14203f")
	box.content_margin_left = 26.0
	box.content_margin_right = 26.0
	box.content_margin_top = 16.0
	box.content_margin_bottom = 14.0
	panel.add_theme_stylebox_override("panel", box)
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 22)
	column.add_child(head)
	_title = _label(34, TICKET)
	head.add_child(_title)
	_sub = _label(22, PAPER)
	_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sub.clip_text = true
	head.add_child(_sub)
	_waiting = _label(18, FAINT)
	_waiting.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_waiting)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	_rows_box = VBoxContainer.new()
	_rows_box.custom_minimum_size = Vector2(760, 0)
	_rows_box.add_theme_constant_override("separation", 5)
	body.add_child(_rows_box)
	for k in ROWS.size():
		var p := PanelContainer.new()
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		p.gui_input.connect(_on_row_input.bind(k))
		_rows_box.add_child(p)
		_row_panels.append(p)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 4)
	body.add_child(right)
	_list_head = _label(22, TICKET)
	right.add_child(_list_head)
	_list_sub = _label(16, FAINT)
	_list_sub.clip_text = true
	right.add_child(_list_sub)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(_scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 7)
	_scroll.add_child(_list_box)

	var read := HBoxContainer.new()
	read.add_theme_constant_override("separation", 18)
	column.add_child(read)
	var read_name := _label(18, TICKET)
	read_name.text = _w("read")
	read_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	read.add_child(read_name)
	for part: String in ["coherence", "authenticity", "freshness"]:
		var m := VBoxContainer.new()
		m.custom_minimum_size = Vector2(250, 0)
		m.add_theme_constant_override("separation", 3)
		read.add_child(m)
		var top := HBoxContainer.new()
		m.add_child(top)
		var name_label := _label(16, PAPER)
		name_label.text = _w(part)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(name_label)
		var value := _label(16, PAPER)
		top.add_child(value)
		var back := ColorRect.new()
		back.color = Color(1, 1, 1, 0.12)
		back.custom_minimum_size = Vector2(0, 12)
		m.add_child(back)
		var bar := ColorRect.new()
		bar.color = TICKET
		back.add_child(bar)
		_meters[part] = [back, bar, value]
	_detail = _label(15, FAINT)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	read.add_child(_detail)

	var hear := HBoxContainer.new()
	hear.custom_minimum_size = Vector2(0, 74)
	hear.add_theme_constant_override("separation", 16)
	column.add_child(hear)
	_hear_label = _label(16, TICKET)
	_hear_label.custom_minimum_size = Vector2(120, 0)
	_hear_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hear.add_child(_hear_label)
	_lyrics = Lyrics.new()
	_lyrics.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lyrics.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hear.add_child(_lyrics)
	var foot := HBoxContainer.new()
	column.add_child(foot)
	_note = _label(17, SHORT)
	_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_note)
	_keys = _label(15, FAINT)
	foot.add_child(_keys)


func is_open() -> bool:
	return visible


## Open on the page he left (or a fresh one on the first beat there is), the beat playing.
func open() -> void:
	var state: RefCounted = main._state
	sheet = state.song_draft if not (state.song_draft as Dictionary).is_empty() else {}
	if sheet.is_empty() or main._conductor.sheet_of(String(sheet.get("beat", ""))).is_empty():
		var all: Array = main._conductor.beats()
		sheet = Sheet.blank(String(all[0]) if not all.is_empty() else "", int(main._day) + 1)
		state.song_draft = sheet
	Sheet.refresh(state, sheet)
	row = 1 if (sheet.get("hook", []) as Array).is_empty() else _first_empty()
	focus = "sheet"
	pick = 0
	_hear_rows = []
	_lyrics.set_rows([])
	visible = true
	_play_beat()
	_build_list()
	_refresh()


## Put it away; the page stays the save's draft.
func close() -> void:
	if not visible:
		return
	visible = false
	main._conductor.voice.stop()
	main._conductor.stop(1.0)
	closed.emit()


# ------------------------------------------------------------------ what he does

## Pick a row of the sheet.
func select_row(k: int) -> void:
	row = clampi(k, 0, ROWS.size() - 1)
	focus = "sheet"
	_build_list()
	_refresh()


## Enter on the sheet: the row's list (or SAVE).
func enter() -> void:
	if focus == "list":
		choose(pick)
		return
	var r: Dictionary = ROWS[row]
	if r["kind"] == "save":
		save()
		return
	_build_list()
	focus = "list"
	pick = _first_pickable(_current_index())
	_refresh()


## Put list item `k` in the row (and on to the next row that is empty).
func choose(k: int) -> void:
	if k < 0 or k >= items.size() or items[k]["kind"] == "divider":
		return
	var it: Dictionary = items[k]
	var r: Dictionary = ROWS[row]
	match String(it["kind"]):
		"beat":
			sheet["beat"] = String(it["id"])
			_play_beat()
		"hook":
			Sheet.put(main._state, sheet, "hook", 0, "hook_%s_a" % String(it["id"]))
		"card":
			Sheet.put(main._state, sheet, String(r["row"]), int(r["i"]), String(it["id"]))
		"title":
			sheet["title"] = String(it["id"])
	focus = "sheet"
	if String(it["kind"]) in ["hook", "card"]:
		row = _first_empty() if _first_empty() != -1 else row
	elif String(it["kind"]) == "title":
		row = ROWS.size() - 1
	_changed()


## Left / Right on the sheet: the beat, the slot word, the title.
func change(way: int) -> void:
	var r: Dictionary = ROWS[row]
	match String(r["kind"]):
		"beat":
			var all: Array = main._conductor.beats()
			if all.is_empty():
				return
			sheet["beat"] = String(all[posmod(all.find(String(sheet.get("beat", ""))) + way, all.size())])
			_play_beat()
		"title":
			var all := Sheet.titles(sheet)
			if all.is_empty():
				return
			sheet["title"] = String(all[posmod(all.find(String(sheet.get("title", ""))) + way, all.size())])
		"card":
			var words := Sheet.words_for(main._state, sheet, String(r["row"]), int(r["i"]))
			if words.size() < 2:
				return
			var now := String(Sheet.at(sheet, String(r["row"]), int(r["i"])).get("slot", ""))
			var at := 0
			for n in words.size():
				if String(words[n]["id"]) == now:
					at = n
			Sheet.set_word(main._state, sheet, String(r["row"]), int(r["i"]), String(words[posmod(at + way, words.size())]["id"]))
		_:
			return
	_changed()


## The slot word by id (a --do step).
func set_word(word: String) -> void:
	var r: Dictionary = ROWS[row]
	if r["kind"] == "card":
		Sheet.set_word(main._state, sheet, String(r["row"]), int(r["i"]), word)
		_changed()


## Delete: the card (or the hook) out of the row.
func take_out() -> void:
	var r: Dictionary = ROWS[row]
	if r["kind"] in ["card", "hook"]:
		Sheet.take_out(sheet, String(r["row"]), int(r["i"]))
		_changed()


## SAVE THE SONG: with every slot filled it goes to the booth mic (the save's song_written) and the page is
## cleared; else it says what is missing.
func save() -> bool:
	if not Sheet.complete(sheet):
		_say(_w("save_not_yet"))
		return false
	var state: RefCounted = main._state
	Sheet.refresh(state, sheet)
	var done: Dictionary = sheet.duplicate(true)
	done["written"] = true
	done["day"] = int(main._day) + 1
	state.song_written.append(done)
	state.song_draft = {}
	sheet = {}
	state.deed("song_written")      # bars: a deed (deeds.json)
	state.touch()
	print("[use] notebook: '%s' written on %s (%d waiting at the mic)" % [done["title"], done["beat"], (state.song_written as Array).size()])
	close()
	if main._video and main._video.has_method("toast"):
		main._video.toast(_w("saved").replace("{title}", String(done["title"])))
	return true


## Space: the voice raps the picked card (or the row's) over the beat, from the next bar.
func hear() -> void:
	var cid := ""
	var r: Dictionary = ROWS[row]
	if focus == "list" and pick < items.size():
		var it: Dictionary = items[pick]
		if it["kind"] == "card":
			cid = String(it["id"])
		elif it["kind"] == "hook":
			cid = "hook_%s_a" % String(it["id"])
	elif r["kind"] == "hook":
		var e := Sheet.at(sheet, "hook", 0)
		cid = String(e.get("id", ""))
	elif r["kind"] == "card":
		cid = String(Sheet.at(sheet, String(r["row"]), int(r["i"])).get("id", ""))
	if cid == "":
		return
	hear_card(cid)


## The voice raps a card (both halves for a hook), each line on a bar from the next one.
func hear_card(cid: String) -> void:
	var c: Node = main._conductor
	_play_beat()
	c.voice.stop()
	var lines: Array = []
	var ids := [cid]
	if Sheet.hook_name(cid) != "":
		ids = ["hook_%s_a" % Sheet.hook_name(cid), "hook_%s_b" % Sheet.hook_name(cid)]
	for one: String in ids:
		var e := _entry_for(one)
		lines.append_array(e.get("lines", []))
	var bar := int(c.bar) + 1
	_hear_rows = []
	for k in lines.size():
		c.voice.rap(String(Score.data("song").get("who", "e")), lines[k]["syl"], bar + k, null)
		_hear_rows.append({"line": lines[k], "bar": bar + k})
	_show_hearing()


# ------------------------------------------------------------------ the list

func _build_list() -> void:
	items = []
	var r: Dictionary = ROWS[row]
	var state: RefCounted = main._state
	match String(r["kind"]):
		"beat":
			for b: String in main._conductor.beats():
				items.append({"kind": "beat", "id": b})
		"hook":
			var names := Sheet.hooks()
			names.sort_custom(func(a: String, b: String) -> bool: return _rank(state, "hook_%s_a" % a) < _rank(state, "hook_%s_a" % b))
			for n: String in names:
				items.append({"kind": "hook", "id": n})
		"card":
			var before := _before(String(r["row"]), int(r["i"]))
			var follows: Array = Bars.follows(before) if before != "" else []
			var all := Sheet.verse_cards()
			var first: Array = all.filter(func(cid: String) -> bool: return cid in follows)
			var rest: Array = all.filter(func(cid: String) -> bool: return not cid in follows)
			var order := func(a: String, b: String) -> bool:
				var ra := _rank(state, a)
				var rb := _rank(state, b)
				return ra < rb if ra != rb else all.find(a) < all.find(b)
			first.sort_custom(order)
			rest.sort_custom(order)
			for cid: String in first:
				items.append({"kind": "card", "id": cid, "group": "follows"})
			if not first.is_empty() and not rest.is_empty():
				items.append({"kind": "divider", "id": "", "group": ""})
			for cid: String in rest:
				items.append({"kind": "card", "id": cid, "group": "rest"})
		"title":
			for t: String in Sheet.titles(sheet, int(Score.data("song").get("titles", 5))):
				items.append({"kind": "title", "id": t})
	pick = _first_pickable(_current_index())
	_build_tiles()


## The card before a slot, as sung: the card before it in its verse ("" for the first of a verse).
func _before(r: String, i: int) -> String:
	if i <= 0:
		return ""
	return String(Sheet.at(sheet, r, i - 1).get("id", ""))


## His own first: earned, then starter, then cap.
func _rank(state: RefCounted, cid: String) -> int:
	match Bars.standing(state, cid):
		"earned":
			return 0
		"starter":
			return 1
	return 2


## The list item that is what the row has now (or -1).
func _current_index() -> int:
	var r: Dictionary = ROWS[row]
	for k in items.size():
		var it: Dictionary = items[k]
		match String(it["kind"]):
			"beat":
				if String(it["id"]) == String(sheet.get("beat", "")):
					return k
			"hook":
				if Sheet.hook_name(String(Sheet.at(sheet, "hook", 0).get("id", ""))) == String(it["id"]):
					return k
			"card":
				if String(Sheet.at(sheet, String(r["row"]), int(r["i"])).get("id", "")) == String(it["id"]):
					return k
			"title":
				if String(sheet.get("title", "")) == String(it["id"]):
					return k
	return -1


func _first_pickable(k: int) -> int:
	if k >= 0 and k < items.size() and items[k]["kind"] != "divider":
		return k
	for n in items.size():
		if items[n]["kind"] != "divider":
			return n
	return 0


## The first row with nothing in it (the hook, then the verses), -1 if none.
func _first_empty() -> int:
	for k in ROWS.size():
		var r: Dictionary = ROWS[k]
		if r["kind"] == "hook" and (sheet.get("hook", []) as Array).size() < 2:
			return k
		if r["kind"] == "card" and Sheet.at(sheet, String(r["row"]), int(r["i"])).is_empty():
			return k
	return ROWS.size() - 2 if String(sheet.get("title", "")) == "" else ROWS.size() - 1


func _build_tiles() -> void:
	for child in _list_box.get_children():
		_list_box.remove_child(child)
		child.queue_free()
	_tiles = []
	_scroll_to = null
	_scroll.scroll_vertical = 0
	for k in items.size():
		var it: Dictionary = items[k]
		if it["kind"] == "divider":
			var d := _label(16, FAINT)
			d.text = "%s" % _w("the_rest")
			_list_box.add_child(d)
			_tiles.append(null)
			continue
		var tile := PanelContainer.new()
		tile.mouse_filter = Control.MOUSE_FILTER_STOP
		tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tile.gui_input.connect(_on_tile_input.bind(k))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 3)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(col)
		match String(it["kind"]):
			"beat":
				var s: Dictionary = main._conductor.sheet_of(String(it["id"]))
				col.add_child(_ink(String(s.get("name", it["id"])), 20))
				col.add_child(_ink("%d BPM    %s" % [int(s.get("bpm", 0)), String(s.get("mood", "")).to_upper()], 15, 0.7))
			"title":
				col.add_child(_ink(String(it["id"]), 20))
			"hook":
				for half: String in ["a", "b"]:
					var e := _entry_for("hook_%s_%s" % [String(it["id"]), half])
					for line: Dictionary in e.get("lines", []):
						col.add_child(_ink(String(line["text"]).to_upper(), 16))
				col.add_child(_chips("hook_%s_a" % String(it["id"]), ""))
			"card":
				var e := _entry_for(String(it["id"]))
				for line: Dictionary in e.get("lines", []):
					col.add_child(_ink(String(line["text"]).to_upper(), 16))
				col.add_child(_chips(String(it["id"]), String(it.get("group", ""))))
		_list_box.add_child(tile)
		_tiles.append(tile)


## The card as it would go in: on its slot row, with the word already in that slot; else its own word.
func _entry_for(cid: String) -> Dictionary:
	var r: Dictionary = ROWS[row]
	var now := Sheet.at(sheet, String(r["row"]), int(r["i"])) if r["kind"] == "card" else {}
	if String(now.get("id", "")) == cid:
		return now
	for e: Variant in sheet.get("hook", []):
		if typeof(e) == TYPE_DICTIONARY and String(e.get("id", "")) == cid:
			return e
	return Sheet.entry(main._state, cid)


## A card's chips: whether it is his (and the deed), its rhyme, its themes, its flow, TRUE, FOLLOWS, IN THE SONG, HEAR.
func _chips(cid: String, group: String) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 4)
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var c := Bars.card(cid)
	var stand := Bars.standing(main._state, cid)
	var deed := _deed_text(c)
	match stand:
		"starter":
			flow.add_child(_chip(_w("starter"), PAPER.darkened(0.12), INK))
		"earned":
			flow.add_child(_chip("%s  %s" % [_w("earned"), deed], GREEN, PAPER))
		"cap":
			flow.add_child(_chip("%s  %s" % [_w("cap"), _w("needs").replace("{deed}", deed)], SHORT, PAPER))
	if bool(c.get("true", false)):
		flow.add_child(_chip(_w("true"), INK, TICKET))
	flow.add_child(_chip("%s %s" % [_w("rhyme"), String(c.get("rhyme", "")).to_upper()], Color(0.25, 0.3, 0.45), PAPER))
	var themes := Score.themes(cid)
	if not themes.is_empty():
		flow.add_child(_chip(" ".join(PackedStringArray(themes.map(func(t: String) -> String: return t.to_upper()))), Color(0.33, 0.27, 0.42), PAPER))
	for t: String in c.get("tags", []):
		if t in Bars.FLOWS:
			flow.add_child(_chip(String(_words.get("flows", {}).get(t, t.to_upper())), Color(0.2, 0.36, 0.4), PAPER))
	if group == "follows":
		flow.add_child(_chip(_w("follows"), TICKET, INK))
	if _in_song(cid):
		flow.add_child(_chip(_w("in_song"), Color(0.45, 0.45, 0.5), PAPER))
	var hear_chip := _chip(_w("hear"), Color(0.1, 0.1, 0.13), TICKET)
	hear_chip.mouse_filter = Control.MOUSE_FILTER_STOP
	hear_chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hear_chip.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().set_input_as_handled()
			hear_card(cid))
	flow.add_child(hear_chip)
	return flow


## "SHOT FIRED", "SHOT FIRED X3" (the deed that unlocks a card, for people).
func _deed_text(c: Dictionary) -> String:
	if not c.has("unlock"):
		return ""
	var deed := String(c["unlock"]["deed"]).replace("_", " ").to_upper()
	var n := int(c["unlock"]["count"])
	return deed if n <= 1 else "%s X%d" % [deed, n]


func _in_song(cid: String) -> bool:
	for c: Dictionary in Sheet.cards(sheet):
		if String(c["card"].get("id", "")) == cid:
			return true
	return false


# ------------------------------------------------------------------ the screen

func _changed() -> void:
	main._state.song_draft = sheet
	_build_list()
	_refresh()


func _refresh() -> void:
	if not visible:
		return
	var c: Node = main._conductor
	_title.text = _w("head")
	var t := String(sheet.get("title", ""))
	_sub.text = "%s    %s" % [t if t != "" else _w("untitled"), c.name_of(String(sheet.get("beat", "")))]
	var waiting := (main._state.song_written as Array).size()
	_waiting.text = _w("waiting").replace("{n}", str(waiting)) if waiting > 0 else ""
	for k in ROWS.size():
		_fill_row(k)
	var r: Dictionary = ROWS[row]
	match String(r["kind"]):
		"beat":
			_list_head.text = _w("beat")
			_list_sub.text = ""
		"hook":
			_list_head.text = _w("pick_hook")
			_list_sub.text = ""
		"card":
			_list_head.text = _w("for_slot").replace("{where}", Sheet.where(String(r["row"]), int(r["i"]), _words))
			var before := Sheet.at(sheet, String(r["row"]), int(r["i"]) - 1) if int(r["i"]) > 0 else {}
			var lines: Array = before.get("lines", [])
			_list_sub.text = _w("after").replace("{line}", String(lines[1]["text"]).to_upper()) if lines.size() > 1 else ""
		"title":
			_list_head.text = _w("title")
			_list_sub.text = ""
		"save":
			_list_head.text = _w("save") if Sheet.complete(sheet) else _w("save_not_yet")
			_list_sub.text = ""
	for k in _tiles.size():
		var tile: PanelContainer = _tiles[k]
		if tile == null:
			continue
		var on := focus == "list" and k == pick
		var now := k == _current_index()
		tile.add_theme_stylebox_override("panel", _paper(TICKET if now else (PAPER.lerp(TICKET, 0.3) if on else PAPER), on))
	if focus == "list" and pick < _tiles.size() and _tiles[pick] != null:
		_scroll_to = _tiles[pick]
		_scroll_wait = 2
	var read := Score.read(main._state, sheet)
	for part: String in _meters:
		var m: Array = _meters[part]
		var v := int(read.get(part, 0))
		(m[2] as Label).text = str(v) if Sheet.filled(sheet) > 0 else "-"
		(m[1] as ColorRect).color = TICKET if v >= int(Score.data("score").get("levels", {}).get("low", 40)) else SHORT
		(m[1] as ColorRect).set_meta("value", v if Sheet.filled(sheet) > 0 else 0)
	var stand: Dictionary = read.get("standing", {})
	_detail.text = _w("detail").replace("{r}", str(int(read.get("rhymed", 0)))).replace("{j}", str(int(read.get("joins", 0)))).replace("{t}", str(int(read.get("themed", 0)))).replace("{n}", str(int(read.get("verse_cards", 0)))).replace("{f}", str(int(read.get("flows", 0)))).replace("{cap}", str(int(stand.get("cap", 0)) + int(stand.get("cap_true", 0)))).replace("{true}", str(int(stand.get("earned_true", 0))))
	_keys.text = _w("keys_cards") if focus == "list" else _w("keys_sheet")
	_show_hearing()


## One row of the sheet.
func _fill_row(k: int) -> void:
	var p: PanelContainer = _row_panels[k]
	for child in p.get_children():
		p.remove_child(child)
		child.queue_free()
	var r: Dictionary = ROWS[k]
	var on := k == row
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(line)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(112, 0)
	left.add_theme_constant_override("separation", 3)
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(left)
	var tag := _label(15, TICKET if on else FAINT)
	left.add_child(tag)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(col)
	var look := StyleBoxFlat.new()
	look.bg_color = Color(1, 1, 1, 0.1) if on else Color(1, 1, 1, 0.035)
	look.set_corner_radius_all(6)
	look.set_border_width_all(3 if on else 0)
	look.border_color = TICKET if focus == "sheet" else TICKET.darkened(0.35)
	look.content_margin_left = 10.0
	look.content_margin_right = 10.0
	look.content_margin_top = 4.0
	look.content_margin_bottom = 4.0
	p.add_theme_stylebox_override("panel", look)
	var stand := ""
	match String(r["kind"]):
		"beat":
			tag.text = _w("beat")
			col.add_child(_text("<  %s  >" % main._conductor.name_of(String(sheet.get("beat", ""))) if on else main._conductor.name_of(String(sheet.get("beat", ""))), 17, PAPER))
		"hook":
			tag.text = _w("hook")
			var hook: Array = sheet.get("hook", [])
			if hook.size() < 2:
				col.add_child(_text(_w("pick_hook"), 16, FAINT))
			else:
				for e: Dictionary in hook:
					col.add_child(_text(String(e["lines"][0]["text"]).to_upper(), 15, PAPER))
				stand = _worst(hook)
		"card":
			tag.text = "%s  %d" % [_w(String(r["row"])), int(r["i"]) + 1]
			var e := Sheet.at(sheet, String(r["row"]), int(r["i"]))
			if e.is_empty():
				col.add_child(_text(_w("pick_card"), 16, FAINT))
			else:
				for l: Dictionary in e.get("lines", []):
					col.add_child(_text(String(l["text"]).to_upper(), 15, PAPER))
				stand = String(e.get("standing", ""))
				if String(e.get("slot", "")) != "" and Sheet.words_for(main._state, sheet, String(r["row"]), int(r["i"])).size() > 1:
					var word := _text("<  %s  >" % _slot_text(e) if on else _slot_text(e), 14, TICKET)
					word.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
					col.add_child(word)
		"title":
			tag.text = _w("title")
			var t := String(sheet.get("title", ""))
			col.add_child(_text(("<  %s  >" % t if on else t) if t != "" else _w("pick_hook"), 17, PAPER if t != "" else FAINT))
		"save":
			tag.text = ""
			var ready := Sheet.complete(sheet)
			var go := _text(("ENTER  " if on else "") + (_w("save") if ready else _w("save_not_yet")), 18, INK if ready else FAINT)
			col.add_child(go)
			look.bg_color = TICKET if ready else Color(1, 1, 1, 0.06)
			look.border_color = INK if on and ready else look.border_color
	if stand != "":
		var chip := _chip(_w(stand), {"starter": PAPER.darkened(0.12), "earned": GREEN, "cap": SHORT}.get(stand, PAPER), INK if stand == "starter" else PAPER)
		chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		left.add_child(chip)


## The hook's standing: cap if either half is, else earned if either is, else starter.
func _worst(hook: Array) -> String:
	var all := hook.map(func(e: Dictionary) -> String: return String(e.get("standing", "")))
	return "cap" if "cap" in all else ("earned" if "earned" in all else "starter")


func _slot_text(e: Dictionary) -> String:
	var c := Bars.card(String(e["id"]))
	if not c.has("slot"):
		return ""
	for e2: Dictionary in Bars.word_list(String(c["slot"]["from"])).get("entries", []):
		if String(e2["id"]) == String(e["slot"]):
			return String(e2["text"]).to_upper()
	return String(e["slot"]).to_upper()


func _show_hearing() -> void:
	if _hear_rows.is_empty():
		_hear_label.text = ""
		_lyrics.set_rows([])
		return
	var c: Node = main._conductor
	var now: float = c.time
	var last: Dictionary = _hear_rows[-1]
	if not c.playing or now > float(c.time_of(int(last["bar"]) + 1, 0.0)) + 0.2:
		_hear_rows = []
		_hear_label.text = ""
		_lyrics.set_rows([])
		return
	var first := 0
	for k in range(0, _hear_rows.size(), 2):        # the couplet being heard (the next one once its bar starts)
		if now >= float(c.time_of(int(_hear_rows[k]["bar"]), 0.0)) - 0.1:
			first = k
	var rows: Array = []
	for k in range(first, mini(first + 2, _hear_rows.size())):
		rows.append(Lyrics.row(_hear_rows[k]["line"], int(_hear_rows[k]["bar"]), c, 21))
	if rows.size() != _lyrics.rows.size() or (not rows.is_empty() and String(rows[0]["text"]) != String(_lyrics.rows[0]["text"])):
		_lyrics.set_rows(rows)
	_hear_label.text = _w("hearing")


func _process(delta: float) -> void:
	if not visible:
		return
	_note_t += delta
	_note.modulate.a = clampf(3.0 - _note_t, 0.0, 1.0)
	_lyrics.now = main._conductor.time
	for part: String in _meters:
		var m: Array = _meters[part]
		var back: ColorRect = m[0]
		(m[1] as ColorRect).size = Vector2(back.size.x * int((m[1] as ColorRect).get_meta("value", 0)) / 100.0, back.size.y)
	if not _hear_rows.is_empty():
		_show_hearing()
	if _scroll_to != null:
		_scroll_wait -= 1
		if _scroll_wait <= 0:
			if is_instance_valid(_scroll_to) and _list_box.is_ancestor_of(_scroll_to):
				_scroll.ensure_control_visible(_scroll_to)
			_scroll_to = null


func _say(text: String) -> void:
	_note.text = text
	_note_t = 0.0


func _play_beat() -> void:
	var b := String(sheet.get("beat", ""))
	var c: Node = main._conductor
	if b != "" and (not c.playing or c.id != b or float(c._fade_from) >= 0.0):      # (fading out: from the top again)
		c.play(b, 0)


# ------------------------------------------------------------------ input

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.pressed:
		return
	get_viewport().set_input_as_handled()        # while the notebook is up, no key reaches the game
	var key: int = event.physical_keycode
	if event.echo and not key in [KEY_UP, KEY_DOWN, KEY_W, KEY_S]:
		return
	match key:
		KEY_ESCAPE:
			if focus == "list":
				focus = "sheet"
				_refresh()
			else:
				close()
		KEY_TAB:
			focus = "sheet" if focus == "list" else "list"
			if focus == "list":
				pick = _first_pickable(_current_index())
			_refresh()
		KEY_ENTER, KEY_KP_ENTER:
			enter()
		KEY_SPACE:
			hear()
		KEY_DELETE, KEY_BACKSPACE:
			if focus == "sheet":
				take_out()
		KEY_UP, KEY_W, KEY_DOWN, KEY_S:
			var way := -1 if key in [KEY_UP, KEY_W] else 1
			if focus == "list":
				_move_pick(way)
			else:
				select_row(posmod(row + way, ROWS.size()))
		KEY_LEFT, KEY_A, KEY_RIGHT, KEY_D:
			if focus == "sheet":
				change(-1 if key in [KEY_LEFT, KEY_A] else 1)


func _move_pick(way: int) -> void:
	if items.is_empty():
		return
	var k := pick
	for n in items.size():
		k = posmod(k + way, items.size())
		if items[k]["kind"] != "divider":
			break
	pick = k
	_refresh()


## Move the list's pick to item `k` (a --do step).
func point(k: int) -> void:
	focus = "list"
	pick = _first_pickable(clampi(k, 0, maxi(items.size() - 1, 0)))
	_refresh()


func _on_row_input(event: InputEvent, k: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		if k == row and ROWS[k]["kind"] in ["beat", "title"] and focus == "sheet":
			change(1)                    # a click on the picked beat or title: the next one
			return
		if k == row and ROWS[k]["kind"] == "card" and focus == "sheet" and String(Sheet.at(sheet, String(ROWS[k]["row"]), int(ROWS[k]["i"])).get("slot", "")) != "":
			change(1)                    # ...on the picked card with a slot: the next word
			return
		select_row(k)
		if ROWS[k]["kind"] == "save":
			save()
		else:
			enter()


func _on_tile_input(event: InputEvent, k: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		pick = k
		choose(k)


# ------------------------------------------------------------------ small things

func _w(key: String) -> String:
	return String(_words.get(key, key.to_upper()))


func _label(size: int, colour: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _text(text: String, size: int, colour: Color) -> Label:
	var label := _label(size, colour)
	label.add_theme_constant_override("outline_size", 0 if colour == INK else 4)
	label.text = text
	label.clip_text = true
	return label


## Dark ink on a paper card.
func _ink(text: String, size: int, alpha := 1.0) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(INK, alpha))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _chip(text: String, bg: Color, fg: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var look := StyleBoxFlat.new()
	look.bg_color = bg
	look.set_corner_radius_all(4)
	look.content_margin_left = 7.0
	look.content_margin_right = 7.0
	look.content_margin_top = 1.0
	look.content_margin_bottom = 1.0
	chip.add_theme_stylebox_override("panel", look)
	var label := Label.new()
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", fg)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text
	chip.add_child(label)
	return chip


func _paper(colour: Color, on: bool) -> StyleBoxFlat:
	var look := StyleBoxFlat.new()
	look.bg_color = colour
	look.set_corner_radius_all(6)
	look.set_border_width_all(5 if on else 2)
	look.border_color = INK if on else Color(0.1, 0.1, 0.13)
	look.shadow_color = Color(0, 0, 0, 0.45)
	look.shadow_size = 3
	look.shadow_offset = Vector2(2, 3)
	look.content_margin_left = 12.0
	look.content_margin_right = 12.0
	look.content_margin_top = 7.0
	look.content_margin_bottom = 7.0
	return look
