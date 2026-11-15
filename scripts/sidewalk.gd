extends RefCounted
## Rose Hill Terrace's ground, laid a piece at a time (plans/street.gd uses it):
## the pavement as concrete slabs square to the kerb, a tar-filled expansion
## joint at every party wall and a tooled joint about every 1.6 m between; each
## house's own front strip (concrete, brick, paint, a dead little yard); a
## granite kerb laid in stones, a concrete gutter with a wet line along the foot
## of the kerb, a storm drain, kerb cuts; on the road, patches sealed round with
## tar, sealed cracks, manholes, oil, worn paint. Everything here lies flat:
## nothing in it stands in anyone's way, so it never changes where he can walk.
##
## Numbers are metres on the plan (place.gd's pt: u along the street, v from
## behind the houses). A run "along u" lies along the street; otherwise along v
## (Old York Road), and then its pieces are turned a quarter, so a picture laid
## on one (a crack) runs the same way on both.
##
## The pictures are tools/tex_out.py's (out_concrete, out_slab_*, out_granite,
## out_asphalt_old, out_asphalt_patch, out_dead_grass, out_turf, out_dirt,
## out_tactile, out_tread, out_lid); without them each piece falls back to a
## flat colour. Between begin() and end() the boxes are gathered into a few big
## meshes (see "batching").

const Props := preload("res://scripts/props.gd")

const GAP := 0.02               # a tooled joint
const WIDE := 0.03              # an expansion joint, at a party wall
const STEP := 1.6               # about how far apart the tooled joints are
const JOINT := Color(0.24, 0.22, 0.2)         # the dirt down a joint
const GRIME := Color(0.17, 0.16, 0.15)        # packed into a tooled joint, near the top
const FILL := Color(0.07, 0.07, 0.08)         # tar: in an expansion joint, sealing a crack
const IRON := Color(0.2, 0.2, 0.21)
const RUST := Color(0.36, 0.24, 0.18)
const CONCRETE := Color(0.8, 0.78, 0.74)      # a slab as it came out of the mould
const ROAD_TOP := -0.06         # the road (and the gutter's foot): he walks on one flat floor, the kerb is a 6 cm step
const PAN_TOP := -0.05          # the gutter
const KERB_TOP := 0.02          # the kerb stones stand 2 cm over the pavement
const YELLOW := Color(0.8, 0.67, 0.3)
const WHITE_PAINT := Color(0.86, 0.85, 0.8)

## How each kind of slab is tinted (out_concrete is drawn light).
const TONES := {
	"a": Color(0.92, 0.91, 0.88),       # the run as it was poured
	"b": Color(0.88, 0.87, 0.85),       # its neighbour from the same pour
	"new": Color(1.0, 1.0, 0.98),       # a replacement: paler, cleaner
	"old": Color(0.76, 0.75, 0.73),
	"warm": Color(0.93, 0.87, 0.78),    # a different mix
	"dirty": Color(0.66, 0.65, 0.63),
}
const GRANITE := [Color(0.74, 0.74, 0.73), Color(0.68, 0.68, 0.68), Color(0.78, 0.77, 0.74)]

static var _mats := {}


## A tiling picture from tools/tex_out.py, as Outdoor.tex makes it (the nearest
## texel up close, mipmaps far off); `local` lays the picture once over each
## piece instead, centred on it, `tile_m` metres across (a slab's own crack).
static func look(tex_name: String, tile_m: float, fallback: Color, tint := Color.WHITE, local := false) -> Material:
	var key := "%s_%.2f_%s_%s" % [tex_name, tile_m, tint.to_html(), local]
	if _mats.has(key):
		return _mats[key]
	var path := Kit.TEX_DIR + tex_name + ".png"
	if not ResourceLoader.exists(path):
		_mats[key] = Kit.flat(fallback * tint)
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path)
	m.albedo_color = tint
	m.roughness = 1.0
	m.metallic_specular = 0.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
	m.uv1_triplanar = true
	m.uv1_world_triplanar = not local
	m.uv1_triplanar_sharpness = 8.0
	m.uv1_scale = Vector3.ONE / tile_m
	if local:
		m.uv1_offset = Vector3(0.5, 0.5, 0.5)
	_mats[key] = m
	return m


static func concrete(tone: String) -> Material:
	return look("out_concrete", 2.56, CONCRETE, TONES.get(tone, TONES["a"]))


