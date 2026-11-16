extends RefCounted
## What a written song does to its music video (all static). Two marked lines call in here (`# notebook:`):
## video_score.gd's result() hands the swagger to cap(), video_premiere.gd's open() hands the result to
## premiere(). The video is for the newest song without one: song_sheets[videos.size()], as video_shoot.gd's
## song_beat() finds its beat. A freestyle, a song from an older save, or no game at all (a test calling
## video_score.gd by itself) changes nothing, so the video's numbers without a written song are as before.
##
## songs.json "video": the song's total caps swagger at cap_from + cap_per_point x total; at the premiere up
## to `comments` of songs.json "song_comments" that fit the song are put first (true bars noticed, cap called
## out first, then the rest).

const Bars := preload("res://scripts/bars.gd")
const Deeds := preload("res://scripts/deeds.gd")
const Sheet := preload("res://scripts/song_sheet.gd")
const Score := preload("res://scripts/song_score.gd")
const SHOWN := 5          # video_score.gd's SHOWN: comments on a premiere


## The song the video being made is for: its written sheet with a score, or {}.
static func sheet_now() -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = tree.current_scene if tree else null
	if main == null or not "_state" in main or main._state == null:
		return {}
	var sheets: Array = main._state.song_sheets
	var n := (main._state.videos as Array).size()
	if n >= sheets.size() or typeof(sheets[n]) != TYPE_DICTIONARY:
		return {}
	var sheet: Dictionary = sheets[n]
	if not Sheet.is_written(sheet) or typeof(sheet.get("score")) != TYPE_DICTIONARY or int(sheet["score"].get("total", -1)) < 0:
		return {}
	return sheet


## The video's swagger, capped by its written song's total (as it was with no written song).
static func cap(swagger: int, sheet: Variant = null) -> int:
	var s: Dictionary = sheet if typeof(sheet) == TYPE_DICTIONARY else sheet_now()
	if s.is_empty():
		return swagger
	return mini(swagger, cap_of(int(s["score"]["total"])))


## The most swagger a song with that total allows.
static func cap_of(total: int) -> int:
	var v := Score.data("video")
	return roundi(float(v.get("cap_from", 30)) + float(v.get("cap_per_point", 0.8)) * total)


## The premiere's result with up to two comments about the song first (a copy; as it was with no written song).
static func premiere(result: Dictionary, sheet: Variant = null) -> Dictionary:
	var s: Dictionary = sheet if typeof(sheet) == TYPE_DICTIONARY else sheet_now()
	if s.is_empty():
		return result
	var mine := comments(s)
	if mine.is_empty():
		return result
	var out := result.duplicate()
	var all: Array = mine.duplicate()
	all.append_array(result.get("comments", []))
	out["comments"] = all.slice(0, SHOWN)
	out["song_comments"] = mine.size()
	return out


## What can be said about a recorded sheet: song:true, song:deed:<deed> and song:family:<family> for each true bar he
## lived; song:cap and song:cap_true (a cap card that claims a deed); song:hook:<name>; song:chain, song:fresh and
## song:flow :high or :low (songs.json score levels); song:total:high.
static func tags(sheet: Dictionary) -> Array:
	var out: Array = []
	var deeds := Deeds.names()
	for c: Dictionary in Sheet.cards(sheet):
		var e: Dictionary = c["card"]
		var stand := String(e.get("standing", ""))
		if bool(e.get("true", false)) and stand == "earned":
			_add(out, "song:true")
			_add(out, "song:deed:" + String(e.get("deed", "")))
			_add(out, "song:family:" + String(deeds.get(String(e.get("deed", "")), {}).get("family", "")))
		if stand == "cap":
			_add(out, "song:cap")
			if bool(e.get("true", false)):
				_add(out, "song:cap_true")
	var hook := Sheet.at(sheet, "hook", 0)
	if not hook.is_empty():
		_add(out, "song:hook:" + Sheet.hook_name(String(hook["id"])))
	var score: Dictionary = sheet.get("score", {})
	var levels: Dictionary = Score.data("score").get("levels", {})
	for pair: Array in [["coherence", "chain"], ["freshness", "fresh"], ["flow", "flow"]]:
		var v := int(score.get(pair[0], -1))
		if v < 0:
			continue
		if v < int(levels.get("low", 40)):
			_add(out, "song:%s:low" % pair[1])
		elif v >= int(levels.get("high", 70)):
			_add(out, "song:%s:high" % pair[1])
	if int(score.get("total", -1)) >= int(levels.get("high", 70)):
		_add(out, "song:total:high")
	return out


## The song's comments: the most particular one about true bars, then the most particular calling out cap, then
## the rest by how particular they are (songs.json order breaks ties); never the same commenter twice; at most
## songs.json video.comments. Each {"who", "text", "when", "song": true}.
static func comments(sheet: Dictionary) -> Array:
	var have := tags(sheet)
	var most := int(Score.data("video").get("comments", 2))
	var fits: Array = []
	var k := 0
	for c: Variant in Score.data().get("song_comments", []):
		k += 1
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var when: Array = c.get("when", [])
		if when.all(func(t: Variant) -> bool: return String(t) in have):
			fits.append({"c": c, "key": when.size() * 1000 - k, "truth": "song:true" in when, "cap": when.has("song:cap") or when.has("song:cap_true")})
	fits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["key"]) > int(b["key"]))
	var order: Array = []
	for want: String in ["truth", "cap"]:
		for f: Dictionary in fits:
			if bool(f[want]):
				order.append(f)
				break
	for f: Dictionary in fits:
		if not order.has(f):
			order.append(f)
	var out: Array = []
	var who := {}
	for f: Dictionary in order:
		if out.size() >= most:
			break
		var c: Dictionary = f["c"]
		if who.has(String(c["who"])):
			continue
		who[String(c["who"])] = true
		var one := c.duplicate()
		one["song"] = true
		out.append(one)
	return out


static func _add(out: Array, tag: String) -> void:
	if not tag.ends_with(":") and not tag in out:
		out.append(tag)
