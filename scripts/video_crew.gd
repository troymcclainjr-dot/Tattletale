extends RefCounted
## The entourage of a HARD music video (video.json's "style"): people backing
## him, not dancers. video_stage.gd places and dresses them through this, and
## video_take.gd poses them each frame (`pose`) after they have walked.
##
## Where they stand (`place`): three uneven depth bands worked out from the
## location's own floor, seen from the lens. Band 1 is one close associate just
## behind him to one side; band 2 is two or three people behind, at uneven
## gaps; band 3 is the rest: one with his back to a car near him if there is
## one with room (else further off behind), one crouched off to the side in
## front, near the camera. A spot is tried where the plan wants it, then in
## rings round it, then anywhere round him, until it is on the floor (outdoors:
## not through a shop front), clear of the props, the cars and everyone placed,
## off his walking line, not between the lens and any place on his line he may
## walk to (he would be hidden: someone in front stands out at the edge of the
## picture), with no post, pole or car between it and the lens, and
## not hidden behind anyone from the lens (nor hiding anyone, nor him). Nobody
## mirrors anybody: the bands are offset to one side picked by the seed, and
## every gap is different.
##
## How they stand (WAYS): each person has a way of standing (arms folded, hands
## at the pockets, arms hanging, crouched) with a watchful, unsmiling face, some
## at the lens and some past it, and a loop of their own: a list of moments
## [at, what, beats] over a period of their own, from a phase of their own, so at
## any moment about half of them are still. The moments: "dip" (a chin dip: his
## knees give a little and his eyes drop), "bob" (a dip on each beat), "rock"
## (a shoulder rock from foot to foot), "look" (a look to the side and back),
## "hand" (an arm comes up on the last beat of every other bar: the "answer"
## way's loop is kept in time with the bars for it). On the hook everyone
## dips together on the first and third beat of each bar, small.
##
## Their clothes are video.json's "hard" "wear": each their own, dark and mixed.

const HANG := [0.06, -0.06, 0.05, -0.05]       # arms (left angle, right angle, left bow, right bow: paper_card.gdshader's)
const FOLDED := [0.62, -0.62, 1.5, -1.5]
const POCKETS := [-0.16, 0.16, 0.65, -0.65]
const KNEES := [0.32, -0.32, 0.75, -0.75]       # crouched, his forearms on his knees
const WAYS := {
	"folded": {"arms": FOLDED, "face": "focused", "period": 6.0, "do": [[0.0, "dip", 0.7], [1.0, "dip", 0.7], [3.5, "look", 1.6]]},
	"rock": {"arms": POCKETS, "face": "neutral", "period": 9.0, "do": [[0.0, "rock", 4.0], [6.0, "dip", 0.7]]},
	"watch": {"arms": HANG, "face": "suspicious", "period": 11.0, "do": [[1.0, "look", 3.0], [5.0, "bob", 3.0]]},
	"answer": {"arms": POCKETS, "face": "neutral", "period": 8.0, "do": [[3.0, "hand", 1.0], [4.5, "dip", 0.7], [5.5, "bob", 2.0]]},
	"lean": {"arms": FOLDED, "face": "bored", "period": 13.0, "do": [[2.0, "look", 2.5], [6.0, "bob", 3.0], [10.0, "dip", 0.8]]},
	"crouch": {"arms": KNEES, "face": "neutral", "period": 7.0, "do": [[0.0, "bob", 3.0], [4.5, "look", 1.5]]},
}
## Who stands where, by how many there are: band, and the way they stand.
const PLAN := {
	1: [{"band": 1, "way": "folded"}],
	2: [{"band": 1, "way": "folded"}, {"band": 2, "way": "answer"}],
	3: [{"band": 1, "way": "folded"}, {"band": 2, "way": "answer"}, {"band": 3, "front": true, "way": "crouch"}],
	4: [{"band": 1, "way": "folded"}, {"band": 2, "way": "rock"}, {"band": 2, "way": "answer"}, {"band": 3, "front": true, "way": "crouch"}],
	5: [{"band": 1, "way": "folded"}, {"band": 2, "way": "rock"}, {"band": 2, "way": "answer"}, {"band": 3, "way": "lean"}, {"band": 3, "front": true, "way": "crouch"}],
	6: [{"band": 1, "way": "folded"}, {"band": 2, "way": "rock"}, {"band": 2, "way": "answer"}, {"band": 2, "way": "watch"}, {"band": 3, "way": "lean"}, {"band": 3, "front": true, "way": "crouch"}],
}
const GAP := 0.7              # metres between two people's middles, at least
const SEEN := 0.5             # metres: two people seen from the lens are at least this far apart across the picture (at the nearer one)
const SEEN_LEAD := 0.62       # ...and from him
const LINE := 0.6             # nobody stands this near his walking line (he walks along x to stay in the picture)
const DIP := 0.022            # a chin dip: his knees give this much of his height
const HOOK_DIP := 0.014       # the hook's dip, everyone together
const TILT := 0.09            # leaning on a car beside him: his card tips this far towards it, radians
const CROUCH := 0.14          # crouched: his feet come up the drawing this much of its height at most (people_flee.gd's LIFT)
const SQUASH := 0.08
const HALF := 0.62            # radians: half the width of the master's picture (video_cuts.gd's FOV, 44 high, at 16:9)
const THIN := 0.7           # metres: a prop narrower than this both ways is a post or a pole (clear_sight)
const RADIUS_Z := 0.26       # paper_actor.gd's RADIUS: how near a prop in front or behind he may stand

