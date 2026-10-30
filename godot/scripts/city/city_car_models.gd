class_name CityCarModels
extends RefCounted
## Restrained, game-scale interpretations of older everyday vehicles. Native +Z
## forward; every prototype fits the existing traffic collision envelope.
## Original geometry, no badges or copied manufacturer meshes/textures.

const KINDS := ["box_sedan", "compact", "minivan"]
const PALETTE := ["526577", "c6bdab", "516558", "834b46", "7c8992", "444a50"]
const REFERENCES := {
	"box_sedan": "https://news.chevrolet.com/content/dam/company/no_search/heritage-archive-docs/vehicle-information-kits/chevrolet/1986-Chevrolet-Caprice.pdf",
	"compact": "https://hondanews.com/en-US/honda-automobiles/photos/photo-3c9390b536ace288a48d2d004c354eeb-1996-honda-civic-lx-sedan",
	"minivan": "https://blog.stellantisnorthamerica.com/2023/08/03/history-of-the-dodge-brand/"}
static var _cache: Dictionary = {}
static var _materials: Dictionary = {}
static var _paint_materials: Dictionary = {}

static func dimensions(kind: String) -> Vector3:
	match kind:
		"compact": return Vector3(1.75, 1.39, 4.38)
		"minivan": return Vector3(1.96, 1.72, 4.58)
	return Vector3(1.96, 1.48, 4.64)

static func wheel_radius(kind: String) -> float:
	return 0.31 if kind == "compact" else 0.34

static func paint_color(index: int) -> Color:
	return Color(str(PALETTE[posmod(index, PALETTE.size())]))

static func _material(id: String) -> StandardMaterial3D:
	if _materials.has(id):
		return _materials[id]
	var material := StandardMaterial3D.new()
	material.resource_name = "city_vehicle_" + id
	material.roughness = 0.72
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var colors := {"paint": "ffffff", "trim": "24272a", "glass": "26353e", "metal": "bbc3c8",
		"tire": "202123", "headlamp": "7c888c", "tail": "752a28", "amber": "9a6d3e", "seam": "33393d"}
	material.albedo_color = Color(str(colors[id]))
	if id == "paint":
		material.vertex_color_use_as_albedo = true
		material.roughness = 0.52
		material.metallic = 0.12
	elif id == "glass":
		# Opaque subdued glass avoids sorting, interiors and bright showroom shine.
		material.roughness = 0.34
		material.metallic = 0.18
	elif id == "metal":
		# Readable satin chrome even when the neighborhood has no reflection probe.
		material.metallic = 0.25
		material.roughness = 0.32
	elif id == "headlamp":
		material.roughness = 0.42
		material.metallic = 0.10
	_materials[id] = material
	return material

static func _paint(index: int) -> Material:
	var key := posmod(index, PALETTE.size())
	if not _paint_materials.has(key):
		var material: StandardMaterial3D = _material("paint").duplicate()
		material.vertex_color_use_as_albedo = false
		material.albedo_color = paint_color(key)
		_paint_materials[key] = material
	return _paint_materials[key]

static func _surface(groups: Dictionary, id: String) -> SurfaceTool:
	if not groups.has(id):
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		builder.set_material(_material(id))
		groups[id] = builder
	return groups[id]

