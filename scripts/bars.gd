extends RefCounted
## The bar cards of the song system (the words half): every pack in assets/data/bars/, each card checked as
## it is read. A card that breaks a rule is refused by name (a warning) and left out; nothing here fails on a
## bad file. What he may rap is decided here from the deeds ledger (player_state.gd's deeds; deeds.gd):
## a starter card needs no deed, an earned one has had its deed done often enough, every other card is "cap"
## (he may still use it: a claim he has not lived, which someone may call out; what that costs is decided later).
##
## A pack is {"about", "cards": [...]}; a card is
##   {"id", "lines": [{"text", "syl": [[step, syllable, stress] ...]}, {...}], "rhyme", "tags", "true",
##    "unlock": {"deed", "count"} (left out for a starter card), "slot": {"line", "from"} (optional)}
## (workers-20261116-songs.md). The rules a card keeps are tools/validate_bars.py's, rule for rule (its top
## says them); that checker proves the packs, and bars:check (bars_steps.gd) prints this file's fill digest,
## which is its --digest when the two fill a slot the same way. Numbers come out of here whole (int), as the
## voice (rap_voice.gd) wants them.
##
## A slot: the end of one line may be swapped for an entry of a list in rules/words.json (places he has been,
## people he has met, weapons he owns or keeps in the stash). The entry's last strong syllable goes on the step
## the card's own word had its strong one; the syllables before it go 2 sixteenths apart (1 if 2 would run into
## the syllable before the slot), those after it 2 apart (1 if 2 would pass step 15).

const DIR := "res://assets/data/bars/"
const RHYMES := "res://assets/data/bars/rules/rhymes.json"
const WORDS := "res://assets/data/bars/rules/words.json"
const Deeds := preload("res://scripts/deeds.gd")
const FIELDS := ["id", "lines", "rhyme", "tags", "true", "unlock", "slot"]
const FLOWS := ["on_beat", "behind", "double", "rests"]

static var _cards := {}            # id to card: every card that passed
static var _order: Array = []      # their ids, pack by pack (the packs by file name), as written
static var _pack_of := {}          # id to its pack's file name
static var _refused: Array = []    # each card refused (and each file that is not a pack): "pack id: what is wrong"
static var _families := {}         # rules/rhymes.json's families
static var _lists := {}            # rules/words.json's lists (entries that are not right are left out, and refused)
static var _loaded := false
static var _rules_read := false
static var _word_re: RegEx = null
static var _hook_re: RegEx = null
static var _id_re: RegEx = null


# ------------------------------------------------------------ reading

## Read every pack (once; `again` reads them afresh). Each refused card is a warning, by name.
static func load_all(again := false) -> void:
	if _loaded and not again:
		return
	_loaded = true
	load_rules(again)
	_cards = {}
	_order = []
	_pack_of = {}
	_refused = _refused.filter(func(r: String) -> bool: return r.begins_with("words.json"))
	var files := Array(DirAccess.get_files_at(DIR))
	files.sort()
	for file: String in files:
		if not file.ends_with(".json"):
			continue
		var got := parse_pack(file, FileAccess.get_file_as_string(DIR + file), _pack_of)
		_refused.append_array(got["refused"])
		for one: Dictionary in got["cards"]:
			_cards[one["id"]] = one
			_order.append(one["id"])
			_pack_of[one["id"]] = file
	for cid: String in _order.duplicate():
		var why := hook_problem(cid, _cards) if _cards.has(cid) else ""
		if why != "":
			_refused.append("%s %s: %s" % [_pack_of[cid], cid, why])
			_cards.erase(cid)
			_order.erase(cid)
	for r: String in _refused:
		push_warning("Bar card refused: " + r)


