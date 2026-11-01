extends Node
## Visual showroom for the six catalog vehicles beside the three legacy
## prototypes, rendered into a private SubViewport (never the desktop) under
## the same neutral daylight as tools/car_style_capture_driver.gd. Captures
## hero 3/4 views, an orthographic side-profile sheet, close-ups of the
## distinguishing features and the shared MultiMesh parked path (instance
## paint x vertex shades). Every shot is compared with the same camera pose
## with its subject hidden, so a missing/invisible model fails instead of
## saving a plausible-looking PNG.

const Models := preload("res://scripts/city/city_car_models.gd")
const Catalog := preload("res://scripts/city/city_car_catalog.gd")
var OUTPUT := "res://../artifacts/alive-next/vehicle-showroom"
var viewport: SubViewport
var stage: Node3D
var camera: Camera3D
var failures := 0
var captures: Array[String] = []
var coverage: Dictionary = {}

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--capture-outdir")
	if index >= 0 and index + 1 < args.size():
		OUTPUT = args[index + 1]
	_run.call_deferred()

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func check(ok: bool, label: String) -> void:
	failures += int(not ok)
	print("[car_showroom] %s %s" % ["PASS" if ok else "FAIL", label])

func capture(filename: String, save := true) -> Image:
	await frames(6)
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		check(false, filename + " has rendered pixels")
		return null
	if not save:
		return image
	var path := ProjectSettings.globalize_path(OUTPUT.path_join(filename + ".png"))
	var result := image.save_png(path)
	check(result == OK, "capture " + path)
	if result == OK:
		captures.append(path)
	return image

## Fraction of a 64x36 sample grid whose colour differs between two frames.
static func _difference(a: Image, b: Image) -> float:
	if a == null or b == null or a.get_size() != b.get_size():
		return 0.0
	var moved := 0
	for gx in 64:
		for gy in 36:
			var x := int((gx + 0.5) * a.get_width() / 64.0)
			var y := int((gy + 0.5) * a.get_height() / 36.0)
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			moved += int(absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) > 0.06)
	return float(moved) / (64.0 * 36.0)

func look(from: Vector3, at: Vector3, fov := 39.0) -> void:
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = fov
	camera.position = from
	camera.look_at(at)

func shot(filename: String, subject: Node3D, minimum: float) -> void:
	subject.visible = false
	var empty := await capture(filename + "-empty", false)
	subject.visible = true
	var image := await capture(filename)
	var fraction := _difference(image, empty)
	coverage[filename] = snappedf(fraction, 0.001)
	check(fraction >= minimum, "%s shows its subject (%.1f%% of samples differ from the same view without it; need %.1f%%)" % [filename, fraction * 100.0, minimum * 100.0])

func _run() -> void:
	if not ("--offscreen-validation" in OS.get_cmdline_user_args() or "--offscreen-validation" in OS.get_cmdline_args()):
		check(false, "requires --offscreen-validation; refusing visible capture")
		get_tree().quit(1)
		return
	if DisplayServer.get_name() == "headless":
		check(false, "requires a real offscreen renderer, not headless dummy rendering")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	viewport = SubViewport.new()
	viewport.name = "PrivateCarShowroom"
	viewport.size = Vector2i(1600, 900)
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	_build_stage()
	var stats: Dictionary = {}
	for i in Catalog.KINDS.size():
		var kind := str(Catalog.KINDS[i])
		var data := Models.prototype(kind)
		stats[kind] = {"label": data.label, "triangles": data.triangles, "surfaces": data.surfaces, "dimensions": str(data.dimensions)}
		var car := Models.make(kind, i)
		stage.add_child(car)
		look(Vector3(5.0, 2.7, 6.0), Vector3(0, 0.75, 0))
		await shot("%02d-%s-front-three-quarter" % [i + 1, kind], car, 0.08)
		look(Vector3(-5.2, 2.5, -6.0), Vector3(0, 0.8, 0))
		await shot("%02d-%s-rear-three-quarter" % [i + 1, kind], car, 0.08)
		car.queue_free()
		await frames(2)
	await _features()
	await _profiles()
	await _lineup()
	await _parked_batches()
	var report := {"captures": captures, "failures": failures, "viewport": [1600, 900], "prototypes": stats, "coverage": coverage,
		"note": "Rendered into a private SubViewport; review PNGs before claiming visual acceptance."}
	var file := FileAccess.open(OUTPUT.path_join("showroom-report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	print("[car_showroom] captures=%d failures=%d" % [captures.size(), failures])
	get_tree().quit(0 if failures == 0 else 1)

func _build_stage() -> void:
	stage = Node3D.new()
	stage.name = "Showroom"
	viewport.add_child(stage)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("b6c0c2")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c5d0d3")
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.ssao_enabled = true
	environment.ssao_radius = 0.8
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, -35, 0)
	key.light_color = Color("fff0d6")
	key.light_energy = 1.3
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 60
	viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 150, 0)
	fill.light_color = Color("d0ddeb")
	fill.light_energy = 0.40
	viewport.add_child(fill)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(240, 240)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("888b85")
	ground_material.roughness = 0.95
	ground.material_override = ground_material
	viewport.add_child(ground)
	camera = Camera3D.new()
	camera.near = 0.05
	camera.far = 400.0
	viewport.add_child(camera)
	camera.make_current()

