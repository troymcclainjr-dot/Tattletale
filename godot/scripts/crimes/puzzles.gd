class_name Puzzles
## The broken payphone (puzzles.js), state side: picking the puzzle, opening and closing it,
## and what happens when it's solved. The HUD runs the puzzle itself (Hud.puzzle_show) and
## calls back G.puzzle_solved(), G.penalty(sec) and G.hang_up().

const PZ_KINDS := ["wires", "keypad", "menu"]
static var pz_last := -1


static func open_puzzle(ph, ev: Array) -> void:
	var S := G.S
	G.P.x = ph.x
	G.P.z = ph.z + 0.72
	G.P.yaw = PI
	S.bino_on = false
	G.K.erase("binoculars")
	Hud.bino(false)
	var by_time := ev.duplicate()
	by_time.sort_custom(func(a, b): return a.left < b.left)
	var focus = by_time[0]
	var k := pz_last
	while k == pz_last:
		k = int(randf() * 3)
	pz_last = k
	var plate_case = null
	for c in ev:
		if c.puzzle == "plate":
			plate_case = c
			break
	S.mode = "puzzle"
	S.pz = {"focus": plate_case if plate_case else focus, "kind": "plate" if plate_case else PZ_KINDS[k], "done": false}
	Hud.puzzle_show(S.pz.kind, S.pz.focus)
	Audio.sfx("pickup")


static func close_puzzle() -> void:
	G.S.mode = "play"
	G.S.pz = null
	Hud.puzzle_hide()
	Player.update_camera(0.0, true)


static func solved() -> void:
	var S := G.S
	if S.pz == null or S.pz.done:
		return
	S.pz.done = true
	Audio.sfx("win")
	Hud.say("OPERATOR", "Nine-one-one, what's your emer-", 1.4)
	G.later(1.45, func(): _connected())
	G.later(2.7, func(): _hang_up_after())


static func _connected() -> void:
	Hud.say("TWOPACK", "It's me.", 1.2)
	Crimes.dispatch(Crimes.pending_evidence().map(func(c): return c.id))


static func _hang_up_after() -> void:
	if G.S.mode == "puzzle":
		close_puzzle()
