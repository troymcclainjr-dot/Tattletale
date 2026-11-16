extends RefCounted
## A song's score: four parts out of 100 and a total (assets/data/songs.json "score" has the weights and
## every number). score(state, sheet, take) is the one function to call; read(state, sheet) is the same
## without the take (flow -1, total -1), what the notebook shows while he writes.
##
##   flow          his timing at the mic: 100 x points / strong syllables judged, less `flub` a press off the
##                 beat (as the video's swagger, video_take.gd)
##   coherence     `rhyme` x the share of verse cards that rhyme on from the card before (same rhyme family),
##                 `theme` x the share of verse cards sharing a theme with the hook or the card before,
##                 `variety` x variety_by_flows[how many flows the song uses], less `repeat` a card used twice
##   authenticity  the mean over the ten cards of each one's value by its standing now: starter, earned,
##                 earned_true (earned, and it claims a deed: he lived it), cap, cap_true (claims what he never did)
##   freshness     the mean over the ten cards of by_uses[how many of his earlier songs used it]
##   total         the parts weighted (weights add to 1)
##
## The result also says which line most helped and which most hurt: each line's parts against the song's
## mean for that part, weighted; the part it differs most in is the reason (songs.json words.why).
## The take (song_take.gd's record): {"points", "judged", "flubs", "lines": {"verse1:0:1": {"points", "judged",
## "flubs"}, ...}} (a line of the hook sung twice adds up both times).

const Bars := preload("res://scripts/bars.gd")
const Sheet := preload("res://scripts/song_sheet.gd")
const DATA := "res://assets/data/songs.json"
const PARTS := ["flow", "coherence", "authenticity", "freshness"]

static var _data := {}


## songs.json, read once (a section of it by name, {} if there is none).
static func data(section := "") -> Dictionary:
	if _data.is_empty():
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(DATA)) == OK and typeof(json.data) == TYPE_DICTIONARY:
			_data = json.data
		else:
			push_warning("Could not read %s" % DATA)
	if section == "":
		return _data
	var got: Variant = _data.get(section, {})
	return got if typeof(got) == TYPE_DICTIONARY else {}


## A word the player reads (songs.json "words"; the key itself if it is missing).
static func word(key: String) -> String:
	return String(data("words").get(key, key.to_upper()))


## The score of a freestyle (a song recorded with nothing written): fixed, low.
static func freestyle() -> Dictionary:
	var s := data("score")
	var out := {}
	for p: String in PARTS:
		out[p] = int(s.get("freestyle", {}).get(p, 0))
	out["total"] = _total(out, s.get("weights", {}))
	out["freestyle"] = true
	return out


## The score of a sheet as he would sing it now: no flow, no total (-1 each).
static func read(state: RefCounted, sheet: Dictionary) -> Dictionary:
	return score(state, sheet, {}, null)


