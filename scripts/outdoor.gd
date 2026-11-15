extends RefCounted
## Things that grow, for the places out of doors, and the out-of-doors pass's
## own tiling textures. The trees and shrubs are the old Pen Lucy game's own
## models (assets/models/tree_a .. tree_d, shrub_a .. shrub_d: see the README),
## repainted when they are loaded in bold flat cartoon greens, bark browns and
## azalea pinks (their own colours are a muted olive that goes drab beside the
## paper characters); where a model is missing a plain stand-in of cylinders and
## balls is built instead, so a place still loads.
##
##   const Outdoor := preload("res://scripts/outdoor.gd")
##   Outdoor.tree(p, band, u, v, "a")            # a tree; its trunk is walked round
##   Outdoor.shrub(p, band, u, v, "b", 1.2)      # a shrub, 1.2 times its size
##   Outdoor.tex("out_grass", 3.0, Color(0.4, 0.68, 0.28))   # a lawn (tools/tex_out.py)
##   Outdoor.chain_link()                        # see-through chain link

const MODELS := "res://assets/models/"
const LEAF := Color(0.3, 0.64, 0.24)
const BARK := Color(0.5, 0.32, 0.19)

## The cartoon paint for each model, a colour per surface in the model's own
## order (light and dark foliage, bark, branches, blossom). Each tree also gets
## a shade of its own (`_shade`), so a row of one kind is not one colour.
const PAINT := {
	"tree_a": [Color(0.16, 0.47, 0.21), Color(0.38, 0.7, 0.25), Color(0.47, 0.3, 0.17), Color(0.4, 0.25, 0.14), Color(0.43, 0.27, 0.15)],
	"tree_b": [Color(0.13, 0.43, 0.26), Color(0.31, 0.64, 0.29), Color(0.42, 0.26, 0.15), Color(0.47, 0.3, 0.17)],
	"tree_c": [Color(0.1, 0.42, 0.32), Color(0.42, 0.26, 0.15)],
	"tree_d": [Color(0.3, 0.6, 0.2), Color(0.5, 0.76, 0.25), Color(0.18, 0.44, 0.18), Color(0.45, 0.29, 0.17)],
	"shrub_a": [Color(0.17, 0.48, 0.22), Color(0.36, 0.68, 0.27)],
	"shrub_b": [Color(0.12, 0.42, 0.27), Color(0.28, 0.6, 0.3)],
	"shrub_c": [Color(0.17, 0.47, 0.22), Color(0.33, 0.64, 0.27)],
	"shrub_d": [Color(0.18, 0.48, 0.22), Color(0.34, 0.66, 0.26), Color(0.96, 0.42, 0.66), Color(1.0, 0.76, 0.86)],
}
## Surfaces that lie flat on the model's other faces (the hedge's flecks): they
## are pushed out along their normals a little, or the two flicker.
const LIFT := {"shrub_c": [1]}

static var _mats := {}


## A tree standing at (u, v). kind: "a" to "d". `size` scales it; `turn` (degrees)
## turns it so that two of a kind do not look the same. The trunk takes up floor.
static func tree(p: Node3D, b: int, u: float, v: float, kind := "a", size := 1.0, turn := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.5, 0.5)
	var model := _model("tree_" + kind, u * 1.7 + v * 3.1)
	if model:
		model.scale = Vector3.ONE * size
		model.rotation_degrees.y = turn
		g.add_child(model)
		return g
	var h := 4.6 * size
	Kit.cyl(g, 0.16 * size, h * 0.5, Vector3(0, h * 0.25, 0), BARK, Vector3.ZERO, 7, 0.11 * size)
	Kit.ball(g, 1.5 * size, Vector3(0, h * 0.68, 0), LEAF, 8)
	Kit.ball(g, 1.05 * size, Vector3(0.75 * size, h * 0.84, 0.2 * size), LEAF.lightened(0.12), 7)
	Kit.ball(g, 0.95 * size, Vector3(-0.7 * size, h * 0.8, -0.2 * size), LEAF.darkened(0.2), 7)
	return g


