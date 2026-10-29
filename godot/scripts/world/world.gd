class_name World
## The block (world.js): ground heights, the 2D colliders (SOLIDS), the camera occluders,
## placing the models, and the Stage 2 props (traffic light, Mama's car, the hammock,
## the county jail, the ice-cream line).
## World units: x runs east along the street, y up, houses at negative z, the street at z 0..14.

const BOUNDS := {"x0": -32.0, "x1": 45.0, "z0": -6.0, "z1": 18.4}
const JAIL := [-9.0, -4.7]
const HAMMOCK := [-17.5, -5.0]
const CART := [24.6, -2.2]
const LINE_X := [23.5, 22.6, 21.7, 20.8]
const LANE2 := 10.5
const PHONES := [[-10.5, -3.0], [2.8, -3.0], [19.6, -3.0]]
const HOUSES := [-30, -24, -18, -12, -6, 6, 12, 17]
## Physics layer 20 holds the occluders (houses, shops, the precinct) for camera and binocular rays.
const OCC_LAYER := 1 << 19


class Sedan:
	var g: Node3D
	var plate: Label3D
	var wheels: Array[Node3D] = []
	var wheel_rest: Array[Basis] = []
	var spin := 0.0
	var x := -58.0
	var z := 10.5
	var honk := 0.0
	var stopped := false


class SquirrelState:
	var g: Node3D
	var tail: Node3D
	var tail_rest := Basis()
	var x := 0.0
	var z := 0.0
	var yaw := 0.0
	var r := 0.22
	var held := false
	var jailed := false
	var tired := 0.0
	var run := 0.0
	var zig := 0.0
	var zig_t := 0.0
	var w_t := 0.0
	var w_yaw := 0.0
	var moving := false
	var body: Body


class Liner:
	var rig: Puppet
	var x := 0.0
	var z := 0.0
	var yaw := PI / 2
	var told := false
	var body: Body


static func ground_y(_x: float, z: float) -> float:
	if z < 0.0 and z > -3.2:
		return 0.16
	if z <= -3.2:
		return 0.12
	if z >= 13.0:
		return 0.16
	return 0.0


static func solid_c(x: float, z: float, r: float) -> void:
	G.SOLIDS.append(Solid.circle(x, z, r))


static func solid_b(x0: float, x1: float, z0: float, z1: float) -> void:
	G.SOLIDS.append(Solid.rect(x0, x1, z0, z1))


