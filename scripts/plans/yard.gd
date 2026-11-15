extends RefCounted
## The police yard behind the station (plans/police.gd), at dusk: the lot the
## patrol cars live in, seen from its front fence looking at the station's back
## wall, so it runs the other way from the station's own plan (the station's u
## is 26 - u here, its v is -v). One band, all out of doors, one room, POLICE YARD:
##
##   along the back, the bail bondsman's blank back with two cruisers nosed in
##   to it and a bay kept clear (the barricades stacked there); the station's
##   back wall: the sally port's roll-up, up, with the prisoner van backed half
##   in (KEEP CLEAR painted behind it), the steel back door under its lamp (E
##   there: into the sally port), the intercom, a camera; then the empty shop's
##   back, and in front of it the impound pen (chain link, its gate open: a car
##   under a tarp, a stripped one, tyres; the gap between them half out of
##   sight). In the open: the fuel island under its canopy with a cruiser at the
##   pump, jersey barriers along the front, oil on the asphalt, two lamp poles. Chain
##   link round the rest with razor wire on it: the vehicle gate, shut and
##   chained, in the side fence on the alley; the front fence on the alley that
##   runs round the lot (a stub of it while the camera is out past it).
##
## Numbers are metres on the plan (see place.gd): u from the left, v from the
## station's back wall (0) towards the front fence (D); the camera stands out
## past the front fence when he is near it.
##
## Invented here (placeholders): the place's name POLICE YARD and its note BEHIND
## THE STATION (main.gd's list); the use points' labels POLICE STATION here and
## POLICE YARD on the sally port's back door (plans/police.gd); the words KEEP
## CLEAR, IMPOUND, POLICE LINE and AUTHORIZED VEHICLES ONLY; the officer's and
## RONNIE's lines (talk_yard_*.json). The tags are the back lot's taggers'.

const Props := preload("res://scripts/props.gd")
const In := preload("res://scripts/props_in.gd")
const Club := preload("res://scripts/props_club.gd")
const Alley := preload("res://scripts/props_alley.gd")
const Park := preload("res://scripts/props_park.gd")
const Street := preload("res://scripts/props_street.gd")
const Backs := preload("res://scripts/props_backs.gd")
const Outdoor := preload("res://scripts/outdoor.gd")
const Service := preload("res://scripts/props_service.gd")
const Prison := preload("res://scripts/props_prison.gd")
const Yard := preload("res://scripts/props_yard.gd")

const NAME := "POLICE YARD"
const W := 34.0
const D := 15.0                   # the front fence, on the alley that runs round the lot
const LEFT := 1.0                 # the side fence on the alley, the vehicle gate in it
const RIGHT := 33.0               # the fence on the empty lot next door
const BONDS := [-2.0, 10.0]       # the bail bondsman's back (the station's u 16..28)
const STATION := [10.0, 26.0]     # the station's back wall
const LEASE := [26.0, 38.0]       # the empty shop's back (FOR LEASE on the street)
const PORT := [10.34, 12.64]      # the sally port's roll-up (police.gd's 13.36..15.66)
const DOOR := 13.38               # the sally port's back door (police.gd's u 12.62)
const VAN := [11.49, 0.55]        # the prisoner van, backed half in (police.gd's 14.51, -0.55)
const GATE := [5.0, 11.0]         # the vehicle gate, along the side fence
const PEN := [26.3, 7.4]          # the impound pen: from u PEN[0] to RIGHT, from the wall to v PEN[1]
const PEN_GATE := [29.2, 31.8]    # its gateway (the gate swung back inside)
const PUMP := [18.6, 9.4]         # the fuel island's middle; it runs along u
const ROOF := 3.9                 # the station's back is one storey; its front two (7.4), from v -17


