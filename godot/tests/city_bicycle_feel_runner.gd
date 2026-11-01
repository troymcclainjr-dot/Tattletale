extends Node3D
## Root serializes engine runs. Bicycle feel and continuity: the real
## city_player.gd explorer (seat, walking and chase cameras), the real
## city_bicycle.gd and its crash rig, on plain bodies on the city's layers
## (ground 1, walls 2, people 8, cars 16 moved before the bicycle ticks, as the
## level orders traffic and bicycle). Start poses and speeds are API arranged,
## and so is one post-knock slip, as the other bicycle fixtures arrange speed.
## Every frame after that is production code with real collision queries.
## Each check states what a rider would see or feel, never a formula.
const Bicycle := preload("res://scripts/city/city_bicycle.gd")
const Player := preload("res://scripts/city/city_player.gd")
const CrashRig := preload("res://scripts/city/city_bicycle_crash.gd")
const DT := 1.0 / 60.0
const WALL_Z := 30.0

class Fixture extends Node3D:
	var paused := false
	var offscreen_validation := false
	var player: CharacterBody3D
	var combat: Node3D
	var bicycle: CharacterBody3D

## A driven car moved by swept motion before the bicycle ticks (the level's
## order). It keeps its intended velocity on contact, as traffic reports it.
class DrivenCar extends CharacterBody3D:
	var vehicle_id := "feel_car"
	var drive := Vector3.ZERO
	func step(dt: float) -> void:
		velocity = drive
		if drive.length_squared() > 0.0:
			move_and_collide(drive * dt)

var world: Fixture
var bike: CharacterBody3D
var player: CharacterBody3D
var cars: Array[DrivenCar] = []
var errors: Array[String] = []
var checks := 0
var impacts: Array[Dictionary] = []
var ejected: Array[Dictionary] = []
var recovered: Array[Dictionary] = []

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors.append(message)
		push_error(message)
	print("BIKE_FEEL ", "PASS " if ok else "FAIL ", message)

func _run() -> void:
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	world = Fixture.new()
	add_child(world)
	_box(Vector3(0.0, -0.25, 0.0), Vector3(400.0, 0.5, 400.0), 1)
	_box(Vector3(150.0, 1.5, WALL_Z + 0.3), Vector3(14.0, 3.0, 0.6), 2)
	player = Player.new()
	world.player = player
	world.add_child(player)
	player.global_position = Vector3(1.3, 0.05, 0.0)
	player.enabled = true
	await _idle(4)
	bike = Bicycle.new()
	world.add_child(bike)
	world.bicycle = bike
	bike.setup(world)
	_check(bike.spawned, "real bicycle spawns beside the real explorer")
	bike.impact.connect(func(event: Dictionary): impacts.append(event))
	bike.rider_ejected.connect(func(event: Dictionary): ejected.append(event))
	bike.rider_recovered.connect(func(event: Dictionary): recovered.append(event))
	await _slip_never_brakes_pedals()
	await _overtaking_car_brush()
	await _oncoming_car_throw()
	await _mount_dismount_camera()
	await _glide_stays_out_of_geometry()
	await _getup_continuity()
	await _crash_recovery_continuity()
	print("CITY_BICYCLE_FEEL ", "PASS" if errors.is_empty() else "FAIL", " checks=", checks, " failures=", errors.size())
	get_tree().quit(0 if errors.is_empty() else 1)

# ------------------------------------------------------------------ fixture helpers

func _box(at: Vector3, size: Vector3, layer: int) -> StaticBody3D:
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
	return body

func _car(at: Vector3, mask: int) -> DrivenCar:
	var car := DrivenCar.new()
	car.collision_layer = 16
	car.collision_mask = mask
	car.set_meta("traffic_vehicle", true)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.9, 1.4, 4.5)
	collider.shape = shape
	collider.position = Vector3(0.0, 0.95, 0.0)
	car.add_child(collider)
	world.add_child(car)
	car.global_position = at
	cars.append(car)
	return car

func _remove_car(car: DrivenCar) -> void:
	cars.erase(car)
	car.queue_free()
	await _idle(2)

