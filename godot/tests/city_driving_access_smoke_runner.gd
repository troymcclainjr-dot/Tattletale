extends "res://tests/city_driving_smoke_runner.gd"
## Focused production collision checks; reuses only the existing fixture helpers.
## No full world, authored assets, or gameplay-manager doubles are required.

func _run() -> void:
	G.built = false
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	world = Node3D.new()
	add_child(world)
	box("Ground", Vector3(0, -0.5, 0), Vector3(100, 1, 100), 1)
	obstacles.clear()
	level = LevelFixture.new()
	world.add_child(level)
	player = Explorer.new()
	# setup_parked correctly refuses to spawn through the explorer (layer 4).
	# Keep the initial capsule outside the car's origin until entry is tested.
	player.position = Vector3(12, 0.05, 0)
	level.add_child(player)
	level.player = player
	combat = CombatStub.new()
	level.add_child(combat)
	level.combat = combat
	traffic = Traffic.new()
	level.add_child(traffic)
	traffic.level = level
	var strip: Array[Vector3] = [Vector3(0, 0, -50), Vector3(0, 0, 50)]
	traffic.road_points = strip
	traffic.road_width = 100.0
	level.traffic = traffic
	driving = Driving.new()
	level.add_child(driving)
	# Bypass only starter placement, which the main driving fixture covers.
	driving.level = level
	driving.player = player
	driving.traffic = traffic
	await frames(3)
	var car := Vehicle.new()
	traffic.add_child(car)
	if not check(car.setup_parked(traffic, Transform3D(Basis.IDENTITY, Vector3(0, 0.025, 0)), "access_fixture", 3), "fixture car supported"):
		_finish()
		return
	traffic.register_player_vehicle(car)
	driving.starter = car
	await frames(2)
	await stand(Vector3(12, 0.05, 0))
	check(not driving.enter_vehicle(car) and not car.player_controlled, "public entry refuses distant caller before claiming car")
	var side := half_size(car).x
	await stand(Vector3(side + 1.1, 0.05, 0.25))
	var wall := box("ThinFence", Vector3(side + 0.5, 1.0, 0), Vector3(0.08, 2.0, 8.0), 2)
	await frames(2)
	check(not driving._entry_accessible(car), "capsule sweep detects thin intervening fence")
	check(driving._nearest_candidate() == null, "blocked car is not offered as an entry candidate")
	check(not driving.enter_vehicle(car) and not car.player_controlled and not driving.active, "public entry also rejects fence without ownership mutation")
	wall.free()
	await frames(2)
	check(driving._entry_accessible(car), "same nearby approach is accessible after fence removal")
	var prior: Vector3 = player.global_position
	player.global_position.y = 4.0
	check(not driving._entry_accessible(car), "height mismatch fails access gate")
	player.global_position = prior
	await stand(prior)
	check(driving.enter_vehicle(car), "clear nearby public entry succeeds")
	if not driving.active:
		_finish()
		return
	# The oversized obstacle eliminates all door/ring destinations and covers
	# the roof capsule, exercising the former unconditional roof branch.
	var trap := box("TrappedVolume", Vector3(0, 2, 0), Vector3(16, 4, 16), 2)
	await frames(2)
	check(not driving.exit_vehicle(true) and driving.active and car.player_controlled, "forced exit refuses obstructed roof and retains ownership")
	var seat: Vector3 = player.global_position
	check(not driving.recovery_exit_at(Vector3.INF, 0.0), "recovery rejects non-finite destination")
	check(not driving.recovery_exit_at(Vector3(20, 0.05, 0), INF), "recovery rejects non-finite heading")
	check(not driving.recovery_exit_at(Vector3(0, 0.05, 0), 0.0), "recovery rejects occupied destination")
	check(driving.active and car.player_controlled and player.global_position == seat, "failed recovery requests preserve seat and ownership")
	var release := Vector3(20, 0.05, 0)
	check(driving.recovery_exit_at(release, 0.7), "clear facility destination permits recovery detachment")
	check(not driving.active and not car.player_controlled and player.global_position.distance_to(release) < 0.001, "successful recovery releases car and places explorer exactly once")
	check(str(driving.last_exit.get("door", "")) == "recovery" and int(driving.forced_exits) == 1, "recovery is recorded as one forced exit")
	check(not driving.recovery_exit_at(release, 0.7), "repeated recovery cannot detach twice")
	trap.free()
	await frames(2)
	check(await board(car), "can board again after recovery")
	# All ground candidates now exceed the allowed 0.6m step, but the car roof
	# remains unobstructed: a legitimate checked roof fallback still works.
	box("RaisedSurround", Vector3(0, 0.45, 0), Vector3(16, 0.9, 16), 2)
	await frames(2)
	check(driving.exit_vehicle(true), "clear roof remains a valid last resort")
	check(str(driving.last_exit.get("door", "")) == "roof" and capsule_clear(1 | 2 | 8 | 16), "roof fallback leaves full capsule clear")
	clear_obstacles()
	place(car, Vector3.ZERO, 0.0)
	# The sidewalk ends 25cm from the car body and is 15cm above its road.
	# A downward straight-line capsule sweep would clip the slab before its
	# edge; production keeps this entry sweep at the higher endpoint instead.
	var sidewalk := box("BoardingSidewalk", Vector3(side + 1.5, 0.075, 0), Vector3(2.5, 0.15, 8.0), 1)
	await frames(2)
	await stand(Vector3(side + 0.9, 0.2, 0.25))
	await frames(8)
	# The capsule bottom is 1cm above the explorer origin, so a settled origin
	# is ~0.14 (with physics skin), not a robust measure of sidewalk height.
	# Verify the actual support body/top and capsule feet instead.
	var support_ray := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP, player.global_position - Vector3.UP, 1)
	var support := world.get_world_3d().direct_space_state.intersect_ray(support_ray)
	var feet_y: float = player._capsule.global_position.y - float(player._capsule.shape.height) * 0.5
	var support_y := float(support.get("position", Vector3.INF).y)
	var road_y := ground_y(car.global_position)
	check(player.is_on_floor() and support.get("collider") == sidewalk and absf(support_y - 0.15) < 0.001
		and absf(feet_y - support_y) < 0.015 and absf(road_y) < 0.001 and absf(car.global_position.y - 0.025) < 0.005,
		"boarding fixture stands on actual 15cm sidewalk beside road-level car (floor=%s, support=%.6f, feet=%.6f, road=%.6f, car=%.6f)" % [player.is_on_floor(), support_y, feet_y, road_y, car.global_position.y])
	check(driving._entry_accessible(car) and driving._nearest_candidate() == car, "raised sidewalk permits a clear capsule approach and entry prompt")
	var curb_fence := box("SidewalkFence", Vector3(side + 0.35, 0.9, 0), Vector3(0.08, 1.5, 8.0), 2)
	await frames(2)
	check(not driving._entry_accessible(car) and not driving.enter_vehicle(car), "raised sidewalk still refuses boarding through an intervening fence")
	curb_fence.free()
	await frames(2)
	check(driving.enter_vehicle(car) and driving.active and car.player_controlled, "public entry boards from 15cm sidewalk after fence removal")
	check(driving.recovery_exit_at(Vector3(20, 0.05, 0), 0.0), "raised sidewalk boarding cleanup releases safely")
	_finish()
