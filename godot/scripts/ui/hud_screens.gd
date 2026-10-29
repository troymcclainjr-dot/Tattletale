extends Control
## The full-screen layers (index.html + game.js): pause, stage card, title, game over / stage
## clear and the "Still There" music video, stacked in the CSS z-order.

const T := preload("res://scripts/ui/hud_theme.gd")
const Wd := preload("res://scripts/ui/hud_widgets.gd")
const St := preload("res://scripts/ui/hud_state.gd")

const VIDEO_PATH := "res://assets/video/still_there.ogv"
const VIDEO_FAIL := "The music video couldn't load here. Skip ahead to Stage 2."

var pause: Control
var stagecard: Control
var title: Control
var over: Control
var mv: Control

var _sc_title: Label
var _sc_sub: Label
var _card_t := 0.0
var _cont: Button
var _start: Button
var _over_title: Label
var _over_line: Label
var _stats: Array[Label] = []
var _again: Button
var _again2: Button
var _player: VideoStreamPlayer
var _aspect: AspectRatioContainer
var _mv_msg: Label
var _mv_skip: Button
var _mv_pause: Button
var _mv_time: Label
var _mv_bar
var _mv_strip: Control
var _video_cb := Callable()
var _video_done := true
var _video_t := 0.0
var _video_last_pos := -1.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_pause()
	_build_stagecard()
	title = _build_screen(false)
	over = _build_screen(true)
	_build_video()
	for c in [pause, stagecard, title, over, mv]:
		c.visible = false


func _process(delta: float) -> void:
	if stagecard.visible:
		_card_t -= delta
		if _card_t <= 0.0:
			stagecard.visible = false
	if mv.visible and not _video_done:
		_video_tick(delta)


# ------------------------------------------------------------------------------ pause
func _build_pause() -> void:
	pause = ColorRect.new()
	(pause as ColorRect).color = Color(14 / 255.0, 20 / 255.0, 40 / 255.0, 0.6)
	pause.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(pause)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause.add_child(cc)
	var v := T.vbox(0)
	cc.add_child(v)
	v.add_child(T.tight(T.label("PAUSED", T.ls(T.disp(40), 40, T.TICKET, [], 1.15), HORIZONTAL_ALIGNMENT_CENTER)))
	v.add_child(T.label("Press P to keep snitchin'", T.ls(T.body(600), 18, T.PAPER), HORIZONTAL_ALIGNMENT_CENTER))


# ------------------------------------------------------------------------------ stage card
func _build_stagecard() -> void:
	stagecard = Control.new()
	stagecard.set_anchors_preset(Control.PRESET_FULL_RECT)
	stagecard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stagecard)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stagecard.add_child(cc)
	var v := T.vbox(8)
	cc.add_child(T.panel(T.box(T.INK, [18, 26, 20, 26], 0, 4, T.TICKET, Vector2(8, 8), T.a(T.BLACK, 0.4)), v))
	_sc_title = T.label("", T.ls(T.disp(64), 64, T.TICKET, [[Vector2(4, 4), T.BLACK]], 1.0), HORIZONTAL_ALIGNMENT_CENTER, true)
	v.add_child(T.tight(_sc_title))
	_sc_sub = T.label("", T.ls(T.body(600), 20, T.PAPER), HORIZONTAL_ALIGNMENT_CENTER, true)
	v.add_child(_sc_sub)


func card(t: String, sub: String, secs: float) -> void:
	_sc_title.text = T.caps(t)
	_sc_sub.text = sub
	T.fit_label(_sc_title, 588)
	T.fit_label(_sc_sub, 588)
	_card_t = secs
	stagecard.visible = true


