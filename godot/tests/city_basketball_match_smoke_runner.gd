extends Node3D
## Physics fixtures for the pickup game: real ball flight through real rim
## crossings, possession and rebounds, the opponent's own checks, clears and
## shots, semantic input, interruptions and cleanup. A half court and a full
## court sit on one floor with solid backboards; the activity is ticked at the
## physics rate exactly as the level's gameplay loop does.
const Basketball = preload("res://scripts/city/city_basketball.gd")
const Court = preload("res://scripts/city/city_basketball_court.gd")
const Bindings = preload("res://scripts/city/city_input_bindings.gd")
const STEP := 1.0 / 60.0

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

class PhoneFixture:
	extends Node3D
	var active := false

class LevelFixture:
	extends Node3D
	var player: CharacterBody3D
	var ready_to_play := true
	var paused := false
	var notices: Array[String] = []
	func show_notice(message: String) -> void:
		notices.append(message)

class CourtFixture:
	extends Node3D
	var records: Array[Dictionary] = []

var failures := 0
var level: LevelFixture
var player: PlayerFixture
var game: Node3D

func check(ok: bool, label: String) -> void:
	failures += int(not ok)
	print("[basketball_match] %s %s" % ["PASS" if ok else "FAIL", label])

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	# In-memory defaults: a personal controls file must not change these fixtures.
	Bindings.bindings = Bindings.DEFAULTS.duplicate()
	_build_fixture()
	await get_tree().physics_frame
	await get_tree().process_frame
	_setup_and_challenge()
	_inside_arc_check()
	_guarding()
	_player_scores()
	_opponent_scores()
	_rebounds_and_clear()
	_out_of_bounds()
	_lost_ball()
	_interruptions()
	_win_and_rematch()
	_spawn_churn()
	_full_court()
	_semantic_input()
	_perched_ball()
	_shootaround()
	print("[basketball_match] failures=%d" % failures)
	# The fixture advances many minutes of activity synchronously. Give the
	# audio mixer time to release its real playback references before shutdown.
	game.cancel_activity()
	level.queue_free()
	await get_tree().process_frame
	for voice in Audio.get_children():
		if voice is AudioStreamPlayer:
			voice.stop()
			voice.stream = null
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(1 if failures else 0)

func _build_fixture() -> void:
	level = LevelFixture.new()
	add_child(level)
	player = PlayerFixture.new()
	level.player = player
	level.add_child(player)
	player.phone = PhoneFixture.new()
	player.add_child(player.phone)
	player.camera = Camera3D.new()
	player.add_child(player.camera)
	player.global_position = Vector3(0, 0, 30)
	var courts := CourtFixture.new()
	level.add_child(courts)
	courts.records.append({"id": "half_fixture", "kind": "practice_half", "width_m": 14.0, "length_m": 10.0,
		"position": Vector3.ZERO, "along": [0, 0, 1], "across": [1, 0, 0],
		"hoops": [{"position": Vector3(0, 0, -5.72), "rim_position": Vector3(0, 3.05, -3.425)}]})
	courts.records.append({"id": "full_fixture", "kind": "full", "width_m": 15.0, "length_m": 28.0,
		"position": Vector3(60, 0, 0), "along": [0, 0, 1], "across": [1, 0, 0],
		"hoops": [{"position": Vector3(60, 0, -14.72), "rim_position": Vector3(60, 3.05, -12.425)},
			{"position": Vector3(60, 0, 14.72), "rim_position": Vector3(60, 3.05, 12.425)}]})
	_box("CourtFloor", Vector3(30, -0.5, 0), Vector3(240, 1, 120), 1)
	var board := 0
	for record in courts.records:
		for hoop in record.hoops:
			var rim: Vector3 = hoop.rim_position
			var inward := Vector3(0, 0, 1.0 if rim.z < record.position.z else -1.0)
			# Same solid board as city_park_courts.gd: .375 m behind and .40 m above the rim.
			_box("SolidHoopBackboard_%d" % board, rim - inward * 0.375 + Vector3.UP * 0.40, Vector3(1.80, 1.05, 0.06), 2)
			board += 1
	game = Basketball.new()
	level.add_child(game)
	game.setup(level, courts)

