extends Node
## The smoke test (started by tests/smoke.gd). Boots the real main scene, then drives every
## crime to completion through its real steps (binocular spying, cash pickups, minigame presses
## on the beat, payphone puzzles, the cop car's trip and bust), the strikes -> game over path,
## stage 1 clear -> video -> stage 2, and the whole finale. Prints PASS/FAIL per check.

const DT := 1.0 / 60.0

var fails := 0
var passes := 0
var phase := 0
var frames := 0
var main: Node


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)


func _process(_d: float) -> void:
	frames += 1
	if frames < 4:          # let the occluder bodies settle into the physics space
		return
	if phase == 0:
		phase = 1
		G.manual = true
		seed(12345)
		var t0 := Time.get_ticks_msec()
		_run_all()
		print("[smoke] %d passed, %d failed (%.1f s game time, %d ms real)" % [passes, fails, G.clock, Time.get_ticks_msec() - t0])
		_finish.call_deferred()


func _finish() -> void:
	# The suite advances hours of game time in one process callback. Stop and
	# release its audio before quitting, then let the audio thread consume the
	# stop commands in real time rather than counting uncapped headless frames.
	Audio.set_paused(false)
	if is_instance_valid(Audio._music):
		Audio._music.stop()
		Audio._music.stream = null
	for voice in Audio._voices:
		voice.stop()
		voice.stream = null
	Audio._sfx.clear()
	var audio_deadline := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < audio_deadline:
		await get_tree().process_frame
	get_tree().quit(fails)


# ------------------------------------------------------------------ helpers
func check(ok: bool, what: String) -> bool:
	if ok:
		passes += 1
		print("[smoke] PASS ", what)
	else:
		fails += 1
		print("[smoke] FAIL ", what, "   (mode=%s stage=%d score=%d strikes=%d t=%.1f)" % [G.S.mode, G.S.stage, G.S.score, G.S.strikes, G.clock])
	return ok


func step(sec: float) -> void:
	for k in int(ceil(sec / DT)):
		G.tick(DT)


## Tick until cond() is true; false on timeout.
func until(cond: Callable, max_sec: float, each = null) -> bool:
	var t := 0.0
	while t < max_sec:
		if cond.call():
			return true
		if each != null:
			each.call()
		G.tick(DT)
		t += DT
	return cond.call()


func at(x: float, z: float, yaw := INF) -> void:
	G.P.x = x
	G.P.z = z
	if not is_inf(yaw):
		G.P.yaw = yaw


func quiet() -> void:
	# no surprise cases while one is under test
	G.S.spawn_t = 1e9
	G.S.next = null


## Hold the binoculars on crime c from where the player stands until done() (default: its step advances).
func spy(c: Crime, max_sec := 12.0, done = null) -> bool:
	var si := c.si
	if done == null:
		done = func(): return c.si > si
	G.K["binoculars"] = true
	var ok := until(done, max_sec, func():
		var eye := Vector3(G.P.x, World.ground_y(G.P.x, G.P.z) + 1.68, G.P.z)
		var v := c.target() - eye
		G.tt_aim(atan2(v.x, v.z), asin(clampf(v.y / v.length(), -1.0, 1.0))))
	if not ok:
		print("[smoke]   binoculars said: '%s' (bino_on=%s, target %s, player %.2f,%.2f)" % [G.bino_label, G.S.bino_on, c.target(), G.P.x, G.P.z])
	G.K.erase("binoculars")
	step(DT * 2)
	return ok


func press_e() -> void:
	if G.S.lock != null:
		Minigames.lock_press()
	else:
		Interact.interact()


func wait_car_parked(max_sec := 60.0) -> bool:
	return until(func(): return G.car.state == "parked", max_sec)