# ------------------------------------------------------------------------------ title / over
func _build_screen(is_over: bool) -> Control:
	var scr := Control.new()
	scr.set_anchors_preset(Control.PRESET_FULL_RECT)
	scr.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scr)
	var grad := Gradient.new()
	grad.set_color(0, Color(14 / 255.0, 20 / 255.0, 40 / 255.0, 0.25))
	grad.set_color(1, Color(14 / 255.0, 20 / 255.0, 40 / 255.0, 0.82))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 256
	var bg := TextureRect.new()
	bg.texture = gt
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scr.add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	scr.add_child(scroll)
	var cc := CenterContainer.new()
	cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(cc)
	var card_ := T.vbox(16)
	card_.custom_minimum_size = Vector2(620, 0)
	cc.add_child(T.margin(card_, 20, 16, 20, 16))
	# .logo: big yellow display text with a navy drop and a soft dark one behind it
	var logo := T.vbox(0)
	card_.add_child(logo)
	var shadows := [[Vector2(5, 5), T.INK], [Vector2(7, 7), T.a(T.BLACK, 0.35)]]
	var main := T.label("", T.ls(T.disp(74), 74, T.TICKET, shadows, 0.92), HORIZONTAL_ALIGNMENT_LEFT, true)
	main.custom_minimum_size.x = 620
	logo.add_child(T.tight(main))
	var span := T.label("", T.ls(T.disp(31, 1.24), 31, T.PAPER, shadows, 0.92), HORIZONTAL_ALIGNMENT_LEFT, true)
	span.custom_minimum_size.x = 620
	logo.add_child(T.margin(T.tight(span), 8))
	if is_over:
		_over_title = main
		_over_line = span
		var stats := T.hbox(8)
		card_.add_child(stats)
		for cap in ["Snitch points", "Busted", "Still there", "Time on the block"]:
			var sv := T.vbox(0)
			var b := T.label("0", T.ls(T.mono(true), 26, T.PAPER))
			sv.add_child(b)
			sv.add_child(T.label(cap.to_upper(), T.ls(T.spaced(T.body(500), 1), 12, T.TICKET)))
			var sp := T.panel(T.box(T.INK, [8, 10, 8, 10], 3, 2, T.TICKET), sv)
			sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			stats.add_child(sp)
			_stats.append(b)
		var row := T.hbox(12)
		card_.add_child(row)
		_again = _go_button("Snitch again", false, func(): St.call_g("start_game"))
		row.add_child(_again)
		_again2 = _go_button("Replay Stage 2", true, func(): St.call_g("start_stage", [2, false]))
		row.add_child(_again2)
	else:
		main.text = T.caps("Tattletale 2-Pack")
		span.text = T.caps("Snitch Season · playable prototype")
		card_.add_child(_build_form())
		var row := T.hbox(12)
		card_.add_child(row)
		_start = _go_button("Start snitchin'", false, func(): St.call_g("start_game"))
		row.add_child(_start)
		_cont = _go_button("Continue: Stage 2", true, func(): St.call_g("start_stage", [2, false]))
		row.add_child(_cont)
	return scr


func _go_button(text: String, alt: bool, fn: Callable) -> Button:
	var b := Button.new()
	b.text = T.caps(text)
	b.theme_type_variation = "GoAltButton" if alt else "GoButton"
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(fn)
	return b