## The rules files: the rhyme families and the lists of words.
static func load_rules(again := false) -> void:
	if _rules_read and not again:
		return
	_rules_read = true
	_families = _json(RHYMES).get("families", {})
	_lists = {}
	_refused = []
	var lists: Dictionary = _json(WORDS).get("lists", {})
	for name: String in lists:
		var kept: Array = []
		var raw: Variant = lists[name].get("entries", []) if typeof(lists[name]) == TYPE_DICTIONARY else []
		for e: Variant in (raw if typeof(raw) == TYPE_ARRAY else []):
			var why := _entry_problem(e)
			if why != "":
				_refused.append("words.json %s/%s: %s" % [name, e.get("id") if typeof(e) == TYPE_DICTIONARY else "?", why])
				continue
			var syl: Array = []
			for s: Array in e["syl"]:
				syl.append([String(s[0]), int(s[1])])
			e["syl"] = syl
			kept.append(e)
		_lists[name] = {"about": lists[name].get("about", "") if typeof(lists[name]) == TYPE_DICTIONARY else "", "entries": kept}


## One pack's text (a file's): {"cards": the cards that pass, "refused": each one refused, by name}. `taken` is id to
## pack for the ids read already, from other packs (an id read twice is refused). Anything that is not a pack is refused.
static func parse_pack(file: String, text: String, taken: Dictionary) -> Dictionary:
	load_rules()
	var good: Array = []
	var turned: Array = []
	var json := JSON.new()
	if json.parse(text) != OK:            # (JSON.parse_string would print an engine error)
		turned.append("%s: not JSON (%s, line %d)" % [file, json.get_error_message(), json.get_error_line() + 1])
		return {"cards": good, "refused": turned}
	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY or data.size() != 2 or not data.has("about") or typeof(data.get("cards")) != TYPE_ARRAY:
		turned.append("%s: not {\"about\", \"cards\": [...]}" % file)
		return {"cards": good, "refused": turned}
	var mine := {}
	var i := -1
	for one: Variant in data["cards"]:
		i += 1
		var cid: Variant = one.get("id") if typeof(one) == TYPE_DICTIONARY else null
		var bad := problems(one)
		if typeof(cid) == TYPE_STRING and (taken.has(cid) or mine.has(cid)):
			bad.append("the id is also in %s" % taken.get(cid, file))
		if not bad.is_empty():
			turned.append("%s %s: %s" % [file, cid if typeof(cid) == TYPE_STRING else "card %d" % i, "; ".join(PackedStringArray(bad))])
			continue
		_whole_numbers(one)
		mine[cid] = true
		good.append(one)
	return {"cards": good, "refused": turned}


# ------------------------------------------------------------ the rules a card keeps

## What is wrong with a card (empty: nothing). tools/validate_bars.py's card_problems, rule for rule.
static func problems(c: Variant) -> Array:
	load_rules()
	if typeof(c) != TYPE_DICTIONARY:
		return ["not an object"]
	var bad: Array = []
	var extra: Array = []
	for k: Variant in c:
		if not str(k) in FIELDS:
			extra.append(str(k))
	if not extra.is_empty():
		extra.sort()
		bad.append("fields not in the contract: %s" % ", ".join(PackedStringArray(extra)))
	for need: String in ["id", "lines", "rhyme", "tags", "true"]:
		if not c.has(need):
			bad.append("no %s" % need)
	if not bad.is_empty():
		return bad
	if typeof(c["id"]) != TYPE_STRING or _re("_id_re", "^[a-z0-9_]+$").search(c["id"]) == null:
		bad.append("id %s is not a-z 0-9 _" % _show(c["id"]))
	var rhyme: Variant = c["rhyme"]
	if typeof(rhyme) != TYPE_STRING or not _families.has(rhyme):
		bad.append("rhyme %s is not a family of rhymes.json" % _show(rhyme))
		rhyme = null
	var lines: Variant = c["lines"]
	if typeof(lines) != TYPE_ARRAY or lines.size() != 2:
		bad.append("lines: not two")
		return bad
	for i in 2:
		bad.append_array(line_problems(lines[i], "line %d" % i, rhyme))
	var tags: Variant = c["tags"]
	var tags_ok: bool = typeof(tags) == TYPE_ARRAY and not tags.is_empty()
	if tags_ok:
		for t: Variant in tags:
			tags_ok = tags_ok and typeof(t) == TYPE_STRING and t != ""
	if not tags_ok:
		bad.append("tags: not a list of words")
	else:
		var flows: Array = tags.filter(func(t: String) -> bool: return t in FLOWS)
		if flows.size() != 1:
			bad.append("tags: %d flows (one of %s)" % [flows.size(), ", ".join(PackedStringArray(FLOWS))])
		elif not bad.any(func(b: String) -> bool: return b.begins_with("line")) and not flow_ok(flows[0], lines):
			bad.append("tags: its steps are not the flow it names (%s)" % flows[0])
	if typeof(c["true"]) != TYPE_BOOL:
		bad.append("true: not true or false")
	var unlock: Variant = c.get("unlock")
	if typeof(unlock) != TYPE_NIL:
		if typeof(unlock) != TYPE_DICTIONARY or unlock.size() != 2 or not unlock.has("deed") or not unlock.has("count"):
			bad.append("unlock: not {\"deed\", \"count\"}")
		else:
			if typeof(unlock["deed"]) != TYPE_STRING or not Deeds.known(unlock["deed"]):
				bad.append("unlock: no deed %s in deeds.json" % _show(unlock["deed"]))
			if not _whole(unlock["count"]) or int(unlock["count"]) < 1:
				bad.append("unlock: count %s is not a whole number from 1" % _show(unlock["count"]))
	elif typeof(c["true"]) == TYPE_BOOL and c["true"]:
		bad.append("true: it claims a deed but has no unlock")
	var slot: Variant = c.get("slot")
	if typeof(slot) != TYPE_NIL:
		bad.append_array(_slot_problems(c, slot))
	return bad