## A slab's own picture (out_slab_crack and the rest), drawn for a slab 2.4 m square at most.
static func marked(tex_name: String, tone: String, fallback := CONCRETE) -> Material:
	return look(tex_name, 2.4, fallback, TONES.get(tone, TONES["a"]), true)


static func asphalt() -> Material:
	return look("out_asphalt_old", 4.0, Color(0.27, 0.28, 0.32))


static func patch_look() -> Material:
	return look("out_asphalt_patch", 2.0, Color(0.17, 0.17, 0.2))


## One flat piece: a0..a1 along the run, c0..c1 across it, y0..y1. `tilt`:
## degrees about its length and about its width (a heaved slab, a ramp).
static func piece(p: Node3D, n: Node3D, along_u: bool, a0: float, a1: float, c0: float, c1: float, y0: float, y1: float, look_: Variant, tilt := Vector2.ZERO) -> void:
	var mid: Vector3
	if along_u:
		mid = p.pt((a0 + a1) * 0.5, (c0 + c1) * 0.5, (y0 + y1) * 0.5)
	else:
		mid = p.pt((c0 + c1) * 0.5, (a0 + a1) * 0.5, (y0 + y1) * 0.5)
	_box(n, Vector3(a1 - a0, y1 - y0, c1 - c0), mid, look_, Vector3(tilt.x, 0.0 if along_u else 90.0, tilt.y))


## A box on the plan, u0..u1, v0..v1, y0..y1.
static func flat(p: Node3D, n: Node3D, u0: float, u1: float, v0: float, v1: float, y0: float, y1: float, look_: Variant) -> void:
	_box(n, Vector3(u1 - u0, y1 - y0, v1 - v0), p.pt((u0 + u1) * 0.5, (v0 + v1) * 0.5, (y0 + y1) * 0.5), look_)


# ------------------------------------------------------------------ batching

## Between begin() and end(), the boxes laid here are gathered by look and by
## 10 m square, and end() makes one mesh of each gathering: the street's
## thousands of slabs, joints and bits of paint draw in a few hundred calls. The
## lamps light a gathering as they lit its pieces (a mesh takes eight lights at
## most, and no gathering is more than 10 m across). Pieces with a picture laid
## once on each (`local`) stay their own nodes, and so does everything when the
## run is checking faces (flicker_check.gd reads boxes, not meshes).
static var _gather = null           # {key: [node, material, [[transform, size], ...]]} while gathering
static var _unit: Array = []        # a 1 m box: BoxMesh's own vertices, normals and indices


static func begin() -> void:
	_gather = {}
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--check-faces" or (arg.begins_with("--do=") and arg.trim_prefix("--do=").split(",").has("check")):
			_gather = null


static func end() -> void:
	if _gather == null:
		return
	var uv: PackedVector3Array = _unit[0]
	var un: PackedVector3Array = _unit[1]
	var ui: PackedInt32Array = _unit[2]
	for key: String in _gather:
		var e: Array = _gather[key]
		var boxes: Array = e[2]
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var idx := PackedInt32Array()
		verts.resize(boxes.size() * uv.size())
		norms.resize(verts.size())
		idx.resize(boxes.size() * ui.size())
		var vi := 0
		var ii := 0
		for b: Array in boxes:
			var xf: Transform3D = b[0]
			var size: Vector3 = b[1]
			for k in ui.size():
				idx[ii + k] = ui[k] + vi
			for k in uv.size():
				verts[vi + k] = xf * (uv[k] * size)
				norms[vi + k] = xf.basis * un[k]
			ii += ui.size()
			vi += uv.size()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = e[1]
		(e[0] as Node3D).add_child(mi)
	_gather = null


## Kit.box, or into the gathering.
static func _box(n: Node3D, size: Vector3, pos: Vector3, look_: Variant, rot_deg := Vector3.ZERO) -> void:
	var m: Material = look_ if look_ is Material else Kit.flat(look_)
	if _gather == null or (m is BaseMaterial3D and m.uv1_triplanar and not m.uv1_world_triplanar):
		Kit.box(n, size, pos, m, rot_deg)
		return
	if _unit.is_empty():
		var a := BoxMesh.new().get_mesh_arrays()
		_unit = [a[Mesh.ARRAY_VERTEX], a[Mesh.ARRAY_NORMAL], a[Mesh.ARRAY_INDEX]]
	var key := "%d_%d_%d_%d" % [n.get_instance_id(), m.get_instance_id(), floori(pos.x / 10.0), floori(pos.z / 10.0)]
	if not _gather.has(key):
		_gather[key] = [n, m, []]
	_gather[key][2].append([Transform3D(Basis.from_euler(rot_deg * (PI / 180.0)), pos), size])