var people: Array = []        # for each of the crew, in order: {"band", "way", "front", "tilt", "crouch", "phase", "stretch", "look", "side", "looking", "face"}
var _side := 1.0              # the side of him the associate stands on (+1: right of the picture)


## Where each of `crew` (paper actors, already on the set's floor rules) stands,
## and how. Sets their positions; returns nothing. `stage` is video_stage.gd.
func place(stage: Node3D, crew: Array, seed_value: int, drift: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + 7
	_side = 1.0 if rng.randf() < 0.5 else -1.0
	var lens := Vector2(stage.lens.x, stage.lens.z)
	var him := Vector2(stage.mark.x, stage.mark.z)
	var deep := (him - lens).normalized()                    # away from the camera, past him
	var right := Vector2(-deep.y, deep.x)                    # to the right of the picture
	var plan: Array = PLAN.get(crew.size(), PLAN[6])
	var placed: Array = [stage.lead]
	var seconds := 0
	for i in crew.size():
		var npc: Node3D = crew[i]
		var row: Dictionary = plan[mini(i, plan.size() - 1)] if i < plan.size() else {"band": 3, "way": "watch"}
		var band := int(row["band"])
		var front := bool(row.get("front", false))
		var way := String(row["way"])
		var wants: Array = []                                # (depth past him, across) in metres, best first
		var lean := {}
		match band:
			1:                           # at his shoulder, just behind him
				wants = [Vector2(0.7, _side * 0.95), Vector2(0.8, _side * 1.25), Vector2(0.7, -_side * 0.95), Vector2(0.9, -_side * 1.3)]
			2:
				var rows := [Vector2(1.25, -_side * 0.9), Vector2(2.1, _side * 1.7), Vector2(1.6, -_side * 2.3), Vector2(2.6, _side * 2.9)]
				for k in rows.size():
					wants.append(rows[(seconds + k) % rows.size()])
				seconds += 1
			_:
				if front:
					wants = [Vector2(-2.0, -_side * (drift + 0.8)), Vector2(-1.6, _side * (drift + 1.0)), Vector2(-2.6, -_side * (drift + 1.2)), Vector2(-1.4, -_side * (drift + 1.5))]
				else:
					wants = [Vector2(3.6, -_side * 3.2), Vector2(3.2, _side * 3.6), Vector2(4.0, -_side * 1.6), Vector2(2.8, _side * 4.2)]
		var at := Vector2.INF
		if band == 3 and not front:      # against a car near him, if there is one with room
			for spot: Dictionary in _car_spots(stage, npc, him, deep, lens, right):
				if _ok(npc, spot["at"], placed, stage, lens, him, deep, drift, front):
					at = spot["at"]
					lean = spot
					break
		for want: Vector2 in wants:
			if at != Vector2.INF:
				break
			at = _fit(npc, him + deep * want.x + right * want.y, placed, stage, lens, him, deep, drift, front, false)
		if at == Vector2.INF:            # anywhere round him that fits, nearest the first spot wanted
			var grid: Array = []
			for dz in range(-12, 25):
				for dx in range(-20, 21):
					grid.append(Vector2(dz * 0.25, dx * 0.25))
			var first: Vector2 = wants[0]
			grid.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_to(first) < b.distance_to(first))
			for g: Vector2 in grid:
				var p: Vector2 = him + deep * g.x + right * g.y
				if _ok(npc, p, placed, stage, lens, him, deep, drift, front):
					at = p
					print("[shot] video: %s stands further from where his band wanted him (%.1f deep %.1f across)" % [npc.name, g.x, g.y])
					break
		if at == Vector2.INF:
			at = Vector2(npc.position.x, npc.position.z)
			print("[shot] video: no hard spot for %s: left where the row put him" % npc.name)
		npc.position = Vector3(at.x, 0.0, at.y)
		placed.append(npc)
		var tilt := 0.0
		if not lean.is_empty():
			tilt = -TILT * float(lean["car"])                      # his top towards the car (a card's rotation above zero tips it left)
		var across := (at - him).dot(right)
		var phase := rng.randf_range(0.0, 8.0)
		var stretch := rng.randf_range(0.9, 1.15)
		if way == "answer":              # his hand comes up on the last beat of a bar (WAYS: at 3 of 8), every other bar
			phase = 4.0 * float(rng.randi() % 2)
			stretch = 1.0
		people.append({"band": band, "way": way, "front": front, "tilt": tilt, "crouch": way == "crouch", "against": not lean.is_empty(),
			"phase": phase, "stretch": stretch,
			"side": -signf(across) if across != 0.0 else -_side,      # the way to look to see him
			"look": 0.0 if band == 1 or way in ["answer", "lean"] else (-signf(across) if way == "watch" else signf(across)),
			"looking": 99.0, "face": ""})
		if npc.face:
			npc.face.set_expression(String(WAYS[way]["face"]), true)
	_say_bands(stage, crew, lens, him, deep, right)