## The score of a written sheet. `take`: how he sang it ({} for not sung yet). `earlier`: the songs before it
## (null: every song he has recorded, state.song_sheets).
static func score(state: RefCounted, sheet: Dictionary, take := {}, earlier: Variant = null) -> Dictionary:
	if bool(sheet.get("freestyle", false)):
		return freestyle()
	var s := data("score")
	var weights: Dictionary = s.get("weights", {})
	var before: Array = earlier if typeof(earlier) == TYPE_ARRAY else state.song_sheets
	var units: Array = []          # each line of each card: {"row", "i", "line", "id", "text", parts...}
	var standing := {"starter": 0, "earned": 0, "earned_true": 0, "cap": 0, "cap_true": 0}
	var used_before := 0
	var auth_sum := 0.0
	var fresh_sum := 0.0
	var n := 0
	var seen := {}
	var repeats := 0
	var flows := {}
	var hook_themes := {}
	for e: Variant in sheet.get("hook", []):
		if typeof(e) == TYPE_DICTIONARY and String(e.get("id", "")) != "":
			for t: String in themes(String(e["id"])):
				hook_themes[t] = true
	var rhymed := 0
	var joins := 0
	var themed := 0
	var verse_n := 0
	var coh_of := {}               # "row:i" to the card's own coherence (verse cards)
	var c_rhyme := float(s.get("coherence", {}).get("rhyme", 50))
	var c_theme := float(s.get("coherence", {}).get("theme", 30))
	for c: Dictionary in Sheet.cards(sheet):
		var e: Dictionary = c["card"]
		var cid := String(e["id"])
		var card := Bars.card(cid)
		if card.is_empty():
			continue
		n += 1
		var stand := Bars.standing(state, cid)
		var key := stand + ("_true" if bool(card["true"]) and stand != "starter" else "")
		standing[key] = int(standing.get(key, 0)) + 1
		var a := float(s.get("authenticity", {}).get(key, s.get("authenticity", {}).get(stand, 0)))
		auth_sum += a
		var uses := 0
		for old: Variant in before:
			if typeof(old) == TYPE_DICTIONARY and Sheet.is_written(old) and _has_card(old, cid):
				uses += 1
		used_before += 1 if uses > 0 else 0
		var by_uses: Array = s.get("freshness", {}).get("by_uses", [100])
		var f := float(by_uses[mini(uses, by_uses.size() - 1)])
		fresh_sum += f
		if seen.has(cid):
			repeats += 1
		seen[cid] = true
		for t: String in card["tags"]:
			if t in Bars.FLOWS:
				flows[t] = true
		var coh := -1.0
		var row := String(c["row"])
		var i := int(c["i"])
		if row != "hook":
			verse_n += 1
			var prev := Sheet.at(sheet, row, i - 1) if i > 0 else {}
			var next := Sheet.at(sheet, row, i + 1) if i < 3 else {}
			var on := false
			if not prev.is_empty():
				joins += 1
				if _rhymes(String(prev["id"]), cid):
					rhymed += 1
					on = true
			if not next.is_empty() and _rhymes(cid, String(next["id"])):
				on = true
			var mine := themes(cid)
			var shares := mine.any(func(t: String) -> bool: return hook_themes.has(t))
			if not prev.is_empty():
				var theirs := themes(String(prev["id"]))
				shares = shares or mine.any(func(t: String) -> bool: return t in theirs)
			themed += 1 if shares else 0
			coh = (c_rhyme * (1.0 if on else 0.0) + c_theme * (1.0 if shares else 0.0)) / maxf(c_rhyme + c_theme, 1.0) * 100.0
			if _first_of(sheet, cid) != "%s:%d" % [row, i]:
				coh -= float(s.get("coherence", {}).get("repeat", 15))
			coh_of["%s:%d" % [row, i]] = coh
		var lines: Array = e.get("lines", [])
		for l in lines.size():
			units.append({"row": row, "i": i, "line": l, "id": cid, "text": String(lines[l].get("text", "")),
				"authenticity": a, "freshness": f, "coherence": coh, "flow": _line_flow(take, "%s:%d:%d" % [row, i, l])})
	var out := {}
	if n == 0:
		for p: String in PARTS:
			out[p] = -1 if p == "flow" else 0
		out["total"] = -1
		return out
	var cs: Dictionary = s.get("coherence", {})
	var vf: Array = cs.get("variety_by_flows", [0, 0, 0.6, 1, 1])
	var rhyme_share := float(rhymed) / joins if joins > 0 else 0.0
	var theme_share := float(themed) / verse_n if verse_n > 0 else 0.0
	out["coherence"] = clampi(roundi(c_rhyme * rhyme_share + c_theme * theme_share + float(cs.get("variety", 20)) * float(vf[mini(flows.size(), vf.size() - 1)])
		- float(cs.get("repeat", 15)) * repeats), 0, 100)
	out["authenticity"] = clampi(roundi(auth_sum / n), 0, 100)
	out["freshness"] = clampi(roundi(fresh_sum / n), 0, 100)
	out["flow"] = flow_of(take)
	out["total"] = _total(out, weights) if int(out["flow"]) >= 0 else -1
	out["rhymed"] = rhymed
	out["joins"] = joins
	out["themed"] = themed
	out["verse_cards"] = verse_n
	out["flows"] = flows.size()
	out["repeats"] = repeats
	out["standing"] = standing
	out["used_before"] = used_before
	out["cards"] = n
	var picked := _helped_hurt(units, weights)
	out["helped"] = picked[0]
	out["hurt"] = picked[1]
	return out