# ------------------------------------------------------------------ pavement

## A run of pavement one slab across, c0..c1, from a0 to a1: an expansion joint
## (wider, tar in it) at each of `walls`, where one pour met the next, and
## between them a tooled joint about every STEP. `marks`: {where along: kind}
## for the slabs out of the ordinary (see `slab`); the rest are "a" or "b".
## `kerb_side` 1: the kerb is at c1; -1: at c0.
static func run(p: Node3D, n: Node3D, along_u: bool, a0: float, a1: float, c0: float, c1: float, walls: Array, marks: Dictionary, key: float, kerb_side := 1) -> void:
	var cuts: Array = [a0, a1]
	for w: float in walls:
		if w > a0 + 0.05 and w < a1 - 0.05:
			cuts.append(w)
	cuts.sort()
	var i := 0
	for k in range(cuts.size() - 1):
		var s0: float = cuts[k]
		var s1: float = cuts[k + 1]
		var count := maxi(1, roundi((s1 - s0) / STEP))
		var size := (s1 - s0) / count
		var last := ""
		for j in count:
			var b0 := s0 + j * size
			var b1 := b0 + size
			var g0 := WIDE if j == 0 else GAP
			var g1 := WIDE if j == count - 1 else GAP
			var kind := "a" if Props.rnd(key + i * 1.7) < 0.55 else "b"
			for at: float in marks:
				if at >= b0 and at < b1:
					kind = marks[at]
			slab(p, n, along_u, b0 + g0 * 0.5, b1 - g1 * 0.5, c0 + GAP * 0.5, c1 - GAP * 0.5, kind, key + i * 2.3, kerb_side)
			if j > 0:                # the grime packed in the tooled joint, just under the lower slab's top
				piece(p, n, along_u, b0 - GAP * 0.5, b0 + GAP * 0.5, c0 + GAP * 0.5, c1 - GAP * 0.5, -0.06, minf(_top(last), _top(kind)) - 0.004, GRIME)
			last = kind
			i += 1
		if k < cuts.size() - 2:      # the tar in the expansion joint
			piece(p, n, along_u, s1 - WIDE * 0.3, s1 + WIDE * 0.3, c0 + GAP * 0.5, c1 - GAP * 0.5, -0.06, -0.006, FILL)
	# The joint along the kerb, grime in it too, in pieces no longer than 10 m (the lamps).
	var ka := c1 - GAP * 0.5 if kerb_side > 0 else c0
	var kb := c1 if kerb_side > 0 else c0 + GAP * 0.5
	var pieces := ceili((a1 - a0) / 10.0)
	for k in pieces:
		var e0 := lerpf(a0, a1, float(k) / pieces) + (0.01 if k == 0 else 0.0)
		var e1 := lerpf(a0, a1, float(k + 1) / pieces) - (0.01 if k == pieces - 1 else 0.0)
		piece(p, n, along_u, e0, e1, ka, kb, -0.06, -0.004, GRIME)


## How high a kind of slab's top is where it meets the next (see `slab`).
static func _top(kind: String) -> float:
	return {"sunk": -0.02, "split": -0.014, "patch": -0.004}.get(kind, 0.0)


