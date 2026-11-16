extends RefCounted
## A song as written in the notebook (song_notebook.gd): its sheet, one Dictionary, kept in the save
## (player_state.gd: `song_draft` while it is being written, `song_written` once saved, `song_sheets` once
## recorded at the booth mic, in step with `songs`).
##
##   {"title": "THIS IS FOR THE BLOCK", "beat": "iron",
##    "hook":   [card, card]                the two halves of one hook (hook_<name>_a, _b); [] until picked
##    "verse1": [card, card, card, card]    {} for a slot not filled yet
##    "verse2": [card, card, card, card],
##    "day": the day it was written (1 is the first), "written": true once saved,
##    "recorded": the day it was recorded at the mic (once it is), "score": song_score.gd's, once performed}
##   card: {"id": "glass_01", "slot": the id of the word in its slot (rules/words.json; "" if it has no slot),
##          "lines": its two lines as sung, {"text", "syl"} each, the slot word in,
##          "standing": "starter", "earned" or "cap" (as he wrote it; again when he recorded it),
##          "true": it claims something he did, "deed": what unlocks it ("" for a starter card), "count": how often}
##
## A song recorded with nothing written (a freestyle at the mic) has {"freestyle": true, "beat", "day", "score"};
## a song from a save older than the notebook has {}. Which true bars he has put out: true_bars(state).

const Bars := preload("res://scripts/bars.gd")
const ROWS := ["hook", "verse1", "verse2"]
const SIZE := {"hook": 2, "verse1": 4, "verse2": 4}
const ORDER := ["verse1", "hook", "verse2", "hook"]      # as performed: each card two bars, a line a bar


## A fresh page on that beat.
static func blank(beat_id: String, day: int) -> Dictionary:
	return {"title": "", "beat": beat_id, "hook": [], "verse1": [{}, {}, {}, {}], "verse2": [{}, {}, {}, {}], "day": day,
		"written": false, "score": {}}


## What a song recorded with nothing written keeps: its beat, the day, a fixed low score.
static func freestyle(beat_id: String, day: int, score: Dictionary) -> Dictionary:
	return {"freestyle": true, "beat": beat_id, "day": day, "written": false, "score": score}


## A sheet written in the notebook and saved, with every slot filled (not a freestyle, not an older save's {}).
static func is_written(sheet: Dictionary) -> bool:
	return bool(sheet.get("written", false)) and complete(sheet)


## Every slot filled and a title chosen.
static func complete(sheet: Dictionary) -> bool:
	return filled(sheet) == 10 and String(sheet.get("title", "")) != ""


## How many of the ten cards (two of the hook, eight of the verses) are in.
static func filled(sheet: Dictionary) -> int:
	var n := 0
	for row: String in ROWS:
		for e: Variant in sheet.get(row, []):
			if typeof(e) == TYPE_DICTIONARY and String(e.get("id", "")) != "":
				n += 1
	return n


## The card in a slot ({} if it is empty).
static func at(sheet: Dictionary, row: String, i: int) -> Dictionary:
	var cards: Array = sheet.get(row, [])
	return cards[i] if i >= 0 and i < cards.size() and typeof(cards[i]) == TYPE_DICTIONARY else {}


## The hook's name: "block" for hook_block_a or _b ("" for a card that is not half of a hook).
static func hook_name(cid: String) -> String:
	if not cid.begins_with("hook_") or cid.length() < 8:
		return ""
	return cid.substr(5, cid.length() - 7)


## Every hook there is, by name, in the bank's order.
static func hooks() -> Array:
	var out: Array = []
	for cid: String in Bars.ids():
		if cid.ends_with("_a") and hook_name(cid) != "" and not hook_name(cid) in out:
			out.append(hook_name(cid))
	return out


## The cards that go in a verse (every card that is not half of a hook), in the bank's order.
static func verse_cards() -> Array:
	return Bars.ids().filter(func(cid: String) -> bool: return not "hook" in (Bars.card(cid)["tags"] as Array))


