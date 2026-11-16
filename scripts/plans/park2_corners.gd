extends RefCounted
## Linden Square's corners (the civic worker's; built by plans/park2.gd): the
## parts of THE GREEN out of sight of the street. In the back-right, behind the
## chess tables and under the trees, the square's little brick public
## convenience, both doors padlocked, and the parks' tool shed, padlocked too,
## its window boarded, a barrow and sacks of leaves by it. Near them a gap broken
## in the right-hand railing, the hedge trodden through behind it and a line
## worn in the grass from it, and outside it the side pavement, walked up from
## the street in front (a room of its own: the railing is between, and the gap
## is the way through it). Behind the bandstand, on the brick ring, a crate to
## sit on, a cool box and cans. People: TRE and CHUY behind the bandstand, LIL
## keeping an eye on the gap, HUFF DADDY waiting for the convenience to open.
##
## Numbers are park2.gd's plan: u from the left railing, v from the back railing.
##
## Placeholders (all invented here): the room SIDE STREET; the lines in
## talk_square_bandstand.json, talk_square_gap.json and talk_square_toilets.json.
## Nothing here has words on it: the convenience's doors carry a man and a woman.

const Park := preload("res://scripts/props_park2.gd")
const Bits := preload("res://scripts/props_corners.gd")

const RIGHT := 32.0               # the right-hand railing
const GAP := [5.0, 6.4]           # the gap broken in it, along v (park2.gd leaves this run to here)


static func build(p: Node3D, st: int) -> void:
	p.room("SIDE STREET", st, RIGHT, 3.5, 34.4, 24.5, null, {"street": true})
	_gap(p, st)
	_back(p, st)
	_bandstand(p, st)
	_people(p, st)


## The right-hand railing's run near the back, with the gap broken in it (the
## gap is the way through between the square and the side pavement), and the
## grass trodden dead from the gap towards the right-hand path.
static func _gap(p: Node3D, st: int) -> void:
	p.fence(st, false, RIGHT, 0.3, 9.05, [GAP], 1.05, "rail", Park.IRON)
	Park.plinth(p, st, false, RIGHT, 0.3, GAP[0])
	Park.plinth(p, st, false, RIGHT, GAP[1], 9.05)
	Bits.broken_ends(p, st, RIGHT, GAP[0], GAP[1])
	var line := [[31.35, 5.7, 1.0, 0.75, 0.0], [30.35, 5.95, 1.5, 0.5, 14.0], [29.0, 6.45, 1.6, 0.48, 22.0],
			[27.8, 7.3, 1.6, 0.46, 40.0], [27.0, 8.35, 1.3, 0.42, 58.0]]
	for i in line.size():
		var w: Array = line[i]
		Bits.worn(p, st, w[0], w[1], w[2], w[3], w[4], i * 0.0015)


## Against the back railing between the trees: the shed behind the left-hand
## chess table, the convenience behind the right-hand one, the dark fir between
## them. The fir's boughs come down to the grass, so its foot is now floor
## nobody walks on (it was walked into before; between the shed and the
## convenience it would have been a nook out of the camera's sight).
static func _back(p: Node3D, st: int) -> void:
	Bits.shed(p, st, 22.6, 1.5)
	Bits.convenience(p, st, 28.0, 1.4)
	p.block(23.9, 0.3, 26.26, 2.56)
	Bits.barrow(p, st, 24.3, 3.3, 165.0)          # in front of the fir, its handles to the front
	Bits.sacks(p, st, 25.15, 3.05)


## Behind the bandstand on the brick ring (the side away from the gate).
static func _bandstand(p: Node3D, st: int) -> void:
	Bits.crate(p, st, 17.35, 7.65, 15.0)
	Bits.cool_box(p, st, 18.3, 7.95, -20.0)
	Bits.litter(p, st, 16.95, 7.85, 1)
	Bits.litter(p, st, 18.95, 7.3, 4)


## Open-eyed, three to talk to.
static func _people(p: Node3D, st: int) -> void:
	p.person(st, "tre", 17.95, 6.85, {"name": "TRE", "face": "smug", "talk": "talk_square_bandstand.json"})
	p.person(st, "chuy", 16.45, 7.15, {"name": "CHUY", "face": "content"})
	p.person(st, "lil", 30.45, 2.9, {"name": "LIL", "face": "focused", "talk": "talk_square_gap.json"})      # by the hedge's end, in front of the tree: from the side pavement his feet show through the gap (nearer it, they stood on the railing's top rail)
	p.person(st, "huff", 27.55, 3.15, {"name": "HUFF DADDY", "face": "bored", "talk": "talk_square_toilets.json"})