## One slab, a0..a1 by c0..c1 (the joints already taken off), of a kind:
##   "a", "b", "new", "old", "warm", "dirty"   plain, in that tone
##   "crack", "stain", "gum", "shatter"        that picture on it (out_slab_*)
##   "heave"     lifted 3 cm along its kerb edge by a root, cracked across
##   "lift"      lifted 2.5 cm at one end
##   "sunk"      settled 2 cm, dirty
##   "split"     broken in two across the middle, one half sunk
##   "half"      its kerb half dug up and relaid, newer
##   "patch"     dug out and filled with asphalt
##   "brick"     relaid in brick
##   "pit"       an empty tree pit at its kerb end, dirt and weeds in a frame
##   "drive"     a driveway's: darker, oil on it
static func slab(p: Node3D, n: Node3D, along_u: bool, a0: float, a1: float, c0: float, c1: float, kind: String, key: float, kerb_side := 1) -> void:
	var y0 := -0.3
	var width := c1 - c0
	match kind:
		"crack", "stain", "gum", "shatter":
			piece(p, n, along_u, a0, a1, c0, c1, y0, 0.0, marked("out_slab_" + kind, "a"))
		"heave":
			var lift := 0.03
			var angle := rad_to_deg(atan(lift / width)) * (-1.0 if kerb_side > 0 else 1.0)
			piece(p, n, along_u, a0, a1, c0, c1, y0 + lift * 0.5, lift * 0.5, marked("out_slab_shatter", "b"), Vector2(angle, 0.0))
		"lift":
			var lift := 0.025
			piece(p, n, along_u, a0, a1, c0, c1, y0 + lift * 0.5, lift * 0.5, marked("out_slab_crack", "old"), Vector2(0.0, rad_to_deg(atan(lift / (a1 - a0)))))
		"sunk":
			piece(p, n, along_u, a0, a1, c0, c1, y0, -0.02, concrete("dirty"))
		"split":
			var mid := (a0 + a1) * 0.5 + (Props.rnd(key) - 0.5) * 0.3
			piece(p, n, along_u, a0, mid - 0.007, c0, c1, y0, 0.0, marked("out_slab_crack", "b"))
			piece(p, n, along_u, mid + 0.007, a1, c0, c1, y0, -0.014, concrete("old"))
		"half":
			var cut := c0 + width * 0.46 if kerb_side > 0 else c1 - width * 0.46
			piece(p, n, along_u, a0, a1, c0, cut - 0.008, y0, 0.0, concrete("old" if kerb_side > 0 else "new"))
			piece(p, n, along_u, a0, a1, cut + 0.008, c1, y0, 0.0, concrete("new" if kerb_side > 0 else "old"))
		"patch":
			piece(p, n, along_u, a0, a1, c0, c1, y0, -0.004, patch_look())
		"brick":
			piece(p, n, along_u, a0, a1, c0, c1, y0, 0.0, Kit.tex("brick", 1.5, Color(0.5, 0.3, 0.25), true, Color(0.78, 0.72, 0.7)))
		"pit":
			_pit(p, n, along_u, a0, a1, c0, c1, key, kerb_side)
		"drive":
			piece(p, n, along_u, a0, a1, c0, c1, y0, 0.0, marked("out_slab_stain", "dirty"))
		_:
			piece(p, n, along_u, a0, a1, c0, c1, y0, 0.0, concrete(kind))


## A slab with an empty tree pit at its kerb end: the tree long gone, dirt a
## little below the pavement, weeds, a concrete frame round it.
static func _pit(p: Node3D, n: Node3D, along_u: bool, a0: float, a1: float, c0: float, c1: float, key: float, kerb_side: int) -> void:
	var deep := 0.95                  # the pit, across the walk
	var rim := 0.16                   # the concrete either side of it
	var k0 := c1 - 0.06 - deep if kerb_side > 0 else c0 + 0.06
	var k1 := k0 + deep
	var y0 := -0.3
	# The walk side of the slab, the frame along the kerb, either end.
	if kerb_side > 0:
		piece(p, n, along_u, a0, a1, c0, k0 - GAP * 0.5, y0, 0.0, concrete("b"))
		piece(p, n, along_u, a0, a1, k1, c1, y0, 0.0, concrete("old"))
	else:
		piece(p, n, along_u, a0, a1, k1 + GAP * 0.5, c1, y0, 0.0, concrete("b"))
		piece(p, n, along_u, a0, a1, c0, k0, y0, 0.0, concrete("old"))
	piece(p, n, along_u, a0, a0 + rim, k0 + GAP * 0.5, k1, y0, 0.0, concrete("old"))
	piece(p, n, along_u, a1 - rim, a1, k0 + GAP * 0.5, k1, y0, 0.0, concrete("old"))
	piece(p, n, along_u, a0 + rim, a1 - rim, k0 + GAP * 0.5, k1, y0, -0.05, look("out_dirt", 1.2, Color(0.3, 0.24, 0.18)))
	# Weeds: decoration, nothing to trip on.
	var weed := [Color(0.36, 0.42, 0.2), Color(0.5, 0.48, 0.26), Color(0.3, 0.36, 0.18)]
	for w in 6:
		var a := lerpf(a0 + rim + 0.08, a1 - rim - 0.08, Props.rnd(key + w * 3.7))
		var c := lerpf(k0 + 0.1, k1 - 0.1, Props.rnd(key + w * 5.3))
		var h := 0.08 + Props.rnd(key + w * 1.9) * 0.14
		var at: Vector3 = p.pt(a, c, -0.05 + h * 0.5) if along_u else p.pt(c, a, -0.05 + h * 0.5)
		Kit.cyl(n, 0.035 + h * 0.15, h, at, weed[w % 3], Vector3(0, w * 40.0, 0), 5, 0.0)