func _idle(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

## One level tick per physics frame: traffic first, then the bicycle.
func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		for car in cars:
			car.step(DT)
		bike.tick(DT)

## Ends any ride or crash and stands the explorer at `at` (between scenarios only).
func _release_explorer(at: Vector3, heading: float) -> void:
	if bike.active:
		bike.recovery_exit_at(at, heading)
	elif player.is_seated():
		player.leave_vehicle(at, heading)
	player.global_position = at
	player.velocity = Vector3.ZERO
	await _idle(2)

func _park_bike(at: Vector3, heading: float) -> void:
	bike.global_position = at
	bike.yaw = heading
	bike.rotation.y = heading
	bike.reset_motion_state()
	bike.speed = 0.0
	bike.set_control_override(Vector2.ZERO, true)

## Between scenarios only: stand the explorer beside the bicycle and mount with
## the real enter_bicycle(); never used to turn a failed check into a pass.
func _arrange(at: Vector3, heading: float, target: float) -> bool:
	for car in cars:
		car.drive = Vector3.ZERO
	var beside := at - Vector3(cos(heading), 0.0, -sin(heading)) * 1.3 + Vector3.UP * 0.05
	await _release_explorer(beside, heading)
	_park_bike(at, heading)
	player.camera_yaw = heading
	await _idle(3)
	var mounted: bool = bike.enter_bicycle()
	bike.speed = target
	bike.set_control_override(Vector2(0.0, minf(1.0, target / Bicycle.MAX_SPEED)), false, target > Bicycle.MAX_SPEED)
	return mounted and bike.active

func _until_crashed(limit: int) -> bool:
	for i in limit:
		await _frames(1)
		if bike.is_crashed():
			return true
	return false

func _until_recovered() -> Dictionary:
	var before := recovered.size()
	for i in int(Bicycle.MAX_CRASH_TIME / DT) + 90:
		if not bike.is_crashed():
			break
		await _frames(1)
	return recovered.back() if recovered.size() > before else {}

func _hull_ok() -> bool:
	return bike._hull_clear(bike.global_transform, 0.0, 0.02)

func _sphere_clear(at: Vector3, radius: float, exclude: Array) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, at)
	query.collision_mask = 1 | 2 | 8 | 16
	var rids: Array[RID] = [bike.get_rid(), player.get_rid()]
	for rid in exclude:
		rids.append(rid)
	query.exclude = rids
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _ground_y(at: Vector3) -> float:
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.0, at + Vector3.DOWN * 3.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return float(hit.position.y) if not hit.is_empty() else -INF

func _eye() -> Vector3:
	return player.camera.global_position

func _look() -> Vector3:
	return -player.camera.global_basis.z

## Worst per-frame camera movement and view turn over `count` level frames.
func _camera_steps(count: int) -> Dictionary:
	var worst_step := 0.0
	var worst_turn := 0.0
	var eye := _eye()
	var look := _look()
	for i in count:
		await _frames(1)
		worst_step = maxf(worst_step, _eye().distance_to(eye))
		worst_turn = maxf(worst_turn, rad_to_deg(look.angle_to(_look())))
		eye = _eye()
		look = _look()
	return {"step": worst_step, "turn": worst_turn}

## Where the ordinary chase camera rests behind a stopped bicycle.
func _chase_eye() -> Vector3:
	var pitch := float(player.vehicle_orbit_pitch)
	var distance := float(player.chase_distance)
	var forward := Vector3(sin(bike.yaw), 0.0, cos(bike.yaw))
	var boom := -forward * cos(pitch) * distance + Vector3.UP * (sin(pitch) * distance + 0.55)
	return bike.global_position + Vector3.UP * Player.CHASE_TARGET_HEIGHT + boom

## Length of the unobstructed walking boom at `pitch` (no aim, no shoulder).
func _walking_boom(pitch: float) -> float:
	return Vector2(cos(pitch) * 5.2, sin(pitch) * 5.2 + 0.65).length()

# ------------------------------------------------------------------ riding feel

