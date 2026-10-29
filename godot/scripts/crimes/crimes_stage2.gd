class_name Stage2Crimes
## Stage 2 crimes (crimes-stage2.js), verse 3: everybody he's ever told on. Mama, Daddy,
## the squirrel, the baby, and the finale (the cops).


class Mama extends Crime:
	func _init() -> void:
		id = "mama"
		title = "Running a red light"
		who = "2-Pack's mama"
		time = 90
		pts = 240
		line = ["TWOPACK", "I told on my mama for runnin' a light,"]
		describe = "My mama. Pink car. Rolled right through it."
		steps = [{"k": "spy", "t": "Catch her running the red light at the crosswalk. Binoculars, while it's red.", "m": "!"},
				{"k": "call", "t": func(): return "Call it in from a payphone. Remember her plate?" + ((" It starts %s..." % plate.substr(0, hint)) if hint else ""), "m": "CALL IT IN"}]
		puzzle = "plate"
		bust = [["STEVE", "Ma'am, you ran that light.", 1.8], ["MOM", "Baby, you told on your own MAMA?!", 2.2]]

	func target() -> Vector3:
		return Vector3(G.W.mama_car.x, 1.1, G.W.mama_car.z)

	func start() -> void:
		var mc = G.W.mama_car
		plate = str(1000 + int(randf() * 9000))
		hint = 0
		World.set_plate(plate)
		mc.x = -56.0
		mc.g.visible = true
		mc.stopped = false

	func update(dt: float) -> void:
		var mc = G.W.mama_car
		if dispatched:
			if not mc.stopped and (mc.x < -27 or mc.x > 40):
				mc.x = -26.0
			mc.stopped = true
			World.set_light("green")
			Stage2Crimes.place2(mc)
			return
		var sp := 2.3 if (mc.x > -6 and mc.x < 8) else 6.5
		var blocked := false
		for b in G.bodies:
			if not b.on.call():
				continue
			var p: Vector3 = b.pos.call()
			var ahead: float = p.x - mc.x
			if ahead > 0 and ahead < 3.0 + b.r and absf(p.z - mc.z) < 1.0 + b.r:
				blocked = true
		if blocked:
			mc.honk -= dt
			if mc.honk <= 0:
				Audio.sfx("honk")
				mc.honk = 2.2
		else:
			mc.x += sp * dt
			mc.spin += sp * dt / 0.36
			mc.honk = 0.0
		if mc.x > 72:
			mc.x = -58.0
		World.set_light("yellow" if (mc.x > -17 and mc.x < -6) else ("red" if (mc.x >= -6 and mc.x < 9) else "green"))
		Stage2Crimes.place2(mc)

	func spy_ok() -> bool:
		return G.W_.tl_state == "red" and G.W.mama_car.x > -5 and G.W.mama_car.x < 8

	func on_spy() -> bool:
		Hud.pop(target(), "PLATE " + plate)
		var dashed := ""
		for i in plate.length():
			dashed += ("-" if i else "") + plate[i]
		Hud.say("TWOPACK", "Plate %s! Got it!" % dashed, 2.2)
		return true

	func end(_why: String) -> void:
		G.W.mama_car.g.visible = false

	func slots(t: Vector3) -> Array:
		return [[t.x - 1.2, World.LANE2 - 1.55], [t.x + 1.2, World.LANE2 - 1.55]]


static func place2(mc) -> void:
	mc.g.position = Vector3(mc.x, 0, mc.z)
	mc.g.rotation.y = 0.0
	World.spin_wheels(mc.wheels, mc.wheel_rest, mc.spin)


class Daddy extends Crime:
	var snores := 0

	func _init() -> void:
		id = "daddy"
		title = "Snoring in public"
		who = "2-Pack's daddy"
		time = 85
		pts = 220
		line = ["TWOPACK", "I told on my daddy for snorin' at night,"]
		describe = "My daddy. In a hammock. Sounds like a leaf blower."
		steps = [{"k": "record", "t": func(): return "Record his snoring on your flip phone (%d/3). Close, but not too close." % snores, "m": "RECORD"},
				{"k": "play", "t": "Play it back right in his ear", "m": "PLAY IT BACK"}]

	func target() -> Vector3:
		return Vector3(World.HAMMOCK[0], 1.1, World.HAMMOCK[1])

	func start() -> void:
		snores = 0
		World.reset_dad()
		G.W.dad.on = true

	func act():
		var k: String = G.cur(self).k
		if k == "record":
			return {"x": World.HAMMOCK[0], "z": World.HAMMOCK[1], "r": 5.4, "rmin": 2.0, "label": "Record the snoring", "fn": func(): Minigames.start_record(self)}
		if k == "play":
			return {"x": World.HAMMOCK[0] - 0.9, "z": World.HAMMOCK[1] + 1.05, "r": 1.1, "label": "Play it back in his ear", "fn": _play}
		return null

	func _play() -> void:
		handling = true
		G.P.yaw = PI
		Audio.sfx("snore", 1.6)
		G.later(0.5, _wake)
		G.talk([["DADDY", "WHAT?! WHO'S SNORIN'?!", 1.6], ["TWOPACK", "You. You snorin'.", 1.4], ["TWOPACK", "I told on my daddy for snorin' at night,", 2.3]], _woke)

	func _wake() -> void:
		G.W.dad.awake = true
		G.W.dad.fall = 0.0

	func _woke() -> void:
		Crimes.busted(self, "WIDE AWAKE!")
		G.later(3.0, func():
			if not G.C.daddy.active:
				World.reset_dad())

	func end(_why: String) -> void:
		G.W.dad.on = false


