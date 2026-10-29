class_name Player
## 2-Pack's controls, the binoculars (evidence), the camera (player.js).


## Push o (anything with x, z) out of every collider, like the JS resolve().
static func resolve(o, r: float) -> void:
	for s in G.SOLIDS:
		if s.c == 1:
			var dx: float = o.x - s.x
			var dz: float = o.z - s.z
			var d := sqrt(dx * dx + dz * dz)
			var rr: float = s.r + r
			if d < rr and d > 1e-4:
				o.x = s.x + dx / d * rr
				o.z = s.z + dz / d * rr
		else:
			var cx := clampf(o.x, s.x0, s.x1)
			var cz := clampf(o.z, s.z0, s.z1)
			var dx: float = o.x - cx
			var dz: float = o.z - cz
			var d := sqrt(dx * dx + dz * dz)
			if d < r:
				if d > 1e-4:
					o.x = cx + dx / d * r
					o.z = cz + dz / d * r
				else:
					var opts := [[s.x0 - r - o.x, 0.0], [s.x1 + r - o.x, 0.0], [0.0, s.z0 - r - o.z], [0.0, s.z1 + r - o.z]]
					opts.sort_custom(func(a, b): return absf(a[0] + a[1]) < absf(b[0] + b[1]))
					o.x += opts[0][0]
					o.z += opts[0][1]
	for b in G.bodies:
		if b == G.player_body or not b.on.call():
			continue
		var p: Vector3 = b.pos.call()
		var dx: float = o.x - p.x
		var dz: float = o.z - p.z
		var d := sqrt(dx * dx + dz * dz)
		var rr: float = b.r + r
		if d < rr and d > 1e-4:
			o.x = p.x + dx / d * rr
			o.z = p.z + dz / d * rr
	for cb in Movement.car_boxes():
		var dx: float = o.x - cb.x
		var dz: float = o.z - cb.z
		var hx := 2.2 + r
		var hz := 0.95 + r
		if absf(dx) < hx and absf(dz) < hz:
			if hx - absf(dx) < hz - absf(dz):
				o.x = cb.x + (signf(dx) if dx != 0.0 else 1.0) * hx
			else:
				o.z = cb.z + (signf(dz) if dz != 0.0 else 1.0) * hz
	o.x = clampf(o.x, World.BOUNDS.x0, World.BOUNDS.x1)
	o.z = clampf(o.z, World.BOUNDS.z0, World.BOUNDS.z1)


static func update_player(dt: float) -> void:
	var P := G.P
	P.moving = false
	P.run = false
	if G.S.bino_on or G.S.lock != null:
		return
	if G.key("turn_left"):
		G.cam_yaw += 1.9 * dt
	if G.key("turn_right"):
		G.cam_yaw -= 1.9 * dt
	var fw := (1.0 if G.key("move_forward") else 0.0) - (1.0 if G.key("move_back") else 0.0)
	var rt := (1.0 if G.key("move_right") else 0.0) - (1.0 if G.key("move_left") else 0.0)
	var fx := sin(G.cam_yaw)
	var fz := cos(G.cam_yaw)
	var dx := fx * fw - fz * rt
	var dz := fz * fw + fx * rt
	if dx != 0.0 or dz != 0.0:
		# turn toward where you're going; speed falls off until you face it (never sideways)
		var want := atan2(dx, dz)
		P.yaw = U.turn_toward(P.yaw, want, 11.0 * dt)
		var align := maxf(0.0, cos(U.ang_diff(P.yaw, want)))
		P.run = G.key("run")
		var sp := (6.4 if P.run else 3.3) * align * align * align
		var ox := P.x
		var oz := P.z
		P.x += sin(P.yaw) * sp * dt
		P.z += cos(P.yaw) * sp * dt
		resolve(P, 0.33)
		var moved := Vector2(P.x - ox, P.z - oz).length()
		P.moving = moved > 0.002
		G.tp.phase += moved * (2.6 if P.run else 3.2)


