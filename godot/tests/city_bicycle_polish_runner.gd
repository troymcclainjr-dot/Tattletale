extends "res://tests/city_bicycle_feel_runner.gd"
## Production controls, movement and rider contacts on the existing real-player
## fixture. Root owns engine launches; this runner does not start another one.

var worst_hand_gap := 0.0
var shortest_arm := INF
var longest_arm := 0.0

func _run() -> void:
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	world = Fixture.new()
	add_child(world)
	_box(Vector3(0.0, -0.25, 0.0), Vector3(400.0, 0.5, 400.0), 1)
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
	_check(await _arrange(Vector3.ZERO, 0.0, 6.0), "polish: real explorer mounts the real bicycle")
	await _ride(60)
	_check(bike._pedal_rate > 5.0 and bike._pedal_rate < 9.0, "pedaling: ordinary cadence stays human-sized")
	bike.set_control_override(Vector2.ZERO)
	var wheel_start: float = bike._phase
	await _ride(40)
	var coast_phase: float = bike._pedal_phase
	await _ride(10)
	_check(absf(angle_difference(coast_phase, bike._pedal_phase)) < 0.01, "freewheel: feet settle while coasting")
	_check(absf(bike._phase - wheel_start) > 5.0 and bike.speed > 4.0, "freewheel: tyres keep turning and bike keeps rolling")
	var coast_lean: float = bike._rider.body.rotation.x
	bike.set_control_override(Vector2(0.0, 1.0), false, true)
	await _ride(100)
	_check(bike.speed > Bicycle.MAX_SPEED and bike._pedal_rate > 9.0 and bike._pedal_rate < 11.0, "hard pedal: Shift gains speed with bounded faster cadence")
	_check(bike._rider.body.rotation.x > coast_lean + 0.04, "hard pedal: rider visibly tucks into the effort")
	bike.set_control_override(Vector2(0.0, -1.0))
	var before_brake: float = bike.speed
	await _ride(18)
	_check(bike.speed < before_brake - 3.0 and bike._brake_effort > 0.8, "brake: S slows the bicycle and braces the rider")
	_check(absf(bike._pedal_rate) < 0.4 and bike._rider.g.position.z < -0.255, "brake: feet stop driving and weight shifts back")
	bike.set_control_override(Vector2.ZERO, true)
	await _ride(90)
	_check(absf(bike.speed) < 0.001 and bike._brake_effort < 0.01, "stop: braking posture relaxes at rest")
	bike.set_control_override(Vector2(0.0, 1.0), false, false, true)
	await _ride(1)
	_check(bike._hop_active, "hop: Space still starts the production hop")
	bike.set_control_override(Vector2(0.0, 1.0))
	var compressed := 0.0
	var landed := false
	var air_cadence := 0.0
	for frame in 90:
		await _ride(1)
		if frame > 15 and bike._hop_active:
			air_cadence = maxf(air_cadence, absf(bike._pedal_rate))
		if not bike._hop_active:
			landed = true
			compressed = maxf(compressed, bike._rider_compression)
	_check(landed and bike._grounded and absf(bike.global_position.y) < 0.02, "landing: wheels return to actual ground")
	_check(air_cadence < 0.1, "hop: feet hold their pedals while airborne")
	_check(compressed > 0.015 and compressed < 0.08, "landing: rider absorbs touchdown with bounded knee compression")
	bike.set_control_override(Vector2.ZERO, true)
	await _ride(90)
	_check(bike._rider_compression < 0.001, "landing: rider settles naturally back onto the saddle")
	_check(worst_hand_gap < 0.001 and shortest_arm > 0.65 and longest_arm < 1.3,
		"contacts: hands remain on grips throughout coast/brake/sprint/hop (gap %.6f m, arm %.3f..%.3f)" % [worst_hand_gap, shortest_arm, longest_arm])
	bike._landing_load = 1.0
	bike._pedal_rate = 8.0
	bike.reset_motion_state()
	bike._animate(0.0, 0.0)
	_check(bike._pedal_rate == 0.0 and bike._landing_load == 0.0 and bike._rider_compression == 0.0,
		"restore: transient cadence and landing load clear with motion reset")
	await _brake_reverse_timing()
	print("CITY_BICYCLE_POLISH ", "PASS" if errors.is_empty() else "FAIL", " checks=", checks, " failures=", errors.size())
	get_tree().quit(0 if errors.is_empty() else 1)

