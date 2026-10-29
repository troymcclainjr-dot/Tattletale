extends PanelContainer
## #puzzle: the payphone puzzle panel (puzzles.js). The four puzzles run here and call back G:
##   G.puzzle_solved() when solved, G.penalty(4) on a wrong answer (+ the red flash via the
##   `penalized` signal), G.hang_up() for the Hang up button.

signal penalized(sec: int)

const T := preload("res://scripts/ui/hud_theme.gd")
const Wd := preload("res://scripts/ui/hud_widgets.gd")
const St := preload("res://scripts/ui/hud_state.gd")

const KEYS := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"]

var kind := ""
var focus = null
var _done := false
var _gen := 0                 # bumps on every show/hide; stale timers are dropped
var _timers: Array = []       # [seconds left, gen, Callable]
var _key_handler := Callable()
var _shakes: Array = []       # [MarginContainer, t]
var _lit := {}                # key -> seconds left lit (keypad)

var eye_l: Label
var title_l: Label
var sub_l: Label
var body: VBoxContainer
var msg_l: Label
var hang: Button
var _key_btn := {}
var _key_style: StyleBox
var _key_lit_style: StyleBox


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", T.box(T.PAPER, [0, 0, 0, 0], 0, 0, Color(0, 0, 0, 0), Vector2(8, 0), T.a(T.BLACK, 0.3)))
	var col := T.vbox(0)
	add_child(col)
	# header
	var hv := T.vbox(2)
	col.add_child(T.panel(T.box(T.INK, [14, 18, 12, 18]), hv))
	eye_l = T.label("PAYPHONE", T.ls(T.spaced(T.mono(), 2), 11, T.TICKET))
	hv.add_child(eye_l)
	title_l = T.label("", T.ls(T.disp(22), 22, T.PAPER, [], 1.1), HORIZONTAL_ALIGNMENT_LEFT, true)
	hv.add_child(T.tight(title_l))
	sub_l = T.label("", T.ls(T.body(500), 16, T.SUB_P, [], 1.25), HORIZONTAL_ALIGNMENT_LEFT, true)
	hv.add_child(T.margin(sub_l, 2))
	# body (#pz)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	body = T.vbox(12)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bm := T.margin(body, 16, 18, 16, 18)
	bm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(bm)
	# footer
	var fbox = T.box(Color(0, 0, 0, 0), [10, 18, 12, 18])
	fbox.dashed_top = T.a(T.INK, 0.3)
	var foot := T.hbox(12)
	col.add_child(T.panel(fbox, foot))
	var fl := T.label("Every second counts. The crime is still happening.", T.ls(T.mono(), 12, T.INK), HORIZONTAL_ALIGNMENT_LEFT, true)
	fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(fl)
	hang = Button.new()
	hang.text = "HANG UP"
	hang.theme_type_variation = "HangButton"
	hang.focus_mode = Control.FOCUS_NONE
	hang.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hang.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hang.pressed.connect(func(): St.call_g("hang_up"))
	foot.add_child(hang)
	_key_style = T.box(T.INK, [0, 0, 0, 0], 8, 0, Color(0, 0, 0, 0), Vector2(0, 3), T.KEY_SHADOW)
	_key_lit_style = T.box(T.TICKET, [0, 0, 0, 0], 8, 0, Color(0, 0, 0, 0), Vector2(0, 3), T.KEY_SHADOW)


# ------------------------------------------------------------------------------ control
func open(k: String, f) -> void:
	_reset()
	kind = k
	focus = f
	visible = true
	match k:
		"wires":
			_wires()
		"keypad":
			_keypad()
		"menu":
			_menu()
		"plate":
			_plate()
		_:
			_head("PAYPHONE", k, "")


func close() -> void:
	_reset()
	visible = false


func _reset() -> void:
	_gen += 1
	_timers.clear()
	_shakes.clear()
	_lit.clear()
	_key_btn.clear()
	_key_handler = Callable()
	_done = false
	kind = ""
	focus = null
	msg_l = null
	for ch in body.get_children():
		body.remove_child(ch)
		ch.queue_free()


## Keys forwarded by the game while in puzzle mode: "0".."9", "*", "#", "Backspace".
func key(k: String) -> void:
	if visible and _key_handler.is_valid():
		_key_handler.call(k)


