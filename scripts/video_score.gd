extends RefCounted
## How a music video does: worked out from what was bought for it and how the
## take went, with the numbers in assets/data/video.json ("payout"):
##
##   production  what the plan adds up to, 0..100 (everything at its dearest is 100)
##   swagger     how well he performed: the moves, on the beat and in shot
##   polish      100, less what the mishaps and being out of shot took off
##   chaos       what went wrong and was left in (funny), 0..100
##   LOOKS       production, never more than his swagger, times polish
##   buzz        looks, swagger and chaos weighted ("buzz"); views come from it
##               ("views": buzz to views, in between the points it grows evenly
##               by a factor), give or take "luck"; pay is views times
##               "per_1000_views"; the stars are how many of "stars" it passed
##
## Comments are picked by tags (see `tags`): one whose "when" tags all fit can
## be shown, the ones with more tags first.

const SHOWN := 5          # comments on a premiere


## The choice picked in each row: row id to the choice's Dictionary.
static func chosen(rows: Array, picks: Dictionary) -> Dictionary:
	var out := {}
	for row: Dictionary in rows:
		var choices: Array = row["choices"]
		out[row["id"]] = choices[clampi(int(picks.get(row["id"], 0)), 0, choices.size() - 1)]
	return out


## What the plan costs, in dollars.
static func price(rows: Array, picks: Dictionary) -> int:
	var total := 0
	for choice: Dictionary in chosen(rows, picks).values():
		total += int(choice.get("price", 0))
	return total


static func production(rows: Array, picks: Dictionary) -> int:
	var most := 0.0
	for row: Dictionary in rows:
		var best := 0.0
		for choice: Dictionary in row["choices"]:
			best = maxf(best, float(choice.get("adds", 0)))
		most += best
	var got := 0.0
	for choice: Dictionary in chosen(rows, picks).values():
		got += float(choice.get("adds", 0))
	return roundi(100.0 * got / maxf(most, 1.0))


## The whole result. `take` is what the take kept: "swagger", "polish",
## "chaos" and "mishaps" (each {"id", "handled"}). `luck_seed` makes the luck
## the same each time for the same video.
##
## HARD (take "style" is "hard"): what was bought counts for less; production
## starts from "hard"'s "production_floor" of the way up (a cheap street video
## can still look right), so the take (timing, holds, variety, staying in the
## lens: video_take.gd's swagger and polish) decides more of it.
static func result(data: Dictionary, picks: Dictionary, take: Dictionary, spent: int, luck_seed: int) -> Dictionary:
	var pay: Dictionary = data["payout"]
	var prod := production(data["rows"], picks)
	if String(take.get("style", "clean")) == "hard":
		prod = roundi(prod + float(data.get("hard", {}).get("production_floor", 0.0)) * (100 - prod))
	var swagger := clampi(roundi(float(take.get("swagger", 0))), 0, 100)
	var polish := clampf(float(take.get("polish", 100)), 0.0, 100.0)
	var chaos := clampi(roundi(float(take.get("chaos", 0))), 0, 100)
	# ---- SONG SCORE HOOK (for the notebook worker) ---------------------------
	# A song's own score goes in here: one compact step on `prod`, `swagger` or
	# `chaos`, after the take's numbers and before LOOKS and buzz below. Nothing
	# here yet (the hard video's only change is the production floor above).
	# --------------------------------------------------------------------------
	var looks := roundi(minf(float(prod), float(swagger)) * polish / 100.0)
	var weight: Dictionary = pay["buzz"]
	var buzz := clampf(looks * float(weight["looks"]) + swagger * float(weight["swagger"]) + chaos * float(weight["chaos"]), 0.0, 100.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = luck_seed
	var luck := 1.0 + rng.randf_range(-1.0, 1.0) * float(pay["luck"])
	var views := roundi(curve(pay["views"], buzz) * luck)
	var paid := roundi(views / 1000.0 * float(pay["per_1000_views"]))
	var stars := 1
	for bar: float in pay["stars"]:
		if buzz >= bar:
			stars += 1
	var out := {"production": prod, "swagger": swagger, "polish": roundi(polish), "chaos": chaos, "looks": looks,
		"buzz": roundi(buzz), "views": views, "paid": paid, "stars": stars, "spent": spent}
	out["tags"] = tags(data, picks, out, take.get("mishaps", []))
	out["comments"] = comments(data["comments"], out["tags"], luck_seed)
	return out


## Views for a buzz: between two points of the table they grow by the same factor each step.
static func curve(points: Array, buzz: float) -> float:
	if points.is_empty():
		return 0.0
	var last: Array = points[0]
	if buzz <= float(last[0]):
		return float(last[1])
	for point: Array in points:
		if buzz <= float(point[0]):
			var t := (buzz - float(last[0])) / maxf(float(point[0]) - float(last[0]), 0.001)
			return float(last[1]) * pow(float(point[1]) / maxf(float(last[1]), 1.0), t)
		last = point
	return float(last[1])


## What can be said about this video:
##   looks:low, looks:high (and the same for chaos and swagger: under "levels"' low, at or over its high)
##   broke (spent no more than "broke"), rich (spent "rich" or more)
##   at:<location>, entourage:<choice>, bling:<choice>, cars:<choice>, rain, smoke
##   <mishap>:handled, <mishap>:missed
static func tags(data: Dictionary, picks: Dictionary, numbers: Dictionary, mishaps: Array) -> Array:
	var pay: Dictionary = data["payout"]
	var levels: Dictionary = pay["levels"]
	var out: Array = []
	for key: String in ["looks", "chaos", "swagger"]:
		var value := float(numbers[key])
		if value < float(levels["low"]):
			out.append(key + ":low")
		elif value >= float(levels["high"]):
			out.append(key + ":high")
	if int(numbers["spent"]) <= int(pay.get("broke", 0)):
		out.append("broke")
	if int(numbers["spent"]) >= int(pay.get("rich", 999999)):
		out.append("rich")
	var got := chosen(data["rows"], picks)
	out.append("at:" + String(got["location"]["id"]))
	for row: String in ["entourage", "bling", "cars"]:
		out.append("%s:%s" % [row, got[row]["id"]])
	if String(got["rain"]["id"]) != "none":
		out.append("rain")
	if String(got["smoke"]["id"]) != "none":
		out.append("smoke")
	for m: Dictionary in mishaps:
		out.append("%s:%s" % [m["id"], "handled" if m["handled"] else "missed"])
	return out


## Up to SHOWN comments that fit, the most particular first (ties in a seeded
## shuffle); never the same commenter twice running.
static func comments(all: Array, have: Array, luck_seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = luck_seed + 7
	var fits: Array = []
	for c: Dictionary in all:
		var ok := true
		for tag: String in c.get("when", []):
			if not tag in have:
				ok = false
		if ok:
			fits.append({"c": c, "key": c.get("when", []).size() * 1000 + rng.randi_range(0, 999)})
	fits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["key"] > b["key"])
	var out: Array = []
	var last := ""
	for pass_n in 2:          # a second pass takes what was skipped for being the same commenter twice
		for f: Dictionary in fits:
			if out.size() >= SHOWN:
				break
			var c: Dictionary = f["c"]
			if out.has(c) or (pass_n == 0 and String(c["who"]) == last):
				continue
			out.append(c)
			last = String(c["who"])
	return out
