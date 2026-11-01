extends Node3D
## Root serializes engine runs. Real city_player.gd explorer (seated chase
## camera, enter/leave vehicle), real city_bicycle.gd with its crash rig, and
## the real city_world_save.gd checkpoint blocker against a minimal level.
## Obstacles are plain bodies on the city's layers: structures 2, a parked car
## 2|16 with parked meta, a driven car 16 (CharacterBody3D velocity), a person
## 8 with a crowd index. Start speeds are API arranged; contact
## classification, ejection, tumble, landing, recovery and the riderless slide
## are production code with real collision queries, one tick per physics frame.
const Bicycle := preload("res://scripts/city/city_bicycle.gd")
const Player := preload("res://scripts/city/city_player.gd")
const Save := preload("res://scripts/city/city_world_save.gd")
const DT := 1.0 / 60.0
const WALL_Z := 6.0

class Residents extends Node:
	var actors: Dictionary = {}
	func get_status() -> Dictionary:
		return {"pending_routes": 0, "count": 0}

class Fixture extends Node3D:
	var paused := false
	var offscreen_validation := false
	var player: CharacterBody3D
	var combat: Node3D
	var bicycle: CharacterBody3D
	var world_time: Node
	var residents: Node
	var missions: Node
	var level_data: Dictionary = {"terrain_extent": {"min": [-300.0, -20.0, -300.0], "max": [300.0, 20.0, 300.0]}}
	func ground_at(point: Vector3) -> Dictionary:
		var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 60.0, point - Vector3.UP * 120.0, 1)
		return get_world_3d().direct_space_state.intersect_ray(ray)

## Mirrors the incidents contract's combat.knockdown_from_bicycle signature.
class KnockdownProbe extends Node:
	var calls: Array[Dictionary] = []
	func knockdown_from_bicycle(target, contact_speed: float, impulse := Vector3.ZERO, context := {}) -> Dictionary:
		calls.append({"target": target, "speed": contact_speed, "impulse": impulse, "context": context})
		return {"ok": true, "outcome": "knocked_down"}

## A driven car moved by swept motion before the bicycle ticks, the level's
## order (traffic, then bicycle). It keeps its intended velocity on contact.
class DrivenCar extends CharacterBody3D:
	var vehicle_id := "fixture_car"
	var drive := Vector3.ZERO
	func step(dt: float) -> void:
		velocity = drive
		if drive.length_squared() > 0.0:
			move_and_collide(drive * dt)

var world: Fixture
var bike: CharacterBody3D
var player: CharacterBody3D
var provider: Node
var probe: KnockdownProbe
var cars: Array[DrivenCar] = []
var errors: Array[String] = []
var checks := 0
var ejected: Array[Dictionary] = []
var recovered: Array[Dictionary] = []
var impacts: Array[Dictionary] = []
var people: Array[Dictionary] = []
var wall_scenario := false
var audit: Dictionary = {}

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors.append(message)
		push_error(message)
	print("BIKE_CRASH ", "PASS " if ok else "FAIL ", message)

func _run() -> void:
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	world = Fixture.new()
	add_child(world)
	world.world_time = Node.new()
	world.add_child(world.world_time)
	world.residents = Residents.new()
	world.add_child(world.residents)
	world.missions = Node.new()
	world.add_child(world.missions)
	probe = KnockdownProbe.new()
	world.add_child(probe)
	_box(Vector3(0.0, -0.25, 0.0), Vector3(300.0, 0.5, 300.0), 1)
	_box(Vector3(0.0, 1.5, WALL_Z + 0.3), Vector3(40.0, 3.0, 0.6), 2)
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
	_check(bike.spawned and bike.has_method("blocks_checkpoint") and bike.has_signal("rider_ejected"), "real bicycle with crash API spawns")
	provider = Save.new()
	world.add_child(provider)
	provider.setup(world, ProjectSettings.globalize_path("res://../.work/pacifist-foundation/bike-crash-fixture/never-written.json"))
	bike.rider_ejected.connect(func(event: Dictionary): ejected.append(event))
	bike.rider_recovered.connect(func(event: Dictionary): recovered.append(event))
	bike.impact.connect(func(event: Dictionary): impacts.append(event))
	bike.pedestrian_contact.connect(_bridge)
	await _wall_crash()
	await _glances()
	await _head_on_bump()
	await _parked_car()
	await _moving_cars()
	await _pedestrian()
	await _forced_releases()
	print("CITY_BICYCLE_CRASH ", "PASS" if errors.is_empty() else "FAIL", " checks=", checks, " failures=", errors.size())
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

