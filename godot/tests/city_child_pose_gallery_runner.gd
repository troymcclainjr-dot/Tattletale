extends "res://tests/city_cast_motion_gallery_runner.gd"
## Child-specific follow-up: real legacy crawl/walk rig after the infant refit.
func _run() -> void:
	assert(OS.get_cmdline_user_args().has("--offscreen-validation"))
	assert(DisplayServer.get_name() != "headless")
	_setup()
	viewport.size = Vector2i(1280, 900)
	# The general gallery recesses its floor 15mm. Contact QA needs the actual
	# zero-metre plane and a shadow, otherwise even grounded small feet float.
	for node in viewport.get_children():
		if node is MeshInstance3D and node.mesh is PlaneMesh:
			node.position.y = 0.0
		elif node is DirectionalLight3D and node.light_energy > 1.0:
			node.shadow_enabled = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LINEUP_OUT))
	var baby := Cast.person("baby", stage)
	camera.size = .82
	camera.position = Vector3(.65, .43, 1.8)
	camera.look_at(Vector3(0, .29, 0))
	baby.pose({})
	await _save("09_baby_v2_rest", {"purpose": "Infant head about one-quarter height; short chubby legs"})
	baby.crawl(0.0, 0.0)
	camera.position = Vector3(.8, .45, 1.2)
	camera.look_at(Vector3(0, .24, .05))
	await _save("10_baby_v2_actual_crawl", {"source": "Production Puppet.crawl: actual limb contact fit", "phase": 0.0})
	camera.position = Vector3(1.5, .30, 0)
	camera.look_at(Vector3(0, .24, .05))
	await _save("11_baby_v2_crawl_side", {"purpose": "Actual crawl hand/foot/head-ground relationship"})
	for phase in 2:
		baby.crawl(PI * (.5 + float(phase)), 0.0)
		await _save("11_baby_v2_crawl_step_%d" % phase, {"source": "Production Puppet.crawl", "phase": PI * (.5 + float(phase))})
	_clear_stage()
	var child := Cast.person("timmy", stage)
	camera.size = 1.3
	camera.position = Vector3(.8, .70, 2.3)
	camera.look_at(Vector3(0, .48, 0))
	child.pose({})
	await _save("12_timmy_v2_rest", {"purpose": "Older-child profile retained separately from infant/adult"})
	child.phase = PI / 2.0
	child.pose({"walk": .42})
	await _save("13_timmy_v2_walk", {"source": "Puppet.pose actual walk phase PI/2"})
	# Oblique projection can superimpose opposite stepping feet. Straight front
	# and side views distinguish that from actual midline crossing/intersection.
	camera.position = Vector3(0, .48, 2.3)
	camera.look_at(Vector3(0, .48, 0))
	await _save("14_timmy_v2_walk_front", {"purpose": "Straight front leg-lane separation; actual pure-X pivots"})
	camera.position = Vector3(2.3, .48, 0)
	camera.look_at(Vector3(0, .48, 0))
	await _save("15_timmy_v2_walk_side", {"purpose": "Side view disambiguates forward/back foot spacing from oblique overlap"})
	var file := FileAccess.open(LINEUP_OUT.path_join("child-pose-evidence.json"), FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"captures": evidence, "limit": "Discrete visual pose snapshots; no gameplay physics or contacts modified."}, "\t"))
	file.close()
	print("[child_pose] COMPLETE ", evidence.size(), " captures")
	get_tree().quit(0)
