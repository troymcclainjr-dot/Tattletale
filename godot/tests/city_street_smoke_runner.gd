extends Node
## End-to-end road fixture, signal behavior and traffic spacing checks.
const Surfaces := preload("res://scripts/city/city_street_surfaces.gd")

var passes := 0
var fails := 0
var stop_control_verified := false

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passes += 1
	else:
		fails += 1
	print("[city_street] %s %s" % ["PASS" if ok else "FAIL", label])

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn")
	await frames(4)
	var level: Node = get_tree().current_scene
	for i in 600:
		if level != null and level.get("level_ready") == true:
			break
		await frames(1)
		level = get_tree().current_scene
	if level == null or level.get("level_ready") != true:
		check(false, "neighborhood initializes")
		_finish()
		return
	level.pause_exploring()
	await frames(2)
	var traffic: Node3D = level.traffic
	var details: Dictionary = traffic.street_details
	check(traffic.vehicles.size() >= 6, "at least six physical sedans spawn")
	check(int(details.get("street_lamps", 0)) >= 10, "streetlamps extend along actual road polylines")
	check(int(details.get("fixture_batches", 0)) == 2, "all streetlights and stop signs share two geometry batches")
	check(int(details.get("stop_signs", 0)) >= 12, "unlit junctions receive neighborhood-wide stop controls")
	var mesh := CityDressing.source_lamp_mesh()
	check(mesh != null and mesh.get_aabb().size.x < 0.6 and mesh.get_aabb().size.y > 4.5, "extracted original lamp contains exactly one standing fixture")
	check(traffic.signals.heads.size() >= 2, "original signal heads survive ground and route-clearance validation")
	_audit_map_fixtures(level, traffic)
	if "--capture-street-fixtures" in OS.get_cmdline_user_args():
		await _capture_fixtures(level, traffic)
	var paints: Dictionary = {}
	var trim_preserved := true
	var paint_shared := true
	for car in traffic.vehicles:
		check(car._pose_clear(car.global_transform), "physical car begins inside clear roadway: " + str(car.name))
		var body := Assets.find(car.model, "Body") as MeshInstance3D
		if body:
			for surface in body.mesh.get_surface_count():
				var paint_override := body.get_surface_override_material(surface)
				if paint_override == null:
					continue
				trim_preserved = trim_preserved and body.mesh.surface_get_material(surface).resource_name == "city_vehicle_paint"
				var color: String = car.paint_color
				if paints.has(color):
					paint_shared = paint_shared and paints[color] == paint_override.get_instance_id()
				paints[color] = paint_override.get_instance_id()
	check(paints.size() >= 4 and paint_shared, "traffic paint palette reuses shared materials")
	check(trim_preserved, "car paint overrides preserve original glass and trim surfaces")
	var signals: Node3D = traffic.signals
	var exclusive := true
	for second in 360:
		signals.elapsed = second / 10.0
		exclusive = exclusive and not (signals.phase("old_york") != "Red" and signals.phase("wyanoke") != "Red")
	check(exclusive, "opposing road axes never receive conflicting green or amber")
	signals.elapsed = 20.0
	check(signals.phase("old_york") == "Red" and signals.phase("wyanoke") == "Red", "all-red clearance phase separates road axes")
	signals.elapsed = 0.0
	check(is_finite(signals.stopping_distance(Vector3(20, 0, 0), Vector3.LEFT, 2.35)), "cross-street cars also observe their red signal")
	signals.elapsed = 22.0
	check(not is_finite(signals.stopping_distance(Vector3(20, 0, 0), Vector3.LEFT, 2.35)), "cross-street green releases its approach")
	var car = traffic.vehicles[0]
	_check_stop_control(traffic, car)
	check(stop_control_verified, "stop-control regression completes both dwell and release checks")
	# Other frozen vehicles are not participants in this isolated signal test.
	for other in traffic.vehicles:
		if other != car:
			other.collision_layer = 0
	# Independent northbound route crosses the physical signal's stop line.
	car.set_manual_route(traffic._lane_path(traffic.road_length * 0.42, traffic.road_length * 0.59))
	car.near_physics = true
	var direction: Vector3 = (car.route[1] - car.route[0]).normalized()
	car.yaw = atan2(direction.x, direction.z)
	var ground: Dictionary = car._ground_pose(car.route[0], car.yaw)
	check(not ground.is_empty(), "signal test lane is grounded")
	if not ground.is_empty():
		car.global_transform = ground.transform
		car.state = "waiting"
		car.speed = 0.0
		signals.elapsed = 22.0
		signals.update_lenses()
		for i in 480:
			car.tick(1.0 / 60.0)
			await frames(1)
		check(car.state == "blocked" and car.blocked_reason == "Waiting at traffic signal", "sedan stops at a red signal")
		check(car.global_position.z - car.BODY_SIZE.z * 0.5 >= signals.junction.z + signals.STOP_LINE - 0.12, "front bumper stays behind stop line")
		var stopped: Vector3 = car.global_position
		for i in 30:
			car.tick(1.0 / 60.0)
			await frames(1)
		check(car.global_position.distance_to(stopped) < 0.01 and car.honks == 0, "red-light wait is stationary and silent")
		signals.elapsed = 0.0
		signals.update_lenses()
		for i in 180:
			car.tick(1.0 / 60.0)
			await frames(1)
		check(car.global_position.distance_to(stopped) > 3.0, "green signal releases waiting traffic")
		check(not car.try_recycle(), "active vehicle cannot visibly recycle")
	var summary: Dictionary = details.duplicate()
	for key in ["lamp_anchors", "stop_anchors", "stop_lane_ids", "stop_placement_checks"]:
		summary.erase(key)
	print("[city_street] details ", summary, " signals ", signals.get_status())
	_finish()

