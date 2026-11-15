extends RefCounted
## The corner store's cellar (the strip worker's): built by plans/store.gd, not
## a place of its own. Steel doors in the pavement in front of the shop window
## (E on them: down), and under the shop two bands on a level of their own (-1),
## drawn CU to the right of the store on the plan:
##
##   the vault under the pavement: old brick, a bare bulb, the wooden stair up
##   to the doors (E at its foot: up to the street), the doors over its top
##   seen from under, daylight in the crack where the leaves meet;
##   the cellar under the shop, through an arch in the foundation wall:
##   whitewashed stone, a concrete floor gone damp in the middle, old stock on
##   shelves, cases of soda, boxes, a chest freezer long dead, the water heater
##   and its pipes, a bench of tools, a hand truck, a mop in its bucket.
##
## Numbers are the store's plan (see store.gd: u from its left wall, v from its
## back wall, its street face at v = 11), CU added to u down here. Invented
## here (placeholders): the rooms' names VAULT and CELLAR and the labels DOWN
## TO THE CELLAR (on the pavement) and UP TO THE STREET.

const Props := preload("res://scripts/props.gd")
const In := preload("res://scripts/props_in.gd")
const Outdoor := preload("res://scripts/outdoor.gd")
const Backs := preload("res://scripts/props_backs.gd")
const Service := preload("res://scripts/props_service.gd")

const CU := 40.0                            # the cellar is drawn this far to the right on the plan
const DOORS := [4.6, 6.0, 11.15, 12.35]     # the doors in the pavement: u0, u1, v0, v1
const LOW := 2.5                            # the cellar's walls; the pavement over the vault:
const PAVE := 2.6
const ARCH := [7.0, 8.0]                    # the arch from the vault into the cellar (u)