## What is wrong with one line {"text", "syl"} (empty: nothing). `rhyme`: the family its last word must end in.
static func line_problems(line: Variant, where: String, rhyme: Variant = null) -> Array:
	if typeof(line) != TYPE_DICTIONARY or line.size() != 2 or not line.has("text") or not line.has("syl"):
		return ["%s is not {\"text\", \"syl\"}" % where]
	var text: Variant = line["text"]
	var syl: Variant = line["syl"]
	if typeof(text) != TYPE_STRING or letters(text) == "":
		return ["%s has no text" % where]
	if not _ascii(text):
		return ["%s is not plain ASCII" % where]
	if typeof(syl) != TYPE_ARRAY or syl.is_empty():
		return ["%s has no syllables" % where]
	var bad: Array = []
	var last := -1
	for i in syl.size():
		var s: Variant = syl[i]
		if typeof(s) != TYPE_ARRAY or s.size() != 3 or not _whole(s[0]) or typeof(s[1]) != TYPE_STRING or not _whole(s[2]):
			return ["%s syllable %d is not [step, syllable, stress]" % [where, i]]
		var step := int(s[0])
		var stress := int(s[2])
		if step < 0 or step > 15:
			bad.append("%s syllable %d (%s) is on step %d, not 0-15" % [where, i, s[1], step])
		if step <= last:
			bad.append("%s syllable %d (%s) on step %d does not come after step %d" % [where, i, s[1], step, last])
		last = step
		if stress < 0 or stress > 2:
			bad.append("%s syllable %d (%s) has stress %d, not 0, 1 or 2" % [where, i, s[1], stress])
		if letters(s[1]) == "":
			bad.append("%s syllable %d is empty" % [where, i])
	if not bad.is_empty():
		return bad
	var sung := ""
	for s: Array in syl:
		sung += letters(s[1])
	if sung != letters(text):
		return ["%s: the syllables give \"%s\", the text \"%s\"" % [where, sung, letters(text)]]
	# Which word each syllable is in: none may run across two.
	var words := words_of(text)
	var owner: Array = []
	var w := 0
	var used := 0
	for s: Array in syl:
		var part := letters(s[1])
		while w < words.size() and used == String(words[w]).length():
			w += 1
			used = 0
		if w >= words.size() or not String(words[w]).substr(used).begins_with(part):
			return ["%s: the syllable \"%s\" runs across two words" % [where, s[1]]]
		owner.append(w)
		used += part.length()
	var strong: Array = []
	for i in syl.size():
		if int(syl[i][2]) == 2:
			strong.append(i)
	if strong.is_empty():
		return ["%s has no strong syllable" % where]
	var near := 0
	for i: int in strong:
		if beat_gap(int(syl[i][0])) <= 1:
			near += 1
	if near * 2 <= strong.size():
		bad.append("%s: only %d of its %d strong syllables are on or by a beat" % [where, near, strong.size()])
	var end: int = strong[-1]
	if beat_gap(int(syl[end][0])) > 1:
		bad.append("%s: its last strong syllable (%s, step %d) is not on or by a beat" % [where, syl[end][1], int(syl[end][0])])
	if owner[end] != words.size() - 1:
		bad.append("%s: its last strong syllable (%s) is not in its last word" % [where, syl[end][1]])
	if typeof(rhyme) == TYPE_STRING and not rhymes_with(words[-1], rhyme):
		bad.append("%s ends in \"%s\", not in the rhyme family %s" % [where, words[-1], rhyme])
	return bad


