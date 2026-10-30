extends CanvasLayer
## HUD autoload: subtitles, toasts, markers, case file, mini-map, binoculars overlay,
## minigame panel, payphone puzzles, title / game over / pause / stage card, music video.
## The port of index.html + css/style.css + hud.js + puzzles.js and the screen parts of
## minigames.js / game.js. Built in code; the look lives in hud_theme.gd.
##
## CONTRACT. The simulation (G and the gameplay scripts) only talks to the HUD through the
## functions below, and the HUD only reads game state listed in godot/README.md ([HUD] in
## g.gd / crime.gd, read through hud_state.gd). Keep every signature exactly as is.

const T := preload("res://scripts/ui/hud_theme.gd")
const Wd := preload("res://scripts/ui/hud_widgets.gd")
const St := preload("res://scripts/ui/hud_state.gd")
const Cases := preload("res://scripts/ui/hud_cases.gd")
const Mini := preload("res://scripts/ui/hud_minimap.gd")
const Lock := preload("res://scripts/ui/hud_lock.gd")
const Puzzle := preload("res://scripts/ui/hud_puzzle.gd")
const Screens := preload("res://scripts/ui/hud_screens.gd")

## hud.js NAMES: speaker id -> subtitle name.
const NAMES := {"TWOPACK": "2-Pack", "COPS": "Dan & Steve", "OPERATOR": "911", "DAN": "Officer Dan", "STEVE": "Officer Steve",
	"GARY": "Gary", "RICKY": "Ricky", "TIMMY": "Little Timmy", "MAMA": "Timmy's mama", "GRANDMA": "Grandma",
	"MAILMAN": "The mailman", "MOM": "2-Pack's mama", "DADDY": "2-Pack's daddy", "VENDOR": "Ice-cream man", "LINER": "Somebody in line"}

const TOAST_SECS := 3.6
const POP_SECS := 1.7
const POP_RISE := 1.6
const SLOW_STEP := 0.15

var root: Control
var _markers_layer: Control
var _shade
var _plate: PanelContainer
var _score_l: Label
var _rank_l: Label
var _strikes: Array = []
var _still_l: Label
var _stage_l: Label
var _told: HFlowContainer
var _told_key := "~"
var _cases
var _prompt: PanelContainer
var _prompt_l: Label
var _lock
var _mini_panel: PanelContainer
var _mini
var _subs: VBoxContainer
var _sub_name: Label
var _sub_text: Label
var _toast: PanelContainer
var _toast_l: Label
var _keys: Control
var _reticle
var _bino_label: Label
var _bino_top: Label
var _livecam: VBoxContainer
var _lc_label: Label
var _lc_big: Label
var _lc_what: Label
var _puzzle
var _pzpen: Label
var _screens

var _sub_q: Array = []
var _sub_t := 0.0
var _toast_t := 0.0
var _pen_t := 0.0
var _slow_t := 0.0
var _pops: Array = []       # [Tag, world pos, age]
var _marks := {}            # crime id -> Tag
var _hud_on := false
var _bino_vis := false
var _pulse_t := 0.0
var _mk_styles := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 5
	_build()


# ==================================================================================== API
# ---- subtitles and feedback ----------------------------------------------------------
## Queue a subtitle. When it starts showing, call G.set_talking(who, dur * 0.85).
func say(who: String, text: String, dur := 2.4) -> void:
	_sub_q.append([who, text, dur])


func toast(text: String) -> void:
	_toast_l.text = text
	T.fit_label(_toast_l, 520)
	_toast.visible = true
	_toast_t = TOAST_SECS


## Floating label that starts 1 m above world_pos and rises/fades (1.7 s), like the JS pop().
func pop(world_pos: Vector3, text: String) -> void:
	var tag = Wd.Tag.new()
	tag.setup(text, T.disp(24), 24, T.PAPER, _mk_style("pop"))
	tag.visible = false
	_markers_layer.add_child(tag)
	_pops.append([tag, world_pos + Vector3(0, 1, 0), 0.0])
	_place_pop(_pops[_pops.size() - 1])


