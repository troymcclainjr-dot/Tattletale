extends RefCounted
## --do steps for the song system's words half, for a screenshot run (tools/shot.py): the deeds ledger
## (player_state.gd's deeds; deeds.gd; assets/data/deeds.json) and the bar cards (bars.gd; assets/data/bars/).
## main.gd's _take_shot hands bars:... here.
##
##   bars:ledger                  every deed he has done and how often, and the ledger's digest
##   bars:deed:<name>[:n]         count a deed n times (1), as its hook does; prints the cards that opened
##   bars:unlocked                the cards he may use: starter, earned (each with its deed), and how many are cap
##   bars:follows:<card>          the cards that may come after that one, each with his standing with it
##   bars:slot:<card>             the words he may put in that card's slot, each line as it then is, on its steps
##   bars:card:<card>             a card on the sixteen steps: its words, rhyme, tags, unlock, his standing with it
##   bars:check                   the packs read afresh (each refused card by name); made-up broken cards and packs,
##                                each of which must be refused by name; the fill digest (validate_bars.py --digest)
##   bars:portal:<label>          E at the stairs, ladder or trapdoor here with that label, as a player does it
##                                (UP THE FIRE ESCAPE at Fry's, DOWN TO THE CELLAR at the store: deeds roof, cellar)
##   bars:mark                    remember the ledger as it is now
##   bars:since                   what has been counted since bars:mark, and the cards that opened
##   bars:expect:<name=n+name=n>  since bars:mark exactly those were counted, and nothing else: ok, or what differs
##   bars:save                    save the game (a run saves only with --save=<file>, never the player's) and say
##                                whether the file holds this ledger
##   bars:same                    is the ledger the one in the save file (after continue)?
##
## Every line printed starts "[shot] bars:".

const Bars := preload("res://scripts/bars.gd")
const Deeds := preload("res://scripts/deeds.gd")

static var _mark := {}               # the ledger at bars:mark, name to count
static var _mark_earned: Array = []  # the cards he had earned then


