extends Node3D
## Root serializes engine runs. Synthetic replicas of the city's actual curb
## collision (pen_lucy_level._add_mesh_collision: trimesh on layer 1): flat tops
## per zone joined by vertical "skirt" quads exactly as blender/city/process.py
## emits them (sidewalk +0.15, grass/yards +0.10, alley +0.02 above the road),
## plus box curbs for contrast. Faces carry both windings so the replica cannot
## silently depend on a winding assumption. Start pose and speed are API
## arranged; every metre after that is the production solver and real queries.
## Ticks run back to back inside physics-frame callbacks (static scenery only).
const Bicycle := preload("res://scripts/city/city_bicycle.gd")
const DT := 1.0 / 60.0
const ANGLES := [0.0, 25.0, 45.0, 60.0, 70.0, 78.0]
const SPEEDS := [1.2, 9.0, 12.0]

class Explorer extends CharacterBody3D:
	var enabled := true
	var yaw := 0.0
	var camera_yaw := 0.0
	var chase_distance := 6.2
	var phone: Node3D
	var seated_vehicle: Node3D
	var shakes := 0
	func is_seated() -> bool:
		return seated_vehicle != null
	func enter_vehicle(vehicle: Node3D) -> void:
		seated_vehicle = vehicle
		follow_vehicle()
	func follow_vehicle() -> void:
		if seated_vehicle != null:
			global_position = seated_vehicle.global_position
	func leave_vehicle(at: Vector3, heading: float) -> void:
		seated_vehicle = null
		global_position = at
		yaw = heading
	func vehicle_shake(_amount: float) -> void:
		shakes += 1

class Fixture extends Node3D:
	var paused := false
	var player: CharacterBody3D
	var combat: Node3D

var world: Fixture
var bike: CharacterBody3D
var errors: Array[String] = []
var checks := 0
var crossings := 0
var ejections := 0
var recoveries: Array[Dictionary] = []
var _scenery: Array[Node] = []

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors.append(message)
		push_error(message)
		print("BIKE_CURB_MATRIX FAIL ", message)

func _run() -> void:
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	world = Fixture.new()
	add_child(world)
	# A permanent parking pad well away from every scenario.
	_box(Vector3(-30.0, -0.25, -80.0), Vector3(14.0, 0.5, 14.0), 1, false)
	world.player = Explorer.new()
	world.add_child(world.player)
	world.player.position = Vector3(-30.0, 0.05, -80.0)
	await get_tree().physics_frame
	bike = Bicycle.new()
	world.add_child(bike)
	bike.setup(world)
	_check(bike.spawned and bike.enter_bicycle(), "fixture mounts actual bicycle")
	if not bike.active:
		_finish()
		return
	bike.rider_ejected.connect(func(_event: Dictionary): ejections += 1)
	bike.rider_recovered.connect(func(event: Dictionary): recoveries.append(event))
	await _matrix()
	await _mixed_strip()
	await _tall_riser()
	await _ramps()
	await _overhang()
	await _posts()
	await _steer_into_curb()
	await _reverse_climb()
	_finish()

func _finish() -> void:
	print("CITY_BICYCLE_CURB_MATRIX ", "PASS" if errors.is_empty() else "FAIL", " checks=", checks, " failures=", errors.size(), " crossings=", crossings)
	get_tree().quit(0 if errors.is_empty() else 1)

# ------------------------------------------------------------------ scenery

