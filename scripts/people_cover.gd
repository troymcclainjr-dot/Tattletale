extends RefCounted
## Where the frightened hide (combat_people.gd): a spot out of the shooter's sight that they can run to, found
## from the place itself (its walk areas, its props, its meshes), never placed by hand, so a place built later has
## hiding places too.
##
## The floor someone may stand on (the place's walk areas: its rooms, its open doorways; less its props, grown by
## his size as paper_actor.gd grows them) is laid on a grid of CELL squares, once for each place, size of person
## and set of open doors. From where he stands the grid is flooded: the squares he can walk to, and how far each
## is, never passing near the shooter. A spot worth trying is a square beside something he cannot walk through (a
## counter, a car, a wall's corner, a doorway's frame) that lies between it and the shooter on the grid, or one in
## a part of the place the camera has cut away (a band nearer the street: he has gone out through a door towards
## us, and the walls between are there for him, if not for the camera). The likeliest are tried first: far from
## the shooter, not far to run, close behind what covers them (or in a part cut away: surely hidden), not where
## someone else is hiding, and not beside a spot already found to be in sight. A spot is hidden when every line
## from the shooter's eyes to where he would be crouching there (his face, its sides, his middle; the top of his
## hair may show) runs into something solid (combat_world.gd's trace: glass, chain link and what cannot be seen do
## not hide him; nor does a door, which someone may open), and so do the lines to him a little (MARGIN) to either
## side of it, nearer the shooter and further away. Where nothing hides him, the search gives the square furthest
## from the shooter he can run to (fled: he crouches there, in sight), if that is RUN_OFF further from him than he
## is.
##
## The work is spread over frames: a Search is made, stepped each frame until it is done (combat_people.gd gives
## all of them BUDGET microseconds a frame between them), and then holds its way there, or none.

const CELL := 0.2                # metres: the floor's squares
const RADIUS := 0.26             # paper_actor.gd's: props are grown this much front and back for someone's middle
const FAR := 16.0                # metres: no further than this to run, walking round things
const NEAR_SHOOTER := 2.5        # metres: never a spot nearer the shooter than this
const PASS := 1.3                # metres: never a way that passes nearer him than this (unless he starts nearer)
const CLAIM := 0.8               # metres: two people do not hide this close together
const TRIES := 48                # spots looked at from the shooter's eyes, at most, before giving up
const GLANCES := 400             # spots given a short look first (is anything near, as high as his face?), at most
const LOOK := 2.0                # metres: something solid this near a spot, on the shooter's side, makes it worth trying
const SIDE := 0.17               # metres: either side of his head, looked at too
const EYE := 0.92                # the shooter's eyes, of his height
const BUDGET := 3500             # microseconds of searching in a frame, for everyone
const CUT_AWAY := 3.0            # a spot in a part of the place the camera has cut away scores this much (it is surely hidden)
const SPREAD := 0.4              # metres: once a spot is found to be in sight, the spots this near it are not tried
const IN_THE_WAY := 0.6          # metres: a way does not pass this near someone standing still (crouched, held up): more
                                 # than paper_actor.gd's 2 RADIUS, inside which he blocks a step towards him
const MARGIN := 0.15             # metres: a spot is hidden this far to either side of it, nearer the shooter and further away
                                 # too (he may stop that far from it: people_flee.gd's ARRIVE)
const RUN_OFF := 3.0             # metres: with nowhere to hide, he runs where he is at least this much further from the shooter
const RUN_COST := 0.3            # ...the furthest he can get, less this much for each metre of running there

static var _grids := {}