func _alive() -> bool:
	if not visible or _done or kind == "":
		return false
	var pz = St.field(St.s(), "pz")
	return not bool(St.field(pz, "done", false))


func _solve() -> void:
	if _done:
		return
	_done = true
	St.call_g("puzzle_solved")


func _wrong() -> void:
	St.sfx("buzz")
	St.call_g("penalty", [4])
	penalized.emit(4)


func _after(sec: float, fn: Callable) -> void:
	_timers.append([sec, _gen, fn])


func _process(delta: float) -> void:
	if _timers.size():
		var due := []
		for t in _timers:
			t[0] -= delta
			if t[0] <= 0.0:
				due.append(t)
		for t in due:
			_timers.erase(t)
			if t[1] == _gen:
				(t[2] as Callable).call()
	if _shakes.size():
		var done := []
		for s in _shakes:
			s[1] += delta
			var u: float = s[1] / 0.35
			var off := 0.0
			if u < 0.25:
				off = lerpf(0, -6, u / 0.25)
			elif u < 0.5:
				off = lerpf(-6, 6, (u - 0.25) / 0.25)
			elif u < 0.75:
				off = lerpf(6, -3, (u - 0.5) / 0.25)
			elif u < 1.0:
				off = lerpf(-3, 0, (u - 0.75) / 0.25)
			else:
				done.append(s)
			var mc: MarginContainer = s[0]
			if is_instance_valid(mc):
				mc.add_theme_constant_override("margin_left", int(round(off)))
				mc.add_theme_constant_override("margin_right", -int(round(off)))
		for s in done:
			_shakes.erase(s)
	if _lit.size():
		for k in _lit.keys():
			_lit[k] -= delta
			if _lit[k] <= 0.0:
				_lit.erase(k)
				_set_lit(k, false)


# ------------------------------------------------------------------------------ helpers
func _head(eye: String, title: String, sub: String) -> void:
	eye_l.text = eye
	title_l.text = T.caps(title)
	sub_l.text = sub


func _add_msg() -> void:
	msg_l = T.label("", T.ls(T.mono(true), 14, T.INK))
	msg_l.custom_minimum_size.y = 20
	msg_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(msg_l)


## .pzmsg: cls "" | "bad" | "good"
func _msg(text: String, cls := "") -> void:
	if msg_l == null:
		return
	msg_l.text = text
	msg_l.label_settings.font_color = T.SIREN if cls == "bad" else (T.GO if cls == "good" else T.INK)


## A margin wrapper the .shake animation moves sideways.
func _shaker(child: Control) -> MarginContainer:
	var m := T.margin(child)
	m.mouse_filter = Control.MOUSE_FILTER_PASS
	return m


func _shake(m: MarginContainer) -> void:
	for s in _shakes:
		if s[0] == m:
			s[1] = 0.0
			return
	_shakes.append([m, 0.0])


func _keypad_grid(labels := {}) -> GridContainer:
	var pad := GridContainer.new()
	pad.columns = 3
	pad.add_theme_constant_override("h_separation", 8)
	pad.add_theme_constant_override("v_separation", 8)
	pad.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for k in KEYS:
		var b := Button.new()
		b.text = labels.get(k, k)
		b.theme_type_variation = "KeyButton"
		b.custom_minimum_size = Vector2(64, 56)
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		pad.add_child(b)
		_key_btn[k] = b
	return pad


