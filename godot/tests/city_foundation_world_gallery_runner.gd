extends "res://tests/city_priorities_session_fixture.gd"
## Production-world acceptance images. Only camera composition/HUD visibility
## change: player, time, populations, collision and detail-provider presence stay live.
var gallery: Array[Dictionary] = []
var _baseline_static: Dictionary = {}

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--offscreen-validation"):
		check(false, "rendered gallery requires explicit --offscreen-validation and a graphical backend")
		_finish()
		return
	if not await boot_world():
		_finish()
		return
	var original_override: Dictionary = player.camera_override.duplicate(true)
	var original_fov: float = player.camera_fov
	var original_ui: bool = level._ui.visible
	var original_layer: int = player.collision_layer
	var original_mask: int = player.collision_mask
	var original_position: Vector3 = player.global_position
	_baseline_static = _static_inventory()
	level._ui.hide()
	var views: Array[Dictionary] = _views()
	check(views.size() == 8, "eight production subjects resolve from current metadata")
	for view in views:
		await _capture(view)
		if not _window_off_desktop() or Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
			break
	player.camera_override = original_override
	player.camera_fov = original_fov
	player.update_camera()
	level._ui.visible = original_ui
	check(gallery.size() == 8, "eight production PNGs written")
	check(player.collision_layer == original_layer and player.collision_mask == original_mask,
		"player collision layer/mask unchanged")
	check(level.is_physics_processing() and player.is_physics_processing() and not level.paused,
		"world and player simulation remain live")
	result_details["gallery"] = gallery
	result_details["static_colliders_before"] = _baseline_static
	result_details["static_colliders_after"] = _static_inventory()
	result_details["player_start"] = _xyz(original_position)
	result_details["player_end"] = _xyz(player.global_position)
	result_details["player_displacement_m"] = original_position.distance_to(player.global_position)
	result_details["fixture_relocations"] = 0
	result_details["limitations"] = "Camera-only architecture review. Normal simulation can move actors. Detail visuals include the camera neighborhood; player collision residency is retained. Road distances are metadata corridor estimates, not mesh intersection proof; eye probes test collision surfaces, not all visual triangles. PNG composition still requires visual review."
	_finish()

func _views() -> Array[Dictionary]:
	var views: Array[Dictionary] = []
	# Stable identities resolve from the published runtime metadata, never the
	# staging source. Rose Hill and East 41st show genuinely different bay families.
	for spec in [
		{"id": "01-rose-hill-walk", "building": "w336345756", "distance": 10.0, "side": 5.0, "height": 1.7},
		{"id": "02-east-41st-oblique", "building": "w336340482", "distance": 14.0, "side": -7.0, "height": 4.5}]:
		var found := false
		for facade in level.level_data.get("facade_details", []):
			if str(facade.building_id) != str(spec.building):
				continue
			var view: Dictionary = spec.duplicate(true)
			view["anchor"] = point(facade.position)
			view["target"] = point(facade.position) - Vector3.UP * 1.0
			view["normal"] = point(facade.normal).normalized()
			view["subject"] = facade.duplicate(true)
			view["fov"] = 65.0
			views.append(view)
			found = true
			break
		check(found, "published facade exists: " + str(spec.building))
	# Row_186 is intentionally retained beside the hospital; include its mixed
	# porch/stoop frontage and existing pitched-roof rhythm, not just a bay sample.
	for stair in level.level_data.get("porch_stairs", []):
		if str(stair.building_id) == "w336328500":
			views.append({"id": "03-argonne-row-186", "anchor": point(stair.landing),
				"target": point(stair.landing) + Vector3.UP * 2.7, "normal": point(stair.normal).normalized(),
				"distance": 14.0, "side": 8.0, "height": 4.0, "fov": 70.0,
				"subject": {"source_mesh": "Row_186", "building_id": str(stair.building_id), "street": "Argonne Drive", "stair": stair}})
			break
	if level.get("civic_district") != null:
		for civic_id in ["police", "fire", "courthouse", "hospital"]:
			for site in level.civic_district.sites:
				if str(site.id) != civic_id:
					continue
				var center := point(site.position)
				var normal := Vector3(sin(float(site.yaw)), 0, cos(float(site.yaw)))
				views.append({"id": "%02d-%s" % [views.size() + 1, civic_id], "anchor": center,
					"target": center + Vector3.UP * (7.5 if civic_id == "hospital" else 5.0), "normal": normal,
					"distance": 26.0 if civic_id == "police" else float(site.depth_m) * .5 + 27.0,
					"side": 8.0 if civic_id == "police" else 16.0, "height": 8.0 if civic_id == "police" else 10.0,
					"fov": 65.0 if civic_id == "hospital" else 60.0,
					"subject": {"civic_id": civic_id, "name": site.name, "clearance_audit": site.get("clearance_audit", {})}})
				break
	# Published source survey: w336344637/Bldg_212, a low garage facing Old York.
	# Coordinates are game-space metres; ground height is sampled from live terrain.
	views.append({"id": "08-old-york-garage", "anchor": Vector3(15.86, .90, -43.83),
		"target": Vector3(15.86, 2.00, -43.83), "normal": Vector3(-.999194, 0, .040132),
		"distance": 8.0, "side": 2.0, "height": 1.7, "fov": 60.0,
		"subject": {"building_id": "w336344637", "source_mesh": "Bldg_212", "archetype": "garage",
			"coordinate_source": "blender/city/data/pen_lucy_buildings.geojson"}})
	return views