## A knock leaves a decaying sideways slip. Steering off that line with W held
## must never brake the pedals: only what walls and people take is lost.
func _slip_never_brakes_pedals() -> void:
	_check(await _arrange(Vector3(-20.0, 0.0, -40.0), 0.0, 6.0), "slip: mounted on open ground")
	# Already holding W and turning left when the knock lands.
	bike.set_control_override(Vector2(-1.0, 1.0))
	await _frames(20)
	# Arranged knock aftermath, as a glancing bump leaves it: recoil across the
	# frame toward the rider's right, plus the balance wobble.
	var right := Vector3(-cos(bike.yaw), 0.0, sin(bike.yaw))
	bike._slip = right * 2.5
	bike._wobble = 0.45
	var impacts_before := impacts.size()
	var previous: float = bike.speed
	var start_speed: float = bike.speed
	var worst_drop := 0.0
	var slip_frames := 0
	for i in 40:
		await _frames(1)
		if bike._slip.length() > 0.05:
			slip_frames += 1
		worst_drop = maxf(worst_drop, previous - float(bike.speed))
		previous = bike.speed
	var travel := Vector3(bike.velocity.x, 0.0, bike.velocity.z)
	var heading := Vector3(sin(bike.yaw), 0.0, cos(bike.yaw))
	_check(impacts.size() == impacts_before and not bike.is_crashed(), "slip: open ground, nothing was touched")
	_check(slip_frames >= 5, "slip: the leftover slip was still moving the bike while steering (%d frames)" % slip_frames)
	_check(worst_drop <= 0.003, "slip: steering through leftover slip with W held never slows the pedals (worst frame drop %.3f m/s)" % worst_drop)
	_check(float(bike.speed) > start_speed + 0.5, "slip: pedals keep gaining speed toward the W target (%.2f -> %.2f m/s)" % [start_speed, bike.speed])
	_check(travel.length() > 1.0 and rad_to_deg(travel.angle_to(heading)) < 2.0, "slip: once the slip has decayed the bike travels where it points (%.1f deg off)" % rad_to_deg(travel.angle_to(heading)))

## A faster car brushing the rider's side drags the bike along its flank. The
## frame aligns with the car or stays put; it never swings into the car.
func _overtaking_car_brush() -> void:
	_check(await _arrange(Vector3(40.0, 0.0, -60.0), 0.087, 9.0), "brush: mounted beside the traffic lane")
	# The car sweeps only the world, like traffic that has not reacted yet, so
	# every contact is the bicycle meeting the car's flank, which stays beside it.
	var car := _car(Vector3(41.4, 0.0, -60.0), 1 | 2)
	await _idle(2)
	car.drive = Vector3(0.0, 0.0, 12.0)
	var yaw_start: float = bike.yaw
	var impacts_before := impacts.size()
	var crashes_before: int = bike.crashes
	var toward_car := 0.0
	var overlaps := 0
	for i in 50:
		await _frames(1)
		toward_car = maxf(toward_car, angle_difference(yaw_start, float(bike.yaw)))
		if not _hull_ok():
			overlaps += 1
	car.drive = Vector3.ZERO
	var first: Dictionary = impacts[impacts_before] if impacts.size() > impacts_before else {}
	_check(str(first.get("kind", "")) == "vehicle" and str(first.get("severity", "")) == "scrape",
		"brush: the overtaking car's flank is met as a vehicle scrape (%s %s)" % [str(first.get("kind", "none")), str(first.get("severity", "none"))])
	_check(toward_car <= 0.01, "brush: the frame never swings toward the overtaking car (peak %.3f rad toward it)" % toward_car)
	_check(bike.crashes == crashes_before and not bike.is_crashed() and player.seated_vehicle == bike, "brush: the rider stays on")
	_check(overlaps == 0, "brush: the bicycle never overlaps the moving car (%d frames)" % overlaps)
	_check(absf(bike.speed) >= 7.0, "brush: the bicycle keeps riding (%.2f m/s)" % bike.speed)
	await _remove_car(car)

