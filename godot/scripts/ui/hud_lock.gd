extends PanelContainer
## #lock: the minigame panel (minigames.js): the whistle on the beat ("rhythm"), the ruler
## ("ruler") and recording the snoring ("record"). Driven by Hud.lock_open/update/msg/close.

const T := preload("res://scripts/ui/hud_theme.gd")
const Wd := preload("res://scripts/ui/hud_widgets.gd")

var kind := ""
var eye_l: Label
var title_l: Label
var body: VBoxContainer
var msg_l: Label
var track
var ruler
var vu
var value_l: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", T.box(T.PAPER, [10, 14, 12, 14], 3, 0, Color(0, 0, 0, 0), Vector2(5, 5), T.a(T.BLACK, 0.4)))
	custom_minimum_size = Vector2(440, 0)
	var col := T.vbox(6)
	add_child(col)
	eye_l = T.label("", T.ls(T.spaced(T.mono(true), 2), 11, T.SIREN))
	col.add_child(eye_l)
	title_l = T.label("", T.ls(T.disp(20), 20, T.INK, [], 1.05), HORIZONTAL_ALIGNMENT_LEFT, true)
	col.add_child(T.tight(title_l))
	body = T.vbox(6)
	col.add_child(body)
	msg_l = T.label("", T.ls(T.mono(), 13, T.INK, [], 1.35), HORIZONTAL_ALIGNMENT_LEFT, true)
	col.add_child(msg_l)


func open(k: String, eye: String, title: String, msg: String) -> void:
	kind = k
	eye_l.text = eye
	title_l.text = T.caps(title)
	msg_l.text = msg
	for ch in body.get_children():
		ch.queue_free()
	track = null
	ruler = null
	vu = null
	value_l = null
	match k:
		"rhythm":
			track = Wd.Track.new()
			body.add_child(T.margin(track, 4, 0, 4, 0))
		"ruler":
			ruler = Wd.Ruler.new()
			body.add_child(T.margin(ruler, 4, 0, 4, 0))
			body.add_child(_read_row("Reading: ", "0 in"))
		"record":
			vu = Wd.Vu.new()
			body.add_child(vu)
			body.add_child(_read_row("Snores on tape: ", "0/3"))
	visible = true


func _read_row(caption: String, value: String) -> HBoxContainer:
	var row := T.hbox(0)
	row.add_child(T.label(caption, T.ls(T.mono(), 13, T.INK)))
	value_l = T.label(value, T.ls(T.mono(true), 13, T.INK))
	row.add_child(value_l)
	return row


## rhythm: {"head": 0..1, "hit": pip index just hit or -1}
## ruler:  {"needle": 0..1, "reading": "1/4 in"}
## record: {"vu": 0..1, "count": "2/3"}
func update(k: String, data: Dictionary) -> void:
	if k != kind:
		return
	match k:
		"rhythm":
			if track:
				track.head = float(data.get("head", track.head))
				var hit := int(data.get("hit", -1))
				if hit >= 0 and hit < track.hits.size():
					track.hits[hit] = true
				track.queue_redraw()
		"ruler":
			if ruler:
				ruler.needle = float(data.get("needle", ruler.needle))
				ruler.queue_redraw()
			if value_l and data.has("reading"):
				value_l.text = str(data["reading"])
		"record":
			if vu:
				vu.level = float(data.get("vu", vu.level))
				vu.queue_redraw()
			if value_l and data.has("count"):
				value_l.text = str(data["count"])


func set_msg(text: String) -> void:
	msg_l.text = text


func close() -> void:
	kind = ""
	visible = false
