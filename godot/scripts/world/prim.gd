class_name Prim
## Code-built meshes (engine.js box/sph/cyl/tor/sign/M helpers). Used for the placeholders
## that stand in for missing GLBs, and for the few things that are always code (plate, Zs).
## Sizes and rotations follow three.js, so JS lines translate 1:1:
##   M(box(w,h,d),clay(c),x,y,z,parent)  ->  Prim.M(Prim.box(w,h,d), ClayLib.clay(c), x, y, z, parent)

static var _meshes := {}
static var _fonts := {}


static func clear_cache() -> void:
	_meshes.clear()
	_fonts.clear()


static func box(w: float, h: float, d: float) -> Mesh:
	var k := "b%.4f|%.4f|%.4f" % [w, h, d]
	if not _meshes.has(k):
		var m := BoxMesh.new()
		m.size = Vector3(w, h, d)
		_meshes[k] = m
	return _meshes[k]


## SphereGeometry(r, w, h, 0, TAU, ts, tl): tl < PI makes a cap around +y (hair, hats).
static func sph(r: float, ws := 16, hs := 12, ts := 0.0, tl := PI) -> Mesh:
	var k := "s%.4f|%d|%d|%.3f|%.3f" % [r, ws, hs, ts, tl]
	if _meshes.has(k):
		return _meshes[k]
	var m: Mesh
	if ts == 0.0 and is_equal_approx(tl, PI):
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 2.0
		sm.radial_segments = ws
		sm.rings = hs
		m = sm
	else:
		m = _cap(r, ws, hs, ts, tl)
	_meshes[k] = m
	return m