static func step(main: Node, bits: PackedStringArray) -> void:
	var state: RefCounted = main._state
	var arg := bits[2] if bits.size() > 2 else ""
	match bits[1] if bits.size() > 1 else "":
		"ledger":
			_say("ledger: %s" % _ledger_line(state.deeds))
		"deed":
			var n := int(bits[3]) if bits.size() > 3 else 1
			if not Deeds.known(arg):
				_say("deed: there is no deed %s in deeds.json" % arg)
			elif n < 1:
				_say("deed: %d is not a count" % n)
			else:
				var before := Bars.earned(state)
				state.deed(arg, n)
				_say("deed: %s +%d, now %d; opened: %s" % [arg, n, int(state.done(arg)), _named(_new(Bars.earned(state), before))])
		"unlocked":
			var earned := Bars.earned(state)
			_say("unlocked: %d cards: %d starter, %d earned, %d cap (usable, not earned)" % [Bars.ids().size(), Bars.starter().size(), earned.size(), Bars.cap(state).size()])
			_say("unlocked: starter: %s" % " ".join(PackedStringArray(Bars.starter())))
			_say("unlocked: earned: %s" % _named(earned))
		"follows":
			var c := Bars.card(arg)
			if c.is_empty():
				_say("follows: there is no card %s (or it was refused)" % arg)
			else:
				var next := Bars.follows(arg).map(func(o: String) -> String: return "%s %s" % [o, Bars.standing(state, o)])
				_say("follows %s (%s, a %s card): %d: %s" % [arg, c["rhyme"], "hook" if "hook" in c["tags"] else "verse", next.size(), ", ".join(PackedStringArray(next))])
		"slot":
			var c := Bars.card(arg)
			if c.is_empty() or not c.has("slot"):
				_say("slot: %s is not a card with a slot" % arg)
			else:
				var at := int(c["slot"]["line"])
				var words := Bars.slot_words(state, arg)
				var all := (Bars.word_list(c["slot"]["from"]).get("entries", []) as Array).size()
				_say("slot %s: line %d, from %s: %d of its %d words are his" % [arg, at, c["slot"]["from"], words.size(), all])
				for w: Dictionary in words:
					var line: Dictionary = w["lines"][at]
					_say("slot %s: %-10s %s" % [arg, String(w["id"]) + (" (own)" if w["default"] else ""), line["text"]])
					_say("slot %s: %-10s %s" % [arg, "", _grid(line)])
		"card":
			var c := Bars.card(arg)
			if c.is_empty():
				_say("card: there is no card %s (or it was refused)" % arg)
			else:
				var unlock := "unlocked by %s" % _unlock_of(arg) if c.has("unlock") else "starter"
				_say("card %s (%s): rhyme %s; tags %s; %s; %s; to him: %s" % [arg, Bars.pack_of(arg), c["rhyme"], ", ".join(PackedStringArray(c["tags"])), unlock, "true" if c["true"] else "not a claim", Bars.standing(state, arg)])
				for line: Dictionary in c["lines"]:
					_say("card %s:   %s" % [arg, line["text"]])
					_say("card %s:   %s" % [arg, _grid(line)])
		"check":
			_check()
		"portal":
			await _portal(main, arg)
		"mark":
			_mark = _counts(state.deeds)
			_mark_earned = Bars.earned(state)
			_say("mark: %s" % _ledger_line(state.deeds))
		"since":
			var diff := _since(state)
			_say("since the mark: %s" % (_diff_line(diff) if not diff.is_empty() else "nothing counted"))
			_say("since the mark, opened: %s" % _named(_new(Bars.earned(state), _mark_earned)))
		"expect":
			var want := {}
			for pair: String in arg.split("+", false):
				var kv := pair.split("=")
				want[kv[0]] = int(kv[1]) if kv.size() > 1 else 1
			var diff := _since(state)
			var wrong := PackedStringArray()
			for name: String in want:
				if int(diff.get(name, 0)) != int(want[name]):
					wrong.append("%s +%d (expected +%d)" % [name, int(diff.get(name, 0)), int(want[name])])
			for name: String in diff:
				if not want.has(name):
					wrong.append("%s +%d (not expected)" % [name, int(diff[name])])
			_say("expect: %s" % (("ok: exactly " + _diff_line(diff)) if wrong.is_empty() else "WRONG: " + "; ".join(wrong)))
		"save":
			if _no_save_of_its_own(main):
				_say("save: not saved: a run saves only to a file of its own (--save=<file>), never the player's")
			else:
				main._save_game()
				var kept := _counts(_saved_deeds(main))
				_say("save: %s: the file holds %d deeds, the ledger's own: %s (digest %s)" % [main._save_path, kept.size(), "yes" if _digest(kept) == _digest(_counts(state.deeds)) else "NO", _digest(kept)])
		"same":
			if _no_save_of_its_own(main):
				_say("same: this run has no save of its own (--save=<file>)")
			else:
				var now := _counts(state.deeds)
				var kept := _counts(_saved_deeds(main))
				_say("same: the ledger %s the save's (%s): %d deeds, digest %s" % ["is" if _digest(now) == _digest(kept) else "is NOT", main._save_path, now.size(), _digest(now)])
		var what:
			_say("there is no step bars:%s (ledger, deed, unlocked, follows, slot, card, check, mark, since, expect, save, same)" % what)
	await main.get_tree().process_frame       # a frame for whatever the step changed to show


