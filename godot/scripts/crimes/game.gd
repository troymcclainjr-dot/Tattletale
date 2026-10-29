class_name Game
## Flow (game.js): start, stages, the music video, the finale, game over.

const SAVE_PATH := "user://tattletale.cfg"


static func reset_game(stage: int, keep := false) -> void:
	var S := G.S
	var P := G.P
	var W := G.W
	var carry := {"score": S.score, "busts": S.busts, "still": S.still, "time": S.time} if keep else {"score": 0, "busts": 0, "still": 0, "time": 0.0}
	S.strikes = 0
	S.case_no = 0
	S.spawn_t = 5.0
	S.first_ev = true
	S.next = G.STAGES[stage].first
	S.gary_t = 0.0
	S.stage = stage
	S.told = {}
	S.finale_queued = false
	S.fin = null
	S.score = carry.score
	S.busts = carry.busts
	S.still = carry.still
	S.time = carry.time
	G.LATER.clear()
	Minigames.end_lock()
	for c in G.C.values():
		if c.active:
			c.end("reset")
		c.active = false
		c.si = 0
		c.dispatched = false
		c.handling = false
		c.frozen = false
		c.cool = 0.0
	W.dan.escort = null
	W.dan.lost = false
	W.dan.speed = 1.6
	W.dan.detour = null
	G.tp.cup.visible = false
	W.mama.g.visible = false
	for b in W.bills:
		b.visible = false
	W.sq.g.visible = false
	W.sq.held = false
	W.sq.jailed = false
	W.mama_car.g.visible = false
	for L in W.liners:
		L.rig.g.visible = false
	W.baby.visible = false
	W.baby_rig.g.visible = false
	World.reset_dad()
	W.dad.on = stage == 2
	W.ricky.visible = false
	G.ricky.g.visible = false
	for w in [W.dan, W.steve]:
		w.target = null
		w.detour = null
	World.set_lawn(false)
	var car: CopCar = G.car
	car.x = 42.0
	car.h = PI
	car.state = "parked"
	car.queue = []
	car.on_arrive = null
	G.cops_home()
	if stage == 2:
		P.x = -3.0
		P.z = -1.6
		P.yaw = -PI / 2
	else:
		P.x = 0.6
		P.z = -4.0
		P.yaw = PI / 2
	G.cam_yaw = P.yaw
	G.cam_pitch = 0.32
	Crimes.start_crime("gary")
	Hud.clear_subs()


static func save_stage(n: int) -> void:
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)
	cf.set_value("progress", "stage", n)
	cf.save(SAVE_PATH)


static func saved_stage() -> int:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return 1
	return int(cf.get_value("progress", "stage", 1))


static func start_stage(n: int, keep: bool) -> void:
	Audio.start()
	Audio.set_music(G.S.music_on)
	reset_game(n, keep)
	G.S.mode = "play"
	Hud.hide_screens()
	Hud.show_hud(true)
	Player.update_camera(0.0, true)
	Hud.card(G.STAGES[n].name.to_upper(), G.STAGES[n].sub, 3.2)
	if n == 2:
		Hud.say("TWOPACK", "I told on my mama for runnin' a light,", 2.3)
		G.later(3.4, func(): Hud.toast("New side of the block: the crosswalk, Daddy's hammock, the squirrel, the ice-cream line."))


static func stage1_clear() -> void:
	var S := G.S
	if S.mode != "play" and S.mode != "puzzle":
		return
	if S.mode == "puzzle":
		Puzzles.close_puzzle()
	Minigames.end_lock()
	S.mode = "cut"
	S.bino_on = false
	G.K.clear()
	G.drag = false
	Hud.bino(false)
	Hud.show_hud(false)
	save_stage(2)
	Hud.card("STAGE 1 CLEAR", "Everybody on the block got told on.", 3)
	Hud.say("TWOPACK", "Snitch season, baby!", 2)
	Audio.sfx("win")
	G.later(3.2, func(): play_video())


static func play_video() -> void:
	G.S.mode = "video"
	Audio.set_music(false)
	Hud.play_video(func(): start_stage(2, true))


static func start_finale_setup() -> void:
	if G.car.state != "parked":
		G.later(1.0, func(): start_finale_setup())
		return
	for w in [G.W.dan, G.W.steve]:
		w.visible = false
		w.rig.g.visible = false
	G.car.state = "tohydrant"
	Crimes.start_crime("cops")


# ---- the finale: 2-Pack reports the cops to the police
static func _cam(p: Vector3, l: Vector3, f: float) -> Dictionary:
	return {"p": p, "l": l, "f": f}