## First hit on an occluder along from->dir within far, or -1.
static func ray_hit(from: Vector3, dir: Vector3, far: float) -> float:
	if far <= 0.0 or G.world_root == null:
		return -1.0
	var space := G.world_root.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * far, World.OCC_LAYER)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return -1.0
	return from.distance_to(hit.position)


static func update_bino(dt: float) -> void:
	var S := G.S
	var P := G.P
	var want: bool = G.key("binoculars") and S.mode == "play" and S.lock == null
	if want and not S.bino_on:
		S.bino_on = true
		G.bino_yaw = G.cam_yaw
		G.bino_pitch = 0.02
		G.bino_fov = 22.0
	if not want and S.bino_on:
		S.bino_on = false
		G.cam_yaw = G.bino_yaw
	G.tp.bino.visible = S.bino_on
	if not S.bino_on:
		S.ev = 0.0
		S.ev_id = null
		Hud.bino(false)
		return
	var zk := G.bino_fov / 16.0
	if G.key("move_left") or G.key("turn_left"):
		G.bino_yaw += 0.9 * dt * zk
	if G.key("move_right") or G.key("turn_right"):
		G.bino_yaw -= 0.9 * dt * zk
	if G.key("move_forward"):
		G.bino_pitch += 0.6 * dt * zk
	if G.key("move_back"):
		G.bino_pitch -= 0.6 * dt * zk
	G.bino_pitch = clampf(G.bino_pitch, -0.5, 0.45)
	P.yaw = U.turn_toward(P.yaw, G.bino_yaw, 8.0 * dt)
	# what's in the circle?
	var eye := Vector3(P.x, World.ground_y(P.x, P.z) + 1.68, P.z)
	var dir := Vector3(sin(G.bino_yaw) * cos(G.bino_pitch), sin(G.bino_pitch), cos(G.bino_yaw) * cos(G.bino_pitch))
	var best = null
	var best_a := 0.065 * zk + 0.02
	var best_d := 0.0
	var label := ""
	for c in G.C.values():
		if not c.active:
			continue
		var t: Vector3 = c.target()
		var v := t - eye
		var d := v.length()
		var a := v.normalized().angle_to(dir)
		if a < best_a:
			if ray_hit(eye, v.normalized(), d - 0.7) < 0.0:
				best = c
				best_a = a
				best_d = d
	var prog := 0.0
	if best:
		var st: Dictionary = G.cur(best)
		var nm := G.short_name(best).to_upper()
		var spyable: bool = (st.k == "spy" or st.k == "tail") and not best.dispatched and not best.handling and best.spy_ok()
		if not spyable:
			S.ev = 0.0
			var why := ""
			if best.dispatched:
				why = "COPS ON THE WAY"
			elif best.id == "mama" and st.k == "spy":
				why = "WAIT FOR THE RED LIGHT"
			elif best.id == "cops" and st.k == "spy":
				why = "WAIT TILL THEY PARK"
			elif st.k == "tail":
				why = "ACTING NORMAL..." if best.sus > 0 else ("GOT THIS ONE. NEXT STOP." if best.bending else "WAIT TILL HE BENDS ONE")
			else:
				why = "NEXT: " + st.m
			label = nm + " · " + why
		elif best_d < 4.0:
			label = "TOO CLOSE. BACK UP."
			S.ev = 0.0
		else:
			if S.ev_id != best.id:
				S.ev_id = best.id
				S.ev = 0.0
			S.ev += dt / 1.3
			label = "%s · %d FT" % [nm, roundi(best_d * 3.3)]
			prog = S.ev
			if S.ev >= 1.0:
				S.ev = 0.0
				Audio.sfx("shutter")
				if st.k == "tail":
					best.photos += 1
					best.last_photo = best.stop
					Hud.pop(best.target(), "PHOTO %d/2" % best.photos)
					if best.photos >= 2:
						Hud.say(best.line[0], best.line[1], 2.6)
						Crimes.adv(best)
				else:
					if not best.on_spy():
						Hud.say(best.line[0], best.line[1], 2.8)
						Hud.pop(best.target(), "EVIDENCE")
					Crimes.adv(best)
	else:
		S.ev = 0.0
		S.ev_id = null
		label = "NOTHING TO REPORT. YET."
	G.bino_label = label
	Hud.bino(true, label, clampf(prog, 0.0, 1.0))