static func _quad(groups: Dictionary, id: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var builder := _surface(groups, id)
	var normal := (b - a).cross(c - a).normalized()
	for point in [a, b, c, a, c, d]:
		builder.set_normal(normal)
		builder.add_vertex(point)

static func _box(groups: Dictionary, id: String, size: Vector3, at: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_append_primitive(groups, id, mesh, Transform3D(basis, at))

static func _append_primitive(groups: Dictionary, id: String, mesh: Mesh, pose: Transform3D) -> void:
	# The lofts/quads are initially unindexed. append_from() on an indexed
	# primitive introduces an index buffer that omits those earlier vertices;
	# that made the compact's painted shell disappear when its bumpers joined
	# the paint surface. Expand primitives into the same unindexed stream, then
	# index the entire finished surface exactly once in _finish().
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var builder := _surface(groups, id)
	var count := indices.size() if not indices.is_empty() else vertices.size()
	for i in count:
		var index := indices[i] if not indices.is_empty() else i
		builder.set_normal((pose.basis * normals[index]).normalized())
		builder.add_vertex(pose * vertices[index])

static func _finish(groups: Dictionary, lods := true) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	# Paint occupies a stable surface slot for traffic-instance paint overrides.
	var order: Array = groups.keys()
	order.sort()
	if order.has("paint"):
		order.erase("paint")
		order.push_front("paint")
	for id in order:
		var builder: SurfaceTool = groups[id]
		builder.index()
		builder.commit(mesh)
	if not lods:
		return mesh
	var importer := ImporterMesh.new()
	for surface in mesh.get_surface_count():
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(surface), [], {}, mesh.surface_get_material(surface))
	importer.generate_lods(45.0, 0.0, [])
	return importer.get_mesh()

static func _loft(groups: Dictionary, rings: Array, id := "paint") -> void:
	for i in range(1, rings.size()):
		var previous: Array = rings[i - 1]
		var current: Array = rings[i]
		for k in previous.size():
			var next := (k + 1) % previous.size()
			_quad(groups, id, previous[k], current[k], current[next], previous[next])
	for cap in [0, rings.size() - 1]:
		var ring: Array = rings[cap]
		var center := Vector3.ZERO
		for p in ring:
			center += p
		center /= ring.size()
		for k in ring.size():
			_quad(groups, id, center, ring[k], ring[(k + 1) % ring.size()], center)

static func _body(kind: String) -> ArrayMesh:
	var size := dimensions(kind)
	var half := size.x * 0.5
	var length := size.z * 0.5
	var axle := 1.28 if kind == "compact" else 1.40
	var radius := wheel_radius(kind)
	var belt := 0.80 if kind == "compact" else (0.94 if kind == "minivan" else 0.88)
	var groups: Dictionary = {}
	var stations: Array[float] = [-length, -length + 0.14, -axle - 0.42, -axle - 0.32,
		-axle - 0.18, -axle, -axle + 0.18, -axle + 0.32, -axle + 0.42,
		0.0, axle - 0.42, axle - 0.32, axle - 0.18, axle, axle + 0.18,
		axle + 0.32, axle + 0.42, length - 0.14, length]
	if kind == "compact":
		stations.append_array([length - 0.28, length - 0.07])
	stations.sort()
	var rings: Array = []
	for z in stations:
		var end_factor := clampf((absf(z) - length + 0.28) / 0.28, 0.0, 1.0)
		var taper := end_factor * (0.055 if kind == "box_sedan" else 0.10)
		var droop := end_factor * 0.06
		if kind == "compact" and z > 0:
			taper = end_factor * end_factor * 0.16
			droop = end_factor * end_factor * 0.14
		var width := half * (1.0 - taper)
		var upper := belt - droop
		var bottom := 0.25
		for wheel_z in [-axle, axle]:
			var offset := absf(z - wheel_z)
			if offset < 0.40:
				bottom = maxf(bottom, radius + sqrt(maxf(0.0, 0.40 * 0.40 - offset * offset)))
		rings.append([Vector3(-width * 0.92, bottom, z), Vector3(-width, bottom + 0.035, z),
			Vector3(-width, upper - 0.075, z), Vector3(-width * 0.95, upper, z),
			Vector3(width * 0.95, upper, z), Vector3(width, upper - 0.075, z),
			Vector3(width, bottom + 0.035, z), Vector3(width * 0.92, bottom, z)])
	_loft(groups, rings)
	var roof_front := 0.43 if kind != "minivan" else 0.75
	var roof_rear := -0.79 if kind != "minivan" else -1.87
	var base_front := 1.10 if kind != "minivan" else 1.82
	var base_rear := -1.32 if kind != "minivan" else -2.10
	if kind == "compact":
		roof_front = 0.48
		base_front = 1.25
		base_rear = -1.43
	var roof_width := half * 0.79
	var base_width := half * 0.91
	var roof_y := size.y
	var cabin: Array = []
	# The upper body is a tapered greenhouse with a low, nearly flat roof.
	for item in [[base_rear, belt + 0.015, base_width], [roof_rear, roof_y - 0.035, roof_width],
		[roof_front, roof_y, roof_width], [base_front, belt + 0.015, base_width]]:
		var z := float(item[0])
		var top := float(item[1])
		var width := float(item[2])
		cabin.append([Vector3(-base_width, belt - 0.015, z), Vector3(-width, top - 0.035, z),
			Vector3(-width * 0.95, top, z), Vector3(width * 0.95, top, z),
			Vector3(width, top - 0.035, z), Vector3(base_width, belt - 0.015, z)])
	_loft(groups, cabin)
	# Individual dark panes leave painted pillars and thin window seals visible.
	for side in [-1.0, 1.0]:
		var sill := belt + 0.075
		var upper := roof_y - 0.09
		var side_height := roof_y - belt - 0.02
		var x_bottom: float = side * (lerpf(base_width, roof_width, (sill - belt + 0.015) / side_height) + 0.012)
		var x_top: float = side * (lerpf(base_width, roof_width, (upper - belt + 0.015) / side_height) + 0.012)
		_quad(groups, "glass", Vector3(x_bottom, sill, -0.04), Vector3(x_bottom, sill, base_front - 0.11),
			Vector3(x_top, upper, roof_front - 0.045), Vector3(x_top, upper, -0.04))
		if kind == "minivan":
			for span in [[-1.94, -1.13], [-1.05, -0.13]]:
				_quad(groups, "glass", Vector3(x_bottom, sill, float(span[0])), Vector3(x_bottom, sill, float(span[1])),
					Vector3(x_top, upper - 0.025, float(span[1])), Vector3(x_top, upper - 0.025, maxf(float(span[0]), roof_rear + 0.06)))
		else:
			_quad(groups, "glass", Vector3(x_bottom, sill, base_rear + 0.11), Vector3(x_bottom, sill, -0.13),
				Vector3(x_top, upper - 0.025, -0.13), Vector3(x_top, upper - 0.025, roof_rear + 0.06))
		_box(groups, "trim", Vector3(0.016, 0.045, 2.0), Vector3(side * (half + 0.004), 0.57, -0.02))
		for door_z in [-0.13, base_rear + 0.02, base_front - 0.03]:
			_box(groups, "seam", Vector3(0.007, 0.44, 0.009), Vector3(side * (half + 0.006), 0.61, door_z))
		for handle_z in [-0.86, 0.17]:
			_box(groups, "metal" if kind == "box_sedan" else "trim", Vector3(0.028, 0.026, 0.14), Vector3(side * (half + 0.018), belt - 0.10, handle_z))
		_box(groups, "trim", Vector3(0.10, 0.095, 0.15), Vector3(side * (half + 0.015), belt + 0.11, base_front - 0.18))
	for front in [true, false]:
		var lower_y := belt + 0.065
		var upper_y := roof_y - (0.075 if front else 0.10)
		var cap_y := roof_y if front else roof_y - 0.035
		var low_t := (lower_y - belt - 0.015) / (cap_y - belt - 0.015)
		var high_t := (upper_y - belt - 0.015) / (cap_y - belt - 0.015)
		var offset := 0.014 if front else -0.014
		var low_z := lerpf(base_front if front else base_rear, roof_front if front else roof_rear, low_t) + offset
		var high_z := lerpf(base_front if front else base_rear, roof_front if front else roof_rear, high_t) + offset
		var low_x := lerpf(base_width * 0.95, roof_width * 0.95, low_t) - 0.055
		var high_x := lerpf(base_width * 0.95, roof_width * 0.95, high_t) - 0.045
		_quad(groups, "glass", Vector3(-low_x, lower_y, low_z), Vector3(low_x, lower_y, low_z),
			Vector3(high_x, upper_y, high_z), Vector3(-high_x, upper_y, high_z))
	for end in [-1.0, 1.0]:
		var bumper_material := "metal" if kind == "box_sedan" else ("paint" if kind == "compact" else "trim")
		_box(groups, bumper_material, Vector3(size.x * (0.84 if kind == "compact" else 0.92), 0.11, 0.09), Vector3(0, 0.40, end * (length - 0.015)))
		_box(groups, "trim", Vector3(0.34, 0.15, 0.016), Vector3(0, 0.58, end * (length + 0.012)))
	if kind == "compact":
		_box(groups, "trim", Vector3(0.34, 0.055, 0.025), Vector3(0, 0.64, length + 0.013))
		_box(groups, "metal", Vector3(0.30, 0.009, 0.018), Vector3(0, 0.64, length + 0.027))
	else:
		_box(groups, "trim", Vector3(0.74 if kind == "box_sedan" else 0.62, 0.19, 0.025), Vector3(0, belt - 0.19, length + 0.013))
		if kind == "box_sedan":
			for bar in 9:
				_box(groups, "metal", Vector3(0.012, 0.15, 0.018), Vector3(-0.325 + 0.65 * float(bar) / 8.0, belt - 0.19, length + 0.03))
		else:
			_box(groups, "metal", Vector3(0.54, 0.018, 0.018), Vector3(0, belt - 0.19, length + 0.03))
			_box(groups, "metal", Vector3(0.018, 0.16, 0.018), Vector3(0, belt - 0.19, length + 0.03))
	for side in [-1.0, 1.0]:
		var lamp_y := belt - (0.20 if kind == "compact" else 0.17)
		var lamp_width := 0.36 if kind == "compact" else 0.42
		var lamp_height := 0.09 if kind == "compact" else 0.145
		_box(groups, "headlamp", Vector3(lamp_width, lamp_height, 0.025), Vector3(side * half * 0.67, lamp_y, length + 0.012))
		# Fine unlit reflector divisions, not emissive glowing blocks in daylight.
		for division in [-0.08, 0.04]:
			_box(groups, "seam", Vector3(0.008, lamp_height * 0.78, 0.008), Vector3(side * half * 0.67 + float(division), lamp_y, length + 0.029))
		_box(groups, "amber", Vector3(0.05, lamp_height * 0.85, 0.028), Vector3(side * half * (0.82 if kind == "compact" else 0.92), lamp_y, length - 0.035))
		if kind == "minivan":
			_box(groups, "tail", Vector3(0.14, 0.46, 0.045), Vector3(side * half * 0.85, 1.03, -length + 0.015))
		else:
			_box(groups, "tail", Vector3(0.40, 0.13, 0.035), Vector3(side * half * 0.68, belt - 0.19, -length - 0.01))
	return _finish(groups)

static func _wheel(kind: String, segments: int = 20) -> ArrayMesh:
	var groups: Dictionary = {}
	var radius := wheel_radius(kind)
	var profile := [Vector2(-0.105, radius * 0.70), Vector2(-0.105, radius * 0.86), Vector2(-0.075, radius),
		Vector2(0.075, radius), Vector2(0.105, radius * 0.86), Vector2(0.105, radius * 0.70)]
	for i in range(1, profile.size()):
		for j in segments:
			var a := float(j) * TAU / segments
			var b := float(j + 1) * TAU / segments
			var p: Vector2 = profile[i - 1]
			var q: Vector2 = profile[i]
			_quad(groups, "tire", Vector3(p.x, sin(a) * p.y, cos(a) * p.y), Vector3(q.x, sin(a) * q.y, cos(a) * q.y),
				Vector3(q.x, sin(b) * q.y, cos(b) * q.y), Vector3(p.x, sin(b) * p.y, cos(b) * p.y))
	var hub := CylinderMesh.new()
	hub.top_radius = radius * 0.70
	hub.bottom_radius = radius * 0.70
	hub.height = 0.22
	hub.radial_segments = segments
	_append_primitive(groups, "trim" if kind == "box_sedan" else "metal", hub, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3.ZERO))
	if kind == "box_sedan":
		for side in [-1.0, 1.0]:
			for j in segments:
				var a := float(j) * TAU / segments
				var b := float(j + 1) * TAU / segments
				_quad(groups, "metal", Vector3(side * 0.112, sin(a) * 0.205, cos(a) * 0.205), Vector3(side * 0.112, sin(a) * 0.235, cos(a) * 0.235),
					Vector3(side * 0.112, sin(b) * 0.235, cos(b) * 0.235), Vector3(side * 0.112, sin(b) * 0.205, cos(b) * 0.205))
	if kind != "box_sedan" and segments > 8:
		for side in [-1.0, 1.0]:
			for spoke in 7:
				var angle := float(spoke) * TAU / 7.0
				_box(groups, "trim", Vector3(0.006, 0.045, radius * 0.35), Vector3(side * 0.113, sin(angle) * radius * 0.40, cos(angle) * radius * 0.40), Basis(Vector3.RIGHT, -angle))
	return _finish(groups)