func _capture(view: Dictionary) -> void:
	begin_phase(str(view.id))
	var composition := _choose_eye(view)
	check(not composition.is_empty(), "camera near-plane sphere clears static world surfaces")
	if composition.is_empty():
		return
	var eye: Vector3 = composition.eye
	var target: Vector3 = view.target
	level.capture_view(eye, target)
	player.camera_fov = float(view.fov)
	player.update_camera()
	player.camera.reset_physics_interpolation()
	level.streaming.refresh_now()
	var status: Dictionary = {}
	var wait_frames := 0
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline:
		level.streaming.refresh_now()
		await frames(1)
		wait_frames += 1
		status = level.streaming.get_status()
		if int(status.get("near_cells_missing", 0)) == 0 and not bool(status.get("pending", false)) and int(status.get("detail_missing", 0)) == 0 and int(status.get("detail_pending", 0)) == 0:
			break
	check(int(status.get("near_cells_missing", 0)) == 0 and int(status.get("failures", 0)) == 0,
		"nearby production building cells loaded")
	check(int(status.get("detail_missing", 0)) == 0 and int(status.get("detail_pending", 0)) == 0, "camera detail providers finish residency")
	check(status.get("collision_streaming") == false, "camera focus preserves authoritative terrain/building collision")
	await frames(12)
	var safe := _window_off_desktop() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
	check(safe, "render window remains outside monitors and unfocused; mouse visible")
	if not safe:
		return
	await RenderingServer.frame_post_draw
	var screenshot := get_viewport().get_texture().get_image()
	check(screenshot != null and not screenshot.is_empty(), "rendered viewport image exists")
	if screenshot == null or screenshot.is_empty():
		return
	var path: String = output_dir.path_join(str(view.id) + ".png")
	var saved := screenshot.save_png(path) == OK
	check(saved, "production image saved: " + str(view.id))
	if not saved:
		return
	var ray := PhysicsRayQueryParameters3D.create(eye, target, 1 | 2)
	ray.exclude = [player.get_rid()]
	var first_hit: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(ray)
	var line_evidence: Dictionary = {"hit": not first_hit.is_empty()}
	if not first_hit.is_empty():
		line_evidence["distance_m"] = eye.distance_to(first_hit.position)
		line_evidence["distance_to_target_m"] = target.distance_to(first_hit.position)
		line_evidence["node"] = str(first_hit.collider.get_path())
	gallery.append({"id": view.id, "path": path, "width": screenshot.get_width(), "height": screenshot.get_height(),
		"eye": _xyz(eye), "target": _xyz(target), "fov": view.fov, "composition": composition.evidence,
		"subject": view.subject, "streaming": status, "stream_wait_frames": wait_frames,
		"center_ray": line_evidence, "camera_road_corridor": _road_distance(eye),
		"subject_road_corridor": _road_distance(view.anchor), "static_colliders": _static_inventory(),
		"clock_minutes": float(level.world_time.minute_of_day), "player_position": _xyz(player.global_position),
		"rendered_draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"rendered_primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)})
	# Persist progress before moving the camera so a later runtime failure still
	# leaves exact image provenance for the successfully completed captures.
	var receipt := FileAccess.open(output_dir.path_join("gallery.json"), FileAccess.WRITE)
	if receipt != null:
		receipt.store_string(JSON.stringify({"complete": gallery.size() == 8, "captures": gallery}, "\t"))
		receipt.flush()

