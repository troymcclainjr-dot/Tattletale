extends RefCounted
## The service alley behind the strip, at dusk: the backs of the corner store
## (plans/store.gd), the gun store (plans/gunstore.gd), the studio (building.gd)
## and the clothing store (plans/clothes.gd), seen from the alley's far side
## looking at their back walls, so they run the other way from the street's:
## the corner store on the left by the cross street, the clothing store on the
## right. One band, all out of doors, one room, SERVICE ALLEY:
##
##   the alley, from the chained gate across its mouth on the cross street to
##   the board fence across its far end. The corner store's roll door, its bay
##   painted on the ground (E there: into its stock room), crates, a bale of
##   cardboard, its bins; a van along the gun store's blank back with its back
##   doors open and the driver at it, and between the van and the wall a gap
##   that is half out of sight, a dumpster closing its far end; the studio's
##   steel back door (E: into the vocal booth); the clothing store's (E: into
##   its stock room), roll cages of stock waiting, pallets, more bins.
##
## Numbers are metres on the plan (see place.gd): u along the alley from the
## cross street, v from the shops' back walls (0) across the alley; the camera
## stands over its far side (v > 9), where nothing is built. A shop's own u
## runs the other way here: the store's u is 10.5 - u, the studio's x is
## 24.6 - u, the clothing store's u is 39 - u.
##
## Invented here (placeholders): the place's name SERVICE ALLEY and its note
## BEHIND THE STRIP (main.gd's list); the use points' labels CORNER STORE,
## STUDIO, CLOTHING STORE; RECEIVING over the store's roll door; PEN LUCY
## WHOLESALE on the van; the tags (DRIZZO is the back lot's tagger); the
## people's lines (talk_service_*.json).

const Props := preload("res://scripts/props.gd")
const In := preload("res://scripts/props_in.gd")
const Club := preload("res://scripts/props_club.gd")
const Alley := preload("res://scripts/props_alley.gd")
const Park := preload("res://scripts/props_park.gd")
const Street := preload("res://scripts/props_street.gd")
const Backs := preload("res://scripts/props_backs.gd")
const Outdoor := preload("res://scripts/outdoor.gd")
const Service := preload("res://scripts/props_service.gd")

const NAME := "SERVICE ALLEY"
const W := 42.0
const D := 9.0               # the alley's far side
const MOUTH := 1.5           # the gate across the alley's mouth (u); the cross street beyond
const END := 40.2            # the board fence across its far end (u)
const STORE := [1.5, 10.5]
const GUN := [10.5, 20.5]
const STUDIO := [20.5, 29.0]
const CLOTHES := [29.0, 39.0]
const STORE_DOOR := 4.5      # the store's roll door: its stock room's (store.gd's u 6.0)
const STUDIO_DOOR := 24.45   # the studio's back door: the booth's (building.gd's x 0.15)
const CLOTHES_DOOR := 31.475   # the clothing store's: its stock room's (clothes.gd's u 7.525)
const VAN := [15.6, 2.45]    # the van's middle; it is 5.2 long along u, 2.0 wide
const PAINT := Color(0.75, 0.62, 0.15)


static func build(p: Node3D) -> void:
	p.setup(NAME, W, D)
	var st: int = p.band()
	p.arrive = p.pt(20.0, 5.2)
	# Dusk, as on Rose Hill: main.gd's sun off, the last of the sun and the sky's
	# own light (_sky); the lamps over the back doors.
	p.ambient = 0.16
	p.sun_energy = 0.0
	var alley: int = p.room(NAME, st, MOUTH, 0.0, END, D, null, {"street": true})
	p.rooms[alley]["cam_max_x"] = p.pt(END - 1.4, 0.0).x       # the camera stays this side of the far fence
	_ground(p, st)
	_backs(p, st)
	_store(p, st)
	_gun(p, st)
	_studio(p, st)
	_clothes(p, st)
	_ends(p, st)
	_sky(p, st)
	_people(p, st)
	# The ways in: the store's roll door, the studio's back door, the clothing
	# store's (main.gd's "goto:"; each comes out of its shop's back door).
	p.use_point(st, "CORNER STORE", STORE_DOOR, 0.65, "goto:store", 1.1, 2.35)
	p.use_point(st, "STUDIO", STUDIO_DOOR, 0.65, "goto:studio", 1.0, 2.0)
	p.use_point(st, "CLOTHING STORE", CLOTHES_DOOR, 0.65, "goto:clothes", 1.0, 2.0)


# ------------------------------------------------------------------- the ground

