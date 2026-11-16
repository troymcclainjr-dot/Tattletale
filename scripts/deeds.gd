extends RefCounted
## The deeds ledger's rules (the song system: a bar card is unlocked by a deed, scripts/bars.gd).
## player_state.gd keeps the counts (_state.deeds, deed(name), done(name), in the save). Where a
## thing happens, a one-line hook ending "# bars: a deed" counts it: _state.deed("name") itself, or
## one of these where a deed needs more than the one fact at hand (what happened on this visit,
## which room he came up into, how a video went). assets/data/deeds.json lists every name.
##
## A visit is from his arrival at a place to his next arrival somewhere else. Nothing here is
## saved: a game continued starts a fresh visit (the counts themselves are in the save).

const LIST := "res://assets/data/deeds.json"
const FLOP_STARS := 2              # a video at this many stars or fewer flopped
const BIG_STARS := 4               # ...at this many or more it went big
const CELLARS := ["CELLAR", "VAULT"]          # the rooms under the corner store (plans/store_cellar.gd)

static var _names := {}            # deeds.json's names (read once)
static var _visit := 0             # arrivals since the program started
static var _place := ""            # where this visit is
static var _ledger: Variant = null  # the ledger (state.deeds) the visit began with: a new game or a continued one has another
static var _fired_at := 0          # shot_fired when he arrived
static var _drawn_on := false      # someone drew on him on this visit
static var _room_kind := ""        # "roof", "cellar" or "" for the room he last landed in
static var _once := {}             # deeds counted at most once a visit: name to the visit it was counted on


## Every deed name there is (deeds.json), name to its row.
static func names() -> Dictionary:
	if _names.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(LIST))
		if typeof(data) == TYPE_DICTIONARY and typeof(data.get("deeds")) == TYPE_DICTIONARY:
			_names = data["deeds"]
		else:
			push_warning("Could not read %s" % LIST)
	return _names


static func known(name: String) -> bool:
	return names().has(name)


## main.gd's _open_place: he is at main._place now. Leaving the last place may be a deed (walked
## away from a gun, out of the crib clean); the first arrival anywhere is one (visited_<place>).
static func arrived(main: Node) -> void:
	var state: RefCounted = main._state
	var here := String(main._place)
	if here != _place or not is_same(_ledger, state.deeds):
		var free: bool = is_same(_ledger, state.deeds) and not bool(state.flags.get("held", false)) and int(state.health) > 0      # the same game; not arrested, not put down
		if free and _drawn_on and state.done("shot_fired") == _fired_at:
			state.deed("walked_away")
		if free and _place == "crib" and (state.owned as Array).is_empty() and not (state.flags.get("stash", []) as Array).is_empty():
			state.deed("guns_left_home")
		_visit += 1
		_place = here
		_ledger = state.deeds
		_fired_at = state.done("shot_fired")
		_drawn_on = false
	_room_kind = _kind(main)
	if state.done("visited_" + here) == 0 and known("visited_" + here):
		state.deed("visited_" + here)


## combat_foes.gd's _engage: someone here has drawn on him.
static func drawn_on() -> void:
	_drawn_on = true


## Count `name` at most once on this visit (combat_foes.gd: green at the courthouse detector).
static func once(main: Node, name: String) -> void:
	if int(_once.get(name, -1)) == _visit:
		return
	_once[name] = _visit
	main._state.deed(name)


## main.gd's _teleport (stairs, ladders): up onto a roof, or down into the cellar, from somewhere that was not one.
static func landed(main: Node) -> void:
	var kind := _kind(main)
	if kind != "" and kind != _room_kind:
		main._state.deed(kind)
	_room_kind = kind


## combat.gd's _trace: his round hit someone: `result` is combat_people.gd's hit() ("hit", "down", "dead");
## `whole` says they were unhurt before it.
static func shot(main: Node, result: String, whole: bool) -> void:
	if result == "dead":
		return
	if whole:
		main._state.deed("person_shot")
	if result == "down":
		main._state.deed("person_killed")


## main.gd's _start_talk: a conversation with `npc` (its rig's folder names it: "fry", "tre", "cop").
static func talked(main: Node, npc: Node3D) -> void:
	main._state.deed("talked")
	var rig: Variant = npc.get("_who") if npc != null else null
	var who := "met_" + str(rig) if rig != null else ""
	if who != "" and main._state.done(who) == 0 and known(who):
		main._state.deed(who)


## player_state.gd's add_video: a music video premiered (video_shoot.gd's record: "stars", "mishaps").
static func video(state: RefCounted, record: Dictionary) -> void:
	state.deed("video_shot")
	var stars := int(record.get("stars", 0))
	if stars <= FLOP_STARS:
		state.deed("video_flopped")
	elif stars >= BIG_STARS:
		state.deed("video_went_big")
	for m: Variant in record.get("mishaps", []):
		if typeof(m) == TYPE_DICTIONARY:
			state.deed("mishap_handled" if bool(m.get("handled", false)) else "mishap_missed")


## What sort of room he is in: "roof" (its name ends ROOF), "cellar" (CELLARS) or "".
static func _kind(main: Node) -> String:
	var b: Node3D = main._building
	var i := int(main._room)
	if b == null or not "rooms" in b or i < 0 or i >= (b.rooms as Array).size():
		return ""
	var room := String(b.rooms[i].get("name", ""))
	if room.ends_with("ROOF"):
		return "roof"
	return "cellar" if room in CELLARS else ""