static func _cap(r: float, ws: int, hs: int, ts: float, tl: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts: Array[Vector3] = []
	for iy in hs + 1:
		var th := ts + float(iy) / hs * tl
		for ix in ws + 1:
			var ph := float(ix) / ws * TAU
			verts.append(Vector3(-r * cos(ph) * sin(th), r * cos(th), r * sin(ph) * sin(th)))
	for iy in hs:
		for ix in ws:
			var a := iy * (ws + 1) + ix
			var b := a + ws + 1
			# Godot's front faces wind clockwise seen from outside
			for idx in [a, a + 1, b, b, a + 1, b + 1]:
				var v: Vector3 = verts[idx]
				st.set_normal(v.normalized())
				st.add_vertex(v)
	return st.commit()


static func cyl(rt: float, rb: float, h: float, segs := 14, open := false) -> Mesh:
	var k := "c%.4f|%.4f|%.4f|%d|%s" % [rt, rb, h, segs, open]
	if not _meshes.has(k):
		var m := CylinderMesh.new()
		m.top_radius = rt
		m.bottom_radius = rb
		m.height = h
		m.radial_segments = maxi(segs, 3)
		m.rings = 1
		m.cap_top = not open
		m.cap_bottom = not open
		_meshes[k] = m
	return _meshes[k]


static func cone(r: float, h: float, segs := 8) -> Mesh:
	return cyl(0.0, r, h, segs)


## three.js torus lies in the xy plane (axis z); Godot's lies in xz (axis y). T() wraps it so
## the returned pivot takes the JS rotation unchanged.
static func torus(r: float, t: float, rs := 8, ts := 24) -> Mesh:
	var k := "t%.4f|%.4f|%d|%d" % [r, t, rs, ts]
	if not _meshes.has(k):
		var m := TorusMesh.new()
		m.inner_radius = maxf(r - t, 0.001)
		m.outer_radius = r + t
		m.rings = ts
		m.ring_segments = rs
		_meshes[k] = m
	return _meshes[k]


## Mesh instance at (x, y, z) under parent, like the JS M().
static func M(mesh: Mesh, mat: Material, x := 0.0, y := 0.0, z := 0.0, parent: Node = null, cast := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if mat:
		mi.material_override = mat
	mi.position = Vector3(x, y, z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if parent:
		parent.add_child(mi)
	return mi


## Torus at (x, y, z): returns a pivot holding the mesh, so .rotation works like three.js.
static func T(r: float, t: float, mat: Material, x := 0.0, y := 0.0, z := 0.0, parent: Node = null, rs := 8, ts := 24, cast := true) -> Node3D:
	var pv := Node3D.new()
	pv.position = Vector3(x, y, z)
	var mi := M(torus(r, t, rs, ts), mat, 0, 0, 0, pv, cast)
	mi.rotation.x = PI / 2
	if parent:
		parent.add_child(pv)
	return pv


static func group(parent: Node, x := 0.0, y := 0.0, z := 0.0, nm := "") -> Node3D:
	var g := Node3D.new()
	if nm != "":
		g.name = nm
	g.position = Vector3(x, y, z)
	if parent:
		parent.add_child(g)
	return g


## The lumpy() wobble from engine.js, on a copy of a primitive.
static func lumpy(mesh: Mesh, amt: float) -> Mesh:
	var arr := mesh.surface_get_arrays(0)
	var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in pos.size():
		var v := pos[i]
		var k := sin(v.x * 23.1 + 1.3) * sin(v.y * 19.7 + 0.7) * sin(v.z * 21.3 + 2.1)
		pos[i] = v + v.normalized() * amt * k
	arr[Mesh.ARRAY_VERTEX] = pos
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


static func font(kind := "sign") -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var f := SystemFont.new()
	match kind:
		"mono":
			f.font_names = PackedStringArray(["Courier New", "Consolas", "Liberation Mono", "monospace"])
			f.font_weight = 700
		_:
			f.font_names = PackedStringArray(["Impact", "Arial Black", "Arial", "sans-serif"])
			f.font_weight = 900
	_fonts[kind] = f
	return f


## Text label sized like the JS canvas text (fills 78% of the height, shrinks to 92% of the width).
## Faces +z like the JS sign planes.
static func label(text: String, w: float, h: float, fg: String, kind := "sign") -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font(kind)
	l.font_size = 64
	l.outline_size = 0
	l.modulate = Color.html(fg)
	l.shaded = true
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fit(l, w, h)
	return l


static func fit(l: Label3D, w: float, h: float) -> void:
	var lines := l.text.split("\n")
	var px := (h * 0.78 / lines.size()) / l.font_size
	var widest := 0.0
	for ln in lines:
		widest = maxf(widest, l.font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size).x)
	if widest * px > w * 0.92 and widest > 0.0:
		px *= w * 0.92 / (widest * px)
	l.pixel_size = maxf(px, 0.00005)


## sign(text, w, h, o, x, y, z, parent, ry) from engine.js: optional background card + text.
static func sign(text: String, w: float, h: float, o: Dictionary, x: float, y: float, z: float, parent: Node, ry := 0.0) -> Node3D:
	var g := group(parent, x, y, z)
	g.rotation.y = ry
	if o.has("bg"):
		var q := QuadMesh.new()
		q.size = Vector2(w, h)
		M(q, ClayLib.clay(o.bg, 0.8), 0, 0, 0, g, false)
	var l := label(text, w, h, o.get("fg", "#111111"), "mono" if o.get("font", "") == "mono" else "sign")
	l.position.z = 0.004
	g.add_child(l)
	return g


## Horizontal stripes (Ricky's shirt, the ice-cream umbrella), like stripesMat().
static func stripes(a: String, b: String) -> Material:
	var k := "stripes|" + a + "|" + b
	if _meshes.has(k):
		return _meshes[k]
	var img := Image.create(2, 8, false, Image.FORMAT_RGB8)
	for yy in 8:
		var c := Color.html(a if yy % 2 else b)
		for xx in 2:
			img.set_pixel(xx, yy, c)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_scale = Vector3(1, 2, 1)
	m.roughness = 0.9
	_meshes[k] = m
	return m


## Emissive material of its own (things the game switches on and off).
static func glow_mat(hex: String, energy: float, emissive := "") -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.html(hex)
	m.roughness = 0.4
	m.emission_enabled = true
	m.emission = Color.html(emissive if emissive != "" else hex)
	m.emission_energy_multiplier = energy
	return m


static func glass_mat(hex: String, alpha: float, rough := 0.4) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(Color.html(hex), alpha)
	m.roughness = rough
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
