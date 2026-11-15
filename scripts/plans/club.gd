extends RefCounted
## The club: THE LOWDOWN (a placeholder name), a low-rent club on a night
## street. One storey, 12 x 16 m inside, two bands from the street back:
##
##   the main room              the bar down the left wall, the DJ at the back with
##                              the dance floor in front of him under a light rig,
##                              booths down the right wall, the pool table by the
##                              front window, a dead arcade machine, the jukebox
##   toilets | back hall | office
##                              the stalls (where business is done); the hall to
##                              the back door (E there: out into the back lot,
##                              plans/alley.gd); the manager's office, its safe
##
## Out front: the dead sign, a shutter half down over the blacked-out window, the
## rope and the doorman's stool. Numbers are metres on the plan (see place.gd):
## u from the left wall, v from the back wall; the street is at v = 16. Every
## name, sign and line here is a placeholder.

const Props := preload("res://scripts/props.gd")
const In := preload("res://scripts/props_in.gd")
const Club := preload("res://scripts/props_club.gd")
const F := 16.075            # the club's street face
const DOOR := {"a": 5.0, "b": 6.1, "head": 2.15}
const WINDOW := {"a": 7.2, "b": 10.4, "kind": "window", "sill": 0.9, "head": 2.3}
const TO_TOILETS := {"a": 2.6, "b": 3.45, "hinge": "a", "swing": -1}
const TO_HALL := {"a": 4.9, "b": 5.75, "hinge": "b", "swing": -1}
const TO_OFFICE := {"a": 2.3, "b": 3.2, "hinge": "a", "swing": 1}
## What the people from the neighbourhood wear here (main.gd's _people: "wear"
## dresses them for the place, the same every day): not what they wear outside.
const BLACK := "#28282c"


static func build(p: Node3D) -> void:
	p.setup("THE LOWDOWN", 12.0, 16.0)
	p.ambient = 0.13
	p.sun_energy = 0.0
	var facade := Kit.tex("brick", 1.5, Color(0.13, 0.12, 0.13), true, Color(0.3, 0.27, 0.31))
	var block := Kit.tex("painted_block", 1.2, Color(0.2, 0.18, 0.2), true, Color(0.36, 0.33, 0.38))
	var carpet := Kit.tex("carpet", 1.6, Color(0.25, 0.1, 0.14), true, Color(0.42, 0.26, 0.34))
	var tiles := Kit.tex("in_tile", 0.6, Color(0.62, 0.62, 0.58), true, Color(0.66, 0.66, 0.58))
	var lino := Kit.tex("lino", 1.2, Color(0.4, 0.4, 0.42), true, Color(0.5, 0.48, 0.47))
	var office_floor := Kit.tex("lino", 1.2, Color(0.4, 0.4, 0.34), true, Color(0.62, 0.6, 0.5))
	var steel := Color(0.36, 0.4, 0.44)

	var st: int = p.street(-4.0, 16.0)
	var b1: int = p.band()
	var b2: int = p.band()
	p.arrive = p.pt(10.3, 17.3)

	p.room("MAIN ROOM", b1, 0, 6, 12, 16, carpet)
	p.room("TOILETS", b2, 0, 0, 4.2, 6, tiles, {"light": Color(0.8, 1.0, 0.78), "energy": 0.32})
	p.room("BACK HALL", b2, 4.2, 0, 7.0, 6, lino)
	p.room("OFFICE", b2, 7.0, 0, 12, 6, office_floor)

	var door := DOOR.duplicate()
	door.merge({"colour": Color(0.4, 0.06, 0.08), "frame": Color(0.1, 0.1, 0.11), "name": "FRONT DOOR"})
	var window := WINDOW.duplicate()
	window.merge({"pane": Color(0.03, 0.03, 0.04, 0.96), "frame": Color(0.1, 0.1, 0.11)})
	var front: Node3D = p.cross(b1, 16.0, 0, 12, facade, [door, window], {"h": 4.2})
	p.side(b1, 0.0, 6, 16, facade)
	p.side(b1, 12.0, 6, 16, facade)
	var toilets := TO_TOILETS.duplicate()
	toilets.merge({"colour": Color(0.3, 0.32, 0.36), "name": "TOILETS"})
	var hall := TO_HALL.duplicate()
	hall.merge({"colour": steel, "name": "STAFF ONLY"})
	p.cross(b2, 6.0, 0, 12, block, [toilets, hall])
	p.side(b2, 0.0, 0, 6, facade)
	p.side(b2, 4.2, 0, 6, block)
	var office := TO_OFFICE.duplicate()
	office.merge({"colour": Color(0.42, 0.3, 0.2), "name": "OFFICE"})
	p.side(b2, 7.0, 0, 6, block, [office])
	p.side(b2, 12.0, 0, 6, facade)
	p.cross(b2, 0.0, 0, 12, facade, [], {"back": true})

	_street(p, st, front)
	_main(p, b1)
	_back(p, b2)
	_dress(p, b1, b2)
	_people(p, st, b1, b2)


