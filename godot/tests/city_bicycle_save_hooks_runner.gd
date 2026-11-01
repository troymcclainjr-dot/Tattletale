extends Node3D
## Root serializes engine runs. The bicycle's checkpoint hooks
## (.work/five-priorities-20261101/bicycle-save-contract.md sections 2-3) with
## the real city_player.gd explorer and the real bicycle: truthful save_blocker
## reasons through riding, braking, a hop, a knock and a crash; pose_blocker on
## walls, people, car roofs and missing ground; restore_pose and
## park_beside_explorer outcomes, with every refusal leaving the world alone.
## Start poses and speeds are API arranged; everything after is production code.
## The save worker's own fixtures cover the checkpoint file and load order.
const Bicycle := preload("res://scripts/city/city_bicycle.gd")
const Player := preload("res://scripts/city/city_player.gd")
const DT := 1.0 / 60.0
const WALL_Z := 30.0
const PRESSED := "something is pressing against the bicycle"
const NO_GROUND := "no stable ground under the bicycle"

class Fixture extends Node3D:
	var paused := false
	var offscreen_validation := false
	var player: CharacterBody3D
	var combat: Node3D
	var bicycle: CharacterBody3D

## The explorer's phone held up (photo mode): riding must not start under it.
class PhoneUp extends Node3D:
	var active := true
	var photo_fov := 50.0

var world: Fixture
var bike: CharacterBody3D
var player: CharacterBody3D
var errors: Array[String] = []
var checks := 0
var mounts := 0
var dismounts := 0

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors.append(message)
		push_error(message)
	print("BIKE_SAVE_HOOKS ", "PASS " if ok else "FAIL ", message)

func _run() -> void:
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	world = Fixture.new()
	add_child(world)
	_box(Vector3(0.0, -0.25, 0.0), Vector3(400.0, 0.5, 400.0), 1)
	_box(Vector3(0.0, 1.5, WALL_Z + 0.3), Vector3(30.0, 3.0, 0.6), 2)
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
	bike.mounted.connect(func(): mounts += 1)
	bike.dismounted.connect(func(): dismounts += 1)
	await _riding_reasons()
	await _hop_reason()
	await _knock_reasons()
	await _crash_reasons()
	await _pose_checks()
	await _restores()
	await _refusals()
	await _park_beside()
	print("CITY_BICYCLE_SAVE_HOOKS ", "PASS" if errors.is_empty() else "FAIL", " checks=", checks, " failures=", errors.size())
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

