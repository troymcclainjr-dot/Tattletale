extends "res://tests/city_car_showroom_runner.gd"
## Reuses the established private showroom stage/capture; only the occupied
## driver is hidden in comparison frames so an invisible occupant fails.
const Presentation := preload("res://scripts/city/city_vehicle_presentation.gd")
class LevelFixture:
	extends Node3D
	var paused := false
class CarFixture:
	extends Node3D
	var prototype_kind := "midsize_sedan"
	var model: Node3D
	var speed := 0.0
	var disabled := false

func _ready() -> void:
	OUTPUT = "res://../artifacts/priorities-five/driver-visuals"
	var args := OS.get_cmdline_user_args()
	var index := args.find("--capture-outdir")
	if index >= 0 and index + 1 < args.size():
		OUTPUT = args[index + 1]
	_run.call_deferred()

func _run() -> void:
	if not OS.get_cmdline_user_args().has("--offscreen-validation") or DisplayServer.get_name() == "headless":
		check(false, "requires --offscreen-validation and actual renderer; root remains hidden")
		get_tree().quit(1)
		return
	G.built = false
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	viewport = SubViewport.new()
	viewport.name = "PrivateDriverVisuals"
	viewport.size = Vector2i(1600, 900)
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	_build_stage()
	var level := LevelFixture.new()
	stage.add_child(level)
	var view := Presentation.new()
	level.add_child(view)
	view.setup(level)
	var states: Dictionary = {}
	for kind in ["midsize_sedan", "hatchback"]:
		var car := CarFixture.new()
		car.prototype_kind = kind
		level.add_child(car)
		car.model = Models.make(kind, 3)
		car.add_child(car.model)
		var body := car.model.get_node("Body") as MeshInstance3D
		var original := body.mesh
		view.attach(car)
		view.engine.stop() # This is a silent visual fixture.
		var transparent := 0
		for surface in body.mesh.get_surface_count():
			var material := body.get_active_material(surface)
			if material is StandardMaterial3D and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
				transparent += 1
		check(body.mesh != original and transparent > 0, kind + " has private cutout geometry and instance glass")
		states[kind] = {"geometry_private": body.mesh != original, "transparent_surfaces": transparent,
			"driver": view.driver.id, "hip_local": str(Presentation.seat_local_point(kind)), "hit_zones": str(view.get_occupant_hit_zones(car))}
		look(Vector3(5.6, 1.6, 0.1), Vector3(0, 0.85, 0.0), 50.0)
		await _driver_shot(kind + "-side", view)
		look(Vector3(4.4, 2.4, 5.0), Vector3(0, 0.85, 0.1), 55.0)
		await _driver_shot(kind + "-front-three-quarter", view)
		look(Vector3(2.3, 1.65, 1.5), Vector3(0.25, 1.05, 0.12), 48.0)
		await _driver_shot(kind + "-driver-detail", view)
		view.detach()
		check(body.mesh == original, kind + " restores shared body after visual capture")
		car.free()
	var report := {"captures": captures, "failures": failures, "driver_changed_samples": coverage,
		"vehicles": states, "viewport": [1600, 900], "note": "Private SubViewport. Review PNGs for pose/roof/pillar fit; changed pixels prove actual driver visibility only."}
	var file := FileAccess.open(OUTPUT.path_join("driver-visuals-report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	print("[driver_visuals] %d captures; %d failures" % [captures.size(), failures])
	get_tree().quit(0 if failures == 0 else 1)

func _driver_shot(filename: String, view: Node3D) -> void:
	view.driver.g.visible = false
	var empty := await capture(filename + "-driver-hidden", false)
	view.driver.g.visible = true
	var occupied := await capture(filename)
	var changed := 0
	if occupied != null and empty != null:
		for y in range(0, occupied.get_height(), 2):
			for x in range(0, occupied.get_width(), 2):
				var a := occupied.get_pixel(x, y)
				var b := empty.get_pixel(x, y)
				changed += int(absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.06)
	coverage[filename] = changed
	check(changed >= 20, "%s renders actual driver (%d changed samples)" % [filename, changed])