func _choose_eye(view: Dictionary) -> Dictionary:
	var normal: Vector3 = view.normal
	var right := Vector3(normal.z, 0, -normal.x)
	var shape := SphereShape3D.new()
	shape.radius = .22
	# Small alternate lateral offsets avoid poles/walls without editing the world
	# or silently turning the requested walking-height view into an aerial shot.
	for lateral in [0.0, 2.5, -2.5, 5.0, -5.0]:
		var eye: Vector3 = view.anchor + normal * float(view.distance) + right * (float(view.side) + lateral)
		var terrain: Dictionary = level.ground_at(eye)
		if terrain.is_empty():
			continue
		eye.y = terrain.position.y + float(view.height)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(Basis.IDENTITY, eye)
		query.collision_mask = 1 | 2
		query.exclude = [player.get_rid()]
		var overlaps: Array[Dictionary] = level.get_world_3d().direct_space_state.intersect_shape(query, 16)
		if overlaps.is_empty():
			return {"eye": eye, "evidence": {"eye_static_overlaps": 0, "probe_radius_m": .22,
				"height_above_ground_m": float(view.height), "lateral_adjustment_m": lateral,
				"terrain_y": terrain.position.y}}
	return {}

func _road_distance(at: Vector3) -> Dictionary:
	var nearest := INF
	var result: Dictionary = {}
	for road in level.level_data.get("roads", []):
		var points: Array = road.points
		for index in range(1, points.size()):
			var a := point(points[index - 1])
			var b := point(points[index])
			var closest := Geometry2D.get_closest_point_to_segment(Vector2(at.x, at.z), Vector2(a.x, a.z), Vector2(b.x, b.z))
			var distance := closest.distance_to(Vector2(at.x, at.z))
			var margin := distance - float(road.get("width", 0)) * .5
			if margin < nearest:
				nearest = margin
				result = {"street": str(road.get("name", "")), "centerline_distance_m": distance,
					"signed_road_edge_distance_m": margin, "method": "2D centerline minus half metadata road width"}
	return result

func _static_inventory() -> Dictionary:
	var count := 0
	var shapes := 0
	var disabled := 0
	var layer_counts: Dictionary = {}
	for body in level.find_children("*", "StaticBody3D", true, false):
		count += 1
		var key := str(body.collision_layer)
		layer_counts[key] = int(layer_counts.get(key, 0)) + 1
		for owner_id in body.get_shape_owners():
			shapes += body.shape_owner_get_shape_count(owner_id)
			disabled += int(body.is_shape_owner_disabled(owner_id))
	return {"bodies": count, "shapes": shapes, "disabled_shape_owners": disabled, "bodies_by_layer": layer_counts}

func _xyz(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
