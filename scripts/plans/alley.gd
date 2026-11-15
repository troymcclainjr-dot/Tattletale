extends RefCounted
## The back lot behind THE LOWDOWN (plans/club.gd), at night. Every name, sign
## and line here is a placeholder. All of it is out of doors but one room, so
## nearly all of it is in the street's band and always on show:
##
##   the alley: down the club's back wall (its back door, the dumpsters, the
##     extractor, the warehouse's loading door beyond), to a dead end at a board
##     fence where somebody sleeps by a burning drum; a lookout on a crate
##   ---- chain link along the alley, a hole cut in it ----
##   the lot: where the houses on the street came down: a car stripped on
##     blocks, tyres, a dumped couch, rubble, a street lamp gone dark; across it
##     the backs of the row, one of them boarded up
##   the stash room: the boarded house's back room, in by its broken back door
##     (its own band: standing in it hides the rest)
##   street: the pavement and the road in front; two on the corner
##
## The club's front is round the corner on the left: this is its back wall, and
## its back door (E: into the club's back hall) opens on the alley. Numbers are
## metres on the plan (see place.gd): u from the club's back wall, v from the
## alley's far end; the street is at v = 18.

const Props := preload("res://scripts/props.gd")
const In := preload("res://scripts/props_in.gd")
const Club := preload("res://scripts/props_club.gd")
const Alley := preload("res://scripts/props_alley.gd")
const Park := preload("res://scripts/props_park.gd")
const Street := preload("res://scripts/props_street.gd")
const Outdoor := preload("res://scripts/outdoor.gd")

const FENCE := 7.0                          # the chain link between the alley and the lot (u)
const HOLE := [9.6, 10.9]                   # the hole cut in it (v)
const BACKS := 6.075                        # the row's back walls' face (v)
const STASH := [12.4, 1.5, 17.6, 6.0]       # the boarded house's back room: u0, v0, u1, v1
const ARCH := {"a": 13.0, "b": 13.9, "kind": "arch", "head": 2.05, "frame": Color(0.24, 0.2, 0.16)}
const DOOR := [0.0, 11.6]                   # the club's back door, on its back wall
const LIL := [0.78, 10.25]                  # the lookout's crate, by the back door (clear of the camera's way down the alley)
const COPING := Color(0.2, 0.2, 0.21)


static func build(p: Node3D) -> void:
	p.setup("THE BACK LOT", 22.0, 18.0)
	p.ambient = 0.12
	p.sun_energy = 0.0
	var st: int = p.street(-3.0, 25.0)
	var b1: int = p.band()
	p.arrive = p.pt(4.0, 19.3)
	var alley: int = p.room("ALLEY", st, 0.0, 0.0, FENCE, 18.0, null, {"street": true, "areas": [[0.0, 0.3, FENCE, 18.8]]})
	var lot: int = p.room("THE LOT", st, FENCE, 6.0, 22.0, 18.0, null, {"street": true})
	# The follow camera stays on his side of the chain link, and short of the
	# board fence on the lot's far side (out of doors it may otherwise go anywhere).
	p.rooms[alley]["cam_max_x"] = p.pt(FENCE - 1.4, 0.0).x
	p.rooms[lot]["cam_max_x"] = p.pt(19.6, 0.0).x
	p.room("STASH ROOM", b1, STASH[0], STASH[1], STASH[2], STASH[3], Kit.tex("in_planks", 1.2, Color(0.3, 0.24, 0.18), true, Color(0.42, 0.36, 0.32)))
	_ground(p, st)
	_club(p, st)
	_alley(p, st)
	# What would hide him in the lot fades while it is in the way (props_street.gd's
	# CarFade, as for the parked cars): the front fence, which the camera is behind
	# once he is halfway in, and the car (_fences, _lot hand it them).
	var fade = Street.car_fade(p, st)
	_fences(p, st, fade)
	_lot(p, st, fade)
	_row(p, st, b1)
	_stash(p, b1)
	_street(p, st)
	_night(p, st)
	_people(p, st, b1)


# ------------------------------------------------------------------- the ground