## The front: black brick with the dead sign over the door, a caged lamp, the
## window blacked out behind a shutter half down and tagged, flyers pasted up
## left of the door; the rope and the doorman's stool on the pavement. A boarded
## house on the left, a lit one on the right, a street lamp.
static func _street(p: Node3D, st: int, front: Node3D) -> void:
	var n: Node3D = p.node_of(st)
	var coping := Color(0.3, 0.29, 0.3)
	p.slab(front, true, 16.0, -0.05, 12.05, 4.2, 4.32, 0.3, coping)
	for run: Array in [[-0.05, 4.9], [6.2, 12.05]]:          # a black plinth, either side of the door, its top off the neighbours' sills
		p.slab(front, true, 16.12, run[0], run[1], 0.0, 0.3, 0.1, Color(0.18, 0.17, 0.18))
	Club.dead_sign(p, front, 5.55, F, 3.05, 4.4, "THE LOWDOWN", "COCKTAILS  -  DJ NIGHTLY", Color(1.0, 0.3, 0.65))
	In.sconce(p, front, 5.55, F, 0.0, "cage", 2.45, In.WARM, 0.7)
	Club.shutter(p, front, F, WINDOW["a"], WINDOW["b"], 1.45, WINDOW["head"])
	Club.tags(p, front, 8.8, F + 0.137, 0.0, [["MIZZLE", -0.6, 1.95, 0.24, 6.0], ["GRIMLO", 0.8, 1.65, 0.18, -4.0]], 3.0)
	Club.flyers(p, front, 3.0, F, 0.0, 2.6, 1.3, 0.8, 14)
	Kit.box(front, Vector3(0.5, 0.36, 0.02), p.pt(6.75, F + 0.01, 1.55), Props.PAPER)
	Props.words(front, "NO HATS\nNO HOODS\nID REQUIRED", p.pt(6.75, F + 0.021, 1.55), 0.07, Color(0.15, 0.15, 0.2), 0.0, false)
	var old_brick := Kit.tex("brick", 1.5, Color(0.4, 0.22, 0.2), true, Color(0.62, 0.58, 0.62))
	Props.rowhouse(p, n, -5.0, 16.0, old_brick, true)
	Props.rowhouse(p, n, 12.0, 16.0, old_brick, false, true)
	Props.rowhouse(p, n, 17.0, 16.0, old_brick, true)
	Props.street_lamp(p, st, 0.6, 18.05)
	Props.bin(p, st, 11.5, 16.45)
	Club.rope(p, st, [6.7, 7.9, 9.1], 16.95)
	Club.tall_stool(p, st, 4.1, 16.4)
	Club.litter(p, st, 7.2, 16.55, 4.4, 0.6, 7, 7.0)