# -------------------------------------------------------------- house fronts

## A house's own strip between its porch steps and the pavement, u0..u1 by
## v0..v1 (the joints already taken off), the steps at `door` (1.25 wide):
##   "concrete", "new", "old"  a slab either side of the walk and one in front of the steps
##   "yard"      dead grass either side of a concrete walk
##   "brick"     brick pavers, two of them gone
##   "paint"     concrete painted (porch paint), worn through on the walk
##   "turf"      plastic grass either side of the walk
static func front(p: Node3D, n: Node3D, u0: float, u1: float, v0: float, v1: float, door: float, kind: String, key: float, paint := Color(0.45, 0.49, 0.5)) -> void:
	var w0 := door - 0.66
	var w1 := door + 0.66
	var y0 := -0.3
	var sides: Array = []                 # [from, to] either side of the walk, if wide enough
	if w0 - u0 > 0.12:
		sides.append([u0, w0 - GAP * 0.5])
	if u1 - w1 > 0.12:
		sides.append([w1 + GAP * 0.5, u1])
	var walk_u0 := w0 + GAP * 0.5 if w0 - u0 > 0.12 else u0
	var walk_u1 := w1 - GAP * 0.5 if u1 - w1 > 0.12 else u1
	match kind:
		"yard", "turf":
			var grass: Material = look("out_dead_grass", 1.6, Color(0.46, 0.42, 0.27)) if kind == "yard" else look("out_turf", 1.0, Color(0.27, 0.41, 0.26))
			for s: Array in sides:
				if float(s[1]) - float(s[0]) < 0.4:
					piece(p, n, true, s[0], s[1], v0, v1, y0, 0.0, concrete("old"))
				else:
					piece(p, n, true, s[0], s[1], v0, v1, y0, -0.012 if kind == "yard" else 0.004, grass)
			piece(p, n, true, walk_u0, walk_u1, v0, v1, y0, 0.0, concrete("b"))
		"brick":
			var brick := Kit.tex("brick", 1.2, Color(0.5, 0.3, 0.25), true, Color(0.82, 0.72, 0.68))
			piece(p, n, true, u0, u1, v0, v1, y0, 0.0, brick)
			for b in 2:                   # two pavers gone, dirt in the holes
				var bu := lerpf(u0 + 0.3, u1 - 0.3, Props.rnd(key + b * 7.1))
				var bv := lerpf(v0 + 0.95, v1 - 0.2, Props.rnd(key + b * 3.3))
				flat(p, n, bu - 0.1, bu + 0.1, bv - 0.05, bv + 0.05, -0.02, 0.003, Color(0.25, 0.2, 0.16))
		"paint":
			var painted := Kit.flat(paint)
			for s: Array in sides:
				piece(p, n, true, s[0], s[1], v0, v1, y0, 0.0, painted)
			piece(p, n, true, walk_u0, walk_u1, v0, v1, y0, 0.0, Kit.flat(paint.lerp(Color(0.62, 0.6, 0.57), 0.55)))
		_:
			var tone := kind if TONES.has(kind) else "a"
			for s: Array in sides:
				piece(p, n, true, s[0], s[1], v0, v1, y0, 0.0, concrete(tone))
			piece(p, n, true, walk_u0, walk_u1, v0, v1, y0, 0.0, concrete("b" if tone == "a" else tone))


## Where a porch meets the ground: a dark footing along the deck's front, u0..u1
## (none if that is empty: a stoop), and a grimy band round the foot of the
## steps, a centimetre proud of them.
static func footing(p: Node3D, n: Node3D, u0: float, u1: float, deck: float, door: float, steps_w: float, steps_d: float) -> void:
	if u1 - u0 > 0.02:
		flat(p, n, u0 + 0.005, u1 - 0.005, deck - 0.02, deck + 0.02, -0.05, 0.1, Color(0.36, 0.35, 0.37))
	flat(p, n, door - steps_w * 0.5 - 0.01, door + steps_w * 0.5 + 0.01, deck, deck + steps_d + 0.01, -0.05, 0.035, Color(0.3, 0.28, 0.28))


# ---------------------------------------------------------- kerb and gutter

