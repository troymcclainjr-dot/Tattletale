extends RefCounted
## Static civic architecture: one surface per finish, one static collision body.
var root := Node3D.new()
var body := StaticBody3D.new()
var surfaces: Dictionary = {}
var materials: Dictionary = {}
var _used: Dictionary = {}

func _init(title: String = "CivicBuilding") -> void:
	root.name = title
	body.name = "SolidArchitecture"
	body.collision_layer = 2
	body.collision_mask = 0
	root.add_child(body)

func material(id: String, color: Color, kind: int = 0, roughness: float = 0.92) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://assets/materials/city_surface.gdshader")
	mat.set_shader_parameter("albedo", color)
	mat.set_shader_parameter("surface_kind", kind)
	mat.set_shader_parameter("roughness", roughness)
	materials[id] = mat
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(mat)
	surfaces[id] = surface

func primitive(mesh: PrimitiveMesh, at: Vector3, finish: String, rotation: Vector3 = Vector3.ZERO) -> void:
	_used[finish] = true
	var arrays := mesh.get_mesh_arrays()
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var basis := Basis.from_euler(rotation)
	var surface: SurfaceTool = surfaces[finish]
	for index in indices:
		surface.set_normal(basis * normals[index])
		surface.add_vertex(at + basis * points[index])

func box(at: Vector3, size: Vector3, finish: String, yaw: float = 0.0) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	primitive(mesh, at, finish, Vector3(0, yaw, 0))

func cylinder(at: Vector3, radius: float, height: float, finish: String, sides: int = 10, top_radius: float = -1.0, rotation: Vector3 = Vector3.ZERO) -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	primitive(mesh, at, finish, rotation)

func triangle(a: Vector3, b: Vector3, c: Vector3, finish: String) -> void:
	_used[finish] = true
	var normal := (c - a).cross(b - a).normalized()
	var surface: SurfaceTool = surfaces[finish]
	for vertex in [a, b, c]:
		surface.set_normal(normal)
		surface.add_vertex(vertex)

func solid_box(at: Vector3, size: Vector3, yaw: float = 0.0) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = at
	collision.rotation.y = yaw
	body.add_child(collision)

func solid_convex(points: PackedVector3Array) -> void:
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)

func label(text: String, at: Vector3, size: int = 46, pixel_size: float = 0.012, color: Color = Color("ece5cd"), yaw: float = 0.0) -> Label3D:
	var node := Label3D.new()
	node.text = text
	node.position = at
	node.rotation.y = yaw
	node.font = preload("res://scripts/city/city_theme.gd").T.body(700)
	node.font_size = size
	node.pixel_size = pixel_size
	node.modulate = color
	node.outline_size = 0
	node.double_sided = false
	node.no_depth_test = false
	node.visibility_range_end = 110.0
	root.add_child(node)
	return node

func finish(enable_palette := true) -> Node3D:
	var mesh := ArrayMesh.new()
	for id in surfaces:
		if not _used.has(id):
			continue
		var surface: SurfaceTool = surfaces[id]
		surface.index()
		surface.commit(mesh)
	var before := mesh.get_surface_count()
	if enable_palette and not OS.get_cmdline_user_args().has("--no-civic-palette"):
		var compiler := preload("res://scripts/city/city_render_optimizer.gd").new()
		mesh = compiler.consolidate_authored_mesh(mesh)
		compiler.free()
	root.set_meta("civic_surfaces_before", before)
	root.set_meta("civic_surfaces_after", mesh.get_surface_count())
	var visual := MeshInstance3D.new()
	visual.name = "BatchedArchitecture"
	visual.mesh = mesh
	root.add_child(visual)
	return root
