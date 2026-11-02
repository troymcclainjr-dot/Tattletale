extends Node3D
const Basketball = preload("res://scripts/city/city_basketball.gd")
const Bindings = preload("res://scripts/city/city_input_bindings.gd")
class PlayerFixture:
	extends CharacterBody3D
	var enabled := true
	var camera: Camera3D
	var phone: Node3D
	var combat: Node3D
	var impact_recovery := 0.0
	var seated := false
	func is_seated() -> bool:
		return seated
class CombatFixture:
	extends Node3D
	var downed := false
	func blocks_movement() -> bool:
		return downed
class LevelFixture:
	extends Node3D
	var player: CharacterBody3D
	var ready_to_play := true
	var paused := false
class CourtFixture:
	extends Node3D
	var records: Array[Dictionary] = []
var failures := 0

func check(ok: bool, label: String) -> void:
	failures += int(not ok)
	print("[basketball] %s %s" % ["PASS" if ok else "FAIL", label])

func _ready() -> void:
	_run.call_deferred()

func mouse(pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	return event

func _run() -> void:
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	# Shoot/return route through the shared bindings; use defaults in memory only.
	Bindings.bindings = Bindings.DEFAULTS.duplicate()
	var level := LevelFixture.new()
	add_child(level)
	level.player = PlayerFixture.new()
	level.add_child(level.player)
	level.player.position = Vector3(0, 0, 1.0)
	var courts := CourtFixture.new()
	level.add_child(courts)
	for i in 5:
		courts.records.append({"id": "court_%d" % i, "position": Vector3(i * 8.0, 0, 0), "length_m": 28.0,
			"hoops": [{"rim_position": Vector3(i * 8.0, 3.05, -8.0)}]})
	var floor_body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100, 1, 100)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	floor_body.add_child(collider)
	floor_body.position.y = -0.5
	level.add_child(floor_body)
	var game := Basketball.new()
	level.add_child(game)
	game.setup(level, courts)
	await get_tree().physics_frame
	await get_tree().process_frame
	check(game.balls.size() == courts.records.size(), "one ball for every actual court record")
	check(game.get_status().active == 0 and not game.handle_input(mouse(true)), "resting balls idle and empty hands do not consume LMB")
	check(game.interact() and game.get_status().held, "E interaction picks up nearby ball")
	check(game.handle_input(mouse(true)), "held ball accepts charge press")
	game.tick(0.55)
	check(is_equal_approx(game.get_status().charge, 0.5), "shot charges with elapsed gameplay time")
	check(game.handle_input(mouse(false)) and game.shots == 1 and game.get_status().active == 1, "release launches one ball")
	var launched: CharacterBody3D = game.balls[0].body
	check(launched.velocity.y > 0.0 and launched.collision_layer == 0 and launched.collision_mask == 3, "upward throw touches world only")
	check(Basketball.shot_velocity(Vector3.FORWARD, 1.0).length() > Basketball.shot_velocity(Vector3.FORWARD, 0.0).length(), "charge increases throw strength")
	game.return_ball(0)
	level.player.position = Vector3(0, 0, 1.0)
	check(game.interact(), "returned ball can be picked up again")
	game.handle_input(mouse(true))
	level.paused = true
	game.tick(1.0)
	check(not game.get_status().charging and not game.shoot(), "modal state cancels charging and rejects shots")
	level.paused = false
	level.player.seated = true
	check(not game.interact() and not game.shoot(), "seated player cannot handle basketball")
	level.player.seated = false
	level.player.impact_recovery = 0.5
	check(not game.interact() and not game.shoot(), "impact recovery rejects basketball actions")
	level.player.impact_recovery = 0.0
	level.player.combat = CombatFixture.new()
	level.add_child(level.player.combat)
	level.player.combat.downed = true
	check(not game.interact() and not game.shoot(), "downed player cannot handle basketball")
	level.player.combat.downed = false
	game.suspend(true)
	check(not game.get_status().held and not game.get_status().charging, "mount suspension returns held ball and cancels charge")
	game.return_ball(0)
	var rim := Vector3(0, 3.05, 0)
	check(Basketball.crosses_rim(rim + Vector3.UP, rim - Vector3.UP, rim), "downward crossing through rim scores")
	check(not Basketball.crosses_rim(rim - Vector3.UP, rim + Vector3.UP, rim), "upward crossing does not score")
	check(not Basketball.crosses_rim(rim + Vector3(0.2, 1, 0), rim + Vector3(0.2, -1, 0), rim), "rim misses do not score")
	game.balls[0].hoops = [{"rim_position": rim}]
	game.balls[0].body.global_position = rim + Vector3.UP * 0.1
	game.balls[0].body.velocity = Vector3.DOWN * 5.0
	game.balls[0].active = true
	game.tick(0.05)
	check(game.baskets == 1, "live flight records made basket")
	game.tick(0.05)
	check(game.baskets == 1, "same flight scores only once")
	game.balls[0].body.global_position = Vector3(100, -20, 0)
	game.tick(0.02)
	check(not game.balls[0].active and game.balls[0].body.global_position == game.balls[0].home, "lost ball safely returns to court")
	for i in 3:
		game.balls[i].active = true
	level.player.position = game.balls[3].home + Vector3(0, 0, 1)
	check(game.interact(), "idle fourth ball can be picked up")
	game.interact()
	check(game.get_status().active <= Basketball.MAX_ACTIVE, "drop respects fixed simulation cap")
	game.return_ball(3)
	level.player.position = game.balls[3].home + Vector3(0, 0, 1)
	game.interact()
	level.player.position = Vector3(300, 0, 300)
	game.tick(0.02)
	check(not game.get_status().held and game.get_status().visible == 0, "walking away returns held ball and culls distant visuals")
	print("[basketball] failures=%d" % failures)
	get_tree().quit(1 if failures else 0)
