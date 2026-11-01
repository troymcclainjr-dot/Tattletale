extends Node
## Actual exported city, actual bicycle, normal root physics tick. A queued save
## requested through the level's own save_progress() while really riding is
## written once the bicycle has really stopped; a real hop and an impact recovery
## are refused; the checkpoint restores the explorer onto the real bicycle at the
## saved pose, or (pose physically blocked) standing at the checked spot with the
## bicycle re-parked clear of them. Arrangement (where riding starts, moving the
## explorer between phases) uses public APIs; riding uses the bicycle's control
## override, as the bicycle fixtures do. The level's normal tick drives this
## isolated provider; every phase stays inside one 30 s autosave interval.
## Slot: .work/five-priorities-20261101/mounted-save-city/world.json (never the user's).
## Run: --headless --script res://tests/city_mounted_save_city.gd
const Save := preload("res://scripts/city/city_world_save.gd")
const Mounted := preload("res://scripts/city/city_bicycle_checkpoint.gd")
var passes := 0
var failures := 0
var finished := false
var level: Node3D
var player: CharacterBody3D
var bike: CharacterBody3D
var provider: Node
var fixture := ""
var resolved: Array = []

class CountingSave extends "res://scripts/city/city_world_save.gd":
	var writes := 0
	var reads := 0
	func write_snapshot(state: Dictionary) -> Error:
		writes += 1
		return super.write_snapshot(state)
	func _read(source: String) -> Dictionary:
		reads += 1
		return super._read(source)

func _ready() -> void:
	_run.call_deferred()
	_watchdog()

func _watchdog() -> void:
	await get_tree().create_timer(600.0, true, false, true).timeout
	if not finished:
		check(false, "mounted city fixture completes within 600 seconds")
		_finish()

func check(ok: bool, label: String) -> bool:
	print("[mounted_city] %s %s" % ["PASS" if ok else "FAIL", label])
	passes += int(ok)
	failures += int(not ok)
	return ok

func frames(count: int) -> void:
	for index in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _run() -> void:
	if DisplayServer.get_name() != "headless" and not "--offscreen-validation" in OS.get_cmdline_user_args():
		check(false, "requires --headless or --offscreen-validation (never a user session)")
		_finish()
		return
	fixture = ProjectSettings.globalize_path("res://../.work/five-priorities-20261101/mounted-save-city/world.json")
	DirAccess.make_dir_recursive_absolute(fixture.get_base_dir())
	_cleanup()
	if not await _boot():
		_finish()
		return
	if not await _mount():
		_finish()
		return
	var saved: Dictionary = await _queued_while_riding()
	if saved.is_empty():
		_finish()
		return
	await _airborne_and_recovery_denied()
	await _remount_restore(saved)
	await _blocked_restore(saved)
	await _walking_reparks()
	bike.clear_control_override()
	_cleanup()
	_finish()

func _boot() -> bool:
	get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn")
	await frames(4)
	for index in 1800:
		level = get_tree().current_scene as Node3D
		if level != null and level.get("level_ready") == true:
			break
		await frames(1)
	if not check(level != null and level.get("level_ready") == true, "actual exported world boots"):
		return false
	level.pause_exploring()
	for index in 600:
		if int(level.residents.get_status().pending_routes) == 0:
			break
		await frames(1)
	player = level.player
	bike = level.bicycle as CharacterBody3D
	check(not level.world_save.enabled, "production user-slot provider stays disabled")
	provider = CountingSave.new()
	level.add_child(provider)
	provider.setup(level, fixture)
	# The level's normal physics tick and its save_progress() now reach only this slot.
	level.world_save = provider
	provider.pending_save_resolved.connect(func(result: Dictionary): resolved.append(result))
	provider.pending_save_resolved.connect(Callable(level, "_on_pending_save_resolved"))
	return check(provider.enabled and bike != null and bike.spawned and Mounted.api(level) != null and provider.get_status().mounted_checkpoints,
		"isolated provider enabled; the actual bicycle publishes the persistence hooks")