## One card as the sheet keeps it, with `word` in its slot (its own word when "").
static func entry(state: RefCounted, cid: String, word := "") -> Dictionary:
	var c := Bars.card(cid)
	if c.is_empty():
		return {}
	var slot := ""
	if c.has("slot"):
		var words := Bars.slot_words(state, cid)
		slot = word if word != "" else (String(words[0]["id"]) if not words.is_empty() else "")
	return {"id": cid, "slot": slot, "lines": lines_of(state, cid, slot), "standing": Bars.standing(state, cid), "true": bool(c["true"]),
		"deed": String(c["unlock"]["deed"]) if c.has("unlock") else "", "count": int(c["unlock"]["count"]) if c.has("unlock") else 0}


## A card's two lines with `word` in its slot (Bars.slot_words; a word he no longer has, such as a weapon taken
## off him, is put in all the same).
static func lines_of(state: RefCounted, cid: String, word: String) -> Array:
	var c := Bars.card(cid)
	if c.is_empty():
		return []
	if word == "" or not c.has("slot"):
		return (c["lines"] as Array).duplicate(true)
	for w: Dictionary in Bars.slot_words(state, cid):
		if String(w["id"]) == word:
			return (w["lines"] as Array).duplicate(true)
	var at := int(c["slot"]["line"])
	var entries: Array = Bars.word_list(String(c["slot"]["from"])).get("entries", [])
	var found: Array = Bars._default_of(c["lines"][at], entries)
	for e: Dictionary in entries:
		if String(e["id"]) == word and int(found[1]) > 0:
			var got := Bars.fill(c["lines"][at], int(found[1]), e)
			if not got.is_empty():
				var lines: Array = (c["lines"] as Array).duplicate(true)
				lines[at] = got
				return lines
	return (c["lines"] as Array).duplicate(true)


## The words that may go in a slot's card: [{"id", "text", "default"}], [] if it has no slot.
static func words_for(state: RefCounted, sheet: Dictionary, row: String, i: int) -> Array:
	var e := at(sheet, row, i)
	if e.is_empty():
		return []
	return Bars.slot_words(state, String(e["id"])).map(func(w: Dictionary) -> Dictionary:
		return {"id": w["id"], "text": w["text"], "default": w["default"]})


## Put a card in a slot. On the hook row either half puts the whole hook in.
static func put(state: RefCounted, sheet: Dictionary, row: String, i: int, cid: String, word := "") -> void:
	if row == "hook":
		var name := hook_name(cid)
		if name == "":
			return
		sheet["hook"] = [entry(state, "hook_%s_a" % name), entry(state, "hook_%s_b" % name)]
		if String(sheet.get("title", "")) == "" or not String(sheet["title"]) in titles(sheet):
			var all := titles(sheet)
			sheet["title"] = String(all[0]) if not all.is_empty() else ""
		return
	if not sheet.has(row) or i < 0 or i >= int(SIZE[row]):
		return
	var e := entry(state, cid, word)
	if not e.is_empty():
		sheet[row][i] = e


## Take the card out of a slot (on the hook row, the hook).
static func take_out(sheet: Dictionary, row: String, i: int) -> void:
	if row == "hook":
		sheet["hook"] = []
		sheet["title"] = ""
	elif sheet.has(row) and i >= 0 and i < (sheet[row] as Array).size():
		sheet[row][i] = {}


## Another word in a slot's card.
static func set_word(state: RefCounted, sheet: Dictionary, row: String, i: int, word: String) -> void:
	var e := at(sheet, row, i)
	if not e.is_empty() and String(e.get("slot", "")) != "":
		sheet[row][i] = entry(state, String(e["id"]), word)