## The kerb, c0..c1 across: granite stones 1.6 to 2.2 m long, 6 mm apart, their
## tops 2 cm over the pavement. `cuts`: [[from, to, what], ...] along it, where
## "gap" leaves it out (a ramp goes there), "drop" lays it low (a driveway) and
## "inlet" opens a storm drain's mouth in its face; `face` 1: the face is at c1.
static func kerb(p: Node3D, n: Node3D, along_u: bool, a0: float, a1: float, c0: float, c1: float, cuts: Array, key: float, face := 1) -> void:
	var marks: Array = [a0, a1]
	for cut: Array in cuts:
		marks.append(clampf(cut[0], a0, a1))
		marks.append(clampf(cut[1], a0, a1))
	marks.sort()
	var i := 0
	for k in range(marks.size() - 1):
		var s0: float = marks[k]
		var s1: float = marks[k + 1]
		if s1 - s0 < 0.01:
			continue
		var what := ""
		for cut: Array in cuts:
			if (s0 + s1) * 0.5 > float(cut[0]) and (s0 + s1) * 0.5 < float(cut[1]):
				what = cut[2]
		if what == "gap":
			continue
		var top := -0.03 if what == "drop" else KERB_TOP
		var a := s0
		while a < s1 - 0.01:
			var b := minf(a + 1.6 + Props.rnd(key + i * 3.1) * 0.6, s1)
			if s1 - b < 0.7:
				b = s1
			piece(p, n, along_u, a + 0.003, b - 0.003, c0, c1, -0.3, top, look("out_granite", 1.0, Color.WHITE, GRANITE[i % 3]))
			a = b
			i += 1
		if what == "inlet":
			# The drain's mouth: a dark slot along the foot of the face, a steel edge over it.
			var cf := c1 if face > 0 else c0
			var out := 0.01 * face
			piece(p, n, along_u, s0 + 0.05, s1 - 0.05, minf(cf, cf + out), maxf(cf, cf + out), PAN_TOP, -0.012, FILL)
			piece(p, n, along_u, s0, s1, minf(cf, cf + out * 1.4), maxf(cf, cf + out * 1.4), -0.012, KERB_TOP - 0.004, IRON)


## The concrete gutter along a kerb, from the kerb's face (c_kerb) out to
## c_out, in sections about 3 m long; a darker wet line 6 cm wide down its kerb side.
static func gutter(p: Node3D, n: Node3D, along_u: bool, a0: float, a1: float, c_kerb: float, c_out: float, key: float) -> void:
	var count := maxi(1, roundi((a1 - a0) / 3.0))
	var size := (a1 - a0) / count
	var sgn := 1.0 if c_out > c_kerb else -1.0
	var foot := c_kerb + 0.003 * sgn             # 3 mm off the kerb's face, so the two never lie in one plane
	var wet := c_kerb + 0.06 * sgn
	for i in count:
		var s0 := a0 + i * size + 0.005
		var s1 := a0 + (i + 1) * size - 0.005
		var tone := "old" if Props.rnd(key + i * 2.9) < 0.6 else "dirty"
		piece(p, n, along_u, s0, s1, minf(wet, c_out), maxf(wet, c_out), -0.36, PAN_TOP, concrete(tone))
		piece(p, n, along_u, s0, s1, minf(foot, wet), maxf(foot, wet), -0.36, PAN_TOP - 0.003, Kit.flat(Color(0.25, 0.25, 0.27)))


## A storm drain in the gutter by a kerb's inlet (kerb(): "inlet"): an iron
## grate, its bars across the flow. Along u, the kerb on the -v side.
static func drain(p: Node3D, n: Node3D, u0: float, u1: float, v0: float, v1: float) -> void:
	flat(p, n, u0 + 0.01, u1 - 0.01, v0 + 0.01, v1 - 0.01, PAN_TOP - 0.03, PAN_TOP + 0.004, FILL)
	flat(p, n, u0, u1, v0, v0 + 0.04, PAN_TOP - 0.03, PAN_TOP + 0.008, IRON)
	flat(p, n, u0, u1, v1 - 0.04, v1, PAN_TOP - 0.03, PAN_TOP + 0.008, IRON)
	var bars := int((u1 - u0) / 0.09)
	for b in bars:
		var u := u0 + (b + 0.5) * (u1 - u0) / bars
		flat(p, n, u - 0.022, u + 0.022, v0 + 0.04, v1 - 0.04, PAN_TOP - 0.03, PAN_TOP + 0.008, IRON)