## Call in pending evidence at the payphone by (px, -3): open the puzzle, solve it.
func call_in(px: float, kind_want := "") -> bool:
	at(px, -2.3, PI)
	var it = Interact.nearest_interact()
	if not check(it != null and it.kind == "phone", "payphone at x=%.1f offers 'Use payphone'" % px):
		return false
	press_e()
	if not check(G.S.mode == "puzzle" and G.S.pz != null, "payphone opens a puzzle (%s)" % (G.S.pz.kind if G.S.pz else "none")):
		return false
	if kind_want != "":
		check(G.S.pz.kind == kind_want, "puzzle kind is %s" % kind_want)
	else:
		check(G.S.pz.kind in ["wires", "keypad", "menu"], "puzzle kind is wires/keypad/menu")
	G.puzzle_solved()
	check(G.S.pz.done, "puzzle_solved marks it done")
	return check(until(func(): return G.S.mode == "play", 4.0), "puzzle closes itself after the operator line")


## Cop car takes c from dispatch to the bust (busted() runs at the end of the lines).
func cop_bust(c: Crime, max_sec := 60.0) -> bool:
	check(c.dispatched, "%s is dispatched" % c.id)
	return check(until(func(): return not c.dispatched or not c.active, max_sec), "cop car busts %s" % c.id)


func busted_ok(c: Crime, score0: int, busts0: int) -> void:
	check(G.S.told.has(c.id), "%s is told on" % c.id)
	check(not c.active, "%s case closed" % c.id)
	check(G.S.busts == busts0 + 1 and G.S.score > score0, "%s scored (+%d)" % [c.id, G.S.score - score0])


# ------------------------------------------------------------------ the suite
func _run_all() -> void:
	t_boot()
	t_systems()
	G.start_game()
	check(G.S.mode == "play" and G.S.stage == 1 and G.S.score == 0 and G.C.gary.active, "start_game: playing stage 1, Gary's case open")
	t_input()
	t_gary(1)
	t_granny()
	t_ricky()
	t_timmy()
	t_lawn()
	t_extras()
	t_mail()
	t_stage_clear()
	t_daddy()
	t_mama()
	t_squirrel()
	t_baby()
	t_gary(2)
	t_finale()
	t_strikes()
	t_continue()


func t_boot() -> void:
	check(G.built and G.S.mode == "title", "boot: world built, title screen")
	check(G.C.size() == 11, "all 11 cases defined")
	check(G.C.gary.active, "Gary's case is open at boot (like the JS)")
	check(G.SOLIDS.size() == 33 and G.bodies.size() == 15, "colliders: %d solids, %d bodies" % [G.SOLIDS.size(), G.bodies.size()])
	check(G.OCCLUDERS.size() == 13, "13 occluder boxes")
	check(G.camera() != null and G.camera().current, "camera ready")
	step(1.0)


func t_systems() -> void:
	# rays hit the occluders: from the street toward 2-Pack's house front wall (z = -7)
	var h := Player.ray_hit(Vector3(0, 2, 0), Vector3(0, 0, -1), 20.0)
	check(absf(h - 7.0) < 0.05, "occluder ray hits 2-Pack's house at 7 m (%.2f)" % h)
	check(Player.ray_hit(Vector3(0, 2, 0), Vector3(1, 0, 0), 30.0) < 0.0, "ray along the street hits nothing")
	# resolve pushes out of a collider (the mail drop at 5.9, -3.0, r .42)
	var o := {"x": 5.95, "z": -3.0}
	Player.resolve(o, 0.33)
	check(Vector2(o.x - 5.9, o.z + 3.0).length() >= 0.749, "resolve pushes out of the mail drop")
	check(World.ground_y(0, -1) == 0.16 and World.ground_y(0, -4) == 0.12 and World.ground_y(0, 5) == 0.0 and World.ground_y(0, 14) == 0.16, "groundY heights")
	check(Minigames.inch(0.25) == "1/4 in" and Minigames.inch(0.5) == "1/2 in" and Minigames.inch(0.0) == "0 in" and Minigames.inch(1.0) == "1 in", "inch() readings")
	check(G.short_name(G.C.gary) == "Gary" and G.step_text(G.cur(G.C.ricky)).begins_with("Follow the money"), "short_name / step_text")
	check(G.need_list() == ["ricky", "granny", "timmy", "lawn", "mail", "gary"], "need_list stage 1")
	check(Assets.find(G.tp.g, "Mouth") != null and G.tp.arms[0].name == "ArmR" and G.tp.legs[0].name == "LegR", "puppet pivots bound (ArmR = arms[0])")
	check(G.tp.arms[0].position.x < 0.0, "ArmR is on the -x side")