## Close-ups of what makes each new silhouette distinct.
func _features() -> void:
	var views := [
		["pickup", 3, Vector3(2.6, 3.3, -5.8), Vector3(0, 0.85, -1.3), "20-pickup-bed-tailgate-two-tone"],
		["compact_suv", 4, Vector3(-2.4, 1.5, -5.8), Vector3(0, 0.9, -2.0), "21-suv-tailgate-spare-cladding"],
		["long_sedan", 1, Vector3(3.4, 0.95, -2.3), Vector3(0.95, 0.5, -1.4), "22-long-sedan-rear-skirt-chrome"],
		["cargo_van", 5, Vector3(-6.4, 1.7, 1.8), Vector3(0, 1.0, -0.2), "23-van-kerbside-sliding-door"],
		["midsize_sedan", 0, Vector3(2.1, 0.62, 2.5), Vector3(0.82, 0.33, 1.36), "24-midsize-wheel-round-tyre"],
		["hatchback", 2, Vector3(-4.2, 2.2, -4.8), Vector3(0, 1.0, -1.4), "25-hatchback-hatch-and-spoiler"]]
	for view in views:
		var car := Models.make(str(view[0]), int(view[1]))
		stage.add_child(car)
		look(view[2], view[3], 34.0)
		await shot(str(view[4]), car, 0.20)
		car.queue_free()
		await frames(2)

## Orthographic elevation sheet: rows of three facing +X, legacy cars in the
## middle column for scale. Grey slabs give every row a ground line.
func _profiles() -> void:
	var rows := [["hatchback", "compact", "midsize_sedan"], ["long_sedan", "box_sedan", "pickup"], ["cargo_van", "minivan", "compact_suv"]]
	var holder := Node3D.new()
	stage.add_child(holder)
	var slab_material := StandardMaterial3D.new()
	slab_material.albedo_color = Color("6f726d")
	for r in rows.size():
		var y := 6.0 - float(r) * 3.0
		var slab := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(16.0, 0.06, 3.0)
		slab.mesh = box
		slab.material_override = slab_material
		slab.position = Vector3(0, y - 0.03, 0)
		holder.add_child(slab)
		for col in 3:
			var car := Models.make(str(rows[r][col]), r * 3 + col)
			car.rotation.y = PI * 0.5
			car.position = Vector3((float(col) - 1.0) * 5.2, y, 0)
			holder.add_child(car)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 9.6
	camera.position = Vector3(0, 4.05, 40.0)
	camera.look_at(Vector3(0, 4.05, 0))
	await shot("30-side-profile-sheet", holder, 0.15)
	holder.queue_free()
	await frames(2)

func _lineup() -> void:
	var holder := Node3D.new()
	stage.add_child(holder)
	for i in Models.ALL_KINDS.size():
		var car := Models.make(str(Models.ALL_KINDS[i]), i)
		car.position = Vector3((float(i) - 4.0) * 2.6, 0, 0)
		holder.add_child(car)
	# A single wide row needs elevation to show body length rather than
	# shrinking nine mostly frontal silhouettes into a thin horizontal strip.
	# Orthographic width is24.9m at16:9, giving the22.8m row a safe margin.
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 14.0
	camera.position = Vector3(0,16.0,18.0)
	camera.look_at(Vector3(0,.65,0))
	await shot("31-all-nine-lineup", holder, 0.15)
	holder.queue_free()
	await frames(2)

## The real parked path: one MultiMesh per kind and detail level, white paint
## material with per-instance palette colour multiplying the vertex shades.
func _parked_batches() -> void:
	var holder := Node3D.new()
	stage.add_child(holder)
	for i in Models.ALL_KINDS.size():
		var kind := str(Models.ALL_KINDS[i])
		var data := Models.prototype(kind)
		for detail in ["parked", "far_parked"]:
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.use_colors = true
			multi.mesh = data[detail]
			multi.instance_count = Models.PALETTE.size()
			for slot in Models.PALETTE.size():
				# Rows of one kind (facing +Z), six palette colours across; the far
				# LOD batch sits to the right of the near batch.
				var z := (float(i) - 4.0) * 5.4
				var x := float(slot) * 2.4 + (0.0 if detail == "parked" else 16.0) - 14.0
				multi.set_instance_transform(slot, Transform3D(Basis.IDENTITY, Vector3(x, 0, z)))
				multi.set_instance_color(slot, Models.paint_color(slot))
			var node := MultiMeshInstance3D.new()
			node.name = kind + "_" + detail
			node.multimesh = multi
			holder.add_child(node)
	look(Vector3(0, 40.0, 42.0), Vector3(0, 0, -2.0), 55.0)
	await shot("32-parked-multimesh-near-and-far", holder, 0.15)
	holder.queue_free()
	await frames(2)