## .form: the incident report with the controls.
func _build_form() -> Control:
	var v := T.vbox(10)
	var form := T.panel(T.box(T.PAPER, [14, 16, 16, 16], 3, 0, Color(0, 0, 0, 0), Vector2(6, 6), T.a(T.BLACK, 0.4)), v)
	var hd_ls := T.ls(T.spaced(T.mono(), 2), 11, T.INK)
	var hd := T.vbox(6)
	var hr := T.hbox(8)
	hr.add_child(T.label("PRECINCT 9 · INCIDENT REPORT", hd_ls))
	hr.add_child(T.expander())
	hr.add_child(T.label("FORM 911-B", hd_ls))
	hd.add_child(hr)
	var rule := ColorRect.new()
	rule.color = T.INK
	rule.custom_minimum_size = Vector2(0, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hd.add_child(rule)
	v.add_child(hd)
	var p_ls := T.ls(T.mono(), 14, T.INK, [], 1.45)
	v.add_child(T.label("Crime is breaking out all over the block, and every crime gets reported its own way. Follow a trail of cash. Tail the mailman. Blow your whistle on the beat. Tell Timmy's mama. Your case file always says what to do next, and the timer never stops.", p_ls, HORIZONTAL_ALIGNMENT_LEFT, true))
	var dl := GridContainer.new()
	dl.columns = 2
	dl.add_theme_constant_override("h_separation", 14)
	dl.add_theme_constant_override("v_separation", 5)
	dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dt_ls := T.ls(T.mono(true), 13, T.INK)
	var dd_ls := T.ls(T.mono(), 13, T.INK)
	var kb_style := T.box(T.INK, [0, 5, 0, 5], 2)
	var kb_dt := T.ls(T.mono(true), 13, T.TICKET)
	var kb_dd := T.ls(T.mono(), 13, T.TICKET)
	var rows := [
		[[["W A S D"]], ["Walk (hold ", ["Shift"], " to run)"]],
		[["Drag / ", ["← →"]], ["Turn the camera"]],
		[["Hold ", ["Right mouse"], " or ", ["Space"]], ["Binoculars. Keep the suspect in the circle."]],
		[[["E"]], ["Do it: buy, knock, measure, mail, whistle, call"]],
		[[["M"], " · ", ["P"]], ["Music on/off · Pause"]],
	]
	for r in rows:
		var dt := T.kbd_line(r[0], dt_ls, kb_dt, kb_style)
		dt.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		dl.add_child(dt)
		var dd_parts: Array = r[1]
		if dd_parts.size() == 1:
			var l := T.label(str(dd_parts[0]), dd_ls, HORIZONTAL_ALIGNMENT_LEFT, true)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			dl.add_child(l)
		else:
			var dd := T.kbd_line(dd_parts, dd_ls, kb_dd, kb_style)
			dd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			dl.add_child(dd)
	v.add_child(dl)
	v.add_child(T.label("3 crimes get away and your shift is over.", p_ls, HORIZONTAL_ALIGNMENT_LEFT, true))
	return form


func show_title(can_continue: bool) -> void:
	_cont.visible = can_continue
	title.visible = true


func show_over(t: String, line: String, stats: Dictionary, can_replay2: bool) -> void:
	_over_title.text = T.caps(t)
	_over_line.text = T.caps(line)
	_stats[0].text = T.commas(int(stats.get("score", 0)))
	_stats[1].text = str(int(stats.get("busts", 0)))
	_stats[2].text = str(int(stats.get("still", 0)))
	_stats[3].text = T.fmt(float(stats.get("time", 0.0)))
	_again2.visible = can_replay2
	over.visible = true
	_again.grab_focus.call_deferred()


func hide_screens() -> void:
	_drop_focus()
	title.visible = false
	over.visible = false
	if mv.visible:
		_stop_video()


## A clicked or focused screen button must not keep keyboard focus once its screen is gone
## (Space / Enter would press it again from inside the game).
func _drop_focus() -> void:
	var vp := get_viewport()
	var f := vp.gui_get_focus_owner() if vp else null
	if f and is_ancestor_of(f):
		f.release_focus()


func show_pause(on: bool) -> void:
	pause.visible = on


# ------------------------------------------------------------------------------ music video
func _build_video() -> void:
	mv = ColorRect.new()
	(mv as ColorRect).color = Color.BLACK
	mv.set_anchors_preset(Control.PRESET_FULL_RECT)
	mv.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(mv)
	var col := T.vbox(0)
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	mv.add_child(col)
	var hd := T.hbox(12)
	col.add_child(T.margin(hd, 10, 16, 10, 16))
	var hv := T.vbox(0)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hd.add_child(hv)
	hv.add_child(T.label(T.caps("Tattletale 2-Pack · \"Still There\""), T.ls(T.disp(18), 18, T.TICKET)))
	hv.add_child(T.label("Stage 1 clear. Roll the video.", T.ls(T.body(500), 14, T.DIM)))
	_mv_skip = Button.new()
	_mv_skip.text = "SKIP TO STAGE 2"
	_mv_skip.theme_type_variation = "SkipButton"
	_mv_skip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mv_skip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_mv_skip.pressed.connect(func(): _finish_video())
	hd.add_child(_mv_skip)
	_aspect = AspectRatioContainer.new()
	_aspect.ratio = 16.0 / 9.0
	_aspect.stretch_mode = AspectRatioContainer.STRETCH_FIT
	_aspect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_aspect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_aspect)
	_player = VideoStreamPlayer.new()
	_player.expand = true
	_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player.finished.connect(func(): _finish_video())
	_aspect.add_child(_player)
	# a slim control strip (the web uses the browser's video controls)
	var strip := T.hbox(12)
	_mv_pause = Button.new()
	_mv_pause.text = "Pause"
	_mv_pause.theme_type_variation = "VideoButton"
	_mv_pause.focus_mode = Control.FOCUS_NONE
	_mv_pause.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_mv_pause.pressed.connect(func():
		_player.paused = not _player.paused
		_mv_pause.text = "Play" if _player.paused else "Pause")
	strip.add_child(_mv_pause)
	_mv_time = T.label("0:00", T.ls(T.mono(), 13, T.DIM))
	_mv_time.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	strip.add_child(_mv_time)
	_mv_bar = Wd.Bar.new()
	_mv_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mv_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mv_bar.custom_minimum_size = Vector2(0, 4)
	_mv_bar.bg_color = Color(1, 1, 1, 0.16)
	_mv_bar.fill_color = T.TICKET
	strip.add_child(_mv_bar)
	_mv_strip = T.margin(strip, 6, 16, 0, 16)
	col.add_child(_mv_strip)
	_mv_msg = T.label("", T.ls(T.body(500), 15, T.PAPER), HORIZONTAL_ALIGNMENT_CENTER, true)
	_mv_msg.custom_minimum_size.y = 20
	col.add_child(T.margin(_mv_msg, 8, 16, 10, 16))


