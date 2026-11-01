extends Node
## Six catalog vehicles: budgets, declared bounds, legacy wheel contract,
## shared materials, Godot winding, paint vertex shades, distinct silhouettes,
## collision-hull precision (real physics rays), fleet rotations, and legacy
## prototype invariants. No rendering needed; writes measured values to
## artifacts/alive-next/vehicle-models-measured.json (override: --report-out).

const Models := preload("res://scripts/city/city_car_models.gd")
const Catalog := preload("res://scripts/city/city_car_catalog.gd")
const FLEET_SIZE := Vector3(2.12, 2.30, 4.70) # city_vehicle.gd BODY_SIZE
const PARKING_HEIGHT := 2.05 # city_parked_cars.gd PARKING_SIZE.y
const WHEEL_NAMES := ["WheelFL", "WheelRL", "WheelFR", "WheelRR"]
const RAY_LAYER := 1 << 19
# Legacy greenhouse stations (city_car_collision.gd) for silhouette comparison:
# [length, height, base_rear, roof_rear, base_front, belt].
const LEGACY_SIGNATURES := {
	"box_sedan": [4.64, 1.48, -1.32, -0.79, 1.10, 0.88],
	"compact": [4.38, 1.39, -1.43, -0.79, 1.25, 0.80],
	"minivan": [4.58, 1.72, -2.10, -1.87, 1.82, 0.94]}
var passes := 0
var fails := 0
var report: Dictionary = {}
var output := "res://../artifacts/alive-next/vehicle-models-measured.json"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--report-out")
	if index >= 0 and index + 1 < args.size():
		output = args[index + 1]
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passes += 1
	else:
		fails += 1
	print("[city_car_catalog] %s %s" % ["PASS" if ok else "FAIL", label])

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _run() -> void:
	_check_api()
	for kind in Catalog.KINDS:
		_check_prototype(str(kind))
		_check_model(str(kind))
	_check_silhouettes()
	await _check_collision()
	_check_rotations()
	_check_legacy()
	var absolute := ProjectSettings.globalize_path(output)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"passes": passes, "fails": fails, "kinds": report}, "\t"))
		file.close()
	print("[city_car_catalog] measured -> ", absolute)
	print("[city_car_catalog] %d passed, %d failed" % [passes, fails])
	get_tree().quit(0 if fails == 0 else 1)

func _check_api() -> void:
	check(Models.KINDS == ["box_sedan", "compact", "minivan"], "legacy KINDS unchanged, so current traffic/parked/fleet picks are preserved")
	check(Models.CATALOG_KINDS == Catalog.KINDS, "model and catalog list the same six new kinds")
	check(Models.ALL_KINDS == Models.KINDS + Models.CATALOG_KINDS, "ALL_KINDS is legacy followed by catalog kinds")
	var unique: Dictionary = {}
	for kind in Models.ALL_KINDS:
		unique[kind] = true
		check(Models.has_kind(str(kind)), "has_kind: " + str(kind))
	check(unique.size() == 9 and not Models.has_kind("police"), "nine distinct civilian prototypes; patrol car stays separate")

