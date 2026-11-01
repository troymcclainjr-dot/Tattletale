extends "res://tests/city_priorities_session_fixture.gd"
## Actual imported city, normal root physics, full population and traffic.
## API arrangement/override are explicit (pose, start speed, controls): this is
## a geometry and collision test, not an input test. Curb sites come from a
## bounded live collision search along several real roads; every crossing's
## corridor (braking included) is swept clear first. A live pedestrian or car
## stepping in afterwards marks that crossing "interrupted": reported, never a
## pass. The crash is a real ride into a real parked car's live collider.
const Bike := preload("res://scripts/city/city_bicycle.gd")
const ARGONNE := Vector3(439.0, -6.8, -75.0)
const ROADS := ["Argonne Drive", "Old York Road", "Ellerslie Avenue", "Greenmount Avenue",
	"Wilsby Avenue", "Pen Lucy Avenue", "Frisby Street", "Cator Avenue"]
const MAX_SITES := 4
## [label, degrees from the curb normal, speed m/s, road -> raised side]
const CITY_MATRIX := [
	["head-on up slow", 0.0, 1.2, true],
	["head-on up", 0.0, 3.15, true],
	["45 deg up slow", 45.0, 1.2, true],
	["70 deg up fast", 70.0, 9.0, true],
	["head-on down fast", 0.0, 9.0, false],
	["45 deg down slow", 45.0, 1.2, false],
	["70 deg down sprint", 70.0, 12.0, false],
]
const SIMULATION_BUDGET := 9000
var bicycle: CharacterBody3D
var _ray_count := 0
var _ride_frames := 0
var _penetrations: Array[Dictionary] = []
var _ride_trace: Array[Dictionary] = []
var _crossings: Array[Dictionary] = []
var _impact_log: Array[Dictionary] = []
var _crash_audit: Dictionary = {}

func _run() -> void:
	if not await boot_world():
		_finish()
		return
	# Keep the inherited private provider, but direct this fixture's artifacts
	# and future private autosaves into the requested project scratch directory.
	output_dir = ProjectSettings.globalize_path("res://../.work/pacifist-foundation/bike-city-session/" + run_id)
	DirAccess.make_dir_recursive_absolute(output_dir)
	fixture = output_dir.path_join("checkpoint.json")
	provider.path = fixture
	result_details["scope"] = "API-arranged bicycle poses and start speeds; live imported curbs on several real roads, root tick, authored traffic and full population; a real parked-car crash. No disabled colliders or added AI."
	bicycle = level.bicycle
	check(bicycle != null and bicycle.spawned, "production bicycle exists")
	if bicycle == null or not bicycle.spawned:
		_finish()
		return
	bicycle.impact.connect(func(event: Dictionary): _impact_log.append(event))
	player.phone.close()
	level.basketball.suspend(true)
	level.resume_exploring()
	begin_phase("find-actual-curbs")
	var sites: Array[Dictionary] = await _find_curbs()
	result_details["curb_search_rays"] = _ray_count
	result_details["curb_sites"] = sites
	check(sites.size() >= 3, "bounded live collision search finds at least 3 distinct real curb sites (%d)" % sites.size())
	if sites.is_empty():
		_finish()
		return
	for site in sites:
		print("[bicycle_city] SELECTED_CURB ", JSON.stringify(site))
	await _cross_curb(sites[0], false)
	await _cross_curb(sites[0], true)
	for site in sites:
		for spec in CITY_MATRIX:
			await _cross_city(site, spec)
	_coverage()
	await _road_motion(sites[0])
	await _parked_car_crash(sites)
	result_details["crossings"] = _crossings
	result_details["ride_trace"] = _ride_trace
	result_details["penetrations"] = _penetrations
	result_details["simulation_frames"] = _ride_frames
	result_details["crash"] = _crash_audit
	check(_ride_frames <= SIMULATION_BUDGET, "riding validation stays within %d simulated frames (%d)" % [SIMULATION_BUDGET, _ride_frames])
	check(level.is_physics_processing() and player.is_physics_processing() and level.traffic.vehicles.size() == 90 \
		and int(level.npcs.crowd.get_status().total) == 1200, "normal physics, 90 traffic vehicles and 1200 ambient residents retained")
	check(_penetrations.is_empty(), "bike never penetrates a wall or car during measured rides")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and _window_off_desktop(), "validation leaves desktop pointer visible and window offscreen")
	bicycle.clear_control_override()
	_finish()

