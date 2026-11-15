extends RefCounted
## Being held at the county jail (place `prison`, plans/prison.gd): what
## main.gd's _arrest does, what he may not do while he is held, and how he gets
## out. Static helpers that take main.gd itself, so main.gd keeps only short hooks.
##
##   arrest    He is disarmed (his weapons are not given back), taken to booking
##             at the jail and stood on the yellow box at the height chart, in
##             the orange jumpsuit; he is marked held in the save (_state.flags
##             "held", "held_for", "held_day") and what he was wearing is kept with it.
##   held      He walks the inside but cannot leave: the gate out of the lobby
##             opens for nobody, the travel list (M) stays shut, and a trip to
##             anywhere else is refused (put down, he comes to in the jail's own
##             TREATMENT room rather than the hospital: combat.gd asks for it by name).
##   release   A PLACEHOLDER rule: E on his own bunk (CELL 104) sleeps the night out,
##             and in the morning he is let out in his own clothes, on the pavement
##             at the front gate. (--do=release lets him out at once.)
##   continue  A game saved while he is held comes back held, in the jumpsuit, in his cell.

const PRISON := "prison"
const ORANGE := Color(0.91, 0.44, 0.14)        # for a lead whose clothes are not layers (no jumpsuit drawn)
const SUIT := {"hat": {"item": ""}, "jacket": {"item": ""}, "shirt": {"item": "jumpsuit"}, "trousers": {"item": "jumpsuit_legs"}}


static func held(main: Node) -> bool:
	return bool(main._state.flags.get("held", false))


## main.gd's _arrest(why): `why` is shown across the top.
static func lock_up(main: Node, why: String) -> void:
	print("[arrest] ", why)
	main._aim_off()
	main._actor.aiming = false
	main._actor.weapon = ""
	main._state.disarm()
	var flags: Dictionary = main._state.flags
	flags["arrests"] = int(flags.get("arrests", 0)) + 1
	if not held(main):          # (arrested again inside, he keeps what he came in wearing)
		flags["kept_look"] = (main._look as Dictionary).duplicate(true)
		flags["kept_picks"] = (main._picks as Dictionary).duplicate(true)
	flags["held"] = true
	flags["held_for"] = why
	flags["held_day"] = main._day
	main._state.touch()
	main._travel_to(PRISON, true)
	main._teleport(main._building.get_meta("prison_mark"), true)
	dress(main)
	main._actor.face_way("front")
	main._actor.show_face()
	_caption(main, "ARRESTED: " + why.to_upper())
	main._save_game()
	print("[arrest] held at booking: %.2f, %.2f" % [main._actor.position.x, main._actor.position.z])


## Into the jumpsuit: its two items over everything (no hat, no jacket), or for
## a lead whose clothes are not layers, orange for each piece he has.
static func dress(main: Node) -> void:
	var actor: Node3D = main._actor
	if actor.has_wardrobe():
		var items: Dictionary = actor.wardrobe().get("items", {})
		if items.has("jumpsuit") and items.has("jumpsuit_legs"):
			main._look = SUIT.duplicate(true)
			main._dress_lead()
			return
	var wear := {}
	for piece: String in ["shirt", "trousers", "jacket", "sleeve"]:
		if piece in actor.clothes():
			wear[piece] = ORANGE
	main._wear = wear
	actor.set_outfit(wear)


## May he go to place `id`? Anywhere but the jail, not while he is held.
static func may_go(main: Node, id: String) -> bool:
	if id == PRISON or not held(main):
		return true
	print("[prison] held: no trip to %s" % id)
	return false


## May the travel list open? Not while he is held.
static func can_travel(main: Node) -> bool:
	if not held(main):
		return true
	_caption(main, "HELD: NO TRAVEL")
	print("[prison] held: the travel list stays shut")
	return false


## E at a use point "prison:...". "prison:bunk" is his own bunk: the night, and out.
static func use(main: Node, id: String) -> void:
	if id != "prison:bunk":
		return
	if not held(main):
		_caption(main, "NOT YOUR BUNK")
		return
	main._cut_to(func() -> void:
		main._day += 1
		main._dress_for_day()
		print("[use] day %d" % main._day)
		release(main))


## Let him out: his own clothes back, the held marks gone, on the pavement at the front gate.
static func release(main: Node) -> void:
	if not held(main):
		print("[prison] release: he is not held")
		return
	var flags: Dictionary = main._state.flags
	var look: Variant = flags.get("kept_look", {})
	var picks: Variant = flags.get("kept_picks", {})
	main._look = (look as Dictionary).duplicate(true) if look is Dictionary else {}
	var back := {}
	if picks is Dictionary:
		for piece: String in picks:
			back[piece] = int(picks[piece])
	main._picks = back
	for key: String in ["held", "held_for", "held_day", "kept_look", "kept_picks"]:
		flags.erase(key)
	main._state.touch()
	main._wear = {}
	main._dress_lead()
	main._travel_to(PRISON, true)
	main._actor.face_way("front")
	main._actor.show_face()
	_caption(main, "RELEASED")
	main._save_game()
	print("[prison] released at %.2f, %.2f, day %d" % [main._actor.position.x, main._actor.position.z, main._day])


## CONTINUE of a game saved while he was held: back in his cell, in the jumpsuit.
static func resume(main: Node) -> void:
	if not held(main):
		return
	if main._place != PRISON:
		main._open_place(PRISON)
	main._teleport(main._building.get_meta("prison_cell"), true)
	dress(main)
	print("[prison] continued held: %s, %.2f, %.2f" % [main._place, main._actor.position.x, main._actor.position.z])


static func _caption(main: Node, text: String) -> void:
	if main._combat and main._combat.hud:
		main._combat.hud.caption(text)
