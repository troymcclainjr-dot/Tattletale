class_name Stage1Crimes
## Stage 1 crimes (crimes-stage1.js): Gary, Ricky (and Dan's escort), Grandma, Timmy, the lawn, the mailman.


class Gary extends Crime:
	func _init() -> void:
		id = "gary"
		title = "Smoking crack in the gutter"
		who = "Gary · since 2009"
		time = INF
		pts = 0
		line = ["TWOPACK", "They still smokin' crack in my gutter... and they STILL THERE!"]
		describe = "Gary. He's in the gutter. He's always in the gutter."
		steps = [{"k": "spy", "t": "Spy on him with binoculars", "m": "!"},
				{"k": "call", "t": "Call it in: any payphone, or Precinct 9", "m": "CALL IT IN"}]
		bust = [["COPS", "Hey, Gary!", 1.6], ["GARY", "Heyyy, fellas!", 1.8]]

	func target() -> Vector3:
		return Vector3(-3.55, 0.45, 0.73)

	func slots(t: Vector3) -> Array:
		return [[t.x + 0.3, 1.75], [t.x + 1.5, 1.75]]


class Ricky extends Crime:
	var cash := 0
	var drop_t := 1.5

	func _init() -> void:
		id = "ricky"
		title = "Bank robbery"
		who = "Ricky"
		time = 130
		pts = 600
		line = ["TWOPACK", "Striped shirt, eye mask, and a big bag of cash!"]
		describe = "Striped shirt, eye mask, and a big bag of cash!"
		steps = [{"k": "cash", "t": func(): return "Follow the money: pick up the bills he's dropping (%d/3)" % mini(3, cash), "m": "FOLLOW THE $"},
				{"k": "spy", "t": "ID him with binoculars", "m": "!"},
				{"k": "getdan", "t": "Go get Officer Dan at Precinct 9 (east end). Ricky won't wait.", "m": "GET DAN"},
				{"k": "lead", "t": "Lead Dan to Ricky. Don't lose him.", "m": "LEAD DAN"}]

	func target() -> Vector3:
		return Vector3(G.W.ricky.x, 1.2, G.W.ricky.z)

	func start() -> void:
		var w: Walker = G.W.ricky
		w.x = 28.0
		w.z = -6.2
		w.yaw = 0.0
		w.visible = true
		G.ricky.g.visible = true
		w.route = [[28.0, -1.05], [-26.0, -1.05], [39.0, -1.05]]
		w.ri = 0
		w.target = w.route[0]
		cash = 0
		drop_t = 1.5
		frozen = false
		for b in G.W.bills:
			b.visible = false

	func update(dt: float) -> void:
		var w: Walker = G.W.ricky
		if frozen:
			w.target = null
			w.yaw = U.turn_toward(w.yaw, atan2(G.W.dan.x - w.x, G.W.dan.z - w.z), 4.0 * dt)
			return
		if Movement.step_walker(w, dt):
			w.ri = 1 if w.ri >= 2 else w.ri + 1
			w.target = w.route[w.ri]
		drop_t -= dt                                    # a trail of dropped cash
		if drop_t <= 0 and w.moving and w.z > -2:
			drop_t = 4.2
			var b: Node3D = null
			for bb in G.W.bills:
				if not bb.visible:
					b = bb
					break
			if b == null:
				b = G.W.bills[0]
				for bb in G.W.bills:
					if bb.get_meta("t") < b.get_meta("t"):
						b = bb
			b.position = Vector3(w.x - sin(w.yaw) * 0.5, 0.18, w.z - cos(w.yaw) * 0.5)
			b.rotation.y = U.rand(0, TAU)
			b.set_meta("t", G.clock)
			b.visible = true
		for b in G.W.bills:
			if not b.visible:
				continue
			b.position.y = 0.19 + 0.03 * sin(G.clock * 4.0 + b.get_meta("t"))
			b.rotation.y += dt * 0.8
			if G.S.mode == "play" and Vector2(G.P.x - b.position.x, G.P.z - b.position.z).length() < 0.8:
				b.visible = false
				cash += 1
				Audio.sfx("cash")
				Hud.pop(b.position, "$ %d/3" % mini(cash, 3))
				if G.cur(self).k == "cash" and cash >= 3:
					Crimes.adv(self)

	func end(_why: String) -> void:
		G.W.ricky.visible = false
		G.ricky.g.visible = false
		for b in G.W.bills:
			b.visible = false
		if G.W.dan.escort == "follow":
			Stage1Crimes.send_dan_home()