## Full-screen "Still There". on_done runs once, when the video ends or is skipped.
func play_video(on_done: Callable) -> void:
	_video_cb = on_done
	_video_done = false
	_video_t = 0.0
	_video_last_pos = -1.0
	_mv_msg.text = ""
	_mv_pause.text = "Pause"
	_mv_strip.visible = true
	_mv_bar.set_value(0.0, false)
	_mv_time.text = "0:00"
	mv.visible = true
	_mv_skip.grab_focus.call_deferred()
	var stream: VideoStream = null
	if ResourceLoader.exists(VIDEO_PATH):
		var res = load(VIDEO_PATH)
		if res is VideoStream:
			stream = res
	if stream == null:
		_video_failed()
		return
	_player.stream = stream
	_player.paused = false
	_player.play()


func _video_failed() -> void:
	_mv_msg.text = VIDEO_FAIL
	_mv_strip.visible = false
	if _player.is_playing():
		_player.stop()


func _video_tick(delta: float) -> void:
	_video_t += delta
	var playing := _player.stream != null and _player.is_playing()
	var pos := _player.stream_position if playing else 0.0
	var length := _player.get_stream_length() if _player.stream else 0.0
	if playing:
		_mv_time.text = T.fmt(pos) + (" / " + T.fmt(length) if length > 0.0 else "")
		_mv_bar.set_value(pos / length if length > 0.0 else 0.0, false)
		var tex := _player.get_video_texture()
		if tex and tex.get_height() > 0:
			var r := float(tex.get_width()) / tex.get_height()
			if absf(r - _aspect.ratio) > 0.01:
				_aspect.ratio = r
	# The JS shows the failure message when the source errors; Theora has no error signal,
	# so call it failed when nothing has started playing after 2.5 s.
	if _mv_msg.text == "" and _video_t > 2.5 and (not playing or pos <= 0.0) and not _player.paused:
		_video_failed()


func _finish_video() -> void:
	if _video_done:
		return
	_stop_video()
	var cb := _video_cb
	_video_cb = Callable()
	if cb.is_valid():
		cb.call_deferred()


func _stop_video() -> void:
	_drop_focus()
	_video_done = true
	if _player.is_playing():
		_player.stop()
	_player.stream = null
	mv.visible = false