static func _look(cam: Camera3D, from: Vector3, at: Vector3) -> void:
	if from.is_equal_approx(at):
		return
	var up := Vector3.UP
	if absf((at - from).normalized().dot(up)) > 0.999:
		up = Vector3.BACK
	cam.look_at_from_position(from, at, up)


static func update_camera(dt: float, snap := false) -> void:
	var cam := G.cam
	if cam == null:
		return
	var S := G.S
	var P := G.P
	G.set_dof(S.mode != "title" and not S.bino_on and G.cam_override == null)
	if G.cam_override != null:            # screenshot tool / debug: a fixed camera
		cam.fov = G.cam_override.f
		_look(cam, G.cam_override.p, G.cam_override.l)
		return
	if S.mode == "title":
		var a := G.clock * 0.08
		cam.fov = 40.0
		_look(cam, Vector3(6 + cos(a) * 16, 6.5, 6 + sin(a) * 9), Vector3(4, 1.2, -2))
		return
	if S.mode == "cut" and S.fin != null:
		var c: Dictionary = S.fin.cam
		var k := 1.0 if (S.fin.snap or snap) else minf(1.0, dt * 2.5)
		S.fin.snap = false
		G.cam_pos = G.cam_pos.lerp(c.p, k)
		G.cam_look = G.cam_look.lerp(c.l, k)
		cam.fov = lerpf(cam.fov, c.f, k)
		_look(cam, G.cam_pos, G.cam_look)
		return
	if S.mode == "puzzle" and S.pz != null:
		var t: Vector3 = S.pz.focus.target()
		var want := Vector3(t.x - 2.6, 2.5, maxf(t.z + 6.5, 4.0))
		G.cam_pos = G.cam_pos.lerp(want, 1.0 if snap else minf(1.0, dt * 3.0))
		G.cam_look = G.cam_look.lerp(t, 1.0 if snap else minf(1.0, dt * 4.0))
		cam.fov = lerpf(cam.fov, 38.0, minf(1.0, dt * 3.0))
		_look(cam, G.cam_pos, G.cam_look)
		return
	if S.bino_on:
		var gy := World.ground_y(P.x, P.z)
		var pos := Vector3(P.x + sin(G.bino_yaw) * 0.25, gy + 1.68, P.z + cos(G.bino_yaw) * 0.25)
		var fwd := Vector3(sin(G.bino_yaw) * cos(G.bino_pitch), sin(G.bino_pitch), cos(G.bino_yaw) * cos(G.bino_pitch))
		_look(cam, pos, pos + fwd)
		cam.fov = G.bino_fov
		G.cam_pos = pos
		return
	var gy := World.ground_y(P.x, P.z)
	var head := Vector3(P.x, gy + 1.5, P.z)
	var dist := 5.6
	var want := Vector3(P.x - sin(G.cam_yaw) * cos(G.cam_pitch) * dist, gy + 1.5 + sin(G.cam_pitch) * dist, P.z - cos(G.cam_yaw) * cos(G.cam_pitch) * dist)
	var v := want - head
	var L := v.length()
	var hit := ray_hit(head, v / L, L)
	if hit >= 0.0:
		want = head + v / L * maxf(0.8, hit - 0.35)
	G.cam_pos = G.cam_pos.lerp(want, 1.0 if snap else minf(1.0, dt * 9.0))
	G.cam_look = G.cam_look.lerp(head, 1.0 if snap else minf(1.0, dt * 12.0))
	cam.fov = lerpf(cam.fov, 55.0, minf(1.0, dt * 6.0))
	_look(cam, G.cam_pos, G.cam_look)