## Drop queued subtitles (on reset).
func clear_subs() -> void:
	_sub_q.clear()


# ---- visibility ----------------------------------------------------------------------
## Score plate, case file, key help and mini-map. Turning it off also hides prompt and lock panel.
func show_hud(on: bool) -> void:
	_hud_on = on
	_plate.visible = on
	_keys.visible = on
	_sync_side()
	if not on:
		_prompt.visible = false
		_lock.close()
	else:
		_slow_t = 0.0


## Stage card (big title + subtitle) for secs seconds.
func card(title: String, sub: String, secs: float) -> void:
	_screens.card(title, sub, secs)


# ---- binoculars ----------------------------------------------------------------------
## Called every frame while playing. on = binoculars up. label = text under the reticle,
## progress = evidence ring 0..1.
func bino(on: bool, label := "", progress := 0.0) -> void:
	_set_bino(on)
	if on:
		if _bino_label.text != label:
			_bino_label.text = label
		_reticle.progress = progress


# ---- minigame panel (whistle rhythm, ruler, snore recording) --------------------------
## kind: "rhythm" | "ruler" | "record"
func lock_open(kind: String, eye: String, title: String, msg: String) -> void:
	_lock.open(kind, eye, title, msg)


## rhythm: {"head": 0..1, "hit": index of the pip just hit or -1}
## ruler:  {"needle": 0..1, "reading": "1/4 in"}
## record: {"vu": 0..1, "count": "2/3"}
func lock_update(kind: String, data: Dictionary) -> void:
	_lock.update(kind, data)


func lock_msg(text: String) -> void:
	_lock.set_msg(text)


func lock_close() -> void:
	_lock.close()


# ---- payphone puzzles ----------------------------------------------------------------
## kind: "wires" | "keypad" | "menu" | "plate". focus = the Crime being reported.
## The puzzle UI runs the puzzle itself and calls back:
##   G.puzzle_solved()   when solved      G.penalty(4)   on a wrong answer (also show penalty_flash)
##   G.hang_up()         Hang up button
## "plate" reads focus.plate and updates focus.hint; "menu" reads focus.describe and focus.id;
## "keypad" length = 4 + min(2, floor(G.S.score / 1500)).
func puzzle_show(kind: String, focus) -> void:
	_set_bino(false)
	_prompt.visible = false
	_puzzle.open(kind, focus)
	_livecam.visible = true
	_update_livecam()
	_sync_side()


func puzzle_hide() -> void:
	_puzzle.close()
	_livecam.visible = false
	_sync_side()


## Keys forwarded while G.S.mode == "puzzle": "0".."9", "*", "#", "Backspace".
func puzzle_key(key: String) -> void:
	_puzzle.key(key)


## The red "-4s" flash.
func penalty_flash(sec: int) -> void:
	_pzpen.text = "-%ds" % sec
	_pzpen.visible = true
	_pen_t = 0.9


# ---- screens -------------------------------------------------------------------------
## Title screen. Buttons: "Start snitchin'" -> G.start_game(); "Continue: Stage 2" (only if
## can_continue) -> G.start_stage(2, false).
func show_title(can_continue: bool) -> void:
	_screens.show_title(can_continue)


## Game over / stage clear. stats = {"score": int, "busts": int, "still": int, "time": float}.
## Buttons: "Snitch again" -> G.start_game(); "Replay Stage 2" (if can_replay2) -> G.start_stage(2, false).
func show_over(title: String, line: String, stats: Dictionary, can_replay2: bool) -> void:
	_screens.show_over(title, line, stats, can_replay2)


func hide_screens() -> void:
	_screens.hide_screens()


## Discard transient UI and callbacks when leaving a world, including an active puzzle.
func reset_for_scene_change() -> void:
	hide_screens()
	_screens.pause.hide()
	_screens.stagecard.hide()
	puzzle_hide()
	show_hud(false)
	bino(false)
	clear_subs()
	_sub_t = 0.0
	_toast_t = 0.0
	_pen_t = 0.0
	_subs.hide()
	_toast.hide()
	_pzpen.hide()
	for pop_item in _pops:
		pop_item[0].queue_free()
	_pops.clear()
	for marker in _marks.values():
		marker.queue_free()
	_marks.clear()
	_told_key = "~"