func _audit_map_fixtures(level: Node, traffic: Node3D) -> void:
	check(bool(Surfaces.get_status().available), "exact exported sidewalk/road pavement index is available")
	var lamps: Array = traffic.street_details.lamp_anchors.duplicate()
	lamps.append_array(level.dressing_report.get("lamp_anchors", []))
	lamps.append_array(traffic.signals.heads)
	var all_fixtures: Array = lamps.duplicate()
	all_fixtures.append_array(traffic.street_details.stop_anchors.values())
	var sidewalks_clear := true
	var roads_clear := true
	var supported := true
	var worst_base_gap := 0.0
	for fixture in all_fixtures:
		var at: Vector3 = fixture.position
		var radius: float = float(fixture.radius)
		sidewalks_clear = sidewalks_clear and Surfaces.circle_clear("sidewalk", at, radius + 0.04)
		for i in 13:
			var angle := float(i) * TAU / 12.0
			var sample := at + (Vector3.ZERO if i == 12 else Vector3(cos(angle), 0, sin(angle)) * radius)
			roads_clear = roads_clear and not Surfaces.contains("road", sample)
			var ground: Dictionary = level.ground_at(sample)
			supported = supported and not ground.is_empty()
			if not ground.is_empty():
				var gap: float = float(ground.position.y) - at.y
				worst_base_gap = maxf(worst_base_gap, absf(gap))
				supported = supported and gap >= -0.004 and gap < 0.08 and ground.normal.y >= 0.90
	check(lamps.size() >= 12 and sidewalks_clear, "every lamp/signal/stop base stays wholly on actual source sidewalks")
	check(roads_clear, "no street fixture base footprint enters any road, including crossing roads")
	check(supported, "every fixture base has continuous ground support and no floating edge (max %.3fm)" % worst_base_gap)
	var controls_match := true
	var signs_face := true
	var junctions: Dictionary = {}
	for lane in traffic.network.lanes:
		if not bool(lane.enabled) or not bool(lane.stop):
			continue
		controls_match = controls_match and traffic.street_details.stop_anchors.has(str(lane.id)) and not bool(traffic.network.nodes[lane.to].signal)
	for anchor in traffic.street_details.stop_anchors.values():
		var lane: Dictionary = traffic.network.lanes[int(anchor.lane)]
		var incoming: Vector3 = anchor.incoming
		var right := incoming.cross(Vector3.UP)
		signs_face = signs_face and anchor.normal.dot(incoming) < -0.99 and (anchor.position - lane.points[-1]).dot(right) > 0.0
		controls_match = controls_match and bool(lane.stop) and bool(lane.enabled)
		junctions[str(anchor.junction)] = true
	check(controls_match and junctions.size() >= 8, "physical stop signs match actual controlled lanes across at least eight unlit junctions")
	check(signs_face, "stop signs stand on each incoming driver's right and face that approach")
	# The reported Old York/39th roadway remains an invalid lamp location.
	var diagnostic: Dictionary = {}
	var bad := CityDressing.fixture_position(level, Vector3(-1.556, -2.673, 114.102), 0.28, 5.0, diagnostic)
	check(bad.is_empty() and diagnostic.get("reason") == "outside_sidewalk_footprint", "Old York/39th intersection pavement cannot accept a streetlamp")
	var details: Node3D = level.neighborhood_details
	var crossing_status: Dictionary = details.get_status()
	check(int(crossing_status.crossings) >= 18, "supported pedestrian crossings at least double the previous nine")
	var landing_clear := true
	var stripes_clear := true
	var expected_stripes := 0
	var crossing_streets: Dictionary = {}
	for crossing in details._crossing_details:
		landing_clear = landing_clear and Surfaces.circle_clear("sidewalk", crossing.landing_a, 0.32) and Surfaces.circle_clear("sidewalk", crossing.landing_b, 0.32)
		expected_stripes += int(crossing.stripes)
		crossing_streets[str(crossing.street)] = true
	for record in details.records:
		if record.kind != "crosswalk_stripe":
			continue
		for x in [-0.5, 0.0, 0.5]:
			for z in [-0.5, 0.0, 0.5]:
				stripes_clear = stripes_clear and Surfaces.contains("road", record.position + record.basis.x * float(x) + record.basis.z * float(z))
	check(landing_clear and crossing_streets.size() >= 8, "crosswalks connect supported sidewalks across at least eight streets")
	check(stripes_clear and expected_stripes == int(crossing_status.counts.get("crosswalk_stripe", 0)), "every complete crossing stripe footprint stays on actual asphalt")
	var directory := ProjectSettings.globalize_path("res://../artifacts/streets-pass")
	DirAccess.make_dir_recursive_absolute(directory)
	var report := FileAccess.open(directory.path_join("fixture-audit.json"), FileAccess.WRITE)
	if report:
		report.store_string(JSON.stringify({"lamps_and_signals": lamps, "stops": traffic.street_details.stop_anchors,
			"crossings": details._crossing_details, "sidewalks_clear": sidewalks_clear, "roads_clear": roads_clear,
			"supported": supported, "controls_match": controls_match, "signs_face_approach": signs_face,
			"landings_clear": landing_clear, "stripes_clear": stripes_clear}, "\t"))