func key_ev(code: Key, uni := 0) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = code
		e.keycode = code
		e.unicode = uni
		e.pressed = down
		get_viewport().push_input(e)


func t_input() -> void:
	# the real input path (G._unhandled_input), with events pushed into the viewport
	var music: bool = G.S.music_on
	key_ev(KEY_M)
	check(G.S.music_on != music, "M toggles the music")
	key_ev(KEY_M)
	key_ev(KEY_P)
	check(G.S.mode == "pause", "P pauses")
	var c0 := G.clock
	G.frame(0.1)
	check(G.clock == c0, "paused: the clock stands still")
	key_ev(KEY_P)
	check(G.S.mode == "play", "P again: back to play")
	var yaw0 := G.cam_yaw
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = Vector2(1200, 640)
	get_viewport().push_input(mb)
	var mm := InputEventMouseMotion.new()
	mm.position = Vector2(1300, 640)
	mm.relative = Vector2(100, 0)
	mm.screen_relative = Vector2(100, 0)
	get_viewport().push_input(mm)
	check(absf(G.cam_yaw - (yaw0 - 0.6)) < 0.001, "left-drag turns the camera (%.3f -> %.3f)" % [yaw0, G.cam_yaw])
	mb = mb.duplicate()
	mb.pressed = false
	get_viewport().push_input(mb)
	check(not G.drag, "releasing the button ends the drag")
	G.K["binoculars"] = true
	step(0.1)
	var fov: float = G.bino_fov
	var wh := InputEventMouseButton.new()
	wh.button_index = MOUSE_BUTTON_WHEEL_UP
	wh.pressed = true
	wh.position = Vector2(1200, 640)
	get_viewport().push_input(wh)
	check(G.S.bino_on and G.bino_fov == fov - 3.0, "wheel zooms the binoculars (%.0f -> %.0f)" % [fov, G.bino_fov])
	var by: float = G.bino_yaw
	mm = InputEventMouseMotion.new()
	mm.position = Vector2(1250, 640)
	mm.relative = Vector2(50, 0)
	mm.screen_relative = Vector2(50, 0)
	get_viewport().push_input(mm)
	check(absf(G.bino_yaw - (by - 50 * 0.0022 * G.bino_fov / 16.0)) < 0.001, "the mouse aims the binoculars")
	G.K.erase("binoculars")
	step(0.1)
	# puzzle keys and Esc
	G.C.gary.si = 1
	at(2.8, -2.3, PI)
	key_ev(KEY_E)
	check(G.S.mode == "puzzle", "E at the payphone opens the puzzle")
	key_ev(KEY_5, 53)
	check(G.S.mode == "puzzle", "digits go to the puzzle")
	key_ev(KEY_ESCAPE)
	check(G.S.mode == "play" and G.S.pz == null, "Esc hangs up")
	G.C.gary.si = 0
	at(2.0, -1.0)
	step(0.1)


func t_gary(stage: int) -> void:
	var c: Crime = G.C.gary
	quiet()
	wait_car_parked()
	var still0: int = G.S.still
	at(2.0, -1.0, -PI / 2)
	check(c.active and G.cur(c).k == "spy", "[stage %d] Gary: spy step" % stage)
	check(spy(c), "Gary: binoculars get the evidence")
	check(G.cur(c).k == "call", "Gary: step 2 is call it in")
	if not call_in(2.8):
		return
	check(G.car.state != "parked", "cop car leaves the precinct")
	if cop_bust(c):
		check(G.S.still == still0 + 1 and G.S.told.has("gary"), "Gary: still there x%d, told on" % G.S.still)
		check(c.active and c.si == 0, "Gary's case reopens (he's STILL there)")
	check(wait_car_parked(), "cop car comes home and parks")
	check(G.W.dan.visible and G.W.steve.visible, "the cops are back on the steps")


