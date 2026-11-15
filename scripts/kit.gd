class_name Kit
extends RefCounted
## Low-poly set-building helpers. Sizes and positions are metres: x right, y up,
## z towards the camera. Every helper adds the part to `parent` and returns it.

const TEX_DIR := "res://assets/textures/"

static var _mats := {}


## Flat colour. `emit` above zero makes it glow (lamps, LEDs, screens).
static func flat(color: Color, emit := 0.0) -> StandardMaterial3D:
	var key := "c%s_%.2f" % [color.to_html(), emit]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	m.metallic_specular = 0.0
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = Color(color.r, color.g, color.b)
		m.emission_energy_multiplier = emit
	_mats[key] = m
	return m


## A 256 px tiling texture, repeated every `tile_m` metres with chunky texels.
## `world` lines the pattern up across separate boxes (walls, floors); leave it
## off for props so the pattern turns with the prop. Falls back to a flat colour
## when the image is missing. `cutout` keeps the image's see-through holes (a
## chain-link fence, kit_chainlink): anything under half alpha is not drawn, and
## both sides show.
static func tex(name: String, tile_m: float, fallback: Color, world := true, tint := Color.WHITE, cutout := false) -> StandardMaterial3D:
	var key := "t%s_%.2f_%s_%s%s" % [name, tile_m, world, tint.to_html(), "_cut" if cutout else ""]
	if _mats.has(key):
		return _mats[key]
	var path := TEX_DIR + name + ".png"
	if not ResourceLoader.exists(path):
		_mats[key] = flat(fallback * tint)
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path)
	m.albedo_color = tint
	m.roughness = 1.0
	m.metallic_specular = 0.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_triplanar = true
	m.uv1_world_triplanar = world
	m.uv1_triplanar_sharpness = 8.0
	m.uv1_scale = Vector3.ONE / tile_m
	if cutout:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


static func _mat(v: Variant) -> Material:
	return v if v is Material else flat(v)


static func group(parent: Node3D, pos := Vector3.ZERO, rot_deg := Vector3.ZERO, node_name := "") -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation_degrees = rot_deg
	if node_name != "":
		n.name = node_name
	parent.add_child(n)
	return n