## The incidents-contract root bridge, verbatim in shape.
func _bridge(contact: Dictionary) -> void:
	people.append(contact)
	var speed := float(contact.get("relative_speed", contact.get("speed", 0.0)))
	var push: Vector3 = contact.get("impulse", Vector3.ZERO)
	if push == Vector3.ZERO and contact.get("direction") is Vector3:
		push = contact.direction * speed
	probe.knockdown_from_bicycle(contact.get("collider"), speed, push, contact)

func _idle(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		for car in cars:
			car.step(DT)
		bike.tick(DT)
		_audit()

func _reset_audit() -> void:
	audit = {"rider_overlaps": 0, "bike_overlaps": 0, "anchor_air": 0.0, "camera_past_wall": 0, "rider_past_wall": 0}

func _audit() -> void:
	if not bike._hull_clear(bike.global_transform, 0.0, 0.02):
		audit.bike_overlaps = int(audit.bike_overlaps) + 1
	if not bike.is_crashed():
		return
	var crash = bike.get("_crash")
	if not _sphere_clear(crash.center, 0.25, [crash.get_rid(), crash.rider_rid(), bike.get_rid(), player.get_rid()]):
		audit.rider_overlaps = int(audit.rider_overlaps) + 1
	audit.anchor_air = maxf(float(audit.anchor_air), absf(player.global_position.y - _ground_y(player.global_position)))
	if wall_scenario:
		if float(crash.center.z) + 0.25 > WALL_Z + 0.02:
			audit.rider_past_wall = int(audit.rider_past_wall) + 1
		if player.camera.global_position.z > WALL_Z - 0.02:
			audit.camera_past_wall = int(audit.camera_past_wall) + 1

func _sphere_clear(at: Vector3, radius: float, exclude: Array) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, at)
	query.collision_mask = 1 | 2 | 8 | 16
	var rids: Array[RID] = []
	for rid in exclude:
		rids.append(rid)
	query.exclude = rids
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _ground_y(at: Vector3) -> float:
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.0, at + Vector3.DOWN * 3.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return float(hit.position.y) if not hit.is_empty() else -INF

func _capsule_clear(body: CharacterBody3D) -> bool:
	var capsule: CollisionShape3D = body.get("_capsule")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule.shape
	query.transform = capsule.global_transform
	query.collision_mask = 2 | 8 | 16
	query.exclude = [body.get_rid()]
	query.margin = 0.002
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

## Between scenarios only: put the explorer beside the bicycle and mount with
## the real enter_bicycle(); never used to turn a failed check into a pass.
func _arrange(at: Vector3, heading: float, target: float) -> bool:
	for car in cars:
		car.drive = Vector3.ZERO
	var beside := at + Vector3(cos(heading), 0.0, -sin(heading)) * 1.3 + Vector3.UP * 0.05
	if bike.active:
		bike.recovery_exit_at(beside, heading)
	bike.global_position = at
	bike.yaw = heading
	bike.rotation.y = heading
	bike.reset_motion_state()
	player.global_position = beside
	player.velocity = Vector3.ZERO
	await _idle(3)
	var mounted: bool = bike.enter_bicycle()
	bike.speed = target
	bike.set_control_override(Vector2(0.0, minf(1.0, target / Bicycle.MAX_SPEED)), false, target > Bicycle.MAX_SPEED)
	_reset_audit()
	return mounted and bike.active