class Granny extends Crime:
	func _init() -> void:
		id = "granny"
		title = "Jaywalking"
		who = "Grandma"
		time = 62
		pts = 180
		line = ["TWOPACK", "Saw Grandma jaywalkin' - she ain't even use the signs!"]
		describe = "Grandma. Walker. Tennis balls. No crosswalk."
		steps = [{"k": "spy", "t": "Catch her in the act with binoculars", "m": "!"},
				{"k": "whistle", "t": "Get in front of her in the street and blow your whistle on the beat", "m": "WHISTLE"}]
		bust = []

	func target() -> Vector3:
		return Vector3(G.W.granny.x, 1.1, G.W.granny.z)

	func start() -> void:
		var w: Walker = G.W.granny
		w.x = 7.2
		w.z = -4.6
		w.yaw = 0.0
		w.visible = true
		G.granny.g.visible = true
		w.target = [7.2, 14.6]
		frozen = false

	func update(dt: float) -> void:
		var w: Walker = G.W.granny
		if frozen or dispatched:
			return
		if w.target == null and w.z < 14:
			w.target = [7.2, 14.6]
		Movement.step_walker(w, dt)

	func act():
		if G.cur(self).k != "whistle" or frozen:
			return null
		var w: Walker = G.W.granny
		if w.z < 0.3:
			return null
		return {"x": w.x, "z": w.z + 1.35, "r": 1.0, "label": "Blow the whistle", "fn": func(): Minigames.start_rhythm(self)}

	func end(_why: String) -> void:
		G.W.granny.visible = false
		G.granny.g.visible = false

	func slots(t: Vector3) -> Array:
		return [[t.x + 1.2, t.z], [t.x - 1.2, t.z]]


class Timmy extends Crime:
	var busy := false

	func _init() -> void:
		id = "timmy"
		title = "Unlicensed lemonade stand"
		who = "Little Timmy"
		time = 80
		pts = 160
		line = ["TWOPACK", "No permit, no license - I need SWAT on demand!"]
		describe = "Little Timmy runnin' a lemonade stand."
		steps = [{"k": "buy", "t": "Go undercover: buy a cup at his stand", "m": "BUY ONE"},
				{"k": "mama", "t": "Tell his mama: knock on the door of the house behind the stand", "m": "KNOCK"}]
		bust = []

	func target() -> Vector3:
		return Vector3(16.5, 0.9, -3.6)

	func start() -> void:
		G.timmy.g.visible = true
		G.W_.stand_sign.visible = true
		G.W_.stand_closed.visible = false
		busy = false

	func act():
		if busy:
			return null
		var k: String = G.cur(self).k
		if k == "buy":
			return {"x": 16.5, "z": -2.25, "r": 1.1, "label": "Buy a lemonade (25¢)", "fn": _buy}
		if k == "mama":
			return {"x": 17.1, "z": -5.4, "r": 1.0, "label": "Knock on the door", "fn": _knock}
		return null

	func _buy() -> void:
		busy = true
		G.P.yaw = PI
		G.talk([["TWOPACK", "One lemonade, please.", 1.4], ["TIMMY", "That's 25 cents.", 1.4]], _bought)

	func _bought() -> void:
		busy = false
		if not active:
			return
		G.tp.cup.visible = true
		Audio.sfx("cash")
		Hud.pop(Vector3(16.5, 0.4, -2.6), "RECEIPT")
		Hud.say(line[0], line[1], 2.4)
		Crimes.adv(self)

	func _knock() -> void:
		busy = true
		handling = true
		G.P.yaw = PI
		Audio.sfx("knock")
		if G.P.z < -5.35:
			G.P.z = -5.35
		G.later(0.9, _mama_opens)
		G.later(1.0, _mama_talks)

	func _mama_opens() -> void:
		G.W.mama.g.visible = true
		Audio.sfx("door")

	func _mama_talks() -> void:
		G.talk([["MAMA", "Can I help y-", 1.0], ["TWOPACK", "Ma'am. Your son is runnin' an unlicensed business.", 2.3],
				["MAMA", "TIMMY! Get in this house!", 1.9], ["TIMMY", "Mooom!", 1.1]], _grounded)

	func _grounded() -> void:
		Crimes.busted(self, "GROUNDED!")
		G.later(1.6, _mama_closes)

	func _mama_closes() -> void:
		G.W.mama.g.visible = false
		Audio.sfx("door")

	func end(_why: String) -> void:
		G.timmy.g.visible = false
		G.W_.stand_sign.visible = false
		G.W_.stand_closed.visible = true
		G.tp.cup.visible = false

	func slots(_t: Vector3) -> Array:
		return [[15.2, -1.6], [17.8, -1.6]]