func t_granny() -> void:
	var c: Crime = G.C.granny
	quiet()
	Crimes.start_crime("granny")
	check(c.active and G.W.granny.visible, "Grandma: case opens, she starts across")
	at(12.0, -1.0, -PI / 2)
	check(spy(c), "Grandma: caught in the act with binoculars")
	check(G.cur(c).k == "whistle", "Grandma: whistle step")
	check(until(func(): return G.W.granny.z >= 0.4, 30.0), "Grandma reaches the street")
	var w: Walker = G.W.granny
	at(w.x, w.z + 1.35, PI)
	var it = Interact.nearest_interact()
	check(it != null and it.label == "Blow the whistle", "standing in front of her offers the whistle")
	var score0: int = G.S.score
	var busts0: int = G.S.busts
	press_e()
	check(G.S.lock != null and G.S.lock.kind == "rhythm" and c.frozen, "whistle minigame starts, Grandma stops")
	var L: Dictionary = G.S.lock
	for i in L.n:
		var bt: float = L.t0 + i * L.B
		until(func(): return G.clock >= bt, 5.0)
		press_e()
	check(L.hits == 6, "6/6 whistles on the beat (%d)" % L.hits)
	check(until(func(): return G.S.lock == null, 3.0), "whistle minigame ends")
	check(c.handling, "Grandma: citation scene")
	check(until(func(): return not c.active, 8.0), "Grandma: CITED")
	busted_ok(c, score0, busts0)


func t_ricky() -> void:
	var c: Crime = G.C.ricky
	quiet()
	wait_car_parked()
	Crimes.start_crime("ricky")
	check(c.active and G.W.ricky.visible, "Ricky: robs the bank")
	# follow the money: stand on each bill as it drops
	var ok := until(func(): return G.cur(c).k != "cash", 40.0, func():
		for b in G.W.bills:
			if b.visible:
				at(b.position.x, b.position.z)
				break)
	check(ok and c.cash >= 3, "Ricky: picked up 3 bills (%d)" % c.cash)
	var w: Walker = G.W.ricky
	at(w.x, 13.5, PI)
	check(spy(c), "Ricky: ID'd with binoculars")
	check(G.cur(c).k == "getdan", "Ricky: go get Dan")
	wait_car_parked()
	at(36.2, -1.7, PI)
	var it = Interact.nearest_interact()
	check(it != null and it.label == "Get Officer Dan", "precinct offers 'Get Officer Dan'")
	press_e()
	check(G.W.dan.escort == "follow" and G.cur(c).k == "lead", "Dan follows: lead him to Ricky")
	var score0: int = G.S.score
	var busts0: int = G.S.busts
	# lead Dan: stay a couple of meters ahead of him, toward Ricky, on the sidewalk
	ok = until(func(): return G.W.dan.escort != "follow", 90.0, func():
		var d: Walker = G.W.dan
		var dir := Vector2(G.W.ricky.x - d.x, G.W.ricky.z - d.z).normalized()
		at(d.x + dir.x * 2.6, -1.6))
	check(ok and G.W.dan.escort == "bust", "Dan reaches Ricky")
	check(until(func(): return not c.active, 10.0), "Ricky: BUSTED")
	busted_ok(c, score0, busts0)
	check(G.W.dan.escort == "home", "Dan walks home")
	check(until(func(): return G.W.dan.escort == null, 60.0), "Dan is back at the precinct")