## Each card's standing again, as it is now (he may have earned one since he wrote it).
static func refresh(state: RefCounted, sheet: Dictionary) -> void:
	for row: String in ROWS:
		for e: Variant in sheet.get(row, []):
			if typeof(e) == TYPE_DICTIONARY and String(e.get("id", "")) != "":
				e["standing"] = Bars.standing(state, String(e["id"]))


## The cards as performed: [{"row", "i", "card"}] for verse 1, the hook, verse 2, the hook (empty slots left in, as {}).
static func performed(sheet: Dictionary) -> Array:
	var out: Array = []
	for row: String in ORDER:
		for i in int(SIZE[row]):
			out.append({"row": row, "i": i, "card": at(sheet, row, i)})
	return out


## The ten cards of the sheet once each (verse 1, the hook, verse 2), the empty ones left out: [{"row", "i", "card"}].
static func cards(sheet: Dictionary) -> Array:
	var out: Array = []
	for row: String in ["verse1", "hook", "verse2"]:
		for i in int(SIZE[row]):
			var e := at(sheet, row, i)
			if not e.is_empty() and String(e.get("id", "")) != "":
				out.append({"row": row, "i": i, "card": e})
	return out


## Titles to pick from, built from the hook's own words: each part of a line between commas that is two to five
## words long, and the last three words of each longer line. [] until there is a hook.
static func titles(sheet: Dictionary, most := 5) -> Array:
	var out: Array = []
	for e: Variant in sheet.get("hook", []):
		if typeof(e) != TYPE_DICTIONARY:
			continue
		for line: Variant in e.get("lines", []):
			var text := String(line.get("text", ""))
			for part: String in text.split(","):
				var words := part.strip_edges().split(" ", false)
				if words.size() >= 2 and words.size() <= 5:
					_add_title(out, " ".join(words))
			var all := text.replace(",", " ").split(" ", false)
			if all.size() > 5:
				_add_title(out, " ".join(all.slice(all.size() - 3)))
	return out.slice(0, most)


static func _add_title(out: Array, words: String) -> void:
	var t := words.to_upper().strip_edges()
	while t != "" and t[t.length() - 1] in ".!?;:-\"":
		t = t.left(t.length() - 1)
	if t != "" and not t in out:
		out.append(t)


## Fill every empty slot from a seed (a --do step; the notebook never does this by itself). `only` keeps to
## some cards: "any", "mine" (not cap), "starter", "earned", "true" (earned, and a claim), "cap". A verse card
## after the first is one that follows the card before (Bars.follows) three times in four, when one does.
static func fill(state: RefCounted, sheet: Dictionary, seed_value: int, only := "any") -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var ok := func(cid: String) -> bool:
		var standing := Bars.standing(state, cid)
		match only:
			"mine":
				return standing != "cap"
			"starter":
				return standing == "starter"
			"earned":
				return standing == "earned"
			"true":
				return standing == "earned" and bool(Bars.card(cid)["true"])
			"cap":
				return standing == "cap"
		return true
	if (sheet.get("hook", []) as Array).size() < 2:
		var names := hooks().filter(func(n: String) -> bool: return ok.call("hook_%s_a" % n))
		if names.is_empty():
			names = hooks()
		if not names.is_empty():
			put(state, sheet, "hook", 0, "hook_%s_a" % names[rng.randi() % names.size()])
	var used := {}
	for c: Dictionary in cards(sheet):
		used[String(c["card"]["id"])] = true
	var pool := verse_cards().filter(func(cid: String) -> bool: return ok.call(cid))
	if pool.is_empty():
		pool = verse_cards()
	for row: String in ["verse1", "verse2"]:
		for i in 4:
			if not at(sheet, row, i).is_empty():
				continue
			var free := pool.filter(func(cid: String) -> bool: return not used.has(cid))
			if free.is_empty():
				free = pool.duplicate()
			var pick := String(free[rng.randi() % free.size()])
			var before := at(sheet, row, i - 1) if i > 0 else {}
			if not before.is_empty():
				var next := Bars.follows(String(before["id"])).filter(func(cid: String) -> bool: return free.has(cid))
				if not next.is_empty() and rng.randf() < 0.75:
					pick = String(next[rng.randi() % next.size()])
			var word := ""
			var words := Bars.slot_words(state, pick)
			if not words.is_empty():
				word = String(words[rng.randi() % words.size()]["id"])
			put(state, sheet, row, i, pick, word)
			used[pick] = true
	if String(sheet.get("title", "")) == "":
		var all := titles(sheet)
		if not all.is_empty():
			sheet["title"] = String(all[rng.randi() % all.size()])


