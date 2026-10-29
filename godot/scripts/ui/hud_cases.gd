extends VBoxContainer
## #cases: the case file, one incident ticket per active crime, sorted by time left
## (no-limit cases last), refreshed by the HUD every 0.15 s (hud.js updateHUD).

const T := preload("res://scripts/ui/hud_theme.gd")
const Wd := preload("res://scripts/ui/hud_widgets.gd")
const St := preload("res://scripts/ui/hud_state.gd")

var _cards := {}   # crime id -> Card


func _init() -> void:
	add_theme_constant_override("separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(270, 0)


func refresh() -> void:
	var all := St.crimes()
	var order := {}
	for i in all.size():
		order[all[i]] = i
	var list := []
	for c in all:
		if St.active(c):
			list.append(c)
	list.sort_custom(func(a, b):
		var la := St.left(a)
		var lb := St.left(b)
		var ia := is_inf(la)
		var ib := is_inf(lb)
		if ia != ib:
			return ib
		if not ia and la != lb:
			return la < lb
		return order[a] < order[b])
	var keep := {}
	for c in list:
		keep[str(St.field(c, "id", ""))] = true
	for id in _cards.keys():
		if not keep.has(id):
			_cards[id].queue_free()
			_cards.erase(id)
	var bino := St.bino_on()
	var yaw := float(St.gv("bino_yaw", 0.0)) if bino else float(St.gv("cam_yaw", 0.0))
	var pl = St.xz(St.gv("P"))
	if pl == null:
		pl = Vector2.ZERO
	for i in list.size():
		var c = list[i]
		var id := str(St.field(c, "id", ""))
		var card: Card = _cards.get(id)
		if card == null:
			card = Card.new()
			_cards[id] = card
			add_child(card)
		if card.get_index() != i:
			move_child(card, i)
		card.refresh(c, pl, yaw)


func clear_all() -> void:
	for id in _cards:
		_cards[id].queue_free()
	_cards.clear()


# ------------------------------------------------------------------------------ one card
class Card extends PanelContainer:
	static var _styles := {}
	var no_l: Label
	var t_l: Label
	var who_l: Label
	var arrow
	var dist_l: Label
	var nx: RichTextLabel
	var chip: PanelContainer
	var chip_l: Label
	var tm_l: Label
	var bar
	var _look := ""
	var _nx_text := "~"
	var _tm_ls: LabelSettings
	var _tm_urgent_ls: LabelSettings
	var _chip_ls: LabelSettings
	var _chip_ev_ls: LabelSettings

	static func style(key: String) -> StyleBox:
		if _styles.has(key):
			return _styles[key]
		var s: StyleBox
		match key:
			"card", "ev", "dis", "gary":
				var stripe: Color = {"card": T.SIREN, "ev": T.TICKET, "dis": T.COP, "gary": T.GARY}[key]
				s = T.striped(T.PAPER, [7, 10, 8, 12], 3, stripe, 5, Vector2(3, 3), T.a(T.BLACK, 0.35))
			"chip", "chip_ev", "chip_dis", "chip_gary":
				var bg: Color = {"chip": T.SIREN, "chip_ev": T.INK, "chip_dis": T.COP, "chip_gary": T.GARY_CHIP}[key]
				s = T.box(bg, [1, 6, 1, 6], 2)
		_styles[key] = s
		return s

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_stylebox_override("panel", style("card"))
		var col := T.vbox(2)
		add_child(col)
		var top := T.hbox(8)
		col.add_child(top)
		var left := T.vbox(2)
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(left)
		var no_ls := T.ls(T.spaced(T.mono(), 1), 10, T.a(T.INK, 0.7))
		no_l = T.label("", no_ls)
		left.add_child(no_l)
		t_l = T.label("", T.ls(T.body(700), 16, T.INK, [], 1.05), HORIZONTAL_ALIGNMENT_LEFT, true)
		left.add_child(T.tight(t_l))
		who_l = T.label("", T.ls(T.mono(), 12, T.INK))
		who_l.clip_text = true
		who_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		left.add_child(who_l)
		var dir := T.vbox(1)
		dir.alignment = BoxContainer.ALIGNMENT_CENTER
		dir.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(dir)
		arrow = Wd.Arrow.new()
		dir.add_child(arrow)
		dist_l = T.label("", T.ls(T.mono(), 11, T.INK), HORIZONTAL_ALIGNMENT_CENTER)
		dir.add_child(dist_l)
		var nb := Wd.NextBlock.new()
		col.add_child(nb)
		nx = RichTextLabel.new()
		nx.fit_content = true
		nx.scroll_active = false
		nx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nx.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nx.add_theme_color_override("default_color", T.INK)
		nx.add_theme_constant_override("line_separation", -2)
		nb.add_child(nx)
		var st := T.hbox(4)
		col.add_child(T.margin(st, 3))
		_chip_ls = T.ls(T.spaced(T.mono(true), 1), 11, T.PAPER)
		_chip_ev_ls = T.ls(T.spaced(T.mono(true), 1), 11, T.TICKET)
		chip_l = T.label("", _chip_ls)
		chip = T.panel(style("chip"), chip_l)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		st.add_child(chip)
		st.add_child(T.expander())
		_tm_ls = T.ls(T.spaced(T.mono(), 1), 11, T.INK)
		_tm_urgent_ls = T.ls(T.spaced(T.mono(true), 1), 11, T.SIREN)
		tm_l = T.label("", _tm_ls, HORIZONTAL_ALIGNMENT_RIGHT)
		tm_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		st.add_child(tm_l)
		bar = Wd.Bar.new()
		col.add_child(bar)

	static func _put(l: Label, s: String) -> void:
		if l.text != s:
			l.text = s

	func refresh(c, pl: Vector2, yaw: float) -> void:
		var id := str(St.field(c, "id", ""))
		var dispatched := bool(St.field(c, "dispatched", false))
		var handling := bool(St.field(c, "handling", false))
		var si := int(St.field(c, "si", 0))
		var left := St.left(c)
		var full := maxf(0.001, float(St.field(c, "full", 1.0)))
		var st := St.cur(c)
		var k := St.kind(st)
		var lost := k == "lead" and St.dan_lost()
		var urgent := not dispatched and not handling and left < 15.0
		var ev := not dispatched and si > 0
		# looks (the CSS cascade: .gary wins the stripe and the chip background)
		var look := "gary" if id == "gary" else ("dis" if dispatched else ("ev" if ev else "card"))
		var chip_look := "chip_gary" if id == "gary" else ("chip_dis" if dispatched else ("chip_ev" if ev else "chip"))
		var key := look + "|" + chip_look + "|" + str(ev) + "|" + str(urgent)
		if key != _look:
			_look = key
			add_theme_stylebox_override("panel", style(look))
			chip.add_theme_stylebox_override("panel", style(chip_look))
			chip_l.label_settings = _chip_ev_ls if ev else _chip_ls
			tm_l.label_settings = _tm_urgent_ls if urgent else _tm_ls
		_put(no_l, "CASE #0911-%03d" % int(St.field(c, "no", 0)))
		_put(t_l, str(St.field(c, "title", "")).to_upper())
		_put(who_l, str(St.field(c, "who", "")))
		var t := St.mark(c)
		var dx := t.x - pl.x
		var dz := t.z - pl.y
		arrow.ang = -(atan2(dx, dz) - yaw)
		_put(dist_l, "%d ft" % roundi(sqrt(dx * dx + dz * dz) * 3.3))
		var text := "Cops on the way." if dispatched else ("Going down right now." if handling else St.step_text(st))
		if text != _nx_text:
			_nx_text = text
			nx.clear()
			nx.push_font(T.spaced(T.mono(true), 1), 10)
			nx.push_color(T.SIREN)
			nx.add_text("NEXT ")
			nx.pop()
			nx.pop()
			nx.push_font(T.body(600), 15)
			nx.add_text(text)
			nx.pop()
		var steps = St.field(c, "steps", [])
		var n_steps: int = steps.size() if steps is Array else 0
		_put(chip_l, "DISPATCHED" if dispatched else ("GOING DOWN" if handling else ("DAN STOPPED" if lost else "STEP %d/%d" % [si + 1, n_steps])))
		_put(tm_l, "no rush" if is_inf(left) else ("paused" if (dispatched or handling) else T.fmt(left)))
		bar.set_value(1.0 if is_inf(left) else clampf(left / full, 0.0, 1.0), urgent)