func t_timmy() -> void:
	var c: Crime = G.C.timmy
	quiet()
	Crimes.start_crime("timmy")
	check(G.timmy.g.visible and G.W_.stand_sign.visible and not G.W_.stand_closed.visible, "Timmy: stand open")
	at(16.5, -2.25, PI)
	var it = Interact.nearest_interact()
	check(it != null and it.label == "Buy a lemonade (25¢)", "stand offers 'Buy a lemonade (25¢)'")
	press_e()
	check(until(func(): return G.cur(c).k == "mama", 5.0) and G.tp.cup.visible, "Timmy: bought a cup (receipt)")
	at(17.1, -5.4, PI)
	var score0: int = G.S.score
	var busts0: int = G.S.busts
	press_e()
	check(c.handling, "Timmy: knocked on mama's door")
	check(until(func(): return G.W.mama.g.visible, 2.0), "Timmy's mama opens the door")
	check(until(func(): return not c.active, 10.0), "Timmy: GROUNDED")
	busted_ok(c, score0, busts0)
	check(not G.tp.cup.visible and G.W_.stand_closed.visible, "stand closed, cup gone")
	check(until(func(): return not G.W.mama.g.visible, 3.0), "mama goes back in")


func t_lawn() -> void:
	var c: Crime = G.C.lawn
	quiet()
	wait_car_parked()
	Crimes.start_crime("lawn")
	at(11.5, -4.7, PI)
	press_e()
	check(G.S.lock != null and G.S.lock.kind == "ruler", "Lawn: ruler out")
	# a wrong reading costs 3 s
	until(func(): return absf(G.S.lock.v - 0.25) > 0.2, 3.0)
	var left0: float = c.left
	press_e()
	check(G.S.lock != null and c.left <= left0 - 2.99, "wrong reading: -3 s, ruler stays out")
	check(until(func(): return absf(G.S.lock.v - 0.25) < 0.03, 4.0), "ruler swings to 1/4 inch")
	press_e()
	check(G.S.lock == null and G.cur(c).k == "mail", "Lawn: measured 1/4 inch, mail it")
	at(G.MAILDROP[0], G.MAILDROP[1] + 0.78, PI)
	var it = Interact.nearest_interact()
	check(it != null and it.label == "Mail the complaint", "mail drop offers 'Mail the complaint'")
	var score0: int = G.S.score
	var busts0: int = G.S.busts
	press_e()
	if cop_bust(c):
		busted_ok(c, score0, busts0)


func t_mail() -> void:
	var c = G.C.mail
	quiet()
	wait_car_parked()
	Crimes.start_crime("mail")
	check(c.active and G.W.mail.visible and c.bending, "Mailman: bending mail at stop 1")
	# across the street, out of his sight (he looks up when he stops bending)
	at(-31.0, 13.5, PI / 2)
	check(spy(c, 6.0, func(): return c.photos >= 1), "Mailman: photo 1")
	check(c.photos == 1 and c.last_photo == 0, "photo counted for stop 1")
	check(not c.spy_ok(), "same stop can't be photographed twice")
	# he walks to the next stop; stay out of his sight
	check(until(func(): return c.bending and c.stop == 1, 20.0), "Mailman: bending at stop 2")
	check(spy(c, 6.0, func(): return c.photos >= 2), "Mailman: photo 2")
	check(G.cur(c).k == "call" and c.sus <= 0.0, "Mailman: call it in")
	if not call_in(-10.5):
		return
	var score0: int = G.S.score
	var busts0: int = G.S.busts
	if cop_bust(c):
		busted_ok(c, score0, busts0)
	wait_car_parked()


func t_extras() -> void:
	# Gary waves when 2-Pack walks by
	var gt: float = G.S.gary_t
	at(-2.8, 1.8, PI)
	step(0.1)
	check(G.S.gary_t > gt, "Gary says 'Heyyyy, 2-Pack!' when you're near")
	at(2.0, -1.0)
	# hang up, penalty, too-late
	var m = G.C.mail
	quiet()
	Crimes.start_crime("mail")
	m.si = 1
	at(2.8, -2.3, PI)
	press_e()
	check(G.S.mode == "puzzle", "puzzle open for the penalty test")
	var left0: float = m.left
	G.penalty(4)
	check(absf(m.left - (left0 - 4.0)) < 0.001, "penalty(4) costs every pending case 4 s")
	G.hang_up()
	check(G.S.mode == "play" and G.S.pz == null, "hang_up closes the puzzle")
	press_e()
	m.left = 0.05
	var strikes0: int = G.S.strikes
	step(0.2)
	check(G.S.mode == "play" and not m.active and G.S.strikes == strikes0 + 1, "case expires during the puzzle: 'Too late', strike")
	# mailman spotting
	quiet()
	Crimes.start_crime("mail")
	var w: Walker = G.W.mail
	at(w.x - 2.0, w.z, PI / 2)
	step(0.1)
	check(m.sus > 0.0, "the mailman spots you up close")
	Crimes.end_crime(m, "reset")
	G.S.strikes = strikes0
	# lock cancel
	Crimes.start_crime("lawn")
	at(11.5, -4.7, PI)
	press_e()
	Minigames.cancel_lock()
	check(G.S.lock == null, "Esc backs out of a minigame")
	Crimes.end_crime(G.C.lawn, "reset")
	G.S.strikes = strikes0
	step(0.1)