func _check_stop_control(traffic: Node3D, car: Node3D) -> void:
	var selected: Dictionary = {}
	for lane in traffic.network.lanes:
		if bool(lane.enabled) and bool(lane.stop) and not bool(traffic.network.nodes[lane.to].signal):
			selected = lane
			break
	check(not selected.is_empty(), "a signed unlit approach is available for controller regression")
	if selected.is_empty():
		return
	var fleet: Array[Node3D] = traffic.vehicles.duplicate()
	var saved_reservations: Dictionary = traffic.reservations.duplicate()
	var isolated: Array[Node3D] = [car]
	traffic.vehicles = isolated
	traffic.reservations.clear()
	var path: Array[Vector3] = selected.points
	var approach: Array[Vector3] = [path[-2], path[-1]]
	car.route = approach
	car.route_index = 1
	var incoming := path[-1] - path[-2]
	car.yaw = atan2(incoming.x, incoming.z)
	car.global_transform = Transform3D(Basis(Vector3.UP, car.yaw), path[-1])
	car.lane_id = int(selected.id)
	car.next_lane_id = -1
	car.reservation_id = ""
	car.connector_end_index = -1
	car.stop_dwell = 0.0
	car.route_sequence = 1
	car.speed = 0.0
	car.leader_distance = INF
	var held := true
	for i in 7:
		held = held and traffic.control_distance(car, 0.1) < 0.01 and car.reservation_id.is_empty()
	check(held and car.stop_dwell >= 0.69, "new stop controls require a stationary dwell and prevent early reservations")
	var completed_dwell: float = car.stop_dwell
	for i in 5:
		completed_dwell = maxf(completed_dwell, car.stop_dwell)
		traffic.control_distance(car, 0.1)
		completed_dwell = maxf(completed_dwell, car.stop_dwell)
		if not car.reservation_id.is_empty():
			break
	# Successful transfer resets stop_dwell for the NEXT junction. Measure the
	# completed approach's dwell before that reset, and require a real transfer.
	check(completed_dwell >= 0.79 and not car.reservation_id.is_empty() and car.route_sequence > 1 and car.route.size() > 2,
		"stopped traffic receives a supported outgoing route after the full dwell")
	traffic.release_reservation(car)
	traffic.vehicles = fleet
	traffic.reservations = saved_reservations
	stop_control_verified = true

func _capture_fixtures(level: Node, traffic: Node3D) -> void:
	if DisplayServer.get_name() == "headless":
		print("[city_street] SKIP fixture PNG capture on dummy renderer")
		return
	var directory := ProjectSettings.globalize_path("res://../artifacts/streets-pass/fixtures")
	DirAccess.make_dir_recursive_absolute(directory)
	var points: Array[Dictionary] = [{"name": "old-york-39th", "at": Vector3(-1.556, -2.673, 114.102)},
		{"name": "old-york-wyanoke", "at": Vector3.ZERO}]
	if not traffic.street_details.stop_anchors.is_empty():
		points.append({"name": "unlit-stop-approach", "at": traffic.street_details.stop_anchors.values()[-1].position})
	for entry in points:
		var view := SubViewport.new()
		view.size = Vector2i(960, 640)
		view.world_3d = level.get_world_3d()
		view.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(view)
		var camera := Camera3D.new()
		view.add_child(camera)
		camera.current = true
		camera.position = entry.at + Vector3(12, 13, 15)
		camera.look_at(entry.at, Vector3.UP)
		await frames(3)
		var result := view.get_texture().get_image().save_png(directory.path_join(str(entry.name) + ".png"))
		check(result == OK, "offscreen fixture capture: " + str(entry.name))
		view.queue_free()
		await frames(1)

func _finish() -> void:
	print("[city_street] %d passed, %d failed" % [passes, fails])
	get_tree().quit(0 if fails == 0 else 1)