func show_pause(on: bool) -> void:
	_screens.show_pause(on)


## Full-screen music video ("Still There"). Calls on_done when it ends or is skipped.
## If the video can't load, says so and offers the skip button.
func play_video(on_done: Callable) -> void:
	_screens.play_video(on_done)


# ================================================================================= build
func _build() -> void:
	root = Control.new()
	root.name = "HudRoot"
	root.theme = T.theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# z-order follows the CSS: markers, binocular shade, then the z5 HUD, then z6, z19...
	_markers_layer = Control.new()
	_markers_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_markers_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_markers_layer.clip_contents = true
	root.add_child(_markers_layer)
	_shade = Wd.Shade.new()
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.visible = false
	root.add_child(_shade)
	_build_plate()
	_cases = Cases.new()
	root.add_child(_cases)
	_pin(_cases, 1, 0, -12, 12, Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_END)
	_build_prompt()
	_lock = Lock.new()
	_lock.visible = false
	root.add_child(_lock)
	_pin(_lock, 0.5, 1, 0, -172, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN)
	_mini = Mini.new()
	_mini_panel = T.panel(T.box(T.INK, [0, 0, 0, 0], 3, 2, T.TICKET, Vector2(3, 3), T.a(T.BLACK, 0.35)), _mini)
	root.add_child(_mini_panel)
	_pin(_mini_panel, 1, 1, -12, -12, Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_BEGIN)
	_build_subs()
	_build_toast()
	_build_keys()
	_reticle = Wd.Reticle.new()
	root.add_child(_reticle)
	_pin(_reticle, 0.5, 0.5, -42, -42)
	_bino_label = T.label("", T.ls(T.spaced(T.mono(true), 1), 14, T.TICKET, [[Vector2(0, 1), T.BLACK]]), HORIZONTAL_ALIGNMENT_CENTER)
	root.add_child(_bino_label)
	_pin(_bino_label, 0.5, 0.5, 0, 62, Control.GROW_DIRECTION_BOTH)
	_bino_top = T.label("BINOCULARS · MOUSE TO AIM · WHEEL TO ZOOM", T.ls(T.spaced(T.mono(), 1), 12, T.BINO_TOP), HORIZONTAL_ALIGNMENT_CENTER)
	root.add_child(_bino_top)
	_pin(_bino_top, 0.5, 0, 0, 14, Control.GROW_DIRECTION_BOTH)
	for c in [_reticle, _bino_label, _bino_top]:
		c.visible = false
	_build_livecam()
	_puzzle = Puzzle.new()
	_puzzle.visible = false
	_puzzle.penalized.connect(penalty_flash)
	root.add_child(_puzzle)
	_puzzle.anchor_left = 0
	_puzzle.anchor_right = 0
	_puzzle.anchor_top = 0
	_puzzle.anchor_bottom = 1
	_puzzle.offset_left = 0
	_puzzle.offset_right = 440
	_puzzle.offset_top = 0
	_puzzle.offset_bottom = 0
	_pzpen = T.label("", T.ls(T.disp(30), 30, T.SIREN, [[Vector2(2, 2), T.PAPER]]), HORIZONTAL_ALIGNMENT_RIGHT)
	_pzpen.visible = false
	root.add_child(_pzpen)
	_pin(_pzpen, 1, 0, -30, 120, Control.GROW_DIRECTION_BEGIN)
	_screens = Screens.new()
	root.add_child(_screens)
	show_hud(false)


## Pin a control's corner/edge to an anchor point; it grows from there to its minimum size.
func _pin(c: Control, ax: float, ay: float, ox: float, oy: float, gh := Control.GROW_DIRECTION_END, gv := Control.GROW_DIRECTION_END) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = ox
	c.offset_right = ox
	c.offset_top = oy
	c.offset_bottom = oy
	c.grow_horizontal = gh
	c.grow_vertical = gv