func t_stage_clear() -> void:
	var need := G.need_list()
	var told := need.filter(func(id): return G.S.told.has(id))
	if not check(told.size() == need.size(), "stage 1: told on everybody (%d/%d)" % [told.size(), need.size()]):
		for id in need:
			G.S.told[id] = true
		Crimes.check_stage()
	var score: int = G.S.score
	check(until(func(): return G.S.mode == "cut" or G.S.mode == "video", 4.0), "stage 1 clear: cutscene")
	check(Game.saved_stage() >= 2, "stage 2 saved")
	check(until(func(): return G.S.mode == "video", 5.0), "the music video rolls")
	G.start_stage(2, true)          # what the video's end / skip does
	check(G.S.mode == "play" and G.S.stage == 2 and G.S.score == score, "stage 2 starts, score carried (%d)" % G.S.score)
	check(G.W.dad.on and G.C.gary.active, "Daddy's snoring, Gary's still there")
	check(G.need_list() == ["mama", "daddy", "squirrel", "baby", "gary"], "need_list stage 2")
	step(0.5)


func t_daddy() -> void:
	var c = G.C.daddy
	quiet()
	Crimes.start_crime("daddy")
	at(World.HAMMOCK[0], World.HAMMOCK[1] + 3.5, PI)
	var it = Interact.nearest_interact()
	check(it != null and it.label == "Record the snoring", "Daddy: close (not too close) offers recording")
	press_e()
	check(G.S.lock != null and G.S.lock.kind == "record", "flip phone recording")
	check(until(func(): return G.cur(c).k == "play", 12.0) and c.snores == 3, "Daddy: 3 snores on tape")
	at(World.HAMMOCK[0] - 0.9, World.HAMMOCK[1] + 1.05, PI)
	var score0: int = G.S.score
	var busts0: int = G.S.busts
	press_e()
	check(c.handling, "Daddy: played it back in his ear")
	check(until(func(): return G.W.dad.awake, 1.0), "Daddy wakes up and falls out")
	check(until(func(): return not c.active, 8.0), "Daddy: WIDE AWAKE")
	busted_ok(c, score0, busts0)
	step(3.5)
	check(not G.W.dad.awake, "Daddy back in the hammock")


func t_mama() -> void:
	var c: Crime = G.C.mama
	quiet()
	wait_car_parked()
	Crimes.start_crime("mama")
	check(G.W.mama_car.g.visible and c.plate.length() == 4, "Mama: pink car on the road, plate %s" % c.plate)
	check(G.W.mama_car.plate.text.replace(" ", "") == c.plate and G.W.mama_car.plate.text.length() == 7, "plate label reads '%s'" % G.W.mama_car.plate.text)
	at(2.0, -1.0, PI)
	check(until(func(): return G.W_.tl_state == "red" and G.W.mama_car.x > -5, 20.0), "light turns red as she comes")
	check(spy(c, 6.0), "Mama: caught running the red")
	check(G.cur(c).k == "call", "Mama: call it in")
	if not call_in(2.8, "plate"):
		return
	var score0: int = G.S.score
	var busts0: int = G.S.busts
	if cop_bust(c):
		busted_ok(c, score0, busts0)