## A shrub at (u, v). kind: "a" to "d". It takes up floor unless `solid` is false.
static func shrub(p: Node3D, b: int, u: float, v: float, kind := "a", size := 1.0, turn := 0.0, solid := true) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.8 * size, 0.8 * size, solid)
	var model := _model("shrub_" + kind, u * 2.3 + v * 1.3)
	if model:
		model.scale = Vector3.ONE * size
		model.rotation_degrees.y = turn
		g.add_child(model)
		return g
	Kit.ball(g, 0.5 * size, Vector3(0, 0.4 * size, 0), LEAF.darkened(0.2), 7)
	Kit.ball(g, 0.36 * size, Vector3(0.3 * size, 0.5 * size, 0.1 * size), LEAF, 6)
	return g


## A tiling texture of the out-of-doors pass (assets/textures/out_*.png, drawn by
## tools/tex_out.py in the working folder), `tile_m` metres a repeat. It keeps
## the nearest texel up close, as Kit.tex does, but has mipmaps, so far off a
## pattern melts to its average colour instead of shimmering. `world` lines the
## pattern up across separate boxes. Falls back to a flat colour.
static func tex(tex_name: String, tile_m: float, fallback: Color, tint := Color.WHITE, world := true) -> Material:
	var key := "t%s_%.2f_%s_%s" % [tex_name, tile_m, tint.to_html(), world]
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
	m.uv1_world_triplanar = world
	m.uv1_triplanar_sharpness = 8.0
	m.uv1_scale = Vector3.ONE / tile_m
	_mats[key] = m
	return m


## The stock street every place stands on (place.gd's street()), and the plans
## that run it on out of sight: concrete slabs for the pavement, slate asphalt.
static func pavement() -> Material:
	return tex("out_paving", 4.8, Color(0.7, 0.68, 0.64))


static func road() -> Material:
	return tex("out_asphalt", 6.4, Color(0.24, 0.26, 0.31))


const KERB := Color(0.84, 0.82, 0.77)
const GUTTER := Color(0.42, 0.43, 0.46)


## Galvanised chain link you can see through: the wires solid, the holes clear,
## lined up with the world so the bays of a fence meet. Without its texture, the
## old faint grey sheet.
static func chain_link(tile_m := 0.6, tint := Color.WHITE) -> Material:
	var key := "chain_%.2f_%s" % [tile_m, tint.to_html()]
	if _mats.has(key):
		return _mats[key]
	var path := Kit.TEX_DIR + "out_chain_link.png"
	if not ResourceLoader.exists(path):
		_mats[key] = Kit.flat(Color(0.72, 0.76, 0.78, 0.22))
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path)
	m.albedo_color = tint
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	m.metallic_specular = 0.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 8.0
	m.uv1_scale = Vector3.ONE / tile_m
	_mats[key] = m
	return m