## The doors in the pavement, shut: a frame of angle round two leaves of
## diamond plate (walked over), their hinges along the outer edges, a hasp
## where they meet. E on them goes down to the foot of the stair.
static func pavement_doors(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	var plate := Kit.tex("in_diamond", 0.5, Color(0.42, 0.44, 0.46), false, Color(0.62, 0.64, 0.68))
	var u0: float = DOORS[0]
	var u1: float = DOORS[1]
	var v0: float = DOORS[2]
	var v1: float = DOORS[3]
	var mid := (u0 + u1) * 0.5
	var vm := (v0 + v1) * 0.5
	Service.gb(p, n, u0 - 0.05, u1 + 0.05, v0 - 0.05, v1 + 0.05, 0.0, 0.012, Color(0.3, 0.31, 0.33))
	for s: Array in [[u0, mid - 0.008], [mid + 0.008, u1]]:
		Service.gb(p, n, s[0], s[1], v0, v1, 0.012, 0.03, plate)
	for u: float in [u0 + 0.05, u1 - 0.05]:
		for v: float in [v0 + 0.22, v1 - 0.22]:
			Service.gb(p, n, u - 0.04, u + 0.04, v - 0.08, v + 0.08, 0.03, 0.045, Color(0.26, 0.27, 0.29))
	Service.gb(p, n, mid - 0.09, mid + 0.09, vm - 0.03, vm + 0.03, 0.03, 0.05, Props.STEEL)
	p.portal(st, "DOWN TO THE CELLAR", mid, vm, CU + 1.8, 11.9)


## The vault and the cellar: their rooms, walls and things.
static func build(p: Node3D) -> void:
	var vault: int = p.band(-1)
	var cellar: int = p.band(-1)
	var concrete := Outdoor.tex("out_concrete", 2.56, Color(0.5, 0.5, 0.48), Color(0.74, 0.72, 0.68))
	var stone := Kit.tex("in_ashlar", 1.2, Color(0.6, 0.58, 0.52), true, Color(0.78, 0.76, 0.7))       # whitewash gone grey
	var brick := Kit.tex("brick", 1.5, Color(0.38, 0.26, 0.22), true, Color(0.66, 0.56, 0.52))
	var bulb := Color(1.0, 0.82, 0.55)
	p.room("VAULT", vault, CU, 11.0, CU + 9.0, 13.3, concrete, {"light": bulb, "energy": 0.2, "cam_y": 2.3, "look_y": 0.9})
	p.room("CELLAR", cellar, CU, 0.0, CU + 9.0, 11.0, concrete, {"light": bulb, "energy": 0.2})
	p.cross(vault, 13.3, CU, CU + 9.0, brick, [], {"h": PAVE})
	p.side(vault, CU, 11.0, 13.3, brick, [], {"h": PAVE})
	p.side(vault, CU + 9.0, 11.0, 13.3, brick, [], {"h": PAVE})
	p.cross(cellar, 11.0, CU, CU + 9.0, stone, [{"a": CU + ARCH[0], "b": CU + ARCH[1], "kind": "arch", "head": 2.0, "frame": Color(0.44, 0.4, 0.36)}], {"h": PAVE})
	p.side(cellar, CU, 0.0, 11.0, stone, [], {"h": LOW})
	p.side(cellar, CU + 9.0, 0.0, 11.0, stone, [], {"h": LOW})
	p.cross(cellar, 0.0, CU, CU + 9.0, stone, [], {"back": true, "h": LOW})
	_vault(p, vault)
	_cellar(p, cellar)


## The vault: the stair up (its foot on the left, by where he comes down), the
## doors over its top from under, the bulb, old boxes in the corner.
static func _vault(p: Node3D, b: int) -> void:
	var n: Node3D = p.node_of(b)
	Props.stairs(p, b, CU + 4.2, 11.75, 270.0, 1.1, 3.6, PAVE, Props.WOOD, PAVE + 0.3)
	p.portal(b, "UP TO THE STREET", CU + 2.0, 11.75, 4.6, 12.65)
	var u0: float = CU + DOORS[0]
	var u1: float = CU + DOORS[1]
	var v0: float = DOORS[2]
	var v1: float = DOORS[3]
	var mid := (u0 + u1) * 0.5
	var frame := Color(0.3, 0.31, 0.33)
	for s: Array in [[u0 - 0.08, u1 + 0.08, v0 - 0.08, v0], [u0 - 0.08, u1 + 0.08, v1, v1 + 0.08], [u0 - 0.08, u0, v0, v1], [u1, u1 + 0.08, v0, v1]]:
		Service.gb(p, n, s[0], s[1], s[2], s[3], PAVE - 0.1, PAVE, frame)
	for s: Array in [[u0, mid - 0.012], [mid + 0.012, u1]]:
		Service.gb(p, n, s[0], s[1], v0, v1, PAVE - 0.03, PAVE - 0.01, Color(0.36, 0.37, 0.39))
	Service.gb(p, n, mid - 0.012, mid + 0.012, v0, v1, PAVE - 0.012, PAVE - 0.004, Kit.flat(Color(1.0, 0.95, 0.82), 1.6))       # daylight in the crack
	In.pendant(p, b, CU + 7.4, 12.3, 2.05, Props.DARK, "bulb", In.WARM, 0.35, PAVE)
	Props.boxes(p, b, CU + 0.8, 11.5, 3)
	var broom := Kit.group(n, p.pt(CU + 8.75, 11.2), Vector3(0, 0, 8))
	Kit.cyl(broom, 0.016, 1.3, Vector3(0, 0.75, 0), Props.WOOD, Vector3.ZERO, 6)
	Kit.box(broom, Vector3(0.3, 0.1, 0.06), Vector3(0, 0.08, 0), Color(0.5, 0.42, 0.26))


## The cellar: shelves of old stock along the back, the water heater and its
## pipes; cases and boxes and the dead chest freezer down the left; a bench of
## tools and more shelves down the right; a hand truck, the mop, the damp.
static func _cellar(p: Node3D, b: int) -> void:
	var n: Node3D = p.node_of(b)
	# The damp up the foot of the walls.
	var damp := Color(0.4, 0.38, 0.34)
	Service.gb(p, n, CU + 0.075, CU + 0.083, 0.075, 10.925, 0.0, 0.42, damp)
	Service.gb(p, n, CU + 8.917, CU + 8.925, 0.075, 10.925, 0.0, 0.42, damp)
	Service.gb(p, n, CU + 0.083, CU + 8.917, 0.075, 0.083, 0.0, 0.42, damp)
	Props.shelves(p, b, CU + 1.6, 0.31, 0.0, 2.4, "cans")
	Props.shelves(p, b, CU + 4.3, 0.31, 0.0, 2.0, "bottles")
	# The water heater, its flue up the wall, its pipes along the top of it.
	var heater: Node3D = p.prop(b, CU + 7.6, 0.5, 0.0, 0.62, 0.62)
	Kit.cyl(heater, 0.29, 1.45, Vector3(0, 0.78, 0), Color(0.86, 0.85, 0.8), Vector3.ZERO, 16)
	Kit.cyl(heater, 0.3, 0.06, Vector3(0, 0.03, 0), Color(0.4, 0.4, 0.42), Vector3.ZERO, 16)
	Kit.cyl(heater, 0.29, 0.12, Vector3(0, 1.56, 0), Color(0.62, 0.62, 0.6), Vector3.ZERO, 16, 0.12)
	Kit.cyl(heater, 0.06, 0.88, Vector3(0, 2.06, 0), Props.STEEL, Vector3.ZERO, 8)
	Kit.box(heater, Vector3(0.16, 0.12, 0.05), Vector3(0, 0.36, 0.3), Color(0.3, 0.3, 0.32))
	var copper := Color(0.72, 0.45, 0.3)
	for pipe: Array in [[0.12, 2.25, copper], [0.2, 2.12, Props.STEEL]]:
		Kit.tube(n, p.pt(CU + 0.2, pipe[0], pipe[1]), p.pt(CU + 8.8, pipe[0], pipe[1]), 0.026, pipe[2])
	Kit.tube(n, p.pt(CU + 7.3, 0.12, 2.25), p.pt(CU + 7.3, 0.12, 1.2), 0.026, copper)
	Kit.tube(n, p.pt(CU + 7.3, 0.12, 1.2), p.pt(CU + 7.38, 0.36, 1.2), 0.026, copper)
	# Down the left.
	Props.case_stack(p, b, CU + 0.45, 2.6, 90.0, 3, 4, Color(0.2, 0.42, 0.25))
	Props.case_stack(p, b, CU + 0.45, 4.2, 90.0, 2, 2, Color(0.75, 0.16, 0.14))
	Props.chest_freezer(p, b, CU + 0.5, 6.4, 90.0, 1.3, "", Color(0.5, 0.5, 0.52))
	Props.boxes(p, b, CU + 0.62, 8.6, 4)
	# Down the right: the bench, its tools on the wall over it, more shelves.
	Props.table(p, b, CU + 8.55, 3.4, 270.0, 1.6, 0.7, Color(0.5, 0.4, 0.28), 0.9)
	var vice := Kit.group(n, p.pt(CU + 8.35, 2.85, 0.9))
	Kit.box(vice, Vector3(0.14, 0.12, 0.26), Vector3(0, 0.06, 0), Color(0.24, 0.36, 0.3))
	Kit.box(vice, Vector3(0.1, 0.1, 0.06), Vector3(0, 0.08, -0.16), Color(0.24, 0.36, 0.3))
	In.pegboard(p, b, CU + 8.925, 3.4, 270.0, 1.2, 0.7, 1.55, "tools")
	Props.shelves(p, b, CU + 8.69, 6.6, 270.0, 2.0, "boxes")
	# In the middle: the damp, the mop and its bucket, a hand truck left standing.
	Backs.puddle(p, n, CU + 4.4, 6.2, 0.6, 15.0)
	Props.bucket(p, b, CU + 5.3, 6.9)
	Service.hand_truck(p, b, CU + 3.0, 8.4, 30.0, Color(0.62, 0.48, 0.3))
	In.pendant(p, b, CU + 2.6, 3.6, 2.0, Props.DARK, "bulb", In.WARM, 0.35, LOW)
	In.pendant(p, b, CU + 6.2, 7.2, 2.0, Props.DARK, "bulb", In.WARM, 0.3, LOW)
