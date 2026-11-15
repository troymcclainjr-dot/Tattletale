extends RefCounted
## Glass that shots break. Whatever builds a pane of glass marks it with Kit.pane() (place.gd's windows,
## houses.gd's sashes, Kit.window, the studio's windows, cars), so a new place gets breakable windows as soon
## as it uses any of those.
##
## A pane (a box thin one way) breaks as glass does. A round cracks the piece of glass it hits (at first the whole
## pane) from the point it hits: cracks run out from there, some on to the frame and some only part of the way,
## and rings of cracks go round the hit. The cracks cut the piece into pieces. The few right round the hit always
## come away (the hole); the next ring often, the ones further out seldom; a piece held by the frame, or a big one,
## less often. A piece left held by nothing, with the glass under it gone, falls too. Cracks stop at the cracks
## already there, so each round breaks the pane its own way and a hole stays a hole: a round through it breaks
## nothing. How far the cracks run, how wide the rings are and how much comes away depend on the round (a rifle's
## does more, and so do rounds close together in a burst: POWER, `heat`) and on the pane (a big shop window cracks
## in long runs and keeps its big pieces; a small sash comes apart sooner). By an edge or in a corner the pieces
## between the hit and the frame are small, and go. A round that comes in at a slant makes a longer hole and rings,
## stretched the way it went (SLANT). A big piece that comes away breaks up as it falls (MOST). The same pane hit
## the same way breaks the same way every time (the dice are seeded from where the pane is and where it was hit;
## --do=glassseed:n for another way), and no two panes break alike.
##
## What is left is drawn in the pane's own material in place of its box (hidden), with a line along each crack (ink,
## or light on a pane drawn dark), an ink edge with a light rim round each hole, and, on a pane drawn dark or lit,
## a dark void behind the holes. The pieces that come away are handed back for combat_fx.gd to drop. A block of
## glass (a car's glasshouse) is not broken through: it gets a dark hole with cracks where it is hit. It all stays
## broken while the place is loaded (going away and coming back too), until mend() (a new day).

const INK := Color(0.03, 0.02, 0.05)
const VOID := Color(0.035, 0.03, 0.05)
const CRACK := Color(0.86, 0.92, 0.97)        # cracks on dark glass are light
const GLINT := Color(0.84, 0.93, 1.0)         # crushed glass: a light rim inside the ink of a hole (shows on clear glass)
const BAND := 0.012                           # metres: the ink round a hole
const GLINT_W := 0.016                        # metres: its light rim
const CRACK_W := 0.007                        # a crack (half of it drawn on the piece either side)
const LIFT := 0.0012                          # lines stand this far proud of the glass
const DUST := 0.00015                         # square metres: a piece smaller than this (about 12 mm across) is dust
const MOST := 0.025                           # square metres: a bigger piece that comes away breaks up as it goes
const SLANT := 0.9                            # a round at a slant stretches the break along its way (by this, side-on)
const GRID := 0.1                             # metres: the squares for finding which piece a point is on
const ON_FRAME := 0.0015                      # metres: an edge this near the pane's edge is in the frame
## How hard a round of each gun hits glass (the pistol's is 1): a rifle round cracks it further and takes more out.
const POWER := {"pistol": 1.0, "uzi": 0.8, "ak": 1.9}

static var _mats := {}
static var glass_seed := 0                    # --do=glassseed:n: the same shots break the glass another way


## A piece of glass still in the frame, in the pane's own plane (x across it, y up it; (0, 0) its middle).
class Piece:
	var poly := PackedVector2Array()          # anticlockwise
	var box := Rect2()
	var area := 0.0
	var held := 0.0                           # metres of its edge in the frame
	var lines := PackedVector2Array()         # cracks that run into it and stop short: pairs of points
	var dirty := true                         # what is drawn of it must be worked out again
	var fill := PackedVector3Array()          # drawn: the glass, both faces
	var fill_n := PackedVector3Array()
	var ink := PackedVector3Array()           # the edges of holes
	var lit := PackedVector3Array()           # their light rims
	var thin := PackedVector3Array()          # cracks


## A pane's broken glass: kept on the pane (and its twins) as meta "broken" {"state", "node"}.
class State:
	var half := Vector2.ZERO
	var d := 0.02                             # its thickness
	var k := 2                                # its thin axis; ia across, ja up
	var ia := 0
	var ja := 1
	var seed := 0
	var hits := 0
	var heat := 0.0                           # rounds just now (a burst): each adds 1, it halves every 8 frames
	var heat_frame := -1
	var whole := 0.0                          # its area, whole
	var clear := true
	var dark := false
	var pieces: Array = []                    # of Piece: the glass left
	var panes: Array = []                     # the panes showing this glass: one, and its twins
	var grid := {}                            # Vector2i: Array of Piece


static func _mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = color
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats[key] = m
	return _mats[key]


## Let the shared materials go (the game is closing).
static func forget() -> void:
	_mats.clear()


## Is the pane drawn dark (a window with no light behind it)? Its cracks are drawn light.
static func _dark(mi: MeshInstance3D) -> bool:
	var mat := mi.get_active_material(0)
	if not mat is BaseMaterial3D or clear(mi):
		return false
	var b := mat as BaseMaterial3D
	return not b.emission_enabled and b.albedo_color.get_luminance() < 0.35


## Is the pane see-through (clear glass) rather than drawn dark or lit?
static func clear(mi: MeshInstance3D) -> bool:
	var mat := mi.get_active_material(0)
	return mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and (mat as BaseMaterial3D).albedo_color.a < 0.95


# ------------------------------------------------------------------ what is left of a pane