## The sky at the back of an outdoor place and what stands against it far off:
## a band of glow along the horizon (the city's lights by night, the last of
## the sun at dusk), the moon, and the city on the skyline: a strip of low far
## roofs, then towers in two ranks, the far one hazier, all with lit windows,
## over dark ground that runs out under everything. None of it takes the
## place's lights (it is far beyond them). It stands in `parent` round
## `centre` (world space: on the ground behind the place) and off to -z, the
## towers from `dist` metres. glow: [the colour at the horizon, the colour
## higher up], or three for dusk: [the last of the sun at the horizon, the band
## over it, the colour higher up]. moon: where the moon hangs (world space;
## Vector3.INF for none). `key` varies the towers. `toward`: at dusk, the way
## (x, z) the sun went down; the glow is strongest that way and goes round the
## ring to the colour higher up (Vector2.ZERO: the same all the way round).
static func backdrop(parent: Node3D, centre: Vector3, glow: Array, moon := Vector3.INF, key := 1.0, dist := 900.0, toward := Vector2.ZERO) -> Node3D:
	var g := Kit.group(parent, centre, Vector3.ZERO, "Backdrop")
	g.set_meta("combat_fx", true)      # not something a shot hits or glass lands on: a 4 km plane and the sky ring swamp combat_world.gd's squares
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4000, 4000)
	ground.mesh = plane
	ground.material_override = _unshaded(Color(0.07, 0.07, 0.12))
	ground.position = Vector3(0, -0.6, 0)
	g.add_child(ground)
	# The glow: a ring of sky all the way round beyond it all (so no camera looks
	# past its end), the horizon's colour going up into the night.
	var far_z := dist * 2.0
	var c0: Color = glow[0]
	var c1: Color = glow[1]
	var rows := [[-0.05, c0], [0.0, c0], [0.14, c1], [0.34, Color(c1.r, c1.g, c1.b, 0.0)]]   # heights over the distance
	var top: Color = glow[glow.size() - 1]
	if glow.size() > 2:
		rows = [[-0.05, c0], [0.0, c0], [0.045, c1], [0.15, top], [0.36, Color(top.r, top.g, top.b, 0.0)]]
	var sun := toward.normalized()
	var band := SurfaceTool.new()
	band.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 48:
		var a0 := TAU * float(i) / 48.0
		var a1 := TAU * float(i + 1) / 48.0
		for j in rows.size() - 1:
			var lo: Array = rows[j]
			var hi: Array = rows[j + 1]
			var quad := [[a0, lo], [a1, lo], [a1, hi], [a0, lo], [a1, hi], [a0, hi]]
			for corner: Array in quad:
				var col: Color = corner[1][1]
				if sun != Vector2.ZERO:
					var f := clampf(Vector2(cos(corner[0]), sin(corner[0])).dot(sun), 0.0, 1.0)
					col = Color(top.r, top.g, top.b, col.a).lerp(col, 0.3 + 0.7 * f * f)
				band.set_color(col)
				band.add_vertex(Vector3(cos(corner[0]) * far_z, float(corner[1][0]) * far_z, sin(corner[0]) * far_z))
	var sheet := StandardMaterial3D.new()
	sheet.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sheet.vertex_color_use_as_albedo = true
	sheet.vertex_color_is_srgb = true
	sheet.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sheet.cull_mode = BaseMaterial3D.CULL_DISABLED
	sheet.render_priority = -100        # drawn before every other see-through thing (the moon's halo)
	var sky := MeshInstance3D.new()
	sky.mesh = band.commit()
	sky.material_override = sheet
	g.add_child(sky)
	if moon != Vector3.INF:
		# A cartoon moon: a cream disc, two faint halos behind it, its seas in front.
		var m := Kit.group(g, moon - centre)
		var r := (moon - centre).length() * 0.02
		var gap := maxf(r * 0.25, 2.0)          # far off, the depth buffer needs metres between them
		for disc: Array in [[r * 1.9, Color(1.0, 0.95, 0.8, 0.08), -gap * 2.0], [r * 1.4, Color(1.0, 0.95, 0.8, 0.14), -gap], [r, Color(1.0, 0.97, 0.84), 0.0]]:
			Kit.cyl(m, disc[0], 0.5, Vector3(0, 0, disc[2]), _unshaded(disc[1]), Vector3(90, 0, 0), 32)
		for c: Array in [[Vector2(-0.32, 0.22), 0.2], [Vector2(0.28, -0.12), 0.26], [Vector2(-0.05, -0.42), 0.14], [Vector2(0.36, 0.38), 0.1]]:
			Kit.cyl(m, r * c[1], 0.5, Vector3(r * c[0].x, r * c[0].y, gap), _unshaded(Color(0.92, 0.87, 0.7)), Vector3(90, 0, 0), 16)
	# The city: a strip of far roofs, and the towers in two ranks beyond it.
	var far := Color(0.22, 0.17, 0.32)
	var near := Color(0.12, 0.1, 0.21)
	Kit.box(g, Vector3(far_z * 3.0, 14.0, 8.0), Vector3(0, 7.0, -dist * 0.45), _skyline_look(near.lerp(far, 0.3), 0.35))
	var span := dist * 0.8
	for rank in 2:
		var z := -dist - 380.0 * float(1 - rank)
		var look := _skyline_look(far if rank == 0 else near, 0.5 if rank == 0 else 0.8)
		var x := -span
		var k := key * 7.1 + float(rank) * 31.0
		while x < span:
			var r1 := fposmod(sin(k * 12.9898) * 43758.5453, 1.0)
			var r2 := fposmod(sin(k * 78.233) * 43758.5453, 1.0)
			var r3 := fposmod(sin(k * 37.719) * 43758.5453, 1.0)
			k += 1.0
			var w := 24.0 + 30.0 * r1
			# A city has its tall part: the towers fall away from the middle.
			var mid := 1.0 - clampf(absf(x) / span, 0.0, 1.0)
			var h := (50.0 + 130.0 * r2 * r2) * (1.2 if rank == 0 else 1.0) * (0.35 + 0.65 * mid)
			if r3 < 0.25:
				x += w * 0.7
				continue
			var at := Vector3(x + w * 0.5, h * 0.5, z - 40.0 * r3)
			Kit.box(g, Vector3(w, h, 24.0), at, look)
			if r1 > 0.6:            # a crown on some
				Kit.box(g, Vector3(w * 0.6, h * 0.1, 16.0), at + Vector3(0, h * 0.55, 0), look)
			if r2 > 0.72:           # a mast and its red light on the tallest
				Kit.box(g, Vector3(1.2, h * 0.25, 1.2), at + Vector3(0, h * 0.62, 0), _unshaded(far if rank == 0 else near))
				Kit.ball(g, 2.2, at + Vector3(0, h * 0.75, 0), _unshaded(Color(1.0, 0.25, 0.2)), 6)
			x += w + 6.0 + 50.0 * r3
	return g