static func _add(parent: Node3D, mesh: Mesh, pos: Vector3, look: Variant, rot_deg: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(look)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


## Box centred on `pos`.
static func box(parent: Node3D, size: Vector3, pos: Vector3, look: Variant, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add(parent, mesh, pos, look, rot_deg)


## Box standing on `base` (the centre of its underside).
static func block(parent: Node3D, size: Vector3, base: Vector3, look: Variant, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	return box(parent, size, base + Vector3(0, size.y * 0.5, 0), look, rot_deg)


## Upright cylinder or cone centred on `pos`. Give `top_r` for a taper.
static func cyl(parent: Node3D, radius: float, height: float, pos: Vector3, look: Variant, rot_deg := Vector3.ZERO, sides := 10, top_r := -1.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_r < 0.0 else top_r
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 0
	return _add(parent, mesh, pos, look, rot_deg)


## Flat disc facing +z (speaker cones, clock faces, reels).
static func disc(parent: Node3D, radius: float, pos: Vector3, look: Variant, thick := 0.012, sides := 12) -> MeshInstance3D:
	return cyl(parent, radius, thick, pos, look, Vector3(90, 0, 0), sides)


static func ball(parent: Node3D, radius: float, pos: Vector3, look: Variant, sides := 8) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = sides
	mesh.rings = maxi(3, sides / 2)
	return _add(parent, mesh, pos, look, Vector3.ZERO)


## Ring facing +z (pop filter, headphone band).
static func ring(parent: Node3D, radius: float, thick: float, pos: Vector3, look: Variant, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - thick
	mesh.outer_radius = radius
	mesh.rings = 12
	mesh.ring_segments = 6
	return _add(parent, mesh, pos, look, rot_deg + Vector3(90, 0, 0))


# ------------------------------------------------- chunkier shapes (kit pass)

static var _meshes := {}


## A box with every edge bevelled off by `edge` metres, centred on `pos`. It
## reads as a soft, toy-like block (cushions, cabinets, car bodies, counter
## tops) and its bevels catch the light, so its outline shows even against a
## wall of the same colour. A plain box when `edge` is next to nothing.
static func bevel(parent: Node3D, size: Vector3, pos: Vector3, look: Variant, edge := 0.03, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	return _add(parent, _bevel_mesh(size, edge), pos, look, rot_deg)


## A bevelled box standing on `base` (the centre of its underside).
static func bevel_block(parent: Node3D, size: Vector3, base: Vector3, look: Variant, edge := 0.03, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	return bevel(parent, size, base + Vector3(0, size.y * 0.5, 0), look, edge, rot_deg)


## A rod from `a` to `b`: chair legs, rails, lamp arms, braces.
static func tube(parent: Node3D, a: Vector3, b: Vector3, radius: float, look: Variant, sides := 6) -> MeshInstance3D:
	var d := b - a
	var mi := cyl(parent, radius, maxf(d.length(), 0.001), (a + b) * 0.5, look, Vector3.ZERO, sides)
	if d.length() > 0.0001:
		var dir := d.normalized()
		if dir.dot(Vector3.UP) < -0.9999:
			mi.basis = Basis(Vector3.RIGHT, PI)
		else:
			mi.basis = Basis(Quaternion(Vector3.UP, dir))
	return mi


## A three-sided bar centred on `pos`: its end is a triangle `size.x` wide and
## `size.y` high, and it runs `size.z` along z. `apex` 0.5 puts the ridge in the
## middle (a gable roof), 0 over the left edge (a ramp or wedge), 1 over the right.
static func prism(parent: Node3D, size: Vector3, pos: Vector3, look: Variant, rot_deg := Vector3.ZERO, apex := 0.5) -> MeshInstance3D:
	var mesh := PrismMesh.new()
	mesh.size = size
	mesh.left_to_right = apex
	return _add(parent, mesh, pos, look, rot_deg)


## A striped shop awning on a wall that faces +z. `pos` is the middle of its top
## edge, on the wall; it reaches `out` from the wall and falls `drop` on the way,
## in stripes about `stripe` wide of colours a and b, with a valance hanging off
## the front that ends in a row of scallops. Returns its group.
static func awning(parent: Node3D, w: float, out: float, drop: float, pos: Vector3, a: Color, b: Color, stripe := 0.3, rot_deg := Vector3.ZERO) -> Node3D:
	var g := group(parent, pos, rot_deg)
	var n := maxi(int(round(w / stripe)), 2)
	var sw := w / n
	var slope := Vector2(out, drop).length()
	var canvas := group(g, Vector3(0, -drop * 0.5, out * 0.5), Vector3(rad_to_deg(atan2(drop, out)), 0, 0))
	box(canvas, Vector3(w, 0.03, slope), Vector3.ZERO, a)
	for i in range(1, n, 2):
		box(canvas, Vector3(sw, 0.01, slope - 0.01), Vector3(-w * 0.5 + (i + 0.5) * sw, 0.019, 0), b)
	var front := group(g, Vector3(0, -drop, out))
	box(front, Vector3(w, 0.24, 0.03), Vector3(0, -0.1, 0), a)
	for i in n:
		var x := -w * 0.5 + (i + 0.5) * sw
		if i % 2 == 1:
			box(front, Vector3(sw, 0.24, 0.01), Vector3(x, -0.1, 0.019), b)
		disc(front, sw * 0.5, Vector3(x, -0.22, 0.011 if i % 2 == 0 else 0.021), a if i % 2 == 0 else b, 0.012, 10)
	return g


## A framed window on a wall that faces +z, `pos` the middle of the glass on the
## wall's face: the glass, a frame standing proud of it, a cross bar (`bars` 1)
## or a single upright (`bars` 2: a sash window's meeting rail is used instead),
## a stone sill under it and a lintel over it. `glass` is the pane's look (a lit
## window is a glowing Kit.flat). Returns its group.
static func window(parent: Node3D, w: float, h: float, pos: Vector3, frame: Color, glass: Variant, bars := 1, stone: Variant = null, rot_deg := Vector3.ZERO) -> Node3D:
	var g := group(parent, pos, rot_deg)
	var trim: Color = stone if stone is Color else frame.lightened(0.1)
	pane(box(g, Vector3(w, h, 0.02), Vector3(0, 0, 0.01), glass))
	for x: float in [-w * 0.5 - 0.035, w * 0.5 + 0.035]:
		box(g, Vector3(0.07, h + 0.14, 0.05), Vector3(x, 0, 0.025), frame)
	for y: float in [-h * 0.5 - 0.035, h * 0.5 + 0.035]:
		box(g, Vector3(w, 0.07, 0.05), Vector3(0, y, 0.025), frame)
	if bars == 1:
		box(g, Vector3(0.045, h, 0.03), Vector3(0, 0, 0.035), frame)
		box(g, Vector3(w, 0.045, 0.034), Vector3(0, h * 0.08, 0.037), frame)
	elif bars == 2:
		box(g, Vector3(w, 0.06, 0.034), Vector3(0, 0, 0.037), frame)
	bevel(g, Vector3(w + 0.3, 0.09, 0.14), Vector3(0, -h * 0.5 - 0.115, 0.07), trim, 0.02)
	bevel(g, Vector3(w + 0.34, 0.16, 0.09), Vector3(0, h * 0.5 + 0.15, 0.045), trim, 0.02)
	return g


## A pane of glass that a shot can break (combat_glass.gd): marks the mesh, and anything drawn on the glass that
## goes when it does (a glare streak). Returns the mesh.
static func pane(mi: MeshInstance3D, extras: Array = []) -> MeshInstance3D:
	var paths: Array = mi.get_meta("glass", [])
	for extra: Node in extras:
		paths.append(mi.get_path_to(extra))
	mi.set_meta("glass", paths)
	return mi


static func _bevel_mesh(size: Vector3, edge: float) -> Mesh:
	var h := size * 0.5
	var c := clampf(edge, 0.0, minf(h.x, minf(h.y, h.z)) * 0.9)
	var key := "%.4f_%.4f_%.4f_%.4f" % [size.x, size.y, size.z, c]
	if _meshes.has(key):
		return _meshes[key]
	if c < 0.001:
		var plain := BoxMesh.new()
		plain.size = size
		_meshes[key] = plain
		return plain
	var polys: Array = []
	for axis in 3:          # the six faces
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for sa: float in [-1.0, 1.0]:
			var quad: Array = []
			for k: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var s := Vector3.ZERO
				s[axis] = sa
				s[u] = k.x
				s[v] = k.y
				quad.append(_bevel_point(h, c, axis, s))
			polys.append(quad)
	for axis in 3:          # the twelve bevels: each runs along this axis
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for su: float in [-1.0, 1.0]:
			for sv: float in [-1.0, 1.0]:
				var quad: Array = []
				for k: Vector2 in [Vector2(-1, u), Vector2(1, u), Vector2(1, v), Vector2(-1, v)]:
					var s := Vector3.ZERO
					s[axis] = k.x
					s[u] = su
					s[v] = sv
					quad.append(_bevel_point(h, c, int(k.y), s))
				polys.append(quad)
	for sx: float in [-1.0, 1.0]:      # the eight cut corners
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var s := Vector3(sx, sy, sz)
				polys.append([_bevel_point(h, c, 0, s), _bevel_point(h, c, 1, s), _bevel_point(h, c, 2, s)])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for poly: Array in polys:
		var mid := Vector3.ZERO
		for q: Vector3 in poly:
			mid += q
		mid /= float(poly.size())
		var p0: Vector3 = poly[0]
		var p1: Vector3 = poly[1]
		var p2: Vector3 = poly[2]
		var n := (p1 - p0).cross(p2 - p0)
		var out := n.normalized() if n.dot(mid) > 0.0 else -n.normalized()
		var pts := poly.duplicate()
		if n.dot(mid) > 0.0:        # Godot draws the side whose corners run clockwise
			pts.reverse()
		for i in range(1, pts.size() - 1):
			for q: Vector3 in [pts[0], pts[i], pts[i + 1]]:
				st.set_normal(out)
				st.add_vertex(q)
	var mesh := st.commit()
	_meshes[key] = mesh
	return mesh


## A corner of a bevelled box: the point on the face across `axis` near corner s.
static func _bevel_point(h: Vector3, c: float, axis: int, s: Vector3) -> Vector3:
	var p := Vector3(s.x * (h.x - c), s.y * (h.y - c), s.z * (h.z - c))
	p[axis] = s[axis] * h[axis]
	return p


static func omni(parent: Node3D, pos: Vector3, color: Color, energy: float, reach: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = reach
	l.omni_attenuation = 1.2
	parent.add_child(l)
	return l


static func label(parent: Node3D, text: String, pos: Vector3, height_m: float, color: Color, rot_deg := Vector3.ZERO) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 96
	l.pixel_size = height_m / 96.0
	l.modulate = color
	l.outline_size = 0
	l.shaded = false
	l.position = pos
	l.rotation_degrees = rot_deg
	parent.add_child(l)
	return l