static func build(p: Node3D) -> void:
	p.setup(NAME, W, D)
	var st: int = p.band()
	p.arrive = p.pt(DOOR, 2.0)
	# Dusk, as in the service alley: main.gd's sun off, the sky's own light
	# (_sky), the yard's lamps.
	p.ambient = 0.16
	p.sun_energy = 0.0
	var yard: int = p.room(NAME, st, LEFT, 0.0, RIGHT, D, null, {"street": true})
	p.rooms[yard]["cam_max_x"] = p.pt(RIGHT - 1.2, 0.0).x       # the camera stays this side of the far fence
	var fade := Street.car_fade(p, st)
	_ground(p, st)
	_backs(p, st)
	_station(p, st, fade)
	_bays(p, st, fade)
	_pump(p, st, fade)
	_pen(p, st, fade)
	_fences(p, st)
	_alley(p, st)
	_sky(p, st)
	_people(p, st)
	# The way in: the sally port's back door (main.gd's "goto:"; it comes out of
	# its POLICE YARD door, plans/police.gd).
	p.use_point(st, "POLICE STATION", DOOR, 0.65, "goto:police", 1.0, 2.0)


# ------------------------------------------------------------------- the ground

## Old asphalt (in pieces 11 m long at most: a mesh takes eight lamps at most),
## a concrete apron along the station's wall, patches, puddles, oil where the
## cars stand; the alley's own older asphalt past the side fence, and the empty
## lot's dirt past the far one.
static func _ground(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	var tar := Outdoor.tex("out_asphalt_old", 4.0, Color(0.24, 0.24, 0.26), Color(0.62, 0.62, 0.68))
	var patch := Outdoor.tex("out_asphalt_patch", 3.0, Color(0.27, 0.27, 0.29), Color(0.86, 0.86, 0.9))
	for run: Array in [[LEFT, 9.0], [9.0, 17.0], [17.0, 25.0], [25.0, RIGHT]]:
		Service.gb(p, n, run[0], run[1], 0.0, D + 9.0, -0.3, 0.0, tar)
	Service.gb(p, n, STATION[0] + 0.2, STATION[1] - 0.1, 0.0, 1.1, 0.0, 0.006, Kit.tex("sidewalk", 2.4, Color(0.55, 0.55, 0.54), true, Color(0.7, 0.7, 0.68)))
	for s: Array in [[6.2, 9.6, 2.2, 1.3], [15.0, 12.4, 1.6, 2.2], [24.4, 9.8, 2.4, 1.2], [3.2, 12.6, 1.4, 1.4]]:
		Service.gb(p, n, s[0] - s[2] * 0.5, s[0] + s[2] * 0.5, s[1] - s[3] * 0.5, s[1] + s[3] * 0.5, 0.0, 0.012, patch)
	for s: Array in [[9.0, 7.6, 0.6, 15.0], [22.6, 13.4, 0.45, -25.0], [29.8, 9.6, 0.5, 40.0]]:
		Backs.puddle(p, n, s[0], s[1], s[2], s[3])
	var oil := StandardMaterial3D.new()
	oil.albedo_color = Color(0.13, 0.12, 0.15, 0.6)
	oil.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	oil.roughness = 0.3
	oil.metallic_specular = 0.6
	for s: Array in [[3.4, 3.4, 0.4], [6.5, 3.6, 0.32], [8.8, 3.3, 0.36], [11.4, 2.9, 0.3], [18.2, 7.6, 0.42]]:
		Kit.cyl(n, s[2], 0.004, p.pt(s[0], s[1], 0.012), oil, Vector3.ZERO, 16)
	# Past the side fence, the alley; past the far fence, the empty lot.
	var old := Outdoor.tex("out_asphalt_old", 4.0, Color(0.22, 0.22, 0.23), Color(0.55, 0.55, 0.6))
	Service.gb(p, n, -9.0, LEFT, -6.0, D + 9.0, -0.3, 0.0, old)
	Service.gb(p, n, -3.2, -2.9, -6.0, D + 9.0, 0.0, 0.006, Color(0.34, 0.34, 0.35))       # its gutter
	var dirt := Outdoor.tex("out_dirt", 3.0, Color(0.36, 0.32, 0.26), Color(0.62, 0.56, 0.48))
	Service.gb(p, n, RIGHT, RIGHT + 9.0, 0.0, D + 9.0, -0.3, 0.0, dirt)


# --------------------------------------------------------------- the backs

## Along the back, v = 0: the bail bondsman's (brick, lower), the station's
## (painted block, its two-storey front rising behind) and the empty shop's
## (stucco, taller); a coping along each top.
static func _backs(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	var brick := Kit.tex("brick", 1.5, Color(0.4, 0.22, 0.2), true, Color(0.72, 0.68, 0.74))
	var stucco := Kit.tex("stucco", 2.0, Color(0.6, 0.56, 0.5), true, Color(0.72, 0.68, 0.62))
	var front := Kit.tex("brick", 1.5, Color(0.5, 0.26, 0.2), true, Color(0.9, 0.82, 0.8))
	Service.gb(p, n, BONDS[0], BONDS[1], -10.0, 0.0, 0.0, 3.5, brick)
	Service.gb(p, n, BONDS[0] - 0.02, BONDS[1], -0.25, 0.08, 3.5, 3.66, Park.COPING)
	Service.gb(p, n, LEASE[0], LEASE[1], -12.0, 0.0, 0.0, 4.4, stucco)
	Service.gb(p, n, LEASE[0], LEASE[1] + 0.02, -0.25, 0.08, 4.4, 4.56, Park.COPING)
	# The station's front block over its back: its back face, upstairs windows lit and dark.
	Service.gb(p, n, STATION[0], STATION[1], -22.0, -17.0, 0.0, 7.4, front)
	Service.gb(p, n, STATION[0] - 0.02, STATION[1] + 0.02, -17.25, -16.92, 7.4, 7.56, Park.COPING)
	for i in 6:
		var u: float = STATION[1] - 1.5 - i * 2.6
		var lit := i in [1, 4]
		var look: Variant = Kit.flat(Color(1.0, 0.86, 0.6), 0.7) if lit else Color(0.13, 0.14, 0.17)
		Service.gb(p, n, u - 0.55, u + 0.55, -16.99, -16.96, 4.75, 6.25, look)
		Service.gb(p, n, u - 0.62, u + 0.62, -16.98, -16.9, 4.68, 4.75, Color(0.74, 0.72, 0.66))       # its sill
	# The bail bondsman's: a barred window, the air conditioner, a downspout.
	Alley.house_window(p, n, 8.0, 0.0, 0.0, 1.75, 0.8, 0.7, "bars")
	Service.ac_unit(p, n, 4.9, 0.0, 2.6)
	Service.gb(p, n, 1.6, 1.7, 0.0, 0.1, 0.12, 3.5, Color(0.32, 0.33, 0.34))
	Club.tags(p, st, 2.3, 0.0, 0.0, [["GRIMLO", 0.0, 1.0, 0.26, -4.0]], 41.0)
	# The empty shop's: its roll door shut, a boarded window, a downspout.
	Backs.roll_door(p, n, 31.6, 0.0, 0.0, 2.4, 2.2)
	Alley.house_window(p, n, 28.0, 0.0, 0.0, 1.5, 1.0, 1.1, "boarded")
	Service.gb(p, n, 26.25, 26.35, 0.0, 0.1, 0.12, 4.4, Color(0.32, 0.33, 0.34))
	Club.tags(p, st, 29.7, 0.0, 0.0, [["TEKKA", 0.0, 2.6, 0.28, 3.0]], 42.0)


## The station's back wall, painted block one storey high: the sally port's
## roll-up (up, its hood over it, the prisoner van backed half in, the port's
## lit inside past it), KEEP CLEAR painted behind the van; the steel back door
## under its lamp, the intercom and a camera; a lamp further along, downspouts,
## the condensers on the roof.
static func _station(p: Node3D, st: int, fade) -> void:
	var n: Node3D = p.node_of(st)
	var block := Kit.tex("painted_block", 1.2, Color(0.56, 0.56, 0.53), true, Color(0.76, 0.76, 0.72))
	var iron := Color(0.24, 0.25, 0.28)
	Service.gb(p, n, STATION[0], PORT[0], -0.15, 0.0, 0.0, ROOF, block)
	Service.gb(p, n, PORT[1], STATION[1], -0.15, 0.0, 0.0, ROOF, block)
	Service.gb(p, n, PORT[0], PORT[1], -0.15, 0.0, 2.7, ROOF, block)
	Service.gb(p, n, STATION[0], STATION[1], -17.0, -5.15, 0.0, ROOF, block)
	Service.gb(p, n, STATION[0] + 4.0, STATION[1], -5.15, -0.15, 0.0, ROOF, block)
	Service.gb(p, n, STATION[0] - 0.02, STATION[1] + 0.02, -0.27, 0.1, ROOF, ROOF + 0.16, Park.COPING)
	# The sally port, seen through its door: the concrete floor, block walls
	# striped at their foot, a lamp; the rolled door in its hood; the guides.
	var inside := Color(0.5, 0.52, 0.56)
	Service.gb(p, n, STATION[0], STATION[0] + 4.0, -5.15, -0.15, -0.3, 0.0, Kit.tex("sidewalk", 2.4, Color(0.55, 0.55, 0.55), true, Color(0.72, 0.72, 0.76)))
	Service.gb(p, n, STATION[0], STATION[0] + 4.0, -5.15, -5.0, 0.0, 2.9, inside)
	Service.gb(p, n, STATION[0], STATION[0] + 0.15, -5.0, -0.15, 0.0, 2.9, inside)
	Service.gb(p, n, STATION[0] + 3.85, STATION[0] + 4.0, -5.0, -0.15, 0.0, 2.9, inside)
	Service.gb(p, n, STATION[0], STATION[0] + 4.0, -5.0, -0.15, 2.9, 3.0, inside.darkened(0.3))
	var hazard := Kit.tex("in_hazard", 0.8, Color(0.9, 0.75, 0.2))
	Service.gb(p, n, STATION[0] + 0.15, STATION[0] + 3.85, -4.999, -4.99, 0.0, 0.42, hazard)
	Service.gb(p, n, STATION[0] + 0.7, STATION[0] + 1.9, -4.99, -4.95, 2.45, 2.55, Kit.flat(Color(0.97, 0.98, 0.94), 1.2))
	Kit.omni(n, p.pt(STATION[0] + 2.0, -2.6, 2.4), Color(0.97, 0.98, 0.94), 0.5, 4.0)
	Service.gb(p, n, PORT[0] - 0.12, PORT[1] + 0.12, 0.0, 0.28, 2.72, 3.12, iron)
	Service.gb(p, n, PORT[0] - 0.1, PORT[1] + 0.1, 0.27, 0.29, 2.75, 3.09, iron.lightened(0.1))
	for u: float in [PORT[0] - 0.05, PORT[1] + 0.05]:
		Service.gb(p, n, u - 0.05, u + 0.05, 0.0, 0.09, 0.0, 2.72, iron)
	fade.add(Props.car(p, st, VAN[0], VAN[1], 180.0, "van"))
	Prison.bollard(p, st, PORT[0] - 0.32, 0.4)
	Park.ground_words(n, "KEEP CLEAR", p.pt(VAN[0], 3.55, 0.012), 0.3, Color(0.86, 0.72, 0.24))
	# The back door, its lamp, the intercom beside it, the camera over them.
	Yard.back_door(p, n, DOOR, 0.0, 0.0)
	In.sconce(p, st, DOOR, 0.0, 0.0, "cage", 2.5, In.WARM, 0.9)
	Prison.intercom(p, st, DOOR + 0.78, 0.0, 0.0, 1.35)
	In.camera(p, st, DOOR + 1.6, 0.0, 330.0, 3.2)
	Props.bucket(p, st, DOOR + 1.25, 0.35)          # the smokers' (sand and butts)
	# Further along: a lamp, the cell block's vents up high, downspouts.
	In.sconce(p, st, 20.0, 0.0, 0.0, "cage", 3.3, In.WARM, 1.0)
	for u: float in [16.5, 19.5, 22.5, 25.0]:
		Service.gb(p, n, u - 0.3, u + 0.3, 0.0, 0.05, 2.75, 3.1, Color(0.46, 0.48, 0.5))
		for k in 4:
			Service.gb(p, n, u - 0.27, u + 0.27, 0.05, 0.06, 2.8 + k * 0.08, 2.83 + k * 0.08, Color(0.3, 0.31, 0.33))
	for u: float in [14.15, 25.8]:
		Service.gb(p, n, u - 0.05, u + 0.05, 0.0, 0.1, 0.12, ROOF, Color(0.32, 0.33, 0.34))
	Service.ac_unit(p, n, 23.6, 0.0, 2.0)
	var unit := Service.condenser(p, st, 18.0, -2.4, 0.0)
	unit.position.y += ROOF
	unit = Service.condenser(p, st, 23.4, -3.0, 90.0)
	unit.position.y += ROOF


# ------------------------------------------------------------------- the yard

## The bays along the bail bondsman's back: two cruisers nosed in, the third
## bay kept clear with the barricades stacked against the wall and cones out.
## Lines painted between them.
static func _bays(p: Node3D, st: int, fade) -> void:
	var n: Node3D = p.node_of(st)
	var paint := Color(0.86, 0.85, 0.8)
	for u: float in [1.9, 4.9, 7.9, 10.1]:
		Service.gb(p, n, u - 0.05, u + 0.05, 0.3, 5.6, 0.0, 0.006, paint)
	fade.add(Props.car(p, st, 3.4, 2.85, 180.0, "cruiser"))
	fade.add(Props.car(p, st, 6.4, 2.85, 180.0, "cruiser"))
	Yard.barricades(p, st, 9.0, 0.4, 0.0)
	Prison.cone(p, st, 8.5, 4.2)
	Prison.cone(p, st, 9.5, 4.8)


## The fuel island under its canopy, a cruiser at the pump on its far side; a
## pair of jersey barriers kept along the front fence.
static func _pump(p: Node3D, st: int, fade) -> void:
	Yard.fuel_island(p, st, PUMP[0], PUMP[1], 0.0, 3.4)
	fade.add(Props.car(p, st, PUMP[0], PUMP[1] - 2.1, 90.0, "cruiser"))
	for k in 2:
		Yard.jersey(p, st, 6.0 + k * 2.06, 13.9, 0.0)
	Club.litter(p, st, 14.0, 12.0, 6.0, 3.0, 6, 43.0)


## The impound pen in the far corner: chain link across its front and down its
## side, the gate swung back inside, IMPOUND wired to it; inside, a car under a
## tarp and a stripped one with a gap between them, tyres.
static func _pen(p: Node3D, st: int, fade) -> void:
	var n: Node3D = p.node_of(st)
	p.fence(st, true, PEN[1], PEN[0], RIGHT, [PEN_GATE], 2.4, "chain")
	p.fence(st, false, PEN[0], 0.1, PEN[1], [], 2.4, "chain")
	Prison.open_leaf(p, n, PEN[1], PEN_GATE[0], 2.0, 2.3)
	Yard.fence_sign(p, n, 27.75, PEN[1], "IMPOUND")
	fade.add(Backs.tarp_car(p, st, 28.0, 3.0, 0.0))
	fade.add(Alley.stripped_car(p, st, 31.3, 3.3, 180.0, Color(0.5, 0.2, 0.16)))
	Alley.tyres(p, st, 27.0, 6.45, 3, true)
	Alley.tyres(p, st, 32.4, 6.6, 2)


## The rest of the chain link, 2.4 high with razor wire along it: down the side
## on the alley with the vehicle gate in it, along the far side, and across the
## front, in a group of its own with a knee-high stub of it in another that
## stands in for it while the camera is out past it (props_alley.gd's Cutaway).
## The two lamp poles in the front corners, thrown back over the yard.
static func _fences(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	p.fence(st, false, LEFT, 0.0, GATE[0], [], 2.4, "chain")
	p.fence(st, false, LEFT, GATE[1], D, [], 2.4, "chain")
	Yard.side_gate(p, n, LEFT, GATE[0], GATE[1], 2.4)
	Prison.wire_on(p, n, false, LEFT, 0.0, GATE[0], [], 2.4)
	Prison.wire_on(p, n, false, LEFT, GATE[1], D, [], 2.4)
	p.fence(st, false, RIGHT, 0.0, D, [], 2.4, "chain")
	Prison.wire_on(p, n, false, RIGHT, 0.0, D, [], 2.4)
	var front := Kit.group(n, Vector3.ZERO, Vector3.ZERO, "YardFront")
	var stub := Kit.group(n, Vector3.ZERO, Vector3.ZERO, "YardFrontStub")
	for g: Node3D in [front, stub]:
		var first := n.get_child_count()
		p.fence(st, true, D, LEFT, RIGHT, [], 2.4 if g == front else 0.5, "chain")
		for c: Node in n.get_children().slice(first):      # (place.gd builds it in the band's node: move it into its group)
			c.reparent(g)
	p.obstacles.pop_back()                                 # (the stub's: where it stands is blocked already)
	Prison.wire_on(p, front, true, D, LEFT, RIGHT, [], 2.4)
	Alley.cutaway(p, st, front, stub, D)
	Park.floodlight(p, st, 1.7, 14.3, 45.0, 7.2, 2, 3.5, 4.5, false, Vector2(9.0, 4.0))
	Park.floodlight(p, st, 32.3, 14.3, -45.0, 7.2, 2, 3.5, 4.5, false, Vector2(23.0, 4.0))


## The alley past the side fence: its far side the blank back of a warehouse
## (a roll door, barred windows, tags), a dumpster against it, a lamp on a
## pole over it.
static func _alley(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	var brick := Kit.tex("brick", 1.5, Color(0.34, 0.26, 0.24), true, Color(0.6, 0.54, 0.56))
	Service.gb(p, n, -12.0, -7.0, -10.0, D + 9.0, 0.0, 4.8, brick)
	Service.gb(p, n, -7.08, -6.9, -10.0, D + 9.0, 4.8, 4.96, Park.COPING)
	Backs.roll_door(p, n, -7.0, 3.2, 90.0, 2.8, 2.6)
	for v: float in [8.4, 12.6]:
		Alley.house_window(p, n, -7.0, v, 90.0, 1.8, 0.9, 0.8, "bars")
	Club.tags(p, st, -6.99, 7.0, 90.0, [["DRIZZO", 0.0, 1.4, 0.3, -3.0]], 44.0)
	Alley.dumpster(p, st, -6.4, 10.4, 90.0, Color(0.2, 0.32, 0.5), true, [], 45.0)
	Alley.bags(p, st, -5.7, 12.0, 2, 46.0)
	Street.cobra_lamp(p, st, -6.6, 6.0, 90.0, 1.6, 6.0)


# ------------------------------------------------------------------- the sky

## Dusk, as over the service alley: the sky's light, the last of the sun low in
## the west, the glow behind the station.
static func _sky(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	Outdoor.moonlight(n, 0.22, Color(0.56, 0.6, 1.0))
	var glow := Outdoor.moonlight(n, 0.32, Color(1.0, 0.6, 0.42))
	glow.rotation_degrees = Vector3(-14, 64, 0)
	var sky := Outdoor.backdrop(n, p.pt(17.0, -40.0), [Color(1.0, 0.62, 0.3), Color(0.93, 0.4, 0.42), Color(0.34, 0.22, 0.5)], Vector3.INF, 9.0, 900.0, Vector2(1.0, -0.05))
	sky.set_meta("combat_fx", true)      # out of the shooting (see plans/service.gd)


# ------------------------------------------------------------------ the people

## An officer at the pump (to talk to), another by the back door; RONNIE, who
## drives the tow truck, waiting on his paperwork outside the pen (to talk to).
## Lines are placeholders.
static func _people(p: Node3D, st: int) -> void:
	p.person(st, "cop", PUMP[0] + 2.6, PUMP[1] + 0.1, {"name": "PATROL OFFICER", "face": "neutral", "talk": "talk_yard_cop.json"})
	p.person(st, "cop", DOOR + 1.9, 1.5, {"face": "focused"})
	p.person(st, "ronnie", 32.25, 8.5, {"name": "RONNIE", "face": "neutral", "talk": "talk_yard_tow.json"})