## Flow from a take: 100 x points / judged, less flub x flubs, 0 to 100 (-1 with no take).
static func flow_of(take: Dictionary) -> int:
	if take.is_empty() or not take.has("judged"):
		return -1
	var flub := float(data("take").get("flub", 2.0))
	var judged := int(take.get("judged", 0))
	if judged <= 0:
		return 0
	return clampi(roundi(100.0 * float(take.get("points", 0.0)) / judged - flub * int(take.get("flubs", 0))), 0, 100)


## A card's themes: its tags that are not a flow and not "hook".
static func themes(cid: String) -> Array:
	var c := Bars.card(cid)
	if c.is_empty():
		return []
	return (c["tags"] as Array).filter(func(t: String) -> bool: return t != "hook" and not t in Bars.FLOWS)


## The score's parts as one line of text.
static func line(score: Dictionary) -> String:
	if score.is_empty():
		return "no score"
	return "flow %d, coherence %d, authenticity %d, freshness %d, total %d" % [int(score.get("flow", -1)), int(score.get("coherence", 0)),
		int(score.get("authenticity", 0)), int(score.get("freshness", 0)), int(score.get("total", -1))]


static func _total(parts: Dictionary, weights: Dictionary) -> int:
	var t := 0.0
	var w_all := 0.0
	for p: String in PARTS:
		var w := float(weights.get(p, 0.25))
		t += w * float(parts.get(p, 0))
		w_all += w
	return clampi(roundi(t / maxf(w_all, 0.0001)), 0, 100)


static func _rhymes(a: String, b: String) -> bool:
	var ca := Bars.card(a)
	var cb := Bars.card(b)
	return not ca.is_empty() and not cb.is_empty() and String(ca["rhyme"]) == String(cb["rhyme"])


static func _has_card(sheet: Dictionary, cid: String) -> bool:
	for c: Dictionary in Sheet.cards(sheet):
		if String(c["card"].get("id", "")) == cid:
			return true
	return false


## Where a card is first in the sheet ("verse1:2"), in the order verse 1, hook, verse 2.
static func _first_of(sheet: Dictionary, cid: String) -> String:
	for c: Dictionary in Sheet.cards(sheet):
		if String(c["card"].get("id", "")) == cid:
			return "%s:%d" % [String(c["row"]), int(c["i"])]
	return ""


## One line's flow from the take (-1 if it was not judged).
static func _line_flow(take: Dictionary, key: String) -> float:
	var lines: Dictionary = take.get("lines", {})
	if not lines.has(key):
		return -1.0
	var l: Dictionary = lines[key]
	var judged := int(l.get("judged", 0))
	if judged <= 0:
		return -1.0
	var flub := float(data("take").get("flub", 2.0))
	return clampf(100.0 * float(l.get("points", 0.0)) / judged - flub * int(l.get("flubs", 0)), 0.0, 100.0)


## The line that most helped and the one that most hurt: [{"row", "i", "line", "id", "text", "why", "by"}, {...}]
## ({} where no line stands out by half a point). `by`: how many points of the total it moved, about.
static func _helped_hurt(units: Array, weights: Dictionary) -> Array:
	if units.is_empty():
		return [{}, {}]
	var mean := {}
	for p: String in PARTS:
		var sum := 0.0
		var k := 0
		for u: Dictionary in units:
			if float(u[p]) >= 0.0:
				sum += float(u[p])
				k += 1
		mean[p] = sum / k if k > 0 else -1.0
	var best := {}
	var worst := {}
	var best_m := 0.5
	var worst_m := -0.5
	for u: Dictionary in units:
		var m := 0.0
		var up := ""
		var down := ""
		var up_d := 0.0
		var down_d := 0.0
		for p: String in PARTS:
			if float(u[p]) < 0.0 or float(mean[p]) < 0.0:
				continue
			var d := float(weights.get(p, 0.25)) * (float(u[p]) - float(mean[p]))
			m += d
			if d > up_d:
				up_d = d
				up = p
			if d < down_d:
				down_d = d
				down = p
		if m > best_m and up != "":
			best_m = m
			best = {"row": u["row"], "i": u["i"], "line": u["line"], "id": u["id"], "text": u["text"], "why": up + "+", "by": snappedf(m / units.size(), 0.1)}
		if m < worst_m and down != "":
			worst_m = m
			worst = {"row": u["row"], "i": u["i"], "line": u["line"], "id": u["id"], "text": u["text"], "why": down + "-", "by": snappedf(m / units.size(), 0.1)}
	return [best, worst]