class Lawn extends Crime:
	func _init() -> void:
		id = "lawn"
		title = "Lawn a quarter inch too brown"
		who = "Mrs. Johnson"
		time = 90
		pts = 130
		line = ["TWOPACK", "Mrs. Johnson's lawn is a quarter inch too brown!"]
		describe = "Mrs. Johnson's lawn is a quarter inch too brown!"
		steps = [{"k": "measure", "t": "Measure it: stand on her lawn and get out your ruler", "m": "MEASURE"},
				{"k": "mail", "t": "Mail a complaint: the blue mailbox near your house", "m": "MAIL IT"}]
		bust = [["STEVE", "That is... a little brown.", 1.8]]

	func target() -> Vector3:
		return Vector3(11.5, 0.2, -5)

	func start() -> void:
		World.set_lawn(false)

	func act():
		var k: String = G.cur(self).k
		if k == "measure":
			return {"x": 11.5, "z": -4.7, "r": 2.3, "label": "Measure the grass", "fn": func(): Minigames.start_ruler(self)}
		if k == "mail":
			return {"x": G.MAILDROP[0], "z": G.MAILDROP[1] + 0.78, "r": 1.0, "label": "Mail the complaint", "fn": _mail}
		return null

	func _mail() -> void:
		G.P.yaw = PI
		Audio.sfx("door")
		Hud.say("TWOPACK", "Dear Precinct 9. Enclosed: one quarter inch.", 2.2)
		Crimes.dispatch(["lawn"])

	func end(why: String) -> void:
		if why == "expired":
			World.set_lawn(true)

	func slots(_t: Vector3) -> Array:
		return [[10.8, -1.6], [12.4, -1.6]]


class Mail extends Crime:
	var stop := 0
	var dir := 1
	var bend_t := 4.5
	var bending := true
	var photos := 0
	var last_photo := -1
	var spot_t := 0.0
	var sus := 0.0

	func _init() -> void:
		id = "mail"
		title = "Bending the mail"
		who = "The mailman"
		time = 100
		pts = 200
		line = ["TWOPACK", "I told on the mailman for bendin' my mail,"]
		describe = "The mailman. Bending it. On purpose."
		steps = [{"k": "tail", "t": func(): return "Tail him and photograph him bending mail (%d/2). Stay out of his sight." % photos, "m": "TAIL HIM"},
				{"k": "call", "t": "Call it in from a payphone", "m": "CALL IT IN"}]
		bust = [["DAN", "Sir, step away from the mail.", 1.8]]

	func target() -> Vector3:
		return Vector3(G.W.mail.x, 1.2, G.W.mail.z)

	func start() -> void:
		var w: Walker = G.W.mail
		w.x = Crimes.MAILSTOPS[0][0]
		w.z = Crimes.MAILSTOPS[0][1]
		w.yaw = -PI / 2
		w.visible = true
		G.mailman.g.visible = true
		w.target = null
		stop = 0
		dir = 1
		bend_t = 4.5
		bending = true
		photos = 0
		last_photo = -1
		spot_t = 0.0
		sus = 0.0

	func update(dt: float) -> void:
		var w: Walker = G.W.mail
		if dispatched:
			bending = false
			w.target = null
			return
		if bend_t > 0:
			bending = true
			w.yaw = U.turn_toward(w.yaw, -PI / 2, 4.0 * dt)
			bend_t -= dt
			if bend_t <= 0:
				bending = false
				var n := stop + dir
				if n < 0 or n > 2:
					dir *= -1
					n = stop + dir
				stop = n
				w.target = Crimes.MAILSTOPS[n]
		elif Movement.step_walker(w, dt):
			bend_t = 4.5
		sus = maxf(0.0, sus - dt)
		spot_t -= dt
		if G.cur(self).k == "tail" and spot_t <= 0 and G.S.mode == "play":
			var dx := G.P.x - w.x
			var dz := G.P.z - w.z
			var d := sqrt(dx * dx + dz * dz)
			if d == 0.0:
				d = 1.0
			var dot := (dx * sin(w.yaw) + dz * cos(w.yaw)) / d
			if d < (3.2 if bending else 7.5) and dot > 0.5:
				spot_t = 7.0
				sus = 3.0
				Hud.toast("He saw you. Your photos are no good now. Hang back." if photos else "He saw you. Hang back and use the binoculars.")
				photos = 0
				last_photo = -1
				Hud.say("MAILMAN", "...Mornin'.", 1.3)
				Audio.sfx("buzz")

	func spy_ok() -> bool:
		return bending and stop != last_photo and sus <= 0

	func end(_why: String) -> void:
		G.W.mail.visible = false
		G.mailman.g.visible = false

	func slots(t: Vector3) -> Array:
		return [[t.x + 1.2, t.z + 0.3], [t.x - 1.2, t.z + 0.3]]