func _until_crashed(limit: int) -> bool:
	for i in limit:
		await _frames(1)
		if bike.is_crashed():
			return true
	return false

## Runs the tumble to the standing explorer; returns the recovery event.
func _until_recovered() -> Dictionary:
	var before := recovered.size()
	for i in int(Bicycle.MAX_CRASH_TIME / DT) + 90:
		if not bike.is_crashed():
			break
		await _frames(1)
	return recovered.back() if recovered.size() > before else {}

# ------------------------------------------------------------------ scenarios

func _wall_crash() -> void:
	wall_scenario = true
	_check(await _arrange(Vector3(0.0, 0.0, 0.5), 0.0, 9.0), "wall crash: explorer mounts the real bicycle")
	var before := ejected.size()
	var crashed := await _until_crashed(90)
	var impact_z: float = bike.global_position.z
	_check(crashed and ejected.size() == before + 1, "9 m/s head-on into a wall ejects the rider exactly once")
	if not crashed:
		wall_scenario = false
		return
	var event: Dictionary = ejected.back().impact
	_check(str(event.severity) == "crash" and str(event.kind) == "structure" and bool(event.ejected), "crash event classifies a structure crash (%s/%s)" % [str(event.severity), str(event.kind)])
	_check(float(event.closing_speed) >= Bicycle.CRASH_SPEED and float(event.incidence_deg) >= 60.0, "closing speed %.2f at %.0f deg decides the crash" % [float(event.closing_speed), float(event.incidence_deg)])
	_check(bool(event.harmless) and is_zero_approx(float(event.body_damage)), "crash event carries no damage")
	var crash = bike.get("_crash")
	_check(player.is_seated() and player.seated_vehicle == crash, "explorer rides the crash rig, so every seated guard stays engaged")
	var status: Dictionary = bike.get_status()
	_check(bike.blocks_checkpoint() and bool(status.crashed) and str(status.prompt).is_empty() and not bool(status.exit_available), "crash blocks checkpoints, riding prompts and dismount")
	_check(str(status.message) == "You came off the bike!", "HUD message tells the player what happened")
	_check(provider.checkpoint_blocker() == "recovering from a bicycle crash", "real checkpoint provider refuses to save mid-crash (%s)" % provider.checkpoint_blocker())
	var load_result: Dictionary = provider.load_state()
	_check(not bool(load_result.get("ok", true)), "real checkpoint provider refuses to load mid-crash")
	_check(not player.puppet.g.visible and crash.get("_pivot").visible, "the tumbling rider rig is shown, the walking puppet hidden")
	await _frames(3)
	# Menus freeze the whole sequence.
	var frozen_center: Vector3 = crash.center
	var frozen_phase: String = crash.phase
	var frozen_time: float = crash.phase_time
	var frozen_anchor: Vector3 = player.global_position
	world.paused = true
	await _frames(30)
	_check(crash.center.is_equal_approx(frozen_center) and crash.phase == frozen_phase and is_equal_approx(crash.phase_time, frozen_time) and player.global_position.is_equal_approx(frozen_anchor), "pause freezes the ejected rider and the explorer")
	world.paused = false
	var phases := {}
	var recovered_before := recovered.size()
	for i in int(Bicycle.MAX_CRASH_TIME / DT) + 90:
		await _frames(1)
		if not bike.is_crashed():
			break
		phases[str(crash.phase)] = true
	_check(not bike.is_crashed() and recovered.size() == recovered_before + 1, "rider stands up within the bounded crash time")
	_check(phases.has("flight") and phases.has("slide") and phases.has("down") and phases.has("getup"), "tumble runs flight, slide, down and getup (%s)" % str(phases.keys()))
	_check(int(audit.rider_overlaps) == 0 and int(audit.rider_past_wall) == 0, "rider sweeps never enter or pass through the wall")
	_check(int(audit.bike_overlaps) == 0, "riderless bicycle never overlaps the wall")
	_check(float(audit.anchor_air) <= 0.06, "explorer anchor stays on the ground through the tumble (%.3f m)" % float(audit.anchor_air))
	_check(int(audit.camera_past_wall) == 0, "chase camera stays on the rider's side of the wall")
	var rig: Dictionary = crash.get_status()
	_check(float(rig.max_height) - float(rig.launch_height) >= 0.15 and int(rig.wall_hits) >= 1, "rider is visibly thrown up and into the wall (rise %.2f, wall hits %d)" % [float(rig.max_height) - float(rig.launch_height), int(rig.wall_hits)])
	_check(not bool(rig.visible), "rider rig hides once the explorer stands")
	if recovered.size() > recovered_before:
		var recovery: Dictionary = recovered.back()
		var stand: Vector3 = recovery.position
		_check(str(recovery.recovery) in ["nearby", "bike_side", "pre_crash"], "recovery uses a verified spot (%s)" % str(recovery.recovery))
		_check(stand.z < WALL_Z - 0.3 and absf(stand.y - 0.05) < 0.06, "explorer stands on the street side of the wall (%s)" % str(stand))
	_check(not player.is_seated() and player.collision_layer == 4 and player.collision_mask == (1 | 2 | 8 | 16), "walking explorer and its collision layers are restored")
	_check(_capsule_clear(player), "explorer capsule is clear where they stand")
	_check(not bike.blocks_checkpoint() and not provider.checkpoint_blocker() in ["recovering from a bicycle crash", "step off your bicycle before saving", "recovering from an impact"],
		"bicycle no longer blocks checkpoints once standing (%s)" % provider.checkpoint_blocker())
	# The riderless bicycle recoiled, slid and fell over instead of stopping dead.
	await _frames(90)
	_check(bike.global_position.z < impact_z - 0.15, "riderless bicycle recoils from the wall (%.2f -> %.2f)" % [impact_z, bike.global_position.z])
	_check(bool(bike.get_status().fallen) and not bool(bike.get("_settling")) and absf(bike.get("_visual").rotation.z) > 1.2, "riderless bicycle falls onto its side and settles")
	_check(bike.get_map_pois().size() == 1, "fallen bicycle stays on the map")
	var near := Vector3.INF
	for side in [1.0, -1.0]:
		var candidate: Vector3 = bike.global_position + Vector3(float(side) * 1.3, 0.05, -0.4)
		if bike._standing_clear(candidate):
			near = candidate
			break
	_check(near.is_finite(), "fixture finds a clear spot beside the fallen bicycle")
	if near.is_finite():
		player.global_position = near
		await _idle(3)
		_check(str(bike.get_status().prompt) == "F · Pick up bicycle", "prompt offers to pick the bicycle up (%s)" % str(bike.get_status().prompt))
		_check(bike.enter_bicycle() and not bool(bike.get_status().fallen) and is_zero_approx(bike.get("_visual").rotation.z), "F picks the fallen bicycle up and rides it upright")
	wall_scenario = false