class SquirrelCase extends Crime:
	func _init() -> void:
		id = "squirrel"
		title = "Stole Gary's lunch"
		who = "A squirrel"
		time = 80
		pts = 220
		line = ["TWOPACK", "I told on a squirrel - now that squirrel's in JAIL!"]
		describe = "Squirrel. Fluffy tail. Armed with a sandwich."
		steps = [{"k": "catch", "t": "Catch the squirrel. He's fast: run (Shift), corner him, grab him (E).", "m": "CATCH HIM"},
				{"k": "jail", "t": "Lock him up in the County Jail", "m": "LOCK HIM UP"}]

	func target() -> Vector3:
		return Vector3(G.W.sq.x, 0.45, G.W.sq.z)

	func start() -> void:
		var q = G.W.sq
		q.x = -6.4
		q.z = -0.9
		q.yaw = PI
		q.g.visible = true
		q.held = false
		q.jailed = false
		q.tired = 0.0
		q.run = 0.0
		q.w_t = 0.0
		Hud.say("GARY", "2-Pack! A squirrel took my sandwich!", 2.0)

	func update(dt: float) -> void:
		Stage2Crimes.update_squirrel(dt, self)

	func act():
		var k: String = G.cur(self).k
		var q = G.W.sq
		if k == "catch" and not q.held:
			return {"x": q.x, "z": q.z, "r": 1.05, "label": "Grab the squirrel", "fn": _grab}
		if k == "jail":
			return {"x": World.JAIL[0], "z": World.JAIL[1] + 1.1, "r": 1.05, "label": "Lock him up", "fn": _lock_up}
		return null

	func _grab() -> void:
		var q = G.W.sq
		q.held = true
		Audio.sfx("cash")
		Hud.pop(Vector3(q.x, 0.5, q.z), "GOTCHA")
		Crimes.adv(self)

	func _lock_up() -> void:
		var q = G.W.sq
		q.held = false
		q.jailed = true
		handling = true
		G.P.yaw = PI
		Audio.sfx("cuffs")
		G.talk([["TWOPACK", "I told on a squirrel - now that squirrel's in JAIL!", 2.6]], func(): Crimes.busted(self, "LOCKED UP!"))

	func end(why: String) -> void:
		if why != "busted":
			G.W.sq.g.visible = false
			G.W.sq.held = false
			G.W.sq.jailed = false


static func update_squirrel(dt: float, _c: Crime) -> void:
	var q = G.W.sq
	var P := G.P
	if q.held or q.jailed:
		return
	var dx: float = q.x - P.x
	var dz: float = q.z - P.z
	var d := sqrt(dx * dx + dz * dz)
	var want := 0.0
	var spd := 0.0
	q.tired -= dt
	q.zig_t -= dt
	if q.zig_t <= 0:
		q.zig = U.rand(-0.9, 0.9)
		q.zig_t = U.rand(0.35, 0.8)
	if d < 5.2 and q.tired <= 0:
		want = atan2(dx, dz) + q.zig
		spd = 5.0
		q.run += dt
		if q.run > 3.2:
			q.tired = 1.8
			q.run = 0.0
	else:
		q.run = maxf(0.0, q.run - dt)
		q.w_t -= dt
		if q.w_t <= 0:
			q.w_yaw = U.rand(0, TAU)
			q.w_t = U.rand(1.5, 3.5)
		want = q.w_yaw
		spd = 1.6 if q.tired > 0 else 1.1
	q.yaw = U.turn_toward(q.yaw, want, 10.0 * dt)
	var al := maxf(0.0, cos(U.ang_diff(q.yaw, want)))
	var st := spd * al * al * dt
	var fx := sin(q.yaw)
	var fz := cos(q.yaw)
	var nx: float = q.x + fx * st
	var nz: float = q.z + fz * st
	var out := nx < -31.5 or nx > 30 or nz < -6 or nz > -0.25
	if out or Movement.blocked_ahead(q.body, nx, nz, fx, fz, q.r) != null:
		q.w_yaw = q.yaw + (1.0 if randf() < 0.5 else -1.0) * U.rand(1.6, 2.6)
		q.zig = U.ang_diff(atan2(dx, dz), q.w_yaw)
		q.zig_t = 0.5
		if d >= 5.2:
			q.w_t = 1.2
		q.moving = false
	else:
		q.x = nx
		q.z = nz
		q.moving = st > 1e-4


