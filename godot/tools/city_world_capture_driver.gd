extends Node
var level: Node3D
var output := "res://../artifacts/pen-lucy-world"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--outdir")
	if index >= 0 and index + 1 < args.size():
		output = args[index + 1]
	_run.call_deferred()

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func view(eye: Vector3, target: Vector3, filename: String) -> void:
	level._place_player(target, 0.0)
	level.player.first_person = true
	level.capture_view(eye, target)
	level.streaming.refresh_now()
	for i in 600:
		await frames(1)
		if level.streaming.get_status().near_cells_missing == 0:
			break
	await frames(45)
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(output.path_join(filename + ".png"))
	print("[world_capture] ", filename, " ", error_string(error))

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn")
	await frames(5)
	level = get_tree().current_scene
	for i in 1800:
		if level.level_ready:
			break
		await frames(1)
	if not level.level_ready:
		get_tree().quit(1)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var window := get_tree().root
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_size = Vector2i(1920, 1080)
	window.content_scale_factor = 1.0
	window.size = Vector2i(1920, 1080)
	window.scaling_3d_scale = 1.0
	level.resume_exploring()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await frames(120)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join("playable.png"))
	level.pause_exploring()
	level._ui.hide()
	var corner: Dictionary = level.ground_at(Vector3(12, 0, -82))
	if not corner.is_empty():
		var point: Vector3 = corner.position
		await view(point + Vector3(-12, 3.5, 7), point + Vector3(1, 3, -12), "dumbarton-repaired-corner")
	var sidewalk: Dictionary = level.ground_at(Vector3(295, 0, 35))
	if not sidewalk.is_empty():
		var point: Vector3 = sidewalk.position
		await view(point + Vector3(-5, 2.5, 6), point + Vector3(3, 0.4, -5), "graded-pedestrian-path")
	var crowd: Node = level.npcs.crowd
	var porch_count := 0
	for resident in crowd.residents:
		if resident.activity != "porch" or int(resident.pose) != 1:
			continue
		var point: Vector3 = resident.position
		var front := Vector3(sin(float(resident.yaw)), 0, cos(float(resident.yaw)))
		await view(point + front * 7.0 + Vector3(-front.z, 0, front.x) * 2.0 + Vector3.UP * 2.2, point + Vector3.UP * 0.8, "porch-%d" % porch_count)
		porch_count += 1
		if porch_count >= 3:
			break
	var circle_count := 0
	for group in crowd._circle_groups:
		var point: Vector3 = group.center
		await view(_street_eye(point), point + Vector3.UP, "neighbors-%d" % circle_count)
		circle_count += 1
		if circle_count >= 3:
			break
	var business_count := 0
	for business in level.neighborhood_details.get_business_fronts():
		var point: Vector3 = business.position
		var normal: Vector3 = business.normal
		await view(point + normal * 8.0 + Vector3.UP * 0.2, point - Vector3.UP * 0.8, "business-%02d" % business_count)
		business_count += 1
		if business_count >= 18:
			break
	var park_centers: Dictionary = {}
	for resident in crowd.residents:
		if resident.activity != "park":
			continue
		var park_name: String = resident.get("park_name", "Park")
		if not park_centers.has(park_name):
			park_centers[park_name] = {"sum": Vector3.ZERO, "count": 0}
		park_centers[park_name].sum += resident.position
		park_centers[park_name].count += 1
	var park_views := 0
	for name_ in park_centers:
		if int(park_centers[name_].count) < 35:
			continue
		var center: Vector3 = park_centers[name_].sum / float(park_centers[name_].count)
		var point := center
		var nearest := INF
		for resident in crowd.residents:
			if resident.activity == "park" and resident.get("park_name", "") == name_:
				var distance: float = resident.position.distance_squared_to(center)
				if distance < nearest:
					nearest = distance
					point = resident.position
		# Aim at an occupied patch rather than a polygon's possibly occupied
		# central hole, and clear the neighboring roofline with the camera.
		await view(point + Vector3(8, 22, 12), point + Vector3.UP, "park-%d" % park_views)
		park_views += 1
		if park_views >= 3:
			break
	var patrol_views := 0
	for id in level.npcs.actors:
		if not str(id).begins_with("patrol_officer_"):
			continue
		var point: Vector3 = level.npcs.actors[id].global_position
		await view(_street_eye(point), point + Vector3.UP, "foot-patrol-%d" % patrol_views)
		patrol_views += 1
		if patrol_views >= 2:
			break
	var rear_views := 0
	for door in level.level_data.get("rear_doors", []):
		var point: Vector3 = level.vector(door.position)
		var normal: Vector3 = level.vector(door.normal)
		await view(point + normal * 5.0 + Vector3.UP * 1.6, point + Vector3.UP, "rear-door-%d" % rear_views)
		rear_views += 1
		if rear_views >= 2:
			break
	var captured: Dictionary = {}
	for record in level.neighborhood_details.records:
		var kind: String = record.kind
		if kind not in ["postal_drop", "mailbox", "pothole", "crosswalk_stripe", "road_dot"] or captured.has(kind):
			continue
		var point: Vector3 = record.position
		await view(point + Vector3(3.0, 3.0, 4.0), point, kind)
		captured[kind] = true
	if level.traffic.parked != null:
		var parking_views := 0
		for record in level.traffic.parked.records:
			var point: Vector3 = record.pose.origin
			await view(point + record.pose.basis.x * 7.0 + record.pose.basis.z * 8.0 + Vector3.UP * 4.0, point + Vector3.UP, "parked-%d" % parking_views)
			parking_views += 1
			if parking_views >= 3:
				break
	if level.vegetation != null:
		var examples := {}
		var origin: Vector3 = level.vector(level.level_data.spawn.position)
		for plants in level.vegetation._cells.values():
			for plant in plants:
				var kind: String = plant.kind
				var point: Vector3 = plant.position
				if not examples.has(kind) or point.distance_squared_to(origin) < (examples[kind].position as Vector3).distance_squared_to(origin):
					examples[kind] = plant
		for kind in examples:
			var plant: Dictionary = examples[kind]
			var point: Vector3 = plant.position
			var height: float = plant.height
			var distance := maxf(height * 1.25, 4.0)
			var outward := (_street_eye(point) - point).normalized()
			outward.y = 0.0
			await view(point + outward.normalized() * distance + Vector3.UP * (height * 0.5 + 1.0), point + Vector3.UP * height * 0.45, str(kind))
	level._ui.show()
	level.toggle_map()
	await frames(5)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join("full-map.png"))
	level._map_overlay.map.zoom_by(2.0)
	await frames(5)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join("full-map-zoom.png"))
	var report := {"crowd": crowd.get_status(), "people": level.npcs.get_status(), "traffic": level.traffic.get_status(), "details": level.neighborhood_details.get_status(), "streaming": level.streaming.get_status(), "vegetation": level.vegetation.get_stats() if level.vegetation != null else {}}
	var file := FileAccess.open(output.path_join("world-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("[world_capture] saved report; residents=", report.crowd.total, " people=", report.people.count, " moving fleet=", report.traffic.total, " businesses=", report.details.counts.get("business", 0))
	get_tree().quit()

func _street_eye(point: Vector3) -> Vector3:
	var best := INF
	var eye := point + Vector3(6, 4, 7)
	for road in level.level_data.roads:
		var points: Array = road.points
		for i in range(1, points.size()):
			var a: Vector3 = level.vector(points[i - 1])
			var b: Vector3 = level.vector(points[i])
			var nearest := Geometry2D.get_closest_point_to_segment(Vector2(point.x, point.z), Vector2(a.x, a.z), Vector2(b.x, b.z))
			var distance := nearest.distance_to(Vector2(point.x, point.z))
			if distance < best:
				best = distance
				var outward := Vector3(nearest.x - point.x, 0, nearest.y - point.z).normalized()
				var along := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
				eye = point + outward * 6.5 + along * 2.0 + Vector3.UP * 3.0
	return eye