## A box the camera and the binoculars can't see through (the JS OCCLUDERS meshes).
static func occluder(root: Node3D, center: Vector3, size: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.name = "Occluder"
	sb.collision_layer = OCC_LAYER
	sb.collision_mask = 0
	sb.position = center
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	root.add_child(sb)
	G.OCCLUDERS.append(AABB(center - size * 0.5, size))


static func place(root: Node3D, id: String, x: float, y: float, z: float) -> Node3D:
	var n := Assets.model(id)
	n.position = Vector3(x, y, z)
	root.add_child(n)
	return n


# ===================================================================== the block
static func build_block(root: Node3D) -> void:
	for id in ["street", "houses", "shops", "furniture", "gary_spot"]:
		root.add_child(Assets.model(id))
	for k in HOUSES.size():
		var x: float = HOUSES[k]
		var w := 5.0 if x == 17 else 5.6
		var graf := x == -6 or x == 6 or x == 12
		var h := 7.6 if graf else 5.6 + float((k * 37) % 25) / 10.0
		occluder(root, Vector3(x, h / 2, -10.5), Vector3(w, h, 7))
	occluder(root, Vector3(0, 3.5, -10.5), Vector3(5.6, 7, 7))
	for s in [[22.5, 6.0], [28.0, 5.0], [43.5, 6.0]]:
		occluder(root, Vector3(s[0], 3.5, -10.5), Vector3(s[1], 7, 7))
	occluder(root, Vector3(36, 4, -11), Vector3(9, 8, 8))
	# colliders, in the JS order
	solid_b(33.5, 38.5, -5.7, -3.3)                 # the precinct steps
	for x in [-24, -12, 4, 14, 30, 40]:
		solid_c(x, -0.2, 0.12)                       # street lamps
	for x in [-8.5, 9.6, 25]:
		solid_c(x, -0.32, 0.22)                      # hydrants
	for x in [-15.8, 4.8, 26.4]:
		solid_c(x, -3.5, 0.34)                       # trash cans
	G.W_.phones = []
	for p in PHONES:
		var g := place(root, "payphone", p[0], 0.12, p[1])
		solid_c(p[0], p[1], 0.36)
		G.W_.phones.append({"x": p[0], "z": p[1], "g": g})
	var st := place(root, "lemonade_stand", 16.5, 0.12, -3.05)
	G.W_.stand_sign = Assets.need(st, "SignOpen", "lemonade_stand")
	G.W_.stand_closed = Assets.need(st, "SignClosed", "lemonade_stand")
	G.W_.stand_sign.visible = false           # the stand starts CLOSED
	G.W_.stand_closed.visible = true
	solid_b(15.75, 17.25, -3.4, -2.7)
	var lawn := place(root, "lawn", 11.5, 0.12, -5.0)
	G.W_.lawn_brown = Assets.need(lawn, "Brown", "lawn")
	G.W_.lawn_green = Assets.need(lawn, "Green", "lawn")
	solid_c(9.5, -3.5, 0.1)                          # THE JOHNSONS sign
	for x in [-27, -21.2, -14.2]:
		solid_c(x, -3.0, 0.2)                        # house mailboxes
	solid_c(5.9, -3.0, 0.42)                         # the blue mail drop
	solid_c(-5.9, 1.15, 0.6)                         # Gary's cart
	solid_c(-4.55, 0.6, 0.12)                        # WELCOME HOME
	solid_c(-1.25, 0.35, 0.2)                        # GARY's mailbox
	solid_c(-7.2, 0.4, 0.4)                          # the grill
	solid_b(-3.85, -1.85, 0.48, 0.98)                # Gary himself


## Mrs. Johnson's lawn: brown (the evidence) or green (she watered it).
static func set_lawn(green: bool) -> void:
	G.W_.lawn_brown.visible = not green
	G.W_.lawn_green.visible = green


# ===================================================================== stage 2: the west end and the crosswalk
static func build_stage2(root: Node3D) -> void:
	# the traffic light at the crosswalk (it faces eastbound traffic in the far lane)
	var tl := place(root, "traffic_light", -0.5, 0, 13.6)
	G.W_.tl = {
		"r": Assets.own_materials(Assets.need(tl, "LampRed", "traffic_light")),
		"y": Assets.own_materials(Assets.need(tl, "LampYellow", "traffic_light")),
		"g": Assets.own_materials(Assets.need(tl, "LampGreen", "traffic_light")),
	}
	G.W_.tl_state = ""
	G.W_.tl_t = 0.0
	set_light("green")
	solid_c(-0.5, 13.6, 0.14)
	G.W.mama_car = make_sedan(root)
	G.W.mama_car.g.visible = false
	# Daddy's hammock
	place(root, "hammock", HAMMOCK[0], 0, HAMMOCK[1])
	for sx in [-1, 1]:
		solid_c(HAMMOCK[0] + sx * 1.4, HAMMOCK[1], 0.14)
	solid_b(HAMMOCK[0] - 1.4, HAMMOCK[0] + 1.4, HAMMOCK[1] - 0.45, HAMMOCK[1] + 0.45)
	var d_outer := Prim.group(root, 0, 0, 0, "DadOuter")
	d_outer.rotation_order = EULER_ORDER_XYZ
	var d_inner := Prim.group(d_outer, 0, 0, 0, "DadInner")
	d_inner.rotation.x = -PI / 2
	var dad := Cast.person("dad", d_inner)
	dad.outer = d_outer
	dad.inner = d_inner
	G.W.dad = dad
	G.W.zz = []
	for k in 3:
		var z := Prim.label("Z", 0.32, 0.32, "#f4f0e6")
		z.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		z.visible = false
		root.add_child(z)
		G.W.zz.append(z)
	# the squirrel and his tiny county jail
	var q := SquirrelState.new()
	q.g = Assets.model("squirrel")
	q.g.rotation_order = EULER_ORDER_XYZ
	root.add_child(q.g)
	q.tail = Assets.need(q.g, "Tail", "squirrel")
	q.tail_rest = q.tail.basis
	q.body = Movement.add_body(0.22, func(): return Vector3(q.x, 0, q.z), func(): return q.g.visible and not q.held and not q.jailed)
	q.g.visible = false
	G.W.sq = q
	place(root, "county_jail", JAIL[0], 0.12, JAIL[1])
	solid_c(JAIL[0], JAIL[1], 0.62)
	# the ice-cream cart, the vendor, the line
	place(root, "ice_cream_cart", CART[0], 0.16, CART[1])
	solid_c(CART[0], CART[1], 0.72)
	G.W.vendor = Cast.person("vendor", root)
	Movement.add_body(0.3, func(): return Vector3(CART[0] + 0.95, 0, CART[1]), func(): return true)
	G.W.liners = []
	for k in 4:
		var L := Liner.new()
		L.rig = Cast.person("liner_%d" % (k + 1), root)
		L.rig.g.visible = false
		L.x = LINE_X[k]
		L.z = CART[1]
		L.yaw = PI / 2
		L.body = Movement.add_body(0.32, func(): return Vector3(L.x, 0, L.z), func(): return L.rig.g.visible)
		G.W.liners.append(L)
	var baby_rig := Cast.person("baby", root)
	baby_rig.g.visible = false
	G.W.baby_rig = baby_rig
	var baby := Walker.make(baby_rig, 0.2, 0.11)
	baby.body = Movement.add_body(0.2, func(): return Vector3(baby.x, 0, baby.z), func(): return baby.visible)
	G.W.baby = baby
	reset_dad()


static func make_sedan(root: Node3D) -> Sedan:
	var s := Sedan.new()
	s.g = Assets.model("sedan")
	root.add_child(s.g)
	var pl := Assets.need(s.g, "Plate", "sedan")
	var lbl := Prim.label("0 0 0 0", 0.55, 0.22, "#14203f", "mono")
	s.g.add_child(lbl)
	var p := s.g.global_transform.affine_inverse() * pl.global_position
	lbl.position = p + Vector3(-0.012, 0, 0)
	lbl.rotation.y = -PI / 2
	s.plate = lbl
	for nm in ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]:
		var w := Assets.need(s.g, nm, "sedan")
		s.wheels.append(w)
		s.wheel_rest.append(w.basis)
	return s


## The plate number, digits spaced like the JS ("1 2 3 4").
static func set_plate(t: String) -> void:
	var s := ""
	for i in t.length():
		s += (" " if i else "") + t[i]
	G.W.mama_car.plate.text = s


static func set_light(st: String) -> void:
	if G.W_.tl_state == st:
		return
	G.W_.tl_state = st
	Assets.set_energy(G.W_.tl.r, 3.0 if st == "red" else 0.08)
	Assets.set_energy(G.W_.tl.y, 3.0 if st == "yellow" else 0.08)
	Assets.set_energy(G.W_.tl.g, 3.0 if st == "green" else 0.08)


static func reset_dad() -> void:
	var d: Puppet = G.W.dad
	d.outer.position = Vector3(HAMMOCK[0] + 0.9, 1.02, HAMMOCK[1])
	d.outer.rotation = Vector3(0, PI / 2, 0)
	d.awake = false
	d.fall = -1.0


## Spin wheel pivots (local z is the axle on cars that face +x).
static func spin_wheels(wheels: Array[Node3D], rest: Array[Basis], angle: float) -> void:
	for i in wheels.size():
		wheels[i].basis = rest[i] * Basis(Vector3(0, 0, 1), -angle)