func _idle(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		bike.tick(DT)

## Ends any ride or crash and stands the explorer at `at` (between scenarios only).
func _stand_at(at: Vector3, heading: float) -> void:
	if bike.active:
		bike.recovery_exit_at(at, heading)
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.yaw = heading
	await _idle(3)

## Between scenarios only: park the bicycle at `at`, stand the explorer beside
## it and mount with the real enter_bicycle().
func _mount(at: Vector3, heading: float) -> bool:
	await _stand_at(at - Vector3(cos(heading), 0.0, -sin(heading)) * 1.3 + Vector3.UP * 0.05, heading)
	bike.global_position = at
	bike.yaw = heading
	bike.rotation.y = heading
	bike.reset_motion_state()
	bike.speed = 0.0
	bike.set_control_override(Vector2.ZERO, true)
	await _idle(2)
	return bike.enter_bicycle() and bike.active

# ------------------------------------------------------------------ save_blocker

func _riding_reasons() -> void:
	_check(bike.spawned and not bike.active, "the real bicycle is parked")
	_check(bike.save_blocker() == "", "a parked bicycle never blocks a checkpoint (%s)" % bike.save_blocker())
	var facts: Dictionary = bike.persistence_state()
	_check(int(facts.version) == Bicycle.SAVE_VERSION and bool(facts.spawned) and not bool(facts.mounted) and not bool(facts.crashed)
		and Vector3(facts.position).is_equal_approx(bike.global_position) and is_equal_approx(float(facts.yaw), float(bike.yaw)) and str(facts.blocker) == "",
		"persistence_state reports the parked bicycle truthfully")
	_check(await _mount(Vector3(-20.0, 0.0, -20.0), 0.0), "the explorer mounts with the real F path")
	_check(bike.save_blocker() == "", "a rider sitting still on level ground may checkpoint (%s)" % bike.save_blocker())
	facts = bike.persistence_state()
	_check(bool(facts.mounted) and bool(facts.grounded) and not bool(facts.airborne) and bool(facts.steady)
		and absf(float(facts.speed)) <= Bicycle.SAVE_STILL_SPEED and float(facts.planar_speed) <= Bicycle.SAVE_STILL_SPEED,
		"a still rider's facts agree: mounted, grounded, steady and still")
	bike.set_control_override(Vector2(0.0, 1.0))
	await _frames(30)
	_check(bike.save_blocker() == "stop the bicycle before saving", "a moving rider is refused with the truthful reason (%s)" % bike.save_blocker())
	_check(not bike.blocks_checkpoint(), "blocks_checkpoint stays crash-only while riding")
	bike.set_control_override(Vector2.ZERO, true)
	var cleared := -1
	var early := false
	for i in 120:
		await _frames(1)
		var reason: String = bike.save_blocker()
		var moving: bool = absf(float(bike.speed)) > Bicycle.SAVE_STILL_SPEED or Vector2(bike.velocity.x, bike.velocity.z).length() > Bicycle.SAVE_STILL_SPEED
		if reason.is_empty():
			early = moving
			cleared = i
			break
	_check(not early, "save_blocker never clears while the bicycle still moves")
	_check(cleared >= 0, "braking to a stop makes the rider saveable again (%d frames)" % cleared)

func _hop_reason() -> void:
	_check(await _mount(Vector3(-30.0, 0.0, -20.0), 0.0), "hop: mounted")
	bike.set_control_override(Vector2.ZERO, false, false, true)
	await _frames(4)
	_check(bool(bike.get_status().airborne) and bike.save_blocker() == "land the bicycle before saving", "a rider in the air is refused as airborne (%s)" % bike.save_blocker())
	bike.set_control_override(Vector2.ZERO, true)
	await _frames(70)
	_check(not bool(bike.get_status().airborne) and bike.save_blocker() == "", "once landed and still the rider is saveable again (%s)" % bike.save_blocker())

func _knock_reasons() -> void:
	_check(await _mount(Vector3(0.0, 0.0, WALL_Z - 3.0), 0.0), "knock: mounted facing the wall")
	bike.speed = 4.0
	bike.set_control_override(Vector2(0.0, 4.0 / Bicycle.MAX_SPEED))
	var before: int = bike.impacts
	var bumped := false
	for i in 90:
		await _frames(1)
		if bike.impacts > before:
			bumped = true
			break
	_check(bumped and str(bike.last_impact.get("severity", "")) == "bump" and not bike.is_crashed(), "knock: 4 m/s into the wall is a bump and the rider stays on")
	bike.set_control_override(Vector2.ZERO, true)
	var seen := {}
	var cleared := -1
	for i in 150:
		var reason: String = bike.save_blocker()
		seen[reason] = true
		if reason.is_empty():
			cleared = i
			break
		await _frames(1)
	_check(seen.has("steady the bicycle before saving"), "a fresh knock is reported truthfully while the bicycle recovers (%s)" % str(seen.keys()))
	_check(cleared >= 24 and cleared <= 120, "the knock holds the checkpoint about half a second, then clears (%d frames)" % cleared)

func _crash_reasons() -> void:
	_check(await _mount(Vector3(6.0, 0.0, WALL_Z - 6.0), 0.0), "crash: mounted facing the wall")
	bike.speed = 9.0
	bike.set_control_override(Vector2(0.0, 1.0))
	var crashed := false
	for i in 90:
		await _frames(1)
		if bike.is_crashed():
			crashed = true
			break
	_check(crashed, "crash: 9 m/s into the wall ejects the rider")
	if not crashed:
		return
	_check(bike.blocks_checkpoint() and bike.save_blocker() == "recovering from a bicycle crash", "a crash blocks with the existing crash reason")
	var pose: Vector3 = bike.global_position
	var mounts_before := mounts
	var refused: Dictionary = bike.restore_pose(Vector3(6.0, 0.0, 0.0), 0.0, true)
	_check(not bool(refused.ok) and str(refused.reason) == "recovering from a bicycle crash" and bike.is_crashed()
		and bike.global_position.is_equal_approx(pose) and mounts == mounts_before, "restore_pose refuses mid-crash and changes nothing")
	# A forced (law) release ends the crash while the riderless bicycle still slides.
	_check(bike.exit_vehicle(true) and not bike.is_crashed(), "crash: a forced release stands the explorer up")
	_check(bike.save_blocker() == "your bicycle is still settling", "a riderless bicycle still sliding after a crash is reported as settling (%s)" % bike.save_blocker())
	var settled := false
	for i in 240:
		await _frames(1)
		if bike.save_blocker().is_empty():
			settled = true
			break
	_check(settled and not bool(bike.persistence_state().settling), "once the riderless bicycle is at rest it no longer blocks")
	_check(bool(bike.persistence_state().fallen), "persistence_state reports the bicycle lying on its side")

# ------------------------------------------------------------------ pose_blocker

func _pose_checks() -> void:
	await _stand_at(Vector3(-60.0, 0.05, -60.0), 0.0)
	var open := Vector3(-40.0, 0.0, -40.0)
	_check(bike.pose_blocker(open, 0.3).is_empty(), "an open level pose is accepted (%s)" % bike.pose_blocker(open, 0.3))
	_check(bike.pose_blocker(Vector3(0.0, 0.0, WALL_Z + 0.3), 0.0) == PRESSED, "a pose inside a wall is refused")
	_check(bike.pose_blocker(open + Vector3.UP * 2.0, 0.0) == NO_GROUND, "a pose two metres above the ground is refused")
	_check(bike.pose_blocker(Vector3(INF, 0.0, 0.0), 0.0) == "invalid bicycle pose", "a non-finite pose is refused")
	var person := _box(Vector3(-50.0, 0.85, -40.0), Vector3(0.5, 1.7, 0.5), 8)
	var car := _box(Vector3(-56.0, 0.95, -40.0), Vector3(1.9, 1.4, 4.6), 2 | 16)
	car.set_meta("parked_vehicle", true)
	await _idle(2)
	_check(bike.pose_blocker(Vector3(-50.0, 0.0, -40.0), 0.0) == PRESSED, "a person standing there refuses the pose")
	_check(bike.pose_blocker(Vector3(-56.0, 1.65, -40.0), 0.0) == NO_GROUND, "a parked car's roof is never wheel support")
	var feet: Vector3 = player.global_position
	var over := Vector3(feet.x, 0.0, feet.z - 0.3)
	_check(bike.pose_blocker(over, 0.0, true) == PRESSED, "counting the explorer, a pose on top of them is refused")
	_check(bike.pose_blocker(over, 0.0).is_empty(), "the same pose is clear of the world itself")
	person.queue_free()
	car.queue_free()
	await _idle(2)

# ------------------------------------------------------------------ restore_pose

func _restores() -> void:
	# A mounted restore seats a standing explorer at the saved pose (here > 3 m away).
	bike.set_control_override(Vector2.ZERO, true)
	await _stand_at(Vector3(-90.0, 0.05, -40.0), 0.0)
	var mounts_before := mounts
	var target := Vector3(-100.0, 0.0, -60.0)
	var result: Dictionary = bike.restore_pose(target, 0.7, true)
	_check(bool(result.ok) and bike.active and player.is_seated() and player.seated_vehicle == bike and mounts == mounts_before + 1,
		"a mounted restore seats the explorer on the bicycle (%s)" % str(result.reason))
	_check(Vector2(bike.global_position.x - target.x, bike.global_position.z - target.z).length() < 0.001 and absf(bike.global_position.y) < 0.02
		and is_equal_approx(float(bike.yaw), 0.7), "the bicycle sits at the saved pose, settled on the ground")
	_check(player.global_position.distance_to(bike.global_position) < 0.001, "the explorer rides at the bicycle origin")
	var facts: Dictionary = bike.persistence_state()
	_check(bool(facts.mounted) and bool(facts.grounded) and not bool(facts.airborne) and absf(float(facts.speed)) < 0.0001
		and float(facts.planar_speed) < 0.0001 and str(facts.blocker).is_empty(), "the restored ride reports mounted, grounded and still (%s)" % str(facts.blocker))
	_check(absf(angle_difference(float(player.camera_yaw), 0.7)) < 0.001, "the chase view starts behind the restored heading")
	var seat: Vector3 = bike.global_position
	await _frames(30)
	_check(bike.active and player.is_seated() and bike.global_position.distance_to(seat) < 0.005, "the restored ride survives ticking: no relocation dismount, no drift")
	# Moving a rider who is already mounted moves both, without remounting.
	var second := Vector3(-110.0, 0.0, -60.0)
	result = bike.restore_pose(second, -0.4, true)
	_check(bool(result.ok) and bike.active and Vector2(bike.global_position.x - second.x, bike.global_position.z - second.z).length() < 0.001
		and player.global_position.distance_to(bike.global_position) < 0.001 and mounts == mounts_before + 1,
		"an already-mounted rider is moved with the bicycle, not remounted")
	await _frames(10)
	_check(bike.active and player.is_seated(), "the moved rider stays seated")
	# Round trip: what persistence_state reports is what restore_pose puts back.
	var saved: Dictionary = bike.persistence_state()
	bike.set_control_override(Vector2(0.4, 1.0))
	await _frames(40)
	bike.set_control_override(Vector2.ZERO, true)
	await _frames(90)
	result = bike.restore_pose(Vector3(saved.position), float(saved.yaw), true)
	facts = bike.persistence_state()
	var drift := Vector3(facts.position) - Vector3(saved.position)
	_check(bool(result.ok) and Vector2(drift.x, drift.z).length() <= 0.02 and absf(drift.y) <= 0.06
		and absf(angle_difference(float(facts.yaw), float(saved.yaw))) <= 0.01, "round trip: the restored ride matches the saved facts within the save's tolerances")
	# A parked restore while riding steps the explorer off, clear of the new pose.
	var dismounts_before := dismounts
	result = bike.restore_pose(Vector3(-120.0, 0.0, -60.0), 0.0, false)
	_check(bool(result.ok) and not bike.active and not player.is_seated() and dismounts == dismounts_before + 1, "a parked restore steps a seated rider off first")
	_check(player.collision_layer == 4 and bike.pose_blocker(bike.global_position, bike.yaw, true).is_empty(), "the explorer walks again, clear of the restored bicycle")
	# A fallen bicycle restores lying on its side and is picked up with F.
	result = bike.restore_pose(Vector3(-130.0, 0.0, -60.0), 1.0, false, true)
	_check(bool(result.ok) and bool(result.fallen) and bool(bike.get_status().fallen), "a fallen bicycle restores lying on its side")
	player.global_position = bike.global_position + Vector3(1.6, 0.05, 0.0)
	await _idle(3)
	_check(str(bike.get_status().prompt) == "F · Pick up bicycle", "the explorer is offered to pick it up (%s)" % str(bike.get_status().prompt))
	_check(bike.enter_bicycle() and not bool(bike.get_status().fallen), "F picks it up and rides it upright")

func _refusals() -> void:
	_check(bike.exit_vehicle(), "the stopped rider gets off")
	var pose: Vector3 = bike.global_position
	var heading: float = bike.yaw
	var mounts_before := mounts
	var result: Dictionary = bike.restore_pose(Vector3(0.0, 0.0, WALL_Z + 0.3), 0.0, true)
	_check(not bool(result.ok) and str(result.reason) == PRESSED and not bike.active and bike.global_position.is_equal_approx(pose)
		and is_equal_approx(float(bike.yaw), heading) and mounts == mounts_before, "a pose inside a wall is refused and nothing changes")
	var feet: Vector3 = player.global_position
	result = bike.restore_pose(Vector3(feet.x, 0.0, feet.z + 0.2), 0.0, false)
	_check(not bool(result.ok) and str(result.reason) == PRESSED and bike.global_position.is_equal_approx(pose), "a parked pose on top of the standing explorer is refused")
	var phone := PhoneUp.new()
	world.add_child(phone)
	player.phone = phone
	result = bike.restore_pose(Vector3(-140.0, 0.0, -60.0), 0.0, true)
	_check(not bool(result.ok) and str(result.reason) == "put away the phone before riding" and not bike.active
		and bike.global_position.is_equal_approx(pose) and phone.active, "a mounted restore with the phone up is refused and the phone is left alone")
	player.phone = null
	phone.queue_free()
	await _idle(2)

# ------------------------------------------------------------------ park_beside_explorer

func _park_beside() -> void:
	_check(await _mount(Vector3(-150.0, 0.0, -60.0), 0.0), "park: mounted")
	var mounted_at: Vector3 = bike.global_position
	var refused: Dictionary = bike.park_beside_explorer()
	_check(not bool(refused.ok) and bike.active and bike.global_position.is_equal_approx(mounted_at), "park_beside_explorer refuses while ridden and changes nothing")
	_check(bike.exit_vehicle(), "park: the rider gets off")
	await _stand_at(Vector3(60.0, 0.05, -100.0), 1.1)
	var parked: Dictionary = bike.park_beside_explorer()
	var gap := Vector2(bike.global_position.x - player.global_position.x, bike.global_position.z - player.global_position.z).length()
	_check(bool(parked.ok) and not bike.active and gap >= 2.0 and gap <= 5.1, "the bicycle is re-parked beside where the explorer now stands (%.2f m)" % gap)
	_check(bike._hull_clear(bike.global_transform, 0.0, 0.02) and not bool(bike.get_status().fallen) and bike.save_blocker().is_empty(), "the re-parked bicycle is upright, clear and saveable")
	_check(is_equal_approx(float(bike.yaw), 1.1), "it faces the explorer's heading, as setup parks it")
	_check(bike.get_map_pois().size() == 1, "the re-parked bicycle is on the map")
