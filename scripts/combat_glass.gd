extends RefCounted
## Glass that shots break. Whatever builds a pane of glass marks it with Kit.pane() (place.gd's windows,
## houses.gd's sashes, Kit.window, the studio's windows, cars), so a new place gets breakable windows as soon
## as it uses any of those.
##
## A pane (a box thin one way) gets a jagged hole where it is hit: the original box is hidden and the glass that
## is left is drawn in its place, in the pane's own material, with an ink line round the hole and cracks running
## from it. Clear glass shows what is behind through the hole; a pane drawn dark or lit (a house window) shows a
## dark hole. Hit again it breaks wider, and a third time only a jagged fringe is left in the frame. A block of
## glass (a car's glasshouse) is not broken through: it gets a dark hole with cracks where it is hit.
## It all stays broken while the place is loaded, until mend() (a new day).

const INK := Color(0.03, 0.02, 0.05)
const VOID := Color(0.035, 0.03, 0.05)
const CRACK := Color(0.86, 0.92, 0.97)        # cracks on dark glass are light
const BAND := 0.014                           # metres: the ink round a hole
const CRACK_W := 0.007

static var _mats := {}


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


## Is the pane see-through (clear glass) rather than drawn dark or lit?
static func clear(mi: MeshInstance3D) -> bool:
	var mat := mi.get_active_material(0)
	return mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and (mat as BaseMaterial3D).albedo_color.a < 0.95


## Break a pane where `hit` is (in the world). `twins` are panes in exactly the same spot (the studio's
## see-through copy of a wall), broken the same way. Returns where the hole is, for the shards:
## {"center": Vector3, "normal": Vector3, "radius": float, "clear": bool}.
static func shatter(mi: MeshInstance3D, hit: Vector3, rng: RandomNumberGenerator, twins: Array = []) -> Dictionary:
	var s: Vector3 = (mi.mesh as BoxMesh).size
	var k := 0 if s.x <= s.y and s.x <= s.z else (1 if s.y <= s.z else 2)       # the thin way
	var ia := (k + 1) % 3
	var ja := (k + 2) % 3
	var half := Vector2(s[ia], s[ja]) * 0.5
	var lh := mi.global_transform.affine_inverse() * hit
	var p := Vector2(lh[ia], lh[ja])
	var was: Dictionary = mi.get_meta("broken", {})
	var hits := int(was.get("hits", 0)) + 1
	var c: Vector2 = p if hits == 1 else (was["c"] as Vector2).lerp(p, 0.5)
	c = c.clamp(-half * 0.8, half * 0.8)
	var r := minf(half.x, half.y) * 2.0 * (0.36 + 0.22 * float(hits - 1)) * rng.randf_range(0.85, 1.1)
	var plan := _plan(c, r, half, hits, rng)
	plan["k"] = k
	plan["ia"] = ia
	plan["ja"] = ja
	plan["d"] = s[k]
	for pane: MeshInstance3D in [mi] + twins:
		_build(pane, plan)
		var keep: Dictionary = pane.get_meta("broken", {})
		keep["hits"] = hits
		keep["c"] = c
		pane.set_meta("broken", keep)
	var n := Vector3.ZERO
	n[k] = 1.0
	var centre := Vector3.ZERO
	centre[ia] = c.x
	centre[ja] = c.y
	return {"center": mi.global_transform * centre, "normal": (mi.global_transform.basis * n).normalized(),
			"radius": r if hits < 3 else minf(half.x, half.y), "clear": clear(mi)}