class Baby extends Crime:
	var told := 0

	func _init() -> void:
		id = "baby"
		title = "Cutting the line"
		who = "A baby"
		time = 52
		pts = 240
		line = ["TWOPACK", "I told on a baby for cuttin' the line,"]
		describe = "Baby. Diaper. No respect for the line."
		steps = [{"k": "spy", "t": "Catch her cutting the ice-cream line. Binoculars.", "m": "!"},
				{"k": "tell", "t": func(): return "Tell everybody in line (%d/4) before she gets her cone" % told, "m": "TELL THE LINE"}]

	func target() -> Vector3:
		return Vector3(G.W.baby.x, 0.35, G.W.baby.z)

	func start() -> void:
		told = 0
		for L in G.W.liners:
			L.told = false
			L.yaw = PI / 2
			L.rig.g.visible = true
		var b: Walker = G.W.baby
		b.x = 19.2
		b.z = World.CART[1] + 0.82
		b.yaw = PI / 2
		b.visible = true
		G.W.baby_rig.g.visible = true
		b.target = [World.CART[0] - 0.75, World.CART[1] + 0.82]
		b.speed = 4.6 / (time * maxf(0.65, 1.0 - G.S.score / 8000.0) * 0.92)

	func update(dt: float) -> void:
		if handling:
			return
		Movement.step_walker(G.W.baby, dt)

	func act():
		if G.cur(self).k != "tell":
			return null
		var best = null
		var bd := 1.6
		for L in G.W.liners:
			if L.told:
				continue
			var d := Vector2(G.P.x - L.x, G.P.z - L.z).length()
			if d < bd:
				bd = d
				best = L
		if best == null:
			return null
		return {"x": best.x, "z": best.z, "r": 1.6, "label": "Tell 'em: that baby cut", "fn": func(): _tell(best)}

	func _tell(L) -> void:
		L.told = true
		told += 1
		Audio.sfx("step")
		var lines := ["Hey! She cut!", "Is that a... baby?", "Unbelievable.", "I been here since noon!"]
		Hud.say("LINER", lines[(told - 1) % 4], 1.4)
		if told >= 4:
			handling = true
			G.talk([["TWOPACK", "I told on a baby for cuttin' the line,", 2.4], ["VENDOR", "Back of the line, kid.", 1.6]], func(): Crimes.busted(self, "BACK OF THE LINE!"))
		else:
			Hud.toast("Told %d/4. Keep goin'." % told)

	func end(_why: String) -> void:
		G.W.baby.visible = false
		G.W.baby_rig.g.visible = false
		for L in G.W.liners:
			L.rig.g.visible = false


# ---- the finale: the cops parked in the fire lane
class Cops extends Crime:
	func _init() -> void:
		id = "cops"
		title = "Parked in the fire lane"
		who = "Officers Dan & Steve"
		time = INF
		pts = 1000
		line = ["TWOPACK", "I told on the COPS - now the cops in a hurry!"]
		describe = "The police. In the fire lane. Eating donuts."
		steps = [{"k": "spy", "t": "Photograph the cop car parked in the fire lane", "m": "!"},
				{"k": "call911", "t": "Call 911 on the cops. Any payphone.", "m": "CALL 911"},
				{"k": "precinct", "t": "Report this... to the POLICE. Go to Precinct 9.", "m": "PRECINCT 9"}]

	func target() -> Vector3:
		return Vector3(G.car.x, 1.5, G.car.z)

	func start() -> void:
		Hud.toast("Wait... is that the cop car? In the FIRE LANE?")

	func spy_ok() -> bool:
		return G.car.state == "hydrant"

	func act():
		if G.cur(self).k == "precinct":
			return {"x": 36.2, "z": -1.7, "r": 2.4, "label": "Report the cops to the police", "fn": func(): Game.start_finale()}
		return null