static func _triangles(mesh: Mesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		total += mesh.surface_get_array_index_len(surface) / 3
	return total

## Godot front faces wind clockwise from outside: the right-handed cross of
## each triangle must oppose its stored (outward) normals.
static func _winding(mesh: ArrayMesh) -> Vector2i:
	var good := 0
	var total := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for i in range(0, indices.size(), 3):
			var a := vertices[indices[i]]
			var cross := (vertices[indices[i + 1]] - a).cross(vertices[indices[i + 2]] - a)
			if cross.length_squared() < 0.000000000001:
				continue
			total += 1
			var normal := normals[indices[i]] + normals[indices[i + 1]] + normals[indices[i + 2]]
			good += int(cross.dot(normal) < 0.0)
	return Vector2i(good, total)

func _check_prototype(kind: String) -> void:
	var c := Catalog.config(kind)
	var data := Models.prototype(kind)
	var dims := Catalog.dimensions(kind)
	var radius := float(c.wheel_radius)
	var tire := float(c.tire_half_width)
	check(bool(data.catalog) and data.dimensions == dims and Models.dimensions(kind) == dims, kind + " dimensions come from the catalog")
	check(is_equal_approx(Models.wheel_radius(kind), radius), kind + " wheel radius from the catalog")
	check(Models.prototype(kind).parked == data.parked and Models.prototype(kind).body == data.body, kind + " prototype meshes are cached")
	check(data.spinner == null, kind + " has no decorative spinner hubs")
	var bounds: AABB = data.parked.get_aabb()
	check(bounds.size.x <= dims.x + 0.09 and bounds.size.x <= FLEET_SIZE.x, kind + " width incl. mirrors/tyres %.3f fits the fleet envelope" % bounds.size.x)
	check(bounds.size.z <= FLEET_SIZE.z and absf(bounds.size.z - dims.z) <= 0.03, kind + " length %.3f matches declared %.2f and the fleet envelope" % [bounds.size.z, dims.z])
	check(absf(bounds.get_center().z) <= 0.02 and absf(bounds.get_center().x) <= 0.005, kind + " is centred on the vehicle origin")
	check(bounds.end.y <= dims.y + 0.003 and bounds.end.y >= dims.y - 0.02 and bounds.end.y <= PARKING_HEIGHT, kind + " height %.3f matches declared and parking clearance" % bounds.end.y)
	check(absf(bounds.position.y) < 0.005, kind + " tyres meet the ground")
	var near_triangles := int(data.triangles)
	var far_triangles := _triangles(data.far_parked)
	check(near_triangles < 3500, kind + " near mesh %d triangles < 3500" % near_triangles)
	check(far_triangles < near_triangles, kind + " far mesh reduces wheel detail (%d)" % far_triangles)
	check(int(data.surfaces) <= 6 and data.body.get_surface_count() <= 6, kind + " uses at most six shared surfaces (%d)" % int(data.surfaces))
	var shared := true
	for surface in data.body.get_surface_count():
		var material: Material = data.body.surface_get_material(surface)
		shared = shared and material != null and material == Models._material(material.resource_name.trim_prefix("city_vehicle_"))
	for surface in data.parked.get_surface_count():
		var material: Material = data.parked.surface_get_material(surface)
		shared = shared and material != null and material == Models._material(material.resource_name.trim_prefix("city_vehicle_"))
	check(shared, kind + " every surface uses the shared city_vehicle_* materials (no per-car textures)")
	check(data.body.surface_get_material(0).resource_name == "city_vehicle_paint", kind + " paint is surface 0 for traffic paint overrides")
	# Paint must be the full rendered shell with per-vertex shade multipliers.
	var arrays: Array = data.body.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var raw_colors = arrays[Mesh.ARRAY_COLOR]
	var shades: Dictionary = {}
	if raw_colors is PackedColorArray:
		var colors: PackedColorArray = raw_colors
		for color in colors:
			shades[snappedf(color.r, 0.01)] = true
	check(raw_colors is PackedColorArray and shades.has(1.0) and shades.size() >= 3, kind + " paint carries vertex shades %s" % str(shades.keys()))
	var roof := -INF
	for vertex_index in indices:
		roof = maxf(roof, vertices[vertex_index].y)
	var top := 0.0
	for index in c.greenhouse.size():
		top = maxf(top, float(Catalog.greenhouse_station(kind, index).top))
	check(indices.size() / 3 >= 250 and roof >= top - 0.005 and roof >= dims.y - 0.02, kind + " paint draw indices retain the complete body and roof")
	for mesh_name in ["body", "wheel", "parked"]:
		var winding := _winding(data[mesh_name])
		check(winding.y > 0 and winding.x == winding.y, kind + " %s faces wind clockwise outside (%d/%d)" % [mesh_name, winding.x, winding.y])
	var wheel_bounds: AABB = data.wheel.get_aabb()
	check(absf(wheel_bounds.size.y - radius * 2.0) < 0.005 and absf(wheel_bounds.size.z - radius * 2.0) < 0.01 and absf(wheel_bounds.size.x - tire * 2.0) < 0.012,
		kind + " round tyre matches radius %.3f and width %.3f" % [radius, tire * 2.0])
	check(radius >= 0.29 and radius <= 0.37 and radius / dims.y <= 0.24, kind + " moderate, non-cartoon wheel size")
	var poses: Array = data.wheel_poses
	var expected := Catalog.wheel_poses(kind)
	var contract := poses.size() == 4
	for i in mini(4, poses.size()):
		var pose: Transform3D = poses[i]
		contract = contract and pose.is_equal_approx(expected[i]) and is_equal_approx(pose.origin.y, radius)
	if contract:
		var fl: Vector3 = poses[0].origin
		var rl: Vector3 = poses[1].origin
		var fr: Vector3 = poses[2].origin
		var rr: Vector3 = poses[3].origin
		contract = fl.x < 0 and rl.x < 0 and fr.x > 0 and rr.x > 0 and fl.z > rl.z and fr.z > rr.z
		contract = contract and is_equal_approx(fl.x, -fr.x) and is_equal_approx(fl.z, fr.z)
	check(contract, kind + " wheel poses keep the legacy [FL, RL, FR, RR] = [-X front, -X rear, +X front, +X rear] contract")
	var outer: float = absf(float(expected[0].origin.x)) + tire
	check(outer <= dims.x * 0.5 + 0.045, kind + " tyre sidewall stays inside the lower collision hull")
	var front_axle := float(c.front_axle)
	var rear_axle := float(c.rear_axle)
	check(Catalog.bottom(kind, front_axle) >= radius * 2.0 + 0.03, kind + " front arch clears the tyre")
	check(float(c.rear_skirt) > 0.0 or Catalog.bottom(kind, rear_axle) >= radius * 2.0 + 0.03, kind + " rear arch clears the tyre (or is a deliberate skirt)")
	check(front_axle + radius + 0.25 < Catalog.body_front(kind) and rear_axle - radius - 0.25 > Catalog.body_rear(kind), kind + " credible front/rear overhangs")
	if c.extras.has("bed"):
		var bed: Dictionary = c.bed
		check(float(bed["floor"]) - 0.04 >= radius * 2.0 and Catalog.upper(kind, -1.0) - float(bed["floor"]) >= 0.25,
			kind + " bed floor slab clears the rear tyres and leaves a usable bed depth")
	var wheelbase := front_axle - rear_axle
	check(wheelbase >= 2.40 and wheelbase <= 3.00, kind + " wheelbase %.2f within everyday range" % wheelbase)
	var centers: Array = []
	for pose in poses:
		var origin: Vector3 = pose.origin
		centers.append([snappedf(origin.x, 0.001), snappedf(origin.y, 0.001), snappedf(origin.z, 0.001)])
	report[kind] = {"label": data.label, "declared_dimensions": [dims.x, dims.y, dims.z],
		"mesh_aabb_position": [snappedf(bounds.position.x, 0.001), snappedf(bounds.position.y, 0.001), snappedf(bounds.position.z, 0.001)],
		"mesh_aabb_size": [snappedf(bounds.size.x, 0.001), snappedf(bounds.size.y, 0.001), snappedf(bounds.size.z, 0.001)],
		"wheel_radius": radius, "wheel_centers_FL_RL_FR_RR": centers, "triangles_near": near_triangles,
		"triangles_far": far_triangles, "surfaces": int(data.surfaces), "paint_shades": shades.keys()}

func _check_model(kind: String) -> void:
	var data := Models.prototype(kind)
	var car := Models.make(kind, 3)
	add_child(car)
	check(str(car.get_meta("vehicle_prototype")) == kind and car.get_meta("paint_color") == Models.paint_color(3).to_html(false), kind + " model metadata")
	var body := car.get_node_or_null("Body") as MeshInstance3D
	check(body != null and body.mesh == data.body, kind + " Body uses the cached shell")
	var legacy := Models.make("compact", 3)
	var legacy_body := legacy.get_node("Body") as MeshInstance3D
	var paint: Material = body.get_surface_override_material(0) if body != null else null
	check(paint != null and paint == legacy_body.get_surface_override_material(0) and (paint as StandardMaterial3D).vertex_color_use_as_albedo,
		kind + " shares the per-colour paint material with legacy cars (vertex shades on)")
	legacy.free()
	var wheels_ok := true
	var before: Array[Transform3D] = []
	for i in WHEEL_NAMES.size():
		var wheel := car.get_node_or_null(str(WHEEL_NAMES[i])) as MeshInstance3D
		var pose: Transform3D = data.wheel_poses[i]
		wheels_ok = wheels_ok and wheel != null and wheel.mesh == data.wheel and wheel.transform.is_equal_approx(pose)
		if wheel != null:
			before.append(wheel.transform)
	check(wheels_ok and car.get_child_count() == 5, kind + " has Body + WheelFL/RL/FR/RR at the prototype poses")
	var spinners := 0
	for child in car.get_children():
		spinners += int(str(child.name).begins_with("Spinner_"))
	Models.animate_spinners(car, 1.3)
	var unchanged := before.size() == 4
	for i in before.size():
		unchanged = unchanged and (car.get_node(str(WHEEL_NAMES[i])) as Node3D).transform == before[i]
	check(spinners == 0 and unchanged, kind + " has no spinner nodes; animate_spinners leaves its wheels alone")
	car.free()

## Each new silhouette must differ from every other new and legacy kind in at
## least one major proportion; palette-only variants would fail this.
func _check_silhouettes() -> void:
	var signatures: Dictionary = LEGACY_SIGNATURES.duplicate()
	for kind in Catalog.KINDS:
		var c := Catalog.config(str(kind))
		var stations: Array = c.greenhouse
		var front_base: Array = stations[stations.size() - 1]
		var rear_base: Array = stations[0]
		var rear_roof: Array = stations[1]
		signatures[kind] = [float(c.length), float(c.height), float(rear_base[0]), float(rear_roof[0]), float(front_base[0]),
			Catalog.upper(str(kind), 0.0)]
	for kind in Catalog.KINDS:
		var nearest := INF
		var nearest_kind := ""
		for other in signatures:
			if other == kind:
				continue
			var a: Array = signatures[kind]
			var b: Array = signatures[other]
			var distance := 0.0
			for i in a.size():
				distance = maxf(distance, absf(float(a[i]) - float(b[i])))
			if distance < nearest:
				nearest = distance
				nearest_kind = str(other)
		check(nearest >= 0.06, "%s silhouette differs from nearest (%s) by %.2fm" % [kind, nearest_kind, nearest])
	check(Catalog.config("pickup").extras.has("bed") and Catalog.config("cargo_van").extras.has("rear_doors") and Catalog.config("compact_suv").extras.has("spare"),
		"pickup bed, van rear doors and SUV spare are real geometry features")

func _check_collision() -> void:
	var bodies: Dictionary = {}
	var slot := 0
	for kind in Catalog.KINDS:
		var parts := Catalog.collision_parts(str(kind))
		check(parts.size() == 2 and str(parts[0].name) == "LowerBody" and str(parts[1].name) == "Cabin", str(kind) + " collision keeps the [LowerBody, Cabin] schema")
		check(Catalog.collision_parts(str(kind))[0].shape == parts[0].shape, str(kind) + " collision shapes are cached and shared")
		var hull_bounds := AABB()
		var seeded := false
		var planes_ok := true
		for part in parts:
			var shape: ConvexPolygonShape3D = part.shape
			var planes: Array = part.planes
			planes_ok = planes_ok and planes.size() >= 6 and float(part.radius) > 0.0
			for point in shape.points:
				hull_bounds = hull_bounds.expand(point) if seeded else AABB(point, Vector3.ZERO)
				seeded = true
		check(planes_ok, str(kind) + " hulls carry supporting planes for capsule sweeps and shot rays")
		var limit := FLEET_SIZE * 0.5 + Vector3(0.001, 0, 0.001)
		check(absf(hull_bounds.position.x) <= limit.x and absf(hull_bounds.end.x) <= limit.x
			and absf(hull_bounds.position.z) <= limit.z and hull_bounds.end.z <= limit.z and hull_bounds.end.y <= FLEET_SIZE.y,
			str(kind) + " collision fits the fleet road/parking envelope")
		var body := StaticBody3D.new()
		body.name = "Hull_" + str(kind)
		body.collision_layer = RAY_LAYER
		body.collision_mask = 0
		for part in parts:
			var collider := CollisionShape3D.new()
			collider.name = str(part.name)
			collider.shape = part.shape
			body.add_child(collider)
		add_child(body)
		body.global_position = Vector3(300.0 + 20.0 * slot, 0, 0)
		bodies[kind] = body
		report[kind]["collision_aabb"] = [[snappedf(hull_bounds.position.x, 0.001), snappedf(hull_bounds.position.y, 0.001), snappedf(hull_bounds.position.z, 0.001)],
			[snappedf(hull_bounds.size.x, 0.001), snappedf(hull_bounds.size.y, 0.001), snappedf(hull_bounds.size.z, 0.001)]]
		slot += 1
	await frames(3)
	for kind in Catalog.KINDS:
		var c := Catalog.config(str(kind))
		var body: StaticBody3D = bodies[kind]
		var x0 := body.global_position.x
		var top := 0.0
		var top_z := 0.0
		for index in c.greenhouse.size():
			var station := Catalog.greenhouse_station(str(kind), index)
			if float(station.top) > top:
				top = float(station.top)
				top_z = float(station.z)
		var roof := _ray(Vector3(x0, 4, top_z), Vector3(x0, -1, top_z))
		check(not roof.is_empty() and absf(float(roof.position.y) - top) < 0.03, str(kind) + " roof collider follows the visible roof")
		# Vans place their front axle beneath the sloped windshield. Sample
		# the visible hood beyond the final greenhouse station instead.
		var hood_z := maxf(float(c.front_axle),float(c.greenhouse[-1][0])+.15)
		var hood := _ray(Vector3(x0, 4, hood_z), Vector3(x0, -1, hood_z))
		check(not hood.is_empty() and absf(float(hood.position.y) - Catalog.upper(str(kind), hood_z)) < 0.03, str(kind) + " hood collider follows the visible hood (no full-height box)")
		var shoulder_y := top - 0.05
		var width := float(c.width)
		var shoulder := _ray(Vector3(x0 + width * 0.48, shoulder_y, -4), Vector3(x0 + width * 0.48, shoulder_y, 4))
		check(shoulder.is_empty(), str(kind) + " space outside the tapered cabin is clear")
		var tyre := _ray(Vector3(x0 + 3.0, float(c.wheel_radius), hood_z), Vector3(x0, float(c.wheel_radius), hood_z))
		var wheel_outer := width * 0.5 - float(c.wheel_inset) + float(c.tire_half_width)
		check(not tyre.is_empty() and absf(float(tyre.position.x) - x0 - (wheel_outer - .005)) < .002, str(kind) + " lower hull preserves5mm exposed tire-shot margin")
		if Catalog.config(str(kind)).extras.has("bed"):
			var bed := _ray(Vector3(x0, 4, -1.0), Vector3(x0, -1, -1.0))
			check(not bed.is_empty() and absf(float(bed.position.y) - Catalog.upper(str(kind), -1.0)) < 0.03, "pickup bed collides at rail height (documented simplification)")
		body.queue_free()
	await frames(1)

func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, RAY_LAYER)
	return get_viewport().find_world_3d().direct_space_state.intersect_ray(query)