## Spots against a car near him (not in front of him), nearest him first: on
## the side of the car that faces the lens, just clear of it, so he stands with
## his back to it (upright: "car" 0); or, where that side is end-on to the lens
## (the car beside him in the picture), tipped towards it ("car" +1: it is on his
## right in the picture). Each {"at", "car"}.
func _car_spots(stage: Node3D, npc: Node3D, him: Vector2, deep: Vector2, lens: Vector2, right: Vector2) -> Array:
	var out: Array = []
	for c: Dictionary in stage.cars:
		var rect: Rect2 = c["rect"]
		var mid := rect.get_center()
		if (mid - him).dot(deep) < -0.5 or mid.distance_to(him) > 7.0:     # in front of him, or too far off
			continue
		var to_lens := (lens - mid).normalized()
		var sides := [[Vector2(0.0, 1.0), rect.end.y], [Vector2(0.0, -1.0), rect.position.y], [Vector2(1.0, 0.0), rect.end.x], [Vector2(-1.0, 0.0), rect.position.x]]
		sides.sort_custom(func(a: Array, b: Array) -> bool: return (a[0] as Vector2).dot(to_lens) > (b[0] as Vector2).dot(to_lens))
		var n: Vector2 = sides[0][0]
		var edge: float = sides[0][1]
		var clear: float = (RADIUS_Z if n.x == 0.0 else float(npc.reach)) + 0.06
		var beside := absf(n.dot(deep)) < 0.5                       # that side faces across the picture
		var car := 0.0
		if beside:
			car = 1.0 if n.dot(right) < 0.0 else -1.0
		for k in [0.0, -0.8, 0.8, -1.4, 1.4]:
			var p := Vector2.ZERO
			if n.x == 0.0:           # a long side (the car lies across x)
				p = Vector2(clampf(him.x + k, rect.position.x + 0.5, rect.end.x - 0.5), edge + n.y * clear)
			else:
				p = Vector2(edge + n.x * clear, clampf(him.y + k, rect.position.y + 0.5, rect.end.y - 0.5))
			if p.distance_to(him) > 1.8:
				out.append({"at": p, "car": car, "d": p.distance_to(him)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	return out


## Nothing that would cut him in two or hide him between the lens and this spot:
## a thin prop (a lamp post, a pole, a hydrant, a bin: under THIN across both
## ways; the props have no heights, and the wide ones, benches and planters,
## are low and only hide feet) or one of the video's cars. The last `skip`
## metres before the spot (what he stands against) are left out.
static func clear_sight(stage: Node3D, from: Vector2, p: Vector2, skip := 0.5) -> bool:
	var block: Array = []
	for prop: Rect2 in stage.obstacles:
		if not stage.low.has(prop) and prop.size.x < THIN and prop.size.y < THIN:
			block.append(prop.grow(0.12))
	for c: Dictionary in stage.cars:
		block.append((c["rect"] as Rect2).grow(0.05))
	var n := maxi(int(from.distance_to(p) / 0.15), 1)
	for k in range(1, n):
		var q := from.lerp(p, float(k) / n)
		if q.distance_to(p) < skip:
			break
		for r: Rect2 in block:
			if r.has_point(q):
				return false
	return true


## Not inside a building: the spot is in no room of the place, or in one of its
## outdoor ones (place.gd's street rooms), or in the room his mark is in. (The
## rooms' floors are all floor to stand on, and a spot behind the shop front is
## a spot inside the shop.)
static func _outdoors(stage: Node3D, p: Vector2) -> bool:
	var mark := Vector2(stage.mark.x, stage.mark.z)
	for r: Dictionary in stage.main._building.rooms:
		var box: Variant = r.get("rect", r.get("area"))      # place.gd's rooms have a "rect", building.gd's (the studio) an "area"
		if typeof(box) != TYPE_RECT2:
			continue
		var rect: Rect2 = box
		if rect.has_point(p) and float(r.get("cam_max_x", 99.0)) < 99.0 and not rect.has_point(mark):
			return false
	return true


## The nearest spot to `want` where he can stand by the rules above, or INF.
func _fit(npc: Node3D, want: Vector2, placed: Array, stage: Node3D, lens: Vector2, him: Vector2, deep: Vector2, drift: float, front: bool, exact: bool) -> Vector2:
	var tries: Array = [want]
	if not exact:
		for ring in range(1, 7):
			for k in 12:
				tries.append(want + Vector2.from_angle(TAU * (k + 0.5 * (ring % 2)) / 12.0) * ring * 0.15)
	for p: Vector2 in tries:
		if _ok(npc, p, placed, stage, lens, him, deep, drift, front):
			return p
	return Vector2.INF


func _ok(npc: Node3D, p: Vector2, placed: Array, stage: Node3D, lens: Vector2, him: Vector2, deep: Vector2, drift: float, front: bool) -> bool:
	if not npc.can_stand(p):
		return false
	if absf(p.y - him.y) < LINE and absf(p.x - him.x) < drift + 0.8:      # on his walking line
		return false
	if p.distance_to(lens) < 2.4 or (front and (p - him).dot(deep) > -0.9):
		return false
	var dp := (p - him).dot(deep)
	var far := maxf((him - lens).dot(deep), 1.0)
	if dp < -0.3 and absf((p - him).dot(Vector2(-deep.y, deep.x))) < drift * (far + dp) / far + 0.6:
		return false                 # nearer the lens than his line and inside the part of the picture he may walk across: he would be behind him
	var a := _angle(p, lens, deep)
	var d := (p - lens).dot(deep)
	if absf(a) > HALF - 0.3 / maxf(d, 0.5):
		return false                 # out of the master's picture while it is on his mark
	if stage.op and p.distance_to(Vector2(stage.op.position.x, stage.op.position.z)) < 1.2:
		return false
	if not clear_sight(stage, lens, p) or not _outdoors(stage, p):
		return false
	for other: Node3D in placed:
		var q := Vector2(other.position.x, other.position.z)
		if p.distance_to(q) < GAP:
			return false
		var dq := (q - lens).dot(deep)
		var need := (SEEN_LEAD if other == stage.lead else SEEN) / maxf(minf(d, dq), 0.5)
		if absf(a - _angle(q, lens, deep)) < need:
			return false
	return true


## How far across the picture a spot is from the lens, as an angle.
static func _angle(p: Vector2, lens: Vector2, deep: Vector2) -> float:
	var v := p - lens
	return atan2(v.dot(Vector2(-deep.y, deep.x)), v.dot(deep))


## Print where each band ended up (for the report and the checks).
func _say_bands(stage: Node3D, crew: Array, lens: Vector2, him: Vector2, deep: Vector2, right: Vector2) -> void:
	var out := PackedStringArray()
	for i in crew.size():
		var p := Vector2(crew[i].position.x, crew[i].position.z)
		out.append("%s band %d %s %.2f deep %.2f across%s" % [crew[i].name, people[i]["band"], people[i]["way"], (p - him).dot(deep), (p - him).dot(right),
			(", against a car, tipped" if people[i]["tilt"] != 0.0 else ", against a car") if people[i]["against"] else ""])
	print("[shot] video: the crew, hard: %s" % "; ".join(out))


## Dress each in their own clothes from video.json's "hard" "wear" (by drawing).
static func dress(main: Node3D, npc: Node3D, who: String, wear: Dictionary) -> void:
	if npc.has_wardrobe() and wear.has(who):
		npc.wear(main._outfit_of(wear[who]))


## Pose person `i` (after he has walked this frame, standing): his way, his loop
## at beat `b`, the hook's dip if `hook` is on. Returns what he is doing ("" still).
func pose(i: int, npc: Node3D, b: float) -> String:
	var who: Dictionary = people[i]
	var way: Dictionary = WAYS[who["way"]]
	var arms: Array = (way["arms"] as Array).duplicate()
	var t := fposmod(b + float(who["phase"]), float(way["period"]) * float(who["stretch"])) / float(who["stretch"])
	var drop := 0.0
	var rock := 0.0
	var doing := ""
	var look := float(who["look"])
	var face := String(way["face"])
	for m: Array in way["do"]:
		var at := float(m[0])
		var length := float(m[2])
		if t < at or t >= at + length:
			continue
		var u := (t - at) / length
		doing = String(m[1])
		match doing:
			"dip":
				drop = DIP * sin(PI * u)
			"bob":
				drop = DIP * 0.8 * pow(maxf(sin(PI * fposmod(t - at, 1.0)), 0.0), 2.0)
			"rock":
				rock = 0.045 * sin(PI * (t - at))
				arms[0] += 0.06 * sin(PI * (t - at))
				arms[1] += 0.06 * sin(PI * (t - at))
			"look":
				look = float(who["side"]) if float(who["look"]) == 0.0 else -float(who["look"])
			"hand":            # the arm on the far side from him comes up and goes down
				var k := smoothstep(0.0, 0.18, u) * (1.0 - smoothstep(0.55, 1.0, u))
				if float(who["side"]) > 0.0:      # he is to the right: the left arm answers
					arms[0] = lerpf(arms[0], -1.45, k)
					arms[2] = lerpf(arms[2], -0.45, k)
				else:
					arms[1] = lerpf(arms[1], 1.45, k)
					arms[3] = lerpf(arms[3], 0.45, k)
	if drop > DIP * 0.45:
		face = "bored"                    # his eyes drop with his chin
	var lift := 0.0
	if who["crouch"]:
		var hip := float(npc._mat.get_shader_parameter("hip_v"))
		var knee := float(npc._mat.get_shader_parameter("knee_v"))
		lift = minf(CROUCH, 0.8 * maxf(knee - hip, 0.0))
		npc._pivot.scale = Vector3(1.0 + 0.5 * SQUASH, 1.0 - SQUASH, 1.0)
	var names := ["arm_l_angle", "arm_r_angle", "arm_l_curl", "arm_r_curl"]
	for k in 4:
		npc._put(names[k], float(arms[k]))
	npc._put("lift_l", lift + drop)
	npc._put("lift_r", lift + drop)
	npc._card.position.y = -(lift + drop) * float(npc.height)
	npc._card.rotation.z = float(who["tilt"]) + rock
	if npc.face:
		if look != float(who["looking"]):
			who["looking"] = look
			npc.face.look(look)
		if face != who["face"]:
			who["face"] = face
			npc.face.set_expression(face)
	return doing


## Everyone's small dip together on the hook: added over whatever they are doing.
static func hook_dip(npc: Node3D, b: float) -> void:
	var u := fposmod(b, 2.0)
	if u >= 0.6:
		return
	var drop := HOOK_DIP * sin(PI * u / 0.6)
	npc._put("lift_l", float(npc._mat.get_shader_parameter("lift_l")) + drop)
	npc._put("lift_r", float(npc._mat.get_shader_parameter("lift_r")) + drop)
	npc._card.position.y -= drop * float(npc.height)


## Put him back as the plain card left him (out of a crouch).
static func unpose(npc: Node3D) -> void:
	npc._pivot.scale = Vector3.ONE
	npc._card.rotation.z = 0.0