func _build_plate() -> void:
	var v := T.vbox(2)
	_plate = T.panel(T.box(T.INK, [8, 12, 9, 12], 4, 3, T.TICKET, Vector2(4, 4), T.a(T.BLACK, 0.35)), v)
	_plate.custom_minimum_size = Vector2(170, 0)
	root.add_child(_plate)
	_pin(_plate, 0, 0, 12, 12)
	v.add_child(T.tight(T.label("TATTLETALE 2-PACK", T.ls(T.disp(13), 13, T.TICKET, [], 1.25))))
	var sc := T.vbox(0)
	sc.add_child(T.label("SNITCH POINTS", T.ls(T.spaced(T.mono(), 1), 11, T.TICKET)))
	_score_l = T.label("0", T.ls(T.mono(true), 26, T.PAPER, [], 1.05))
	sc.add_child(T.tight(_score_l))
	v.add_child(sc)
	_rank_l = T.label("HALL MONITOR", T.ls(T.spaced(T.body(600), 1), 14, T.PAPER))
	v.add_child(_rank_l)
	var st := T.hbox(5)
	st.add_child(T.label("GOT AWAY", T.ls(T.spaced(T.body(500), 1), 11, T.DIM)))
	for i in 3:
		var s = Wd.Strike.new()
		st.add_child(s)
		_strikes.append(s)
	v.add_child(T.margin(st, 3))
	_still_l = T.label("", T.ls(T.mono(), 12, T.DIM))
	_still_l.visible = false
	v.add_child(_still_l)
	_stage_l = T.label("", T.ls(T.spaced(T.mono(), 1), 11, T.TICKET))
	v.add_child(T.margin(_stage_l, 3))
	_told = HFlowContainer.new()
	_told.add_theme_constant_override("h_separation", 3)
	_told.add_theme_constant_override("v_separation", 3)
	_told.custom_minimum_size = Vector2(200, 0)
	_told.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tm := T.margin(_told, 4)
	tm.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(tm)


func _build_prompt() -> void:
	var row := T.hbox(6)
	_prompt = T.panel(T.box(T.TICKET, [6, 14, 6, 14], 3, 0, Color(0, 0, 0, 0), Vector2(3, 3), T.a(T.BLACK, 0.4)), row)
	row.add_child(T.kbd("E", T.ls(T.mono(true), 18, T.TICKET), T.box(T.INK, [0, 6, 0, 6], 2)))
	_prompt_l = T.label("", T.ls(T.spaced(T.body(700), 1), 18, T.INK))
	_prompt_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_prompt_l)
	_prompt.visible = false
	root.add_child(_prompt)
	_pin(_prompt, 0.5, 1, 0, -76, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN)


func _build_subs() -> void:
	_subs = T.vbox(2)
	_sub_name = T.label("", T.ls(T.disp(13, 0.52), 13, T.TICKET, [[Vector2(0, 2), T.BLACK], [Vector2(0, 0), T.a(T.BLACK, 0.25), 4]]), HORIZONTAL_ALIGNMENT_CENTER)
	_subs.add_child(_sub_name)
	_sub_text = T.label("", T.ls(T.body(600), 22, T.PAPER, [[Vector2(0, 2), T.BLACK], [Vector2(0, 0), T.a(T.BLACK, 0.22), 6]], 1.2), HORIZONTAL_ALIGNMENT_CENTER, true)
	_subs.add_child(_sub_text)
	_subs.visible = false
	root.add_child(_subs)
	_pin(_subs, 0.5, 1, 0, -122, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN)


func _build_toast() -> void:
	_toast_l = T.label("", T.ls(T.body(600), 17, T.PAPER), HORIZONTAL_ALIGNMENT_CENTER, true)
	_toast = T.panel(T.box(T.INK, [8, 16, 8, 16], 3, 2, T.TICKET, Vector2(3, 3), T.a(T.BLACK, 0.4)), _toast_l)
	_toast.visible = false
	root.add_child(_toast)
	_pin(_toast, 0.5, 0, 0, 18, Control.GROW_DIRECTION_BOTH)