## A kerb cut: a ramp a0..a1 wide, running down across from c_hi (pavement
## level) to c_lo (the gutter's), through the gap left in the kerb; a red pad
## of raised dots at its foot.
static func ramp(p: Node3D, n: Node3D, along_u: bool, a0: float, a1: float, c_hi: float, c_lo: float) -> void:
	var drop := -PAN_TOP          # 5 cm down to the gutter
	var run_len := absf(c_lo - c_hi)
	var angle := rad_to_deg(atan(drop / run_len)) * (1.0 if c_lo > c_hi else -1.0)
	piece(p, n, along_u, a0, a1, minf(c_hi, c_lo), maxf(c_hi, c_lo), -0.3 - drop * 0.5, -drop * 0.5, concrete("new"), Vector2(angle, 0.0))
	# The pad: 0.6 m deep, at the foot, its top 4 mm over the slope.
	var sgn := 1.0 if c_lo > c_hi else -1.0
	var pc := c_lo - sgn * 0.35                       # its middle, across
	var y := -drop * (absf(pc - c_hi) / run_len) + 0.004
	piece(p, n, along_u, a0 + 0.15, a1 - 0.15, pc - 0.3, pc + 0.3, y - 0.02, y, look("out_tactile", 0.6, Color(0.55, 0.2, 0.15)), Vector2(angle, 0.0))


# ------------------------------------------------------------- on the ground

## An iron lid set in the pavement (its top 5 mm proud): "water" a meter's
## round lid, "gas" a little round valve box, "vault" a plate of diamond tread,
## "cleanout" a small square cap.
static func lid(p: Node3D, n: Node3D, u: float, v: float, kind: String) -> void:
	match kind:
		"water":
			Kit.cyl(n, 0.17, 0.02, p.pt(u, v, -0.007), Color(0.5, 0.49, 0.47), Vector3.ZERO, 14)
			Kit.cyl(n, 0.14, 0.02, p.pt(u, v, -0.005), look("out_lid", 0.3, IRON, Color.WHITE, true), Vector3.ZERO, 14)
		"gas":
			Kit.cyl(n, 0.075, 0.02, p.pt(u, v, -0.005), Color(0.3, 0.3, 0.3), Vector3.ZERO, 10)
			Kit.cyl(n, 0.045, 0.02, p.pt(u, v, -0.004), Color(0.75, 0.62, 0.2), Vector3.ZERO, 8)
		"vault":
			flat(p, n, u - 0.32, u + 0.32, v - 0.47, v + 0.47, -0.05, 0.004, look("out_tread", 0.5, IRON))
		"cleanout":
			flat(p, n, u - 0.09, u + 0.09, v - 0.09, v + 0.09, -0.05, 0.005, IRON)


## A manhole in the road: a square of newer asphalt round it where it was
## reset, the iron frame, the cover.
static func manhole(p: Node3D, n: Node3D, u: float, v: float, r := 0.36) -> void:
	flat(p, n, u - r - 0.3, u + r + 0.3, v - r - 0.3, v + r + 0.3, ROAD_TOP - 0.002, ROAD_TOP + 0.005, patch_look())
	Kit.cyl(n, r + 0.05, 0.02, p.pt(u, v, ROAD_TOP - 0.002), IRON, Vector3.ZERO, 16)
	Kit.cyl(n, r, 0.02, p.pt(u, v, ROAD_TOP + 0.001), look("out_lid", r * 2.0, Color(0.24, 0.24, 0.25), Color.WHITE, true), Vector3.ZERO, 16)


## A patch in the road, u0..u1 by v0..v1 (where it was dug up): darker, newer
## asphalt, a band of tar sealing it all round.
static func patch(p: Node3D, n: Node3D, u0: float, u1: float, v0: float, v1: float) -> void:
	var y0 := ROAD_TOP - 0.002          # all of it a thin skin on the road
	flat(p, n, u0, u1, v0, v1, y0, ROAD_TOP + 0.006, patch_look())
	var s := 0.04
	flat(p, n, u0 - s, u1 + s, v0 - s, v0, y0, ROAD_TOP + 0.007, FILL)
	flat(p, n, u0 - s, u1 + s, v1, v1 + s, y0, ROAD_TOP + 0.007, FILL)
	flat(p, n, u0 - s, u0, v0, v1, y0, ROAD_TOP + 0.007, FILL)
	flat(p, n, u1, u1 + s, v0, v1, y0, ROAD_TOP + 0.007, FILL)