## A car driving into the rider throws them back away from its front, never
## forward into the car they just hit.
func _oncoming_car_throw() -> void:
	_check(await _arrange(Vector3(80.0, 0.0, -66.0), 0.0, 4.0), "oncoming: mounted")
	var car := _car(Vector3(80.0, 0.0, -60.0), 1 | 2 | 4 | 8 | 16)
	await _idle(2)
	car.drive = Vector3(0.0, 0.0, -5.0)
	var crashed := await _until_crashed(90)
	car.drive = Vector3.ZERO
	_check(crashed, "oncoming: 4 m/s into a car coming at 5 m/s ejects the rider")
	if not crashed:
		await _remove_car(car)
		return
	var event: Dictionary = ejected.back()
	var impact: Dictionary = event.impact
	var normal: Vector3 = impact.normal
	_check(str(impact.kind) == "vehicle" and float(impact.closing_speed) >= 8.0, "oncoming: classified from the closing speed of both (%.2f m/s)" % float(impact.closing_speed))
	var crash = bike.get("_crash")
	var start_plane := Vector3(event.start).dot(normal)
	var toward := 0.0
	var overlaps := 0
	for i in 60:
		await _frames(1)
		if not bike.is_crashed():
			break
		toward = maxf(toward, start_plane - Vector3(crash.center).dot(normal))
		if not _sphere_clear(crash.center, 0.25, [crash.get_rid(), crash.rider_rid()]):
			overlaps += 1
	_check(toward <= 0.05, "oncoming: the thrown rider never travels back toward the car (%.2f m toward it)" % toward)
	_check(overlaps == 0, "oncoming: the rider never overlaps the car (%d frames)" % overlaps)
	var recovery := await _until_recovered()
	_check(not recovery.is_empty(), "oncoming: the rider stands up again")
	await _remove_car(car)

# ------------------------------------------------------------------ camera continuity

## Mounting from a couple of metres away, and getting off, swap the camera's
## subject. The view glides over instead of cutting. A teleport still cuts.
func _mount_dismount_camera() -> void:
	var at := Vector3(-60.0, 0.0, 40.0)
	await _release_explorer(at + Vector3(-2.2, 0.05, 0.0), 0.0)
	_park_bike(at, 0.0)
	player.yaw = 0.0
	player.camera_yaw = 0.0
	player.camera_pitch = 0.7
	await _idle(20)
	var before := _eye()
	_check(bike.enter_bicycle(), "camera: ordinary mount from 2.2 m away")
	bike.set_control_override(Vector2.ZERO, true)
	var mount_jump := _eye().distance_to(before)
	var steps := await _camera_steps(60)
	_check(mount_jump <= 0.45 and float(steps.step) <= 0.45,
		"camera: mounting from 2.2 m glides the view over, no cut (mount frame %.2f m, worst frame %.2f m)" % [mount_jump, float(steps.step)])
	_check(float(steps.turn) <= 6.0, "camera: the view turns smoothly while gliding (worst %.1f deg per frame)" % float(steps.turn))
	_check(absf(float(player.vehicle_orbit_pitch) - 0.7) < 0.01, "camera: the walking view's tilt carries onto the bicycle (pitch %.2f)" % float(player.vehicle_orbit_pitch))
	_check(_eye().distance_to(_chase_eye()) <= 0.05, "camera: after a second the view rests at the ordinary chase pose (off by %.3f m)" % _eye().distance_to(_chase_eye()))
	before = _eye()
	_check(bike.exit_vehicle(), "camera: the stopped bicycle dismounts")
	var exit_jump := _eye().distance_to(before)
	steps = await _camera_steps(60)
	_check(exit_jump <= 0.45 and float(steps.step) <= 0.45,
		"camera: getting off glides back to the walking view (exit frame %.2f m, worst frame %.2f m)" % [exit_jump, float(steps.step)])
	var boom := _walking_boom(player.camera_pitch)
	var head: Vector3 = player.global_position + Vector3.UP * 1.5
	_check(absf(_eye().distance_to(head) - boom) <= 0.06, "camera: the walking view is back at its full boom (%.2f of %.2f m)" % [_eye().distance_to(head), boom])
	# A teleport (respawn, checkpoint) is not a seat change: it cuts at once.
	before = _eye()
	player.global_position += Vector3(25.0, 0.0, 0.0)
	player.update_camera()
	head = player.global_position + Vector3.UP * 1.5
	_check(_eye().distance_to(before) > 20.0 and absf(_eye().distance_to(head) - boom) <= 0.06,
		"camera: a teleport still cuts straight to the full walking view (boom %.2f of %.2f m)" % [_eye().distance_to(head), boom])
	await _idle(4)

