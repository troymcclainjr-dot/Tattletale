class_name Minigames
## Hands-on minigames (minigames.js): the whistle on the beat, the ruler, recording the
## snoring, the 911 call. The HUD draws the panel; this file runs them (S.lock).


# ---- the whistle (on the beat)
static func start_rhythm(c: Crime) -> void:
	var B := 60.0 / 90.0
	c.frozen = true
	G.S.lock = {"kind": "rhythm", "c": c, "t0": G.clock + 1.2, "n": 6, "hits": 0, "judged": [], "next": 0, "B": B}
	G.P.yaw = PI
	Hud.lock_open("rhythm", "CITIZEN'S CITATION", "Blow the whistle on the beat", "Press E as the line crosses each dot. Hit 4 of 6. Esc to back off.")
	Hud.say("TWOPACK", "Hold it right there, ma'am!", 1.4)


static func inch(v: float) -> String:
	var e := roundi(v * 16.0)
	if e == 0:
		return "0 in"
	if e == 16:
		return "1 in"
	var a := e
	var b := 16
	while a % 2 == 0:
		a /= 2
		b /= 2
	return "%d/%d in" % [a, b]


# ---- the ruler
static func start_ruler(c: Crime) -> void:
	G.S.lock = {"kind": "ruler", "c": c, "t": U.rand(0, 1.8), "v": 0.0}
	Hud.lock_open("ruler", "LAWN INSPECTION", "Measure the grass", "Press E when it reads exactly 1/4 inch. Esc to stop.")


static func end_lock() -> void:
	G.S.lock = null
	Hud.lock_close()


static func dad_snoring() -> bool:
	return fmod(G.clock, 3.2) < 1.6


# ---- the snore recording
static func start_record(c: Crime) -> void:
	G.S.lock = {"kind": "record", "c": c, "was": dad_snoring()}
	G.P.yaw = atan2(World.HAMMOCK[0] - G.P.x, World.HAMMOCK[1] - G.P.z)
	Hud.lock_open("record", "FLIP PHONE · VOICE MEMO", "Record the snoring", "Hold still. It records every snore. Esc to stop.")
	Audio.sfx("click")


# ---- the 911 call on the cops
static func call911(ph) -> void:
	G.P.x = ph.x
	G.P.z = ph.z + 0.72
	G.P.yaw = PI
	G.S.lock = {"kind": "scene"}
	Audio.sfx("pickup")
	var keys := ["9", "1", "1"]
	for i in 3:
		G.later(0.5 + 0.15 * i, func(): Audio.sfx("dtmf", keys[i]))
	G.later(1.0, func(): G.talk([["OPERATOR", "Nine-one-one, what's your emer-", 1.4], ["TWOPACK", "It's me.", 1.0]], func(): _hung_up()))


static func _hung_up() -> void:
	Audio.sfx("hangup")
	G.later(0.3, func(): Audio.sfx("busy"))
	G.talk([["TWOPACK", "Hello? ...HELLO?! Y'all hung up on a SNITCH?!", 2.4], ["TWOPACK", "I'm reportin' this... to the POLICE!", 2.2]], func(): _call_done())


static func _call_done() -> void:
	end_lock()
	Crimes.adv(G.C.cops)


static func cancel_lock() -> void:
	var L = G.S.lock
	if L == null or L.kind == "scene":
		return
	if L.kind == "rhythm":
		L.c.frozen = false
	end_lock()


static func _head(L: Dictionary) -> float:
	var B: float = L.B
	return clampf((G.clock - (L.t0 - B)) / ((L.n + 1) * B), 0.0, 1.0)


static func update_lock(dt: float) -> void:
	var L = G.S.lock
	if L == null:
		return
	if L.kind == "rhythm":
		var B: float = L.B
		while L.next < L.n and G.clock >= L.t0 + L.next * B:
			Audio.sfx("tick")
			L.next += 1
		Hud.lock_update("rhythm", {"head": _head(L), "hit": -1})
		if G.clock > L.t0 + (L.n - 1) * B + 0.4:
			var c: Crime = L.c
			var ok: bool = L.hits >= 4
			end_lock()
			if ok:
				c.handling = true
				Audio.sfx("win")
				G.talk([["TWOPACK", "Ma'am. That's a citation.", 1.8], ["GRANDMA", "Sonny, I'm ninety-one.", 1.8]], func(): Crimes.busted(c, "CITED!"))
			else:
				c.frozen = false
				Hud.toast("Off the beat (%d/6). You need 4. Try again." % L.hits)
				Audio.sfx("buzz")
	elif L.kind == "record":
		var sn := dad_snoring()
		var c = L.c
		var vu := (55.0 + 40.0 * absf(sin(G.clock * 9.0)) if sn else 6.0 + 4.0 * sin(G.clock * 5.0)) / 100.0
		Hud.lock_update("record", {"vu": vu, "count": "%d/3" % c.snores})
		if sn and not L.was:
			c.snores += 1
			Hud.pop(Vector3(World.HAMMOCK[0], 1.2, World.HAMMOCK[1]), "SNORE %d/3" % c.snores)
			Hud.lock_update("record", {"vu": vu, "count": "%d/3" % c.snores})
			if c.snores >= 3:
				end_lock()
				Audio.sfx("shutter")
				Crimes.adv(c)
		L.was = sn
	elif L.kind == "ruler":
		L.t += dt
		L.v = 0.5 - 0.5 * cos(L.t * TAU / 1.8)
		Hud.lock_update("ruler", {"needle": L.v, "reading": inch(L.v)})


## E while a minigame is up.
static func lock_press() -> void:
	var L = G.S.lock
	if L == null:
		return
	if L.kind == "rhythm":
		var i := roundi((G.clock - L.t0) / L.B)
		var bt: float = L.t0 + i * L.B
		if i >= 0 and i < L.n and not L.judged.has(i) and absf(G.clock - bt) < 0.17:
			L.judged.append(i)
			L.hits += 1
			Audio.sfx("whistle")
			Hud.lock_update("rhythm", {"head": _head(L), "hit": i})
		else:
			Audio.sfx("click")
	elif L.kind == "ruler":
		var c: Crime = L.c
		if absf(L.v - 0.25) < 0.04:
			end_lock()
			Audio.sfx("shutter")
			Hud.say(c.line[0], c.line[1], 2.6)
			Hud.pop(c.target(), "1/4 INCH")
			Crimes.adv(c)
		else:
			c.left -= 3
			Audio.sfx("buzz")
			Hud.lock_msg("That reads %s. Again. (-3s)" % inch(L.v))