## A crack in the road sealed with tar: a black line through `pts` (plan
## points), 4 cm wide, lying on the road, each leg broken into short kinks
## `jitter` metres either side (0: straight legs, as along the gutter).
static func tar_line(p: Node3D, n: Node3D, pts: Array, w := 0.04, jitter := 0.05) -> void:
	var line: Array = [pts[0]]
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var k := maxi(1, ceili(a.distance_to(b) / 0.45)) if jitter > 0.0 else 1
		var side := (b - a).orthogonal().normalized()
		for j in range(1, k + 1):
			var at := a.lerp(b, float(j) / k)
			if j < k:
				at += side * (Props.rnd(at.x * 3.1 + at.y * 1.7) - 0.5) * 2.0 * jitter
			line.append(at)
	for i in range(line.size() - 1):
		var a: Vector2 = line[i]
		var b: Vector2 = line[i + 1]
		var d := b - a
		var mid := (a + b) * 0.5
		_box(n, Vector3(d.length() + w * 0.6, 0.006, w), p.pt(mid.x, mid.y, ROAD_TOP + 0.0), FILL, Vector3(0, rad_to_deg(atan2(-d.y, d.x)), 0))


## A wandering line from `from`, heading `dir` (degrees on the plan: 0 along +u,
## 90 along +v), `steps` legs of `leg` metres, for tar_line.
static func wander(from: Vector2, dir: float, steps: int, leg: float, key: float, wobble := 28.0) -> Array:
	var pts: Array = [from]
	var at := from
	var heading := dir
	for i in steps:
		heading += (Props.rnd(key + i * 1.31) - 0.5) * wobble * 2.0
		heading = lerpf(heading, dir, 0.35)
		at += Vector2(cos(deg_to_rad(heading)), sin(deg_to_rad(heading))) * leg * (0.7 + Props.rnd(key + i * 2.7) * 0.6)
		pts.append(at)
	return pts


## Oil dropped by parked cars: a dark flat blot on the road, ragged (three
## ellipses run together), darker where most dripped.
static func oil(p: Node3D, n: Node3D, u: float, v: float, w: float, d: float, turn := 0.0) -> void:
	var dark := Color(0.21, 0.21, 0.23)
	for b: Array in [[0.0, 0.0, 1.0, 1.0, 0.0, dark], [0.3, 0.2, 0.62, 0.55, 50.0, dark], [-0.32, -0.12, 0.45, 0.5, -30.0, dark], [0.06, -0.05, 0.42, 0.45, 20.0, Color(0.16, 0.16, 0.18)]]:
		var at := Vector2(float(b[0]) * w, float(b[1]) * d).rotated(deg_to_rad(-turn))
		var blot := Kit.cyl(n, 0.5, 0.004, p.pt(u + at.x, v + at.y, ROAD_TOP + 0.001 + (0.001 if b[5] != dark else 0.0)), b[5], Vector3(0, turn + float(b[4]), 0), 9)
		blot.scale = Vector3(w * float(b[2]), 1.0, d * float(b[3]))


## Paint on the road, u0..u1 by v0..v1, worn: cut into pieces about `bit` long
## with some missing (`wear` 0: whole .. 1: mostly gone) and some faded more.
static func paint(p: Node3D, n: Node3D, u0: float, u1: float, v0: float, v1: float, colour: Color, key: float, wear := 0.3, bit := 0.4, fade := 0.12) -> void:
	var along_u := u1 - u0 >= v1 - v0
	var a0 := u0 if along_u else v0
	var a1 := u1 if along_u else v1
	var pieces := maxi(1, roundi((a1 - a0) / bit))
	var size := (a1 - a0) / pieces
	for i in pieces:
		var r := Props.rnd(key + i * 1.9)
		if r < wear:
			continue
		var s0 := a0 + i * size
		var s1 := s0 + size
		if r < wear * 1.5:                      # half gone
			s1 = s0 + size * 0.5
		var tone := colour.lerp(Color(0.42, 0.42, 0.44), fade * floorf(Props.rnd(key + i * 3.7) * 3.0))
		# A skin of paint lying on the road, clear of its faces.
		if along_u:
			flat(p, n, s0, s1, v0, v1, ROAD_TOP + 0.0005, ROAD_TOP + 0.004, tone)
		else:
			flat(p, n, u0, u1, s0, s1, ROAD_TOP + 0.0005, ROAD_TOP + 0.004, tone)
