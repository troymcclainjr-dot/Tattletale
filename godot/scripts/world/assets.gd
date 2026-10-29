class_name Assets
## Loads the Blender GLBs, or builds a primitive placeholder (in the JS shapes and colors)
## when one is missing, so the game always runs. Node names the code drives are the same
## either way (blender/README.md), so the gameplay code never cares which one it got.

const DIR := "res://assets/models/"

static var _warned := {}
static var used_glb: Array[String] = []
static var used_placeholder: Array[String] = []


static func path_of(id: String) -> String:
	return DIR + id + ".glb"


static func has_glb(id: String) -> bool:
	return ResourceLoader.exists(path_of(id))


## A model instance: the GLB if it imports, else the placeholder. Never null.
static func model(id: String) -> Node3D:
	var n := glb(id)
	if n == null:
		n = Placeholders.build(id)
		used_placeholder.append(id)
	n.name = id.get_file()
	return n


## The GLB instance (materials swapped to clay), or null.
static func glb(id: String) -> Node3D:
	var p := path_of(id)
	if not ResourceLoader.exists(p):
		return null
	var res = load(p)
	if not (res is PackedScene):
		warn_once("load:" + id, "[assets] %s exists but did not load as a scene; using the placeholder" % p)
		return null
	var n = res.instantiate()
	if not (n is Node3D):
		if n:
			n.free()
		return null
	ClayLib.apply(n)
	used_glb.append(id)
	return n


static func warn_once(key: String, msg: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(msg)


## Find a named node anywhere under root (GLB importers may wrap nodes).
static func find(root: Node, nm: String) -> Node3D:
	if root == null:
		return null
	if root.name == nm and root is Node3D:
		return root
	var n := root.find_child(nm, true, false)
	return n as Node3D


## Find a contracted node; warn once if it's missing and hand back a hidden stand-in so
## the code that drives it keeps working.
static func need(root: Node, nm: String, ctx: String) -> Node3D:
	var n := find(root, nm)
	if n:
		return n
	warn_once(ctx + ":" + nm, "[assets] %s: missing node '%s' (blender/README.md contract)" % [ctx, nm])
	var d := Node3D.new()
	d.name = nm + "_missing"
	d.visible = false
	root.add_child(d)
	return d


## Every mesh surface at or under node gets its own copy of its material, so this instance
## can be recolored or dimmed alone. Returns the emissive copies (to drive their energy).
static func own_materials(node: Node) -> Array[StandardMaterial3D]:
	var out: Array[StandardMaterial3D] = []
	_own(node, out)
	return out


static func _own(node: Node, out: Array[StandardMaterial3D]) -> void:
	if node is MeshInstance3D and node.mesh:
		var mi: MeshInstance3D = node
		if mi.material_override:
			var m := _emissive_copy(mi.material_override)
			mi.material_override = m
			out.append(m)
		else:
			for i in mi.mesh.get_surface_count():
				var cur := mi.get_active_material(i)
				var m := _emissive_copy(cur)
				mi.set_surface_override_material(i, m)
				out.append(m)
	for c in node.get_children():
		_own(c, out)


static func _emissive_copy(cur: Material) -> StandardMaterial3D:
	if cur is StandardMaterial3D:
		var d: StandardMaterial3D = cur.duplicate()
		if not d.emission_enabled:
			d.emission_enabled = true
			d.emission = d.albedo_color
			d.emission_energy_multiplier = 0.0
		return d
	var col := Color(0.8, 0.8, 0.8)
	if cur is ShaderMaterial:
		var a = cur.get_shader_parameter("albedo")
		if a is Color:
			col = a
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.4
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.0
	return m


static func set_energy(mats: Array, e: float) -> void:
	for m in mats:
		m.emission_energy_multiplier = e