## E at the stairs, ladder or trapdoor here with that label, as a player does it (deeds.gd's landed: a roof,
## a cellar): he is stood at its foot, E finds it as the nearest thing, and the move plays out.
static func _portal(main: Node, label: String) -> void:
	var found: Node3D = null
	for p: Node3D in (main._building.portals if "portals" in main._building else []):
		if String(p.label).to_lower() == label.to_lower():
			found = p
	if found == null:
		_say("portal: no %s here (%s)" % [label, main._place])
		return
	var spot: Vector3 = found.use_spot()
	main._actor.position = Vector3(spot.x, main._actor.position.y, spot.z)
	main._actor.areas = main._building.walk_areas()
	main._change_room(main._building.room_at_pos(main._actor.position, main._room), true)
	main._find_nearest()
	var near: String = main._nearest.use_name() if main._nearest else "nothing in reach"
	main._use_nearest()
	for i in 40:                              # the blackout and the move (main.gd's _teleport)
		await main.get_tree().process_frame
	_say("portal: E at %s: now in the %s at %.2f, %.2f" % [near, main._building.rooms[main._room]["name"], main._actor.position.x, main._actor.position.z])


## The packs read afresh, and made-up broken cards and packs: each must be refused, by name.
static func _check() -> void:
	Bars.load_all(true)
	var packs := {}
	for cid: String in Bars.ids():
		packs[Bars.pack_of(cid)] = int(packs.get(Bars.pack_of(cid), 0)) + 1
	var each := PackedStringArray()
	for p: String in packs:
		each.append("%s %d" % [p.trim_suffix(".json"), packs[p]])
	_say("check: %d cards read from %d packs (%s); %d refused" % [Bars.ids().size(), packs.size(), ", ".join(each), Bars.refused().size()])
	for r: String in Bars.refused():
		_say("check: refused %s" % r)
	_say("check: fill digest %s" % Bars.digest())
	var good := _made_up_card()
	var kept := Bars.problems(good).is_empty()
	_say("check: made up: the good card is %s" % ("kept" if kept else "REFUSED: " + "; ".join(PackedStringArray(Bars.problems(good)))))
	var all_refused := true
	var cases := _made_up_cases(good)
	for name: String in cases:
		var bad := Bars.problems(cases[name])
		all_refused = all_refused and not bad.is_empty()
		_say("check: made up: %-42s %s" % [name, "refused: " + String(bad[0]) if not bad.is_empty() else "KEPT (wrong)"])
	var text := JSON.stringify({"about": "made up", "cards": [good, good]})
	var files := {
		"a file that is not JSON": [Bars.parse_pack("made_up.json", "{\"about\": \"half a file", {}), 0],
		"a file that is not a pack": [Bars.parse_pack("made_up.json", "[1, 2]", {}), 0],
		"an id twice in one pack": [Bars.parse_pack("made_up.json", text, {}), 1],
		"an id another pack has": [Bars.parse_pack("made_up.json", JSON.stringify({"about": "made up", "cards": [good]}), {"test_good": "starter.json"}), 0],
	}
	for name: String in files:
		var got: Dictionary = files[name][0]
		var ok: bool = (got["cards"] as Array).size() == int(files[name][1]) and (got["refused"] as Array).size() == 1
		all_refused = all_refused and ok
		_say("check: made up: %-42s %s" % [name, ("kept %d, refused: %s" % [(got["cards"] as Array).size(), got["refused"][0]]) if ok else "WRONG: %s" % [got]])
	var hook := good.duplicate(true)
	hook["id"] = "hook_test_a"
	var unnamed := hook.duplicate(true)
	hook["tags"] = ["hook", "block", "on_beat"]
	for row: Array in [["half a hook", hook], ["a hook's name, not tagged hook", unnamed]]:
		var why := Bars.hook_problem("hook_test_a", {"hook_test_a": row[1]})
		all_refused = all_refused and why != ""
		_say("check: made up: %-42s %s" % [row[0], "refused: " + why if why != "" else "KEPT (wrong)"])
	_say("check: made up: %d broken cards and packs, every one refused by name: %s; the good card kept: %s" % [cases.size() + files.size() + 2, "yes" if all_refused else "NO", "yes" if kept else "NO"])