## The main room.
static func _main(p: Node3D, b: int) -> void:
	var n: Node3D = p.node_of(b)
	# The bar down the left wall, the back bar behind it, the stools.
	Club.back_bar(p, b, 0.325, 12.1, 90.0, 6.4)
	Club.bar(p, b, 2.18, 12.36, 90.0, 7.12)
	var v := 9.4
	for i in 6:
		if i != 3:                 # a gap at the bar, for someone standing
			Club.stool(p, b, 2.75, v, i == 1 or i == 4)
		v += 0.92
	# The DJ against the back wall, speakers either side, the dance floor in front
	# of him under the rig.
	Club.dj_booth(p, b, 8.4, 7.0, 0.0, 2.2)
	Props.speaker(p, b, 6.8, 6.3, 0.0, 1.5)
	Props.speaker(p, b, 10.0, 6.3, 0.0, 1.5)
	In.mat(p, b, 7.6, 9.9, 4.6, 3.4, Kit.tex("in_check", 1.2, Color(0.5, 0.5, 0.52), true, Color(0.55, 0.53, 0.58)), Color(0.6, 0.62, 0.66))
	Club.light_rig(p, b, 5.6, 9.6, 9.9, 2.62, [Color(1.0, 0.2, 0.7), Color(0.25, 0.4, 1.0), Color(1.0, 0.6, 0.15)])
	# Booths down the right wall.
	for at: float in [6.45, 9.3]:          # the seats run 2 cm into the wall: built in
		Club.booth_seat(p, b, 11.275, at, 0.0, 1.34, 1)
		Club.booth_table(p, b, 11.35, at + 0.75, 0.0, 1.1, 0.7)
		Club.booth_seat(p, b, 11.275, at + 1.5, 180.0, 1.34, 2 if at > 7.0 else 0)
	# By the front: the pool table under the window, the dead arcade machine, the jukebox.
	Club.pool_table(p, b, 8.4, 13.9, 0.0)
	Club.arcade(p, b, 11.45, 15.4, 180.0)
	Club.jukebox(p, b, 3.7, 15.6, 180.0)
	# Lamps over the bar; the dropped ceiling, stained, a tile gone.
	for at: float in [9.6, 12.2, 14.6]:
		In.pendant(p, b, 1.25, at, 2.05, Color(0.55, 0.06, 0.08), "cone", In.WARM, 0.6)
	Club.ceiling(p, b, 0.0, 6.0, 12.0, 16.0, 2.89, [[1.2, 10.0], [3.0, 13.6], [9.6, 7.6], [10.2, 8.2], [6.0, 14.8], [10.8, 12.4]], [4.2, 11.2])
	# Sticky patches, cable taped across the floor, a mop bucket left by the toilets.
	for s: Array in [[4.6, 12.6, 0.9, 0.5], [3.4, 9.0, 0.6, 0.45], [6.1, 14.6, 0.7, 0.4]]:
		In.mat(p, b, s[0], s[1], s[2], s[3], Color(0.16, 0.08, 0.1))
	Kit.box(n, Vector3(0.05, 0.004, 1.6), p.pt(7.0, 7.9, 0.002), Club.TAPE, Vector3(0, 12, 0))
	Props.bucket(p, b, 3.9, 6.55)
	# What has been dropped and not swept up.
	Club.litter(p, b, 3.25, 12.2, 0.7, 5.6, 8, 1.0)
	Club.litter(p, b, 10.3, 8.75, 0.5, 3.4, 4, 2.0)
	Club.litter(p, b, 5.2, 11.4, 0.9, 1.6, 3, 3.0)
	Club.litter(p, b, 5.0, 15.1, 1.6, 0.8, 4, 4.0)