## Old patched asphalt down the alley (on under the fence at its end), dirt and
## dead grass over the lot with the slabs of the houses' floors still in it.
static func _ground(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	var tar := Outdoor.tex("out_asphalt_old", 4.0, Color(0.24, 0.24, 0.26), Color(0.62, 0.62, 0.68))
	var patch := Outdoor.tex("out_asphalt_patch", 3.0, Color(0.18, 0.18, 0.2), Color(0.55, 0.55, 0.6))
	var dirt := Outdoor.tex("out_dirt", 3.0, Color(0.3, 0.25, 0.2), Color(0.62, 0.58, 0.56))
	var grass := Outdoor.tex("out_dead_grass", 2.4, Color(0.36, 0.34, 0.22), Color(0.6, 0.6, 0.55))
	var slab := Outdoor.tex("out_slab_crack", 2.4, Color(0.5, 0.5, 0.48), Color(0.55, 0.55, 0.56))
	# (In pieces, so no one mesh is lit by more lamps than the renderer takes.)
	for run: Array in [[-6.0, 9.0], [9.0, 18.0]]:
		Kit.box(n, Vector3(FENCE, 0.3, run[1] - run[0]), p.pt(FENCE * 0.5, (run[0] + run[1]) * 0.5, -0.15), tar)
	for run: Array in [[FENCE, 14.5], [14.5, 22.0]]:
		Kit.box(n, Vector3(run[1] - run[0], 0.3, 18.0 - BACKS), p.pt((run[0] + run[1]) * 0.5, (BACKS + 18.0) * 0.5, -0.15), dirt)
	# Patches over the alley's cracks, the gutter down its middle, puddles and oil.
	for s: Array in [[2.2, 4.6, 1.6, 1.1], [4.8, 9.8, 1.2, 2.0], [1.6, 16.2, 1.8, 1.2]]:
		Kit.box(n, Vector3(s[2], 0.012, s[3]), p.pt(s[0], s[1], 0.006), patch)
	Kit.box(n, Vector3(0.34, 0.01, 24.0), p.pt(3.5, 6.0, 0.005), Color(0.15, 0.15, 0.17))
	for s: Array in [[3.3, 6.2, 0.6, 1.6], [3.6, 12.6, 0.5, 1.3], [5.6, 16.8, 0.7, 1.0], [10.6, 9.0, 0.8, 1.1], [17.8, 15.6, 0.6, 1.5]]:
		var pool := Kit.cyl(n, s[2], 0.004, p.pt(s[0], s[1], 0.016), Color(0.1, 0.12, 0.17, 0.75), Vector3.ZERO, 14)
		pool.scale = Vector3(s[3], 1.0, 1.0)
	for s: Array in [[1.9, 9.6, 0.45], [5.2, 14.2, 0.35], [15.2, 14.6, 0.6]]:
		Kit.cyl(n, s[2], 0.004, p.pt(s[0], s[1], 0.012), Color(0.06, 0.06, 0.07, 0.8), Vector3.ZERO, 12)
	# The lot: dead grass in drifts, the houses' floor slabs, cracked.
	for s: Array in [[9.4, 9.4, 3.2, 2.6], [19.8, 7.6, 3.4, 2.2], [11.0, 15.0, 2.6, 2.4], [20.0, 16.2, 3.0, 2.6]]:
		Kit.box(n, Vector3(s[2], 0.008, s[3]), p.pt(s[0], s[1], 0.004), grass)
	for s: Array in [[15.3, 8.4, 4.4, 3.4], [13.6, 16.2, 3.0, 2.4]]:
		Kit.box(n, Vector3(s[2], 0.04, s[3]), p.pt(s[0], s[1], 0.02), slab)


# ------------------------------------------------------------- the club's back

## The club's block on the left, its back wall along the alley: black brick, the
## back door under a caged lamp, the extractor, a meter, conduit, tags. Behind it
## along the alley, the warehouse's taller block with its loading door. On the
## club's side on the street, its name painted on the brick.
static func _club(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	var brick := Kit.tex("brick", 1.5, Color(0.13, 0.12, 0.13), true, Color(0.3, 0.27, 0.31))
	var block := Kit.tex("painted_block", 1.2, Color(0.32, 0.36, 0.32), true, Color(0.44, 0.5, 0.44))
	Kit.box(n, Vector3(20.0, 4.2, 12.05), p.pt(-10.0, 12.025, 2.1), brick)
	Kit.box(n, Vector3(0.3, 0.14, 12.15), p.pt(-0.12, 12.025, 4.27), COPING)            # the copings, the alley's and the street's
	Kit.box(n, Vector3(20.15, 0.14, 0.3), p.pt(-10.045, 17.95, 4.27), COPING)
	Kit.box(n, Vector3(20.0, 5.2, 12.0), p.pt(-10.0, 0.0, 2.6), block)
	Kit.box(n, Vector3(0.3, 0.14, 12.0), p.pt(-0.12, 0.0, 5.27), COPING)
	Kit.box(n, Vector3(19.7, 0.04, 11.7), p.pt(-10.15, 12.0, 4.22), Park.TAR)          # their flat roofs
	Kit.box(n, Vector3(19.7, 0.04, 11.9), p.pt(-10.15, 0.0, 5.22), Park.TAR)
	# The back door (a picture of it: E there goes in), its lamp, cases of empties.
	Alley.back_door(p, n, DOOR[0], DOOR[1], 90.0)
	In.sconce(p, st, DOOR[0], DOOR[1], 90.0, "cage", 2.55, In.WARM, 0.9)
	p.use_point(st, "BACK DOOR", 0.9, DOOR[1], "goto:club", 1.1, 2.35)       # (its word over the door, clear of the lookout's head)
	Props.case_stack(p, st, 0.42, 12.9, 90.0, 2, 2, Color(0.2, 0.3, 0.55))
	Alley.vent(p, n, 0.0, 9.6, 90.0, 2.9)
	var meter := Kit.group(n, p.pt(0.0, 15.9), Vector3(0, 90, 0))
	Kit.box(meter, Vector3(0.34, 0.5, 0.16), Vector3(0, 1.55, 0.08), Color(0.46, 0.48, 0.5))
	Kit.cyl(meter, 0.09, 0.08, Vector3(0, 1.6, 0.2), Color(0.75, 0.82, 0.85, 0.5), Vector3(90, 0, 0), 12)
	Kit.cyl(n, 0.03, 11.6, p.pt(0.06, 12.0, 3.4), Props.IRON, Vector3(90, 0, 0), 6)     # conduit along the wall
	Kit.cyl(n, 0.03, 1.8, p.pt(0.06, 15.9, 2.5), Props.IRON, Vector3.ZERO, 6)            # down to the meter
	Kit.box(n, Vector3(0.1, 4.05, 0.1), p.pt(0.06, 17.6, 2.025), Color(0.32, 0.33, 0.34))   # the downspout
	Club.tags(p, st, 0.0, 13.6, 90.0, [["SKRONK", -0.4, 1.9, 0.3, 5.0], ["OOKS", 1.1, 1.2, 0.2, -6.0]], 11.0)
	Club.tags(p, st, 0.0, 6.9, 90.0, [["DRIZZO", 0.0, 2.2, 0.26, -4.0]], 12.0)
	Club.flyers(p, n, 0.0, 15.0, 90.0, 1.2, 0.8, 1.35, 7)
	# The warehouse: its loading door, the bay painted out in front of it, a stencil.
	Alley.loading_door(p, n, 0.0, 3.6, 90.0, 2.6, 2.6)
	for k in 6:
		Kit.box(n, Vector3(1.8, 0.006, 0.12), p.pt(1.2, 2.5 + 0.44 * k, 0.004), Color(0.75, 0.62, 0.15))
	Park.ground_words(n, "NO PARKING", p.pt(1.5, 3.6, 0.012), 0.26, Color(0.82, 0.7, 0.2), 90.0)
	Club.tags(p, st, 0.0, 1.2, 90.0, [["KOOLA", 0.0, 1.6, 0.34, 3.0]], 13.0)
	# Round the corner on the street: the club's name painted on its side, faded.
	var sign := Props.words(n, "THE LOWDOWN", p.pt(-4.6, 18.06, 3.2), 0.62, Color(0.75, 0.66, 0.58, 0.38))
	sign.outline_size = 0
	Props.words(n, "COCKTAILS  -  DJ NIGHTLY", p.pt(-4.6, 18.06, 2.55), 0.22, Color(0.75, 0.66, 0.58, 0.3)).outline_size = 0
	Club.flyers(p, n, -2.0, 18.05, 0.0, 2.2, 1.0, 0.85, 10)
	Club.tags(p, st, -6.5, 18.05, 0.0, [["VEX 7", 0.0, 1.5, 0.3, -3.0]], 14.0)


# ------------------------------------------------------------------- the alley

## Down the alley: the dumpsters against the club, bags, the steam off the
## grate, and at the dead end the mattress against the fence, the sleeper, the
## drum somebody burns rubbish in, the pole and its wires; the lookout's crate.
static func _alley(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	Alley.dumpster(p, st, 0.62, 7.9, 90.0, Color(0.18, 0.32, 0.22), true, [["NUBZ", 0.3, 0.62, 0.2, -6.0]], 1.0)
	Alley.dumpster(p, st, 0.62, 14.75, 90.0, Color(0.16, 0.24, 0.42), false, [["ZAYDO", -0.2, 0.7, 0.18, 4.0]], 2.0)
	Street.bags(n, p.pt(1.45, 6.6), 2)
	Street.bags(n, p.pt(1.4, 16.0), 3)
	Alley.steam_grate(p, st, 2.6, 13.6)
	Alley.mattress(p, st, 1.6, 0.75, 0.0, 12.0)
	Alley.sleeper(p, st, 4.3, 1.45, 270.0)
	Alley.burn_barrel(p, st, 5.3, 3.4, 1.5)
	Alley.perch(p, st, LIL[0], LIL[1])
	# What has blown in and not been swept.
	Club.litter(p, st, 3.0, 9.0, 4.4, 6.0, 9, 21.0)
	Club.litter(p, st, 3.2, 15.6, 4.0, 3.6, 6, 22.0)
	Club.litter(p, st, 3.0, 2.4, 3.6, 2.4, 6, 23.0)


# ------------------------------------------------------------------- the fences

## Chain link down the alley's side, a hole cut in it and the mesh peeled up
## over the hole, the owner's sign beside it; chain link along the lot's front
## (in a group of its own, for `fade`); boards across the alley's end and down
## the lot's far side.
static func _fences(p: Node3D, st: int, fade) -> void:
	var n: Node3D = p.node_of(st)
	p.fence(st, false, FENCE, BACKS + 0.08, 18.0, [HOLE], 2.4, "chain")
	var front := Kit.group(n, Vector3.ZERO, Vector3.ZERO, "LotFront")
	var first := n.get_child_count()
	p.fence(st, true, 18.0, FENCE, 21.95, [], 2.4, "chain")
	for c: Node in n.get_children().slice(first):      # (place.gd builds it in the band's node: move it into its group)
		c.reparent(front)
	fade.add(front)
	Park._boards(p, n, true, 0.3, 0.0, FENCE, 2.4)          # (the park's board fence: its rails stand off its boards)
	p.block(0.0, 0.26, FENCE, 0.34)
	Park._boards(p, n, false, 22.0, BACKS + 0.05, 15.0, 2.2)
	p.block(21.96, BACKS + 0.05, 22.04, 15.0)
	# Over the hole: the top rail runs on, and the mesh cut from it hangs peeled up, into the lot.
	Kit.cyl(n, 0.024, HOLE[1] - HOLE[0], p.pt(FENCE, (HOLE[0] + HOLE[1]) * 0.5, 2.37), Color(0.55, 0.58, 0.6), Vector3(90, 0, 0), 8)
	var flap := Kit.group(n, p.pt(FENCE, (HOLE[0] + HOLE[1]) * 0.5, 2.3), Vector3(0, 0, 58))
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(HOLE[1] - HOLE[0] - 0.1, 0.85)
	mesh.mesh = quad
	# The fence's mesh is laid on from the world's sides (outdoor.gd), which smears
	# it on a slope: the flap's own copy is laid on the flap, at the same size.
	var wire := Outdoor.chain_link().duplicate() as StandardMaterial3D
	if wire:
		wire.uv1_triplanar = false
		wire.uv1_world_triplanar = false
		wire.uv1_scale = Vector3(quad.size.x / 0.6, quad.size.y / 0.6, 1.0)
	mesh.material_override = wire if wire else Outdoor.chain_link()
	mesh.position = Vector3(0, -0.425, 0)
	mesh.rotation_degrees = Vector3(0, 90, 0)
	flap.add_child(mesh)
	# The owner's sign, wired to the chain link on the alley's side, a step from
	# the hole; a tag on the board fence at the alley's end, another on the lot's.
	var notice := Kit.group(n, p.pt(FENCE - 0.012, 12.2), Vector3(0, 270, 0))
	Kit.box(notice, Vector3(0.9, 0.5, 0.012), Vector3(0, 1.45, 0.0), Props.PAPER, Vector3(0, 0, -3))
	Props.words(notice, "PRIVATE PROPERTY\nNO TRESPASSING", Vector3(0, 1.45, 0.012), 0.085, Color(0.7, 0.1, 0.08)).rotation_degrees.z = -3.0
	Club.tags(p, st, 4.2, 0.33, 0.0, [["GRIMLO", 0.0, 1.75, 0.26, -5.0]], 15.0)
	Club.tags(p, st, 21.98, 11.7, 270.0, [["TEKKA", 0.0, 1.45, 0.3, -4.0]], 19.0)


# --------------------------------------------------------------------- the lot

## Where the houses were: a car on blocks across the middle (stripped, its boot
## up, one of its doors in the dirt), tyres, a couch somebody dumped, a heap of
## the houses' rubble, and the lot's lamp, gone dark. The car fades (`fade`)
## while it hides him, so it has no tag on it (a fading car leaves words standing).
static func _lot(p: Node3D, st: int, fade) -> void:
	var n: Node3D = p.node_of(st)
	fade.add(Alley.stripped_car(p, st, 15.0, 12.0, 90.0, Color(0.42, 0.28, 0.5)))
	Alley.car_door(n, p.pt(11.2, 13.9, 0.0), 24.0, Color(0.42, 0.28, 0.5))
	Alley.tyres(p, st, 8.3, 7.0, 3, true)
	Alley.tyres(p, st, 19.2, 9.0, 4)
	Alley.tyres(p, st, 20.7, 16.6, 2)
	Props.couch(p, st, 19.6, 13.4, 270.0, 1.9, Color(0.36, 0.3, 0.2))
	Alley.rubble(p, st, 10.4, 16.3, 1.6)
	Alley.dead_lamp(p, st, 21.0, 10.6, 270.0)
	Club.litter(p, st, 13.0, 9.0, 8.0, 4.0, 8, 24.0)
	Club.litter(p, st, 15.0, 15.4, 9.0, 2.6, 7, 25.0)
	for i in 6:                         # weeds along the fences' feet
		var u := 7.4 + 2.3 * i
		var g := Kit.group(n, p.pt(u, 17.7))
		for j in 4:
			Kit.box(g, Vector3(0.04, 0.3 + 0.3 * Props.rnd(u + j), 0.04), Vector3(0.06 * j, 0.2, 0.03 * (j % 2)), Color(0.32, 0.4, 0.2), Vector3(14.0 * (Props.rnd(u * 2.0 + j) - 0.5), 60.0 * j, 14.0 * (Props.rnd(u * 3.0 + j) - 0.5)))


# --------------------------------------------------------------------- the row

## The backs of the row across the lot, its end wall on the alley. The boarded
## house in the middle: its back door kicked in (the plywood that was over it
## leaning beside it), plywood over its windows; the houses either side lived
## in, a light at one back door. More backs run on over the board fence.
static func _row(p: Node3D, st: int, b1: int) -> void:
	var n: Node3D = p.node_of(st)
	var red := Kit.tex("brick", 1.5, Color(0.42, 0.22, 0.18), true, Color(0.66, 0.56, 0.56))
	var dark := Kit.tex("brick", 1.5, Color(0.34, 0.2, 0.18), true, Color(0.54, 0.46, 0.5))
	var brown := Kit.tex("brick", 1.5, Color(0.4, 0.28, 0.2), true, Color(0.6, 0.5, 0.44))
	var form := Outdoor.tex("out_formstone", 2.0, Color(0.6, 0.59, 0.55), Color(0.62, 0.62, 0.66))
	var deep := BACKS + 4.0
	# The houses' blocks, left to right; the boarded one's ground floor is the stash room's wall (b1).
	for h: Array in [[FENCE, STASH[0], 6.5, red], [STASH[2], 22.0, 6.0, form], [22.0, 27.2, 6.4, brown], [27.2, 32.4, 6.1, red]]:
		Kit.box(n, Vector3(h[1] - h[0], h[2], deep), p.pt((h[0] + h[1]) * 0.5, BACKS - deep * 0.5, h[2] * 0.5), h[3])
		Kit.box(n, Vector3(h[1] - h[0] + 0.04, 0.16, 0.32), p.pt((h[0] + h[1]) * 0.5, BACKS - 0.14, h[2] + 0.08), COPING)
		Kit.box(n, Vector3(h[1] - h[0] - 0.04, 0.04, deep - 0.4), p.pt((h[0] + h[1]) * 0.5, BACKS - deep * 0.5 - 0.2, h[2] + 0.02), Park.TAR)
	Kit.box(n, Vector3(STASH[2] - STASH[0], 3.3, deep), p.pt((STASH[0] + STASH[2]) * 0.5, BACKS - deep * 0.5, 4.55), dark)
	Kit.box(n, Vector3(STASH[2] - STASH[0] + 0.04, 0.16, 0.32), p.pt((STASH[0] + STASH[2]) * 0.5, BACKS - 0.14, 6.28), COPING)
	Kit.box(n, Vector3(STASH[2] - STASH[0] - 0.04, 0.04, deep - 0.4), p.pt((STASH[0] + STASH[2]) * 0.5, BACKS - deep * 0.5 - 0.2, 6.22), Park.TAR)
	# The boarded house: the doorway (the stash room's), plywood, boarded windows.
	p.cross(b1, STASH[3], STASH[0], STASH[2], dark, [ARCH])
	var ply := Kit.group(n, p.pt(14.45, BACKS + 0.2), Vector3(-7, 0, 0))
	Kit.box(ply, Vector3(0.95, 2.05, 0.02), Vector3(0, 1.02, 0), Alley.PLY)
	Kit.box(ply, Vector3(0.95, 0.08, 0.015), Vector3(0, 1.5, 0.018), Alley.PLY.darkened(0.3))
	p.block(13.95, BACKS, 14.95, BACKS + 0.3)
	for s: Array in [[13.6, 13.4, 30.0], [12.9, 14.0, 75.0]]:         # two of its battens, pulled off and dropped
		Kit.box(n, Vector3(1.0, 0.025, 0.08), p.pt(s[0], s[1], 0.0125), Alley.PLY.darkened(0.3), Vector3(0, s[2], 0))
	Alley.house_window(p, n, 16.3, BACKS, 0.0, 0.95, 1.0, 1.3, "boarded")
	for u: float in [13.6, 16.3]:
		Alley.house_window(p, n, u, BACKS, 0.0, 3.85, 1.0, 1.4, "boarded")
	Club.tags(p, st, 15.2, BACKS + 0.03, 0.0, [["MIZZLE", 0.0, 2.55, 0.24, 3.0]], 16.0)
	# The left one: its back door and window, lit upstairs; the end wall on the alley, tagged.
	Alley.house_door(p, n, 8.2, BACKS, 0.0, Color(0.3, 0.36, 0.3))
	p.block(7.55, BACKS, 8.85, BACKS + 0.45)
	Alley.house_window(p, n, 10.6, BACKS, 0.0, 1.0, 0.9, 1.2, "bars")
	Alley.house_window(p, n, 8.4, BACKS, 0.0, 3.9, 0.9, 1.35, "lit", Color(0.85, 0.3, 0.32))
	Alley.house_window(p, n, 10.8, BACKS, 0.0, 3.9, 0.9, 1.35, "dark")
	Club.tags(p, st, FENCE, 3.0, 270.0, [["VORPO", 0.0, 2.1, 0.3, -4.0], ["OOKS 4 LIFE", 0.8, 1.2, 0.14, 2.0]], 17.0)
	Kit.box(n, Vector3(0.1, 6.3, 0.1), p.pt(7.1, 5.95, 3.15), Color(0.86, 0.85, 0.8))          # the downspout down the corner
	# The right one: lit, its back light on.
	Alley.house_door(p, n, 21.0, BACKS, 0.0, Color(0.6, 0.16, 0.13))
	p.block(20.35, BACKS, 21.65, BACKS + 0.45)
	In.sconce(p, st, 21.0, BACKS, 0.0, "globe", 2.75, In.WARM, 0.7)
	Alley.house_window(p, n, 18.9, BACKS, 0.0, 1.05, 0.9, 1.15, "lit", Color(0.95, 0.85, 0.4))
	Alley.house_window(p, n, 19.5, BACKS, 0.0, 3.75, 0.9, 1.3, "dark")
	var ac := Kit.group(n, p.pt(19.5, BACKS))
	Kit.box(ac, Vector3(0.62, 0.42, 0.5), Vector3(0, 3.98, 0.25), Color(0.84, 0.82, 0.74))
	Kit.box(ac, Vector3(0.5, 0.3, 0.012), Vector3(0, 3.98, 0.506), Color(0.45, 0.45, 0.44))
	# Over the board fence: the next backs, a window lit in each.
	Alley.house_window(p, n, 24.4, BACKS, 0.0, 3.9, 0.9, 1.35, "lit", Color(0.4, 0.6, 0.85))
	Alley.house_window(p, n, 26.0, BACKS, 0.0, 3.9, 0.9, 1.35, "dark")
	Alley.house_window(p, n, 28.6, BACKS, 0.0, 3.9, 0.9, 1.35, "dark")
	Alley.house_window(p, n, 30.8, BACKS, 0.0, 3.9, 0.9, 1.35, "lit", Color(0.9, 0.5, 0.3))


# ----------------------------------------------------------- the stash room

## The boarded house's back room: torn paper on the walls down to the lath in
## places, the door to the front room boarded; one bare bulb over a table with
## a scale on it; a camp stove on a crate, a cooler, a bag, rubbish.
static func _stash(p: Node3D, b: int) -> void:
	var n: Node3D = p.node_of(b)
	var plaster := Kit.tex("in_plaster", 1.0, Color(0.5, 0.46, 0.4), true, Color(0.56, 0.52, 0.46))
	p.side(b, STASH[0], STASH[1], STASH[3], plaster)
	p.side(b, STASH[2], STASH[1], STASH[3], plaster)
	p.cross(b, STASH[1], STASH[0], STASH[2], plaster, [], {"back": true})
	var paper := Kit.tex("in_flower", 0.9, Color(0.45, 0.4, 0.3), true, Color(0.55, 0.5, 0.38))
	var style := {"lower": paper, "upper": paper, "dado": Color(0.28, 0.2, 0.14), "dado_y": 0.95,
			"skirt": Color(0.2, 0.15, 0.11), "skirt_h": 0.12}
	In.room_walls(p, b, STASH[0], STASH[1], STASH[2], STASH[3], style, [], [], [])
	var skin := 0.075 + In.SKIN               # where the paper's face is, off a wall's middle line
	# The paper torn down to the lath, the door to the front room boarded over.
	var back := Kit.group(n, p.pt(0.0, STASH[1] + skin))
	Alley.lath(back, 13.6, 1.7, 0.0, 0.8, 0.6)
	Alley.lath(back, 15.4, 0.55, 0.0, 0.6, 0.4)
	Kit.box(back, Vector3(0.94, 2.06, 0.004), Vector3(16.6, 1.03, 0.002), Color(0.06, 0.05, 0.05))
	Kit.box(back, Vector3(1.0, 2.1, 0.02), Vector3(16.65, 1.05, 0.016), Alley.PLY, Vector3(0, 0, -4))
	var right := Kit.group(n, p.pt(STASH[2] - skin, 0.0), Vector3(0, 270, 0))
	Alley.lath(right, 3.4, 1.9, 0.0, 0.7, 0.5)
	Club.tags(p, b, STASH[0] + skin, 3.4, 90.0, [["RONNIE", 0.0, 1.8, 0.16, -3.0]], 18.0)
	# The table under the bulb: the scale, a shoebox, little bags, money, a phone.
	var table: Node3D = Props.table(p, b, 15.4, 2.75, 0.0, 1.3, 0.7, Color(0.36, 0.28, 0.2))
	Alley.scale(table, Vector3(-0.32, 0.74, 0.02), 12.0)
	var shoebox := Kit.group(table, Vector3(0.22, 0.74, -0.08), Vector3(0, -8, 0))
	Kit.box(shoebox, Vector3(0.34, 0.12, 0.2), Vector3(0, 0.06, 0), Color(0.82, 0.42, 0.16))
	Kit.box(shoebox, Vector3(0.35, 0.025, 0.21), Vector3(0.05, 0.02, 0.24), Color(0.85, 0.45, 0.18), Vector3(0, 14, 0))
	for k in 7:
		Kit.box(table, Vector3(0.04, 0.012, 0.05), Vector3(-0.05 + 0.06 * (k % 4), 0.746, 0.12 + 0.07 * (k / 4)), Color(0.95, 0.95, 0.93), Vector3(0, 20.0 * k, 0))
	for k in 3:
		Kit.box(table, Vector3(0.15, 0.02, 0.07), Vector3(0.45, 0.75 + 0.02 * k, 0.15), Color(0.42, 0.55, 0.38), Vector3(0, 6.0 * k - 4.0, 0))
	Kit.box(table, Vector3(0.07, 0.012, 0.14), Vector3(-0.5, 0.746, -0.15), Color(0.08, 0.08, 0.09), Vector3(0, 30, 0))
	Props.chair(p, b, 14.35, 2.75, 90.0, Color(0.25, 0.22, 0.2))
	In.pendant(p, b, 15.4, 3.1, 2.05, Color(0.3, 0.3, 0.3), "bulb", In.WARM, 0.9)
	Alley.camp_stove(p, b, 13.35, 2.15, 0.0)
	Alley.cooler(p, b, 17.05, 4.4, 270.0)
	Alley.duffel(p, b, 16.65, 5.3, 0.0, Color(0.42, 0.08, 0.1))
	Props.bucket(p, b, 13.15, 3.7)
	Street.bags(n, p.pt(13.1, 4.5), 2)
	Club.litter(p, b, 15.0, 4.4, 3.4, 1.8, 7, 26.0)


# ------------------------------------------------------------------ the street

## The pavement in front: the street lamp on its wood pole at the alley's
## mouth, the wires down the alley to the pole at its end (and from that one on
## over the fence, and down to the club and the row); the houses on along the
## street past the lot.
static func _street(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	var tops: Array = Park.utility_pole(p, n, 6.62, 17.55, 9.4, false, false)
	p.block(6.47, 17.4, 6.77, 17.7)
	var arm := Kit.group(n, p.pt(6.62, 17.55), Vector3(0, 270, 0))
	Park.cobra(arm, 6.2, 1.9, 5.5, 11.0)
	var back: Array = Park.utility_pole(p, n, 6.62, 0.95, 9.4, true, false)
	p.block(6.47, 0.8, 6.77, 1.1)
	for k in 4:
		Park.wire(n, tops[k], back[k], 0.7)
		Park.wire(n, back[k], (back[k] as Vector3) + Vector3(0, 0.6, -40.0), 1.2)
	Park.wire(n, back[3], p.pt(0.05, 9.0, 4.1), 0.5, Color(0.07, 0.07, 0.08), 0.012, 6)
	Park.wire(n, back[3], p.pt(7.6, BACKS + 0.02, 6.2), 0.4, Color(0.07, 0.07, 0.08), 0.012, 6)
	var old := Kit.tex("brick", 1.5, Color(0.4, 0.22, 0.2), true, Color(0.62, 0.58, 0.62))
	Props.rowhouse(p, n, 22.0, 18.0, old, false, true)
	Props.rowhouse(p, n, 27.0, 18.0, old, true)
	Props.rowhouse(p, n, 32.0, 18.0, old, false, false)
	Club.litter(p, st, 6.0, 18.7, 6.0, 0.8, 6, 27.0)


# ------------------------------------------------------------------- the night

## The cool moon in place of main.gd's sun, the city's glow beyond the roofs, and
## the far end of the alley closed by the back of a warehouse.
static func _night(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	Outdoor.moonlight(n, 0.2, Color(0.56, 0.6, 1.0))
	var far := Kit.tex("brick", 1.5, Color(0.25, 0.18, 0.18), true, Color(0.4, 0.36, 0.4))
	Kit.box(n, Vector3(20.0, 8.0, 6.0), p.pt(4.0, -9.0, 4.0), far)
	Kit.box(n, Vector3(19.96, 0.04, 5.96), p.pt(4.0, -9.0, 8.02), Park.TAR)
	Alley.house_window(p, n, 2.2, -6.0, 0.0, 5.0, 1.2, 1.0, "lit", Color(0.6, 0.6, 0.55))
	Alley.house_window(p, n, 5.4, -6.0, 0.0, 5.0, 1.2, 1.0, "dark")
	Outdoor.backdrop(n, p.pt(11.0, -12.0), [Color(0.34, 0.2, 0.38), Color(0.16, 0.12, 0.26)], p.pt(70.0, -480.0, 80.0), 4.0)


# ------------------------------------------------------------------- the people

## Two on the corner at the alley's mouth, the lookout on her crate halfway down,
## and Ronnie in the stash room (names are placeholders; the sleeper is a prop).
static func _people(p: Node3D, st: int, b1: int) -> void:
	p.person(st, "tre", 4.6, 17.3, {"name": "TRE", "face": "suspicious", "talk": "talk_alley_corner.json",
			"wear": {"hat": {"item": "beanie", "colour": "#28282c"}, "jacket": {"item": "puffer", "colour": "#4b5a32"},
				"shirt": {"item": "tee", "colour": "#ececE6"}, "trousers": {"item": "jeans", "colour": "#2c3e64"},
				"shoes": {"item": "boots", "colour": "#c8a050"}}})
	p.person(st, "rell", 1.4, 19.0, {"name": "RELL", "face": "neutral"})
	p.person(st, "lil", LIL[0], LIL[1], {"name": "LIL", "face": "neutral", "talk": "talk_alley_lookout.json"})
	var lil: Dictionary = p.people.back()
	lil["at"] = p.pt(LIL[0], LIL[1], 0.296)          # up on her crate (Alley.perch: its board's top)
	p.person(b1, "ronnie", 15.6, 1.95, {"name": "RONNIE", "face": "neutral", "talk": "talk_alley_stash.json"})