func t_squirrel() -> void:
	var c: Crime = G.C.squirrel
	quiet()
	Crimes.start_crime("squirrel")
	var q = G.W.sq
	check(q.g.visible, "Squirrel: on the loose")
	step(1.0)
	at(q.x + 0.6, q.z, -PI / 2)
	var it = Interact.nearest_interact()
	check(it != null and it.label == "Grab the squirrel", "next to him: 'Grab the squirrel'")
	press_e()
	check(q.held and G.cur(c).k == "jail", "Squirrel: GOTCHA")
	step(0.5)
	at(World.JAIL[0], World.JAIL[1] + 1.1, PI)
	var score0: int = G.S.score
	var busts0: int = G.S.busts
	press_e()
	check(q.jailed, "Squirrel: in the county jail")
	check(until(func(): return not c.active, 5.0), "Squirrel: LOCKED UP")
	busted_ok(c, score0, busts0)


func t_baby() -> void:
	var c = G.C.baby
	quiet()
	Crimes.start_crime("baby")
	check(G.W.baby.visible and G.W.liners.all(func(L): return L.rig.g.visible), "Baby: crawling up the ice-cream line")
	at(13.0, -0.5, PI / 2)
	check(spy(c), "Baby: caught cutting")
	var score0: int = G.S.score
	var busts0: int = G.S.busts
	for L in G.W.liners:
		at(L.x, L.z + 1.0, PI)
		var it = Interact.nearest_interact()
		check(it != null and it.label == "Tell 'em: that baby cut", "liner at x=%.1f: 'Tell 'em: that baby cut'" % L.x)
		press_e()
		step(0.2)
	check(c.told == 4, "told all 4 in line")
	check(until(func(): return not c.active, 6.0), "Baby: BACK OF THE LINE")
	busted_ok(c, score0, busts0)


func t_finale() -> void:
	var c: Crime = G.C.cops
	check(until(func(): return c.active, 30.0), "finale: the cops case opens")
	check(until(func(): return G.car.state == "hydrant", 30.0), "cop car parks in the fire lane")
	at(14.6, -1.0, -PI / 2)
	check(spy(c), "Cops: photographed in the fire lane")
	check(G.cur(c).k == "call911", "Cops: call 911")
	at(19.6, -2.3, PI)
	press_e()
	check(G.S.lock != null and G.S.lock.kind == "scene", "911 call scene")
	check(until(func(): return G.cur(c).k == "precinct", 12.0) and G.S.lock == null, "911 hangs up on him: go to the precinct")
	at(36.2, -1.7, PI)
	var it = Interact.nearest_interact()
	check(it != null and it.label == "Report the cops to the police", "precinct: 'Report the cops to the police'")
	var score0: int = G.S.score
	press_e()
	check(G.S.mode == "cut" and G.S.fin != null, "finale cutscene")
	check(until(func(): return G.S.fin != null and G.S.fin.cuffed, 15.0), "2-Pack gets cuffed")
	check(until(func(): return G.S.fin.gary_phone, 3.0), "cut to Gary on the phone")
	check(until(func(): return G.S.fin.ricky, 10.0), "Ricky runs off with the wallet")
	check(until(func(): return G.S.mode == "over", 10.0), "Stage 2 clear")
	check(G.S.told.has("cops") and G.S.score == score0 + 1000, "the cops: +1000 (%d)" % G.S.score)


func t_strikes() -> void:
	G.start_game()
	quiet()
	for id in ["lawn", "timmy", "granny"]:
		Crimes.start_crime(id)
		G.C[id].left = 0.2
	step(0.5)
	check(G.S.strikes == 3, "three cases got away: 3 strikes")
	check(until(func(): return G.S.mode == "over", 3.0), "shift over")


func t_continue() -> void:
	check(G.saved_stage() == 2, "saved stage is 2")
	G.start_stage(2, false)
	check(G.S.mode == "play" and G.S.stage == 2 and G.S.score == 0, "Continue: Stage 2 starts fresh")
	step(1.0)
	check(G.P.x == -3.0 and G.P.z == -1.6, "stage 2 start spot")