## The floor of a place for someone of reach `reach`, on squares.
class Grid:
	var x0 := 0.0
	var z0 := 0.0
	var nx := 0
	var nz := 0
	var open := PackedByteArray()       # 1: his middle may be here
	var edge := PackedByteArray()       # 1: open, beside a square that is not; 2: open, not; 0: not worked out yet
	var room := PackedInt32Array()      # the room each square is in (the place's `rooms`), -1 for none (a doorway), -2 not worked out yet
	var rects: Array = []               # each room's floor (Rect2)
	var snap := {}                      # square: where to stand in it, when not its middle (a narrow doorway)
	var door_at := {}                   # square: the door whose doorway it is in (shut ones too: he opens it)
	var props: Array = []               # the props, grown for his size (Rect2): no straight way goes through one

	## Is square i open and beside a square that is not (something to hide behind)?
	func is_edge(i: int) -> bool:
		if edge[i] == 0:
			edge[i] = 2
			var ix := i % nx
			var iz := i / nx
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var x := ix + dx
					var z := iz + dz
					if x < 0 or z < 0 or x >= nx or z >= nz or open[z * nx + x] == 0:
						edge[i] = 1
		return edge[i] == 1

	## The room square i is in, -1 for none.
	func room_of(i: int) -> int:
		if room[i] == -2:
			room[i] = -1
			var p := middle(i)
			for ri in rects.size():
				if (rects[ri] as Rect2).has_point(p):
					room[i] = ri
					break
		return room[i]

	func at(p: Vector2) -> int:
		var ix := floori((p.x - x0) / CELL)
		var iz := floori((p.y - z0) / CELL)
		if ix < 0 or iz < 0 or ix >= nx or iz >= nz:
			return -1
		return iz * nx + ix

	func middle(i: int) -> Vector2:
		if snap.has(i):
			return snap[i]
		return Vector2(x0 + (float(i % nx) + 0.5) * CELL, z0 + (float(i / nx) + 0.5) * CELL)

	func is_open(i: int) -> bool:
		return i >= 0 and open[i] == 1

	## The nearest open square to `p` (within a metre), or -1.
	func nearest(p: Vector2) -> int:
		var i := at(p)
		if is_open(i):
			return i
		var best := -1
		var gap := INF
		for dz in range(-5, 6):
			for dx in range(-5, 6):
				var j := at(p + Vector2(dx, dz) * CELL)
				if is_open(j) and middle(j).distance_to(p) < gap:
					gap = middle(j).distance_to(p)
					best = j
		return best


