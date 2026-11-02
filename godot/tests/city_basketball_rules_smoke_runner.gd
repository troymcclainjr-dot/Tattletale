extends Node
## Court frames from real park records, the stepped-gravity launch solver, and
## the one-on-one rules: scoring values, possession, clears, out of bounds,
## duplicate-score protection, winning, rematch and abandonment.
const Court = preload("res://scripts/city/city_basketball_court.gd")
const Rules = preload("res://scripts/city/city_basketball_rules.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	failures += int(not ok)
	print("[basketball_rules] %s %s" % ["PASS" if ok else "FAIL", label])

func near(a: float, b: float, tolerance := 0.01) -> bool:
	return absf(a - b) <= tolerance

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	_court_geometry()
	_authored_floor_plane()
	_check_pickup_clear()
	_ballistics()
	_rules()
	print("[basketball_rules] failures=%d" % failures)
	get_tree().quit(1 if failures else 0)

## park_court_0 (Community green 3) from res://assets/data/pen_lucy_courts.json,
## shaped as city_park_courts.gd hands it over (vectors converted, axes raw).
func full_record() -> Dictionary:
	return {"id": "park_court_0", "kind": "full", "width_m": 15.0, "length_m": 28.0,
		"position": Vector3(43.252046, 1.967394, -131.755581),
		"across": [6.123233995736766e-17, 0, -1.0], "along": [-1.0, 0, -6.123233995736766e-17],
		"hoops": [{"position": Vector3(57.97205, 1.7468, -131.75558), "rim_position": Vector3(55.67705, 4.8312, -131.75558)},
			{"position": Vector3(28.53205, 2.18798, -131.75558), "rim_position": Vector3(30.82705, 5.20359, -131.75558)}]}

## park_court_11 (Neighborhood green 12), a practice half court.
func half_record() -> Dictionary:
	return {"id": "park_court_11", "kind": "practice_half", "width_m": 14.0, "length_m": 10.0,
		"position": Vector3(432.231313, -9.537496, -177.662605),
		"across": [-0.25881904510252085, 0, -0.9659258262890683], "along": [-0.9659258262890683, 0, 0.25881904510252085],
		"hoops": [{"position": Vector3(437.75641, -9.62219, -179.14305), "rim_position": Vector3(435.53961, -6.53821, -178.54906)}]}

func _court_geometry() -> void:
	var full = Court.new().setup(full_record())
	check(full.full() and full.rims.size() == 2 and full.playable(), "real full court record keeps both hoops")
	check(full.select_hoop(Vector3(50.0, 2.0, -131.0)) == 0 and full.inward().dot(Vector3(-1, 0, 0)) > 0.99, "nearest hoop is selected and defends toward mid-court")
	var span: Vector2 = full.play_range()
	check(near(span.x, -14.0) and near(span.y, 0.0), "full-court game uses the selected half up to the centre line")
	check(near(full.local(full.rim()).y, -12.425), "rim sits 1.575 m inside the baseline")
	check(near(full.floor_y(full.rims[1]) + 3.05, full.rims[1].y, 0.003), "graded floor plane matches the far rim height")
	check(near(full.arc_radius(), 6.75) and near(full.corner_x(), 6.6), "standard width keeps the 6.75 m arc and 6.6 m corner lines")
	var top: Vector3 = full.check_spot()
	check(full.beyond_arc(top) and full.outside_distance(top) == 0.0 and full.shot_value(top) == 2, "check spot is in play beyond the arc")
	check(not full.beyond_arc(full.free_throw_spot()) and full.shot_value(full.free_throw_spot()) == 1, "free-throw line is a one-point shot")
	check(full.beyond_arc(full.spot(6.9, 0.0)) and not full.beyond_arc(full.spot(6.6, 0.0)), "the arc boundary sits at 6.75 m straight out")
	var corner: Vector3 = full.on_floor(full.rim() + Vector3(0.0, 0.0, 7.0))
	check(full.beyond_arc(corner) and full.outside_distance(corner) == 0.0, "corner three counts from the straight corner line")
	check(not full.beyond_arc(full.on_floor(full.rim() + Vector3(0.0, 0.0, 6.0))), "inside the corner line near the baseline is a one")
	var over_line: Vector3 = full.world(0.0, 2.0)
	check(near(full.outside_distance(over_line), 2.0) and near(full.outside_distance(over_line, 2.5), 0.0), "centre line bounds the half; ball handlers get slack")
	check(near(full.outside_distance(full.world(8.5, -7.0)), 1.0), "sideline distance is measured from the painted line")
	var clamped: Vector3 = full.clamp_in_play(full.world(20.0, 10.0), 0.4)
	check(full.outside_distance(clamped) == 0.0 and near(full.local(clamped).x, 7.1) and near(full.local(clamped).y, -0.4), "clamping keeps goals inside the half with a margin")
	var second: Vector3 = full.free_throw_spot(1)
	check(second.distance_to(full.on_floor(full.rims[1])) > 4.0 and full.local(second).y > 0.0, "the far hoop's free-throw spot stays in its own half")
	check(full.select_hoop(Vector3(32.0, 2.0, -131.0)) == 1 and near(full.play_range().x, 0.0) and near(full.play_range().y, 14.0), "the other hoop plays the other half")
	var half = Court.new().setup(half_record())
	check(not half.full() and half.rims.size() == 1, "practice half court has one hoop")
	check(near(half.local(half.rim()).y, -3.425) and near(half.local(half.rim()).x, 0.0), "half-court rim sits on the centreline 1.575 m in")
	var half_span: Vector2 = half.play_range()
	check(near(half_span.x, -5.0) and near(half_span.y, 5.0), "half court plays its whole slab")
	check(near(half.arc_radius(), 6.25), "a narrower slab shrinks the arc to width/2 - .75")
	check(half.beyond_arc(half.check_spot()) and half.outside_distance(half.check_spot()) == 0.0, "half-court check spot is beyond the arc and in play")
	check(half.inward().dot(half.along) > 0.99, "half-court hoop defends toward the open end")
	check(half.beyond_arc(half.clear_spot(half.free_throw_spot())), "clear spot from the lane is beyond the arc")
	var guard: Vector3 = half.guard_spot(half.check_spot(), 1.5)
	var basket: Vector3 = half.on_floor(half.rim())
	check(guard.distance_to(half.check_spot()) <= 1.51 and basket.distance_to(guard) < basket.distance_to(half.check_spot()), "guard spot sits between the attacker and the basket")
	var spawns: Array[Vector3] = half.spawn_points(half.check_spot())
	check(spawns.size() == 4 and half.outside_distance(spawns[0]) > 1.0 and half.outside_distance(spawns[2]) == 0.0, "walk-on spots start beside the court with in-play fallbacks")
	check(half.outside_distance(half.exit_point(half.check_spot())) > 2.5, "exit walk leaves the court")
	var sparse = Court.new().setup({"id": "fixture", "position": Vector3.ZERO, "length_m": 28.0, "hoops": [{"rim_position": Vector3(0, 3.05, -8)}]})
	check(not sparse.full() and sparse.inward().dot(Vector3.BACK) > 0.99 and near(sparse.width, 15.0), "sparse fixture records derive a sane frame")
	check(not Court.new().setup({"id": "bare", "position": Vector3.ZERO}).playable(), "a court without hoops cannot host a game")

## Check actual authored interior collision vertices, not a duplicate floor formula.
func _authored_floor_plane() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/pen_lucy_courts.json"))
	check(data is Dictionary, "authored court floor data is available")
	if not data is Dictionary:
		return
	for record in data.courts:
		var frame = Court.new().setup(record)
		var vertices: Array = record.mesh.vertices
		var samples := 0
		var worst := 0.0
		for i in int(record.floor_triangles) * 3:
			var point := Vector3(float(vertices[i * 3]), float(vertices[i * 3 + 1]), float(vertices[i * 3 + 2]))
			var at: Vector3 = point + frame.center
			var local_at: Vector2 = frame.local(at)
			if absf(local_at.x) >= frame.width * 0.5 - 0.1 or absf(local_at.y) >= frame.length * 0.5 - 0.1:
				continue
			samples += 1
			worst = maxf(worst, absf(frame.floor_y(at) - at.y))
			worst = maxf(worst, absf(frame.world(local_at.x, local_at.y).y - at.y))
		check(samples > 0 and worst < 0.0001, "%s floor frame matches all interior collider vertices across both grades (%.6f m max)" % [str(record.id), worst])

func _check_pickup_clear() -> void:
	for side in ["player", "opponent"]:
		var rules = Rules.new()
		rules.start(side)
		rules.pick_up(side, false)
		check(rules.needs_clear, "%s collecting a check ball from inside the arc owes a clear" % side)
		rules.release(side, 1, true)
		var result: Dictionary = rules.basket()
		check(int(result.get("points", -1)) == 0 and int(rules.score[side]) == 0, "%s cannot score directly from an inside-arc check pickup" % side)
		rules.start(side)
		rules.pick_up(side, false)
		rules.clear(side)
		rules.release(side, 2, true)
		result = rules.basket()
		check(int(result.get("points", -1)) == 2, "%s can score normally after clearing the checked ball" % side)

## The balls' own integration: gravity first, then the move.
func simulate(from: Vector3, velocity: Vector3, target_y: float, step: float) -> Vector3:
	var at := from
	var speed := velocity
	for i in 900:
		var before := at
		speed.y -= 9.8 * step
		at += speed * step
		if speed.y < 0.0 and before.y >= target_y and at.y < target_y:
			return before.lerp(at, (before.y - target_y) / (before.y - at.y))
	return Vector3.INF

func _ballistics() -> void:
	var step := 1.0 / 60.0
	for pair in [[Vector3(0, 2.0, 0), Vector3(0, 3.05, -1.2)], [Vector3(0, 1.4, 0), Vector3(3, 3.05, -6)], [Vector3(0, 2.1, 0), Vector3(0, 3.05, -7.4)]]:
		var from: Vector3 = pair[0]
		var target: Vector3 = pair[1]
		var flat := Vector3(target.x - from.x, 0.0, target.z - from.z)
		var distance := flat.length()
		var rise := target.y - from.y
		var angle := atan(1.05 + 2.0 * rise / distance)
		var speed := Court.launch_speed(distance, rise, angle, 9.8, step)
		var crossing := simulate(from, (flat / distance * cos(angle) + Vector3.UP * sin(angle)) * speed, target.y, step)
		check(speed > 0.0 and crossing.is_finite() and Vector2(crossing.x - target.x, crossing.z - target.z).length() < 0.01, "launch solver lands a %.1f m shot on the rim centre under stepped gravity" % distance)
		check(Court.entry_angle(distance, rise, angle) > deg_to_rad(40.0), "the opponent's arc enters the ring steeply from %.1f m" % distance)
	check(Court.launch_speed(5.0, 6.0, deg_to_rad(30.0), 9.8, step) == 0.0, "an unreachable arc reports no speed")

func _rules() -> void:
	var rules = Rules.new()
	rules.start("player")
	check(rules.phase == "check" and rules.can_pick_up("player") and not rules.can_pick_up("opponent"), "a checked ball belongs to the side starting with it")
	check(rules.pick_up("opponent", true).is_empty(), "the defence cannot take a checked ball")
	var event: Dictionary = rules.pick_up("player", true)
	check(event.get("kind", "") == "check" and rules.holder == "player" and not rules.needs_clear and rules.phase == "live", "checking up starts live play with no clear owed")
	event = rules.release("player", 2, true)
	check(event.get("kind", "") == "shot" and int(rules.shot.get("value", 0)) == 2 and bool(rules.shot.get("valid", false)) and rules.holder.is_empty(), "a release keeps the value of where it left the hand")
	check(rules.release("player", 1, true).is_empty(), "nobody can release a ball they do not hold")
	event = rules.basket()
	check(event.get("kind", "") == "basket" and int(event.get("points", 0)) == 2 and int(rules.score.player) == 2, "a made two-pointer scores two")
	check(rules.basket().is_empty() and int(rules.score.player) == 2, "the same release can never score twice")
	check(rules.phase == "dead" and rules.possession == "opponent" and not rules.can_pick_up("player") and not rules.can_pick_up("opponent"), "after a basket the ball is dead and goes to the other side")
	rules.tick(0.5)
	check(rules.phase == "dead", "the dead-ball pause holds the check briefly")
	event = rules.tick(1.0)
	check(event.get("kind", "") == "check_ready" and rules.phase == "check" and rules.possession == "opponent", "loser's ball is checked at the top")
	rules.pick_up("opponent", true)
	rules.release("opponent", 1, true)
	rules.touch()
	check(bool(rules.shot.get("touched", false)), "first contact makes a miss a fair rebound")
	event = rules.pick_up("player", false)
	check(event.get("kind", "") == "defensive_rebound" and rules.needs_clear and rules.holder == "player", "a defensive rebound inside the arc must be cleared")
	rules.release("player", 1, true)
	check(not bool(rules.shot.get("valid", true)), "an uncleared release cannot score")
	event = rules.basket()
	check(event.get("kind", "") == "no_basket" and int(event.get("points", -1)) == 0 and int(rules.score.player) == 2 and rules.possession == "opponent", "an uncleared basket counts nothing and turns it over")
	rules.tick(2.0)
	rules.pick_up("opponent", true)
	rules.release("opponent", 1, true)
	event = rules.pick_up("opponent", false)
	check(event.get("kind", "") == "offensive_rebound" and not rules.needs_clear, "an offensive rebound keeps the ball without clearing")
	check(rules.clear("opponent").is_empty(), "clearing only applies when a clear is owed")
	rules.release("opponent", 1, false)
	event = rules.pick_up("player", false)
	check(event.get("kind", "") == "loose_ball" and rules.needs_clear, "a loose ball taken from the other side must be cleared")
	check(not rules.clear("player").is_empty() and not rules.needs_clear, "carrying it beyond the arc clears it")
	rules.release("player", 2, true)
	event = rules.out_of_bounds()
	check(event.get("kind", "") == "out" and rules.possession == "opponent" and rules.phase == "dead", "out of bounds goes to the side that did not touch it last")
	rules.tick(2.0)
	rules.pick_up("opponent", true)
	event = rules.out_of_bounds("opponent")
	check(event.get("side", "") == "opponent" and rules.possession == "player", "a ball handler stepping out turns it over")
	check(rules.out_of_bounds().is_empty(), "a dead ball cannot go out again")
	rules.tick(2.0)
	rules.score = {"player": 10, "opponent": 4}
	rules.pick_up("player", true)
	rules.release("player", 2, true)
	event = rules.basket()
	check(event.get("winner", "") == "player" and rules.phase == "over" and int(rules.score.player) == 12 and rules.games == 1, "a two from ten wins first to eleven")
	check(not rules.can_pick_up("player") and rules.basket().is_empty() and rules.tick(5.0).is_empty(), "a decided game takes no more baskets or checks")
	check(rules.rematch() and rules.phase == "check" and rules.possession == "opponent" and int(rules.score.player) == 0 and int(rules.score.opponent) == 0, "rematch resets the score with the loser's ball")
	check(not rules.rematch(), "rematch only follows a finished game")
	check(rules.give("player", true).is_empty() and rules.holder.is_empty(), "only the checking side can start with the ball in hand")
	check(not rules.give("opponent", false).is_empty() and rules.holder == "opponent" and rules.needs_clear, "starting in hand inside the arc still owes a clear")
	check(not rules.abandon("test").is_empty() and rules.phase == "abandoned" and not rules.can_pick_up("opponent") and rules.abandon("again").is_empty(), "an abandoned game accepts nothing and abandons once")
	for i in 40:
		rules._event({"kind": "noise"})
	check(rules.events.size() == Rules.MAX_EVENTS, "the event log stays bounded")