func _glances() -> void:
	wall_scenario = true
	for spec in [[15.0, 12.0, "bump"], [6.0, 9.0, "scrape"]]:
		var angle := deg_to_rad(float(spec[0]))
		var heading := atan2(cos(angle), sin(angle))
		var tag := "%.0f deg glance at %.0f m/s" % [float(spec[0]), float(spec[1])]
		_check(await _arrange(Vector3(-14.0, 0.0, WALL_Z - 0.28 - 0.8 * sin(angle) - 0.35), heading, float(spec[1])), tag + ": mounted")
		var crashes_before: int = bike.crashes
		var before := impacts.size()
		var x0: float = bike.global_position.x
		for i in 75:
			await _frames(1)
		var first: Dictionary = impacts[before] if impacts.size() > before else {}
		_check(str(first.get("severity", "none")) == str(spec[2]), "%s: low-angle contact is a %s (closing %.2f)" % [tag, str(spec[2]), float(first.get("closing_speed", -1.0))])
		_check(bike.crashes == crashes_before and not bike.is_crashed() and player.seated_vehicle == bike, tag + ": rider stays on")
		_check(bike.global_position.x - x0 > 5.0, "%s: bicycle keeps travelling along the wall (dx %.2f)" % [tag, bike.global_position.x - x0])
		_check(absf(bike.speed) >= float(spec[1]) * 0.5, "%s: glance keeps most of its speed (%.2f)" % [tag, bike.speed])
		_check(bike.yaw > heading + 0.03, "%s: frame swings along the wall (yaw %.2f -> %.2f)" % [tag, heading, bike.yaw])
		_check(int(audit.bike_overlaps) == 0, tag + ": never overlaps the wall")
	wall_scenario = false