func _brake_reverse_timing() -> void:
	var row := 0
	for cadence in [[1.0 / 30.0], [1.0 / 60.0], [1.0 / 120.0], [1.0 / 24.0, 1.0 / 90.0, 1.0 / 45.0]]:
		var at := Vector3(-60.0 + row * 15.0, 0.0, -70.0)
		row += 1
		_check(await _arrange(at, 0.0, 2.0), "brake timing %d: starts on supported clear ground" % row)
		bike.set_control_override(Vector2(0.35, -1.0))
		var stopped_seconds := 0.0
		var reversed := false
		var stop_heading := INF
		var last_heading := 0.0
		for frame in 360:
			var dt: float = cadence[frame % cadence.size()]
			await get_tree().physics_frame
			bike.tick(dt)
			if absf(bike.speed) < 0.001:
				stopped_seconds += dt
				if not is_finite(stop_heading):
					stop_heading = bike.yaw
				last_heading = bike.yaw
			if bike.speed < -0.01:
				reversed = true
				break
		_check(reversed and stopped_seconds >= 0.25 and stopped_seconds <= 0.38,
			"brake timing %d: held S gives a visible stop then intentional reverse (%.3f s)" % [row, stopped_seconds])
		_check(is_finite(stop_heading) and absf(angle_difference(stop_heading, last_heading)) > 0.01,
			"brake timing %d: steering remains independent during stopped dwell" % row)
	# Releasing S at the observed stop must not start reversing later. A hop
	# remains available, and motion/restore reset discards any pending dwell.
	_check(await _arrange(Vector3(20.0, 0.0, -70.0), 0.0, 1.0), "brake release: mounted")
	bike.set_control_override(Vector2(0.0, -1.0))
	for frame in 90:
		await _frames(1)
		if absf(bike.speed) < 0.001:
			break
	_check(bike._reverse_wait > 0.0 and bike.save_blocker().is_empty(), "stopped brake dwell permits a safe mounted checkpoint")
	bike.set_control_override(Vector2.ZERO)
	await _frames(30)
	_check(absf(bike.speed) < 0.001 and bike._reverse_wait == 0.0, "releasing S holds the stop without delayed reversal")
	bike.set_control_override(Vector2.ZERO, false, false, true)
	await _frames(1)
	_check(bike._hop_active and bike.save_blocker() == "land the bicycle before saving", "hop after braking still launches and blocks airborne save")
	bike.set_control_override(Vector2.ZERO)
	await _frames(90)
	_check(await _arrange(Vector3(30.0, 0.0, -70.0), 0.0, 1.0), "brake reset: mounted")
	bike.set_control_override(Vector2(0.0, -1.0))
	for frame in 90:
		await _frames(1)
		if absf(bike.speed) < 0.001:
			break
	_check(bike._reverse_wait > 0.0, "brake reset: real forward braking creates pending reverse dwell")
	bike.reset_motion_state()
	_check(bike._reverse_wait == 0.0, "motion and checkpoint restore reset clear pending reverse dwell")
	bike.set_control_override(Vector2(0.0, -1.0))
	await _frames(1)
	_check(bike.speed < -0.01, "fresh S from rest intentionally reverses immediately")
	# High-rate first strokes are smaller than the solver's old slide cutoff.
	# They must still move through the real hull sweep instead of repeatedly
	# losing all acceleration to zero measured travel.
	for direction in [-1.0, 1.0]:
		var start := Vector3(45.0 + direction * 8.0, 0.0, -70.0)
		_check(await _arrange(start, 0.0, 0.0), "120 Hz startup: mounted at rest")
		bike.set_control_override(Vector2(0.0, direction))
		for frame in 60:
			await get_tree().physics_frame
			bike.tick(1.0 / 120.0)
		_check(bike.speed * direction > 0.7 and (bike.global_position - start).z * direction > 0.15,
			"120 Hz startup: first %s strokes actually move through hull sweep" % ("reverse" if direction < 0.0 else "forward"))

func _ride(count: int) -> void:
	for frame in count:
		await _frames(1)
		for hand in 2:
			var side := -1.0 if hand == 0 else 1.0
			var grip: Vector3 = bike._front.to_global(Vector3(side * 0.30, 0.22, -0.04))
			worst_hand_gap = maxf(worst_hand_gap, bike._rider.hand_pos(hand).distance_to(grip))
			shortest_arm = minf(shortest_arm, bike._rider.arms[hand].scale.y)
			longest_arm = maxf(longest_arm, bike._rider.arms[hand].scale.y)
