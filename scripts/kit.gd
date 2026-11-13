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
## when the image is missing.
static func tex(name: String, tile_m: float, fallback: Color, world := true, tint := Color.WHITE) -> StandardMaterial3D:
	var key := "t%s_%.2f_%s_%s" % [name, tile_m, world, tint.to_html()]
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