func _build_keys() -> void:
	var v := T.vbox(0)
	var txt := T.ls(T.mono(), 12, T.KEYS_TEXT, [[Vector2(0, 1), T.BLACK]])
	var key := T.ls(T.mono(), 12, T.TICKET)
	var ks := T.box(T.a(T.INK, 0.85), [0, 4, 0, 4], 2, 1, T.KBD_EDGE)
	for parts in [
			[["WASD"], " walk · ", ["Shift"], " run · drag or ", ["←"], ["→"], " look"],
			[["Right mouse"], "/", ["Space"], " spy · ", ["E"], " use · ", ["M"], " music · ", ["P"], " pause"]]:
		var row := T.kbd_line(parts, txt, key, ks)
		row.custom_minimum_size.y = 18
		v.add_child(row)
	v.modulate = Color(1, 1, 1, 0.85)
	_keys = v
	root.add_child(v)
	_pin(v, 0, 1, 12, -12, Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_BEGIN)


func _build_livecam() -> void:
	_livecam = T.vbox(4)
	_livecam.alignment = BoxContainer.ALIGNMENT_BEGIN
	var lrow := T.hbox(6)
	lrow.add_child(Wd.LiveDot.new())
	_lc_label = T.label("LIVE", T.ls(T.spaced(T.mono(), 1), 12, T.PAPER))
	lrow.add_child(_lc_label)
	var lp := T.panel(T.box(T.SIREN, [2, 8, 2, 8], 2), lrow)
	lp.size_flags_horizontal = Control.SIZE_SHRINK_END
	_livecam.add_child(lp)
	_lc_big = T.label("0:00", T.ls(T.disp(64), 64, T.PAPER, [[Vector2(4, 4), T.INK]], 1.0), HORIZONTAL_ALIGNMENT_RIGHT)
	var bm := T.tight(_lc_big)
	bm.size_flags_horizontal = Control.SIZE_SHRINK_END
	_livecam.add_child(bm)
	_lc_what = T.label("", T.ls(T.body(700), 18, T.PAPER, [[Vector2(0, 2), T.BLACK]]), HORIZONTAL_ALIGNMENT_RIGHT, true)
	_lc_what.size_flags_horizontal = Control.SIZE_SHRINK_END
	_livecam.add_child(_lc_what)
	_livecam.visible = false
	root.add_child(_livecam)
	_pin(_livecam, 1, 0, -14, 14, Control.GROW_DIRECTION_BEGIN)


func _mk_style(k: String) -> StyleBox:
	if _mk_styles.has(k):
		return _mk_styles[k]
	var bg: Color = {"mk": T.SIREN, "ev": T.TICKET, "dis": T.COP, "pop": T.SIREN}[k]
	var bc: Color = T.INK if k == "ev" else T.PAPER
	var s := T.box(bg, [2, 7, 3, 7], 3, 2, bc, Vector2(2, 2), T.a(T.BLACK, 0.4))
	_mk_styles[k] = s
	return s


## Case file and mini-map: hidden while the HUD is off or a puzzle is up (openPuzzle).
func _sync_side() -> void:
	var on: bool = _hud_on and not _puzzle.visible
	if on and not _cases.visible:
		_slow_t = 0.0   # refresh the case file right away instead of showing it stale
	_cases.visible = on
	_mini_panel.visible = on


func _set_bino(on: bool) -> void:
	if on == _bino_vis:
		return
	_bino_vis = on
	for c in [_shade, _reticle, _bino_label, _bino_top]:
		c.visible = on
	if not on:
		_reticle.progress = 0.0