## The glide is clamped by a swept sphere: a head-height beam between the
## explorer and the bicycle is never entered by the camera or its look point.
func _glide_stays_out_of_geometry() -> void:
	var at := Vector3(-60.0, 0.0, 80.0)
	await _release_explorer(at + Vector3(-2.2, 0.05, 0.0), 0.0)
	_park_bike(at, 0.0)
	var beam := _box(at + Vector3(-1.1, 1.55, 0.0), Vector3(0.2, 0.3, 3.0), 2)
	player.yaw = 0.0
	player.camera_yaw = 0.0
	player.camera_pitch = 0.24
	await _idle(20)
	_check(bike.enter_bicycle(), "glide: mounts with a head-height beam between explorer and bicycle")
	bike.set_control_override(Vector2.ZERO, true)
	var inside := 0
	for i in 40:
		var look_point: Vector3 = player._camera_last_target
		if not _sphere_clear(_eye(), 0.15, []) or not _sphere_clear(look_point, 0.1, []):
			inside += 1
		await _frames(1)
	_check(inside == 0, "glide: neither the camera nor its look point ever enters the beam (%d frames)" % inside)
	bike.exit_vehicle(true)
	beam.queue_free()
	await _idle(2)

# ------------------------------------------------------------------ crash recovery continuity

## The real crash rig, driven through its public API with the real explorer
## seated on it as city_bicycle._tick_crash drives it: standing up carries the
## explorer's anchor (the camera's subject) to the standing spot, and a far
## fallback spot is not slid to through whatever ruled the near ones out.
func _getup_continuity() -> void:
	var rig := CrashRig.new()
	world.add_child(rig)
	rig.setup(bike, player)
	var row := 0
	for spec in [[1.2, "near"], [2.4, "far"]]:
		var reach := float(spec[0])
		var tag := "get-up %s (%.1f m)" % [str(spec[1]), reach]
		var origin := Vector3(-80.0, 0.0, -80.0 + 12.0 * float(row))
		row += 1
		await _release_explorer(origin + Vector3(0.0, 0.05, -2.5), 0.0)
		player.camera_yaw = 0.0
		player.camera_pitch = 0.24
		_check(rig.begin(origin + Vector3.UP * 0.6, Vector3(0.0, 1.0, 0.0), Vector3.ZERO, 0.0), tag + ": rig starts a short tumble")
		player.enter_vehicle(rig)
		for i in 300:
			await _idle(1)
			rig.step(DT)
			player.follow_vehicle()
			if rig.phase == "down":
				break
		_check(rig.phase == "down", tag + ": the rider comes to rest lying down")
		var lying: Vector3 = rig.global_position
		var spot := lying + Vector3(reach, 0.05, 0.0)
		rig.begin_getup(spot, 0.0)
		var worst_anchor := 0.0
		var anchor_air := 0.0
		var worst_eye := 0.0
		var anchor_previous: Vector3 = rig.global_position
		var eye_previous := _eye()
		for i in 120:
			await _idle(1)
			rig.step(DT)
			player.follow_vehicle()
			var anchor: Vector3 = rig.global_position
			worst_anchor = maxf(worst_anchor, anchor.distance_to(anchor_previous))
			anchor_air = maxf(anchor_air, absf(anchor.y - _ground_y(anchor)))
			worst_eye = maxf(worst_eye, _eye().distance_to(eye_previous))
			anchor_previous = anchor
			eye_previous = _eye()
			if rig.phase == "done":
				break
		_check(rig.phase == "done", tag + ": the get-up completes")
		var anchor_end: Vector3 = rig.global_position
		var pivot: Vector3 = rig.get("_pivot").global_position
		_check(anchor_air <= 0.02, "%s: the explorer's anchor stays on the ground (%.3f m)" % [tag, anchor_air])
		if reach <= CrashRig.GETUP_REACH:
			_check(worst_anchor <= 0.06, "%s: the anchor walks to the standing spot in small steps (worst %.3f m per frame)" % [tag, worst_anchor])
			_check(Vector2(anchor_end.x - spot.x, anchor_end.z - spot.z).length() <= 0.06,
				"%s: the anchor ends at the standing spot (%.2f m away)" % [tag, Vector2(anchor_end.x - spot.x, anchor_end.z - spot.z).length()])
		else:
			_check(Vector2(anchor_end.x - lying.x, anchor_end.z - lying.z).length() <= 0.02 and worst_anchor <= 0.02,
				"%s: a far fallback is not walked to; the anchor stays where the rider lay" % tag)
			_check(Vector2(pivot.x - lying.x, pivot.z - lying.z).length() <= 0.12,
				"%s: the rider rises in place instead of sliding %.1f m (%.2f m)" % [tag, reach, Vector2(pivot.x - lying.x, pivot.z - lying.z).length()])
		# Hand-off exactly as city_bicycle._end_crash: release the rig, then stand.
		rig.finish()
		var before := _eye()
		player.leave_vehicle(spot, 0.0)
		worst_eye = maxf(worst_eye, _eye().distance_to(before))
		var after := await _camera_steps(30)
		worst_eye = maxf(worst_eye, float(after.step))
		_check(worst_eye <= 0.45, "%s: the camera never jumps from lying to standing (worst %.2f m per frame)" % [tag, worst_eye])
		_check(not player.is_seated() and player.global_position.distance_to(spot) < 0.1, tag + ": the explorer stands at the chosen spot")
	rig.queue_free()
	await _idle(2)