## A search from one square: for a hiding place out of the shooter's sight (goal -1), or for the way to `goal`.
class Search:
	var g: Grid
	var start := -1
	var goal := -1
	var from_spot := Vector2.ZERO       # where he stands (the way starts here, not at his square's middle)
	var shooter := Vector2.ZERO
	var eye := Vector3.ZERO
	var keep_off: Array = []            # spots (Vector2) taken by others, or where he has been seen
	var blocked: Array = []             # where others stand still (hiding, cowering, held up): no way through them
	var tall := 1.4                     # metres: how tall he is crouched
	var floor_y := 0.0
	var world: RefCounted               # combat_world.gd of the place
	var doors := {}                     # the place's doors (node: true): no door counts as hiding him (it may be opened)
	var shown: Callable                 # room index -> bool: is that part of the place on show
	var done := false
	var found := -1                     # the square he goes to, or -1 (none: he cowers where he is)
	var fled := false                   # found is no hiding place, only as far from the shooter as he can get
	var path := PackedVector2Array()
	var tried := 0
	var glanced := 0                    # spots given the short look (_near_cover)
	var usec := 0                       # time it has taken, all told
	var _stage := 0
	var _dist := PackedInt32Array()
	var _from := PackedInt32Array()
	var _queue := PackedInt32Array()
	var _head := 0
	var _scored := 0
	var _order: Array = []              # Vector2(-score, square), best first once sorted
	var _at := 0
	var _missed := PackedByteArray()    # 1: near a spot he would be seen at
	var _away := -1                     # for want of a hiding place: the square furthest from the shooter, less the running
	var _away_score := -INF
	var _pass := -1.0                   # metres: no way passes nearer the shooter than this (-1: no such rule)

	## Work on it until the clock passes `until` (Time.get_ticks_usec). True once it is done.
	func step(until: int) -> bool:
		if done:
			return true
		var began := Time.get_ticks_usec()
		var finished := false
		match _stage:
			0:
				finished = _flood(until)
			1:
				finished = _score(until)
			2:
				finished = _try(until)
		if finished:
			_stage += 1
			if _stage == 1 and goal >= 0:
				found = goal if _dist[goal] >= 0 else -1
				_stage = 3
			if _stage == 3:
				_make_path()
				done = true
		usec += Time.get_ticks_usec() - began
		return done

	func _flood(until: int) -> bool:
		var n := g.nx * g.nz
		if _dist.is_empty():
			_dist.resize(n)
			_dist.fill(-1)
			_from.resize(n)
			_from.fill(-1)
			_queue = PackedInt32Array([start])
			_dist[start] = 0
		var far := int(FAR / CELL)
		var pass_gap := minf(PASS, g.middle(start).distance_to(shooter) - 0.1) if goal < 0 else -1.0
		_pass = pass_gap
		var steps := PackedInt32Array([-1, 1, -g.nx, g.nx])
		while _head < _queue.size():
			if (_head & 63) == 0 and Time.get_ticks_usec() > until:
				return false
			var i := _queue[_head]
			_head += 1
			if i == goal:
				return true
			var d := _dist[i]
			if d >= far:
				continue
			var ix := i % g.nx
			for k in 4:
				if (k == 0 and ix == 0) or (k == 1 and ix == g.nx - 1):
					continue
				var j := i + steps[k]
				if j < 0 or j >= n or g.open[j] == 0 or _dist[j] >= 0:
					continue
				if pass_gap > 0.0 and g.middle(j).distance_to(shooter) < pass_gap:
					continue
				if _in_the_way(g.middle(j)):
					continue
				_dist[j] = d + 1
				_from[j] = i
				_queue.append(j)
		return true

	func _score(until: int) -> bool:
		while _scored < _queue.size():
			if (_scored & 31) == 0 and Time.get_ticks_usec() > until:
				return false
			var i := _queue[_scored]
			_scored += 1
			if g.snap.has(i):
				continue                    # not in a doorway
			var spot := g.middle(i)
			var away := spot.distance_to(shooter)
			var off := away - RUN_COST * float(_dist[i]) * CELL
			if off > _away_score and away >= from_spot.distance_to(shooter) + RUN_OFF and not _taken(spot):
				_away_score = off
				_away = i
			var room := g.room_of(i)
			var cut: bool = room >= 0 and not shown.call(room)
			if not cut and not g.is_edge(i):
				continue
			if away < NEAR_SHOOTER or _taken(spot):
				continue
			var cover := _cover(spot)
			if cover < 0.0 and not cut:
				continue
			var score := minf(away, 9.0) - 0.45 * float(_dist[i]) * CELL + (CUT_AWAY if cut else 2.5 - cover)
			_order.append(Vector2(-score, i))
		_order.sort()
		return true

	func _try(until: int) -> bool:
		if _missed.is_empty():
			_missed.resize(g.nx * g.nz)
			_missed.fill(0)
		while _at < _order.size() and tried < TRIES and glanced < GLANCES:
			if Time.get_ticks_usec() > until:
				return false
			var i := int(_order[_at].y)
			_at += 1
			if _missed[i] == 1:
				continue                    # beside one he would be seen at: try somewhere else first
			var room := g.room_of(i)
			if room >= 0 and not shown.call(room):
				found = i
				return true
			glanced += 1
			if not _near_cover(g.middle(i)):
				continue                    # nothing near him, as high as his face, on the line to the shooter
			tried += 1
			if not looks(world, eye, g.middle(i), floor_y, tall, doors):
				if _firm(g.middle(i)):
					found = i
					return true
				continue                    # at the very edge of what hides him: one beside it may do
			_miss(i)
		if _away >= 0:
			found = _away                   # nowhere hides him: as far from the shooter as he can get
			fled = true
		return true

	## Is he hidden a little to either side of `spot` too, and a little nearer the shooter and further from him (low
	## cover hides less of him the further he is behind it)?
	func _firm(spot: Vector2) -> bool:
		var to := (shooter - spot).normalized()
		var side := Vector2(-to.y, to.x) * MARGIN
		for p: Vector2 in [spot + side, spot - side, spot + to * MARGIN, spot - to * MARGIN]:
			if looks(world, eye, p, floor_y, tall, doors):
				return false
		return true

	## Is the line from his face, crouched at `spot`, to the shooter's eyes blocked within LOOK of him? (A short look,
	## cheap beside the whole line: what is low, a bench, a bar stool, is passed over before trying the spot.)
	func _near_cover(spot: Vector2) -> bool:
		if world == null:
			return true
		var face := Vector3(spot.x, floor_y + tall * 0.86, spot.y)
		var to := eye - face
		var flat := Vector2(to.x, to.z).length()
		if flat < 0.01:
			return false
		return blocked_line(world, face, face + to * minf(1.0, LOOK / flat), doors)

	## The squares within SPREAD of square i, which he would be seen at: not tried (they are in sight much as it is).
	func _miss(i: int) -> void:
		var r := int(ceil(SPREAD / CELL))
		var ix := i % g.nx
		var iz := i / g.nx
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := ix + dx
				var z := iz + dz
				if x >= 0 and z >= 0 and x < g.nx and z < g.nz and Vector2(dx, dz).length() * CELL <= SPREAD:
					_missed[z * g.nx + x] = 1

	## people_cover.gd's seen() (here, for a search to use; through the doors in `see_past` as if they were open).
	static func looks(w: RefCounted, from: Vector3, spot: Vector2, at_y: float, high: float, see_past := {}) -> bool:
		if w == null:
			return true
		var flat := Vector2(spot.x - from.x, spot.y - from.z)
		if flat.length() < 0.01:
			return true
		var side := Vector2(-flat.y, flat.x).normalized() * SIDE
		# His face (above the eyes), its sides and his middle; the top of his hair may show over what hides him.
		for p: Vector3 in [Vector3(spot.x, at_y + high * 0.86, spot.y), Vector3(spot.x + side.x, at_y + high * 0.74, spot.y + side.y),
				Vector3(spot.x - side.x, at_y + high * 0.74, spot.y - side.y), Vector3(spot.x, at_y + high * 0.45, spot.y)]:
			if not blocked_line(w, from, p, see_past):
				return true
		return false

	## Does something solid stand between `from` and `to` (combat_world.gd's trace), going on through the doors in
	## `see_past`? (A door shut now may be open by the time he is there: someone running opens it and leaves it open.)
	static func blocked_line(w: RefCounted, from: Vector3, to: Vector3, see_past: Dictionary) -> bool:
		var at := from
		var on := (to - from).normalized()
		for k in 12:                        # (a door is a slab, a panel and knobs: a trace can meet it several times)
			var hit: Dictionary = w.trace(at, to)
			if not hit["hit"]:
				return false
			if see_past.is_empty() or not _in_door(hit["mi"], see_past):
				return true
			at = (hit["pos"] as Vector3) + on * 0.05
			if (to - at).dot(on) <= 0.0:
				return false
		return false

	## Is mesh `mi` part of one of the doors in `of`?
	static func _in_door(mi: Node, of: Dictionary) -> bool:
		var n := mi
		for k in 6:
			if n == null:
				return false
			if of.has(n):
				return true
			n = n.get_parent()
		return false

	## people_cover.gd's walkable() (here, for a search to use). The squares alone would let a line clip a prop's
	## corner (a square is open if its middle is clear), and he would be held up there: the props are looked at too.
	static func straight(grid: Grid, a: Vector2, b: Vector2) -> bool:
		var n := maxi(int(ceil(a.distance_to(b) / (CELL * 0.5))), 1)
		for k in range(1, n):
			var i := grid.at(a.lerp(b, float(k) / float(n)))
			if i < 0 or grid.open[i] == 0 or grid.snap.has(i) or grid.door_at.has(i):
				return false
		for r: Rect2 in grid.props:
			if cuts(r, a, b):
				return false
		return true

	## Does the straight line from `a` to `b` pass through the inside of `r` (not only along its edge)?
	static func cuts(r: Rect2, a: Vector2, b: Vector2) -> bool:
		var t0 := 0.0
		var t1 := 1.0
		var d := b - a
		for axis in 2:
			var lo: float = r.position[axis]
			var hi: float = r.end[axis]
			var from: float = a[axis]
			var by: float = d[axis]
			if absf(by) < 0.000001:
				if from <= lo or from >= hi:
					return false
				continue
			var u0: float = (lo - from) / by
			var u1: float = (hi - from) / by
			t0 = maxf(t0, minf(u0, u1))
			t1 = minf(t1, maxf(u0, u1))
		return t1 - t0 > 0.000001

	## How far towards the shooter from `spot` the first square he cannot stand on is (something between), or -1.
	func _cover(spot: Vector2) -> float:
		var way := shooter - spot
		var reach := minf(LOOK, way.length() - 0.5)
		way = way.normalized()
		var d := CELL * 0.5
		while d <= reach:
			if not g.is_open(g.at(spot + way * d)):
				return d
			d += CELL * 0.5
		return -1.0

	func _taken(spot: Vector2) -> bool:
		for other: Vector2 in keep_off:
			if other.distance_to(spot) < CLAIM:
				return true
		return false

	func _in_the_way(at: Vector2) -> bool:
		for other: Vector2 in blocked:
			if other.distance_to(at) < IN_THE_WAY:
				return true
		return false

	## The squares from his to the one found, straightened: from each point on to the furthest square along it that
	## can be walked to in a straight line (doorways are walked through square by square, along their middle).
	func _make_path() -> void:
		path = PackedVector2Array()
		if found < 0:
			return
		var cells := PackedInt32Array()
		var back := found
		while back >= 0 and back != start:
			cells.append(back)
			back = _from[back]
		cells.reverse()
		var here := from_spot
		var i := 0
		while i < cells.size():
			var j := i
			while j + 1 < cells.size() and straight(g, here, g.middle(cells[j + 1])) and _clear(here, g.middle(cells[j + 1])):
				j += 1
			here = g.middle(cells[j])
			path.append(here)
			i = j + 1

	## Does the straight line from `a` to `b` keep IN_THE_WAY from everyone standing still (and, from one he starts
	## or ends nearer than that, no nearer than he starts or ends)? The squares near them are kept off; a line
	## between two other squares could still cut by.
	func _clear(a: Vector2, b: Vector2) -> bool:
		for other: Vector2 in blocked:
			var least := minf(IN_THE_WAY, minf(other.distance_to(a), other.distance_to(b))) - 0.001
			if other.distance_to(Geometry2D.get_closest_point_to_segment(other, a, b)) < least:
				return false
		if _pass > 0.0:                         # nor nearer the shooter than the squares may go
			var least_him := minf(_pass, minf(shooter.distance_to(a), shooter.distance_to(b))) - 0.001
			if shooter.distance_to(Geometry2D.get_closest_point_to_segment(shooter, a, b)) < least_him:
				return false
		return true


