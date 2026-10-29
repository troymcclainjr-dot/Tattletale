class_name Movement
## Collision bodies and NPC walking (movement.js). Nobody walks sideways; nobody passes
## through anybody. Collision is 2D (x/z) circles and boxes, exactly like the JS.


static func add_body(r: float, pos: Callable, on: Callable) -> Body:
	var b := Body.make(r, pos, on)
	G.bodies.append(b)
	return b


static func car_boxes() -> Array:
	var a := []
	if G.car and G.car.state != "hidden":
		a.append(G.car)
	if G.W.has("mama_car") and G.W.mama_car.g.visible:
		a.append(G.W.mama_car)
	return a


## What a mover would bump into stepping to (nx, nz) while heading (fx, fz), or null.
static func blocked_ahead(self_b, nx: float, nz: float, fx: float, fz: float, r: float):
	for b in G.bodies:
		if b == self_b or not b.on.call():
			continue
		var p: Vector3 = b.pos.call()
		var dx := p.x - nx
		var dz := p.z - nz
		var rr: float = r + b.r
		if dx * dx + dz * dz < rr * rr and (dx * fx + dz * fz) > -0.05:
			return b
	for cb in car_boxes():
		if self_b == G.car_body and cb == G.car:
			continue
		var dx: float = nx - cb.x
		var dz: float = nz - cb.z
		if absf(dx) < 2.2 + r and absf(dz) < 0.95 + r and (-dx * fx - dz * fz) > -0.3:
			return G.car_body
	for s in G.SOLIDS:
		if s.c == 1:
			var dx: float = s.x - nx
			var dz: float = s.z - nz
			if dx * dx + dz * dz < (s.r + r) * (s.r + r) and (dx * fx + dz * fz) > 0:
				return s
		elif nx > s.x0 - r and nx < s.x1 + r and nz > s.z0 - r and nz < s.z1 + r:
			var cx := clampf(nx, s.x0, s.x1) - nx
			var cz := clampf(nz, s.z0, s.z1) - nz
			if cx * fx + cz * fz >= 0:
				return s
	return null


## One step toward w.target: turn in place first, then walk forward; wait or detour around
## round things in the way. Returns true when there (or with nowhere to go).
static func step_walker(w: Walker, dt: float) -> bool:
	w.moving = false
	var tg = w.detour if w.detour != null else w.target
	if tg == null:
		return true
	var dx: float = tg[0] - w.x
	var dz: float = tg[1] - w.z
	var d := sqrt(dx * dx + dz * dz)
	if d < 0.06:
		if w.detour != null:
			w.detour = null
			return false
		w.target = null
		return true
	var want := atan2(dx, dz)
	w.yaw = U.turn_toward(w.yaw, want, 5.0 * dt)
	if absf(U.ang_diff(w.yaw, want)) > 0.3:
		return false
	var fx := sin(w.yaw)
	var fz := cos(w.yaw)
	var st := minf(d, w.speed * dt)
	var blk = blocked_ahead(w.body, w.x + fx * st, w.z + fz * st, fx, fz, w.r)
	if blk:
		w.waiting += dt
		if blk is Solid and blk.c == 1 and w.detour == null and w.waiting > 0.4:
			var px := -fz
			var pz := fx
			var side := -1.0 if ((blk.x - w.x) * px + (blk.z - w.z) * pz) > 0 else 1.0
			var off: float = blk.r + w.r + 0.3
			w.detour = [blk.x + px * side * off + fx * 0.35, blk.z + pz * side * off + fz * 0.35]
			w.waiting = 0.0
		elif w.detour != null and w.waiting > 1.5:
			w.detour = null
			w.waiting = 0.0
		return false
	w.waiting = 0.0
	w.x += fx * st
	w.z += fz * st
	w.moving = true
	w.rig.phase += st * (4.2 / w.rig.H)
	return false
