extends Control
## Lines of a song on screen, each syllable lighting up as it sounds (the notebook's HEAR strip, the booth
## mic's couplets). The owner sets `rows` (row() makes one from a card's line and the bar it is sung on) and
## `now` (the clock's time) each frame; under each strong syllable (stress 2) a short mark, which turns
## gold for a PERFECT, paper for a GOOD and red for a MISS once the take has judged it.

const Bars := preload("res://scripts/bars.gd")
const FONT := preload("res://assets/fonts/Bungee-Regular.ttf")
const PAPER := Color("#f6f1e3")
const TICKET := Color("#f2d24a")
const SHORT := Color("#e2483a")
const UNLIT := Color(0.96, 0.94, 0.89, 0.5)
const DIM := Color(0.96, 0.94, 0.89, 0.34)
const MARK_H := 5.0

var rows: Array = []        # each {"text" (capitals), "parts": [[from, to, syllable]], "times", "stress", "marks", "size", "dim"}
var now := -INF             # the clock's time
var centred := true
var gap := 6.0              # between rows
var marks := true           # the strong syllables' marks
var lead := 0.0             # > 0 (the mic): a strong syllable's mark fills, gold from the left, over this many seconds
                            # before it is due, full on the step (when to press Space)


## A row for one line {"text", "syl"} sung on `at_bar` (times from the clock), `size` its font size; dim: the
## couplet still to come (no lighting).
static func row(line: Dictionary, at_bar: int, clock: Node, font_size: int, dim := false) -> Dictionary:
	var text := String(line.get("text", "")).to_upper()
	var syl: Array = line.get("syl", [])
	var times: Array = []
	var stress: Array = []
	var marks_now: Array = []
	for s: Array in syl:
		times.append(float(clock.time_of(at_bar, float(s[0]))) if clock else 0.0)
		stress.append(int(s[2]))
		marks_now.append("")
	return {"text": text, "parts": parts_of(text, syl), "times": times, "stress": stress, "marks": marks_now, "size": font_size, "dim": dim}


## The text cut into runs, each the syllable that owns it: [[from, to, k]]. A syllable owns its own letters and
## whatever follows up to the next one's (a space, a comma); anything before the first belongs to the first.
static func parts_of(text: String, syl: Array) -> Array:
	var starts: Array = []
	var i := 0
	for s: Array in syl:
		var want := Bars.letters(String(s[1])).length()
		while i < text.length() and not _alnum(text.unicode_at(i)):
			i += 1
		starts.append(i)
		var got := 0
		while i < text.length() and got < want:
			if _alnum(text.unicode_at(i)):
				got += 1
			i += 1
	var out: Array = []
	for k in starts.size():
		var from: int = 0 if k == 0 else int(starts[k])
		var to: int = text.length() if k == starts.size() - 1 else int(starts[k + 1])
		if to > from:
			out.append([from, to, k])
	if out.is_empty() and text != "":
		out.append([0, text.length(), 0])
	return out


func set_rows(new_rows: Array) -> void:
	rows = new_rows
	var h := 0.0
	for r: Dictionary in rows:
		h += _row_h(int(r["size"])) + gap
	custom_minimum_size.y = maxf(h - gap, 0.0)
	queue_redraw()


func _process(_delta: float) -> void:
	if is_visible_in_tree() and not rows.is_empty():
		queue_redraw()


func _row_h(fs: int) -> float:
	return FONT.get_height(fs) + (MARK_H + 6.0 if marks else 0.0)


func _draw() -> void:
	var y := 0.0
	for r: Dictionary in rows:
		var fs := int(r["size"])
		var text := String(r["text"])
		var width := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var x := (size.x - width) * 0.5 if centred else 0.0
		var base := y + FONT.get_ascent(fs)
		var times: Array = r["times"]
		var dim := bool(r.get("dim", false))
		for part: Array in r["parts"]:
			var piece := text.substr(int(part[0]), int(part[1]) - int(part[0]))
			var k := int(part[2])
			var lit := not dim and k < times.size() and now >= float(times[k])
			var colour := DIM if dim else (TICKET if lit else UNLIT)
			var w := FONT.get_string_size(piece, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string_outline(FONT, Vector2(x, base), piece, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(roundi(fs * 0.22), 3), Color(0, 0, 0, 0.85 if not dim else 0.6))
			draw_string(FONT, Vector2(x, base), piece, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, colour)
			if marks and k < (r["stress"] as Array).size() and int(r["stress"][k]) == 2:
				var letters_w := FONT.get_string_size(piece.strip_edges().rstrip(",.!?;:'\""), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				var mark := String(r["marks"][k]) if k < (r["marks"] as Array).size() else ""
				var c := UNLIT if dim else Color(PAPER, 0.4)
				match mark:
					"perfect":
						c = TICKET
					"good":
						c = PAPER
					"miss":
						c = SHORT
				if lit and mark == "":
					c = Color(TICKET, 0.75)
				var top := base + 6.0
				draw_rect(Rect2(x - 1.0, top - 1.0, letters_w + 2.0, MARK_H + 2.0), Color(0, 0, 0, 0.7 if not dim else 0.4))
				draw_rect(Rect2(x, top, letters_w, MARK_H), c)
				var due := float(times[k]) if k < times.size() else INF
				if lead > 0.0 and not dim and mark == "" and now < due and now >= due - lead:
					draw_rect(Rect2(x, top, letters_w * (1.0 - (due - now) / lead), MARK_H), TICKET)
			x += w
		y += _row_h(fs) + gap


static func _alnum(u: int) -> bool:
	return (u >= 48 and u <= 57) or (u >= 65 and u <= 90) or (u >= 97 and u <= 122)