## The floor of place `b` on squares, for someone of reach `reach` (made once for each place and size): its walk
## areas with every doorway in them, shut or not (someone frightened opens a shut door on his way).
static func grid(b: Node3D, reach: float) -> Grid:
	var areas: Array = b.walk_areas()
	var doors: Array = b.get("doors") if b.get("doors") is Array else []
	for door: Node3D in doors:
		if not door.is_open and door.passage.has_area():
			areas.append(door.passage)
	var names: Array = []
	for r: Rect2 in areas:
		names.append(str(r))
	names.sort()
	var key := "%d:%.2f:%d" % [b.get_instance_id(), reach, hash(str(names))]
	if _grids.has(key):
		return _grids[key]
	var g := Grid.new()
	var box := Rect2()
	for r: Rect2 in areas:
		box = r if not box.has_area() else box.merge(r)
	box = box.grow(CELL * 2.0)
	g.x0 = box.position.x
	g.z0 = box.position.y
	g.nx = int(ceil(box.size.x / CELL))
	g.nz = int(ceil(box.size.y / CELL))
	var n := g.nx * g.nz
	var open := PackedByteArray()
	open.resize(n)
	open.fill(0)
	g.edge.resize(n)
	g.edge.fill(0)
	g.room.resize(n)
	g.room.fill(-2)
	for room: Dictionary in b.rooms:
		g.rects.append(room.get("rect", room.get("area", Rect2())))
	# The floor: every square whose middle is in a walk area; then the narrow strips (doorways), the squares
	# along their middle line, each standing on that line.
	var thin: Array = []
	for r: Rect2 in areas:
		if r.size.x < CELL * 1.5 or r.size.y < CELL * 1.5:
			thin.append(r)
			continue
		var c0 := Vector2i(maxi(ceili((r.position.x - g.x0) / CELL - 0.5), 0), maxi(ceili((r.position.y - g.z0) / CELL - 0.5), 0))
		var c1 := Vector2i(mini(floori((r.end.x - g.x0) / CELL - 0.5), g.nx - 1), mini(floori((r.end.y - g.z0) / CELL - 0.5), g.nz - 1))
		for iz in range(c0.y, c1.y + 1):
			var row := iz * g.nx
			for ix in range(c0.x, c1.x + 1):
				open[row + ix] = 1
	g.open = open
	for r: Rect2 in thin:
		var mid := r.get_center()
		var across_x := r.size.x < r.size.y
		var n_along := maxi(int(ceil((r.size.y if across_x else r.size.x) / CELL)), 1)
		for k in n_along + 1:
			var p := Vector2(mid.x, r.position.y + r.size.y * float(k) / float(n_along)) if across_x \
					else Vector2(r.position.x + r.size.x * float(k) / float(n_along), mid.y)
			var i := g.at(p)
			if i >= 0 and g.open[i] == 0:
				g.open[i] = 1
				g.snap[i] = p
	# The doorways: the door each of their squares belongs to.
	for door: Node3D in doors:
		var r: Rect2 = door.passage
		if not r.has_area():
			continue
		var c0 := Vector2i(maxi(floori((r.position.x - g.x0) / CELL) - 1, 0), maxi(floori((r.position.y - g.z0) / CELL) - 1, 0))
		var c1 := Vector2i(mini(floori((r.end.x - g.x0) / CELL) + 1, g.nx - 1), mini(floori((r.end.y - g.z0) / CELL) + 1, g.nz - 1))
		for iz in range(c0.y, c1.y + 1):
			for ix in range(c0.x, c1.x + 1):
				var i := iz * g.nx + ix
				if g.open[i] == 1 and r.grow(0.01).has_point(g.middle(i)):
					g.door_at[i] = door
	# Less the props, grown for his size.
	for prop: Rect2 in b.obstacles:
		var r := prop.grow_individual(reach, RADIUS, reach, RADIUS)
		g.props.append(r)
		var c0 := Vector2i(floori((r.position.x - g.x0) / CELL) - 1, floori((r.position.y - g.z0) / CELL) - 1)
		var c1 := Vector2i(floori((r.end.x - g.x0) / CELL) + 1, floori((r.end.y - g.z0) / CELL) + 1)
		for iz in range(maxi(c0.y, 0), mini(c1.y + 1, g.nz)):
			for ix in range(maxi(c0.x, 0), mini(c1.x + 1, g.nx)):
				var i := iz * g.nx + ix
				if g.open[i] == 1 and r.has_point(g.middle(i)):
					g.open[i] = 0
					g.snap.erase(i)
	_grids[key] = g
	return g


