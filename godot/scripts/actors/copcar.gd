class_name CopCar
extends RefCounted
## The cop car (copcar.js + makeCar): leaving the station, driving to a crime, the bust,
## coming home. Faces +x at h = 0; drives forward only (turns around in place first).

var g: Node3D
var lr: Array[StandardMaterial3D] = []
var lb: Array[StandardMaterial3D] = []
var wheels: Array[Node3D] = []
var wheel_rest: Array[Basis] = []
var spin := 0.0
var x := 42.0          # [HUD]
var z := 2.7           # [HUD]
var h := PI
var state := "parked"
var queue: Array = []
var t := 0.0
var cur = null
var honk := 0.0
var stop_x := 0.0
var goal := 0.0
var on_arrive = null   # Callable
var lines: Array = []
var line_t := 0.0


static func make(root: Node3D) -> CopCar:
	var c := CopCar.new()
	c.g = Assets.model("cop_car")
	root.add_child(c.g)
	c.lr = Assets.own_materials(Assets.need(c.g, "LightRed", "cop_car"))
	c.lb = Assets.own_materials(Assets.need(c.g, "LightBlue", "cop_car"))
	for nm in ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]:
		var w := Assets.need(c.g, nm, "cop_car")
		c.wheels.append(w)
		c.wheel_rest.append(w.basis)
	return c


func update(dt: float) -> void:
	var W := G.W
	t += dt
	var cops := [W.dan, W.steve].filter(func(w): return not w.escort)
	if state == "leaving":                # the cops amble down the steps and get in
		if t > 2.2:
			for w in cops:
				w.visible = false
				w.rig.g.visible = false
			state = "pick"
			Audio.sfx("siren")
	if state == "pick":
		queue = queue.filter(func(id): return G.C[id].active)
		if queue.is_empty():
			state = "home"
		else:
			queue.sort_custom(func(a, b): return absf(G.C[a].target().x - x) < absf(G.C[b].target().x - x))
			cur = queue.pop_front()
			var tg: Vector3 = G.C[cur].target()
			stop_x = clampf(tg.x + 3.6, -27.0, 42.0)
			state = "drive"
	if state == "drive" or state == "home" or state == "tohydrant" or state == "goto":
		var gl: float = {"home": 42.0, "drive": stop_x, "tohydrant": 9.6, "goto": goal}[state]
		var want_h := PI if signf(gl - x) < 0 else 0.0
		if absf(gl - x) < 0.05:
			x = gl
			if state == "home":
				h = U.turn_toward(h, PI, 2.6 * dt)
				if absf(U.ang_diff(h, PI)) < 0.01:
					state = "parked"
					G.cops_home()
					Audio.sfx("door")
			elif state == "tohydrant":
				state = "hydrant"
				Audio.sfx("door")
			elif state == "goto":
				state = "idle"
				if on_arrive != null:
					var f: Callable = on_arrive
					on_arrive = null
					f.call()
			else:
				state = "arrive"
				t = 0.0
		elif absf(U.ang_diff(h, want_h)) > 0.01:
			h = U.turn_toward(h, want_h, 2.6 * dt)   # turn around in place before driving
		else:
			var fx := cos(h)
			var blocked := false
			for b in G.bodies:
				if not b.on.call():
					continue
				var p: Vector3 = b.pos.call()
				var ahead := (p.x - x) * fx
				if ahead > 0 and ahead < 3.1 + b.r and absf(p.z - z) < 1.0 + b.r:
					blocked = true
			if blocked:
				if honk <= 0:
					Audio.sfx("honk")
					honk = 2.5
			else:
				var sp := minf(9.0, 1.2 + absf(gl - x) * 1.4)
				var step := signf(gl - x) * minf(absf(gl - x), sp * dt)
				x += step
				spin += absf(step) / 0.36
	honk -= dt
	if state == "arrive":                 # the cops get out and walk over
		var c: Crime = G.C[cur]
		var tg := c.target()
		if t < 0.05:
			var sl := c.slots(tg)
			for k in cops.size():
				var w: Walker = cops[k]
				w.x = x - 0.6 + 1.2 * k
				w.z = z - 1.25
				w.yaw = PI
				w.visible = true
				w.rig.g.visible = true
				w.target = free_spot(sl[k][0], sl[k][1], w)
			Audio.sfx("door")
		var there := 0
		for w in cops:
			if Movement.step_walker(w, dt):
				w.yaw = U.turn_toward(w.yaw, atan2(tg.x - w.x, tg.z - w.z), 4.0 * dt)
				there += 1
		if (there == cops.size() and t > 1.0) or t > 9.0:
			state = "bust"
			t = 0.0
			lines = c.bust.duplicate()
			line_t = 0.0
	if state == "bust":
		var c: Crime = G.C[cur]
		var tg := c.target()
		for w in cops:
			w.yaw = U.turn_toward(w.yaw, atan2(tg.x - w.x, tg.z - w.z), 4.0 * dt)
		line_t -= dt
		if line_t <= 0:
			if lines.size():
				var l: Array = lines.pop_front()
				Hud.say(l[0], l[1], l[2])
				line_t = l[2]
			else:
				Crimes.busted(c)
				state = "return"
				t = 0.0
				for w in cops:
					w.target = [x + (-0.6 if w == W.dan else 0.6), z - 1.25]
	if state == "return":
		var back := 0
		for w in cops:
			if Movement.step_walker(w, dt):
				back += 1
		if back == cops.size() or t > 8.0:
			for w in cops:
				w.visible = false
				w.rig.g.visible = false
			state = "pick"
	g.position = Vector3(x, 0, z)
	g.rotation.y = h
	var flash := not (state in ["parked", "leaving", "hydrant", "idle"])
	var on := sin(G.clock * 14.0) > 0
	Assets.set_energy(lr, (4.0 if on else 0.2) if flash else 0.6)
	Assets.set_energy(lb, (0.2 if on else 4.0) if flash else 0.6)
	World.spin_wheels(wheels, wheel_rest, spin)


static func free_spot(px: float, pz: float, self_w: Walker) -> Array:
	for k in 10:
		var ox := px + (1.0 if k % 2 else -1.0) * ceili(k / 2.0) * 0.5
		var ok := true
		for b in G.bodies:
			if b == self_w.body or not b.on.call():
				continue
			var p: Vector3 = b.pos.call()
			if Vector2(p.x - ox, p.z - pz).length() < b.r + self_w.r + 0.1:
				ok = false
		for s in G.SOLIDS:
			if s.c == 1:
				if Vector2(s.x - ox, s.z - pz).length() < s.r + self_w.r:
					ok = false
			elif ox > s.x0 - self_w.r and ox < s.x1 + self_w.r and pz > s.z0 - self_w.r and pz < s.z1 + self_w.r:
				ok = false
		if ok:
			return [ox, pz]
	return [px, pz]