## The far city's look: a flat colour that takes no light, its windows (the
## out_far_windows texture, lined up with the world, `lit` how strongly they
## show) drawn over it in a second pass, so they cannot flicker on it.
static func _skyline_look(c: Color, lit: float) -> Material:
	var key := "sky_%s_%.2f" % [c.to_html(), lit]
	if _mats.has(key):
		return _mats[key]
	var m: StandardMaterial3D = (_unshaded(c) as StandardMaterial3D).duplicate()
	var path := Kit.TEX_DIR + "out_far_windows.png"
	if ResourceLoader.exists(path):
		var w := StandardMaterial3D.new()
		w.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		w.albedo_texture = load(path)
		w.albedo_color = Color(1, 1, 1, lit)
		w.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		w.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		w.uv1_triplanar = true
		w.uv1_world_triplanar = true
		w.uv1_scale = Vector3.ONE / 28.0
		m.next_pass = w
	_mats[key] = m
	return m


## A flat colour that takes no light (far things, the sky); see-through below full alpha.
static func _unshaded(c: Color) -> Material:
	var key := "u_%s" % c.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = c
		if c.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mats[key] = m
	return _mats[key]


## A cool moonlight for a place at night (main.gd's sun is warm and low: a
## place turns that off with `sun_energy` = 0 and hangs this in its band instead).
static func moonlight(parent: Node3D, energy := 0.32, colour := Color(0.62, 0.7, 1.0)) -> DirectionalLight3D:
	var l := DirectionalLight3D.new()
	l.light_color = colour
	l.light_energy = energy
	l.rotation_degrees = Vector3(-48, -32, 0)
	parent.add_child(l)
	return l


static func _model(model_name: String, key := 0.0) -> Node3D:
	var path := MODELS + model_name + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var scene: PackedScene = load(path)
	if not scene:
		return null
	var model: Node3D = scene.instantiate()
	_paint(model, model_name, _shade(key))
	return model


## A small shift of a plant's colours of its own: a little warmer and lighter,
## or cooler and deeper, so the trees in a row differ.
static func _shade(key: float) -> int:
	return int(fposmod(sin(key * 12.9898) * 43758.5453, 1.0) * 3.0) % 3     # props.gd's rnd


## Repaint every mesh in the model with the cartoon colours (`PAINT`), in shade 0..2.
static func _paint(node: Node, model_name: String, shade: int) -> void:
	if not PAINT.has(model_name):
		return
	var colours: Array = PAINT[model_name]
	var lift: Array = LIFT.get(model_name, [])
	for child in node.get_children():
		if child is MeshInstance3D and child.mesh:
			var mi: MeshInstance3D = child
			for i in mini(mi.mesh.get_surface_count(), colours.size()):
				var c: Color = colours[i]
				if c.g > c.r and c.g > c.b:          # only the greens shift
					c = [c, Color(c.r + 0.05, c.g + 0.03, c.b - 0.02), Color(c.r - 0.03, c.g - 0.04, c.b + 0.03)][shade]
				mi.set_surface_override_material(i, _lifted(c) if i in lift else Kit.flat(c))
		_paint(child, model_name, shade)


static func _lifted(c: Color) -> Material:
	var key := "lift_%s" % c.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 1.0
		m.metallic_specular = 0.0
		m.grow = true
		m.grow_amount = 0.012
		_mats[key] = m
	return _mats[key]