## Godot concave faces; both windings so tops face up and skirts face both ways.
func _quad(faces: Array[Vector3], a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for triangle in [[a, b, c], [a, c, d], [a, c, b], [a, d, c]]:
		for corner in triangle:
			faces.append(corner)

func _trimesh(faces: Array[Vector3]) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(PackedVector3Array(faces))
	shape.backface_collision = false
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	world.add_child(body)
	_scenery.append(body)
	return body

func _box(at: Vector3, size: Vector3, layer: int, scenery := true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = layer
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	world.add_child(body)
	if scenery:
		_scenery.append(body)
	return body

func _post(at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.08
	shape.height = 1.2
	collider.shape = shape
	body.add_child(collider)
	body.position = at + Vector3.UP * 0.6
	world.add_child(body)
	_scenery.append(body)
	return body

## City-style curb along X at z = 0: tops `low` (z < 0) and `high` (z > 0) with
## an optional grade along Z, joined by one vertical skirt down to min - 0.08.
func _curb_family(low: float, high: float, grade: float) -> void:
	var faces: Array[Vector3] = []
	var x0 := -45.0
	var x1 := 45.0
	_quad(faces, Vector3(x0, low - grade * 25.0, -25.0), Vector3(x1, low - grade * 25.0, -25.0), Vector3(x1, low, 0.0), Vector3(x0, low, 0.0))
	_quad(faces, Vector3(x0, high, 0.0), Vector3(x1, high, 0.0), Vector3(x1, high + grade * 25.0, 25.0), Vector3(x0, high + grade * 25.0, 25.0))
	var bottom := minf(low, high) - 0.08
	var top := maxf(low, high)
	_quad(faces, Vector3(x0, bottom, 0.0), Vector3(x1, bottom, 0.0), Vector3(x1, top, 0.0), Vector3(x0, top, 0.0))
	_trimesh(faces)

func _step_surface(low: float, high: float, grade: float) -> Callable:
	return func(z: float) -> float: return (high if z > 0.0 else low) + grade * z

func _clear_scenery() -> void:
	for node in _scenery:
		if is_instance_valid(node):
			node.queue_free()
	_scenery.clear()
	await get_tree().physics_frame
	await get_tree().physics_frame

func _settle_physics() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame

# ------------------------------------------------------------------ helpers

func _place(at: Vector3, heading: float, target: float) -> void:
	_remount(at)
	bike.global_position = at
	bike.yaw = heading
	bike.rotation.y = heading
	bike.reset_motion_state()
	bike.speed = target
	if target > Bicycle.MAX_SPEED:
		bike.set_control_override(Vector2(0.0, 1.0), false, true)
	elif target >= 0.0:
		bike.set_control_override(Vector2(0.0, target / Bicycle.MAX_SPEED))
	else:
		bike.set_control_override(Vector2(0.0, target / Bicycle.REVERSE_SPEED))
	world.player.follow_vehicle()
	bike._last_seat = world.player.global_position

## Deliberate crash scenarios end with the rider standing: put them back on.
func _remount(at: Vector3) -> void:
	if bike.is_crashed():
		bike.recovery_exit_at(at + Vector3.UP * 0.05, 0.0)
	if bike.active:
		return
	bike.global_position = at
	world.player.global_position = at + Vector3.UP * 0.05
	_check(bike.enter_bicycle(), "fixture remounts the bicycle after a deliberate crash")

## Highest raw surface (analytic replica) under any wheel/crank sample.
func _footprint_max(surface: Callable) -> float:
	var forward := Vector3(sin(bike.yaw), 0.0, cos(bike.yaw))
	var best := -INF
	for axle in [Bicycle.REAR_AXLE, Bicycle.FRONT_AXLE]:
		for offset in Bicycle.WHEEL_SAMPLES:
			var point: Vector3 = bike.global_position + forward * (float(axle) + float(offset))
			best = maxf(best, float(surface.call(point.z)))
	var crank: Vector3 = bike.global_position + forward * Bicycle.CRANK
	return maxf(best, float(surface.call(crank.z)) - Bicycle.CRANK_CLEARANCE)

## Where a correct wheel solver must rest on the analytic replica: the highest
## tyre-circle contact over every wheel sample (slopes rest on the uphill tyre).
func _expected_foot(surface: Callable) -> float:
	var forward := Vector3(sin(bike.yaw), 0.0, cos(bike.yaw))
	var best := -INF
	for axle in [Bicycle.REAR_AXLE, Bicycle.FRONT_AXLE]:
		for offset in Bicycle.WHEEL_SAMPLES:
			var x := float(offset)
			var point: Vector3 = bike.global_position + forward * (float(axle) + x)
			var lift := sqrt(Bicycle.WHEEL_RADIUS * Bicycle.WHEEL_RADIUS - x * x) - Bicycle.WHEEL_RADIUS
			best = maxf(best, float(surface.call(point.z)) + lift)
	var crank: Vector3 = bike.global_position + forward * Bicycle.CRANK
	return maxf(best, float(surface.call(crank.z)) - Bicycle.CRANK_CLEARANCE)

## How far (m) the real collision surface under either axle sits above the
## bike's foot: anything above zero is a tyre inside a curb or ramp.
func _axle_sink() -> float:
	var worst := 0.0
	var forward := Vector3(sin(bike.yaw), 0.0, cos(bike.yaw))
	for axle in [Bicycle.REAR_AXLE, Bicycle.FRONT_AXLE]:
		var at: Vector3 = bike.global_position + forward * float(axle)
		var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * (Bicycle.STEP_HEIGHT + 0.04), at + Vector3.DOWN * 0.5, 1 | 2)
		query.exclude = [bike.get_rid(), world.player.get_rid()]
		query.hit_back_faces = false
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			worst = maxf(worst, float(hit.position.y) - bike.global_position.y)
	return worst

## No overlap deeper than the solver's 1.5 cm pivot allowance (the next sweep's
## depenetration separates that); anything deeper would be tunnelling.
func _hull_ok() -> bool:
	return bike._hull_clear(bike.global_transform, 0.0, 0.02)

func _rider_clear() -> bool:
	var crash = bike.get("_crash")
	var sphere := SphereShape3D.new()
	sphere.radius = 0.25
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, crash.center)
	query.collision_mask = 1 | 2 | 16
	query.exclude = [bike.get_rid(), world.player.get_rid(), crash.get_rid(), crash.rider_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

## Runs an ejection to its end, auditing every swept rider pose.
func _finish_crash(label: String) -> Dictionary:
	var before := recoveries.size()
	var overlaps := 0
	var hull_hits := 0
	for i in int(Bicycle.MAX_CRASH_TIME / DT) + 90:
		if not bike.is_crashed():
			break
		bike.tick(DT)
		if bike.is_crashed() and not _rider_clear():
			overlaps += 1
		if not _hull_ok():
			hull_hits += 1
	_check(not bike.is_crashed() and recoveries.size() == before + 1, label + ": rider is back on their feet within the bounded crash time")
	_check(overlaps == 0, label + ": ejected rider sweeps never overlap geometry (%d frames)" % overlaps)
	_check(hull_hits == 0, label + ": riderless bicycle never overlaps geometry (%d frames)" % hull_hits)
	_check(not world.player.is_seated() and not bike.active, label + ": explorer released from the crash rig")
	for i in 120:
		bike.tick(DT) # Let the riderless bicycle finish settling.
	return recoveries.back() if recoveries.size() > before else {}

# ------------------------------------------------------------------ the matrix

## One straight crossing of the z = 0 edge at `angle_deg` from the curb normal.
func _cross(tag: String, surface: Callable, angle_deg: float, target: float, upward: bool, rise: float, x0 := -30.0) -> void:
	crossings += 1
	var theta := deg_to_rad(angle_deg)
	var side := 1.0 if upward else -1.0
	var heading := Vector3(sin(theta), 0.0, cos(theta) * side)
	var reach := 0.95 * cos(theta) + 0.3 * sin(theta)
	var start_z := -side * (0.6 + reach)
	var finish := 1.0 + reach
	_place(Vector3(x0, float(surface.call(start_z)), start_z), atan2(heading.x, heading.z), target)
	# Start exactly at the wheel-rest height (graded streets rest on the uphill tyre).
	bike.global_position.y = _expected_foot(surface)
	world.player.follow_vehicle()
	bike._last_seat = world.player.global_position
	var impacts_before: int = bike.impacts
	var crashes_before: int = bike.crashes
	var steps_before: int = bike.steps_climbed
	var yaw_before: float = bike.yaw
	var limit := int(ceil((absf(start_z) + finish) / maxf(cos(theta), 0.05) / absf(target) / DT)) + 150
	var crossed := false
	var max_rise := 0.0
	var hover := 0.0
	var sink := 0.0
	var hull_hits := 0
	var ticks := 0
	for i in limit:
		var before_y: float = bike.global_position.y
		bike.tick(DT)
		ticks += 1
		var pose: Vector3 = bike.global_position
		max_rise = maxf(max_rise, pose.y - before_y)
		hover = maxf(hover, pose.y - _footprint_max(surface))
		sink = maxf(sink, _axle_sink())
		if not _hull_ok():
			hull_hits += 1
		if pose.z * side >= finish:
			crossed = true
			break
	for i in 6:
		bike.tick(DT)
	var final: Vector3 = bike.global_position
	var expected := _expected_foot(surface)
	_check(crossed, "%s crosses within %d frames (z=%.3f reason=%s)" % [tag, limit, final.z, bike.debug_step_reason])
	_check(hull_hits == 0, "%s: raised hull never overlaps geometry (%d frames)" % [tag, hull_hits])
	_check(sink <= 0.012, "%s: no tyre sinks into a surface (%.3f m)" % [tag, sink])
	_check(hover <= 0.012, "%s: never floats above every surface under it (%.3f m)" % [tag, hover])
	_check(max_rise <= Bicycle.STEP_HEIGHT + 0.01, "%s: per-frame rise bounded (%.3f m)" % [tag, max_rise])
	_check(absf(final.y - expected) <= 0.02, "%s: settles on the far surface (y=%.3f expected %.3f)" % [tag, final.y, expected])
	_check(absf(angle_difference(yaw_before, bike.yaw)) < 0.002, "%s: a climbable riser never deflects the frame" % tag)
	_check(bike.impacts == impacts_before and bike.crashes == crashes_before and not bike.is_crashed(), "%s: a climbable riser is not an impact" % tag)
	_check(absf(bike.speed) >= absf(target) * 0.8, "%s: keeps riding speed (%.2f of %.2f)" % [tag, bike.speed, target])
	if upward and rise >= 0.05:
		_check(bike.steps_climbed > steps_before, "%s: counts a climbed step" % tag)
	print("BIKE_CURB %s crossed=%s ticks=%d y=%.3f rise=%.3f hover=%.3f sink=%.3f speed=%.2f" % [tag, crossed, ticks, final.y, max_rise, hover, sink, bike.speed])

func _matrix() -> void:
	var families := [
		{"label": "alley +0.02", "low": 0.0, "high": 0.02},
		{"label": "grass-to-sidewalk +0.05", "low": 0.10, "high": 0.15},
		{"label": "grass +0.10", "low": 0.0, "high": 0.10},
		{"label": "sidewalk +0.15", "low": 0.0, "high": 0.15},
		{"label": "tall curb +0.22", "low": 0.0, "high": 0.22},
		{"label": "near-limit +0.29", "low": 0.0, "high": 0.29},
	]
	for family in families:
		await _clear_scenery()
		var low := float(family.low)
		var high := float(family.high)
		_curb_family(low, high, 0.0)
		await _settle_physics()
		var surface := _step_surface(low, high, 0.0)
		for upward in [true, false]:
			for angle in ANGLES:
				for target in SPEEDS:
					_cross("%s %s %d deg %.1f m/s" % [family.label, "up" if upward else "down", int(angle), float(target)],
						surface, float(angle), float(target), bool(upward), high - low)
			await get_tree().physics_frame
	# Convex box curbs (props, planters, older city pieces) behave the same.
	await _clear_scenery()
	_box(Vector3(0.0, -0.25, -12.5), Vector3(90.0, 0.5, 25.0), 1)
	_box(Vector3(0.0, 0.15 - 0.25, 12.5), Vector3(90.0, 0.5, 25.0), 1)
	await _settle_physics()
	var boxed := _step_surface(0.0, 0.15, 0.0)
	for upward in [true, false]:
		for angle in ANGLES:
			for target in SPEEDS:
				_cross("box sidewalk +0.15 %s %d deg %.1f m/s" % ["up" if upward else "down", int(angle), float(target)],
					boxed, float(angle), float(target), bool(upward), 0.15)
		await get_tree().physics_frame
	# Graded streets: uphill and downhill approaches at 8 %.
	for grade in [0.08, -0.08]:
		await _clear_scenery()
		_curb_family(0.0, 0.15, float(grade))
		await _settle_physics()
		var sloped := _step_surface(0.0, 0.15, float(grade))
		for upward in [true, false]:
			for angle in [0.0, 45.0]:
				for target in [1.2, 9.0]:
					_cross("graded %+.2f sidewalk %s %d deg %.1f m/s" % [float(grade), "up" if upward else "down", int(angle), float(target)],
						sloped, float(angle), float(target), bool(upward), 0.15)

## Road -> grass (+0.10) -> sidewalk (+0.15) -> alley (+0.02) -> road, with
## coincident opposite skirts at every boundary like adjacent city zones.
func _mixed_strip() -> void:
	await _clear_scenery()
	var zones := [[-25.0, 0.0, 0.0], [0.0, 3.0, 0.10], [3.0, 5.0, 0.15], [5.0, 8.0, 0.02], [8.0, 30.0, 0.0]]
	var faces: Array[Vector3] = []
	for zone in zones:
		var z0 := float(zone[0])
		var z1 := float(zone[1])
		var h := float(zone[2])
		_quad(faces, Vector3(-45.0, h, z0), Vector3(45.0, h, z0), Vector3(45.0, h, z1), Vector3(-45.0, h, z1))
	for i in zones.size() - 1:
		var z := float(zones[i][1])
		var a := float(zones[i][2])
		var b := float(zones[i + 1][2])
		_quad(faces, Vector3(-45.0, minf(a, b) - 0.08, z), Vector3(45.0, minf(a, b) - 0.08, z), Vector3(45.0, maxf(a, b), z), Vector3(-45.0, maxf(a, b), z))
	_trimesh(faces)
	await _settle_physics()
	var surface := func(z: float) -> float:
		for zone in zones:
			if z >= float(zone[0]) and z <= float(zone[1]):
				return float(zone[2])
		return 0.0
	var middles := [[1.5, 0.10], [4.0, 0.15], [6.5, 0.02]]
	for forward_run in [true, false]:
		for angle in [0.0, 35.0]:
			for target in [1.2, 9.0]:
				crossings += 1
				var tag := "mixed strip %s %d deg %.1f m/s" % ["outbound" if forward_run else "return", int(angle), float(target)]
				var theta := deg_to_rad(float(angle))
				var side := 1.0 if forward_run else -1.0
				var start_z := -3.0 if forward_run else 11.5
				var finish_z := 11.5 if forward_run else -3.0
				_place(Vector3(-30.0, float(surface.call(start_z)), start_z), atan2(sin(theta), cos(theta) * side), float(target))
				var impacts_before: int = bike.impacts
				var nearest := [INF, INF, INF]
				var heights := [0.0, 0.0, 0.0]
				var hull_hits := 0
				var sink := 0.0
				var hover := 0.0
				var arrived := false
				var limit := int(ceil(15.0 / cos(theta) / float(target) / DT)) + 150
				for i in limit:
					bike.tick(DT)
					var pose: Vector3 = bike.global_position
					sink = maxf(sink, _axle_sink())
					hover = maxf(hover, pose.y - _footprint_max(surface))
					if not _hull_ok():
						hull_hits += 1
					for m in middles.size():
						var gap := absf(pose.z - float(middles[m][0]))
						if gap < float(nearest[m]):
							nearest[m] = gap
							heights[m] = pose.y
					if (pose.z - finish_z) * side >= 0.0:
						arrived = true
						break
				_check(arrived, tag + ": crosses every raised zone")
				_check(hull_hits == 0 and sink <= 0.012 and hover <= 0.012, "%s: no overlap, sink %.3f or hover %.3f" % [tag, sink, hover])
				for m in middles.size():
					_check(absf(float(heights[m]) - float(middles[m][1])) <= 0.02, "%s: rides zone %d at %.3f (expected %.2f)" % [tag, m, float(heights[m]), float(middles[m][1])])
				_check(bike.impacts == impacts_before and not bike.is_crashed(), tag + ": raised zones are never impacts")
				print("BIKE_CURB %s arrived=%s zones=%s" % [tag, arrived, str(heights)])
			await get_tree().physics_frame

# ------------------------------------------------------------------ negative and special cases

func _tall_riser() -> void:
	await _clear_scenery()
	_curb_family(0.0, 0.33, 0.0)
	await _settle_physics()
	# Slow and head-on: blocked without climbing, tunnelling or a crash.
	_place(Vector3(-30.0, 0.0, -1.6), 0.0, 1.2)
	var crashes_before: int = bike.crashes
	var highest := 0.0
	var hull_hits := 0
	var sink := 0.0
	for i in 240:
		bike.tick(DT)
		highest = maxf(highest, bike.global_position.y)
		sink = maxf(sink, _axle_sink())
		if not _hull_ok():
			hull_hits += 1
	_check(bike.global_position.z < -0.4 and highest <= 0.02, "0.33 m ledge above the step limit is never climbed (z=%.2f peak=%.3f)" % [bike.global_position.z, highest])
	_check(hull_hits == 0 and sink <= 0.012, "pushing at a tall ledge never overlaps it (sink %.3f)" % sink)
	_check(bike.crashes == crashes_before and not bike.is_crashed(), "slow push against a tall ledge is not a crash")
	# A 70 degree glance at riding speed deflects along the ledge, rider stays on.
	_place(Vector3(-30.0, 0.0, -1.3), deg_to_rad(70.0), 9.0)
	var x_start: float = bike.global_position.x
	var yaw_start: float = bike.yaw
	hull_hits = 0
	for i in 90:
		bike.tick(DT)
		if not _hull_ok():
			hull_hits += 1
	_check(not bike.is_crashed() and bike.crashes == crashes_before, "70 deg glance off a tall ledge at 9 m/s does not eject")
	_check(bike.global_position.x - x_start > 4.0 and bike.global_position.z < 0.0 and bike.global_position.y < 0.02,
		"glancing bicycle keeps riding along the ledge (dx=%.2f z=%.2f)" % [bike.global_position.x - x_start, bike.global_position.z])
	_check(bike.yaw > yaw_start + 0.05, "glance swings the frame along the ledge (yaw %.2f -> %.2f)" % [yaw_start, bike.yaw])
	_check(hull_hits == 0, "glance never overlaps the ledge")
	# Head-on at riding speed: a real crash; the rider is thrown and recovers.
	var ejected_before := ejections
	_place(Vector3(-20.0, 0.0, -3.0), 0.0, 9.0)
	for i in 60:
		bike.tick(DT)
		if bike.is_crashed():
			break
	_check(bike.is_crashed() and ejections == ejected_before + 1, "head-on 9 m/s into a 0.33 m ledge ejects the rider")
	var last: Dictionary = bike.last_impact
	_check(str(last.get("severity", "")) == "crash" and float(last.get("closing_speed", 0.0)) >= Bicycle.CRASH_SPEED,
		"ledge crash is classified from closing speed (%s)" % str(last.get("closing_speed", 0.0)))
	var recovery := await _finish_crash("ledge crash")
	if not recovery.is_empty():
		var stand: Vector3 = recovery.position
		var support := float(_step_surface(0.0, 0.33, 0.0).call(stand.z))
		_check(absf(stand.y - support - 0.05) < 0.06, "explorer stands on a real surface after the ledge crash (y=%.3f)" % stand.y)

func _ramps() -> void:
	# A walkable 30 degree ramp climbs smoothly; a 55 degree face blocks.
	for spec in [[30.0, 3.0, true], [55.0, 1.0, false]]:
		await _clear_scenery()
		var slope := deg_to_rad(float(spec[0]))
		var run := float(spec[1])
		var top := run * tan(slope)
		var faces: Array[Vector3] = []
		_quad(faces, Vector3(-45.0, 0.0, -25.0), Vector3(45.0, 0.0, -25.0), Vector3(45.0, 0.0, 0.0), Vector3(-45.0, 0.0, 0.0))
		_quad(faces, Vector3(-45.0, 0.0, 0.0), Vector3(45.0, 0.0, 0.0), Vector3(45.0, top, run), Vector3(-45.0, top, run))
		_quad(faces, Vector3(-45.0, top, run), Vector3(45.0, top, run), Vector3(45.0, top, 25.0), Vector3(-45.0, top, 25.0))
		_trimesh(faces)
		await _settle_physics()
		var surface := func(z: float) -> float: return 0.0 if z <= 0.0 else minf(z, run) * tan(slope)
		_place(Vector3(-30.0, 0.0, -2.0), 0.0, 4.0 if bool(spec[2]) else 3.0)
		var crashes_before: int = bike.crashes
		var hull_hits := 0
		var sink := 0.0
		var hover := 0.0
		for i in 150:
			bike.tick(DT)
			sink = maxf(sink, _axle_sink())
			hover = maxf(hover, bike.global_position.y - _footprint_max(surface))
			if not _hull_ok():
				hull_hits += 1
		var tag := "%d deg ramp" % int(spec[0])
		_check(hull_hits == 0 and sink <= 0.012 and hover <= 0.012, "%s: no overlap, sink %.3f or hover %.3f" % [tag, sink, hover])
		if bool(spec[2]):
			_check(bike.global_position.z > run + 1.0 and absf(bike.global_position.y - top) <= 0.02, "%s: walkable ramp is ridden to the top (y=%.2f)" % [tag, bike.global_position.y])
		else:
			_check(bike.global_position.z < 0.1 and bike.global_position.y <= 0.05, "%s: steep face blocks the wheels (z=%.2f y=%.2f)" % [tag, bike.global_position.z, bike.global_position.y])
		_check(bike.crashes == crashes_before and not bike.is_crashed(), tag + ": no ejection at walking pace")

func _overhang() -> void:
	await _clear_scenery()
	_box(Vector3(0.0, -0.25, -12.5), Vector3(90.0, 0.5, 25.0), 1)
	_box(Vector3(0.0, 0.10, 3.0), Vector3(90.0, 0.20, 6.0), 1)
	_box(Vector3(-30.0, 1.65, 0.0), Vector3(8.0, 0.2, 6.0), 2)
	await _settle_physics()
	_place(Vector3(-30.0, 0.0, -2.0), 0.0, 2.0)
	var hull_hits := 0
	for i in 150:
		bike.tick(DT)
		if not _hull_ok():
			hull_hits += 1
	_check(bike.global_position.z < 0.0 and bike.global_position.y <= 0.01 and hull_hits == 0,
		"canopy over a curb blocks the climb without clipping (z=%.2f y=%.3f)" % [bike.global_position.z, bike.global_position.y])
	_check(not bike.is_crashed(), "overhang block is not a crash")

## Round posts: a glancing touch slides the bicycle off and on; dead centre
## recoils at low speed and crashes at riding speed.
func _posts() -> void:
	await _clear_scenery()
	_box(Vector3(0.0, -0.25, 0.0), Vector3(90.0, 0.5, 60.0), 1)
	var cases := [[0.30, 3.0], [0.30, 5.0], [-0.30, 4.0]]
	var lane := -36.0
	var posts: Array[Vector3] = []
	for spec in cases + [[0.15, 3.0], [0.0, 3.0], [0.0, 9.0]]:
		lane += 7.0
		posts.append(Vector3(lane + float(spec[0]), 0.0, 0.0))
		_post(posts.back())
	await _settle_physics()
	lane = -36.0
	for spec in cases:
		lane += 7.0
		var tag := "post offset %+.2f at %.0f m/s" % [float(spec[0]), float(spec[1])]
		_place(Vector3(lane, 0.0, -3.0), 0.0, float(spec[1]))
		var impacts_before: int = bike.impacts
		var hull_hits := 0
		var passed := false
		for i in 180:
			bike.tick(DT)
			if not _hull_ok():
				hull_hits += 1
			if bike.global_position.z > 1.5:
				passed = true
				break
		_check(passed and not bike.is_crashed(), "%s: glances off and keeps riding (z=%.2f)" % [tag, bike.global_position.z])
		_check(hull_hits == 0, tag + ": never overlaps the post")
		_check(bike.impacts > impacts_before and str(bike.last_impact.get("severity", "")) != "crash", tag + ": contact is a scrape or bump event")
		# Steered away from the post side (post on +X means away is -X).
		_check(signf(bike.global_position.x - lane) == -signf(float(spec[0])), tag + ": slides off away from the post")
	# Off-centre 0.15 m at 3 m/s: never through the post; steering away gets past.
	lane += 7.0
	_place(Vector3(lane, 0.0, -3.0), 0.0, 3.0)
	var pivot_hits := 0
	for i in 120:
		bike.tick(DT)
		if not _hull_ok():
			pivot_hits += 1
	_check(pivot_hits == 0 and not bike.is_crashed(), "post offset +0.15: pushing never overlaps or ejects")
	# Aim away, then ride straight once clear. Holding full lock for four
	# seconds can circle the post without ever reaching the world-Z finish.
	# This still requires physical passage; no pose reset or collision bypass.
	var post := Vector3(lane + 0.15, 0.0, 0.0)
	var cleared_post := false
	var no_yaw_frames := 0
	var escape_start: Vector3 = bike.global_position
	var escaped := false
	for i in 240:
		var steer := 0.0 if cleared_post else -clampf(angle_difference(float(bike.yaw), -PI * 0.25) * 2.0, -1.0, 1.0)
		bike.set_control_override(Vector2(steer, 0.35))
		var before_yaw: float = bike.yaw
		bike.tick(DT)
		if absf(steer) > 0.1 and absf(angle_difference(before_yaw, float(bike.yaw))) < 0.000001:
			no_yaw_frames += 1
		if not _hull_ok():
			pivot_hits += 1
		if bike.global_position.x < lane - 0.6 and Vector2(bike.global_position.x - post.x, bike.global_position.z - post.z).length() > 1.2:
			cleared_post = true
		if cleared_post and bike.global_position.z > 1.5:
			escaped = true
			break
	var post_distance := Vector2(bike.global_position.x - post.x, bike.global_position.z - post.z).length()
	print("BIKE_POST_ESCAPE start=%s end=%s x_from_lane=%.3f yaw_deg=%.2f speed=%.3f post_distance=%.3f cleared=%s no_yaw_frames=%d hull_hits=%d" %
		[str(escape_start), str(bike.global_position), bike.global_position.x - lane, rad_to_deg(float(bike.yaw)), float(bike.speed), post_distance, str(cleared_post), no_yaw_frames, pivot_hits])
	_check(escaped and pivot_hits == 0 and not bike.is_crashed(),
		"post offset +0.15: steering away clears the post then rides past (x=%.2f z=%.2f yaw=%.1f speed=%.2f distance=%.2f clear=%s stalled=%d)" %
		[bike.global_position.x, bike.global_position.z, rad_to_deg(float(bike.yaw)), float(bike.speed), post_distance, str(cleared_post), no_yaw_frames])
	# Dead centre at 3 m/s: a bump that recoils, not a dead stop or a crash.
	lane += 7.0
	_place(Vector3(lane, 0.0, -3.0), 0.0, 3.0)
	var touched_z := INF
	var first: Dictionary = {}
	var recoil := 0.0
	for i in 150:
		var before: int = bike.impacts
		bike.tick(DT)
		if bike.impacts > before and first.is_empty():
			touched_z = bike.global_position.z
			first = bike.last_impact.duplicate()
		if is_finite(touched_z):
			recoil = maxf(recoil, touched_z - bike.global_position.z)
	_check(str(first.get("severity", "")) == "bump" and not bike.is_crashed(), "dead-centre post at 3 m/s is a bump (%s)" % str(first.get("severity", "none")))
	_check(recoil > 0.03, "bump recoils the bicycle instead of a dead stop (%.3f m)" % recoil)
	# Dead centre at riding speed: rider ejected, recovers on solid ground.
	lane += 7.0
	var ejected_before := ejections
	_place(Vector3(lane, 0.0, -4.0), 0.0, 9.0)
	for i in 60:
		bike.tick(DT)
		if bike.is_crashed():
			break
	_check(bike.is_crashed() and ejections == ejected_before + 1, "dead-centre post at 9 m/s ejects the rider")
	await _finish_crash("post crash")
	# A post standing on the sidewalk beside the line does not spoil a crossing.
	await _clear_scenery()
	_curb_family(0.0, 0.15, 0.0)
	_post(Vector3(-29.45, 0.15, 0.4))
	await _settle_physics()
	_cross("sidewalk +0.15 beside a post", _step_surface(0.0, 0.15, 0.0), 0.0, 4.0, true, 0.15)

## Running parallel to a curb and steering into it must climb it: the raised
## hull no longer vetoes turning toward a riser.
func _steer_into_curb() -> void:
	await _clear_scenery()
	_curb_family(0.0, 0.15, 0.0)
	await _settle_physics()
	_place(Vector3(-30.0, 0.0, -0.7), PI * 0.5, 6.0)
	bike.set_control_override(Vector2(1.0, 6.0 / Bicycle.MAX_SPEED))
	var climbed := false
	var hull_hits := 0
	for i in 240:
		bike.tick(DT)
		if not _hull_ok():
			hull_hits += 1
		if bike.global_position.z > 1.2 and absf(bike.global_position.y - 0.15) <= 0.02:
			climbed = true
			break
	_check(climbed and hull_hits == 0 and not bike.is_crashed(), "steering from parallel into a curb climbs it (z=%.2f y=%.3f)" % [bike.global_position.z, bike.global_position.y])

func _reverse_climb() -> void:
	await _clear_scenery()
	_curb_family(0.0, 0.15, 0.0)
	await _settle_physics()
	_place(Vector3(-30.0, 0.0, -1.6), PI, -Bicycle.REVERSE_SPEED)
	var climbed := false
	for i in 240:
		bike.tick(DT)
		if bike.global_position.z > 1.4:
			climbed = true
			break
	_check(climbed and absf(bike.global_position.y - 0.15) <= 0.02 and not bike.is_crashed(), "reversing rolls the rear wheel up a curb (z=%.2f y=%.3f)" % [bike.global_position.z, bike.global_position.y])