static func _spinner() -> ArrayMesh:
	var groups: Dictionary = {}
	for i in 5:
		var angle := float(i) * TAU / 5.0
		var rotation := Basis(Vector3.RIGHT, angle)
		_quad(groups, "metal", rotation * Vector3(0, 0.025, 0.025), rotation * Vector3(0, 0.075, 0.245),
			rotation * Vector3(0, -0.012, 0.225), rotation * Vector3(0, -0.035, 0.045))
	return _finish(groups, false)

static func prototype(kind: String) -> Dictionary:
	if not KINDS.has(kind):
		kind = "compact"
	if _cache.has(kind):
		return _cache[kind]
	var body := _body(kind)
	var wheel := _wheel(kind)
	var spinner := _spinner() if kind == "box_sedan" else null
	var width := dimensions(kind).x
	var axle := 1.28 if kind == "compact" else 1.40
	var wheel_poses: Array[Transform3D] = []
	for side in [-1.0, 1.0]:
		for z in [axle, -axle]:
			wheel_poses.append(Transform3D(Basis.IDENTITY, Vector3(side * (width * 0.5 - 0.065), wheel_radius(kind), z)))
	var combined: Dictionary = {}
	var far_combined: Dictionary = {}
	var far_wheel := _wheel(kind, 8)
	for surface in body.get_surface_count():
		var material := body.surface_get_material(surface)
		var id := material.resource_name.trim_prefix("city_vehicle_")
		_surface(combined, id).append_from(body, surface, Transform3D.IDENTITY)
		_surface(far_combined, id).append_from(body, surface, Transform3D.IDENTITY)
	for pose in wheel_poses:
		for surface in wheel.get_surface_count():
			var id := wheel.surface_get_material(surface).resource_name.trim_prefix("city_vehicle_")
			_surface(combined, id).append_from(wheel, surface, pose)
		for surface in far_wheel.get_surface_count():
			var id := far_wheel.surface_get_material(surface).resource_name.trim_prefix("city_vehicle_")
			_surface(far_combined, id).append_from(far_wheel, surface, pose)
	var parked := _finish(combined)
	var far_parked := _finish(far_combined)
	var triangles := 0
	for surface in parked.get_surface_count():
		triangles += parked.surface_get_array_index_len(surface) / 3
	var data := {"body": body, "wheel": wheel, "spinner": spinner, "wheel_poses": wheel_poses,
		"parked": parked, "far_parked": far_parked, "triangles": triangles, "dimensions": dimensions(kind), "reference": REFERENCES[kind]}
	_cache[kind] = data
	return data

static func make(kind: String, paint_index: int = 0) -> Node3D:
	var data := prototype(kind)
	var root := Node3D.new()
	root.name = kind
	root.set_meta("vehicle_prototype", kind)
	root.set_meta("paint_color", paint_color(paint_index).to_html(false))
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = data.body
	body.set_surface_override_material(0, _paint(paint_index))
	root.add_child(body)
	var names := ["WheelFL", "WheelRL", "WheelFR", "WheelRR"]
	for i in data.wheel_poses.size():
		var wheel := MeshInstance3D.new()
		wheel.name = names[i]
		wheel.mesh = data.wheel
		wheel.transform = data.wheel_poses[i]
		root.add_child(wheel)
		if data.spinner:
			var spinner := MeshInstance3D.new()
			spinner.name = "Spinner_%d" % i
			spinner.mesh = data.spinner
			spinner.position = wheel.position + Vector3(signf(wheel.position.x) * 0.12, 0, 0)
			root.add_child(spinner)
	return root

static func animate_spinners(root: Node3D, phase: float) -> void:
	for child in root.get_children():
		if str(child.name).begins_with("Spinner_"):
			child.rotation.x = phase