func _box(label: String, at: Vector3, extent: Vector3, layer: int) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = extent
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	level.add_child(body)
	body.global_position = at

# ------------------------------------------------------------------ helpers

func key(code: int, pressed := true) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	return event

func mouse(pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	return event

func ticks(seconds: float) -> void:
	for i in ceili(seconds / STEP):
		game.tick(STEP)

func run_until(predicate: Callable, seconds: float) -> bool:
	for i in ceili(seconds / STEP):
		if predicate.call():
			return true
		game.tick(STEP)
	return bool(predicate.call())

func phase() -> String:
	return str(game.rules.phase) if game.rules != null else ""

func holder() -> String:
	return str(game.rules.holder) if game.rules != null else ""

func possession() -> String:
	return str(game.rules.possession) if game.rules != null else ""

func shot_info(field: String, fallback):
	return game.rules.shot.get(field, fallback) if game.rules != null else fallback

func score(side: String) -> int:
	return int(game.rules.score[side]) if game.rules != null else -1

func last_event(kind: String) -> Dictionary:
	if game.rules == null:
		return {}
	var events: Array = game.rules.events
	for i in range(events.size() - 1, -1, -1):
		if str(events[i].get("kind", "")) == kind:
			return events[i]
	return {}

func floor_target(point: Vector3) -> Vector3:
	return Vector3(point.x, 0.12, point.z)

func game_ball() -> Dictionary:
	return game.balls[maxi(0, game.session)]

## Real flight from wherever the ball is now: the stepped-gravity solution that
## reaches `target`, steep enough to drop through a ring unless an angle is given.
func launch_at(target: Vector3, angle_deg := -1.0) -> void:
	var body: CharacterBody3D = game_ball().body
	var from := body.global_position
	var flat := Vector3(target.x - from.x, 0.0, target.z - from.z)
	var distance := flat.length()
	var rise := target.y - from.y
	var angle := deg_to_rad(angle_deg) if angle_deg > 0.0 else clampf(atan(1.05 + 2.0 * rise / distance), deg_to_rad(45.0), deg_to_rad(72.0))
	var speed := Court.launch_speed(distance, rise, angle, 9.8, STEP)
	body.velocity = (flat / distance * cos(angle) + Vector3.UP * sin(angle)) * speed

func aim_camera(target: Vector3, lift: float) -> void:
	var eye: Vector3 = player.global_position + Vector3.UP * 1.6
	var flat := Vector3(target.x - eye.x, 0.0, target.z - eye.z).normalized()
	player.camera.global_position = eye
	player.camera.look_at(eye + flat * sqrt(1.0 - lift * lift) + Vector3.UP * lift, Vector3.UP)

func face(target: Vector3) -> void:
	player.look_at(Vector3(target.x, player.global_position.y, target.z), Vector3.UP)

func fresh_game(index := 0, at := Vector3(1.0, 0.0, 4.0)) -> bool:
	game.cancel_activity("test reset")
	game.opponent_accuracy = 0.0
	game.opponent_aim_bias = Vector3.ZERO
	player.phone.active = false
	player.impact_recovery = 0.0
	player.seated = false
	level.paused = false
	player.global_position = at
	return game.start_match(index)

## Walk up to the ball resting at the top of the key and take it (E).
func check_up() -> bool:
	if not run_until(func(): return phase() == "check" and possession() == "player", 6.0):
		return false
	var spot: Vector3 = game_ball().body.global_position
	player.global_position = Vector3(spot.x, 0.0, spot.z) + game.court.inward() * 0.6
	return game.interact() and holder() == "player"

# ------------------------------------------------------------------ sections

func _setup_and_challenge() -> void:
	check(game.balls.size() == 2 and game.frames.size() == 2, "one ball and one court frame per court record")
	var status: Dictionary = game.get_status()
	var legacy := true
	for field in ["enabled", "balls", "active", "visible", "held", "charging", "charge", "shots", "baskets", "max_active"]:
		legacy = legacy and status.has(field)
	check(legacy, "status keeps every key existing callers read")
	check(status.mode == "free" and not status.opponent_present and not status.persistent, "no game, no opponent and nothing persistent before a challenge")
	check(not game.handle_input(key(KEY_T)), "challenge key away from every court falls through")
	player.global_position = Vector3(1.0, 0.0, 4.0)
	check(not game.handle_input(key(KEY_SPACE)) and not game.handle_input(key(KEY_SHIFT)), "jump and sprint keys are never consumed")
	check("Challenge" in game.interaction_prompt(), "court prompt advertises the challenge key")
	check(game.handle_input(key(KEY_T)), "challenge key on a court starts a game")
	status = game.get_status()
	check(status.mode == "match" and status.opponent_present and status.opponent_instances == 1 and status.opponent_appearances == 1, "exactly one opponent walks on")
	check(phase() == "check" and possession() == "player", "the challenger checks the first ball")
	var ball: Dictionary = game.balls[0]
	var at: Vector3 = ball.body.global_position
	check(not ball.active and game.court.beyond_arc(at) and game.court.outside_distance(at) == 0.0, "game ball rests at the top of the key")
	check(game.opponent.collision_layer == 8 and ball.body.collision_layer == 0 and (ball.body.collision_mask & 8) == 0, "opponent is a solid person; balls never strike people")
	check(game.court.outside_distance(game.opponent.global_position) > 0.5, "opponent walks on from beside the court")
	check("FIRST TO 11" in game.interaction_prompt(), "HUD shows the first-to-11 scoreboard")
	check(not level.notices.is_empty() and "aren't saved" in level.notices.back(), "start notice says pickup games are not saved")
	check(not game.handle_input(mouse(true)), "empty hands never consume the shoot button")

func _inside_arc_check() -> void:
	player.global_position = game.court.spot(game.court.arc_radius() - 0.2, 0.0)
	check(not game.court.beyond_arc(player.global_position) and game.interact() and holder() == "player", "real pickup radius can collect the checked ball while feet remain inside the arc")
	check(game.rules.needs_clear and game.interaction_prompt().contains("take it back beyond the arc") and not game.interaction_prompt().contains("Checked · attack"), "inside-arc checked pickup keeps a clear owed and displays consistent guidance")
	check(fresh_game(), "restore the normal checked-ball fixture after inside-arc regression")

func _guarding() -> void:
	check(check_up() and not game.rules.needs_clear, "E checks up the ball at the top; no clear owed")
	var moved := 0.0
	var sideways := 0.0
	var gap := INF
	for i in 200:
		var before: Vector3 = game.opponent.global_position
		game.tick(STEP)
		var after: Vector3 = game.opponent.global_position
		var travel := Vector3(after.x - before.x, 0.0, after.z - before.z)
		if travel.length() > 0.0005:
			moved += travel.length()
			sideways = maxf(sideways, absf(angle_difference(atan2(travel.x, travel.z), float(game.opponent.yaw))))
		gap = minf(gap, Vector2(after.x - player.global_position.x, after.z - player.global_position.z).length())
	check(moved > 1.0, "opponent walks on to guard")
	check(sideways < 0.05, "opponent only steps along its facing: turns in place, never sidesteps")
	check(gap >= 1.0, "guarding keeps a personal-space gap from the ball handler")
	var basket: Vector3 = game.court.on_floor(game.court.rim())
	var defender: Vector3 = game.opponent.global_position
	check(defender.distance_to(basket) < player.global_position.distance_to(basket), "opponent guards between the ball handler and the basket")
	check(game.court.outside_distance(defender) == 0.0, "opponent stays inside the half in play")
	check(str(game.balls[0].holder) == "player" and game._held == 0, "the ball handler keeps the ball: no steals")

func _player_scores() -> void:
	var rim: Vector3 = game.court.rim()
	player.global_position = game.court.free_throw_spot() + game.court.inward() * 0.4
	face(rim)
	aim_camera(rim, 0.23)
	game.tick(STEP)
	check(game.handle_input(mouse(true)) and bool(game.get_status().charging), "shoot button charges the held ball")
	game.tick(STEP)
	var from: Vector3 = game.balls[game._held].body.global_position
	var plan: Dictionary = game.shot_plan(game._held, from)
	var ideal := float(plan.ideal)
	check(ideal >= 0.0 and ideal <= 1.0 and float(plan.window) > 0.0 and plan.rim == rim, "shot meter plans power and a timing window for the lined-up rim")
	check(game._meter.visible and "green" in game.interaction_prompt(), "power meter and green window show while charging")
	var clean: Vector3 = game._player_shot_velocity(game._held, from, ideal)
	var soft: Vector3 = game._player_shot_velocity(game._held, from, ideal + float(plan.window) * 0.9)
	var wild: Vector3 = game._player_shot_velocity(game._held, from, ideal + 0.3)
	check(absf(soft.length() - clean.length()) < 0.08 and absf(wild.length() - clean.length()) > 1.0, "releases inside the window fly true; wild releases do not")
	game._charge = ideal
	var before := score("player")
	var thrown: int = game.shots
	check(game.handle_input(mouse(false)) and game.shots == thrown + 1 and not bool(game.get_status().held), "release launches the real ball")
	check(str(shot_info("by", "")) == "player" and int(shot_info("value", 0)) == 1, "a release inside the arc is worth one")
	var made := run_until(func(): return score("player") > before or phase() != "live", 4.0)
	check(made and score("player") == before + 1 and str(last_event("basket").get("side", "")) == "player", "the lined-up release drops through the rim for one point")
	check("+1" in str(game._notice), "the made shot gets feedback")
	ticks(1.0)
	check(score("player") == before + 1, "the made shot never scores twice")
	check(possession() == "opponent", "after a basket the opponent gets the ball")

func _opponent_scores() -> void:
	game.opponent_accuracy = 0.0
	var before := score("opponent")
	var picked := run_until(func(): return holder() == "opponent", 8.0)
	check(picked and game.opponent.holding and str(game.balls[0].holder) == "opponent" and str(last_event("check").get("side", "")) == "opponent", "opponent walks up and checks the ball at the top")
	ticks(0.3)
	var carried: Vector3 = game.balls[0].body.global_position
	check(not game.balls[0].active and carried.distance_to(game.opponent.global_position) < 2.6, "the checked ball travels with the opponent's hands")
	var released := run_until(func(): return str(shot_info("by", "")) == "opponent", 10.0)
	check(released and game.balls[0].active and game.balls[0].body.velocity.length() > 3.0, "opponent aims and releases a real shot")
	var value := int(shot_info("value", 0))
	check(value == int(game.court.shot_value(game.opponent.global_position)), "the opponent's shot value follows where it was released")
	var crossed := run_until(func(): return phase() != "live", 5.0)
	check(crossed and score("opponent") == before + value and str(last_event("basket").get("side", "")) == "opponent", "the opponent's clean release scores through the rim, not on a timer")
	ticks(1.0)
	check(score("opponent") == before + value, "the opponent's basket is counted exactly once")
	check(possession() == "player", "loser's ball returns to the player")

func _rebounds_and_clear() -> void:
	check(check_up(), "player checks up again")
	var theirs := score("opponent")
	var mine := score("player")
	game.shoot()
	launch_at(floor_target(game.court.spot(4.4, 0.5)), 70.0)
	var rebound := run_until(func(): return holder() == "opponent", 8.0)
	check(rebound and str(last_event("defensive_rebound").get("side", "")) == "opponent", "opponent races to the loose ball for a defensive rebound")
	var outside_arc: bool = game.court.beyond_arc(game.opponent.global_position)
	check(bool(game.rules.needs_clear) != outside_arc, "a defensive rebound inside the arc owes a clear")
	var cleared := run_until(func(): return holder() == "opponent" and not bool(game.rules.needs_clear), 8.0)
	check(cleared and str(last_event("cleared").get("side", "")) == "opponent", "opponent takes it back beyond the arc before attacking")
	# Hold the game (phone) while a controlled opponent miss is in the air.
	player.phone.active = true
	var parked: Vector3 = game.opponent.global_position
	check(game.opponent_shoot(), "the opponent's release goes through the activity's rules")
	launch_at(floor_target(game.court.spot(3.0, -0.6)), 72.0)
	var high := run_until(func(): return game.balls[0].body.global_position.y > 2.3, 2.0)
	check(high and not game._can_pick(0, "player") and not game.match_ball_pickable("opponent"), "no goaltending: an untouched shot above head height belongs to the rim")
	var landed := run_until(func(): return bool(shot_info("touched", false)), 4.0)
	check(landed and game.opponent.global_position.distance_to(parked) < 0.001, "the phone puts the game on hold while the flight still lands")
	check("on hold" in game.interaction_prompt(), "HUD says the game is on hold")
	check(score("opponent") == theirs, "the missed shot does not score")
	player.phone.active = false
	var loose: Vector3 = game.balls[0].body.global_position
	player.global_position = Vector3(loose.x, 0.0, loose.z) + game.court.inward() * 0.7
	check(game.interact() and str(last_event("defensive_rebound").get("side", "")) == "player" and bool(game.rules.needs_clear), "the player's defensive rebound inside the arc must be cleared")
	game.tick(STEP)
	game.shoot()
	launch_at(game.court.rim())
	var finished := run_until(func(): return phase() != "live", 4.0)
	check(finished and str(last_event("no_basket").get("side", "")) == "player" and score("player") == mine, "an uncleared make counts nothing")
	check(possession() == "opponent", "and it turns the ball over")

func _out_of_bounds() -> void:
	game.opponent_accuracy = 0.0
	var mine := run_until(func(): return phase() == "check" and possession() == "player", 20.0)
	check(mine and check_up(), "after the opponent's possession the player checks up again")
	game.tick(STEP)
	player.global_position = Vector3(game.court.width * 0.5 + 1.0, 0.0, player.global_position.z)
	game.tick(STEP)
	check(game._held == -1 and str(last_event("out").get("side", "")) == "player" and possession() == "opponent", "carrying the ball over the sideline turns it over")
	player.global_position = Vector3(1.0, 0.0, 2.0)
	check(run_until(func(): return holder() == "opponent", 8.0), "opponent checks up after the turnover")
	player.phone.active = true
	game.opponent_shoot()
	launch_at(Vector3(game.court.width * 0.5 + 2.0, 0.12, 0.0), 60.0)
	var called := run_until(func(): return phase() == "dead", 4.0)
	check(called and str(last_event("out").get("side", "")) == "opponent" and possession() == "player", "a loose ball landing out of bounds goes to the side that did not touch it last")
	player.phone.active = false
	var reset := run_until(func(): return phase() == "check", 3.0)
	var rest: Vector3 = game.balls[0].body.global_position
	check(reset and not game.balls[0].active and rest.distance_to(game.court.check_spot()) < 0.3, "the dead ball comes back to the top of the key")

func _lost_ball() -> void:
	check(fresh_game() and check_up(), "fresh game for the lost-ball check")
	game.shoot()
	game.balls[0].body.global_position = Vector3(0.0, -20.0, 0.0)
	game.tick(STEP)
	check(phase() == "dead" and possession() == "opponent", "a ball lost under the world is a dead ball for the other side")
	var back := run_until(func(): return phase() == "check", 3.0)
	check(back and game.balls[0].body.global_position.distance_to(game.court.check_spot()) < 0.3, "and it is reset at the top of the key")

func _interruptions() -> void:
	check(fresh_game() and check_up(), "fresh game for the interruption checks")
	game.shoot()
	launch_at(floor_target(game.court.spot(2.0, 0.0)), 65.0)
	ticks(0.2)
	level.paused = true
	var ball_at: Vector3 = game.balls[0].body.global_position
	var opponent_at: Vector3 = game.opponent.global_position
	ticks(0.5)
	check(game.balls[0].body.global_position == ball_at and game.opponent.global_position == opponent_at and game.interaction_prompt().is_empty(), "pause freezes the ball in flight and the opponent")
	level.paused = false
	check(fresh_game() and check_up(), "fresh game for the fumble check")
	player.impact_recovery = 0.7
	game.tick(STEP)
	check(game._held == -1 and holder().is_empty() and str(shot_info("by", "")) == "player" and not bool(shot_info("shot", true)) and game.balls[0].active, "a vehicle impact knocks the ball loose: a live, nonlethal fumble")
	player.impact_recovery = 0.0
	player.global_position = Vector3(15.0, 0.0, 0.0)
	ticks(1.0)
	check("Head back" in game.interaction_prompt(), "walking off the court warns before the game ends")
	ticks(6.0)
	check(game.get_status().mode == "free" and game.rules == null and "left the court" in level.notices.back(), "leaving the court abandons the game with feedback")
	check(game.balls[0].body.global_position == game.balls[0].home and not game.balls[0].active, "an abandoned game's ball goes home")
	check(game.opponent.leaving or not game.opponent.present, "the opponent walks off")
	var gone := run_until(func(): return not game.opponent.present, 12.0)
	check(gone and game.opponent.collision_layer == 0 and game.opponent.collision_mask == 0 and not game.opponent.visible, "the opponent despawns cleanly with no collision left behind")
	var appearances: int = game.opponent_appearances
	check(fresh_game(), "a new challenge after cleanup")
	check(game.opponent_instances == 1 and game.opponent_appearances == appearances + 1, "the same opponent instance walks back on")
	game.suspend(true)
	check(game.rules == null and game.get_status().mode == "free" and game.balls[0].body.global_position == game.balls[0].home, "bike mount or relocation (suspend) calls the game off and puts the ball away")
	check(game.opponent.leaving, "the opponent leaves after a suspension")
	check(fresh_game(), "challenge again after a suspension")
	player.seated = true
	game.tick(STEP)
	check(game.rules == null and game.get_status().mode == "free", "taking a seat calls the game off")
	player.seated = false
	check(fresh_game(), "challenge again for the quit check")
	check(game.handle_input(key(KEY_T)) and game.rules != null and "again" in game.interaction_prompt(), "the first quit press asks for confirmation")
	check(game.handle_input(key(KEY_T)) and game.rules == null and game.opponent.leaving, "the second press quits and the opponent walks off")

func _win_and_rematch() -> void:
	check(fresh_game(), "challenge for the game-point check")
	game.rules.score = {"player": 10, "opponent": 7}
	check(check_up(), "player checks up at game point")
	var rim: Vector3 = game.court.rim()
	player.global_position = game.court.free_throw_spot() + game.court.inward() * 0.4
	face(rim)
	game.tick(STEP)
	game.shoot()
	launch_at(rim)
	var won := run_until(func(): return game.get_status().mode == "result", 4.0)
	check(won and str(game.rules.winner) == "player" and score("player") == 11, "a game-point make wins first to 11")
	check("You win" in level.notices.back() and "rematch" in game.interaction_prompt(), "the result says who won and offers a rematch")
	var appearances: int = game.opponent_appearances
	check(game.handle_input(key(KEY_T)) and game.get_status().mode == "match", "the challenge key during the result starts the rematch")
	check(score("player") == 0 and score("opponent") == 0 and possession() == "opponent", "the rematch resets the score with the loser's ball")
	check(game.opponent_instances == 1 and game.opponent_appearances == appearances and game.opponent.present, "the same opponent stays for the rematch")
	game.quit_match()

func _spawn_churn() -> void:
	for i in 8:
		player.global_position = Vector3(1.0, 0.0, 4.0)
		game.handle_input(key(KEY_T))
		game.tick(STEP)
		game.handle_input(key(KEY_T))
		game.handle_input(key(KEY_T))
		game.tick(STEP)
	var count := 0
	for child in game.get_children():
		count += int(str(child.name).begins_with("CourtOpponent"))
	check(count == 1 and game.opponent_instances == 1 and game.rules == null, "repeated start/quit cycles never spawn a second opponent")

func _full_court() -> void:
	check(fresh_game(1, Vector3(61.0, 0.0, 9.0)) and game.court.hoop == 1, "a full-court game takes the half nearest the challenger")
	var span: Vector2 = game.court.play_range()
	check(is_equal_approx(span.x, 0.0) and is_equal_approx(span.y, 14.0), "that half runs from the centre line to its baseline")
	check(check_up(), "player checks up on the full court")
	game.shoot()
	launch_at(Vector3(61.0, 0.12, -3.0), 55.0)
	var called := run_until(func(): return phase() == "dead", 5.0)
	check(called and str(last_event("out").get("side", "")) == "player" and possession() == "opponent", "a ball landing past the centre line is out of the half-court game")
	game.quit_match()

func _semantic_input() -> void:
	Bindings.bindings["city_basketball_challenge"] = KEY_G
	player.global_position = Vector3(1.0, 0.0, 4.0)
	check(not game.handle_input(key(KEY_T)) and game.rules == null, "a remapped challenge releases the old key")
	check(game.handle_input(key(KEY_G)) and game.rules != null, "the remapped challenge key starts a game")
	game.handle_input(key(KEY_G))
	check("Press G again" in game.interaction_prompt(), "prompts follow the remapped key")
	check(game.handle_input(key(KEY_G)) and game.rules == null, "the remapped key confirms quitting")
	Bindings.bindings = Bindings.DEFAULTS.duplicate()
	var repeat := key(KEY_T)
	repeat.echo = true
	check(not game.handle_input(repeat) and game.rules == null, "key repeat never fires the challenge")

func _perched_ball() -> void:
	game.cancel_activity()
	player.global_position = Vector3(61.0, 0.0, -9.0)
	var ball: Dictionary = game.balls[1]
	ball.body.global_position = Vector3(60.0, 3.45 + 0.525 + 0.125, -12.8)
	ball.body.velocity = Vector3.ZERO
	ball.active = true
	ticks(4.0)
	check(ball.body.global_position.y < 1.7, "a ball perched on a backboard is nudged down (or put away), never stuck")

func _shootaround() -> void:
	game.cancel_activity()
	game.return_ball(0)
	var ball: Dictionary = game.balls[0]
	var home: Vector3 = ball.home
	player.global_position = Vector3(home.x, 0.0, home.z + 0.8)
	check(game.interact() and game.get_status().mode == "shootaround", "picking up a court ball starts a shootaround")
	var rim: Vector3 = game.frames[0].rim()
	player.global_position = Vector3(0.0, 0.0, 1.0)
	face(rim)
	game.tick(STEP)
	game.shoot()
	launch_at(rim)
	run_until(func(): return bool(ball.scored) or not ball.active, 4.0)
	check(int(game.shootaround.makes) == 1 and int(game.shootaround.attempts) == 1 and int(game.shootaround.streak) == 1, "shootaround counts a made shot and the streak")
	run_until(func(): return not ball.active, 8.0)
	var resting: Vector3 = ball.body.global_position
	player.global_position = Vector3(resting.x, 0.0, resting.z + 0.7)
	check(game.interact(), "chase down the rebound")
	game.tick(STEP)
	game.shoot()
	launch_at(floor_target(Vector3(2.5, 0.0, -1.0)), 65.0)
	run_until(func(): return bool(ball.release.get("resolved", false)), 4.0)
	check(int(game.shootaround.attempts) == 2 and int(game.shootaround.makes) == 1 and int(game.shootaround.streak) == 0, "a miss resets the streak")
	check("Air ball" in str(game._notice) or "Short" in str(game._notice) or "Long" in str(game._notice) or "Wide" in str(game._notice), "a miss explains where the shot went")
	run_until(func(): return not ball.active, 8.0)
	resting = ball.body.global_position
	player.global_position = Vector3(resting.x, 0.0, resting.z + 0.7)
	game.interact()
	check(game.return_held() and game.get_status().mode == "free" and "Shootaround · 1/2" in level.notices.back(), "returning the ball ends the shootaround with a summary")
	check(ball.body.global_position == home and not ball.active, "the returned ball rests at its court")
