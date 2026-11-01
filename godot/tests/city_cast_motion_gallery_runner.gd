extends "res://tests/city_model_quality_gallery_runner.gd"
## Shared-metre lineup and real runtime pose-builder snapshots. Uses the private
## SubViewport/focus guards of the per-model gallery; no gameplay/input ticking.
const PEOPLE := preload("res://scripts/city/city_modular_people.gd")
const BICYCLE := preload("res://scripts/city/city_bicycle.gd")
const PHONE := preload("res://scripts/city/city_player_phone.gd")
const PLAYER := preload("res://scripts/city/city_player.gd")
const LINEUP_OUT := "res://../.work/model-quality-20261101/lineup"
const PICKS := [0, 7, 18, 20, 27, 39]
var actors: Array[Puppet] = []
var evidence: Array[Dictionary] = []
var identities: Array[Dictionary] = []

func _run() -> void:
	assert(OS.get_cmdline_user_args().has("--offscreen-validation"))
	assert(DisplayServer.get_name() != "headless", "Real offscreen rendering is required")
	_setup()
	viewport.size = Vector2i(1920, 820)
	camera.size = 3.7
	camera.position = Vector3(0, 1.04, 8)
	camera.look_at(Vector3(0, 1.04, 0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LINEUP_OUT))
	_lineup()
	await _save("01_same_scale_front", {"purpose": "Seven grounded adults, common camera and metres; gold rail at 1.80m"})
	for phase in 4:
		for index in actors.size():
			var actor := actors[index]
			actor.phase = float(phase) * PI / 2.0
			actor.pose({"walk": .42, "bob": absf(sin(actor.phase * 2.0)) * .018})
		await _save("02_walk_phase_%d" % phase, {"pose": "actual Puppet.pose walk", "phase_radians": float(phase)*PI/2.0})
	camera.position = Vector3(1.8, 1.35, -8)
	camera.look_at(Vector3(0, 1.02, 0))
	await _save("03_walk_rear", {"pose": "same final walking phase, rear view"})
	_clear_stage()
	await _accessories()
	await _bike()
	await _phone()
	var file := FileAccess.open(LINEUP_OUT.path_join("motion-evidence.json"), FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"identities": identities, "captures": evidence,
		"limits": ["Discrete deterministic pose samples, not continuous gameplay movement or collision verification.",
		"Phone uses the actual camera-mounted first-person handset/hand. No third-person phone posture exists to validate.",
		"Bicycle uses its production replacement pedal legs/shoes; original character LegR/LegL meshes remain hidden while riding.",
		"Modular character shader morphology is rendered; CPU AABBs alone do not describe those face/hair morphs."]}, "\t"))
	file.close()
	print("[cast_motion] COMPLETE ", evidence.size(), " snapshots; no pointer/focus takeover")
	get_tree().quit(0)

func _lineup(record_identities := true) -> void:
	var roster := PEOPLE.roster()
	assert(roster.size() >= 40)
	var pick := 0
	for column in 7:
		var actor: Puppet
		var label: String
		var cohort: String
		if column == 3:
			actor = Cast.person("two_pack", stage)
			label = "2-PACK  1.80m"
			cohort = "player"
		else:
			var index: int = PICKS[pick]
			pick += 1
			var look: Dictionary = roster[index]
			actor = Puppet.new()
			actor.id = str(look.id)
			actor.H = float(look.height)
			actor.g = PEOPLE.rig(actor.id, index, actor.H)
			stage.add_child(actor.g)
			actor.bind()
			cohort = "original" if index < 20 else "new"
			label = "%s %s  %.2fm" % [actor.id, cohort, actor.H]
		actor.g.position.x = float(column - 3) * 1.15
		actor.pose({})
		actors.append(actor)
		if record_identities:
			identities.append({"id": actor.id, "cohort": cohort, "nominal_height": actor.H})
		var nameplate := Label3D.new()
		nameplate.text = label
		nameplate.font_size = 42
		nameplate.pixel_size = .0015
		nameplate.position = Vector3(actor.g.position.x, 2.18, 0)
		nameplate.modulate = Color("f0d99b") if column == 3 else Color("e4edf1")
		stage.add_child(nameplate)
	var rail := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(8.3, .008, .008)
	rail.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("c1a66d")
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rail.material_override = mat
	rail.position = Vector3(0, 1.8, -.34)
	stage.add_child(rail)