## Does the card's flow tag say what its steps do? on_beat: most strong syllables right on the beat; behind: most a
## sixteenth late; double: a run of 8 syllables on 8 sixteenths in a row; rests: a gap of a beat or more inside a line,
## or a line that starts or ends a beat clear.
static func flow_ok(flow: String, lines: Array) -> bool:
	var strong: Array = []
	for ln: Dictionary in lines:
		for s: Array in ln["syl"]:
			if int(s[2]) == 2:
				strong.append(int(s[0]))
	match flow:
		"on_beat", "behind":
			var want := 0 if flow == "on_beat" else 1
			var n := 0
			for step: int in strong:
				if step % 4 == want:
					n += 1
			return n * 2 > strong.size()
		"double":
			for ln: Dictionary in lines:
				var syl: Array = ln["syl"]
				var run := 1
				for i in range(1, syl.size()):
					run = run + 1 if int(syl[i][0]) == int(syl[i - 1][0]) + 1 else 1
					if run >= 8:
						return true
			return false
		"rests":
			for ln: Dictionary in lines:
				var syl: Array = ln["syl"]
				if int(syl[0][0]) >= 4 or int(syl[-1][0]) <= 11:
					return true
				for i in range(1, syl.size()):
					if int(syl[i][0]) - int(syl[i - 1][0]) >= 5:
						return true
			return false
	return false


## A hook is four bars, two cards: hook_<name>_a and _b, both tagged hook, the same rhyme, unlock and true. What is
## wrong with `cid` as one (or as not one), among `cards` (id to card); "" if nothing.
static func hook_problem(cid: String, cards: Dictionary) -> String:
	var c: Dictionary = cards[cid]
	var m := _re("_hook_re", "^hook_([a-z0-9]+)_([ab])$").search(cid)
	if ("hook" in c["tags"]) != (m != null):
		return "a hook is tagged hook and named hook_<name>_a or _b (both or neither)"
	if m == null:
		return ""
	var other := "hook_%s_%s" % [m.get_string(1), "b" if m.get_string(2) == "a" else "a"]
	if not cards.has(other):
		return "its other half %s is missing" % other
	for k: String in ["rhyme", "unlock", "true"]:
		var mine: Variant = c.get(k)
		var its: Variant = cards[other].get(k)
		if typeof(mine) != typeof(its) or mine != its:
			return "its halves differ in rhyme, unlock or true"
	return ""


static func rhymes_with(word: String, family: String) -> bool:
	load_rules()
	var fam: Variant = _families.get(family)
	if typeof(fam) != TYPE_DICTIONARY:
		return false
	if word in fam.get("not", []):
		return false
	if word in fam.get("words", []):
		return true
	for e: Variant in fam.get("endings", []):
		if word.ends_with(str(e)):
			return true
	return false


static func _slot_problems(c: Dictionary, slot: Variant) -> Array:
	if typeof(slot) != TYPE_DICTIONARY or slot.size() != 2 or not slot.has("line") or not slot.has("from"):
		return ["slot: not {\"line\", \"from\"}"]
	if not _whole(slot["line"]) or not int(slot["line"]) in [0, 1]:
		return ["slot: line %s is not 0 or 1" % _show(slot["line"])]
	if typeof(slot["from"]) != TYPE_STRING or not _lists.has(slot["from"]):
		return ["slot: no list %s in words.json" % _show(slot["from"])]
	var line: Variant = c["lines"][int(slot["line"])]
	if not line_problems(line, "x").is_empty():
		return []
	var entries: Array = _lists[slot["from"]]["entries"]
	var found := _default_of(line, entries)
	if typeof(found[0]) == TYPE_NIL:
		return ["slot: line %d does not end in an entry of %s" % [int(slot["line"]), slot["from"]]]
	var bad: Array = []
	for e: Dictionary in entries:
		var got := fill(line, int(found[1]), e)
		if got.is_empty():
			bad.append("slot: %s (%s) does not fit line %d" % [e["id"], e["text"], int(slot["line"])])
			continue
		for p: String in line_problems(got, "with %s" % e["id"]):
			bad.append("slot: " + p)
	return bad