## A checked standing spot `radius` from the bicycle on its side of every wall.
func _spot_near(radius: float, avoid: Vector3 = Vector3.INF) -> Vector3:
	var space := level.get_world_3d().direct_space_state
	for step in 12:
		var angle := float(step) * TAU / 12.0
		var spot: Dictionary = provider.safe_player_position(bike.global_position + Vector3(sin(angle), 0.0, cos(angle)) * radius)
		if spot.is_empty():
			continue
		var point: Vector3 = spot.position
		if avoid.is_finite() and Vector2(point.x - avoid.x, point.z - avoid.z).length() < 2.6:
			continue
		var ray := PhysicsRayQueryParameters3D.create(bike.global_position + Vector3.UP, point + Vector3.UP, 1 | 2)
		ray.exclude = [player.get_rid(), bike.get_rid()]
		if space.intersect_ray(ray).is_empty():
			return point
	return Vector3.INF

func _mount() -> bool:
	if player.phone != null:
		player.phone.close()
	level.basketball.suspend(true)
	level.resume_exploring()
	var stand := _spot_near(1.3)
	if not check(stand.is_finite(), "a checked standing spot beside the parked bicycle"):
		return false
	provider._put_player(stand, atan2(bike.global_position.x - stand.x, bike.global_position.z - stand.z))
	bike.set_control_override(Vector2.ZERO, true)
	await frames(6)
	return check(bike.enter_bicycle() and bike.active and player.is_seated() and player.seated_vehicle == bike, "explorer mounts the actual bicycle")

## Explorer capsule against structures and vehicles, the bicycle included.
## People (layer 8) keep walking during the fixture, so they are not probed here.
func _standing_clear(at: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.30
	shape.height = 1.72
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.87)
	query.collision_mask = 2 | 16
	query.exclude = [player.get_rid()]
	return level.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _queued_while_riding() -> Dictionary:
	bike.set_control_override(Vector2(0.0, 0.6))
	var moving := false
	for index in 60:
		await frames(1)
		if absf(bike.speed) > 0.4:
			moving = true
			break
	if not check(moving, "the actual bicycle is pedalled up to speed (%.2f m/s)" % bike.speed):
		return {}
	var reason: String = provider.checkpoint_blocker()
	var direct: int = provider.save_state()
	var message: String = level.save_progress()
	for index in 3:
		level.save_progress()
	check(reason == "stop the bicycle before saving" and direct == ERR_BUSY and provider.writes == 0 and provider.reads == 0,
		"a moving rider cannot be checkpointed (%s)" % reason)
	check(message == "Save queued until it is safe: stop the bicycle before saving." and provider.get_status().pending.active
		and provider.get_status().pending.source == "manual", "the level's save_progress() queues with the truthful reason (%s)" % message)
	check(provider.writes == 0 and provider.reads == 0 and bike.active and player.is_seated(), "repeated requests coalesce; nobody is dismounted to fake a save")
	bike.set_control_override(Vector2.ZERO, true)
	var safe_frame := -1
	var write_frame := -1
	for index in 240:
		await frames(1)
		if safe_frame < 0 and str(bike.save_blocker()).is_empty():
			safe_frame = index
		if provider.writes > 0:
			write_frame = index
			break
	check(write_frame >= 0 and provider.writes == 1 and not provider.get_status().pending.active,
		"the queued save is written exactly once after the bicycle stops (%d writes)" % provider.writes)
	var poll_frames := ceili(Save.POLL_SECONDS * Engine.physics_ticks_per_second) + 3
	check(safe_frame >= 0 and write_frame - safe_frame <= poll_frames,
		"it is written within one 0.25 s poll of the stop (%d frames, bound %d)" % [write_frame - safe_frame, poll_frames])
	check(resolved.size() == 1 and resolved[0].state == "saved" and resolved[0].source == "manual", "one completion notice for the queued manual save")
	var parser := JSON.new()
	if not check(FileAccess.file_exists(fixture) and parser.parse(FileAccess.get_file_as_string(fixture)) == OK and parser.data is Dictionary,
		"the checkpoint file is written"):
		return {}
	var saved: Dictionary = parser.data
	if not check(saved.get("bicycle") is Dictionary and int(saved.version) == Save.VERSION and provider.validate_snapshot(saved).is_empty(),
		"the file is a valid schema-4 checkpoint with a bicycle section"):
		return {}
	var seat := Vector3(float(saved.bicycle.position[0]), float(saved.bicycle.position[1]), float(saved.bicycle.position[2]))
	var stand := Vector3(float(saved.player.position[0]), float(saved.player.position[1]), float(saved.player.position[2]))
	check(seat.distance_to(bike.global_position) < 0.02 and absf(angle_difference(float(saved.bicycle.yaw), bike.yaw)) < 0.001,
		"the saved pose is where the bicycle actually stopped")
	check(Mounted.footprint_gap(stand, seat, float(saved.bicycle.yaw)) >= Mounted.STAND_RADIUS and _standing_clear(stand),
		"the saved explorer spot stands clear of the actual bicycle collider")
	var overlap: Dictionary = saved.duplicate(true)
	overlap.player.position = saved.bicycle.position.duplicate()
	check(provider.validate_snapshot(overlap) == "saved explorer overlaps the bicycle", "a file standing the explorer on the seat is rejected")
	return saved

