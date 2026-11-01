extends "res://tests/city_priorities_session_fixture.gd"
func _run() -> void:
	if not await boot_world():
		_finish()
		return
	begin_phase("argonne-traffic")
	if DisplayServer.get_name() != "headless":
		await _ground_views()
		if OS.get_cmdline_user_args().has("--ground-only"):
			_finish()
			return
	_set_scenario_position(Vector3(429.94, -6.6, -68.94))
	player.enabled = false
	var observations: Array = []
	for second in 90:
		await get_tree().create_timer(1.0).timeout
		if second % 10 != 9:
			continue
		var cars: Array = []
		for car in level.traffic.vehicles + level.traffic.player_fleet:
			if car.global_position.distance_to(Vector3(439.28,-6.85,-75.71)) < 65.0:
				var status: Dictionary = car.get_status()
				status["route_target"] = car.route[car.route_index] if car.route_index < car.route.size() else Vector3.INF
				status["body_name"] = str(car.name)
				cars.append(status)
		observations.append({"second":second+1,"cars":cars})
		print("[argonne_probe] ", JSON.stringify(observations[-1]))
	result_details["traffic_observations"] = observations
	_finish()

func _ground_views() -> void:
	var shots := [{"id":"argonne", "eye":Vector3(450.43,1.39,-90.51),"yaw":309.24,"pitch":-23.62},
		{"id":"hospital", "eye":Vector3(423.43,1.19,-112.21),"yaw":33.26,"pitch":-39.30}]
	var terrain: Array[Dictionary] = []
	var lawn_cells: Array[Dictionary] = []
	for node in level.find_children("*", "MeshInstance3D", true, false):
		if str(node.name) in ["Ground", "Curbs"]:
			terrain.append({"node": node, "mesh": node.mesh, "layers": node.layers, "override": node.material_override})
		if str(node.get_parent().name).begins_with("FrontLawnCell_"):
			lawn_cells.append({"node": node, "layers": node.layers, "override": node.material_override})
	var flat := StandardMaterial3D.new()
	flat.albedo_color = Color("667c47")
	flat.roughness = 1.0
	var diagnostics: Array = []
	var modes := ["normal"]
	if OS.get_cmdline_user_args().has("--ground-isolation"):
		modes.append_array(["no_front_overlays", "no_curbs", "no_ground", "plain_terrain"])
	for shot in shots:
		_set_scenario_position(shot.eye)
		level.inspector.enter()
		level.inspector.eye = shot.eye
		level.inspector.yaw = deg_to_rad(shot.yaw)
		level.inspector.pitch = deg_to_rad(shot.pitch)
		player.camera.fov = 83.0
		level.inspector._apply_view()
		level.inspector._canvas.hide()
		for mode in modes:
			for entry in terrain:
				entry.node.mesh = entry.mesh
				entry.node.layers = entry.layers
				entry.node.material_override = entry.override
			for entry in lawn_cells:
				entry.node.layers = entry.layers
				entry.node.material_override = entry.override
			if mode == "no_front_overlays":
				for entry in lawn_cells:
					entry.node.layers = 0
			if mode in ["no_curbs", "no_ground"]:
				for entry in terrain:
					if str(entry.node.name) == ("Curbs" if mode == "no_curbs" else "Ground"):
						entry.node.layers = 0
			if mode == "plain_terrain":
				for entry in terrain + lawn_cells:
					entry.node.material_override = flat
			await frames(20)
			await RenderingServer.frame_post_draw
			diagnostics.append({"shot": shot.id, "mode": mode, "lod_threshold": get_viewport().mesh_lod_threshold,
				"ground_meshes": terrain.size(), "front_overlay_meshes": lawn_cells.size()})
			get_viewport().get_texture().get_image().save_png(output_dir.path_join(str(shot.id)+"-"+mode+".png"))
		level.inspector.leave()
	for entry in terrain:
		entry.node.mesh = entry.mesh
		entry.node.layers = entry.layers
		entry.node.material_override = entry.override
	for entry in lawn_cells:
		entry.node.layers = entry.layers
		entry.node.material_override = entry.override
	result_details["ground_diagnostics"] = diagnostics