func _head_on_bump() -> void:
	_check(await _arrange(Vector3(10.0, 0.0, WALL_Z - 3.0), 0.0, 4.0), "4 m/s head-on: mounted")
	var crashes_before: int = bike.crashes
	var before := impacts.size()
	var touched_z := INF
	var first: Dictionary = {}
	var recoil := 0.0
	var repeats := 0
	for i in 90:
		await _frames(1)
		if first.is_empty() and impacts.size() > before:
			first = impacts[before]
			touched_z = bike.global_position.z
		if not first.is_empty():
			recoil = maxf(recoil, touched_z - bike.global_position.z)
	for index in range(before + 1, impacts.size()):
		var later: Dictionary = impacts[index]
		if int(later.collider_id) == int(first.get("collider_id", -1)) and float(later.time) - float(first.get("time", 0.0)) < Bicycle.IMPACT_DEDUPE:
			repeats += 1
	_check(str(first.get("severity", "none")) == "bump" and bike.crashes == crashes_before and player.seated_vehicle == bike, "4 m/s head-on is a bump; the rider stays on (%s)" % str(first.get("severity", "none")))
	_check(recoil > 0.03, "bump recoils the bicycle instead of a dead stop (%.3f m)" % recoil)
	_check(repeats == 0, "re-touching the same wall inside the dedupe window emits no duplicate event")
	_check(int(audit.bike_overlaps) == 0, "bump never overlaps the wall")

func _parked_car() -> void:
	var car := _box(Vector3(-60.0, 0.95, 0.0), Vector3(4.6, 1.4, 1.9), 2 | 16)
	car.set_meta("parked_vehicle", true)
	car.set_meta("parked_index", 7)
	await _idle(2)
	_check(await _arrange(Vector3(-60.0, 0.0, -5.0), 0.0, 9.0), "parked car: mounted")
	var crashed := await _until_crashed(90)
	_check(crashed, "9 m/s into a parked car's side ejects the rider")
	if not crashed:
		return
	var event: Dictionary = ejected.back().impact
	_check(str(event.kind) == "parked_vehicle" and str(event.vehicle_id) == "parked_007", "parked-car crash names the parked vehicle (%s %s)" % [str(event.kind), str(event.vehicle_id)])
	var recovery := await _until_recovered()
	_check(not recovery.is_empty(), "parked car: rider stands up")
	_check(int(audit.rider_overlaps) == 0 and int(audit.bike_overlaps) == 0, "parked car: neither rider nor bicycle ever overlaps the car")
	if not recovery.is_empty():
		var stand: Vector3 = recovery.position
		_check(stand.y < 0.5 and (absf(stand.x + 60.0) > 2.5 or absf(stand.z) > 1.2), "parked car: explorer stands on the ground beside, not on or in, the car (%s)" % str(stand))
	_check(_capsule_clear(player), "parked car: explorer capsule is clear")
	car.queue_free()
	await _idle(2)