# ------------------------------------------------------------------ live queries

## First walkable surface under `from`..`to`; cars and people never count.
func _support_hit(from: Vector3, to: Vector3) -> Dictionary:
	_ray_count += 1
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 2)
	var excluded: Array[RID] = [player.get_rid(), bicycle.get_rid()]
	query.exclude = excluded
	query.hit_back_faces = false
	var space := level.get_world_3d().direct_space_state
	for attempt in 3:
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return {}
		var body := hit.get("collider") as CollisionObject3D
		if body != null and (body.collision_layer & (8 | 16)) != 0:
			excluded.append(hit.rid)
			query.exclude = excluded
			continue
		return hit
	return {}

func _surface(at: Vector3) -> Dictionary:
	var hit := _support_hit(at + Vector3.UP * 2.0, at + Vector3.DOWN * 3.0)
	return hit if not hit.is_empty() and hit.normal.y > 0.72 else {}

## Metres the real surface under either axle sits above the bike's foot.
func _axle_sink() -> float:
	var worst := 0.0
	var forward := Vector3(sin(bicycle.yaw), 0.0, cos(bicycle.yaw))
	for axle in [Bike.REAR_AXLE, Bike.FRONT_AXLE]:
		var at: Vector3 = bicycle.global_position + forward * float(axle)
		var hit := _support_hit(at + Vector3.UP * (Bike.STEP_HEIGHT + 0.04), at + Vector3.DOWN * 0.5)
		if not hit.is_empty():
			worst = maxf(worst, float(hit.position.y) - bicycle.global_position.y)
	return worst