func _airborne_and_recovery_denied() -> void:
	var writes: int = provider.writes
	bike.set_control_override(Vector2.ZERO, false, false, true)
	var airborne := false
	var reason := ""
	for index in 20:
		await frames(1)
		if bool(bike.get_status().airborne):
			airborne = true
			reason = provider.checkpoint_blocker()
			break
	check(airborne and reason == "land the bicycle before saving" and provider.save_state() == ERR_BUSY,
		"a real hop cannot be checkpointed (%s)" % reason)
	bike.set_control_override(Vector2.ZERO, true)
	for index in 120:
		await frames(1)
		if not bool(bike.get_status().airborne) and str(bike.save_blocker()).is_empty():
			break
	player.impact_recovery = 0.6
	reason = provider.checkpoint_blocker()
	player.impact_recovery = 0.0
	check(reason == "recovering from an impact" and provider.writes == writes, "impact recovery still blocks a checkpoint")

## Explorer walks off and the bicycle is parked elsewhere: away from `seat`, and
## clear of the saved standing spot so the load's own placement is what is tested.
func _scatter(seat: Vector3, stand: Vector3) -> bool:
	if bike.active and not bike.exit_vehicle():
		bike.restore_pose(bike.global_position, bike.yaw, false)
	if bike.active:
		return false
	for attempt in 3:
		var away := _spot_near(3.6 + attempt, seat)
		if not away.is_finite():
			continue
		provider._put_player(away, player.yaw)
		var parked: Dictionary = bike.park_beside_explorer()
		await frames(3)
		if bool(parked.get("ok", false)) and bike.global_position.distance_to(seat) > 1.0 \
			and Mounted.footprint_gap(stand, bike.global_position, bike.yaw) >= 0.6:
			return true
	return false

func _remount_restore(saved: Dictionary) -> void:
	var seat := Vector3(float(saved.bicycle.position[0]), float(saved.bicycle.position[1]), float(saved.bicycle.position[2]))
	var stand := Vector3(float(saved.player.position[0]), float(saved.player.position[1]), float(saved.player.position[2]))
	if not check(await _scatter(seat, stand), "explorer and bicycle moved away from the saved pose"):
		return
	var result: Dictionary = provider.load_state()
	await frames(2)
	check(result.get("ok", false) and str(result.get("bicycle", {}).get("state", "")) == "mounted" and not result.get("player_fallback", true),
		"the checkpoint restores the explorer onto the actual bicycle (%s)" % str(result.get("reason", "")))
	var facts: Dictionary = bike.persistence_state()
	var at: Vector3 = facts.position
	check(bike.active and player.is_seated() and player.seated_vehicle == bike and Vector2(at.x - seat.x, at.z - seat.z).length() < 0.02
		and absf(at.y - seat.y) < 0.06 and absf(angle_difference(bike.yaw, float(saved.bicycle.yaw))) < 0.01,
		"bicycle and rider are at the saved pose and heading")
	check(is_equal_approx(float(player.chase_distance), 4.8) and absf(bike.speed) < 0.001 and bool(facts.grounded) and not bool(facts.airborne),
		"restored as a normal stopped mount: riding camera, grounded, no motion")
	bike.set_control_override(Vector2.ZERO, true)
	await frames(30)
	check(bike.active and player.is_seated() and provider.checkpoint_blocker().is_empty(), "the restored rider stays seated and may checkpoint again")