func _moving_cars() -> void:
	var car := DrivenCar.new()
	car.collision_layer = 16
	car.collision_mask = 1 | 2 | 4 | 8 | 16
	car.set_meta("traffic_vehicle", true)
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.9, 1.4, 4.5)
	collider.shape = box
	collider.position = Vector3(0.0, 0.95, 0.0)
	car.add_child(collider)
	world.add_child(car)
	cars.append(car)
	# Rear-ending a car pulling away: 9 vs 8 m/s is a 1 m/s touch.
	car.global_position = Vector3(60.0, 0.0, -36.0)
	await _idle(2)
	_check(await _arrange(Vector3(60.0, 0.0, -39.5), 0.0, 9.0), "moving car (same direction): mounted")
	car.drive = Vector3(0.0, 0.0, 8.0)
	var crashes_before: int = bike.crashes
	var before := impacts.size()
	for i in 45:
		await _frames(1)
	car.drive = Vector3.ZERO
	var touch: Dictionary = impacts[before] if impacts.size() > before else {}
	_check(not touch.is_empty() and str(touch.kind) == "vehicle" and bike.crashes == crashes_before, "rear-ending a car at 9 vs 8 m/s is a touch, not a crash")
	if not touch.is_empty():
		var relative: Vector3 = touch.relative_velocity
		_check(float(touch.closing_speed) > 0.4 and float(touch.closing_speed) < 2.0 and absf(relative.z - float(touch.closing_speed)) < 0.5, "closing speed uses the car's velocity (%.2f)" % float(touch.closing_speed))
	# Head-on into an oncoming car: 4 m/s bicycle + 5 m/s car closes at 9 m/s.
	car.global_position = Vector3(70.0, 0.0, -30.0)
	await _idle(2)
	_check(await _arrange(Vector3(70.0, 0.0, -36.0), 0.0, 4.0), "oncoming car: mounted")
	car.drive = Vector3(0.0, 0.0, -5.0)
	var crashed := await _until_crashed(90)
	car.drive = Vector3.ZERO
	_check(crashed, "4 m/s into a car coming at 5 m/s is a crash (relative velocity)")
	if crashed:
		var event: Dictionary = ejected.back().impact
		var relative: Vector3 = event.relative_velocity
		_check(str(event.kind) == "vehicle" and float(event.closing_speed) >= 8.0 and relative.z >= 8.0, "oncoming crash closes at %.2f m/s" % float(event.closing_speed))
		var recovery := await _until_recovered()
		_check(not recovery.is_empty() and int(audit.rider_overlaps) == 0, "oncoming car: rider recovers without overlapping the car")
	# The same 4 m/s into the same car standing still is only a bump.
	car.global_position = Vector3(80.0, 0.0, -30.0)
	await _idle(2)
	_check(await _arrange(Vector3(80.0, 0.0, -36.0), 0.0, 4.0), "parked traffic car: mounted")
	crashes_before = bike.crashes
	before = impacts.size()
	for i in 60:
		await _frames(1)
	var bump: Dictionary = impacts[before] if impacts.size() > before else {}
	_check(str(bump.get("severity", "none")) == "bump" and bike.crashes == crashes_before, "4 m/s into a stationary car is a bump (%s)" % str(bump.get("severity", "none")))
	cars.erase(car)
	car.queue_free()
	await _idle(2)

