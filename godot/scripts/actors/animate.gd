class_name Animate
## Animating everybody every frame (animate.js).

# Straight puppet arms (0.30H) that actually reach the face: [forward-raise, outward], negative outward = inward.
const HAND_TO_MOUTH := [-2.35, -0.66]   # donut bite, Gary's pipe
const PHONE_AT_EAR := [-3.0, -0.1]      # arm up beside the head (too long to bend to the ear)


static func animate_all(dt: float) -> void:
	var S := G.S
	var P := G.P
	var W := G.W
	var W_ := G.W_
	var clock := G.clock
	var HAM := World.HAMMOCK
	if not G.C.mama.active:
		W_.tl_t += dt
		var ph := fmod(W_.tl_t, 14.0)
		World.set_light("green" if ph < 6.0 else ("yellow" if ph < 7.5 else "red"))
	var beat := clock * 1.5   # 90 BPM
	# 2-Pack
	var tp := G.tp
	var gy := World.ground_y(P.x, P.z)
	tp.g.visible = not S.bino_on
	tp.place(P.x, P.z, P.yaw, gy)
	var lock = S.lock
	# Hand-to-face poses aim at the face: the JS used outward angles here (+0.42, +0.55...), which
	# with straight puppet arms leave the hand ~0.4 m from the face, invisible on the old primitives.
	if S.mode == "puzzle":
		tp.pose({"armR": PHONE_AT_EAR, "armL": [-0.6, 0.15], "nod": 0.05})
	elif S.bino_on:
		tp.pose({"armR": [-2.45, -0.42], "armL": [-2.45, -0.42]})
	elif lock != null and lock.kind == "rhythm":
		var hit: bool = lock.next > 0 and fmod(clock - lock.t0, lock.B) < 0.2
		tp.pose({"armR": [-2.6, 0.5], "armL": [-2.9 if hit else -1.6, 0.3], "lean": -0.05, "mouth": 0.9 if hit else 0.2})
	elif S.fin != null and S.fin.cuffed:
		tp.pose({"armR": [0.6, 0.2], "armL": [0.6, 0.2], "nod": 0.15, "mouth": 0.2})
	elif lock != null and lock.kind == "scene":
		tp.pose({"armR": PHONE_AT_EAR, "armL": [-0.6, 0.15], "nod": 0.05})
	elif lock != null and lock.kind == "record":
		tp.pose({"armR": [-1.55, -0.12], "armL": [-0.6, 0.15], "nod": 0.05})  # flip phone held out toward Daddy
	elif W.sq.held and not S.bino_on:
		tp.pose({"walk": 0.5 if P.moving else 0.0, "armL": [-1.5, 0.15], "armR": null if P.moving else [-0.4, 0.2]})
	elif lock != null and lock.kind == "ruler":
		tp.pose({"armR": [-0.9, 0.15], "armL": [-0.9, 0.15], "lean": 0.45, "nod": 0.4})
	elif P.moving:
		tp.pose({"walk": 0.95 if P.run else 0.55, "lean": 0.3 if P.run else 0.05,
			"armR": [-1.3 * sin(tp.phase), 0.1] if P.run else null, "armL": [1.3 * sin(tp.phase), 0.1] if P.run else null,
			"bob": 0.04 * absf(sin(tp.phase)) if P.run else 0.0})
	else:
		var b := absf(sin(PI * beat))
		var alt := int(floor(beat)) % 2
		tp.pose({"nod": 0.13 * b, "armR": [-0.5 - 0.7 * b if alt else -0.35, 0.3], "armL": [-0.25 if alt else -0.45 - 0.6 * b, 0.28], "bob": -0.02 * b, "mouth": 0.15})
	# cops
	for w in [W.dan, W.steve]:
		if not w.visible:
			continue
		var r: Puppet = w.rig
		r.place(w.x, w.z, w.yaw)
		var idle_donut: bool = G.car.state == "parked" or w.lost
		var bite := idle_donut and fmod(clock * 0.5 + (0.3 if r == G.steve else 0.0), 1.0) < 0.2
		if w.moving:
			r.pose({"walk": 0.55, "armR": [-0.3, 0.1]})
		else:
			r.pose({"armR": ((HAND_TO_MOUTH if bite else [-1.2, 0.25]) if idle_donut else [-0.4, 0.1]), "armL": [-0.15, 0.12], "mouth": 0.5 if bite else 0.0})
		r.donut.visible = G.car.state == "parked" or G.car.state == "leaving" or w.escort != null
	if G.car.state == "leaving":
		for w in [W.dan, W.steve]:
			if not w.escort:
				w.yaw = U.turn_toward(w.yaw, PI * 0.5, 3.0 * dt)
	# Ricky, Grandma, Timmy, the mailman, Timmy's mama
	if W.ricky.visible:
		var w: Walker = W.ricky
		G.ricky.place(w.x, w.z, w.yaw)
		G.ricky.pose({"walk": 0.45, "armR": [-0.25, 0.1], "armL": [0.2, 0.1]} if w.moving else {"armR": [-0.3, 0.1], "armL": [0.0, 0.1], "look": 0.2 * sin(clock)})
	if W.granny.visible:
		var w: Walker = W.granny
		G.granny.place(w.x, w.z, w.yaw)
		G.granny.pose({"walk": 0.22 if w.moving else 0.0, "lean": 0.3, "armR": [-1.05, 0.02], "armL": [-1.05, 0.02]})
	if G.timmy.g.visible:
		G.timmy.place(16.5, -3.75, 0.0)
		G.timmy.pose({"armR": [-1.2, 0.1], "armL": [-0.6 - 0.4 * absf(sin(clock * 1.5)), 0.1], "look": 0.2 * sin(clock)})
	if W.mail.visible:
		var w: Walker = W.mail
		var mc = G.C.mail
		var mm := G.mailman
		mm.place(w.x, w.z, w.yaw)
		var look := clampf(U.ang_diff(w.yaw, atan2(P.x - w.x, P.z - w.z)), -1.2, 1.2) if mc.sus > 0 else 0.0
		if w.moving:
			mm.pose({"walk": 0.5, "armR": [-0.3, 0.1], "armL": [0.2, 0.1], "look": look})
		elif mc.bending:
			var bnd := 0.5 + 0.5 * sin(clock * 3.0)
			mm.pose({"armR": [-1.4, -0.1 - 0.15 * bnd], "armL": [-1.4, 0.1 + 0.2 * bnd], "nod": 0.2, "look": 0.15 * sin(clock * 0.7)})
			mm.letter.rotation.y = 0.8 * bnd
		else:
			mm.pose({"armR": [-0.2, 0.1], "armL": [-0.2, 0.1], "look": look})
		mm.letter.visible = mc.bending
	if W.mama.g.visible:
		W.mama.place(17.1, -6.7, 0.0, 0.4)
		W.mama.pose({"armR": [-0.35, 0.55], "armL": [-0.35, 0.55], "lean": -0.05, "nod": -0.05})
	# stage 2 cast
	var dad: Puppet = W.dad
	if dad.on or dad.fall >= 0:
		var o := dad.outer
		var sn := Minigames.dad_snoring() and not dad.awake
		if dad.awake and dad.fall >= 0:
			dad.fall = minf(1.0, dad.fall + dt * 2.2)
			var u := dad.fall
			o.position.y = lerpf(1.02, 0.2, u * u)
			o.position.z = HAM[1] - 0.85 * u
			o.rotation.z = 0.6 * sin(u * PI)
		dad.pose({"armR": [-2.6, 0.6] if dad.awake else [-0.2, 0.4], "armL": [-2.6, 0.6] if dad.awake else [-0.4, 0.6], "mouth": 0.9 if sn else 0.3})
		for k in W.zz.size():
			var z: Label3D = W.zz[k]
			var u := fmod(clock * 0.4 + k / 3.0, 1.0)
			z.visible = not dad.awake and dad.on
			z.position = Vector3(HAM[0] - 1.1 + 0.4 * u, 1.4 + 1.3 * u, HAM[1] + 0.2)
			z.scale = Vector3.ONE * (0.4 + 0.9 * u)
		if sn and not dad.snd and G.C.daddy.active and Vector2(P.x - HAM[0], P.z - HAM[1]).length() < 16.0:
			Audio.sfx("snore")
		dad.snd = sn
	else:
		for z in W.zz:
			z.visible = false
	var q = W.sq
	if q.g.visible:
		if q.held:
			# held out front and sideways (the JS faced him into 2-Pack's chest, and the 0.88 m
			# squirrel went right through him)
			var hp := tp.hand_pos(1)
			var fwd := Vector3(sin(P.yaw), 0, cos(P.yaw))
			q.g.position = Vector3(hp.x, hp.y - 0.25, hp.z) + fwd * 0.18
			q.g.rotation = Vector3(0.3 * sin(clock * 20.0), P.yaw + PI / 2, 0.4 * sin(clock * 17.0))
		elif q.jailed:
			# faces along x: the cage is 1.0 m that way (the JS swayed it 0.4 rad facing +z,
			# which pokes the 0.88 m squirrel through the front and back bars)
			q.g.position = Vector3(World.JAIL[0], 0.62, World.JAIL[1])
			q.g.rotation = Vector3(0, PI / 2 + 0.12 * sin(clock * 1.3), 0)
		else:
			q.g.position = Vector3(q.x, World.ground_y(q.x, q.z) + (0.06 * absf(sin(clock * 22.0)) if q.moving else 0.0), q.z)
			q.g.rotation = Vector3(0, q.yaw, 0)
		# the tail pivots at its base: side to side (z) with a little lift (x)
		var fast: bool = q.moving or q.held
		var wag := (0.3 * sin(clock * 16.0)) if fast else (0.12 * sin(clock * 3.0))
		var lift := (0.1 * sin(clock * 8.0 + 1.0)) if fast else (0.05 * sin(clock * 1.5))
		q.tail.basis = q.tail_rest * Basis.from_euler(Vector3(lift, 0, wag))
	for L in W.liners:
		if not L.rig.g.visible:
			continue
		if L.told:
			L.yaw = U.turn_toward(L.yaw, atan2(W.baby.x - L.x, W.baby.z - L.z), 4.0 * dt)
		L.rig.place(L.x, L.z, L.yaw)
		L.rig.pose({"armR": [-0.9, 0.45], "armL": [-0.9, 0.45], "nod": -0.1} if L.told else {"armR": [-0.15, 0.1], "armL": [-0.15, 0.1], "look": 0.25 * sin(clock * 0.6 + L.x)})
	W.vendor.place(World.CART[0] + 0.95, World.CART[1], -PI / 2)
	W.vendor.pose({"armR": [-1.1 + 0.3 * sin(clock * 2.0), 0.1], "armL": [-0.9, 0.1]})
	if W.baby.visible:
		var b: Walker = W.baby
		var br: Puppet = W.baby_rig
		br.place(b.x, b.z, b.yaw, World.ground_y(b.x, b.z) + 0.12)
		br.g.rotation.x = 1.15
		var cr := sin(clock * 7.0)
		br.pose({"armR": [-1.2 + 0.4 * cr, 0.05], "armL": [-1.2 - 0.4 * cr, 0.05], "nod": -1.0})
		br.legs[0].rotation.x = -1.3 + 0.3 * cr
		br.legs[1].rotation.x = -1.3 - 0.3 * cr
	# Gary: smoking, waving at 2-Pack
	var gary := G.gary
	var near := Vector2(P.x + 2.8, P.z - 0.73).length() < 3.2
	var smoking := fmod(clock * 0.33, 1.0) < 0.4
	if S.fin != null and S.fin.gary_phone:
		gary.pose({"armR": PHONE_AT_EAR, "armL": [-0.3, 0.25], "look": 0.3})
	else:
		gary.pose({"armR": HAND_TO_MOUTH if smoking else [-0.5, 0.2],"armL": [-2.6 + 0.3 * sin(clock * 12.0), 0.4] if near else [-0.3, 0.25], "look": 0.4 if near else 0.0})
	Assets.set_energy(gary.ember, 4.0 + 2.0 * sin(clock * 20.0) if smoking else 0.6)
	if G.smoke:
		G.smoke.global_position = gary.mouth.global_position + Vector3(0, 0.1, 0)
	# talking decays
	for r in G.talkers:
		r.talk = maxf(0.0, r.talk - dt)
	# Gary says hi
	if S.mode == "play" and near and clock > S.gary_t:
		S.gary_t = clock + 40.0
		Hud.say("GARY", "Heyyyy, 2-Pack!", 1.8)
		G.later(1.9, func():
			if G.S.mode == "play":
				Hud.say("TWOPACK", "Don't you 'hey 2-Pack' me, Gary!", 2.2))
