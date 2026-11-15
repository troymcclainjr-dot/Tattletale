extends RefCounted
## What a shot can hit in a place, without physics (nothing here has colliders): every mesh of the place,
## gathered the first time something is fired there and sorted into a grid on the floor plan. A segment is
## tested against the meshes in the grid cells it crosses: a box exactly, anything else by its triangles.
##
## Not hit: what cannot be seen (a wall cut away, a band hidden), see-through stuff (a wall faded to a ghost,
## a car faded out of the way, light cones), people (combat_people.gd tests those) and the marks of shots.
## Glass (Kit.pane) is reported on the way: a pane is broken through and the shot goes on; a block of glass
## (a car's glasshouse) stops it.

const PaperActor := preload("res://scripts/paper_actor.gd")
const CELL := 2.0               # metres: the grid's squares
const MANY_FACES := 4000        # a mesh with more triangles than this is hit on its box


class Entry:
	var mi: MeshInstance3D
	var glass := false
	var thin := false           # glass: a pane rather than a block
	var box := false            # a BoxMesh: tested exactly against its box
	var dyn := false            # it moves (a door): its box is found each time
	var metal := false
	var aabb := AABB()
	var stamp := 0


var root: Node3D
var _entries: Array = []
var _dyn: Array = []
var _grid := {}                 # Vector2i: Array of Entry
var _stamp := 0
var _faces := {}                # a mesh's instance id: its triangles


## Gather the place under `root`. `doors` are nodes whose meshes move.
func build(place: Node3D, doors: Array) -> void:
	root = place
	var moving := {}
	for door: Node in doors:
		moving[door] = true
	_walk(place, false, moving)
	# What stands round a block of glass is a car: it is metal.
	var cars := {}
	for e: Entry in _entries:
		if e.glass and not e.thin:
			cars[e.mi.get_parent()] = true
	for e: Entry in _entries:
		if cars.has(e.mi.get_parent()) and not e.glass:
			e.metal = true


func _walk(node: Node, dyn: bool, moving: Dictionary) -> void:
	if node.get_script() == PaperActor or node.has_meta("combat_fx"):
		return
	var here := dyn or moving.has(node)
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		_add(node, here)
	for child in node.get_children():
		_walk(child, here, moving)


func _add(mi: MeshInstance3D, dyn: bool) -> void:
	var e := Entry.new()
	e.mi = mi
	e.glass = mi.has_meta("glass")
	if e.glass and see_through(mi) and ((mi.get_active_material(0) as BaseMaterial3D).albedo_color.a < 0.03):
		return                       # a pane of nothing (an opening drawn as a window): shots go through
	e.box = mi.mesh is BoxMesh
	e.dyn = dyn
	e.thin = e.glass and is_thin(mi)
	e.metal = not e.glass and _looks_metal(mi)
	_entries.append(e)
	if dyn:
		_dyn.append(e)
		return
	e.aabb = mi.global_transform * mi.get_aabb()
	var c0 := Vector2i(floori(e.aabb.position.x / CELL), floori(e.aabb.position.z / CELL))
	var c1 := Vector2i(floori(e.aabb.end.x / CELL), floori(e.aabb.end.z / CELL))
	for x in range(c0.x, c1.x + 1):
		for z in range(c0.y, c1.y + 1):
			var key := Vector2i(x, z)
			if not _grid.has(key):
				_grid[key] = []
			_grid[key].append(e)


## A pane: a box thin one way (a window, a door's little pane), not a block of glass.
static func is_thin(mi: MeshInstance3D) -> bool:
	if not mi.mesh is BoxMesh:
		return false
	var s := (mi.mesh as BoxMesh).size * mi.global_transform.basis.get_scale().abs()
	var d := [s.x, s.y, s.z]
	d.sort()
	return d[0] <= 0.13 and d[0] <= 0.35 * d[1]


## A thin grey thing (a pole, a rail, a post) sparks.
func _looks_metal(mi: MeshInstance3D) -> bool:
	var mat := mi.get_active_material(0)
	if not mat is BaseMaterial3D:
		return false
	var c: Color = (mat as BaseMaterial3D).albedo_color
	if c.s > 0.18 or c.v < 0.18 or c.v > 0.85 or (mat as BaseMaterial3D).albedo_texture != null:
		return false
	var s := mi.get_aabb().size * mi.global_transform.basis.get_scale().abs()
	var d := [s.x, s.y, s.z]
	d.sort()
	return d[1] <= 0.12


## Shots go through it: faint (a ghost wall, a faded car) or a picture with holes in it (chain link).
static func see_through(mi: MeshInstance3D) -> bool:
	var mat := mi.get_active_material(0)
	if mat is BaseMaterial3D:
		var bm := mat as BaseMaterial3D
		if bm.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
			return false
		return bm.albedo_color.a < 0.5 or bm.albedo_texture != null      # faint, or a picture with holes (chain link)
	return false


## Every pane and block of glass gathered here.
func glass() -> Array:
	var out: Array = []
	for e: Entry in _entries:
		if e.glass:
			out.append(e)
	return out