func _pedestrian() -> void:
	var person := _box(Vector3(100.0, 0.85, 0.0), Vector3(0.5, 1.7, 0.5), 8)
	person.set_meta("city_crowd_index", 7)
	await _idle(2)
	_check(await _arrange(Vector3(100.0, 0.0, -4.0), 0.0, 6.0), "pedestrian: mounted")
	var crashes_before: int = bike.crashes
	var before := people.size()
	var calls_before := probe.calls.size()
	for i in 90:
		await _frames(1)
	_check(people.size() == before + 1, "pedestrian contact emits exactly once inside its cooldown (%d)" % (people.size() - before))
	if people.size() > before:
		var contact: Dictionary = people[before]
		var impulse: Vector3 = contact.impulse
		var normal: Vector3 = contact.normal
		var closing := float(contact.relative_speed)
		_check(contact.collider == person and int(contact.crowd_index) == 7 and str(contact.actor_id) == "crowd_7", "payload identifies the person (crowd_7)")
		_check(bool(contact.harmless) and is_zero_approx(float(contact.body_damage)) and str(contact.source) == "bicycle", "payload is harmless")
		_check(closing > 5.0 and closing < 6.6 and float(contact.speed) > 5.0, "payload carries the closing speed (%.2f)" % closing)
		_check(is_zero_approx(impulse.y) and impulse.z > 0.0 and absf(impulse.length() - Bicycle.REDUCED_MASS * closing) < 0.5 and is_equal_approx(float(contact.impulse_magnitude), impulse.length()),
			"impulse pushes the person along the bicycle's travel (%s)" % str(impulse))
		_check(normal.z < -0.9 and is_zero_approx(normal.y), "normal points from the person to the bicycle")
		_check(bool(contact.knockdown_hint), "hard contact hints a knockdown")
		_check(probe.calls.size() == calls_before + 1, "root bridge reaches knockdown_from_bicycle once")
		if probe.calls.size() > calls_before:
			var invocation: Dictionary = probe.calls.back()
			_check(invocation.target == person and is_equal_approx(float(invocation.speed), closing) and Vector3(invocation.impulse).is_equal_approx(impulse) and str(invocation.context.source) == "bicycle",
				"bridge passes collider, closing speed, impulse and context")
	_check(bike.crashes == crashes_before and player.seated_vehicle == bike, "people are knocked down, the rider is never ejected by them")
	_check(absf(bike.speed) <= 0.8 and bike.global_position.z < 0.0, "the person absorbs the bicycle; it never rides through them")
	var combat_script := load("res://scripts/city/city_combat.gd") as Script
	var found := false
	if combat_script != null:
		for method in combat_script.get_script_method_list():
			if str(method.get("name", "")) == "knockdown_from_bicycle" and (method.get("args", []) as Array).size() >= 3:
				found = true
	_check(found, "real city_combat.gd exposes knockdown_from_bicycle(target, contact_speed, impulse, context)")
	person.queue_free()
	await _idle(2)

func _forced_releases() -> void:
	wall_scenario = true
	_check(await _arrange(Vector3(-10.0, 0.0, 0.5), 0.0, 9.0), "forced release: mounted")
	if await _until_crashed(90):
		_check(not bike.exit_vehicle() and bike.is_crashed(), "ordinary F dismount is refused while tumbling")
		var before := recovered.size()
		_check(bike.exit_vehicle(true) and not bike.is_crashed() and not player.is_seated(), "forced (law) release ends the crash at a verified spot")
		_check(recovered.size() == before + 1 and str(recovered.back().recovery) == "forced", "forced release reports its kind")
		await _idle(2)
		_check(_capsule_clear(player) and player.global_position.z < WALL_Z - 0.3, "forced release stands the explorer clear, on the street side")
	else:
		_check(false, "forced release: crash did not happen")
	_check(await _arrange(Vector3(-4.0, 0.0, 0.5), 0.0, 9.0), "relocation: mounted")
	if await _until_crashed(90):
		var target := Vector3(-30.0, 0.05, -20.0)
		_check(bike.recovery_exit_at(target, 1.0) and not bike.is_crashed() and not player.is_seated() and player.global_position.is_equal_approx(target), "checkpoint relocation ends the crash at the requested point")
		_check(str(recovered.back().recovery) == "relocated", "relocation reports its kind")
	else:
		_check(false, "relocation: crash did not happen")
	wall_scenario = false