## tools/validate_bars.py --selftest's good card, word for word.
static func _made_up_card() -> Dictionary:
	return {"id": "test_good", "rhyme": "ock", "tags": ["block", "on_beat"], "true": false, "lines": [
		{"text": "Rose Hill Terrace, I was raised on the block", "syl": [[0, "Rose", 2], [2, "Hill", 1], [4, "Ter", 2], [5, "race", 0], [6, "I", 0], [7, "was", 0], [8, "raised", 2], [10, "on", 0], [11, "the", 0], [12, "block", 2]]},
		{"text": "Where the corners tell the time we never had a clock", "syl": [[0, "Where", 0], [1, "the", 0], [2, "cor", 1], [3, "ners", 0], [4, "tell", 2], [5, "the", 0], [6, "time", 2], [7, "we", 0], [8, "nev", 2], [9, "er", 0], [10, "had", 0], [11, "a", 0], [12, "clock", 2]]}]}


## tools/validate_bars.py --selftest's broken cards (and one that is not a card at all).
static func _made_up_cases(good: Dictionary) -> Dictionary:
	var line0: Array = good["lines"][0]["syl"]
	var line1: Array = good["lines"][1]["syl"]
	var rising := line0.duplicate(true)
	rising[5] = [6, "was", 0]
	var stress := line0.duplicate(true)
	stress[0] = [0, "Rose", 3]
	var past := line0.duplicate(true)
	past[9] = [16, "block", 2]
	var watch := line1.slice(0, line1.size() - 1)
	watch.append([12, "watch", 2])
	return {
		"one line": _changed(good, {"lines": [good["lines"][0]]}),
		"a step past 15": _line_changed(good, 0, {"syl": past}),
		"steps not rising": _line_changed(good, 0, {"syl": rising}),
		"syllables not the text": _line_changed(good, 0, {"text": "Rose Hill Terrace, I was born on the block"}),
		"not plain ASCII": _line_changed(good, 0, {"text": "Rose Hill Terrace, I was raised on the blöck"}),
		"a stress of 3": _line_changed(good, 0, {"syl": stress}),
		"strong syllables off the beat": _line_changed(good, 0, {"syl": [[2, "Rose", 2], [3, "Hill", 1], [6, "Ter", 2], [7, "race", 0], [8, "I", 0], [9, "was", 0], [10, "raised", 2], [11, "on", 0], [12, "the", 0], [14, "block", 2]]}),
		"not in its rhyme": _line_changed(good, 1, {"text": "Where the corners tell the time we never had a watch", "syl": watch}),
		"an unknown rhyme family": _changed(good, {"rhyme": "orange"}),
		"an unknown deed": _changed(good, {"unlock": {"deed": "flew_to_the_moon", "count": 1}}),
		"a count of 0": _changed(good, {"unlock": {"deed": "shot_fired", "count": 0}}),
		"true with no deed": _changed(good, {"true": true}),
		"two flows": _changed(good, {"tags": ["block", "on_beat", "double"]}),
		"a flow its steps are not": _changed(good, {"tags": ["block", "behind"]}),
		"a field not in the contract": _changed(good, {"mood": "sad"}),
		"a slot from no list": _changed(good, {"slot": {"line": 1, "from": "planets"}}),
		"a slot on line 2": _changed(good, {"slot": {"line": 2, "from": "places"}}),
		"a slot whose line ends in none of the list": _changed(good, {"slot": {"line": 1, "from": "places"}}),
		"no id": _changed(good, {"id": null}),
		"not a card at all": 7,
	}


static func _changed(card: Dictionary, change: Dictionary) -> Dictionary:
	var c := card.duplicate(true)
	for k: String in change:
		if typeof(change[k]) == TYPE_NIL:
			c.erase(k)
		else:
			c[k] = change[k]
	return c


