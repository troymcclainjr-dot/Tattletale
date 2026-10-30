extends Node
## Actual imported porch triangles, full player collision, no route teleporting.
var passed := 0
var failed := 0
var level: Node3D
var player: CharacterBody3D

func _ready() -> void:
	_run.call_deferred()

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func check(ok: bool, label: String) -> void:
	passed += int(ok)
	failed += int(not ok)
	print("[city_porch_movement] %s %s" % ["PASS" if ok else "FAIL", label])

func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn")
	await frames(4)
	level = get_tree().current_scene
	for i in 1200:
		if level != null and level.get("level_ready") == true:
			break
		await frames(1)
		level = get_tree().current_scene
	check(level != null and level.get("level_ready") == true, "imported neighborhood initializes")
	if failed > 0:
		get_tree().quit(1)
		return
	player = level.player
	level.pause_exploring()
	var stairs: Array = level.level_data.get("porch_stairs", [])
	check(stairs.size() >= 100, "whole-map porch staircase metadata is available")
	if stairs.is_empty():
		get_tree().quit(1)
		return
	# Evenly sample the entire source collection, not just the introductory route.
	for i in 8:
		var stair: Dictionary = stairs[roundi(float(i) * float(stairs.size() - 1) / 7.0)]
		for running in [false, true]:
			await _walk_stair(stair, running)
	print("[city_porch_movement] %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _walk_stair(stair: Dictionary, running: bool) -> void:
	var approach: Vector3 = level.vector(stair.approach)
	var landing: Vector3 = level.vector(stair.landing)
	var outward: Vector3 = level.vector(stair.normal).normalized()
	var label := "%s %s" % [str(stair.building_id), "run" if running else "walk"]
	Input.action_release("move_forward")
	Input.action_release("run")
	player.enabled = false
	level._place_player(approach, atan2(-outward.x, -outward.z))
	await frames(15)
	player.enabled = true
	var up := await _travel(landing, -outward, running)
	var ascent_position := player.global_position
	var on_deck: bool = up.reached and absf(ascent_position.y - landing.y) < 0.12
	check(on_deck, label + " physically ascends imported porch steps")
	check(float(up.max_rise) <= player.STEP_HEIGHT + 0.015, label + " keeps each rise within the original 28cm cap")
	if not on_deck:
		print("[city_porch_movement] blocked approach=", approach, " landing=", landing, " player=", ascent_position, " reason=", player.debug_step_reason)
		return
	# Turn while standing on the reached deck, then retrace the same physical steps.
	await frames(12)
	player.current_speed = 0.0
	player.yaw = atan2(outward.x, outward.z)
	player.camera_yaw = player.yaw
	player._orbit_basis_latched = false
	var down := await _travel(approach, outward, running)
	var ground: Dictionary = level.ground_at(approach)
	var on_ground: bool = down.reached and not ground.is_empty() and absf(player.position.y - ground.position.y) < 0.12
	check(on_ground, label + " physically descends to the approach")
	if not on_ground:
		print("[city_porch_movement] descent blocked target=", approach, " player=", player.global_position, " reason=", player.debug_step_reason)

func _travel(target: Vector3, forward: Vector3, running: bool) -> Dictionary:
	var max_rise := 0.0
	var reached := false
	if running:
		Input.action_press("run")
	for tick in 300:
		var remaining := target - player.global_position
		remaining.y = 0.0
		var along := remaining.dot(forward)
		var lateral := (remaining - forward * along).length()
		if along <= 0.12 and lateral < 0.20:
			reached = true
			break
		Input.action_press("move_forward", clampf(along / 0.7, 0.25, 1.0))
		var previous_y := player.position.y
		await frames(1)
		max_rise = maxf(max_rise, player.position.y - previous_y)
	Input.action_release("move_forward")
	Input.action_release("run")
	player.current_speed = 0.0
	await frames(12)
	return {"reached": reached, "max_rise": max_rise}