## A real wall crash end to end: the explorer's anchor and the camera move in
## bounded steps from ejection through tumble, get-up and recovery. The chase
## camera keeps its distance behind the rider (open ground behind, the wall
## ahead): the riderless bicycle's upright hull at the launch point must not
## collapse the boom onto the rider at the moment of the crash.
func _crash_recovery_continuity() -> void:
	_check(await _arrange(Vector3(150.0, 0.0, WALL_Z - 5.5), 0.0, 9.0), "crash: mounted")
	if not await _until_crashed(90):
		_check(false, "crash: 9 m/s into a wall ejects the rider")
		return
	var worst_anchor := 0.0
	var worst_eye := 0.0
	var anchor_air := 0.0
	var closest_boom := INF
	var anchor := player.global_position
	var eye := _eye()
	var frames_after := 0
	for i in int(Bicycle.MAX_CRASH_TIME / DT) + 120:
		await _frames(1)
		worst_anchor = maxf(worst_anchor, player.global_position.distance_to(anchor))
		worst_eye = maxf(worst_eye, _eye().distance_to(eye))
		if bike.is_crashed():
			anchor_air = maxf(anchor_air, absf(player.global_position.y - _ground_y(player.global_position)))
			closest_boom = minf(closest_boom, _eye().distance_to(Vector3(player._camera_last_target)))
		anchor = player.global_position
		eye = _eye()
		if not bike.is_crashed():
			frames_after += 1
			if frames_after > 30:
				break
	_check(not bike.is_crashed() and not player.is_seated(), "crash: the rider is back on their feet")
	_check(anchor_air <= 0.06, "crash: the explorer's anchor stays on the ground through the tumble (%.3f m)" % anchor_air)
	_check(closest_boom >= 3.0, "crash: the chase camera keeps its distance through the tumble, no collapse onto the rider (closest %.2f m)" % closest_boom)
	_check(worst_anchor <= 0.5, "crash: the explorer's anchor never jumps between frames, recovery included (worst %.2f m)" % worst_anchor)
	_check(worst_eye <= 0.6, "crash: the camera never cuts from ejection to walking again (worst %.2f m per frame)" % worst_eye)
