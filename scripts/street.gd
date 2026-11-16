extends RefCounted
## His standing on the street, and what people remember of him. All static: the numbers live in the player state's
## `street` Dictionary (player_state.gd), so they are in the save.
##
##   respect   what the block thinks he can and will do (hands, holding a corner, paying what he owes)
##   heat      how hard the police are looking at him
##   trust     how far the block's ordinary people would stand by him
##
## Something that matters is told with note(main, "fair_one_won"): assets/data/standing.json says what each
## event changes, flat and for each person who saw it (people at the place, alive and up, near enough and with
## nothing solid between them and him: witnesses()). Officers who saw it count apart.
##
## People remember (person(state, who)): a Dictionary for each character, by the folder his drawing comes from
## ("tre"), so the same man remembers wherever he is met. melee.gd and dealing.gd write what they need there.
##
## Every number is a placeholder (standing.json).

const DATA := "res://assets/data/standing.json"
const KINDS := ["respect", "heat", "trust"]

static var _data := {}
static var last := {}             # the last note(): {"what", "saw", "police", "changes"} (for the HUD and the steps)


static func data() -> Dictionary:
	if _data.is_empty():
		var read: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		_data = read if typeof(read) == TYPE_DICTIONARY else {"start": {}, "events": {}}
	return _data


## The street part of the player state, with everything it should have.
static func book(state: RefCounted) -> Dictionary:
	var s: Dictionary = state.street
	var start: Dictionary = data().get("start", {})
	for kind: String in KINDS:
		if not s.has(kind):
			s[kind] = int(start.get(kind, 0))
	if typeof(s.get("people")) != TYPE_DICTIONARY:
		s["people"] = {}
	return s


static func value(state: RefCounted, kind: String) -> int:
	return int(book(state).get(kind, 0))


## Change one of the three by `by`, kept within 0 .. 100. What it is now.
static func add(state: RefCounted, kind: String, by: int) -> int:
	var s := book(state)
	s[kind] = clampi(int(s.get(kind, 0)) + by, 0, 100)
	state.touch()
	return int(s[kind])


## What `who` (a drawing's folder: "tre") remembers of him.
static func person(state: RefCounted, who: String) -> Dictionary:
	var people: Dictionary = book(state)["people"]
	if typeof(people.get(who)) != TYPE_DICTIONARY:
		people[who] = {}
	return people[who]


## The name a person is remembered by.
static func who_of(actor: Node3D) -> String:
	var who := String(actor._who) if "_who" in actor else ""
	return who if who != "" else String(actor.display_name).to_lower()


## Who can see what happens at `at`: {"people": n, "police": n, "names": [...]}. `but` are left out (the two
## who are fighting).
static func witnesses(main: Node, at: Vector3, but: Array = []) -> Dictionary:
	var out := {"people": 0, "police": 0, "names": []}
	if main._combat == null:
		return out
	var see := float(data().get("see", 14.0))
	var w: RefCounted = main._combat.world_for(main._building)
	for p: RefCounted in main._combat.people.living_here():
		var a: Node3D = p.actor
		if a in but or a.fallen > 0.5 or a.global_position.distance_to(at) > see:
			continue
		var eye := a.global_position + Vector3(0.0, a.height * 0.8, 0.0)
		if w != null and bool(w.trace(eye, at + Vector3(0.0, 1.0, 0.0))["hit"]):
			continue
		if who_of(a) == "cop":
			out["police"] += 1
		else:
			out["people"] += 1
		out["names"].append(String(a.display_name))
	return out


## Something happened that the street counts: apply standing.json's rule for `what`, with whoever saw it at `at`
## (his own spot if not given). Returns {"what", "saw", "police", "changes": {kind: by}}.
static func note(main: Node, what: String, at: Variant = null, but: Array = []) -> Dictionary:
	var rule: Dictionary = data().get("events", {}).get(what, {})
	var where: Vector3 = at if at is Vector3 else main._actor.global_position
	var saw := witnesses(main, where, but)
	var n := mini(int(saw["people"]), int(data().get("most", 6)))
	var changes := {}
	for kind: String in KINDS:
		var by := 0
		var pair: Array = rule.get(kind, [0, 0])
		if pair.size() >= 2:
			by = int(pair[0]) + int(pair[1]) * n
		by += int(rule.get("police", {}).get(kind, 0)) * int(saw["police"])
		if by != 0:
			changes[kind] = by
			add(main._state, kind, by)
	last = {"what": what, "saw": int(saw["people"]), "police": int(saw["police"]), "names": saw["names"], "changes": changes}
	print(("[shot] street: " if main._scripted else "[street] ") + "%s: seen by %d and %d police%s; %s; now respect %d, heat %d, trust %d" % [what, saw["people"], saw["police"],
		"" if (saw["names"] as Array).is_empty() else " (%s)" % ", ".join(saw["names"]),
		"nothing changed" if changes.is_empty() else ", ".join(changes.keys().map(func(k: String) -> String: return "%s %+d" % [k, changes[k]])),
		value(main._state, "respect"), value(main._state, "heat"), value(main._state, "trust")])
	return last