# ================================================================================ update
func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	var mode := St.mode()
	var paused := mode == "pause" or get_tree().paused
	if _pzpen.visible:
		_pen_t -= delta
		if _pen_t <= 0.0:
			_pzpen.visible = false
	if _bino_vis and mode != "play":
		_set_bino(false)
	if not paused:
		_update_subs(dt)
		if _toast.visible:
			_toast_t -= dt
			if _toast_t <= 0.0:
				_toast.visible = false
		_update_markers(mode)
		_update_prompt(mode)
		_update_livecam()
		_slow_t -= dt
		if _slow_t <= 0.0:
			_slow_t = SLOW_STEP
			_slow_update()
	_update_pops(delta)
	if _livecam.visible:
		_pulse_t += delta
		var urgent := _lc_big.label_settings.font_color == T.TICKET
		var sc := 1.0
		if urgent:
			var u := fmod(_pulse_t, 1.0)
			var tri := u * 2.0 if u < 0.5 else (1.0 - u) * 2.0
			sc = 1.0 + 0.08 * (0.5 - 0.5 * cos(tri * PI))
		var holder: Control = _lc_big.get_parent()
		holder.pivot_offset = holder.size * 0.5
		holder.scale = Vector2(sc, sc)


func _update_subs(dt: float) -> void:
	_sub_t -= dt
	if _sub_t > 0.0:
		return
	if _sub_q.size():
		var s: Array = _sub_q.pop_front()
		var who := str(s[0])
		_sub_name.text = T.caps(str(NAMES.get(who, who)))
		_sub_text.text = str(s[1])
		T.fit_label(_sub_text, 720)
		_subs.visible = true
		_sub_t = float(s[2])
		St.call_g("set_talking", [who, float(s[2]) * 0.85])
	else:
		_subs.visible = false


func _update_markers(mode: String) -> void:
	var live := mode == "play" or mode == "puzzle"
	var cam := St.camera()
	var pl = St.xz(St.gv("P"))
	if pl == null:
		pl = Vector2.ZERO
	var lock := St.lock_on()
	var bino := St.bino_on()
	var seen := {}
	for c in St.crimes():
		var id := str(St.field(c, "id", ""))
		seen[id] = true
		var mk = _marks.get(id)
		if mk == null:
			mk = Wd.Tag.new()
			mk.visible = false
			_markers_layer.add_child(mk)
			_marks[id] = mk
		var show: bool = live and not lock and St.active(c) and not St.field(c, "handling", false) and cam != null
		var st := {}
		var k := ""
		var t := Vector3.ZERO
		if show:
			st = St.cur(c)
			k = St.kind(st)
			t = St.mark(c)
			var spyish := k == "spy" or k == "tail"
			show = Vector2(t.x - pl.x, t.z - pl.y).length() < 38.0 and not (bino and spyish)
		if show:
			var wp := t + Vector3(0, 0.9, 0)
			if cam.is_position_behind(wp) or cam.global_position.distance_to(wp) > cam.far:
				show = false
			else:
				var dispatched := bool(St.field(c, "dispatched", false))
				var spyish2 := k == "spy" or k == "tail"
				var look := "dis" if dispatched else ("mk" if spyish2 else "ev")
				var text := "COPS COMING" if dispatched else ("DAN STOPPED" if (k == "lead" and St.dan_lost()) else str(st.get("m", "")))
				mk.setup(text, T.disp(20) if look == "mk" else T.disp(13), 20 if look == "mk" else 13, T.INK if look == "ev" else T.PAPER, _mk_style(look))
				var sp := cam.unproject_position(wp)
				mk.position = (sp - Vector2(mk.size.x * 0.5, mk.size.y)).round()
		mk.visible = show
	for id in _marks.keys():
		if not seen.has(id):
			_marks[id].queue_free()
			_marks.erase(id)


func _place_pop(p: Array) -> void:
	var tag = p[0]
	var cam := St.camera()
	if cam == null or cam.is_position_behind(p[1]):
		tag.visible = false
		return
	var u: float = clampf(p[2] / POP_RISE, 0.0, 1.0)
	var e := 1.0 - (1.0 - u) * (1.0 - u)
	var sp := cam.unproject_position(p[1])
	tag.position = (sp - Vector2(tag.size.x * 0.5, tag.size.y * (1.0 + 0.8 * e))).round()
	tag.modulate.a = 1.0 - e
	tag.visible = true