static func _state(mi: MeshInstance3D) -> State:
	if mi == null or not is_instance_valid(mi) or not mi.has_meta("broken"):
		return null
	return (mi.get_meta("broken") as Dictionary).get("state", null)


## A point in the world, in the pane's plane.
static func _plane(st: State, mi: MeshInstance3D, p: Vector3) -> Vector2:
	var lh := mi.global_transform.affine_inverse() * p
	return Vector2(lh[st.ia], lh[st.ja])


## The pane's plane (x across, y up, z its face) in the world.
static func _to_world(st: State, mi: MeshInstance3D) -> Transform3D:
	return mi.global_transform * Transform3D(_axes(st), Vector3.ZERO)


static func _axes(st: State) -> Basis:
	var x := Vector3.ZERO
	var y := Vector3.ZERO
	var z := Vector3.ZERO
	x[st.ia] = 1.0
	y[st.ja] = 1.0
	z[st.k] = 1.0
	return Basis(x, y, z)


## The piece at `p` (in the plane), or null if p is in a hole. Within `slack` of a piece's edge counts as on it
## (a round on a crack line hits glass). `skip`: a piece not to count.
static func _piece_at(st: State, p: Vector2, skip: Piece = null, slack := 0.0) -> Piece:
	var cell: Array = st.grid.get(Vector2i(floori(p.x / GRID), floori(p.y / GRID)), [])
	for pc: Piece in cell:
		if pc != skip and pc.box.grow(0.0005).has_point(p) and Geometry2D.is_point_in_polygon(p, pc.poly):
			return pc
	if slack <= 0.0:
		return null
	var best: Piece = null
	var gap := slack
	for pc: Piece in cell:
		if pc == skip or not pc.box.grow(slack).has_point(p):
			continue
		var n := pc.poly.size()
		for i in n:
			var d := Geometry2D.get_closest_point_to_segment(p, pc.poly[i], pc.poly[(i + 1) % n]).distance_to(p)
			if d < gap:
				gap = d
				best = pc
	return best


static func _index(st: State) -> void:
	st.grid = {}
	for pc: Piece in st.pieces:
		var lo := Vector2i(floori((pc.box.position.x - 0.006) / GRID), floori((pc.box.position.y - 0.006) / GRID))
		var hi := Vector2i(floori((pc.box.end.x + 0.006) / GRID), floori((pc.box.end.y + 0.006) / GRID))
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				var key := Vector2i(x, y)
				if not st.grid.has(key):
					st.grid[key] = []
				(st.grid[key] as Array).append(pc)


## Both ends of a-b on the same edge of the pane: that edge is in the frame.
static func _on_frame(a: Vector2, b: Vector2, half: Vector2) -> bool:
	return (absf(a.x - half.x) < ON_FRAME and absf(b.x - half.x) < ON_FRAME) or (absf(a.x + half.x) < ON_FRAME and absf(b.x + half.x) < ON_FRAME) \
			or (absf(a.y - half.y) < ON_FRAME and absf(b.y - half.y) < ON_FRAME) or (absf(a.y + half.y) < ON_FRAME and absf(b.y + half.y) < ON_FRAME)


## A piece of that outline (made anticlockwise), or null if it is dust.
static func _piece(poly: PackedVector2Array, st: State) -> Piece:
	if poly.size() < 3:
		return null
	var a2 := 0.0
	var n := poly.size()
	for i in n:
		a2 += poly[i].cross(poly[(i + 1) % n])
	if a2 < 0.0:
		poly.reverse()
	var pc := Piece.new()
	pc.poly = poly
	pc.area = absf(a2) * 0.5
	if pc.area < DUST:
		return null
	var lo := Vector2(INF, INF)
	var hi := -lo
	for i in n:
		lo = lo.min(poly[i])
		hi = hi.max(poly[i])
		if _on_frame(poly[i], poly[(i + 1) % n], st.half):
			pc.held += poly[i].distance_to(poly[(i + 1) % n])
	pc.box = Rect2(lo, hi - lo)
	return pc


static func _centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	var a := 0.0
	var n := poly.size()
	for i in n:
		var w := poly[i].cross(poly[(i + 1) % n])
		c += (poly[i] + poly[(i + 1) % n]) * w
		a += w
	if absf(a) < 1e-12:
		c = Vector2.ZERO
		for p: Vector2 in poly:
			c += p
		return c / float(maxi(n, 1))
	return c / (3.0 * a)


## The pane's glass, as it is now (made whole the first time).
static func _begin(mi: MeshInstance3D, twins: Array) -> State:
	var st := _state(mi)
	for t: MeshInstance3D in twins:
		if st == null:
			st = _state(t)
	if st == null:
		st = State.new()
		var s: Vector3 = (mi.mesh as BoxMesh).size
		st.k = 0 if s.x <= s.y and s.x <= s.z else (1 if s.y <= s.z else 2)
		st.ia = (st.k + 1) % 3
		st.ja = (st.k + 2) % 3
		st.half = Vector2(s[st.ia], s[st.ja]) * 0.5
		st.d = s[st.k]
		st.whole = st.half.x * st.half.y * 4.0
		st.clear = clear(mi)
		st.dark = _dark(mi)
		var g := mi.global_position
		st.seed = hash([Vector3i(roundi(g.x * 1000.0), roundi(g.y * 1000.0), roundi(g.z * 1000.0)), Vector2i(roundi(st.half.x * 1000.0), roundi(st.half.y * 1000.0))])
		var h := st.half
		st.pieces = [_piece(PackedVector2Array([Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)]), st)]
		_index(st)
	for pane: MeshInstance3D in [mi] + twins:
		if not st.panes.has(pane):
			st.panes.append(pane)
	return st