## The hole and the glass left round it, in the pane's own plane (x, y across it; (0, 0) its middle).
static func _plan(c: Vector2, r: float, half: Vector2, hits: int, rng: RandomNumberGenerator) -> Dictionary:
	var n := 9 + rng.randi_range(0, 4)
	var hole := PackedVector2Array()
	var edge := PackedVector2Array()
	var angles := PackedFloat32Array()
	for i in n:
		var a := TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / float(n)
		var d := Vector2(cos(a), sin(a))
		var reach := _to_edge(c, d, half)
		var want := r * (rng.randf_range(0.5, 0.78) if i % 2 == 0 else rng.randf_range(0.95, 1.4))
		var length := clampf(want, 0.02, reach * 0.93)
		if hits >= 3:                     # all but a fringe in the frame
			length = maxf(reach - rng.randf_range(0.015, 0.07), 0.01)
		hole.append(c + d * length)
		edge.append(c + d * reach)
		angles.append(a)
	var cracks: Array = []
	for i in rng.randi_range(3, 5):
		var at := rng.randi_range(0, n - 1)
		var from: Vector2 = hole[at]
		var line := PackedVector2Array([from])
		var way := (from - c).normalized()
		for j in rng.randi_range(2, 3):
			way = way.rotated(rng.randf_range(-0.45, 0.45))
			var next: Vector2 = (from + way * rng.randf_range(0.05, 0.16)).clamp(-half + Vector2(0.01, 0.01), half - Vector2(0.01, 0.01))
			line.append(next)
			from = next
		cracks.append(line)
	return {"c": c, "half": half, "hole": hole, "edge": edge, "angles": angles, "cracks": cracks}


## How far from c, going along d, the edge of the pane is.
static func _to_edge(c: Vector2, d: Vector2, half: Vector2) -> float:
	var t := INF
	if d.x > 1e-6:
		t = minf(t, (half.x - c.x) / d.x)
	elif d.x < -1e-6:
		t = minf(t, (-half.x - c.x) / d.x)
	if d.y > 1e-6:
		t = minf(t, (half.y - c.y) / d.y)
	elif d.y < -1e-6:
		t = minf(t, (-half.y - c.y) / d.y)
	return maxf(t, 0.0)


static func _build(pane: MeshInstance3D, plan: Dictionary) -> void:
	var was: Dictionary = pane.get_meta("broken", {})
	var node: MeshInstance3D = was.get("node", null) if was.has("node") else null
	if node == null or not is_instance_valid(node):
		node = MeshInstance3D.new()
		node.set_meta("combat_fx", true)
		node.name = String(pane.name) + "Broken"
		pane.get_parent().add_child(node)
	node.transform = pane.transform
	var k: int = plan["k"]
	var ia: int = plan["ia"]
	var ja: int = plan["ja"]
	var d: float = plan["d"]
	var at := func(p: Vector2, z: float) -> Vector3:
		var v := Vector3.ZERO
		v[ia] = p.x
		v[ja] = p.y
		v[k] = z
		return v
	var normal := Vector3.ZERO
	normal[k] = 1.0
	var c: Vector2 = plan["c"]
	var half: Vector2 = plan["half"]
	var hole: PackedVector2Array = plan["hole"]
	var edge: PackedVector2Array = plan["edge"]
	var angles: PackedFloat32Array = plan["angles"]
	var corners := [Vector2(half.x, half.y), Vector2(-half.x, half.y), Vector2(-half.x, -half.y), Vector2(half.x, -half.y)]
	var mesh := ArrayMesh.new()

	# The glass left, in the pane's material: one piece for each slice of the hole, out to the frame.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := hole.size()
	for i in n:
		var j := (i + 1) % n
		var poly := PackedVector2Array([hole[i], edge[i]])
		var span := wrapf(angles[j] - angles[i], 0.0, TAU)
		var inside: Array = []
		for corner: Vector2 in corners:
			var rel := wrapf((corner - c).angle() - angles[i], 0.0, TAU)
			if rel > 0.0 and rel < span:
				inside.append([rel, corner])
		inside.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		for item: Array in inside:
			poly.append(item[1])
		poly.append(edge[j])
		poly.append(hole[j])
		var tris := Geometry2D.triangulate_polygon(poly)
		for t in range(0, tris.size(), 3):
			for side: float in [1.0, -1.0]:
				var z := d * 0.5 * side
				st.set_normal(normal * side)
				for v: int in ([tris[t], tris[t + 1], tris[t + 2]] if side > 0.0 else [tris[t], tris[t + 2], tris[t + 1]]):
					st.add_vertex(at.call(poly[v], z))
	_commit(st, mesh, pane.get_active_material(0))

	# The ink round the hole and the cracks, on both faces.
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var j := (i + 1) % n
		var a0 := hole[i]
		var a1 := hole[j]
		var b0 := a0 + (a0 - c).normalized() * BAND
		var b1 := a1 + (a1 - c).normalized() * BAND
		_quad(st, at, [a0, a1, b1, b0], d)
	for line: PackedVector2Array in plan["cracks"]:
		for i in line.size() - 1:
			var side := (line[i + 1] - line[i]).normalized().orthogonal() * CRACK_W * 0.5
			_quad(st, at, [line[i] - side, line[i + 1] - side, line[i + 1] + side, line[i] + side], d)
	_commit(st, mesh, _mat(INK))

	# A pane drawn dark or lit has nothing to see through: the hole is dark.
	if not clear(pane):
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in n:
			var j := (i + 1) % n
			for v: Vector2 in [c, hole[i], hole[j]]:
				st.add_vertex(at.call(v, 0.0))
			for v: Vector2 in [c, hole[j], hole[i]]:
				st.add_vertex(at.call(v, 0.0))
		_commit(st, mesh, _mat(VOID))
	node.mesh = mesh
	pane.visible = false
	for path: NodePath in pane.get_meta("glass", []):
		var extra := pane.get_node_or_null(path)
		if extra is Node3D:
			(extra as Node3D).visible = false
	var keep: Dictionary = pane.get_meta("broken", {})
	keep["node"] = node
	pane.set_meta("broken", keep)