## Old asphalt (in pieces 11 m long at most: a mesh takes eight lamps at most),
## a gutter down the middle, patches, puddles, oil under the van; past the gate
## the cross street's pavement and road.
static func _ground(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	var tar := Outdoor.tex("out_asphalt_old", 4.0, Color(0.24, 0.24, 0.26), Color(0.62, 0.62, 0.68))
	var patch := Outdoor.tex("out_asphalt_patch", 3.0, Color(0.27, 0.27, 0.29), Color(0.86, 0.86, 0.9))
	for run: Array in [[-0.6, 10.5], [10.5, 21.0], [21.0, 31.5], [31.5, 44.0]]:
		Service.gb(p, n, run[0], run[1], 0.0, 16.0, -0.3, 0.0, tar)
	Service.gb(p, n, -0.6, 44.0, 4.4, 4.7, 0.0, 0.006, Color(0.34, 0.34, 0.35))
	for s: Array in [[7.4, 6.6, 1.8, 1.2], [20.6, 5.8, 1.4, 2.0], [27.4, 7.6, 2.2, 1.1], [36.8, 3.0, 1.5, 1.4]]:
		Service.gb(p, n, s[0] - s[2] * 0.5, s[0] + s[2] * 0.5, s[1] - s[3] * 0.5, s[1] + s[3] * 0.5, 0.0, 0.012, patch)
	for s: Array in [[8.6, 5.6, 0.5, 20.0], [21.8, 4.2, 0.42, -30.0], [35.0, 6.3, 0.55, 10.0]]:
		Backs.puddle(p, n, s[0], s[1], s[2], s[3])
	var oil := StandardMaterial3D.new()
	oil.albedo_color = Color(0.13, 0.12, 0.15, 0.6)
	oil.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	oil.roughness = 0.3
	oil.metallic_specular = 0.6
	for s: Array in [[14.2, 2.6, 0.45], [17.3, 2.3, 0.35]]:
		Kit.cyl(n, s[2], 0.004, p.pt(s[0], s[1], 0.012), oil, Vector3.ZERO, 16)
	# The cross street: its pavement, the kerb, the road.
	Service.gb(p, n, -2.6, -0.6, -6.0, 16.0, -0.3, 0.0, Outdoor.pavement())
	Service.gb(p, n, -2.8, -2.6, -6.0, 16.0, -0.3, 0.02, Color(0.84, 0.82, 0.77))
	Service.gb(p, n, -12.0, -2.8, -6.0, 16.0, -0.45, -0.14, Outdoor.road())


# --------------------------------------------------------------- the shops' backs

## The four blocks along the alley, their back walls on v = 0: the corner
## store's red brick, the gun store's painted block (the range: taller and
## blank), the studio's stucco, the clothing store's dark brick; a coping along
## each top, the flat roofs behind.
static func _backs(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	var brick := Kit.tex("brick", 1.5, Color(0.42, 0.24, 0.2), true, Color(0.75, 0.62, 0.6))
	var block := Kit.tex("painted_block", 1.2, Color(0.5, 0.52, 0.48), true, Color(0.66, 0.7, 0.64))
	var stucco := Kit.tex("stucco", 2.0, Color(0.55, 0.5, 0.42), true, Color(0.85, 0.78, 0.66))
	var dark_brick := Kit.tex("brick", 1.5, Color(0.3, 0.26, 0.28), true, Color(0.6, 0.55, 0.62))
	# (The clothing store's block is drawn on to the block across the far end.)
	for b: Array in [[STORE, 4.4, brick], [GUN, 4.9, block], [STUDIO, 4.1, stucco], [[CLOTHES[0], END], 4.5, dark_brick]]:
		var s: Array = b[0]
		var h: float = b[1]
		Service.gb(p, n, s[0], s[1], -9.0, 0.0, 0.0, h, b[2])
		Service.gb(p, n, s[0] - 0.02, s[1] + 0.02, -0.25, 0.08, h, h + 0.16, Park.COPING)
		Service.gb(p, n, s[0] + 0.02, s[1] - 0.02, -8.8, -0.25, h, h + 0.04, Park.TAR)
	# Downspouts between them, a meter, conduit.
	for s: Array in [[10.3, 4.3], [20.7, 4.0], [28.8, 4.0], [39.6, 4.4]]:
		Service.gb(p, n, s[0] - 0.05, s[0] + 0.05, 0.0, 0.1, 0.12, s[1], Color(0.32, 0.33, 0.34))
	var meter := Kit.group(n, p.pt(9.3, 0.0))
	Kit.box(meter, Vector3(0.34, 0.5, 0.16), Vector3(0, 1.55, 0.08), Color(0.46, 0.48, 0.5))
	Kit.cyl(meter, 0.09, 0.08, Vector3(0, 1.6, 0.2), Color(0.75, 0.82, 0.85, 0.5), Vector3(90, 0, 0), 12)
	Kit.cyl(n, 0.03, 1.9, p.pt(9.3, 0.06, 2.75), Props.IRON, Vector3.ZERO, 6)


## The corner store's back: the roll door with its bay painted in front, the
## bumpers, a lamp; crates, the bale, its bins and bags.
static func _store(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	Alley.loading_door(p, n, STORE_DOOR, 0.0, 0.0, 2.0, 2.2, "RECEIVING", false)
	In.sconce(p, st, STORE_DOOR + 1.55, 0.0, 0.0, "cage", 2.55, In.WARM, 0.9)
	for s: float in [-1.0, 1.0]:
		Service.gb(p, n, STORE_DOOR + s * 1.32 - 0.11, STORE_DOOR + s * 1.32 + 0.11, 0.0, 0.14, 0.32, 0.72, Service.RUBBER)
	for k in 6:
		Service.gb(p, n, 3.5, 5.5, 0.9 + 0.42 * k, 0.9 + 0.42 * k + 0.12, 0.0, 0.006, PAINT)
	for u: float in [3.3, 5.7]:
		Service.gb(p, n, u - 0.04, u + 0.04, 0.3, 3.6, 0.0, 0.006, PAINT)
	Service.gb(p, n, 3.3, 5.7, 3.56, 3.64, 0.0, 0.006, PAINT)
	Park.ground_words(n, "NO PARKING", p.pt(STORE_DOOR, 4.0, 0.012), 0.26, Color(0.82, 0.7, 0.2), 0.0)
	Props.case_stack(p, st, 7.2, 0.45, 0.0, 2, 3, Color(0.2, 0.45, 0.25))
	Service.bale(p, st, 8.5, 0.5, 0.0)
	Service.wheelie_bin(p, st, 9.75, 0.45, 0.0, Color(0.18, 0.36, 0.22))
	Service.wheelie_bin(p, st, 2.3, 0.45, 0.0, Color(0.32, 0.34, 0.37))
	Alley.bags(p, st, 2.6, 1.15, 2, 3.0)
	Club.tags(p, st, 7.9, 0.0, 0.0, [["RATTZ", 0.0, 1.55, 0.26, -4.0]], 21.0)


## The gun store's back: the range, blank and taller; a lamp and a camera high on
## it, an air conditioner; the van along it (fading while it hides him), the
## driver's hand truck, the pallets at its end, the dumpster.
static func _gun(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	In.sconce(p, st, 18.6, 0.0, 0.0, "cage", 3.3, In.WARM, 1.0)
	var cam := Kit.group(n, p.pt(11.2, 0.0))
	Kit.box(cam, Vector3(0.08, 0.08, 0.3), Vector3(0, 3.9, 0.15), Service.DARK)
	Kit.bevel(cam, Vector3(0.16, 0.14, 0.34), Vector3(0, 3.82, 0.36), Color(0.86, 0.86, 0.84), 0.02, Vector3(-18, 0, 0))
	Service.ac_unit(p, n, 13.4, 0.0, 3.4)
	var fade := Street.car_fade(p, st)
	fade.add(Service.van(p, st, VAN[0], VAN[1], 90.0, Color(0.9, 0.9, 0.86), "PEN LUCY WHOLESALE"))
	# Its open back door stands off its back corner on the alley side: its floor too.
	p.block(12.1, 3.25, 13.0, 3.6)
	Service.hand_truck(p, st, 11.5, 2.7, 90.0)
	Service.pallets(p, st, 11.2, 0.56, 0.0, 5)
	Alley.dumpster(p, st, 19.45, 0.62, 0.0, Color(0.2, 0.32, 0.5), false, [], 4.0)
	Alley.bags(p, st, 20.2, 1.5, 2, 5.0)


## The studio's back: its steel door (the booth's) under a lamp, the control
## room's air conditioner, a crate by the door, tags.
static func _studio(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	Alley.back_door(p, n, STUDIO_DOOR, 0.0, 0.0)
	In.sconce(p, st, STUDIO_DOOR, 0.0, 0.0, "cage", 2.55, In.WARM, 0.9)
	Service.ac_unit(p, n, 27.4, 0.0, 2.7)
	var crate: Node3D = p.prop(st, 22.6, 0.4, 0.0, 0.36, 0.36)
	Park.crate(crate, Vector3.ZERO, 8.0, Color(0.15, 0.3, 0.6))
	Club.tags(p, st, 21.7, 0.0, 0.0, [["DRIZZO", 0.0, 2.2, 0.3, 3.0]], 22.0)
	Club.tags(p, st, 26.6, 0.0, 0.0, [["VEX 7", 0.0, 1.3, 0.24, -5.0]], 23.0)


## The clothing store's back: its steel door (the stock room's) under a lamp;
## pallets, two roll cages of stock waiting to go in, the bale, a dumpster at
## the end (somewhere to hide at this end too), a bin, bags, a bucket of sand
## for the smokers.
static func _clothes(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	Alley.back_door(p, n, CLOTHES_DOOR, 0.0, 0.0)
	In.sconce(p, st, CLOTHES_DOOR, 0.0, 0.0, "cage", 2.55, In.WARM, 0.9)
	Service.pallets(p, st, 29.85, 0.56, 0.0, 6)
	Service.cage(p, st, 34.0, 0.45, 0.0)
	Service.cage(p, st, 34.95, 0.5, 6.0, Color(0.6, 0.46, 0.4))
	Service.bale(p, st, 36.0, 0.5, 0.0)
	Alley.dumpster(p, st, 37.7, 0.62, 0.0, Color(0.22, 0.38, 0.26), true, [], 6.0)
	Service.wheelie_bin(p, st, 39.25, 0.45, 0.0, Color(0.2, 0.3, 0.6))
	Alley.bags(p, st, 35.5, 1.35, 3, 9.0)
	Props.bucket(p, st, 32.75, 0.35)
	Club.tags(p, st, 37.0, 0.0, 0.0, [["RATTZ", 0.0, 2.3, 0.26, 4.0]], 24.0)


# ------------------------------------------------------------------- the ends

## The mouth: a chain-link gate shut and chained across it, a lamp on the cross
## street beyond, the dark houses across that. The far end: the blank side of a
## taller block across it (a board fence there showed the dark beyond over it).
static func _ends(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	Service.gate(p, n, MOUTH - 0.05, 0.0, D + 0.6, 2.2)
	Props.street_lamp(p, st, -1.8, 6.5)
	var houses := Kit.tex("brick", 1.5, Color(0.28, 0.2, 0.2), true, Color(0.56, 0.48, 0.5))
	Service.gb(p, n, -22.0, -12.0, -8.0, 16.0, 0.0, 7.2, houses)
	for w: Array in [[-4.0, 1.2, true], [-4.0, 3.9, false], [1.0, 1.2, false], [1.0, 3.9, true], [6.0, 1.2, true], [9.5, 3.9, true]]:
		var look: Variant = Color(0.12, 0.13, 0.17)
		if w[2]:
			look = Kit.flat(Color(1.0, 0.84, 0.55), 0.7)
		Kit.box(n, Vector3(0.03, 1.3, 0.9), p.pt(-11.985, w[0], w[1] + 0.65), look)
	var end_brick := Kit.tex("brick", 1.5, Color(0.36, 0.3, 0.3), true, Color(0.62, 0.56, 0.58))
	Service.gb(p, n, END, END + 8.0, -9.0, 16.0, 0.0, 6.6, end_brick)
	Service.gb(p, n, END - 0.08, END + 0.2, -9.0, 16.0, 6.6, 6.76, Park.COPING)
	for w: Array in [[1.6, 3.4], [5.8, 3.4], [5.8, 0.6]]:
		Kit.box(n, Vector3(0.03, 1.1, 0.8), p.pt(END - 0.015, w[0], w[1] + 0.55), Color(0.12, 0.13, 0.17))
	Service.gb(p, n, END - 0.1, END, 2.9, 3.0, 0.12, 6.5, Color(0.32, 0.33, 0.34))


# ------------------------------------------------------------------- the sky

static func _sky(p: Node3D, st: int) -> void:
	var n: Node3D = p.node_of(st)
	Outdoor.moonlight(n, 0.22, Color(0.56, 0.6, 1.0))
	var glow := Outdoor.moonlight(n, 0.32, Color(1.0, 0.6, 0.42))
	glow.rotation_degrees = Vector3(-14, 64, 0)
	Outdoor.backdrop(n, p.pt(21.0, -40.0), [Color(1.0, 0.62, 0.3), Color(0.93, 0.4, 0.42), Color(0.34, 0.22, 0.5)], Vector3.INF, 9.0, 900.0, Vector2(1.0, -0.05))


# ------------------------------------------------------------------ the people

## The van's driver at its open back (to talk to); somebody in the gap behind
## the van, half out of sight; a singer waiting at the studio's back door, and
## a clerk from the clothing store on her break by its door (both to talk to).
## Names are the characters' own; the lines are placeholders.
static func _people(p: Node3D, st: int) -> void:
	p.person(st, "vic", 12.1, 4.6, {"name": "VIC", "face": "neutral", "talk": "talk_service_van.json"})
	p.person(st, "rell", 16.9, 0.85, {"name": "RELL", "face": "suspicious"})
	p.person(st, "nia", 23.3, 1.35, {"name": "NIA", "face": "happy", "talk": "talk_service_studio.json"})
	p.person(st, "kesha", 33.1, 1.3, {"name": "KESHA", "face": "content", "talk": "talk_service_break.json"})