static func _entry_problem(e: Variant) -> String:
	if typeof(e) != TYPE_DICTIONARY or typeof(e.get("id")) != TYPE_STRING or typeof(e.get("text")) != TYPE_STRING or typeof(e.get("syl")) != TYPE_ARRAY:
		return "not {\"id\", \"text\", \"syl\", ...}"
	if e.has("deed") == e.has("weapon"):
		return "needs a deed or a weapon (one)"
	if e.has("deed") and not Deeds.known(str(e["deed"])):
		return "no deed %s" % _show(e["deed"])
	var sung := ""
	var strong := false
	for s: Variant in e["syl"]:
		if typeof(s) != TYPE_ARRAY or s.size() != 2 or typeof(s[0]) != TYPE_STRING or not _whole(s[1]) or int(s[1]) < 0 or int(s[1]) > 2:
			return "syl is not [[syllable, stress] ...]"
		sung += letters(s[0])
		strong = strong or int(s[1]) == 2
	if sung != letters(e["text"]) or e["syl"].is_empty():
		return "the syllables are not the text"
	return "" if strong else "no strong syllable"


# ------------------------------------------------------------ slots

## The syllable a word is pinned by: its last strong one, else its last most stressed one. `stresses`: one a syllable.
static func _anchor(stresses: Array) -> int:
	var top: int = stresses.max()
	for i in range(stresses.size() - 1, -1, -1):
		if int(stresses[i]) == top:
			return i
	return 0


## The entry of a list a line ends in (its default) and how many syllables it takes: [entry, n], or [null, 0].
static func _default_of(line: Dictionary, entries: Array) -> Array:
	var syl: Array = line["syl"]
	var best: Array = [null, 0]
	for e: Dictionary in entries:
		var esyl: Array = e["syl"]
		var n := esyl.size()
		if n > syl.size() or n <= int(best[1]):
			continue
		var same := true
		for k in n:
			if letters(syl[syl.size() - n + k][1]) != letters(esyl[k][0]):
				same = false
				break
		if same:
			best = [e, n]
	return best


## The line with its last n syllables (its default) swapped for `entry` (a list's entry): {"text", "syl"}, or {} if
## it does not fit. tools/validate_bars.py's fill(), step for step.
static func fill(line: Dictionary, n: int, entry: Dictionary) -> Dictionary:
	var syl: Array = line["syl"]
	var head := syl.slice(0, syl.size() - n)
	var old := syl.slice(syl.size() - n)
	var old_stress: Array = []
	for s: Array in old:
		old_stress.append(int(s[2]))
	var at := int(old[_anchor(old_stress)][0])
	var prev := int(head[-1][0]) if not head.is_empty() else -1
	var sy: Array = entry["syl"]
	var sy_stress: Array = []
	for s: Array in sy:
		sy_stress.append(int(s[1]))
	var j := _anchor(sy_stress)
	var before := j
	var after := sy.size() - 1 - j
	var h := 2 if at + 2 * after <= 15 else 1
	if at + h * after > 15:
		return {}
	var g := 2 if at - 2 * before > prev else 1
	if at - g * before <= prev:
		return {}
	var out: Array = []
	for s: Array in head:
		out.append([int(s[0]), String(s[1]), int(s[2])])
	for i in sy.size():
		var step := at - g * (before - i) if i < j else (at if i == j else at + h * (i - j))
		out.append([step, String(sy[i][0]), int(sy[i][1])])
	var text := String(line["text"])
	var cut := text.length()
	while cut > 0 and not _alnum(text.unicode_at(cut - 1)):
		cut -= 1
	var body := text.substr(0, cut)
	var old_sung := ""
	for s: Array in old:
		old_sung += String(s[1])
	return {"text": body.substr(0, _cut_at(body, letters(old_sung).length())) + String(entry["text"]) + text.substr(cut), "syl": out}


