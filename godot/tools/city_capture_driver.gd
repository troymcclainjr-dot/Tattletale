extends Node
## Capture the real playable scene, including its UI, without changes to the source asset.

var output := "res://../artifacts/pen-lucy"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--outdir")
	if index >= 0 and index + 1 < args.size():
		output = args[index + 1]
	_run.call_deferred()

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func save_view(name_: String) -> void:
	await frames(20)
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png(output.path_join(name_ + ".png"))
	print("[city_capture] %s: %s" % [name_, error_string(result)])

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var began := Time.get_ticks_msec()
	get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn")
	await frames(5)
	var level: Node = get_tree().current_scene
	while not level.level_ready:
		await frames(1)
	print("[city_capture] ready in %.2fs; collision meshes %d; street props %d" % [(Time.get_ticks_msec() - began) / 1000.0, level.collision_meshes, level.dressing_report.get("count", 0)])
	# Let the real FPS counter settle after synchronous scene/cache loading.
	await frames(180)
	print("[city_capture] viewport ", get_viewport().get_visible_rect().size)
	print("[city_capture] weathering ", level.weathering_report)
	print("[city_capture] population ", level.npcs.get_status().count, " fixtures ", level.traffic.street_details)
	await save_view("welcome")
	level.resume_exploring()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await save_view("walk")
	level.teleport_to_landmark("old_york_wyanoke")
	level.player.camera_yaw = PI * 0.5
	level.player.camera_pitch = 0.12
	await save_view("corner")
	level._ui.hide()
	level.capture_view(Vector3(270, 340, 300), Vector3(90, -5, -70))
	await save_view("overview")
	level.player.camera.fov = 50.0
	level.capture_view(Vector3(133.82, 0.96, -91.92), Vector3(140.71, 2.62, -80.14))
	await save_view("rowhouses")
	level.capture_view(Vector3(0, 5.2, -88), Vector3(-5.876, 4.4, -98.433))
	await save_view("street-details")
	for activity in ["porch", "social"]:
		for resident in level.npcs.crowd.residents:
			if resident.activity != activity:
				continue
			var at: Vector3 = resident.position
			var forward := Vector3(sin(float(resident.yaw)), 0, cos(float(resident.yaw)))
			var right := Vector3(forward.z, 0, -forward.x)
			level.capture_view(at + forward * 6.0 + right * 3.0 + Vector3.UP * 2.6, at + Vector3.UP * 0.9)
			await save_view("porch-life" if activity == "porch" else "corner-hangout")
			break
	var grilles: Node3D = level.get_node_or_null("WindowSecurityGrilles")
	var closest := INF
	var grille_pose := Transform3D.IDENTITY
	if grilles != null:
		for batch in grilles.get_children():
			for i in batch.multimesh.instance_count:
				var pose: Transform3D = batch.global_transform * batch.multimesh.get_instance_transform(i)
				var distance: float = pose.origin.distance_to(level.player.position)
				if distance < closest:
					closest = distance
					grille_pose = pose
		if closest < INF:
			level.capture_view(grille_pose.origin + grille_pose.basis.z.normalized() * 4.0 + grille_pose.basis.x.normalized() * 1.4 + Vector3.UP * 0.3, grille_pose.origin)
			await save_view("barred-windows")
	var junction: Vector3 = level.traffic.signals.junction
	level.capture_view(junction + Vector3(14, 9, 18), junction + Vector3.UP * 1.7)
	await save_view("intersection-controls")
	var litter: Node3D = level.get_node_or_null("RoadsideLitter")
	if litter != null:
		for batch in litter.get_children():
			if batch is MultiMeshInstance3D and batch.multimesh.instance_count > 2:
				var piece: Vector3 = batch.global_transform * batch.multimesh.get_instance_transform(0).origin
				level.capture_view(piece + Vector3(2.0, 1.4, 2.0), piece)
				await save_view("roadside-litter")
				break
	level.player.camera.fov = 68.0
	level.release_capture_view()
	level._ui.show()
	level.spawn_player()
	level.resume_exploring()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await frames(90)
	level.capture_view(Vector3(13, 8, 18), Vector3(-4, 1.8, -25))
	level._ui.hide()
	await save_view("street-life")
	if not level.traffic.vehicles.is_empty():
		var car: Node3D = level.traffic.vehicles[0]
		level.capture_view(car.global_position + Vector3(9, 6, 11), car.global_position + Vector3.UP)
		await save_view("traffic")
	level.release_capture_view()
	level._ui.show()
	level.start_neighborhood_case("lost_satchel")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var status: Dictionary = level.missions.get_status()
	var contact: Vector3 = level.vector(status.get("target_position"))
	level._place_player(contact + Vector3(1.7, 0.0, 0.0), -PI / 2.0)
	level.player.camera_yaw = -1.0
	level.player.camera_pitch = 0.20
	await save_view("case-contact")
	level.interact()
	status = level.missions.get_status()
	var clue: Vector3 = level.vector(status.get("target_position"))
	level._place_player(clue + Vector3(1.7, 0.0, 0.0), -PI / 2.0)
	level.player.camera_pitch = 0.38
	await save_view("case-evidence")
	level.pause_exploring()
	await save_view("settings-video")
	var tabs: TabContainer = level._settings.find_children("*", "TabContainer", true, false)[0]
	tabs.current_tab = 1
	await save_view("settings-audio")
	tabs.current_tab = 2
	await save_view("settings-controls")
	level.resume_exploring()
	level.toggle_map()
	await save_view("neighborhood-map")
	level.toggle_map()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await frames(30)
	var t0 := Time.get_ticks_usec()
	await frames(120)
	print("[city_capture] stationary render %.1f fps; draw calls %d; primitives %d" % [120.0 / ((Time.get_ticks_usec() - t0) / 1000000.0), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	get_tree().quit()