func _blocked_restore(saved: Dictionary) -> void:
	var seat := Vector3(float(saved.bicycle.position[0]), float(saved.bicycle.position[1]), float(saved.bicycle.position[2]))
	var stand := Vector3(float(saved.player.position[0]), float(saved.player.position[1]), float(saved.player.position[2]))
	if not check(await _scatter(seat, stand), "explorer and bicycle moved away again"):
		return
	# A solid post where the bicycle stood; the checked standing spot stays open.
	var post := StaticBody3D.new()
	post.collision_layer = 2
	post.collision_mask = 0
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 1.2, 0.4)
	var shape := CollisionShape3D.new()
	shape.shape = box
	post.add_child(shape)
	level.add_child(post)
	post.global_position = seat + Vector3.UP * 0.9
	await frames(3)
	var result: Dictionary = provider.load_state()
	await frames(2)
	var bicycle: Dictionary = result.get("bicycle", {})
	check(result.get("ok", false) and str(bicycle.get("state", "")) == "standing" and result.get("player_fallback", false)
		and not player.is_seated() and not bike.active, "a physically blocked saved pose restores the explorer standing (%s)" % str(bicycle.get("reason", "")))
	check(player.global_position.distance_to(stand) < 0.1 and "you start standing" in str(provider.last_result),
		"standing at the saved checked spot, with the fallback explained (%s)" % provider.last_result)
	check(str(bicycle.get("parked", "")) == "parked" and _standing_clear(player.global_position)
		and Mounted.footprint_gap(player.global_position, bike.global_position, bike.yaw) >= Mounted.STAND_RADIUS,
		"the bicycle is re-parked beside the explorer without overlapping them")
	post.queue_free()
	await frames(3)

func _walking_reparks() -> void:
	if player.is_seated():
		return
	var writes: int = provider.writes
	check(provider.save_state() == OK and provider.writes == writes + 1, "a standing checkpoint is written")
	var parser := JSON.new()
	var walking: Variant = parser.data if parser.parse(FileAccess.get_file_as_string(fixture)) == OK else null
	check(walking is Dictionary and not walking.has("bicycle"), "a standing checkpoint carries no bicycle section")
	var here: Vector3 = player.global_position
	var away := _spot_near(4.0, here)
	if away.is_finite():
		provider._put_player(away, player.yaw)
		bike.park_beside_explorer()
		await frames(3)
	var result: Dictionary = provider.load_state()
	await frames(2)
	check(result.get("ok", false) and str(result.get("bicycle", {}).get("state", "")) == "parked" and not player.is_seated()
		and bike.global_position.distance_to(player.global_position) < 5.5 and _standing_clear(player.global_position),
		"loading it re-parks the bicycle beside the restored explorer")

func _cleanup() -> void:
	if fixture.is_empty() or not DirAccess.dir_exists_absolute(fixture.get_base_dir()):
		return
	for entry_name in DirAccess.get_files_at(fixture.get_base_dir()):
		if entry_name == fixture.get_file() or entry_name.begins_with(fixture.get_file() + "."):
			DirAccess.remove_absolute(fixture.get_base_dir().path_join(entry_name))

func _finish() -> void:
	if finished:
		return
	finished = true
	print("[mounted_city] %d passed, %d failed" % [passes, failures])
	get_tree().quit(1 if failures else 0)