## Add what `st` holds to `mesh` as a surface of its own in `mat` (nothing, if it holds nothing).
static func _commit(st: SurfaceTool, mesh: ArrayMesh, mat: Material) -> void:
	var before := mesh.get_surface_count()
	st.commit(mesh)
	if mesh.get_surface_count() > before:
		mesh.surface_set_material(before, mat)


## A strip on both faces, just proud of them.
static func _quad(st: SurfaceTool, at: Callable, q: Array, d: float) -> void:
	for side: float in [1.0, -1.0]:
		var z := (d * 0.5 + 0.0012) * side
		for v: Vector2 in [q[0], q[1], q[2], q[0], q[2], q[3]]:
			st.add_vertex(at.call(v, z))
		for v: Vector2 in [q[0], q[2], q[1], q[0], q[3], q[2]]:
			st.add_vertex(at.call(v, z))


## Was this point of a broken pane (in the world) in its hole? A shot through the hole breaks nothing more.
static func in_hole(mi: MeshInstance3D, p: Vector3) -> bool:
	var was: Dictionary = mi.get_meta("broken", {})
	if was.is_empty() or not was.has("node"):
		return false
	var mesh: ArrayMesh = (was["node"] as MeshInstance3D).mesh
	if mesh == null:
		return false
	var s: Vector3 = (mi.mesh as BoxMesh).size
	var k := 0 if s.x <= s.y and s.x <= s.z else (1 if s.y <= s.z else 2)
	var lh := mi.global_transform.affine_inverse() * p
	var q := Vector2(lh[(k + 1) % 3], lh[(k + 2) % 3])
	if int(was.get("hits", 0)) >= 3:
		return true
	return q.distance_to(was["c"]) < 0.03 + minf(s[(k + 1) % 3], s[(k + 2) % 3]) * 0.3


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


## Put a pane or a block of glass back as it was built.
static func mend(mi: MeshInstance3D) -> void:
	if mi.has_meta("broken"):
		var was: Dictionary = mi.get_meta("broken")
		if was.has("node") and is_instance_valid(was["node"]):
			(was["node"] as Node).queue_free()
		mi.remove_meta("broken")
		mi.visible = true
		for path: NodePath in mi.get_meta("glass", []):
			var extra := mi.get_node_or_null(path)
			if extra is Node3D:
				(extra as Node3D).visible = true
	for child in mi.get_children():
		if child.has_meta("combat_fx"):
			child.queue_free()