## The back: the toilets (two stalls, the basins, the dryer), the hall to the
## back door (empties, a keg, the payphone, the fuse box), the office (desk,
## safe, files, a couch).
static func _back(p: Node3D, b: int) -> void:
	Club.stalls(p, b, 0.075, 0.075, 2, 1.0, 1.5)
	for at: float in [3.0, 4.1]:
		Props.basin(p, b, 3.91, at, 270.0)
	Club.hand_dryer(p, b, 4.116, 5.0, 270.0)       # things on a dressed wall go on its skin (In.SKIN off its face)
	Props.bin(p, b, 3.85, 1.9)
	# The hall.
	Club.fire_door(p, b, 5.6, 0.084, 0.0)
	p.use_point(b, "BACK DOOR", 5.6, 0.75, "goto:alley", 1.1, 2.0)
	Props.case_stack(p, b, 4.75, 2.6, 90.0, 2, 2, Color(0.2, 0.3, 0.55))
	Club.keg(p, b, 6.6, 1.0)
	Club.keg(p, b, 6.6, 1.55)
	Props.payphone(p, b, 4.284, 4.4, 90.0)
	Club.fuse_box(p, b, 6.916, 4.6, 270.0)
	Props.bucket(p, b, 6.5, 5.3)
	Club.litter(p, b, 3.1, 3.4, 0.9, 2.2, 5, 5.0)
	Club.litter(p, b, 5.7, 3.6, 0.9, 1.8, 3, 6.0)
	# The office.
	Props.desk(p, b, 9.4, 1.0, 0.0, Props.WOOD_DARK, 2)
	Props.safe(p, b, 11.55, 0.4, 0.0)
	Props.files(p, b, 7.75, 0.4, 0.0, 2)
	Props.couch(p, b, 11.47, 3.7, 270.0, 1.9, Color(0.3, 0.22, 0.16))


## The rooms' walls and floors. The main room: cheap dark panelling to a red
## rail, black over it. The toilets: grimy tile to shoulder height, green paint,
## tags. The hall: grey block. The office: brown panelling, a calendar.
static func _dress(p: Node3D, b1: int, b2: int) -> void:
	var black := Color(0.09, 0.08, 0.1)
	var red := Color(0.5, 0.06, 0.09)
	var main := {"lower": Kit.tex("wood_panel", 1.2, Color(0.25, 0.15, 0.1), true, Color(0.36, 0.25, 0.22)),
			"upper": Kit.tex("painted_block", 1.2, Color(0.14, 0.11, 0.16), true, Color(0.22, 0.17, 0.26)),
			"dado": red, "dado_y": 1.15, "skirt": black, "skirt_h": 0.1}
	In.room_walls(p, b1, 0.0, 6.0, 12.0, 16.0, main, [TO_TOILETS, TO_HALL], [], [])
	In.border(p, b1, 0.0, 6.0, 12.0, 16.0, black, 0.18)
	Club.flyers(p, b1, 4.3, 6.084, 0.0, 0.9, 0.8, 1.35, 7)
	Club.flyers(p, b1, 11.916, 13.0, 270.0, 1.4, 0.9, 1.3, 8)
	Props.poster(p, b1, 6.2, 6.08, 0.0, 0.5, 0.7, Color(0.85, 0.35, 0.6), "", 1.75)
	In.sconce(p, b1, 5.325, 6.075, 0.0, "exit", 2.35)
	var toilet := {"lower": Kit.tex("in_tile", 0.3, Color(0.7, 0.72, 0.66), true, Color(0.72, 0.74, 0.64)),
			"upper": Kit.tex("painted_block", 1.2, Color(0.5, 0.58, 0.5), true, Color(0.6, 0.68, 0.58)),
			"dado": Color(0.25, 0.3, 0.26), "dado_y": 1.6}
	In.room_walls(p, b2, 0.0, 0.0, 4.2, 6.0, toilet, [], [], [])
	Club.tags(p, b2, 0.084, 3.6, 90.0, [["TEKKA", -0.6, 1.9, 0.2, 4.0], ["VORPO", 0.7, 2.25, 0.14, -8.0], ["OOKS 4 LIFE", 0.2, 0.9, 0.1, 2.0]], 7.0)
	var hall := {"lower": Kit.tex("painted_block", 1.2, Color(0.4, 0.4, 0.42), true, Color(0.52, 0.52, 0.55)),
			"dado": Color(0.2, 0.2, 0.22), "dado_y": 1.2, "skirt": Color(0.2, 0.2, 0.22), "skirt_h": 0.1}
	In.room_walls(p, b2, 4.2, 0.0, 7.0, 6.0, hall, [], [], [TO_OFFICE])
	Club.flyers(p, b2, 4.284, 2.4, 90.0, 1.0, 0.8, 1.2, 6)
	In.pendant(p, b2, 6.0, 3.2, 2.25, Color(0.3, 0.3, 0.3), "bulb", In.WARM, 0.5)      # (right of the camera's way to the back door's word)
	var office := {"lower": Kit.tex("wood_panel", 1.0, Color(0.35, 0.22, 0.14), true, Color(0.5, 0.36, 0.26)),
			"upper": Kit.tex("wood_panel", 1.0, Color(0.35, 0.22, 0.14), true, Color(0.5, 0.36, 0.26)),
			"dado": Color(0.25, 0.16, 0.1), "skirt": Color(0.2, 0.13, 0.08)}
	In.room_walls(p, b2, 7.0, 0.0, 12.0, 6.0, office, [], [TO_OFFICE], [])
	Props.poster(p, b2, 8.3, 0.08, 0.0, 0.45, 0.62, Color(0.9, 0.85, 0.75), "", 1.65)
	In.pendant(p, b2, 9.4, 2.4, 2.2, Color(0.2, 0.36, 0.25), "cone", In.WARM, 0.45)


