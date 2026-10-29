class_name Crimes
## How a crime works (crimes-core.js): steps, timers, spawning, stages, dispatching the cop
## car, and busted() (copcar.js). Every crime gets reported its own way; a case is a list of
## steps and the case file always shows the next one.

const MAILSTOPS := [[-26.25, -2.3], [-20.45, -2.3], [-13.45, -2.3]]
const POOL_ALL := ["ricky", "granny", "timmy", "lawn", "mail", "mama", "daddy", "squirrel", "baby"]
const EXPIRE := {
	"ricky": "Ricky got away. With the bag.",
	"granny": "Grandma made it across. Free woman.",
	"timmy": "Timmy sold out. He's a millionaire now.",
	"lawn": "Mrs. Johnson watered it. Evidence destroyed.",
	"mail": "The mail got delivered. Bent.",
	"mama": "Mama made it home. She's gonna act like nothin' happened.",
	"daddy": "Daddy woke up on his own. Evidence: gone.",
	"squirrel": "The squirrel ate the evidence.",
	"baby": "The baby got her cone. Sprinkles and everything.",
}


## defCrime for every case, in the JS order (G.C iterates in this order, like Object.values(C)).
static func define_all() -> void:
	G.C.clear()
	for c in [Stage1Crimes.Gary.new(), Stage1Crimes.Ricky.new(), Stage1Crimes.Granny.new(), Stage1Crimes.Timmy.new(),
			Stage1Crimes.Lawn.new(), Stage1Crimes.Mail.new(), Stage2Crimes.Mama.new(), Stage2Crimes.Daddy.new(),
			Stage2Crimes.SquirrelCase.new(), Stage2Crimes.Baby.new(), Stage2Crimes.Cops.new()]:
		G.C[c.id] = c


static func adv(c: Crime) -> void:
	c.si += 1
	Audio.sfx("step")
	Hud.toast("%s: %s" % [G.short_name(c), G.step_text(G.cur(c))])


static func start_crime(id: String) -> void:
	var c: Crime = G.C[id]
	var S := G.S
	c.active = true
	c.si = 0
	c.dispatched = false
	c.handling = false
	S.case_no += 1
	c.no = S.case_no
	c.left = INF if is_inf(c.time) else c.time * maxf(0.65, 1.0 - S.score / 8000.0)
	c.full = c.left
	c.start()
	if id != "gary":
		Hud.toast("New case: %s. %s" % [c.title, G.step_text(G.cur(c))])
		Audio.sfx("tick")


static func end_crime(c: Crime, why: String) -> void:
	var S := G.S
	c.active = false
	c.cool = 22.0
	if S.lock != null and S.lock.get("c") == c:
		Minigames.end_lock()
	c.end(why)
	if why == "expired" and S.strikes < 3:
		S.strikes += 1
		Hud.toast(EXPIRE[c.id])
		Audio.sfx("buzz")
		if S.strikes >= 3:
			G.later(1.4, func(): Game.game_over())


static func active_count() -> int:
	var n := 0
	for id in G.STAGES[G.S.stage].pool:
		if G.C[id].active:
			n += 1
	return n


static func update_crimes(dt: float) -> void:
	var S := G.S
	for c in G.C.values():
		if not c.active:
			c.cool -= dt
			continue
		c.update(dt)
		if c.active and not c.dispatched and not c.handling and not is_inf(c.left):
			c.left -= dt
			if c.left <= 0:
				end_crime(c, "expired")
	Stage1Crimes.update_escort(dt)
	Minigames.update_lock(dt)
	var mx := 2 if S.stage == 2 else (3 if S.score >= 1500 else 2)
	if not S.finale_queued and active_count() < mx:
		S.spawn_t -= dt
		if S.spawn_t <= 0:
			var pool: Array = G.STAGES[S.stage].pool
			var id = S.next if (S.next != null and not G.C[S.next].active) else null
			S.next = "ricky" if id == "granny" else null
			if id == null:
				var opts := pool.filter(func(k): return not G.C[k].active and G.C[k].cool <= 0)
				var fresh := opts.filter(func(k): return not S.told.has(k))
				var from := fresh if fresh.size() else opts
				if from.size():
					id = from[int(randf() * from.size())]
			if id != null:
				start_crime(id)
			S.spawn_t = 9.0 if id == G.STAGES[S.stage].first else U.rand(10, 17)


static func dispatch(ids: Array) -> void:
	for id in ids:
		G.C[id].dispatched = true
		G.car.queue.append(id)
	if G.car.state == "parked":
		G.car.state = "leaving"
		G.car.t = 0.0


static func check_stage() -> void:
	var S := G.S
	if S.mode != "play" and S.mode != "puzzle":
		return
	for id in G.need_list():
		if not S.told.has(id):
			return
	if S.stage == 1:
		G.later(1.8, func(): Game.stage1_clear())
	elif not G.C.cops.active and not S.finale_queued:
		S.finale_queued = true
		Game.start_finale_setup()


static func busted(c: Crime, label := "") -> void:
	var S := G.S
	var t := c.target()
	Hud.pop(t, "STILL THERE" if c.id == "gary" else (label if label != "" else "BUSTED!"))
	S.told[c.id] = true
	if c.id == "gary":
		S.still += 1
		c.si = 0
		c.dispatched = false
		Hud.toast("He's still there.")
		Audio.sfx("buzz")
		check_stage()
		return
	S.busts += 1
	var bonus := roundi(c.pts * (1.0 + maxf(0.0, c.left) / c.full))
	S.score += bonus
	Hud.toast("%s busted · +%d" % [G.short_name(c), bonus])
	Audio.sfx("win")
	end_crime(c, "busted")
	check_stage()


## Crimes with evidence in hand, waiting to be called in (interact.js pendingEvidence).
static func pending_evidence() -> Array:
	return G.C.values().filter(func(c): return c.active and G.cur(c).k == "call" and not c.dispatched and not c.handling)