## The first thing a segment from `from` to `to` hits, and the panes it goes through before that:
## {"hit": bool, "t": 0..1 along it, "pos", "normal", "mi", "metal", "block" (a block of glass),
## "panes": [{"t", "pos", "normal", "entry"}] nearest first}.
func trace(from: Vector3, to: Vector3) -> Dictionary:
	_stamp += 1
	var best := {"hit": false, "t": 1.0, "pos": to, "normal": Vector3.UP, "mi": null, "metal": false, "block": false}
	var panes: Array = []
	for e: Entry in _dyn:
		_test(e, from, to, best, panes)
	for key: Vector2i in _cells(from, to):
		for e: Entry in _grid.get(key, []):
			if e.stamp != _stamp:
				e.stamp = _stamp
				_test(e, from, to, best, panes)
	var before: Array = []
	for p: Dictionary in panes:
		if float(p["t"]) < float(best["t"]):
			before.append(p)
	before.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"]))
	best["panes"] = before
	return best


func _test(e: Entry, from: Vector3, to: Vector3, best: Dictionary, panes: Array) -> void:
	var mi := e.mi
	if not is_instance_valid(mi):
		return
	if e.glass and e.thin and mi.has_meta("broken"):
		if not mi.get_parent().is_visible_in_tree():      # broken, it is hidden: what is left of it still counts
			return
	elif not mi.is_visible_in_tree() or (not e.glass and see_through(mi)):
		return
	var aabb := e.aabb if not e.dyn else mi.global_transform * mi.get_aabb()
	if aabb.grow(0.02).intersects_segment(from, to) == null:
		return
	var hit := _precise(e, from, to)
	if hit.is_empty():
		return
	if e.glass and e.thin:
		hit["entry"] = e
		panes.append(hit)
	elif float(hit["t"]) < float(best["t"]):
		best["hit"] = true
		best["t"] = hit["t"]
		best["pos"] = hit["pos"]
		best["normal"] = hit["normal"]
		best["mi"] = mi
		best["metal"] = e.metal
		best["block"] = e.glass


## Where exactly the segment meets the mesh: {"t", "pos", "normal"}, or {}.
func _precise(e: Entry, from: Vector3, to: Vector3) -> Dictionary:
	var xf := e.mi.global_transform
	var inv := xf.affine_inverse()
	var a := inv * from
	var b := inv * to
	var ab := b - a
	if ab.length_squared() < 1e-10:
		return {}
	var local := e.mi.get_aabb()
	var at: Variant = null
	var n := Vector3.ZERO
	var faces: PackedVector3Array = PackedVector3Array() if e.box else _faces_of(e.mi.mesh)
	if e.box or faces.size() > MANY_FACES * 3:
		at = local.intersects_segment(a, b)
		if at == null:
			return {}
		var rel: Vector3 = ((at as Vector3) - local.get_center()) / (local.size * 0.5).max(Vector3(1e-4, 1e-4, 1e-4))
		var axis := rel.abs().max_axis_index()
		n[axis] = signf(rel[axis])
	else:
		var best_t := INF
		for i in range(0, faces.size(), 3):
			var p: Variant = Geometry3D.segment_intersects_triangle(a, b, faces[i], faces[i + 1], faces[i + 2])
			if p == null:
				continue
			var along := ((p as Vector3) - a).dot(ab) / ab.length_squared()
			if along < best_t:
				best_t = along
				at = p
				n = (faces[i + 1] - faces[i]).cross(faces[i + 2] - faces[i])
		if at == null:
			return {}
		if n.dot(ab) > 0.0:
			n = -n
	var t: float = clampf(((at as Vector3) - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	var normal := (xf.basis.inverse().transposed() * n).normalized()
	return {"t": t, "pos": from.lerp(to, t), "normal": normal}


func _faces_of(mesh: Mesh) -> PackedVector3Array:
	var id := mesh.get_instance_id()
	if not _faces.has(id):
		_faces[id] = mesh.get_faces()
	return _faces[id]


## The grid squares a segment crosses on the floor plan, in order.
func _cells(from: Vector3, to: Vector3) -> Array:
	var a := Vector2(from.x, from.z) / CELL
	var b := Vector2(to.x, to.z) / CELL
	var cell := Vector2i(floori(a.x), floori(a.y))
	var last := Vector2i(floori(b.x), floori(b.y))
	var out: Array = [cell]
	var d := b - a
	var step := Vector2i(1 if d.x > 0.0 else -1, 1 if d.y > 0.0 else -1)
	var t_max := Vector2(INF, INF)
	var t_delta := Vector2(INF, INF)
	if absf(d.x) > 1e-9:
		t_delta.x = absf(1.0 / d.x)
		t_max.x = ((float(cell.x) + (1.0 if d.x > 0.0 else 0.0)) - a.x) / d.x
	if absf(d.y) > 1e-9:
		t_delta.y = absf(1.0 / d.y)
		t_max.y = ((float(cell.y) + (1.0 if d.y > 0.0 else 0.0)) - a.y) / d.y
	var guard := 0
	while cell != last and guard < 400:
		guard += 1
		if t_max.x < t_max.y:
			if t_max.x > 1.0:
				break
			cell.x += step.x
			t_max.x += t_delta.x
		else:
			if t_max.y > 1.0:
				break
			cell.y += step.y
			t_max.y += t_delta.y
		out.append(cell)
	return out


## The height of the floor (or whatever is under it) below `p`, or `fallback` if there is nothing.
func floor_at(p: Vector3, fallback := 0.0) -> float:
	var hit := trace(p + Vector3(0.0, 0.5, 0.0), p - Vector3(0.0, 3.0, 0.0))
	return (hit["pos"] as Vector3).y if hit["hit"] else fallback