## A digest of every slot fill (cards by id, each entry of its list in order): tools/validate_bars.py --digest
## prints the same when the two fill slots the same way.
static func digest() -> String:
	load_all()
	var keys := _cards.keys()
	keys.sort()
	var parts := ""
	for cid: String in keys:
		var c: Dictionary = _cards[cid]
		if not c.has("slot"):
			continue
		var slot: Dictionary = c["slot"]
		var line: Dictionary = c["lines"][int(slot["line"])]
		var entries: Array = _lists[slot["from"]]["entries"]
		var n := int(_default_of(line, entries)[1])
		for e: Dictionary in entries:
			var got := fill(line, n, e) if n > 0 else {}
			var steps := PackedStringArray()
			for s: Array in got.get("syl", []):
				steps.append(str(int(s[0])))
			parts += "%s/%s:%s;" % [cid, e["id"], ",".join(steps) if not got.is_empty() else "none"]
	return parts.md5_text()


# ------------------------------------------------------------ what he may rap

## Every card's id, pack by pack.
static func ids() -> Array:
	load_all()
	return _order.duplicate()


## A card by id ({} if there is none, or it was refused). Not a copy: do not change it.
static func card(cid: String) -> Dictionary:
	load_all()
	return _cards.get(cid, {})


static func pack_of(cid: String) -> String:
	load_all()
	return String(_pack_of.get(cid, ""))


## Each card refused (and each words.json entry), by name: "pack id: what is wrong".
static func refused() -> Array:
	load_all()
	return _refused.duplicate()


## The starter cards: no deed needed.
static func starter() -> Array:
	return ids().filter(func(cid: String) -> bool: return not _cards[cid].has("unlock"))


## What a card is to him: "starter" (no deed needed), "earned" (its deed done often enough), "cap" (not earned: he
## may use it, but it claims what he has not lived), or "" (no such card).
static func standing(state: RefCounted, cid: String) -> String:
	var c := card(cid)
	if c.is_empty():
		return ""
	if not c.has("unlock"):
		return "starter"
	return "earned" if int(state.done(c["unlock"]["deed"])) >= int(c["unlock"]["count"]) else "cap"


## The cards he has earned by his deeds.
static func earned(state: RefCounted) -> Array:
	return ids().filter(func(cid: String) -> bool: return standing(state, cid) == "earned")


## The cards he has not earned: he may still use them, as cap.
static func cap(state: RefCounted) -> Array:
	return ids().filter(func(cid: String) -> bool: return standing(state, cid) == "cap")


## The other half of a hook ("" if `cid` is not half of one).
static func partner(cid: String) -> String:
	var m := _re("_hook_re", "^hook_([a-z0-9]+)_([ab])$").search(cid)
	if m == null:
		return ""
	var other := "hook_%s_%s" % [m.get_string(1), "b" if m.get_string(2) == "a" else "a"]
	return other if card(other).size() > 0 else ""


## The cards that may come after `cid`: the same rhyme family, another card. After half of a hook, its other half
## (a hook is the two together); after a verse card, the other verse cards of its rhyme (hooks are kept for hooks).
static func follows(cid: String) -> Array:
	var c := card(cid)
	if c.is_empty():
		return []
	if "hook" in c["tags"]:
		var other := partner(cid)
		return [other] if other != "" else []
	return ids().filter(func(o: String) -> bool:
		return o != cid and _cards[o]["rhyme"] == c["rhyme"] and not "hook" in _cards[o]["tags"])