static func _line_changed(card: Dictionary, i: int, change: Dictionary) -> Dictionary:
	var c := card.duplicate(true)
	(c["lines"][i] as Dictionary).merge(change, true)
	return c


# ------------------------------------------------------------ the ledger

## The ledger with every count a whole number (a save read back has floats).
static func _counts(deeds: Variant) -> Dictionary:
	var out := {}
	if typeof(deeds) == TYPE_DICTIONARY:
		for name: Variant in deeds:
			if int(deeds[name]) != 0:
				out[str(name)] = int(deeds[name])
	return out


static func _digest(counts: Dictionary) -> String:
	var names := counts.keys()
	names.sort()
	var text := ""
	for name: String in names:
		text += "%s=%d;" % [name, int(counts[name])]
	return text.md5_text().left(12)


static func _ledger_line(deeds: Variant) -> String:
	var counts := _counts(deeds)
	var names := counts.keys()
	names.sort()
	var each := PackedStringArray()
	var total := 0
	for name: String in names:
		each.append("%s %d" % [name, counts[name]])
		total += int(counts[name])
	return "%d deeds, %d counted (digest %s): %s" % [counts.size(), total, _digest(counts), ", ".join(each) if not each.is_empty() else "none"]


## What has been counted since bars:mark: name to how many more.
static func _since(state: RefCounted) -> Dictionary:
	var now := _counts(state.deeds)
	var out := {}
	for name: String in now:
		var more: int = int(now[name]) - int(_mark.get(name, 0))
		if more != 0:
			out[name] = more
	return out


static func _diff_line(diff: Dictionary) -> String:
	var names := diff.keys()
	names.sort()
	var each := PackedStringArray()
	for name: String in names:
		each.append("%s +%d" % [name, int(diff[name])])
	return ", ".join(each) if not each.is_empty() else "nothing"


static func _saved_deeds(main: Node) -> Variant:
	var data: Dictionary = main._read(main._save_path)
	var kept: Variant = data.get("state")
	return kept.get("deeds", {}) if typeof(kept) == TYPE_DICTIONARY else {}


## A run that was not given --save=<file> writes no save (main.gd's _save_game), and its save path is the player's.
static func _no_save_of_its_own(main: Node) -> bool:
	return String(main._save_path) == String(main.get_script().get_script_constant_map().get("SAVE", ""))


# ------------------------------------------------------------ printing

static func _say(text: String) -> void:
	print("[shot] bars: " + text)


## The cards in `now` that are not in `before`.
static func _new(now: Array, before: Array) -> Array:
	return now.filter(func(cid: String) -> bool: return not cid in before)


## Cards with what unlocked them: "shot_01 (shot_fired x1), ...", or "none".
static func _named(cards: Array) -> String:
	if cards.is_empty():
		return "none"
	return ", ".join(PackedStringArray(cards.map(func(cid: String) -> String: return "%s (%s)" % [cid, _unlock_of(cid)])))


static func _unlock_of(cid: String) -> String:
	var c := Bars.card(cid)
	return "%s x%d" % [c["unlock"]["deed"], int(c["unlock"]["count"])] if c.has("unlock") else "starter"


## A line on the sixteen steps, a column a step: UPPER strong, Capitalised medium, lower weak; | every beat.
static func _grid(line: Dictionary) -> String:
	var at := {}
	for s: Array in line["syl"]:
		at[int(s[0])] = s
	var cols := PackedStringArray()
	for step in 16:
		if step > 0 and step % 4 == 0:
			cols.append("|")
		if not at.has(step):
			cols.append(".")
			continue
		var s: Array = at[step]
		var w := ""
		for ch in String(s[1]):
			if Bars._alnum(ch.unicode_at(0)) or ch == "'":
				w += ch
		cols.append(w.to_upper() if int(s[2]) == 2 else (w.left(1).to_upper() + w.substr(1).to_lower() if int(s[2]) == 1 else w.to_lower()))
	return " ".join(cols)