# ------------------------------------------------------------------ breaking

## Break a pane where `hit` is (in the world), by a round going `dir` with `power` (POWER: 1 for a pistol round).
## `twins` are panes in exactly the same spot (the studio's see-through copy of a wall); they show the same glass.
## Returns {} if `hit` is in a hole (nothing breaks), else {"center": the hit, "normal": the pane's face,
## "basis": the pane's plane in the world (x across, y up, z its face), "fallen": the pieces that came away (each
## {"poly": its outline about its middle, "at": its middle in the world, "near": metres from the hit, "size"}),
## "power": how hard it was hit with a burst counted in, "clear": clear glass, "middle": the pane's middle,
## "low": the height of its lowest edge}.
static func shatter(mi: MeshInstance3D, hit: Vector3, dir: Vector3, power := 1.0, twins: Array = []) -> Dictionary:
	var st := _begin(mi, twins)
	var p := _plane(st, mi, hit)
	var q := _piece_at(st, p, null, 0.004)
	if q == null:
		return {}
	for pane: MeshInstance3D in st.panes:
		var keep: Dictionary = pane.get_meta("broken", {})
		keep["state"] = st
		pane.set_meta("broken", keep)
	st.hits += 1
	var frame := Engine.get_process_frames()
	st.heat = (st.heat * pow(0.5, float(frame - st.heat_frame) / 8.0) if st.heat_frame >= 0 else 0.0) + 1.0
	st.heat_frame = frame
	var e := power * (1.0 + 0.35 * (st.heat - 1.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([st.seed, glass_seed, st.hits, Vector2i(roundi(p.x * 1000.0), roundi(p.y * 1000.0))])
	var ld := mi.global_transform.basis.inverse() * dir         # a round coming in slanting makes a longer hole
	var flat := Vector2(ld[st.ia], ld[st.ja])
	var slant := flat.length() / maxf(ld.length(), 1e-6)
	var lean := flat.normalized() * SLANT * slant * slant if flat.length() > 1e-6 else Vector2.ZERO
	var fallen: Array = _fracture(st, q, p.clamp(-st.half, st.half), e, rng, lean)
	_index(st)
	fallen.append_array(_settle(st, rng, e))
	for pc: Piece in st.pieces:               # what lay against what came away has a new edge to draw
		if not pc.dirty:
			for gone: Piece in fallen:
				if gone.box.grow(0.01).intersects(pc.box):
					pc.dirty = true
					break
	_draw(st)
	var xf := _to_world(st, mi)
	var scale := Vector2(xf.basis.x.length(), xf.basis.y.length())       # the pane's own measure to metres
	var centre := xf * Vector3(p.x, p.y, 0.0)
	var low := INF                                                       # the pane's lowest edge
	for c: Vector2 in [st.half, -st.half, Vector2(st.half.x, -st.half.y), Vector2(-st.half.x, st.half.y)]:
		low = minf(low, (xf * Vector3(c.x, c.y, 0.0)).y)
	var out: Array = []
	for pc: Piece in fallen:
		for part: PackedVector2Array in (_split(pc.poly, MOST, rng) if pc.area > MOST else [pc.poly]):
			var area := _area(part)
			if area < DUST:
				continue
			var c := _centroid(part)
			var local := PackedVector2Array()
			for v: Vector2 in part:
				local.append((v - c) * scale)
			var at := xf * Vector3(c.x, c.y, 0.0)
			out.append({"poly": local, "at": at, "near": at.distance_to(centre), "size": sqrt(area * scale.x * scale.y)})
	return {"center": centre, "normal": xf.basis.z.normalized(), "basis": xf.basis.orthonormalized(),
			"fallen": out, "power": e, "clear": st.clear, "middle": xf.origin, "low": low}


## Crack piece q from p: cut it along the new cracks into pieces, take out what comes away. Returns the pieces
## that came away (st.pieces has q's pieces that stay in its place). `lean`: the way the round went across the
## pane, as long as the break is stretched that way (1 + its length).
static func _fracture(st: State, q: Piece, p: Vector2, e: float, rng: RandomNumberGenerator, lean := Vector2.ZERO) -> Array:
	var short := minf(st.half.x, st.half.y) * 2.0
	var big := st.whole > 1.5                              # a shop window
	var sash := st.whole < 0.8 and short < 0.9             # a small pane
	var r1 := clampf((0.03 + 0.026 * e) * rng.randf_range(0.8, 1.2), 0.018, short * 0.28)
	var n_rings := 2 + (1 if e > 1.35 else 0) + (1 if big else 0)
	var rings := PackedFloat32Array([r1])
	for i in range(1, n_rings):
		rings.append(rings[i - 1] * rng.randf_range(1.7, 2.35) * (1.15 if big else 1.0))
	var far := 0.0                                         # the furthest corner of the pane from p
	for c: Vector2 in [st.half, -st.half, Vector2(st.half.x, -st.half.y), Vector2(-st.half.x, st.half.y)]:
		far = maxf(far, c.distance_to(p))
	var reach := far * 1.6 + 0.5                           # the far ring: outside the whole pane
	# The cracks out from the hit: their way, and the outermost band of the rings each one cuts (n_rings: on to
	# the frame). At least two, about opposite, run on to the frame, or the glass round the hole would be one ring.
	var n := 5 + rng.randi_range(0, 3) + (1 if e > 1.35 else 0)
	var turn := rng.randf() * TAU
	var angles := PackedFloat32Array()
	for i in n:
		angles.append(turn + TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / float(n))
	var to_frame := 0.85 if sash else (0.3 + 0.16 * e if big else 0.6)
	var runs := PackedInt32Array()
	var full := 0
	for i in n:
		var r := n_rings if rng.randf() < minf(to_frame, 0.95) else rng.randi_range(1, n_rings - 1)
		runs.append(r)
		if r == n_rings:
			full += 1
	if full < 2:
		var first := rng.randi_range(0, n - 1)
		runs[first] = n_rings
		runs[(first + n / 2) % n] = n_rings
	# Each crack as points from p out to the far ring, wandering a little (never as far as the next crack), with a
	# point on each ring.
	var rad: Array = []
	var marks: Array = []
	for i in n:
		var gap := minf(wrapf(angles[i] - angles[(i - 1 + n) % n], 0.0, TAU), wrapf(angles[(i + 1) % n] - angles[i], 0.0, TAU))
		var lim := gap * 0.28
		var wob := 0.0
		var pts := PackedVector2Array([p])
		var m := PackedInt32Array()
		var r_was := 0.0
		for b in n_rings:
			var steps := 1 if b == 0 else clampi(int((rings[b] - r_was) / 0.09), 1, 3)
			for s in range(1, steps + 1):
				wob = clampf(wob + rng.randf_range(-0.14, 0.14), -lim, lim)
				var rr := lerpf(r_was, rings[b], float(s) / float(steps))
				if s == steps:
					rr *= rng.randf_range(0.92, 1.08)
				pts.append(p + _lean(Vector2.from_angle(angles[i] + wob) * rr, lean))
			m.append(pts.size() - 1)
			r_was = rings[b]
		var rr2 := r_was
		var ring_end := pts[pts.size() - 1]       # on from the last ring, out the way it was going (a slant stretches only the rings)
		while rr2 < reach:
			rr2 = rr2 * rng.randf_range(1.2, 1.4) + 0.03
			if rr2 > far + 0.05:
				rr2 = reach
			wob = clampf(wob + rng.randf_range(-0.1, 0.1), -lim, lim)
			pts.append(ring_end + Vector2.from_angle(angles[i] + wob) * (rr2 - r_was))
		m.append(pts.size() - 1)
		rad.append(pts)
		marks.append(m)
	# The rings between each crack and the next (ring n_rings is the far ring, outside the pane).
	var arcs: Array = []
	for b in n_rings + 1:
		var row: Array = []
		for i in n:
			var j := (i + 1) % n
			var from: Vector2 = (rad[i] as PackedVector2Array)[(marks[i] as PackedInt32Array)[b]]
			var to: Vector2 = (rad[j] as PackedVector2Array)[(marks[j] as PackedInt32Array)[b]]
			row.append(_arc(p, from, to, 0.0 if b == n_rings else 0.1, rng))
		arcs.append(row)
	# The blocks between two cracks and two rings; the hole in the middle.
	var blocks := {}
	for b in range(1, n_rings + 1):
		for i in n:
			var j := (i + 1) % n
			var ri: PackedVector2Array = rad[i]
			var rj: PackedVector2Array = rad[j]
			var mi_: PackedInt32Array = marks[i]
			var mj: PackedInt32Array = marks[j]
			var poly := PackedVector2Array()
			for t in range(mi_[b - 1], mi_[b] + 1):
				poly.append(ri[t])
			poly.append_array(arcs[b][i])
			for t in range(mj[b], mj[b - 1] - 1, -1):
				poly.append(rj[t])
			var inner: PackedVector2Array = arcs[b - 1][i]
			for t in range(inner.size() - 1, -1, -1):
				poly.append(inner[t])
			blocks[Vector2i(i, b)] = poly
	var core := PackedVector2Array()
	for i in n:
		core.append((rad[i] as PackedVector2Array)[(marks[i] as PackedInt32Array)[0]])
		core.append_array(arcs[0][i])
	# Where a crack stops short, or a ring does not run between two cracks, the blocks either side are one piece.
	var parent := {}
	var links := {}
	for key: Vector2i in blocks:
		parent[key] = key
		links[key] = []
	for b in range(1, n_rings + 1):
		for i in n:
			var j := (i + 1) % n
			if runs[i] < b:
				_join(parent, links, Vector2i((i - 1 + n) % n, b), Vector2i(i, b))
			if b < n_rings and not (runs[i] >= b and runs[j] >= b and rng.randf() < 0.72):
				_join(parent, links, Vector2i(i, b), Vector2i(i, b + 1))
	var groups := {}
	for key: Vector2i in blocks:
		var root: Vector2i = _find(parent, key)
		if not groups.has(root):
			groups[root] = []
		(groups[root] as Array).append(key)
	# Cut q: the hole always comes away; of the rest, the nearer the hit the likelier.
	var gone: Array = []
	var keep: Array = []
	for poly: PackedVector2Array in _cut(core, q.poly):
		var pc := _piece(poly, st)
		if pc:
			gone.append(pc)
	var roots: Array = groups.keys()
	roots.sort()
	for root: Vector2i in roots:
		var band := 99
		for key: Vector2i in groups[root]:
			band = mini(band, key.y)
		for gpoly: PackedVector2Array in _merge(groups[root], blocks, links):
			for poly: PackedVector2Array in _cut(gpoly, q.poly):
				var pc := _piece(poly, st)
				if pc == null:
					continue
				var chance: float = [0.0, 0.62, 0.3, 0.12, 0.05][mini(band, 4)] * e
				if pc.held > 0.004:
					chance *= 0.85 if pc.area < r1 * r1 * 8.0 else 0.4
				if pc.area > 0.05:                         # a big piece mostly stays put
					chance *= 0.35
				if pc.area > 0.15:
					chance *= 0.2
				if sash:
					chance *= 1.3
				if rng.randf() < chance:
					gone.append(pc)
				else:
					keep.append(pc)
	# The cracks that stop short still show, running on a little way into the glass they stop in.
	var trails: Array = []
	for i in n:
		if runs[i] >= n_rings:
			continue
		var pts: PackedVector2Array = rad[i]
		var at: int = (marks[i] as PackedInt32Array)[runs[i]]
		var want := rings[runs[i] - 1] * rng.randf_range(0.5, 1.4)
		var line := PackedVector2Array([pts[at]])
		var k := at
		while want > 0.0 and k + 1 < pts.size():
			var step := pts[k].distance_to(pts[k + 1])
			line.append(pts[k].lerp(pts[k + 1], minf(want / maxf(step, 1e-5), 1.0)))
			want -= step
			k += 1
		trails.append(line)
	for pc: Piece in keep:
		for line: PackedVector2Array in trails:
			_scratch(pc, line)
		for s in range(0, q.lines.size(), 2):
			_scratch(pc, PackedVector2Array([q.lines[s], q.lines[s + 1]]))
	var at_q := st.pieces.find(q)
	st.pieces.remove_at(at_q)
	for pc: Piece in keep:
		st.pieces.append(pc)
	return gone


## v stretched along `lean` by 1 + its length.
static func _lean(v: Vector2, lean: Vector2) -> Vector2:
	if lean.length_squared() < 1e-6:
		return v
	var u := lean.normalized()
	return v + u * v.dot(u) * lean.length()


## A ring of cracks from one crack to the next round p (anticlockwise), without its ends.
static func _arc(p: Vector2, from: Vector2, to: Vector2, jag: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	var a0 := (from - p).angle()
	var span := wrapf((to - p).angle() - a0, 0.0, TAU)
	var steps := maxi(int(span / 0.42), 1)
	var r0 := from.distance_to(p)
	var r1 := to.distance_to(p)
	var out := PackedVector2Array()
	for s in range(1, steps):
		var t := float(s) / float(steps)
		out.append(p + Vector2.from_angle(a0 + span * t) * lerpf(r0, r1, t) * (1.0 + rng.randf_range(-jag, jag)))
	return out


static func _find(parent: Dictionary, x: Vector2i) -> Vector2i:
	var r: Vector2i = x
	while parent[r] != r:
		r = parent[r]
	while parent[x] != r:
		var up: Vector2i = parent[x]
		parent[x] = r
		x = up
	return r


static func _join(parent: Dictionary, links: Dictionary, a: Vector2i, b: Vector2i) -> void:
	(links[a] as Array).append(b)
	(links[b] as Array).append(a)
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[rb] = ra


## The blocks of a group as one outline (as few as will merge), going from block to block as they touch.
static func _merge(members: Array, blocks: Dictionary, links: Dictionary) -> Array:
	if members.size() == 1:
		return [blocks[members[0]]]
	members.sort()
	var order: Array = [members[0]]
	var seen := {members[0]: true}
	var i := 0
	while i < order.size():
		for nb: Vector2i in links[order[i]]:
			if not seen.has(nb):
				seen[nb] = true
				order.append(nb)
		i += 1
	var acc: Array = [blocks[order[0]]]
	for k in range(1, order.size()):
		var add: PackedVector2Array = blocks[order[k]]
		var joined := false
		for a in acc.size():
			var both := _simple(Geometry2D.merge_polygons(acc[a], add))
			if both.size() == 1:
				acc[a] = both[0]
				joined = true
				break
		if not joined:
			acc.append(add)
	return acc


## a and b's overlap, as outlines with no holes in them.
static func _cut(a: PackedVector2Array, b: PackedVector2Array) -> Array:
	return _simple(Geometry2D.intersect_polygons(a, b))


## Outlines from the clipper, with any hole in one cut out by splitting that one in two through the hole.
static func _simple(polys: Array) -> Array:
	var outer: Array = []
	var holes: Array = []
	for i in polys.size():
		var poly: PackedVector2Array = polys[i]
		var inside := false
		for j in polys.size():
			if j != i and _area(polys[j]) > _area(poly) and Geometry2D.is_point_in_polygon(poly[0], polys[j]):
				inside = true
				break
		(holes if inside else outer).append(poly)
	for hole: PackedVector2Array in holes:
		var c := _centroid(hole)
		for i in outer.size():
			var poly: PackedVector2Array = outer[i]
			if _area(poly) <= _area(hole) or not Geometry2D.is_point_in_polygon(hole[0], poly):
				continue
			var big := 1000.0
			var halves: Array = []
			for side: float in [-1.0, 1.0]:
				var plane := PackedVector2Array([Vector2(c.x, -big), Vector2(c.x + side * big, -big), Vector2(c.x + side * big, big), Vector2(c.x, big)])
				for part: PackedVector2Array in Geometry2D.intersect_polygons(poly, plane):
					halves.append_array(Geometry2D.clip_polygons(part, hole))
			outer.remove_at(i)
			outer.append_array(halves)
			break
	return outer


static func _area(poly: PackedVector2Array) -> float:
	var a2 := 0.0
	for i in poly.size():
		a2 += poly[i].cross(poly[(i + 1) % poly.size()])
	return absf(a2) * 0.5


## A piece that comes away bigger than `most` breaks up as it goes: it is cut across its long way, along a jagged
## line somewhere near its middle, and so on until no part is bigger than about `most`.
static func _split(poly: PackedVector2Array, most: float, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var todo: Array = [poly]
	var guard := 0
	while not todo.is_empty():
		var cur: PackedVector2Array = todo.pop_back()
		guard += 1
		if guard > 40 or _area(cur) <= most * rng.randf_range(0.8, 1.25):
			out.append(cur)
			continue
		var lo := Vector2(INF, INF)
		var hi := -lo
		for v: Vector2 in cur:
			lo = lo.min(v)
			hi = hi.max(v)
		var span := hi - lo
		var along := Vector2.RIGHT if span.x >= span.y else Vector2.UP
		var way := along.orthogonal().rotated(rng.randf_range(-0.6, 0.6))     # the cut, roughly across the long way
		var at := _centroid(cur) + along * rng.randf_range(-0.18, 0.18) * maxf(span.x, span.y)
		var reach := span.length() + 0.1
		var side := way.orthogonal()
		var cut := PackedVector2Array()
		for s in 9:
			var jag := rng.randf_range(-0.012, 0.012) if s > 0 and s < 8 else 0.0
			cut.append(at + way * lerpf(-reach, reach, float(s) / 8.0) + side * jag)
		cut.append(cut[8] + side * reach * 2.0)
		cut.append(cut[0] + side * reach * 2.0)
		var parts: Array = []
		parts.append_array(_simple(Geometry2D.intersect_polygons(cur, cut)))
		parts.append_array(_simple(Geometry2D.clip_polygons(cur, cut)))
		if parts.size() < 2:
			out.append(cur)
			continue
		todo.append_array(parts)
	return out


## A crack line that runs into a piece and stops: the part of it on the piece is drawn on it.
static func _scratch(pc: Piece, line: PackedVector2Array) -> void:
	var lo := Vector2(INF, INF)
	var hi := -lo
	for v: Vector2 in line:
		lo = lo.min(v)
		hi = hi.max(v)
	if not Rect2(lo, hi - lo).grow(0.001).intersects(pc.box):
		return
	for part: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(line, pc.poly):
		for i in part.size() - 1:
			pc.lines.append(part[i])
			pc.lines.append(part[i + 1])
	pc.dirty = true


## Pieces held by nothing (not in the frame) with little or no glass under them fall, and what they held may then
## fall too. Returns those that fell.
static func _settle(st: State, rng: RandomNumberGenerator, e: float) -> Array:
	var gone: Array = []
	for pass_i in 5:
		var fell := false
		for pc: Piece in st.pieces.duplicate():
			if pc.held > 0.02 or (pc.held > 0.004 and pc.area < 0.02):
				continue
			var under := _support(st, pc)
			var drop := under < 0.3 or (under < 0.6 and pc.area > 0.03 and rng.randf() < 0.35 * e)
			if pc.area < DUST * 4.0 and under < 0.9:
				drop = true
			if drop:
				st.pieces.erase(pc)
				gone.append(pc)
				fell = true
		if not fell:
			break
		_index(st)
	return gone


## How much of a piece's underside rests on other glass (or on the bottom of the frame): 0 to 1.
static func _support(st: State, pc: Piece) -> float:
	var total := 0.0
	var held := 0.0
	var n := pc.poly.size()
	for i in n:
		var a := pc.poly[i]
		var b := pc.poly[(i + 1) % n]
		var length := a.distance_to(b)
		if length < 1e-5:
			continue
		var out := Vector2(b.y - a.y, a.x - b.x) / length         # outwards: the piece is anticlockwise
		if out.y > -0.25:
			continue                                              # not underneath
		var steps := maxi(int(length / 0.03), 1)
		for s in steps:
			var probe := a.lerp(b, (float(s) + 0.5) / float(steps)) + out * 0.004
			total += length / float(steps)
			if probe.y <= -st.half.y or _piece_at(st, probe, pc) != null:
				held += length / float(steps)
	return held / total if total > 0.0 else 1.0


# ------------------------------------------------------------------ drawing it

## Every pane showing this glass gets it drawn afresh (what has not changed is kept from last time).
static func _draw(st: State) -> void:
	var fill := PackedVector3Array()
	var fill_n := PackedVector3Array()
	var ink := PackedVector3Array()
	var lit := PackedVector3Array()
	var thin := PackedVector3Array()
	for pc: Piece in st.pieces:
		if pc.dirty:
			_prepare(st, pc)
		fill.append_array(pc.fill)
		fill_n.append_array(pc.fill_n)
		ink.append_array(pc.ink)
		lit.append_array(pc.lit)
		thin.append_array(pc.thin)
	var void_quad := PackedVector3Array()
	if not st.clear:
		var h := st.half
		void_quad = PackedVector3Array([Vector3(-h.x, -h.y, 0), Vector3(h.x, -h.y, 0), Vector3(h.x, h.y, 0), Vector3(-h.x, -h.y, 0), Vector3(h.x, h.y, 0), Vector3(-h.x, h.y, 0)])
	for pane: MeshInstance3D in st.panes:
		if not is_instance_valid(pane):
			continue
		var mesh := ArrayMesh.new()
		_add(mesh, fill, fill_n, pane.get_active_material(0))
		_add(mesh, ink, PackedVector3Array(), _mat(INK))
		_add(mesh, lit, PackedVector3Array(), _mat(GLINT))
		_add(mesh, thin, PackedVector3Array(), _mat(CRACK if st.dark else INK))
		_add(mesh, void_quad, PackedVector3Array(), _mat(VOID))
		var keep: Dictionary = pane.get_meta("broken", {})
		var node: MeshInstance3D = keep.get("node", null)
		if node == null or not is_instance_valid(node):
			node = MeshInstance3D.new()
			node.set_meta("combat_fx", true)
			node.name = String(pane.name) + "Broken"
			pane.get_parent().add_child(node)
			keep["node"] = node
		keep["state"] = st
		pane.set_meta("broken", keep)
		node.transform = pane.transform * Transform3D(_axes(st), Vector3.ZERO)
		node.mesh = mesh
		pane.visible = false
		if not keep.has("extras"):
			keep["extras"] = _extras(pane, st)
		for extra in keep["extras"]:
			if is_instance_valid(extra):
				(extra as Node3D).visible = false


## What is drawn on a pane's glass (Kit.pane's extras: a glare). A copy of a pane (a ghost wall's) has copies of
## them whose names its paths miss: they are found by being the same mesh in the same spot as the first one's.
static func _extras(pane: MeshInstance3D, st: State) -> Array:
	var out: Array = []
	for path: NodePath in pane.get_meta("glass", []):
		var extra := pane.get_node_or_null(path)
		if extra is Node3D:
			out.append(extra)
	if not out.is_empty() or pane.get_meta("glass", []).is_empty():
		return out
	for other: MeshInstance3D in st.panes:
		if other == pane or not is_instance_valid(other):
			continue
		for path: NodePath in other.get_meta("glass", []):
			var extra := other.get_node_or_null(path)
			if not extra is MeshInstance3D:
				continue
			for sib in pane.get_parent().get_children():
				if sib != pane and sib is MeshInstance3D and (sib as MeshInstance3D).mesh == (extra as MeshInstance3D).mesh \
						and (sib as Node3D).transform.is_equal_approx((extra as Node3D).transform):
					out.append(sib)
	return out


static func _add(mesh: ArrayMesh, verts: PackedVector3Array, norms: PackedVector3Array, mat: Material) -> void:
	if verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	if not norms.is_empty():
		arrays[Mesh.ARRAY_NORMAL] = norms
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, mat)


## A piece's glass (both faces, each wound to face out) and its edges: a crack where other glass lies beyond it, the
## edge of a hole (ink and a light rim) where nothing does, nothing along the frame.
static func _prepare(st: State, pc: Piece) -> void:
	pc.dirty = false
	var hz := st.d * 0.5
	pc.fill = PackedVector3Array()
	pc.fill_n = PackedVector3Array()
	var tris := Geometry2D.triangulate_polygon(pc.poly)
	if tris.is_empty():                       # a crooked outline: as a fan from its middle
		var c := _centroid(pc.poly)
		var fan := PackedVector2Array([c])
		fan.append_array(pc.poly)
		var poly := fan
		for i in pc.poly.size():
			tris.append_array(PackedInt32Array([0, i + 1, (i + 1) % pc.poly.size() + 1]))
		_fill(pc, poly, tris, hz)
	else:
		_fill(pc, pc.poly, tris, hz)
	pc.ink = PackedVector3Array()
	pc.lit = PackedVector3Array()
	pc.thin = PackedVector3Array()
	var band := minf(BAND, sqrt(pc.area) * 0.22)
	var rim := minf(GLINT_W, sqrt(pc.area) * 0.12)
	var n := pc.poly.size()
	for i in n:
		var a := pc.poly[i]
		var b := pc.poly[(i + 1) % n]
		if _on_frame(a, b, st.half):
			continue
		var length := a.distance_to(b)
		if length < 1e-5:
			continue
		var out := Vector2(b.y - a.y, a.x - b.x) / length
		var inn := -out
		var steps := maxi(ceili(length / 0.04), 1)
		for s in steps:
			var s0 := a.lerp(b, float(s) / float(steps))
			var s1 := a.lerp(b, float(s + 1) / float(steps))
			var probe := (s0 + s1) * 0.5 + out * 0.004
			if absf(probe.x) > st.half.x or absf(probe.y) > st.half.y:
				continue
			if _piece_at(st, probe, pc) != null:
				_strip(pc.thin, s0, s1, inn, CRACK_W * 0.5, hz + LIFT)
			else:
				_strip(pc.ink, s0, s1, inn, band, hz + LIFT)
				_strip(pc.lit, s0 + inn * band, s1 + inn * band, inn, rim, hz + LIFT * 0.6)
	for i in range(0, pc.lines.size(), 2):
		var a := pc.lines[i]
		var b := pc.lines[i + 1]
		if a.distance_to(b) < 1e-5:
			continue
		var side := (b - a).normalized().orthogonal()
		_strip(pc.thin, a - side * CRACK_W * 0.5, b - side * CRACK_W * 0.5, side, CRACK_W, hz + LIFT)


static func _fill(pc: Piece, poly: PackedVector2Array, tris: PackedInt32Array, hz: float) -> void:
	for t in range(0, tris.size(), 3):
		var a := poly[tris[t]]
		var b := poly[tris[t + 1]]
		var c := poly[tris[t + 2]]
		var ccw := (b - a).cross(c - a) > 0.0
		# A front face winds clockwise as it is seen: from +z an anticlockwise triangle is turned round.
		for v: Vector2 in ([a, c, b] if ccw else [a, b, c]):
			pc.fill.append(Vector3(v.x, v.y, hz))
			pc.fill_n.append(Vector3(0.0, 0.0, 1.0))
		for v: Vector2 in ([a, b, c] if ccw else [a, c, b]):
			pc.fill.append(Vector3(v.x, v.y, -hz))
			pc.fill_n.append(Vector3(0.0, 0.0, -1.0))


## A strip along a-b, w wide towards `inn`, on both faces (z and -z).
static func _strip(out: PackedVector3Array, a: Vector2, b: Vector2, inn: Vector2, w: float, z: float) -> void:
	var c := b + inn * w
	var d := a + inn * w
	for zz: float in [z, -z]:
		out.append_array(PackedVector3Array([Vector3(a.x, a.y, zz), Vector3(b.x, b.y, zz), Vector3(c.x, c.y, zz),
				Vector3(a.x, a.y, zz), Vector3(c.x, c.y, zz), Vector3(d.x, d.y, zz)]))


# ------------------------------------------------------------------ asking about a pane

## Was this point of a pane (in the world) in a hole? A round through a hole breaks nothing.
static func in_hole(mi: MeshInstance3D, p: Vector3) -> bool:
	var st := _state(mi)
	if st == null:
		return false
	return _piece_at(st, _plane(st, mi, p), null, 0.004) == null


## How much of the pane's glass is left, 0 to 1 (1 for one never hit).
static func left(mi: MeshInstance3D) -> float:
	var st := _state(mi)
	if st == null:
		return 1.0
	var a := 0.0
	for pc: Piece in st.pieces:
		a += pc.area
	return a / maxf(st.whole, 1e-6)


## How many times the pane has been broken (rounds through a hole do not count).
static func hits(mi: MeshInstance3D) -> int:
	var st := _state(mi)
	return st.hits if st else 0


## The other panes showing the same glass (its twins), and it.
static func showing(mi: MeshInstance3D) -> Array:
	var st := _state(mi)
	return st.panes.duplicate() if st else [mi]


## The same broken glass? (a pane and its twin must be)
static func same(a: MeshInstance3D, b: MeshInstance3D) -> bool:
	return _state(a) != null and _state(a) == _state(b)


## What is left of a pane, in words (for the steps).
static func describe(mi: MeshInstance3D) -> String:
	var st := _state(mi)
	if st == null:
		return "whole"
	return "%d hits, %d pieces, %d%% of the glass left" % [st.hits, st.pieces.size(), roundi(left(mi) * 100.0)]


# ------------------------------------------------------------------ car glass, mending

## A block of glass (a car's) hit at `hit`, facing `normal`: a dark hole with light cracks, stuck on it.
static func crack(mi: MeshInstance3D, hit: Vector3, normal: Vector3, rng: RandomNumberGenerator) -> void:
	var marks := 0
	for child in mi.get_children():
		if child.has_meta("combat_fx"):
			marks += 1
	if marks >= 6:
		return
	var r := rng.randf_range(0.08, 0.13)
	var n := 9
	var ring := PackedVector2Array()
	for i in n:
		var a := TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / float(n)
		ring.append(Vector2(cos(a), sin(a)) * r * (rng.randf_range(0.55, 0.8) if i % 2 == 0 else rng.randf_range(0.95, 1.3)))
	var st := SurfaceTool.new()
	var mesh := ArrayMesh.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:                                     # the ink, a little bigger than the hole, under it
		var a0 := ring[i] * (1.0 + BAND / r * 1.6)
		var a1 := ring[(i + 1) % n] * (1.0 + BAND / r * 1.6)
		for v: Vector2 in [Vector2.ZERO, a0, a1]:
			st.add_vertex(Vector3(v.x, v.y, 0.0))
	_commit(st, mesh, _mat(INK))
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		for v: Vector2 in [Vector2.ZERO, ring[i], ring[(i + 1) % n]]:
			st.add_vertex(Vector3(v.x, v.y, 0.0015))
	_commit(st, mesh, _mat(VOID))
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 5:
		var from := ring[rng.randi_range(0, n - 1)]
		var way := from.normalized()
		for j in 2:
			way = way.rotated(rng.randf_range(-0.5, 0.5))
			var to := from + way * rng.randf_range(0.05, 0.12)
			var side := (to - from).normalized().orthogonal() * CRACK_W * 0.5
			for v: Vector2 in [from - side, to - side, to + side, from - side, to + side, from + side]:
				st.add_vertex(Vector3(v.x, v.y, 0.001))
			from = to
	_commit(st, mesh, _mat(CRACK))
	var node := MeshInstance3D.new()
	node.set_meta("combat_fx", true)
	node.mesh = mesh
	mi.add_child(node)
	var z := normal.normalized()
	var x := z.cross(Vector3.UP if absf(z.y) < 0.9 else Vector3.RIGHT).normalized()
	node.global_transform = Transform3D(Basis(x, z.cross(x), z), hit + z * 0.004)


## Add what `st` holds to `mesh` as a surface of its own in `mat` (nothing, if it holds nothing).
static func _commit(st: SurfaceTool, mesh: ArrayMesh, mat: Material) -> void:
	var before := mesh.get_surface_count()
	st.commit(mesh)
	if mesh.get_surface_count() > before:
		mesh.surface_set_material(before, mat)


## How many holes are stuck on a block of glass (a car's).
static func cracks_on(mi: MeshInstance3D) -> int:
	var marks := 0
	for child in mi.get_children():
		if child.has_meta("combat_fx") and not child.is_queued_for_deletion():
			marks += 1
	return marks


## Put a pane or a block of glass back as it was built.
static func mend(mi: MeshInstance3D) -> void:
	if mi.has_meta("broken"):
		var was: Dictionary = mi.get_meta("broken")
		if was.has("node") and is_instance_valid(was["node"]):
			(was["node"] as Node).queue_free()
		var st: State = was.get("state", null)
		if st != null:
			st.panes.erase(mi)
		mi.remove_meta("broken")
		mi.visible = true
		for extra in was.get("extras", []):
			if is_instance_valid(extra):
				(extra as Node3D).visible = true
	for child in mi.get_children():
		if child.has_meta("combat_fx"):
			child.queue_free()