func _obstacle_clear(pose: Transform3D, mask := 2 | 16, contact_tolerance := true) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = mask
	query.exclude = [player.get_rid(), bicycle.get_rid()]
	for collider in bicycle._colliders:
		var shape := (collider.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
		if contact_tolerance:
			shape.radius -= 0.025
			shape.height -= 0.05
		query.shape = shape
		query.transform = pose * collider.transform
		var hits := level.get_world_3d().direct_space_state.intersect_shape(query, 4)
		if not hits.is_empty():
			if contact_tolerance and _penetrations.size() < 8:
				_penetrations.append({"frame": _ride_frames, "position": pose.origin, "collider": str(hits[0].collider.get_path())})
			return false
	return true

# ------------------------------------------------------------------ curb search

## Up to three long segments of a road: the one nearest the original Argonne
## fixture point first, then the road's first and last long segments.
func _segments(road_name: String) -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	for road in level.level_data.get("roads", []):
		if str(road.get("name", "")) != road_name:
			continue
		var points: Array = road.get("points", [])
		for i in maxi(0, points.size() - 1):
			var a := point(points[i])
			var b := point(points[i + 1])
			var delta := b - a
			delta.y = 0.0
			if delta.length() < 8.0:
				continue
			all.append({"name": road_name, "center": a.lerp(b, 0.5), "tangent": delta.normalized(),
				"width": float(road.get("width", 10.0)), "length": delta.length()})
	var chosen: Array[Dictionary] = []
	if all.is_empty():
		return chosen
	var nearest := 0
	for i in all.size():
		if flat_distance(Vector3(all[i].center), ARGONNE) < flat_distance(Vector3(all[nearest].center), ARGONNE):
			nearest = i
	var used: Array[int] = []
	for index in [nearest, 0, all.size() - 1]:
		if not used.has(int(index)):
			used.append(int(index))
			chosen.append(all[int(index)])
	return chosen

## Bounded live search: at most 8 roads x 3 segments x 5 stations x 2 sides x
## 25 rays, plus corridor checks. No population scan, no collision mutation.
func _find_curbs() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for road_name in ROADS:
		if found.size() >= MAX_SITES:
			break
		for segment in _segments(str(road_name)):
			_set_scenario_position(Vector3(segment.center) + Vector3.UP)
			await frames(6) # Stream local collision, presence and traffic first.
			var site := _curb_near(segment)
			if site.is_empty():
				continue
			var distinct := true
			for other in found:
				distinct = distinct and flat_distance(Vector3(other.edge), Vector3(site.edge)) >= 25.0
			if distinct:
				found.append(site)
				break
	return found

func _curb_near(segment: Dictionary) -> Dictionary:
	var tangent: Vector3 = segment.tangent
	for shift in [0.0, 6.0, -6.0, 12.0, -12.0]:
		if absf(float(shift)) > float(segment.length) * 0.5:
			continue
		var station: Vector3 = Vector3(segment.center) + tangent * float(shift)
		for side in [-1.0, 1.0]:
			var outward := Vector3(tangent.z, 0.0, -tangent.x) * float(side)
			var site := _site_at(str(segment.name), station, outward, tangent, float(segment.width))
			if not site.is_empty() and _path_clear(_approach(site, 0.0, true, 3.15)):
				return site
	return {}

## Where a 0.065-0.29 m riser crosses the line from the road centre outward.
func _site_at(road_name: String, station: Vector3, outward: Vector3, tangent: Vector3, width: float) -> Dictionary:
	var previous := {}
	for sample in 25:
		var offset := width * 0.5 - 1.3 + float(sample) * 0.16
		var hit := _surface(station + outward * offset)
		if not hit.is_empty() and not previous.is_empty():
			var rise := float(hit.position.y) - float(previous.position.y)
			if rise >= 0.065 and rise <= 0.29:
				var edge: Vector3 = (Vector3(hit.position) + Vector3(previous.position)) * 0.5
				var road := _surface(edge - outward * 2.4)
				var raised := _surface(edge + outward * 1.15)
				if not road.is_empty() and not raised.is_empty():
					return {"road": road_name, "edge": edge, "normal": outward, "tangent": tangent,
						"road_position": road.position, "sidewalk_position": raised.position, "rise": rise,
						"station": station, "width": width}
		previous = hit
	return {}

## The same curb re-detected `shift` metres along it (curbs bend, driveways cut).
func _shifted_site(site: Dictionary, shift: float) -> Dictionary:
	if is_zero_approx(shift):
		return site
	var tangent: Vector3 = site.tangent
	return _site_at(str(site.road), Vector3(site.station) + tangent * shift, Vector3(site.normal), tangent, float(site.width))

## A straight crossing through the edge at `angle_deg` from the curb normal,
## with room beyond it to brake to a stop.
func _approach(site: Dictionary, angle_deg: float, upward: bool, speed: float) -> Dictionary:
	var theta := deg_to_rad(angle_deg)
	var normal: Vector3 = site.normal
	var tangent: Vector3 = site.tangent
	var side := 1.0 if upward else -1.0
	var direction := (normal * side * cos(theta) + tangent * sin(theta)).normalized()
	var reach := 0.95 * cos(theta) + 0.3 * sin(theta)
	var lead := (0.9 + reach) / maxf(cos(theta), 0.2)
	var run := (1.0 + reach) / maxf(cos(theta), 0.2) + speed * speed / (2.0 * Bike.BRAKING) + 0.8
	var edge: Vector3 = site.edge
	return {"start": edge - direction * lead, "end": edge + direction * run, "direction": direction,
		"yaw": atan2(direction.x, direction.z), "finish": 1.0 + reach, "side": side, "edge": edge, "normal": normal}

## The whole corridor, braking included, is free right now of walls, posts,
## parked or moving cars and people, and its ground never jumps past a step.
func _path_clear(path: Dictionary) -> bool:
	if path.is_empty():
		return false
	var start: Vector3 = path.start
	var end: Vector3 = path.end
	var heading := float(path.yaw)
	var samples := maxi(2, ceili(flat_distance(start, end) / 0.5))
	var previous_y := INF
	var highest := -INF
	for i in samples + 1:
		var at := start.lerp(end, float(i) / float(samples))
		var ground := _surface(at)
		if ground.is_empty():
			return false
		var y := float(ground.position.y)
		if is_finite(previous_y) and absf(y - previous_y) > 0.29:
			return false
		previous_y = y
		highest = maxf(highest, y)
		if not _obstacle_clear(Transform3D(Basis(Vector3.UP, heading), Vector3(at.x, y + 0.02, at.z)), 2 | 8 | 16, false):
			return false
	# One raised-hull sweep over the corridor catches anything between samples.
	var motion := end - start
	motion.y = 0.0
	return not bicycle.test_move(Transform3D(Basis(Vector3.UP, heading), Vector3(start.x, highest + 0.02, start.z)), motion)

# ------------------------------------------------------------------ riding

func _arrange(at: Vector3, heading: float) -> bool:
	if bicycle.active:
		# Only between scenarios; never used to turn a failed crossing into a pass.
		bicycle.recovery_exit_at(player.global_position, heading)
	player.phone.close()
	level.basketball.suspend(true)
	level.resume_exploring()
	var ground := _surface(at)
	if ground.is_empty():
		return false
	bicycle.global_position = ground.position + Vector3.UP * 0.045
	bicycle.yaw = heading
	bicycle.rotation.y = heading
	bicycle.reset_motion_state()
	bicycle.velocity = Vector3.ZERO
	bicycle.speed = 0.0
	bicycle.set_control_override(Vector2.ZERO, true)
	_set_scenario_position(bicycle.global_position)
	await frames(4) # Stream local collision before the API mount.
	if not _obstacle_clear(bicycle.global_transform, 2 | 8 | 16, false):
		return false
	player.camera_yaw = heading + 0.6
	var mounted: bool = bicycle.enter_bicycle()
	await _observe(8)
	return mounted and bicycle.active

func _observe(count: int) -> void:
	for i in count:
		await frames(1)
		_ride_frames += 1
		_obstacle_clear(bicycle.global_transform)
		if _ride_frames % 12 == 0:
			_ride_trace.append({"frame": _ride_frames, "phase": phase_name, "position": bicycle.global_position,
				"speed": bicycle.speed, "step_reason": bicycle.debug_step_reason, "hops": bicycle.hops_started})

## The original head-on and 31 degree crossings of the first site, unchanged.
func _legacy_approach(curb: Dictionary, diagonal: bool) -> Dictionary:
	var tangent: Vector3 = curb.tangent
	var outward: Vector3 = curb.normal
	var edge: Vector3 = curb.edge
	var start := edge - outward * 2.4 - tangent * (1.45 if diagonal else 0.0)
	var end := edge + outward * 1.15 + tangent * (0.68 if diagonal else 0.0)
	var direction := end - start
	direction.y = 0.0
	return {"start": start, "end": end, "direction": direction.normalized(), "yaw": atan2(direction.x, direction.z)}

func _cross_curb(curb: Dictionary, diagonal: bool) -> void:
	begin_phase("city-curb-diagonal" if diagonal else "city-curb-head-on")
	var approach := _legacy_approach(curb, diagonal)
	if not _path_clear(approach):
		print("[bicycle_city] SKIP legacy ", phase_name, ": corridor obstructed right now")
		_crossings.append({"label": "legacy " + phase_name, "result": "corridor obstructed"})
		return
	check(await _arrange(approach.start, float(approach.yaw)), "API fixture arrangement mounts at checked real road position")
	if not bicycle.active:
		return
	var start := bicycle.global_position
	var steps_before: int = bicycle.steps_climbed
	var crossed := false
	bicycle.set_control_override(Vector2(0.0, 0.35))
	for frame in 210:
		await _observe(1)
		if not bicycle.active or not _penetrations.is_empty():
			break
		if (bicycle.global_position - Vector3(curb.edge)).dot(curb.normal) >= 0.95:
			crossed = true
			break
	bicycle.set_control_override(Vector2.ZERO, true)
	await _observe(24)
	var support := _surface(bicycle.global_position)
	var result := {"start": start, "end": bicycle.global_position, "crossed": crossed,
		"steps": bicycle.steps_climbed - steps_before, "reason": bicycle.debug_step_reason, "support": support.get("position", Vector3.INF)}
	result_details[phase_name] = result
	print("[bicycle_city] CROSSING ", JSON.stringify(result))
	check(crossed, "ride crosses imported raised curb without resetting pose or removing obstacles")
	check(not support.is_empty() and absf(bicycle.global_position.y + Bike.HULL_FOOT_OFFSET - float(support.position.y)) < 0.15,
		"bicycle settles on actual sidewalk support after crossing")
	check(bicycle.global_position.distance_to(start) > 2.8 and absf(bicycle.speed) < 0.1, "riding makes real progress and brakes on sidewalk")
	await _capture(phase_name)

func _cross_city(site: Dictionary, spec: Array) -> void:
	var label := "%s / %s" % [str(site.road), str(spec[0])]
	begin_phase("city-curb " + label)
	var angle := float(spec[1])
	var speed := float(spec[2])
	var upward := bool(spec[3])
	var row := {"label": label, "road": site.road, "rise": site.rise, "angle": angle, "speed": speed, "upward": upward}
	var path := {}
	for shift in [0.0, 7.0, -7.0, 14.0, -14.0]:
		var shifted := _shifted_site(site, float(shift))
		if shifted.is_empty():
			continue
		var candidate := _approach(shifted, angle, upward, speed)
		if _path_clear(candidate):
			path = candidate
			row["shift"] = shift
			row["rise"] = shifted.rise
			break
	if path.is_empty():
		row["result"] = "corridor obstructed"
		_crossings.append(row)
		print("[bicycle_city] SKIP ", label, ": every candidate corridor is obstructed")
		return
	if not await _arrange(Vector3(path.start), float(path.yaw)):
		row["result"] = "arrangement failed"
		_crossings.append(row)
		check(false, label + ": API arrangement mounts on a checked corridor")
		return
	bicycle.speed = speed
	bicycle.set_control_override(Vector2(0.0, minf(1.0, speed / Bike.MAX_SPEED)), false, speed > Bike.MAX_SPEED)
	var impacts_before := _impact_log.size()
	var contacts_before: int = bicycle.contacts
	var crashes_before: int = bicycle.crashes
	var penetrations_before := _penetrations.size()
	var edge: Vector3 = path.edge
	var normal: Vector3 = path.normal
	var side := float(path.side)
	var finish := float(path.finish)
	var limit := int(ceil((flat_distance(Vector3(path.start), edge) + finish / maxf(cos(deg_to_rad(angle)), 0.2)) / speed * 60.0)) + 120
	var crossed := false
	var crossed_speed := 0.0
	var max_rise := 0.0
	var sink := 0.0
	for frame in limit:
		var before_y: float = bicycle.global_position.y
		await _observe(1)
		max_rise = maxf(max_rise, bicycle.global_position.y - before_y)
		sink = maxf(sink, _axle_sink())
		if not bicycle.active or bicycle.is_crashed():
			break
		if (bicycle.global_position - edge).dot(normal) * side >= finish:
			crossed = true
			crossed_speed = absf(bicycle.speed)
			break
	bicycle.set_control_override(Vector2.ZERO, true)
	await _observe(int(speed * 6.0) + 20)
	var support := _surface(bicycle.global_position)
	var interrupted := ""
	var solid_impacts := 0
	if bicycle.contacts > contacts_before:
		interrupted = "pedestrian stepped into the corridor"
	for i in range(impacts_before, _impact_log.size()):
		var kind := str(_impact_log[i].get("kind", ""))
		if kind == "vehicle" or kind == "parked_vehicle":
			interrupted = "vehicle entered the corridor"
		else:
			solid_impacts += 1
	row["crossed"] = crossed
	row["crossed_speed"] = crossed_speed
	row["max_rise"] = max_rise
	row["sink"] = sink
	row["end"] = bicycle.global_position
	row["reason"] = bicycle.debug_step_reason
	row["result"] = "interrupted" if not interrupted.is_empty() and solid_impacts == 0 else ("crossed" if crossed else "not crossed")
	_crossings.append(row)
	print("[bicycle_city] CROSSING ", JSON.stringify(row))
	if row.result == "interrupted":
		print("[bicycle_city] INTERRUPTED ", label, ": ", interrupted)
		return # Live traffic or a pedestrian stepped in: reported, never a pass.
	check(crossed, label + ": rides across the real curb")
	check(solid_impacts == 0 and bicycle.crashes == crashes_before, label + ": a climbable real curb is never an impact or crash")
	check(max_rise <= Bike.STEP_HEIGHT + 0.01 and sink <= 0.015, "%s: bounded rise (%.3f m) and no tyre inside a surface (%.3f m)" % [label, max_rise, sink])
	check(_penetrations.size() == penetrations_before, label + ": hull never penetrates walls or cars")
	check(not support.is_empty() and absf(bicycle.global_position.y - float(support.position.y)) < 0.08, label + ": settles on real support")
	if speed >= 9.0 and upward:
		check(crossed_speed >= speed * 0.75, "%s: keeps riding speed over the curb (%.2f)" % [label, crossed_speed])

func _coverage() -> void:
	begin_phase("city-curb-coverage")
	var executed := 0
	var shallow := 0
	var fast := 0
	var downward := 0
	var obstructed := 0
	var interrupted := 0
	var rises: Array[float] = []
	for row in _crossings:
		var result := str(row.get("result", ""))
		if result == "corridor obstructed":
			obstructed += 1
		elif result == "interrupted":
			interrupted += 1
		elif row.has("angle"):
			executed += 1
			shallow += int(float(row.angle) >= 45.0)
			fast += int(float(row.speed) >= 9.0)
			downward += int(not bool(row.upward))
			rises.append(snappedf(float(row.rise), 0.01))
	result_details["coverage"] = {"executed": executed, "shallow": shallow, "fast": fast, "downward": downward,
		"obstructed": obstructed, "interrupted": interrupted, "rises": rises}
	print("[bicycle_city] COVERAGE ", JSON.stringify(result_details.coverage))
	check(executed >= 12 and shallow >= 4 and fast >= 3 and downward >= 3,
		"representative real-curb coverage: %d crossings (%d at >=45 deg, %d at >=9 m/s, %d downward; %d obstructed, %d interrupted)" % [executed, shallow, fast, downward, obstructed, interrupted])

func _road_motion(curb: Dictionary) -> void:
	begin_phase("city-road-hop-sprint-and-priority")
	var tangent: Vector3 = curb.tangent
	var start: Vector3 = curb.road_position - Vector3(curb.normal) * 1.3
	# Select one supported 27m road corridor before riding. Incoming traffic
	# remains live after selection; a later obstruction fails the speed check.
	var direction := Vector3.ZERO
	for sign_value in [1.0, -1.0]:
		var candidate := tangent * float(sign_value)
		var clear := true
		for i in 19:
			var ground := _surface(start + candidate * float(i) * 1.5)
			if ground.is_empty() or not _obstacle_clear(Transform3D(Basis(Vector3.UP, atan2(candidate.x, candidate.z)), ground.position + Vector3.UP * 0.045), 2 | 8 | 16, false):
				clear = false
				break
		if clear:
			direction = candidate
			break
	check(direction.length() > 0.9, "bounded road corridor selection finds live clear sprint lane")
	if direction.length() < 0.9:
		return
	check(await _arrange(start, atan2(direction.x, direction.z)), "API fixture mounts on actual road for moving hop and sprint")
	if not bicycle.active:
		return
	check(not player.phone.open() and not player.phone.active, "phone cannot steal controls while bicycle is mounted")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	check(not level.basketball.handle_input(mouse) and not bool(level.basketball.get_status().charging), "basketball cannot charge while bicycle is mounted")
	level.pause_exploring()
	var paused_at := bicycle.global_transform
	bicycle.set_control_override(Vector2(0.0, 1.0), false, true, true)
	await frames(5)
	check(bicycle.global_transform.is_equal_approx(paused_at), "pause takes priority over pedal and hop override")
	level.resume_exploring()
	bicycle.set_control_override(Vector2(0.0, 0.45))
	await _observe(25)
	var hop_start := bicycle.global_position
	var hops: int = bicycle.hops_started
	var clearance := 0.0
	bicycle.set_control_override(Vector2(0.0, 0.45), false, false, true)
	for frame in 60:
		await _observe(1)
		var ground := _surface(bicycle.global_position)
		if not ground.is_empty():
			clearance = maxf(clearance, bicycle.global_position.y - float(ground.position.y))
	check(bicycle.hops_started == hops + 1 and clearance > 0.45 and not bicycle._hop_active,
		"moving hop clears real road and lands once while Space remains held")
	check(flat_distance(hop_start, bicycle.global_position) > 1.0, "hop preserves forward riding motion")
	var sprint_start := bicycle.global_position
	bicycle.set_control_override(Vector2(0.0, 1.0), false, true)
	var maximum_speed := 0.0
	for frame in 115:
		await _observe(1)
		maximum_speed = maxf(maximum_speed, bicycle.speed)
	bicycle.set_control_override(Vector2.ZERO, true)
	await _observe(65)
	result_details["road_motion"] = {"start": start, "direction": direction, "end": bicycle.global_position,
		"hop_clearance": clearance, "maximum_speed": maximum_speed, "sprint_distance": flat_distance(sprint_start, bicycle.global_position)}
	check(maximum_speed > Bike.MAX_SPEED + 0.5 and maximum_speed <= Bike.SPRINT_SPEED + 0.01, "hard pedalling exceeds ordinary speed without exceeding sprint cap on actual road")
	check(flat_distance(sprint_start, bicycle.global_position) > 8.0 and absf(bicycle.speed) < 0.1, "sprint travels across actual road and brakes to stop")
	await _capture("city-road-motion")

# ------------------------------------------------------------------ real crash

## A real parked car with a clear 7 m run-up, near the sites already streamed.
func _parked_target(sites: Array[Dictionary]) -> Dictionary:
	var parked = level.traffic.get("parked")
	if parked == null or not parked.has_method("records_near"):
		return {}
	for site in sites:
		var center: Vector3 = site.road_position
		_set_scenario_position(center + Vector3.UP)
		parked.set_presence(center, 55.0, 180.0)
		await frames(8)
		var near: Array = parked.records_near(center, 45.0)
		for i in mini(near.size(), 12):
			var index := int(near[i])
			var record: Dictionary = parked.records[index]
			var body := record.get("body") as StaticBody3D
			if body == null or (body.collision_layer & 16) == 0:
				continue
			var pose: Transform3D = record.pose
			var axis := Vector3(pose.basis.z.x, 0.0, pose.basis.z.z).normalized()
			for direction in [axis, -axis]:
				var face: Vector3 = pose.origin - Vector3(direction) * 2.35
				var start: Vector3 = face - Vector3(direction) * 7.0
				var path := {"start": start, "end": face - Vector3(direction) * 0.95, "yaw": atan2(direction.x, direction.z)}
				if _path_clear(path):
					return {"index": index, "body": body, "start": start, "yaw": float(path.yaw), "car": pose.origin}
	return {}

func _parked_car_crash(sites: Array[Dictionary]) -> void:
	begin_phase("city-parked-car-crash")
	var target: Dictionary = await _parked_target(sites)
	check(not target.is_empty(), "bounded search finds a real parked car with a clear 7 m run-up")
	if target.is_empty():
		return
	if not await _arrange(Vector3(target.start), float(target.yaw)):
		check(false, "API arrangement mounts behind the parked car")
		return
	var ejected: Array[Dictionary] = []
	var recovered: Array[Dictionary] = []
	var on_eject := func(event: Dictionary): ejected.append(event)
	var on_recover := func(event: Dictionary): recovered.append(event)
	bicycle.rider_ejected.connect(on_eject)
	bicycle.rider_recovered.connect(on_recover)
	bicycle.speed = 9.0
	bicycle.set_control_override(Vector2(0.0, 1.0))
	for frame in 90:
		await _observe(1)
		if bicycle.is_crashed():
			break
	var crash = bicycle.get("_crash")
	check(bicycle.is_crashed() and ejected.size() == 1, "9 m/s into a real parked car ejects the rider")
	if not bicycle.is_crashed():
		bicycle.rider_ejected.disconnect(on_eject)
		bicycle.rider_recovered.disconnect(on_recover)
		return
	var impact: Dictionary = ejected[0].impact
	check(str(impact.kind) == "parked_vehicle" and impact.collider == target.body and bool(impact.harmless), "crash names the real parked car (%s)" % str(impact.kind))
	check(player.is_seated() and provider.checkpoint_blocker() == "recovering from a bicycle crash", "real checkpoint provider refuses saves mid-crash (%s)" % provider.checkpoint_blocker())
	var rider_overlaps := 0
	var camera_inside := 0
	var anchor_air := 0.0
	var frames_crashed := 0
	for frame in int(Bike.MAX_CRASH_TIME * 60.0) + 90:
		if not bicycle.is_crashed():
			break
		await _observe(1)
		frames_crashed += 1
		if bicycle.is_crashed():
			if not _sphere_clear(crash.center, 0.25, [crash.get_rid(), crash.rider_rid()]):
				rider_overlaps += 1
			if not _sphere_clear(player.camera.global_position, 0.06, []):
				camera_inside += 1
			var ground := _surface(player.global_position)
			if not ground.is_empty():
				anchor_air = maxf(anchor_air, absf(player.global_position.y - float(ground.position.y)))
	bicycle.rider_ejected.disconnect(on_eject)
	bicycle.rider_recovered.disconnect(on_recover)
	_crash_audit = {"target": target.car, "frames": frames_crashed, "rider_overlaps": rider_overlaps,
		"camera_inside": camera_inside, "anchor_air": anchor_air, "recovery": recovered.back() if not recovered.is_empty() else {},
		"rig": crash.get_status()}
	print("[bicycle_city] CRASH ", JSON.stringify(_crash_audit))
	check(not bicycle.is_crashed() and recovered.size() == 1, "rider stands up within the bounded crash time")
	check(rider_overlaps == 0, "ejected rider sweeps never overlap the car, walls or ground (%d frames)" % rider_overlaps)
	check(camera_inside == 0, "chase camera never enters geometry during the tumble (%d frames)" % camera_inside)
	check(anchor_air <= 0.1, "explorer anchor stays on real ground during the tumble (%.3f m)" % anchor_air)
	if not recovered.is_empty():
		var stand: Vector3 = recovered.back().position
		var support := _surface(stand)
		check(not support.is_empty() and absf(stand.y - float(support.position.y)) < 0.12, "explorer stands on real ground, not a car roof (%s)" % str(stand))
	await frames(3)
	check(not player.is_seated() and _sphere_clear(player.global_position + Vector3.UP * 0.9, 0.28, [player.get_rid()]), "walking explorer is released clear of every collider")
	check(not provider.checkpoint_blocker() in ["recovering from a bicycle crash", "step off your bicycle before saving", "recovering from an impact"],
		"bicycle no longer blocks checkpoints once standing (%s)" % provider.checkpoint_blocker())
	await _capture("city-parked-car-crash")

func _sphere_clear(at: Vector3, radius: float, exclude: Array) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, at)
	query.collision_mask = 1 | 2 | 16
	var rids: Array[RID] = [bicycle.get_rid(), player.get_rid()]
	for rid in exclude:
		rids.append(rid)
	query.exclude = rids
	return level.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--capture-bicycle-city"):
		return
	check(OS.get_cmdline_user_args().has("--offscreen-validation") and _window_off_desktop(), "render capture retains offscreen validation safety")
	if not _window_off_desktop():
		return
	var right := Vector3(cos(bicycle.yaw), 0.0, -sin(bicycle.yaw))
	level.capture_view(bicycle.global_position + right * 4.4 + Vector3.UP * 2.4 - bicycle.global_basis.z * 3.0,
		bicycle.global_position + Vector3.UP * 0.8)
	await frames(3)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	check(image != null and not image.is_empty() and image.save_png(output_dir.path_join(label + ".png")) == OK, "saved actual-city bicycle review capture " + label)
	level.release_capture_view()