## Who is here (names are placeholders; the regulars wear what they wear out):
## the doorman out front; the bartender behind the bar; the DJ and two dancing in
## front of him; two drinking; the seller in the toilets.
static func _people(p: Node3D, st: int, b1: int, b2: int) -> void:
	p.person(st, "dee", 4.75, 16.7, {"name": "BIG DEE", "face": "neutral", "talk": "talk_club_door.json",
			"wear": {"hat": {"item": ""}, "jacket": {"item": "puffer", "colour": BLACK},
				"shirt": {"item": "tee", "colour": BLACK}, "trousers": {"item": "jeans", "colour": BLACK},
				"shoes": {"item": "boots", "colour": BLACK}}})
	p.person(b1, "kesha", 1.2, 11.6, {"name": "KESHA", "face": "neutral", "talk": "talk_club_bar.json",
			"roam": [0.575, 8.6, 1.85, 15.9], "speed": 0.55})
	p.person(b1, "doc", 8.4, 6.38, {"name": "DOC DRAY", "face": "happy", "dance": true, "beat": 4.0,
			"wear": {"hat": {"item": "cap", "colour": "#c42828"}, "jacket": {"item": ""},
				"shirt": {"item": "jersey", "colour": "#c8aa28"}, "trousers": {"item": "baggy", "colour": BLACK},
				"shoes": {"item": "hightops", "colour": "#c42828"}}})
	p.person(b1, "nia", 6.6, 9.5, {"name": "NIA", "face": "happy", "dance": true, "beat": 0.0})
	p.person(b1, "huff", 8.6, 10.5, {"name": "HUFF DADDY", "face": "happy", "dance": true, "beat": 8.0,
			"wear": {"hat": {"item": "cap", "colour": "#e6e6e2"}, "jacket": {"item": ""},
				"shirt": {"item": "tee", "colour": "#285aaa"}, "trousers": {"item": "track", "colour": BLACK},
				"shoes": {"item": "sneakers", "colour": "#ececE8"}}})
	p.person(b1, "snoozy", 2.98, 12.16, {"name": "SNOOZY D", "face": "neutral",
			"wear": {"hat": {"item": "beanie", "colour": "#d67828"}, "jacket": {"item": "hoodie", "colour": "#96969c"},
				"trousers": {"item": "jeans", "colour": BLACK}, "shoes": {"item": "sneakers", "colour": "#ececE8"}}})
	p.person(b1, "chuy", 10.15, 10.05, {"name": "CHUY", "face": "suspicious",
			"wear": {"hat": {"item": "cap", "colour": "#284696"}, "jacket": {"item": "flannel", "colour": "#3c6e3c"},
				"shirt": {"item": "tee", "colour": BLACK}, "trousers": {"item": "jeans", "colour": "#32508c"},
				"shoes": {"item": "boots", "colour": "#6e4628"}}})
	p.person(b2, "vic", 2.6, 2.6, {"name": "VIC", "face": "suspicious"})