func _set_lit(k: String, on: bool) -> void:
	var b: Button = _key_btn.get(k)
	if b == null or not is_instance_valid(b):
		return
	if on:
		for st in ["normal", "hover", "pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(st, _key_lit_style)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(c, T.INK)
	else:
		for st in ["normal", "hover", "pressed", "hover_pressed"]:
			b.remove_theme_stylebox_override(st)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			b.remove_theme_color_override(c)


# ------------------------------------------------------------------------------ 1) wires
## Rewire the payphone: rotate tiles until the handset connects to the line.
func _wires() -> void:
	_head("PAYPHONE · OUT OF ORDER", "Rewire the handset", "Click the tiles to turn them. Connect the phone on the left to the LINE on the right.")
	const R := 4
	const CN := 5
	const N := 1
	const E := 2
	const S_ := 4
	const WD := 8
	var opp := {1: 4, 2: 8, 4: 1, 8: 2}
	var rot := func(m: int) -> int: return ((m << 1) | (m >> 3)) & 15
	var r0 := randi() % R
	var path: Array = []
	var r := r0
	var c := 0
	var seen := {}
	while true:
		path.append([r, c])
		seen["%d,%d" % [r, c]] = true
		if c == CN - 1:
			break
		var opts: Array = []
		if r > 0 and not seen.has("%d,%d" % [r - 1, c]) and randf() < 0.45:
			opts.append([r - 1, c])
		if r < R - 1 and not seen.has("%d,%d" % [r + 1, c]) and randf() < 0.45:
			opts.append([r + 1, c])
		opts.shuffle()
		var nx: Array = opts[0] if (opts.size() and path.size() < 14) else [r, c + 1]
		r = nx[0]
		c = nx[1]
	var r_end: int = path[path.size() - 1][0]
	var dir_of := func(a: Array, b: Array) -> int:
		if b[0] < a[0]:
			return N
		if b[0] > a[0]:
			return S_
		if b[1] > a[1]:
			return E
		return WD
	var grid: Array = []
	for i in R:
		var row: Array = []
		for j in CN:
			row.append([5, 3, 7, 3, 5][randi() % 5])
		grid.append(row)
	for i in path.size():
		var p: Array = path[i]
		var inn: int = WD if i == 0 else opp[dir_of.call(path[i - 1], p)]
		var out: int = E if i == path.size() - 1 else dir_of.call(p, path[i + 1])
		grid[p[0]][p[1]] = inn | out
	var turns: Array = []
	for i in R:
		var row: Array = []
		row.resize(CN)
		row.fill(0)
		turns.append(row)
	var cur := func(i: int, j: int) -> int:
		var m: int = grid[i][j]
		for k in (turns[i][j] as int) % 4:
			m = rot.call(m)
		return m
	var powered := func() -> Dictionary:
		var on := {}
		if not (cur.call(r0, 0) & WD):
			return {"on": on, "ok": false}
		var q: Array = [[r0, 0]]
		on["%d,%d" % [r0, 0]] = true
		var ok := false
		while q.size():
			var ij: Array = q.pop_front()
			var i: int = ij[0]
			var j: int = ij[1]
			var m: int = cur.call(i, j)
			if i == r_end and j == CN - 1 and (m & E):
				ok = true
			for dd in [[N, -1, 0], [E, 0, 1], [S_, 1, 0], [WD, 0, -1]]:
				if not (m & dd[0]):
					continue
				var a2: int = i + dd[1]
				var b2: int = j + dd[2]
				if a2 < 0 or b2 < 0 or a2 >= R or b2 >= CN:
					continue
				if on.has("%d,%d" % [a2, b2]):
					continue
				if cur.call(a2, b2) & opp[dd[0]]:
					on["%d,%d" % [a2, b2]] = true
					q.append([a2, b2])
		return {"on": on, "ok": ok}
	while true:
		for i in R:
			for j in CN:
				turns[i][j] = randi() % 4
		if not powered.call()["ok"]:
			break
	var wrap := GridContainer.new()
	wrap.columns = 7
	wrap.add_theme_constant_override("h_separation", 4)
	wrap.add_theme_constant_override("v_separation", 4)
	wrap.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	body.add_child(wrap)
	_add_msg()
	_msg("Line: dead.", "bad")
	var cells: Array = []
	var end_ls := T.ls(T.disp(11), 11, T.INK)
	var live_ls := T.ls(T.disp(11), 11, T.SIREN)
	var phone_ls := T.ls(T.symbols(), 13, T.INK)
	var paint := func() -> void:
		var res: Dictionary = powered.call()
		for cell in cells:
			cell[2].powered = res["on"].has("%d,%d" % [cell[0], cell[1]])
		if res["ok"]:
			_msg("Dial tone!", "good")
			_solve()
	for i in R:
		var l := T.label("☎" if i == r0 else "", phone_ls, HORIZONTAL_ALIGNMENT_CENTER)
		l.custom_minimum_size = Vector2(28, 0)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		wrap.add_child(l)
		for j in CN:
			var b = Wd.WireCell.new()
			b.mask = grid[i][j]
			b.set_turns(turns[i][j], false)
			b.tooltip_text = "Tile row %d column %d" % [i + 1, j + 1]
			var ii := i
			var jj := j
			b.pressed.connect(func():
				if _done:
					return
				turns[ii][jj] += 1
				b.set_turns(turns[ii][jj], true)
				St.sfx("click")
				paint.call())
			wrap.add_child(b)
			cells.append([i, j, b])
		var rr := T.label("LINE" if i == r_end else "", live_ls if i == r_end else end_ls, HORIZONTAL_ALIGNMENT_CENTER)
		rr.custom_minimum_size = Vector2(28, 0)
		rr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		wrap.add_child(rr)
	paint.call()


# ------------------------------------------------------------------------------ 2) keypad
## The busted keypad: repeat the tones it plays back.
func _keypad() -> void:
	_head("PAYPHONE · KEYPAD SCRAMBLED", "Dial what the phone dials", "The buttons are wired wrong. Watch which ones light up, then press them in the same order.")
	var pad := _keypad_grid()
	var shaker := _shaker(pad)
	body.add_child(shaker)
	_add_msg()
	var state := {"seq": [], "pos": 0, "listening": false, "round": 0}
	var score := int(St.num("score", 0))
	var length := 4 + mini(2, int(floor(score / 1500.0)))
	var flash := func(k: String, sec: float) -> void:
		_set_lit(k, true)
		_lit[k] = maxf(sec, _lit.get(k, 0.0))
		St.sfx("dtmf", k)
	var play := func(self_ref: Callable) -> void:
		state["listening"] = false
		state["pos"] = 0
		_msg("Listen...")
		var seq: Array = []
		for i in length:
			seq.append(KEYS[randi() % 12])
		state["seq"] = seq
		for i in seq.size():
			var k: String = seq[i]
			_after(0.6 + i * 0.56, func():
				if _alive():
					flash.call(k, 0.3))
		_after(0.6 + seq.size() * 0.56, func():
			state["listening"] = true
			_msg("Your turn."))
	var press := func(k: String) -> void:
		if not state["listening"] or _done:
			return
		flash.call(k, 0.16)
		var seq: Array = state["seq"]
		if k == seq[state["pos"]]:
			state["pos"] += 1
			if state["pos"] == seq.size():
				state["listening"] = false
				_msg("Connected!", "good")
				_solve()
		else:
			state["listening"] = false
			_msg("Wrong number. -4 seconds.", "bad")
			_shake(shaker)
			_wrong()
			state["round"] += 1
			_after(0.9, func(): play.call(play))
	for k in KEYS:
		var kk: String = k
		(_key_btn[k] as Button).pressed.connect(func(): press.call(kk))
	_key_handler = func(k: String) -> void:
		if _key_btn.has(k):
			press.call(k)
	play.call(play)


# ------------------------------------------------------------------------------ 3) menu
## Precinct 9's phone menu.
func _menu() -> void:
	var f = focus
	_head("PRECINCT 9 · AUTOMATED LINE", "Get through the phone menu", "Pick the right option. Wrong answers put you back on hold.")
	var steps := [
		{"q": "Thank you for calling Precinct 9. Our menu has changed, mostly because of you. Please choose from the following options.",
			"o": [["To report a crime", 1], ["For donut orders", 0], ["To hear the hold music again", 0]]},
		{"q": "Is the crime happening right now?",
			"o": [["Yes. Right now. Right there.", 1], ["It's been happening since 2009", 1 if str(St.field(f, "id", "")) == "gary" else 0], ["I just wanted to see if you'd pick up", 0]]},
		{"q": "Please describe the suspect, in one breath.",
			"o": [[str(St.field(f, "describe", "")), 1], ["Tall-ish? Some kind of hat?", 0], ["*heavy breathing*", 0]]},
	]
	var box_ := T.vbox(8)
	box_.mouse_filter = Control.MOUSE_FILTER_PASS
	var shaker := _shaker(box_)
	body.add_child(shaker)
	_add_msg()
	var state := {"i": 0}
	var q_style := T.striped(T.MENU_Q, [10, 12, 10, 12], 3, T.INK, 4)
	var q_ls := T.ls(T.mono(), 15, T.INK, [], 1.35)
	var opt_n := T.box(T.PAPER, [8, 10, 8, 10], 3, 2, T.INK)
	var opt_h := T.box(T.TICKET, [8, 10, 8, 10], 3, 2, T.INK)
	var kbd_style := T.box(T.INK, [1, 7, 1, 7], 2)
	var kbd_ls := T.ls(T.mono(true), 17, T.TICKET)
	var opt_ls := T.ls(T.body(600), 17, T.INK)
	var gen := _gen
	var show := func(self_ref: Callable) -> void:
		if gen != _gen:
			return
		for ch in box_.get_children():
			box_.remove_child(ch)
			ch.queue_free()
		var st: Dictionary = steps[state["i"]]
		var ql := T.label(st["q"], q_ls, HORIZONTAL_ALIGNMENT_LEFT, true)
		box_.add_child(T.panel(q_style, ql))
		var opts: Array = (st["o"] as Array).duplicate()
		opts.shuffle()
		var pick := func(o: Array) -> void:
			if _done:
				return
			St.sfx("dtmf", str(1 + randi() % 9))
			if o[1]:
				state["i"] += 1
				_msg("")
				if state["i"] == steps.size():
					_msg("Transferring you to a human...", "good")
					_solve()
				else:
					self_ref.call(self_ref)
			else:
				_msg("Your call is important to us. -4 seconds.", "bad")
				_shake(shaker)
				_wrong()
				state["i"] = 0
				_after(0.7, func(): self_ref.call(self_ref))
		for k in opts.size():
			var o: Array = opts[k]
			var row := T.hbox(10)
			row.add_child(T.kbd(str(k + 1), kbd_ls, kbd_style))
			var tl := T.label(str(o[0]), opt_ls, HORIZONTAL_ALIGNMENT_LEFT, true)
			tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(tl)
			var b = Wd.ClickPanel.new(opt_n, opt_h)
			b.add_child(row)
			b.pressed.connect(func(): pick.call(o))
			box_.add_child(b)
		_key_handler = func(key_: String) -> void:
			if key_.is_valid_int():
				var n := key_.to_int()
				if n >= 1 and n <= opts.size():
					pick.call(opts[n - 1])
	show.call(show)


# ------------------------------------------------------------------------------ 4) plate
## Mama's plate: dial it from memory.
func _plate() -> void:
	var c = focus
	_head("PAYPHONE · TRAFFIC DIVISION", "Dial in her license plate", "You saw it on the photo. Four digits. No peeking.")
	var disp := T.label("", T.ls(T.spaced(T.mono(true), 9), 30, T.INK), HORIZONTAL_ALIGNMENT_CENTER)
	disp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var dp := T.panel(T.box(T.PLATE_BG, [6, 10, 6, 10], 6, 3, T.INK), disp)
	dp.custom_minimum_size = Vector2(0, 44)
	body.add_child(dp)
	var pad := _keypad_grid({"*": "⌫"})
	var del: Button = _key_btn["*"]
	del.tooltip_text = "Delete"
	del.add_theme_font_override("font", T.symbols())
	del.add_theme_font_size_override("font_size", 26)
	var shaker := _shaker(pad)
	body.add_child(shaker)
	_add_msg()
	var state := {"got": ""}
	var show := func() -> void:
		var s: String = (str(state["got"]) + "____").substr(0, 4)
		var chars := PackedStringArray()
		for ch in s:
			chars.append(ch)
		disp.text = " ".join(chars)
	show.call()
	var press := func(k: String) -> void:
		if _done:
			return
		if k == "*":
			var g: String = state["got"]
			state["got"] = g.substr(0, maxi(0, g.length() - 1))
			show.call()
			return
		if k == "#":
			return
		state["got"] = str(state["got"]) + k
		St.sfx("dtmf", k)
		show.call()
		if str(state["got"]).length() == 4:
			var plate := str(St.field(c, "plate", ""))
			if state["got"] == plate:
				_msg("That's her. Connecting...", "good")
				_solve()
			else:
				var hint := mini(3, int(St.field(c, "hint", 0)) + 1)
				if c is Object:
					c.set("hint", hint)
				elif c is Dictionary:
					c["hint"] = hint
				_msg("Not her plate. -4 seconds. Starts with %s..." % plate.substr(0, hint), "bad")
				_shake(shaker)
				_wrong()
				state["got"] = ""
				_after(0.5, show)
	for k in KEYS:
		var kk: String = k
		(_key_btn[k] as Button).pressed.connect(func(): press.call(kk))
	_key_handler = func(k: String) -> void:
		if k.length() == 1 and k >= "0" and k <= "9":
			press.call(k)
		elif k == "Backspace":
			press.call("*")