## Can he walk straight from `a` to `b`: every square on the way open, and none of them a doorway's?
static func walkable(g: Grid, a: Vector2, b: Vector2) -> bool:
	return Search.straight(g, a, b)


## Does the straight line from `a` to `b` pass through the inside of `r`?
static func cuts(r: Rect2, a: Vector2, b: Vector2) -> bool:
	return Search.cuts(r, a, b)


## Can the shooter, his eyes at `eye`, see someone `tall` crouched at `spot` (his feet at `floor_y`): is any line
## from his eyes to the top of that head, its sides or its middle clear of everything solid?
static func seen(w: RefCounted, eye: Vector3, spot: Vector2, floor_y: float, tall: float) -> bool:
	return Search.looks(w, eye, spot, floor_y, tall)


## The shooter's eyes.
static func eye_of(shooter: Node3D) -> Vector3:
	return shooter.global_position + Vector3(0.0, float(shooter.height) * EYE, 0.0)


## Which room of place `b` the floor spot `p` is in, -1 for none (a doorway between two).
static func room_of(b: Node3D, p: Vector2) -> int:
	for ri in b.rooms.size():
		var room: Dictionary = b.rooms[ri]
		var r: Rect2 = room.get("rect", room.get("area", Rect2()))
		if r.has_point(p):
			return ri
	return -1


## The node a room of place `b` is shown and hidden with.
static func node_of_room(b: Node3D, ri: int) -> Node3D:
	var room: Dictionary = b.rooms[ri]
	if room.has("node"):
		return room["node"]
	return b.node_of(room["band"])