func _clear_stage() -> void:
	actors.clear()
	for node in stage.get_children():
		node.free()

func _accessories() -> void:
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.45
	camera.position = Vector3(2.4, 1.65, 5)
	camera.look_at(Vector3(0, 1.0, 0))
	var actor := Cast.person("two_pack", stage)
	actor.bino.visible = true
	actor.pose_binoculars()
	assert(actor.bino.get_parent() == actor.head)
	var gaps: Array[float] = []
	for i in 2:
		var gap := actor.hand_pos(i).distance_to(actor.binocular_grip_pos(i))
		assert(gap < .001, "Hands must meet production binocular grips")
		gaps.append(gap)
	await _save("04_player_binocular_binding", {"attachment": "actual Binoculars child of Head", "pose": "production Puppet.pose_binoculars", "hand_grip_gaps_m": gaps})
	actor.bino.visible = false
	actor.cup.visible = true
	actor.pose({"armL": [-1.15, .12], "look": -.16, "mouth": .35})
	assert(actor.cup.get_parent() == actor.hands[1])
	await _save("05_player_cup_binding", {"attachment": "actual Cup child of HandL", "pose": "attachment exercise, not a new gameplay animation"})
	_clear_stage()

func _bike() -> void:
	var bike = BICYCLE.new()
	stage.add_child(bike)
	bike.set_process(false)
	bike.set_physics_process(false)
	bike._build_model()
	bike._rider.g.visible = true
	for part in bike._legs + bike._shoes:
		part.visible = true
	camera.size = 2.6
	camera.position = Vector3(4, 1.8, 4.0)
	camera.look_at(Vector3(0, 1.0, 0))
	for phase in 4:
		bike._phase = float(phase) * PI / (2.0 * .55)
		bike._animate(1.0 / 60.0, 0.0)
		var hand_errors: Array[float] = []
		for side_index in 2:
			var side := -1.0 if side_index == 0 else 1.0
			var grip: Vector3 = bike._front.to_global(Vector3(side * .30, .22, -.04))
			var gap: float = bike._rider.hand_pos(side_index).distance_to(grip)
			hand_errors.append(gap)
			assert(gap < .001, "Production rider hand must meet the real bicycle grip")
		await _save("06_bicycle_pedal_%d" % phase, {"source": "city_bicycle._build_model + _animate", "pedal_phase": float(phase)*PI/2.0,
			"original_character_legs_hidden": true, "replacement_pedal_legs": bike._legs.size(), "hand_grip_gaps_m": hand_errors})
	camera.position = Vector3(5, 1.2, 0)
	camera.look_at(Vector3(0, 1.05, 0))
	await _save("07_bicycle_side_contact", {"purpose": "Actual saddle, hand/grip and foot/pedal alignment, side view"})
	_clear_stage()

func _phone() -> void:
	# Build the actual phone viewmodel against an inert player holder. Avoid setup,
	# overlays, input, storage, camera/photo capture, and gameplay world simulation.
	_lineup(false)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 58.0
	camera.position = Vector3(0, 1.65, 5.0)
	camera.look_at(Vector3(0, 1.15, 0))
	camera.cull_mask |= PHONE.VIEWMODEL_LAYER
	var holder = PLAYER.new()
	holder.camera = camera
	var phone = PHONE.new()
	phone.player = holder
	phone._build_viewmodel()
	phone._viewmodel.show()
	assert(phone._viewmodel.get_parent() == camera)
	await _save("08_actual_phone_viewmodel", {"source": "city_player_phone._build_viewmodel", "attachment": "Camera3D, not HandL/HandR",
		"limit": "This is the actual first-person phone/hand; no third-person phone posture is implemented."})
	phone._viewmodel.free()
	phone.free()
	holder.free()
	_clear_stage()

func _save(filename: String, details: Dictionary) -> void:
	for frame in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not root.has_focus(), "Private render must not take desktop input")
	var image := viewport.get_texture().get_image()
	assert(image != null and not image.is_empty())
	var path := LINEUP_OUT.path_join(filename + ".png")
	assert(image.save_png(path) == OK)
	details["image"] = ProjectSettings.globalize_path(path)
	evidence.append(details)
	print("[cast_motion] captured ", filename)