func _update_pops(delta: float) -> void:
	if _pops.is_empty():
		return
	var gone := []
	for p in _pops:
		p[2] += delta
		if p[2] >= POP_SECS:
			gone.append(p)
		else:
			_place_pop(p)
	for p in gone:
		p[0].queue_free()
		_pops.erase(p)


func _update_prompt(mode: String) -> void:
	var text := ""
	if _hud_on and mode == "play" and not St.bino_on() and not St.lock_on():
		var gg := St.g()
		if gg and gg.has_method("nearest_interact"):
			var it = gg.nearest_interact()
			if it != null:
				text = str(St.field(it, "label", ""))
	if text == "":
		_prompt.visible = false
		return
	var up := text.to_upper()
	if _prompt_l.text != up:
		_prompt_l.text = up
	_prompt.visible = true


## #livecam during a puzzle. (hud.js also closes the puzzle when the crime gets away
## meanwhile; in the port that lives in G.tick, which runs before the HUD each frame.)
func _update_livecam() -> void:
	if not _livecam.visible:
		return
	var pz = St.field(St.s(), "pz")
	var f = St.field(pz, "focus", _puzzle.focus)
	if f == null:
		return
	var left := St.left(f)
	_lc_label.text = "LIVE · " + St.short(f).to_upper()
	_lc_big.text = "∞" if is_inf(left) else T.fmt(left)
	var urgent := left < 10.0
	var col := T.TICKET if urgent else T.PAPER
	if _lc_big.label_settings.font_color != col:
		_lc_big.label_settings.font_color = col
	var what := str(St.field(f, "title", ""))
	if _lc_what.text != what:
		_lc_what.text = what
		T.fit_label(_lc_what, 736)


func _slow_update() -> void:
	if St.live() and _mini_panel.visible:
		_mini.queue_redraw()
	if _plate.visible:
		_update_plate()
	if _cases.visible:
		_cases.refresh()


func _update_plate() -> void:
	var score := int(St.num("score", 0))
	var s := T.commas(score)
	if _score_l.text != s:
		_score_l.text = s
	var r := St.rank().to_upper()
	if _rank_l.text != r:
		_rank_l.text = r
	var strikes := int(St.num("strikes", 0))
	for i in _strikes.size():
		_strikes[i].on = i < strikes
	var still := int(St.num("still", 0))
	var st := "Gary: still there ×%d" % still if still > 0 else ""
	if _still_l.text != st:
		_still_l.text = st
		_still_l.visible = st != ""
	var need := St.need_list()
	var cops := St.cops_active()
	var key := "%d|" % int(St.num("stage", 1))
	for id in need:
		key += ("1" if St.told(str(id)) else "0")
	key += "|c1" if cops else "|c0"
	if St.told("cops"):
		key += "t"
	if key == _told_key:
		return
	_told_key = key
	_stage_l.text = "%s · TOLD ON %d/%d" % [St.stage_name().to_upper(), St.told_count(need), need.size()]
	for ch in _told.get_children():
		ch.queue_free()
	var ids := need.duplicate()
	if cops:
		ids.append("cops")
	var off_ls := T.ls(T.mono(), 10, T.DIM)
	var on_ls := T.ls(T.mono(), 10, T.INK)
	var off_st := T.box(Color(0, 0, 0, 0), [1, 5, 1, 5], 2, 1, T.KBD_EDGE)
	var on_st := T.box(T.TICKET, [1, 5, 1, 5], 2, 1, T.TICKET)
	for id in ids:
		var on := St.told(str(id))
		var l := T.label(St.told_name(str(id)), on_ls if on else off_ls)
		if on:
			l.draw.connect(func():
				var y := l.size.y * 0.55
				l.draw_line(Vector2(0, y), Vector2(l.size.x, y), T.INK, 1.0))
		_told.add_child(T.panel(on_st if on else off_st, l))