func _check_rotations() -> void:
	var traffic: Array = Catalog.TRAFFIC_ROTATION
	var parked: Array = Catalog.PARKED_ROTATION
	check(traffic.size() == 13 and parked.size() == 13, "rotations are 13 slots, coprime with the six-colour palette")
	var legacy_prefix := true
	for i in 3:
		legacy_prefix = legacy_prefix and Catalog.traffic_kind(i) == str(Models.KINDS[i]) and Catalog.parked_kind(i) == str(Models.KINDS[i])
	check(legacy_prefix, "indices 0..2 keep the legacy box_sedan/compact/minivan order")
	var valid := true
	for kind in traffic + parked:
		valid = valid and Models.has_kind(str(kind))
	check(valid, "rotations only name real prototypes")
	for kind in Models.ALL_KINDS:
		check(traffic.has(kind) and parked.has(kind), "%s appears in traffic and parked rotations" % kind)
	var paints: Dictionary = {}
	for index in 78:
		var kind := Catalog.traffic_kind(index)
		if not paints.has(kind):
			paints[kind] = {}
		paints[kind][posmod(index, Models.PALETTE.size())] = true
	var varied := true
	for kind in paints:
		varied = varied and paints[kind].size() >= 6
	check(varied, "every kind receives every palette colour across 78 consecutive spawns")
	check(Catalog.rotation_kinds(parked).size() == 9, "parked batches: %d kinds -> %d near/far batches + 1 hub batch" % [Catalog.rotation_kinds(parked).size(), Catalog.rotation_kinds(parked).size() * 2])

func _check_legacy() -> void:
	for kind in Models.KINDS:
		var data := Models.prototype(str(kind))
		check(not bool(data.catalog) and int(data.triangles) < 4500 and data.reference == Models.REFERENCES[kind], str(kind) + " legacy prototype unchanged")
		var arrays: Array = data.body.surface_get_arrays(0)
		check(arrays[Mesh.ARRAY_COLOR] == null, str(kind) + " legacy paint has no colour array (renders as before with vertex colour enabled)")
	var sedan := Models.make("box_sedan", 0)
	var hubs := 0
	for child in sedan.get_children():
		hubs += int(str(child.name).begins_with("Spinner_"))
	check(hubs == 4 and Models.prototype("box_sedan").spinner != null, "legacy box sedan keeps its four decorative hubs")
	sedan.free()
	var paint := Models._paint(2) as StandardMaterial3D
	check(paint != null and paint.vertex_color_use_as_albedo and paint.albedo_color == Models.paint_color(2), "shared paint keeps the palette colour")