static func start_finale() -> void:
	var S := G.S
	var c: Crime = G.C.cops
	c.handling = true
	S.mode = "cut"
	S.bino_on = false
	Hud.bino(false)
	Hud.show_hud(false)
	S.fin = {"cam": _cam(Vector3(39.4, 2.3, 5.4), Vector3(35.4, 1.1, -1.3), 44.0), "cuffed": false, "gary_phone": false, "snap": false, "ricky": false}
	G.P.x = 36.2
	G.P.z = -1.9
	G.P.yaw = 0.0
	Hud.say("TWOPACK", "I'm reportin' this... to the POLICE!", 2.0)
	G.later(1.2, func(): _finale_car())


static func _finale_car() -> void:
	Audio.sfx("siren")
	G.car.goal = 30.6
	G.car.state = "goto"
	G.car.on_arrive = func(): _finale_arrive()


static func _finale_arrive() -> void:
	Audio.sfx("door")
	var sl := [[35.0, -0.9], [37.4, -0.9]]
	var cops := [G.W.dan, G.W.steve]
	for k in 2:
		var w: Walker = cops[k]
		w.x = G.car.x - 0.6 + 1.2 * k
		w.z = G.car.z - 1.25
		w.yaw = PI
		w.visible = true
		w.rig.g.visible = true
		w.target = sl[k]
	G.talk([["TWOPACK", "FINALLY! He right there, y'all! Right th- wait. What y'all doin'?", 3.0],
			["STEVE", "Sir, somebody called in a public nuisance.", 2.4]], func(): _finale_cuffs())


static func _finale_cuffs() -> void:
	Audio.sfx("cuffs")
	G.S.fin.cuffed = true
	G.later(0.8, func(): _finale_gary())


static func _finale_gary() -> void:
	var fin: Dictionary = G.S.fin
	fin.cam = _cam(Vector3(-1.4, 1.5, 4.2), Vector3(-3.3, 0.5, 0.75), 36.0)
	fin.gary_phone = true
	fin.snap = true
	G.talk([["GARY", "Yeah, that's him, officer.", 1.8], ["GARY", "...Heyyyy, 2-Pack.", 2.0]], func(): _finale_back())


static func _finale_back() -> void:
	var fin: Dictionary = G.S.fin
	fin.gary_phone = false
	fin.cam = _cam(Vector3(39.4, 2.3, 5.4), Vector3(35.4, 1.1, -1.3), 44.0)
	fin.snap = true
	G.talk([["TWOPACK", "...Officer. Ricky got your wallet.", 2.2]], func(): _finale_ricky())


static func _finale_ricky() -> void:
	var w: Walker = G.W.ricky
	w.x = 46.0
	w.z = 0.8
	w.yaw = -PI / 2
	w.visible = true
	G.ricky.g.visible = true
	w.speed = 3.6
	w.target = [-30.0, 0.8]
	G.S.fin.ricky = true
	G.later(1.4, func(): G.talk([["DAN", "...RICKYYYY!", 2.0]], func(): G.later(1.8, func(): _finale_end())))


static func _finale_end() -> void:
	G.S.told["cops"] = true
	G.S.score += 1000
	finish_game()


static func update_finale(dt: float) -> void:
	var S := G.S
	if S.fin == null:
		return
	for w in [G.W.dan, G.W.steve]:
		if w.visible:
			if Movement.step_walker(w, dt):
				w.yaw = U.turn_toward(w.yaw, atan2(G.P.x - w.x, G.P.z - w.z), 4.0 * dt)
	if S.fin.ricky:
		Movement.step_walker(G.W.ricky, dt)


static func _stats() -> Dictionary:
	return {"score": G.S.score, "busts": G.S.busts, "still": G.S.still, "time": G.S.time}


static func finish_game() -> void:
	G.S.mode = "over"
	Hud.show_hud(false)
	Hud.bino(false)
	Hud.show_over("Stage 2 clear", "Gary called it in. To be continued...", _stats(), true)


static func start_game() -> void:
	Audio.start()
	Audio.set_music(G.S.music_on)
	reset_game(1)
	G.S.mode = "play"
	Hud.hide_screens()
	Hud.show_hud(true)
	Player.update_camera(0.0, true)
	Hud.card("STAGE 1", "Snitch Season", 2.6)
	Hud.say("TWOPACK", "Yeah... this one goes out to Precinct Nine.", 2.4)
	G.later(2.6, func(): Hud.toast("Every crime gets reported its own way. Your case file says what to do next."))


static func game_over() -> void:
	var S := G.S
	if S.mode == "over":
		return
	if S.mode == "puzzle":
		Puzzles.close_puzzle()
	S.mode = "over"
	S.bino_on = false
	G.K.clear()
	G.drag = false
	Hud.show_hud(false)
	Hud.bino(false)
	Minigames.end_lock()
	Hud.show_over("Shift over", "I keep on callin', but nothin' gets done", _stats(), S.stage == 2)