## The words he may put in a card's slot: the card's own (its default, first), then each entry of its list he has
## (has_word). Each {"id", "text", "default", "lines"}: the card's two lines with that word in. [] if it has no slot.
static func slot_words(state: RefCounted, cid: String) -> Array:
	var c := card(cid)
	if c.is_empty() or not c.has("slot"):
		return []
	var at := int(c["slot"]["line"])
	var line: Dictionary = c["lines"][at]
	var entries: Array = _lists[c["slot"]["from"]]["entries"]
	var found := _default_of(line, entries)
	var out: Array = []
	for e: Dictionary in entries:
		var own: bool = typeof(found[0]) == TYPE_DICTIONARY and String(found[0]["id"]) == String(e["id"])
		if not own and not has_word(state, e):
			continue
		var lines: Array = (c["lines"] as Array).duplicate(true)
		if not own:
			lines[at] = fill(line, int(found[1]), e)
		var row := {"id": e["id"], "text": e["text"], "default": own, "lines": lines}
		if own:
			out.push_front(row)
		else:
			out.append(row)
	return out


## Has he got this entry of a list: its deed done (been there, met them), or its weapon on him or in the stash.
static func has_word(state: RefCounted, entry: Dictionary) -> bool:
	if entry.has("deed"):
		return int(state.done(entry["deed"])) > 0
	var weapon := String(entry.get("weapon", ""))
	return weapon in state.owned or weapon in (state.flags.get("stash", []) as Array)


## A list of words by name: {"about", "entries"} ({} if there is none).
static func word_list(name: String) -> Dictionary:
	load_rules()
	return _lists.get(name, {})


# ------------------------------------------------------------ small things

## What is sung of a piece of text: its letters and digits, lower case.
static func letters(s: String) -> String:
	var out := ""
	for c in s.to_lower():
		if _alnum(c.unicode_at(0)):
			out += c
	return out


## The text's words, each as its letters (E.R. is one word, er; a hyphen parts two words).
static func words_of(text: String) -> Array:
	var out: Array = []
	for m: RegExMatch in _re("_word_re", "[A-Za-z0-9'][A-Za-z0-9'.]*").search_all(text):
		var w := letters(m.get_string())
		if w != "":
			out.append(w)
	return out


## How far a step is from the nearest beat (0, 4, 8, 12, 16): 0, 1 or 2 sixteenths.
static func beat_gap(step: int) -> int:
	var r := posmod(step, 4)
	return mini(r, 4 - r)


static func _alnum(u: int) -> bool:
	return (u >= 48 and u <= 57) or (u >= 65 and u <= 90) or (u >= 97 and u <= 122)


static func _ascii(s: String) -> bool:
	for i in s.length():
		if s.unicode_at(i) > 127:
			return false
	return true


## Where the last n letters (and digits) of `body` begin.
static func _cut_at(body: String, n: int) -> int:
	var count := 0
	for i in range(body.length() - 1, -1, -1):
		if _alnum(body.unicode_at(i)):
			count += 1
			if count == n:
				return i
	return 0


static func _whole(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or (typeof(v) == TYPE_FLOAT and is_finite(v) and v == floorf(v))


static func _show(v: Variant) -> String:
	return "'%s'" % v if typeof(v) == TYPE_STRING else str(v)


## JSON's numbers are floats: a card that passed gets whole ones (steps, stresses, its count, its slot's line).
static func _whole_numbers(c: Dictionary) -> void:
	for line: Dictionary in c["lines"]:
		var syl: Array = []
		for s: Array in line["syl"]:
			syl.append([int(s[0]), String(s[1]), int(s[2])])
		line["syl"] = syl
	if typeof(c.get("unlock")) == TYPE_NIL:
		c.erase("unlock")
	else:
		c["unlock"]["count"] = int(c["unlock"]["count"])
	if typeof(c.get("slot")) == TYPE_NIL:
		c.erase("slot")
	else:
		c["slot"]["line"] = int(c["slot"]["line"])


static func _json(path: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) == OK and typeof(json.data) == TYPE_DICTIONARY:
		return json.data
	push_warning("Could not read %s" % path)
	return {}


## A regular expression made once (`slot`: the static var that keeps it).
static func _re(slot: String, pattern: String) -> RegEx:
	match slot:
		"_word_re":
			if _word_re == null:
				_word_re = RegEx.create_from_string(pattern)
			return _word_re
		"_hook_re":
			if _hook_re == null:
				_hook_re = RegEx.create_from_string(pattern)
			return _hook_re
	if _id_re == null:
		_id_re = RegEx.create_from_string(pattern)
	return _id_re