# ---- Ricky: Officer Dan follows 2-Pack on foot
static func start_escort() -> void:
	var d: Walker = G.W.dan
	var r: Crime = G.C.ricky
	d.escort = "follow"
	d.lost = false
	d.speed = 2.6
	Crimes.adv(r)
	G.talk([["TWOPACK", "Officer - that's HIM! Right there, walkin' past!", 2.2], ["DAN", "Sir... we're on our lunch break.", 1.8],
			["TWOPACK", "It's TEN in the MORNIN'!", 1.6], ["DAN", "...Fine. Lead the way.", 1.6]])


static func send_dan_home() -> void:
	var d: Walker = G.W.dan
	d.escort = "home"
	d.lost = false
	d.speed = 1.8
	d.path = [[35.2, -1.6], [35.2, -2.75]]
	d.target = [d.x, -1.6]


static func update_escort(dt: float) -> void:
	var d: Walker = G.W.dan
	var r: Crime = G.C.ricky
	var P := G.P
	if not d.escort:
		return
	if d.escort == "follow":
		var dp := Vector2(P.x - d.x, P.z - d.z).length()
		if not d.lost and dp > 13:
			d.lost = true
			d.target = null
			Hud.say("DAN", "I'm gonna finish this donut.", 1.8)
			Hud.toast("You lost Dan. Go back for him.")
		elif d.lost and dp < 6:
			d.lost = false
			Hud.say("DAN", "Alright, alright.", 1.2)
		if not d.lost:
			d.target = [P.x + (d.x - P.x) / dp * 1.7, P.z + (d.z - P.z) / dp * 1.7] if dp > 2.3 else null
		Movement.step_walker(d, dt)
		if r.active and Vector2(d.x - G.W.ricky.x, d.z - G.W.ricky.z).length() < 3.2:
			d.escort = "bust"
			d.target = null
			r.frozen = true
			r.handling = true
			G.talk([["RICKY", "Mornin', officers.", 1.6], ["DAN", "Mornin', Ricky.", 1.4], ["DAN", "Nice bag, Ricky.", 1.5],
					["RICKY", "Thanks. I stole it.", 1.8]], func(): _ricky_busted())
	elif d.escort == "bust":
		d.yaw = U.turn_toward(d.yaw, atan2(G.W.ricky.x - d.x, G.W.ricky.z - d.z), 4.0 * dt)
	elif d.escort == "home":
		if Movement.step_walker(d, dt):
			if d.path.size():
				d.target = d.path.pop_front()
			else:
				d.escort = null
				d.yaw = 0.0
				d.speed = 1.6


static func _ricky_busted() -> void:
	Crimes.busted(G.C.ricky, "BUSTED!")
	send_dan_home()