## The true bars he has put out: every card of every song recorded that claims a deed he had done when he
## recorded it. [{"song" (1 is the first), "title", "card", "deed", "lines" (the two lines' words)}]
static func true_bars(state: RefCounted) -> Array:
	var out: Array = []
	var sheets: Array = state.song_sheets
	for n in sheets.size():
		var sheet: Dictionary = sheets[n]
		if not is_written(sheet):
			continue
		for c: Dictionary in cards(sheet):
			var e: Dictionary = c["card"]
			if bool(e.get("true", false)) and String(e.get("standing", "")) == "earned":
				out.append({"song": n + 1, "title": String(sheet.get("title", "")), "card": String(e["id"]), "deed": String(e.get("deed", "")),
					"lines": (e.get("lines", []) as Array).map(func(l: Variant) -> String: return String(l.get("text", "")))})
	return out


## Where a slot is in the song, for people: "VERSE 1, BARS 3-4", "HOOK".
static func where(row: String, i: int, words: Dictionary) -> String:
	if row == "hook":
		return String(words.get("hook", "HOOK"))
	return "%s, %s" % [String(words.get(row, row.to_upper())), String(words.get("bars", "BARS {a}-{b}")).replace("{a}", str(2 * i + 1)).replace("{b}", str(2 * i + 2))]


## The sheet in lines of text, for a --do step to print.
static func describe(sheet: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if sheet.is_empty():
		out.append("an empty sheet (a song from before the notebook)")
		return out
	if bool(sheet.get("freestyle", false)):
		out.append("a freestyle on %s, day %d; score %s" % [String(sheet.get("beat", "")) if String(sheet.get("beat", "")) != "" else "no beat", int(sheet.get("day", 0)), _score_line(sheet.get("score", {}))])
		return out
	out.append("'%s' on %s, day %d, %s%s; %d of 10 cards; score %s" % [String(sheet.get("title", "")), String(sheet.get("beat", "")), int(sheet.get("day", 0)),
		"written" if bool(sheet.get("written", false)) else "a draft", (", recorded day %d" % int(sheet["recorded"])) if sheet.has("recorded") else "",
		filled(sheet), _score_line(sheet.get("score", {}))])
	for row: String in ["verse1", "hook", "verse2"]:
		for i in int(SIZE[row]):
			var e := at(sheet, row, i)
			if e.is_empty():
				out.append("  %-7s %d  (empty)" % [row, i + 1])
				continue
			var lines: Array = e.get("lines", [])
			out.append("  %-7s %d  %-14s %-7s%s%s  %s / %s" % [row, i + 1, String(e["id"]), String(e.get("standing", "")), " true" if bool(e.get("true", false)) else "",
				(" [%s]" % String(e["slot"])) if String(e.get("slot", "")) != "" else "",
				String(lines[0].get("text", "")) if lines.size() > 0 else "", String(lines[1].get("text", "")) if lines.size() > 1 else ""])
	return out


static func _score_line(score: Variant) -> String:
	if typeof(score) != TYPE_DICTIONARY or (score as Dictionary).is_empty():
		return "none yet"
	var s: Dictionary = score
	return "flow %d, coherence %d, authenticity %d, freshness %d: total %d" % [int(s.get("flow", -1)), int(s.get("coherence", 0)),
		int(s.get("authenticity", 0)), int(s.get("freshness", 0)), int(s.get("total", 0))]
