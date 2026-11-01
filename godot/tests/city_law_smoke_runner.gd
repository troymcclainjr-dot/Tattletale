extends Node
## Law response in a real physics arena with production combat, actor and player
## code: witness line of sight and facing, unobserved crimes, gunfire heard
## through walls, delayed civilian calls that a silenced witness never makes,
## immediate police detection, real patrol dispatch along a street route around a
## wall, combat engagement and hand-off, a last-known-position search that never
## follows the hidden player, escape and return to the beat, G surrender at the
## precinct with one fine, hospital recovery with one bill, pause/inspector holds,
## forced vehicle exit before relocation and bounded work under event floods.
const Law := preload("res://scripts/city/city_law.gd")
const Facilities := preload("res://scripts/city/city_law_facilities.gd")
const Combat := preload("res://scripts/city/city_combat.gd")
const Player := preload("res://scripts/city/city_player.gd")
const Actor := preload("res://scripts/city/city_npc_actor.gd")
const WALL := Vector3(-10, 1.5, 3)
const WALL_SIZE := Vector3(1, 3, 18)
const PRECINCT := Vector3(-60, 0, -60)
const HOSPITAL := Vector3(60, 0, -60)
## PublicEntrance marker (50.5, 0, -64) plus 3 m along its approach, at standing clearance.
const HOSPITAL_RELEASE := Vector3(47.5, 0.05, -64)

class People:
	extends Node3D
	var actors: Dictionary = {}
	var crowd: Node3D
	func get_actor(id: String) -> Node3D:
		return actors.get(id)

class Wallet:
	extends Node
	var money := 500
	var debits: Array[Dictionary] = []
	func debit(amount: int, reason: String) -> int:
		var taken := clampi(amount, 0, money)
		money -= taken
		debits.append({"amount": amount, "taken": taken, "reason": reason})
		return taken

class Driving:
	extends Node
	var active := false
	var vehicle: Node3D
	var exits: Array[bool] = []
	var refuse := 0
	func exit_vehicle(force := false) -> bool:
		exits.append(force)
		if refuse > 0:
			refuse -= 1
			return false
		active = false
		return true

class Inspector:
	extends Node
	var active := false

class Civic:
	extends Node3D
	var sites: Array = []

class Arena:
	extends Node3D
	var player: CharacterBody3D
	var npcs: Node3D
	var combat: Node3D
	var law: Node
	var progression: Node
	var driving: Node
	var inspector: Node
	var civic_district: Node3D
	var paused := false
	var level_data: Dictionary = {}
	var notices: Array[String] = []
	var _safe_position := Vector3.ZERO
	func ground_at(at: Vector3) -> Dictionary:
		var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 60.0, at - Vector3.UP * 120.0, 1)
		return get_world_3d().direct_space_state.intersect_ray(ray)
	func show_notice(text: String) -> void:
		notices.append(text)

var arena: Arena
var player: CharacterBody3D
var npcs: People
var combat: Node3D
var law: Node
var wallet: Wallet
var driving: Driving
var inspector: Inspector
var civic: Civic
var failures := 0
var passes := 0
var defeats := 0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	failures += int(not ok)
	passes += int(ok)
	print("[law] %s %s" % ["PASS" if ok else "FAIL", label])

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

## One gameplay step in the root's order (combat, law, people); menus stop all of it.
func step(delta := 1.0 / 60.0) -> void:
	if not arena.paused:
		combat.tick(delta)
	law.tick(delta)
	if not arena.paused:
		for actor in npcs.actors.values():
			if is_instance_valid(actor):
				actor.tick(delta)
	await get_tree().physics_frame

func advance(seconds: float) -> void:
	for i in ceili(seconds * 60.0):
		await step()

func advance_until(condition: Callable, limit: float) -> bool:
	for i in ceili(limit * 60.0):
		if bool(condition.call()):
			return true
		await step()
	return bool(condition.call())

func box(at: Vector3, size: Vector3, layer := 2) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cube := BoxShape3D.new()
	cube.size = size
	shape.shape = cube
	body.add_child(shape)
	arena.add_child(body)
	body.global_position = at
	return body

func spawn(id: String, cast: String, at: Vector3, facing: Vector3, patrol := false) -> CharacterBody3D:
	var actor := Actor.new()
	npcs.add_child(actor)
	actor.build(arena, id, cast, "Patrol officer" if cast.begins_with("cop_") else "Neighbor")
	actor.global_position = at
	actor.yaw = atan2(facing.x, facing.z)
	actor.puppet.g.rotation.y = actor.yaw
	if patrol:
		var points: Array[Vector3] = [at + Vector3(0, 0, -3), at + Vector3(0, 0, 3)]
		actor.set_patrol(points)
	npcs.actors[id] = actor
	return actor

func dismiss(actors: Array) -> void:
	law.reset_state()
	for state in combat._active.values().duplicate():
		combat._release(state)
	for state in combat._panic.values().duplicate():
		combat._release(state)
	for actor in actors:
		if is_instance_valid(actor):
			npcs.actors.erase(actor.actor_id)
			actor.queue_free()
	await frames(2)

func put_player(at: Vector3) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.yaw = 0.0
	player.enabled = true

func reset_player(at: Vector3) -> void:
	put_player(at)
	combat.downed = 0.0
	combat.health = 100.0
	combat._invulnerable = 0.0

func inside_wall(at: Vector3, margin := 0.0) -> bool:
	return absf(at.x - WALL.x) <= WALL_SIZE.x * 0.5 + margin and absf(at.z - WALL.z) <= WALL_SIZE.z * 0.5 + margin

func segment_hits_wall(a: Vector3, b: Vector3) -> bool:
	var steps := maxi(1, ceili(a.distance_to(b) / 0.25))
	for i in range(steps + 1):
		if inside_wall(a.lerp(b, float(i) / steps), 0.2):
			return true
	return false

## The player's own capsule at a spot overlaps no building, prop, person or car.
func capsule_clear(at: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.30
	capsule.height = 1.72
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.87)
	query.collision_mask = 2 | 8 | 16
	query.exclude = [player.get_rid()]
	return arena.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event

func _run() -> void:
	arena = Arena.new()
	add_child(arena)
	box(Vector3(0, -0.5, 0), Vector3(400, 1, 400), 1)
	box(WALL, WALL_SIZE)
	player = Player.new()
	arena.add_child(player)
	player.set_physics_process(false)
	arena.player = player
	npcs = People.new()
	arena.add_child(npcs)
	arena.npcs = npcs
	wallet = Wallet.new()
	arena.add_child(wallet)
	arena.progression = wallet
	driving = Driving.new()
	arena.add_child(driving)
	arena.driving = driving
	inspector = Inspector.new()
	arena.add_child(inspector)
	arena.inspector = inspector
	civic = Civic.new()
	arena.add_child(civic)
	arena.civic_district = civic
	_build_civic()
	# Street centre lines: one L-shaped street around the wall, one short lane.
	arena.level_data = {"spawn": {"position": [0, 0, 60], "yaw": 0.0}, "roads": [
		{"name": "Fixture Street", "width": 9.5, "points": [[-20, 0, -10], [-20, 0, 6], [-20, 0, 18], [0, 0, 18], [0, 0, 6], [0, 0, -10]]},
		{"name": "Fixture Lane", "width": 7.0, "points": [[-114, 0, 108], [-100, 0, 108]]}]}
	combat = Combat.new()
	arena.add_child(combat)
	combat.setup(arena)
	arena.combat = combat
	combat.player_defeated.connect(func(): defeats += 1)
	law = Law.new()
	arena.add_child(law)
	arena.law = law
	law.setup(arena)
	# Production timing scaled down so the fixture stays short; logic is unchanged.
	law.report_delay_min = 0.6
	law.report_delay_max = 1.0
	law.lost_sight_seconds = 1.5
	law.search_seconds = [2.5, 3.0, 3.0, 3.0]
	law.cooldown_seconds = [0.0, 2.0, 2.0, 2.0]
	law.return_speed = 3.0
	law.stage_seconds = {"down": 0.4, "hands_up": 0.4, "fade_out": 0.3, "fade_in": 0.3}
	combat.player_defeated.connect(law.on_player_defeated)
	reset_player(Vector3.ZERO)
	await frames(3)
	await _routes_and_facilities()
	await _witness_line_of_sight()
	await _unobserved_and_silenced()
	await _gunfire_witnesses()
	await _dispatch_pursuit_search_escape()
	await _surrender_at_precinct()
	await _hospital_recovery()
	await _bounded_work()
	arena.queue_free()
	await frames(3)
	var audio_deadline := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < audio_deadline:
		await get_tree().process_frame
	print("[law] %d passed; %d failed" % [passes, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _build_civic() -> void:
	# Precinct: front faces +X; the plan's graded walk runs 4 m from door to street.
	box(PRECINCT + Vector3(0, 4, 0), Vector3(14, 8, 14))
	civic.sites.append({"id": "police", "name": "Fixture Precinct", "position": [PRECINCT.x, 0.0, PRECINCT.z], "yaw": PI * 0.5,
		"entry_world": [PRECINCT.x + 7.0, 0.0, PRECINCT.z], "approach_center": [PRECINCT.x + 11.0, 0.0, PRECINCT.z],
		"front_vector": [1.0, 0.0, 0.0]})
	# Hospital: front faces -X; its built model's PublicEntrance marker is preferred.
	box(HOSPITAL + Vector3(0, 5, 0), Vector3(20, 10, 20))
	civic.sites.append({"id": "hospital", "name": "Fixture Hospital", "position": [HOSPITAL.x, 0.0, HOSPITAL.z], "yaw": -PI * 0.5,
		"entry_world": [HOSPITAL.x - 10.0, 0.0, HOSPITAL.z], "approach_center": [HOSPITAL.x - 15.0, 0.0, HOSPITAL.z],
		"front_vector": [-1.0, 0.0, 0.0]})
	var model := Node3D.new()
	model.set_meta("civic_id", "hospital")
	civic.add_child(model)
	model.global_position = HOSPITAL
	model.rotation.y = -PI * 0.5
	var marker := Marker3D.new()
	marker.name = "PublicEntrance"
	marker.position = Vector3(-4.0, 0.0, 9.5)
	marker.set_meta("approach_local", Vector3(0, 0, 1))
	model.add_child(marker)

func _routes_and_facilities() -> void:
	var status: Dictionary = law.get_status()
	check(status.has("wanted") and status.has("phase") and status.has("message") and status.has("recovering") and law.get("recovering") == false,
		"status exposes wanted/phase/message/recovering and a recovering property")
	check(law.routes.point_count() == 8, "both fixture streets are indexed as one keyed point per vertex")
	var plan: Dictionary = law.routes.route(Vector3(-20, 0, 6), Vector3.ZERO, 380.0)
	var points: PackedVector3Array = plan.points
	check(points.size() >= 3 and bool(plan.complete), "a destination behind a wall is reached along the street graph (%d points)" % points.size())
	var crosses := false
	var previous := Vector3(-20, 0, 6)
	for point in points:
		crosses = crosses or segment_hits_wall(previous, point)
		previous = point
	check(not crosses, "no route leg passes through the wall")
	var direct: Dictionary = law.routes.route(Vector3(30, 0, 30), Vector3(40, 0, 36), 380.0)
	check((direct.points as PackedVector3Array).size() == 1, "a short clear leg walks straight")
	var nowhere: Dictionary = law.routes.route(Vector3(150, 0, -150), Vector3(160, 0, -190), 380.0)
	check((nowhere.points as PackedVector3Array).is_empty(), "no street within reach means no guessed route")
	var hospital: Dictionary = Facilities.release_point(arena, "hospital", player)
	check(bool(hospital.ok) and Vector3(hospital.position).distance_to(HOSPITAL_RELEASE) < 0.3, "hospital release uses the built entrance marker, outside the footprint (%s)" % str(hospital.get("position")))
	check(capsule_clear(Vector3(hospital.position)) and absf(float(hospital.yaw) + PI * 0.5) < 0.01, "hospital release spot is clear and faces away from the building")
	var blocker := box(PRECINCT + Vector3(11, 1, 0), Vector3(1.2, 2, 1.2))
	await frames(2)
	var precinct: Dictionary = Facilities.release_point(arena, "police", player)
	var at: Vector3 = precinct.get("position", Vector3.INF)
	check(bool(precinct.ok) and Vector2(at.x - PRECINCT.x - 11.0, at.z - PRECINCT.z).length() > 0.9 and capsule_clear(at),
		"a blocked precinct approach falls back to another clear spot on the plan walk (%s)" % str(at))
	check(int(precinct.checks) > 1 and absf(float(precinct.yaw) - PI * 0.5) < 0.01, "the blocked candidate was rejected; release faces the street")
	blocker.free()
	await frames(2)

func _witness_line_of_sight() -> void:
	var at := Vector3(100, 0, 60)
	reset_player(at)
	var seer := spawn("civ_seer", "mama", at + Vector3(6, 0, 6), -Vector3(6, 0, 6))
	var hidden := spawn("civ_hidden", "mama", at + Vector3(-6, 0, 6), Vector3(6, 0, -6))
	var away := spawn("civ_away", "mama", at + Vector3(0, 0, -8), Vector3(0, 0, -1))
	var distant := spawn("civ_distant", "mama", at + Vector3(40, 0, 0), Vector3(-1, 0, 0))
	var cover := box(at + Vector3(-3, 1.5, 3), Vector3(2.5, 3, 2.5))
	await frames(2)
	var rays_before: int = law.witness_rays
	var civilian_before: int = law.report_sources.civilian
	var filed_before: int = law.reports_filed
	law.on_offense("assault", at + Vector3(0, 0, 1), "")
	await advance(0.3)
	var scan: Dictionary = law.last_scan
	var observed: Array = scan.get("observed", [])
	check(observed.size() == 1 and observed.has("civ_seer"), "only the facing witness with clear sight saw the assault (%s)" % str(observed))
	check(int(scan.rays) == 2 and law.witness_rays - rays_before == 2, "two facing candidates cost one sight ray each; facing away costs none")
	check(int(scan.candidates) == 3, "the far bystander is outside the visual radius (%d candidates)" % int(scan.candidates))
	check(law.reports_filed == filed_before and law.wanted == 0 and law.phase == "reported", "a civilian report is a delayed call, not instant police knowledge")
	var filed: bool = await advance_until(func(): return law.reports_filed == filed_before + 1, 2.0)
	check(filed and law.wanted == 1 and law.report_sources.civilian == civilian_before + 1, "the witness's call files after the delay and identifies the offender")
	check(law.last_known_position.distance_to(at) < 0.1 and str(law.message).begins_with("WANTED 1/3"), "police know only where the offender was reported; HUD message shows the tier")
	await dismiss([seer, hidden, away, distant])
	cover.free()
	# Police detection: an officer who sees it acts at once and fights through combat.
	reset_player(at)
	var officer := spawn("patrol_officer_5", "cop_dan", at + Vector3(9, 0, -2), Vector3(-9, 0, 2), true)
	await frames(2)
	var reports: int = law.reports_filed
	var police_before: int = law.report_sources.police
	law.on_offense("assault", at + Vector3(0, 0, 1), "")
	await advance(0.3)
	check(law.reports_filed == reports + 1 and law.report_sources.police == police_before + 1 and law.wanted == 1, "a police witness identifies the offender immediately")
	var engaged: bool = await advance_until(func(): return officer.combat_override, 1.0)
	check(engaged and combat.get_status().actors.has(officer.actor_id), "the detecting officer engages through combat.engage_actor")
	check(law.phase == "pursuit" and int(law.get_status().responder_count) == 1, "police detection starts a pursuit with that officer as the responder")
	await dismiss([officer])

func _unobserved_and_silenced() -> void:
	var lonely := Vector3(140, 0, 140)
	reset_player(lonely)
	await frames(2)
	var unseen: int = law.unobserved_offenses
	var scheduled: int = law.reports_scheduled
	law.on_offense("assault", lonely + Vector3(0, 0, 1), "")
	await advance(0.3)
	check(law.unobserved_offenses == unseen + 1 and law.reports_scheduled == scheduled and law.wanted == 0 and law.heat == 0.0,
		"an unobserved assault creates no report, heat or wanted level")
	check(str(law.last_scan.get("outcome", "")) == "unobserved", "the scan records the crime as unobserved")
	var spot := Vector3(100, 0, 120)
	reset_player(spot)
	var caller := spawn("civ_caller", "mama", spot + Vector3(5, 0, 5), -Vector3(5, 0, 5))
	await frames(2)
	law.on_offense("assault", spot + Vector3(0, 0, 1), "")
	await advance(0.3)
	check(int(law.get_status().pending_reports) == 1, "the witness's call is pending")
	combat._damage_target(caller, 999.0, "shot", caller.global_position + Vector3(0, 1.2, -2), false)
	check(caller.dead and combat.is_actor_dead("civ_caller"), "the fixture silences the witness before the call")
	var dropped: int = law.reports_dropped
	await advance(1.4)
	check(law.reports_dropped == dropped + 1 and law.wanted == 0, "a dead witness's report is never filed")
	await dismiss([caller])

func _gunfire_witnesses() -> void:
	var scene := Vector3(-100, 0, 100)
	reset_player(scene)
	var listener := spawn("civ_listener", "mama", scene + Vector3(12, 0, 0), Vector3(-1, 0, 0))
	var wall_a := box(scene + Vector3(6, 1.5, 0), Vector3(0.6, 3, 6))
	var officer := spawn("patrol_officer_6", "cop_steve", scene + Vector3(-14, 0, 0), Vector3(1, 0, 0), true)
	var wall_b := box(scene + Vector3(-7, 1.5, 0), Vector3(0.6, 3, 6))
	var far := spawn("civ_far", "mama", scene + Vector3(0, 0, -60), Vector3(0, 0, 1))
	await frames(2)
	var scheduled: int = law.reports_scheduled
	var heard_before: int = law.report_sources.heard
	law.on_offense("shooting", scene + Vector3(0, 1.3, 0), "")
	await advance(0.3)
	var scan: Dictionary = law.last_scan
	var heard: Array = scan.get("heard", [])
	check((scan.observed as Array).is_empty() and heard.has("civ_listener") and heard.has("patrol_officer_6"), "gunfire behind walls is heard, not seen (%s)" % str(heard))
	check(not heard.has("civ_far"), "a resident beyond hearing range never notices")
	check(law.reports_scheduled == scheduled + 1 and str(scan.outcome) == "heard", "a listener calls in shots fired without identifying anyone")
	var investigating: bool = await advance_until(func(): return law._responders.has("patrol_officer_6"), 0.6)
	check(investigating and str(law._responders.get("patrol_officer_6", {}).get("purpose", "")) == "investigate", "the officer who heard it investigates the sound at once")
	await advance_until(func(): return law.report_sources.heard == heard_before + 1, 2.0)
	check(law.report_sources.heard == heard_before + 1 and law.wanted == 0 and law.heat == 0.0, "an unidentified shots-fired report raises no wanted level")
	var arrived: bool = await advance_until(func(): return officer.global_position.distance_to(scene) < 2.5, 20.0)
	check(arrived, "the investigating officer walks around the wall to the shot location (%.1f m)" % officer.global_position.distance_to(scene))
	check(not officer.combat_override and law.wanted == 0 and law.phase == "investigating", "seeing an unidentified person at the scene starts no pursuit")
	await dismiss([listener, officer, far])
	wall_a.free()
	wall_b.free()

func _dispatch_pursuit_search_escape() -> void:
	var scene := Vector3.ZERO
	reset_player(scene)
	var officer := spawn("patrol_officer_0", "cop_dan", Vector3(-20, 0, 6), Vector3(0, 0, 1), true)
	var spare := spawn("patrol_officer_1", "cop_steve", Vector3(40, 0, 40), Vector3(0, 0, 1), true)
	var witness := spawn("civ_witness", "mama", Vector3(6, 0, 6), Vector3(-6, 0, -6))
	var home: Vector3 = officer.global_position
	var speed: float = officer.speed
	var escapes: int = law.escapes
	await frames(2)
	law.on_offense("assault", scene + Vector3(0, 0, 1), "")
	var dispatched: bool = await advance_until(func(): return law._responders.has("patrol_officer_0"), 2.5)
	check(dispatched and law.wanted == 1 and law.dispatches >= 1, "the witness's report dispatches the nearest real patrol")
	check(int(law.get_status().responder_count) == 1 and not law._responders.has("patrol_officer_1") and not spare.has_meta("law_responder"),
		"tier one sends one responder; the spare patrol keeps its beat")
	check(officer.has_meta("law_responder") and officer.manual_target and officer.speed > speed, "the responder is marked, steered through its own movement and jogging")
	var state: Dictionary = law._responders.get("patrol_officer_0", {})
	check((state.get("path", []) as Array).size() >= 3, "the responder follows a multi-leg street route around the wall")
	home = state.get("home", home)
	var through := false
	var spotted := false
	for i in 60 * 30:
		await step()
		through = through or inside_wall(officer.global_position, 0.05)
		if officer.combat_override:
			spotted = true
			break
	check(spotted, "the responder reaches line of sight and combat engages them (%s)" % str(officer.global_position))
	check(not through, "the responder never passed through the wall")
	check(law.phase == "pursuit" and law.last_known_position.distance_to(scene) < 0.2, "pursuit, with the last known position at the sighting")
	# Break line of sight: the player slips behind a second wall.
	var hide := Vector3(25, 0, -10)
	var screen := box(Vector3(15, 1.5, -10), Vector3(1, 3, 30))
	await frames(2)
	put_player(hide)
	var searching: bool = await advance_until(func(): return str(law._responders.get("patrol_officer_0", {}).get("mode", "")) == "search", 4.0)
	check(searching and not officer.combat_override, "after losing sight law disengages the officer and starts a search")
	check(law.last_known_position.distance_to(scene) < 0.5, "the last known position stays where they were seen, not behind the wall")
	var omniscient := false
	for i in 60 * 2:
		await step()
		if not officer.combat_override and officer.has_target and officer.target.distance_to(hide) < 6.0:
			omniscient = true
	check(not omniscient, "the search never targets the hidden player's real position")
	check(law.phase in ["search", "cooldown"], "phase reports search or cooldown (%s)" % law.phase)
	var escaped: bool = await advance_until(func(): return law.wanted == 0, 12.0)
	check(escaped and law.escapes == escapes + 1 and law.phase == "clear", "unseen through search and cooldown, the player escapes")
	var returned: bool = await advance_until(func(): return not law._responders.has("patrol_officer_0"), 40.0)
	check(returned and officer.global_position.distance_to(home) < 1.6, "the officer walks back to their beat point (%.1f m)" % officer.global_position.distance_to(home))
	check(is_equal_approx(officer.speed, speed) and not officer.manual_target and not officer.has_meta("law_responder"), "their walking speed, patrol ownership and marker are restored")
	screen.free()
	await dismiss([officer, spare, witness])

func _surrender_at_precinct() -> void:
	var spot := Vector3(40, 0, 80)
	reset_player(spot)
	check(not law.handle_input(key(KEY_G)), "G does nothing (and is not consumed) when not wanted")
	var officer := spawn("patrol_officer_2", "cop_dan", spot + Vector3(8, 0, 0), Vector3(-1, 0, 0), true)
	await frames(2)
	var arrests: int = law.arrests
	var money: int = wallet.money
	var debits := wallet.debits.size()
	law.on_offense("assault", spot + Vector3(0, 0, 1), "")
	await advance_until(func(): return law.wanted == 1 and officer.combat_override, 1.5)
	check(law.wanted == 1 and bool(law.get_status().surrender_available), "a nearby officer with sight makes surrender available")
	check(law.handle_input(key(KEY_G)) and law.recovering and str(law.get_status().recovery.kind) == "arrest", "G surrenders to the officer")
	check(not officer.combat_override, "the officer stops fighting a surrendering player")
	await advance(0.2)
	check(not player.enabled, "the player is held still with hands up")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	check(law.handle_input(key(KEY_1)) and law.handle_input(click) and not law.handle_input(InputEventMouseMotion.new()),
		"world keys and clicks are held during the staged transition; looking around is not")
	var done: bool = await advance_until(func(): return not law.recovering, 3.0)
	var release: Dictionary = law.last_release
	check(done and bool(release.get("ok", false)) and str(release.get("site", "")) == "police", "custody ends at the precinct release point")
	check(Vector2(player.global_position.x - (PRECINCT.x + 11.0), player.global_position.z - PRECINCT.z).length() < 2.0, "released on the precinct's planned approach walk")
	check(capsule_clear(player.global_position), "the released player overlaps no building, person or vehicle")
	check(wallet.debits.size() == debits + 1 and str(wallet.debits[-1].reason) == "arrest_fine" and wallet.money == money - int(Law.ARREST_FINES[1]),
		"one tier-one fine is debited through progression")
	check(law.wanted == 0 and law.heat == 0.0 and combat.health == 100.0 and player.enabled, "wanted cleared, player healed and free to move")
	await advance(1.0)
	check(wallet.debits.size() == debits + 1 and law.arrests == arrests + 1, "the fine is never charged twice")
	await dismiss([officer])

func _hospital_recovery() -> void:
	var spot := Vector3(-40, 0, 40)
	reset_player(spot)
	await frames(2)
	var debits := wallet.debits.size()
	var completed: int = law.recoveries_completed
	var defeated := defeats
	check(combat._hurt_player(1000.0) and law.recovering and defeats == defeated + 1, "combat's defeat signal starts the hospital recovery")
	var sequence: int = law._recovery_sequence
	law.on_player_defeated()
	law.on_player_defeated()
	check(law._recovery_sequence == sequence and str(law.get_status().recovery.kind) == "hospital", "repeated defeat events keep a single recovery")
	await advance(0.2)
	check(player.global_position.distance_to(spot) < 0.01 and combat.downed > 0.0 and combat.health == 0.0, "the player stays down where they fell: no instant heal")
	await advance_until(func(): return str(law.get_status().recovery.get("stage", "")) == "fade_out", 1.0)
	await advance(0.05)
	check(float(law.get_status().cue_alpha) > 0.3, "a visible recovery cue fades the view")
	var held: Dictionary = law.get_status().recovery
	arena.paused = true
	await advance(1.0)
	var paused_status: Dictionary = law.get_status()
	check(str(paused_status.recovery.stage) == str(held.stage) and is_equal_approx(float(paused_status.recovery.time), float(held.time))
		and wallet.debits.size() == debits and player.global_position.distance_to(spot) < 0.01, "a paused menu freezes the recovery: no relocation, no bill")
	check(not bool(paused_status.cue_visible), "the fade never covers a paused menu")
	arena.paused = false
	inspector.active = true
	await advance(1.0)
	check(is_equal_approx(float(law.get_status().recovery.time), float(held.time)) and wallet.debits.size() == debits, "the inspector also holds the recovery")
	inspector.active = false
	var done: bool = await advance_until(func(): return not law.recovering, 3.0)
	var release: Dictionary = law.last_release
	check(done and bool(release.get("ok", false)) and Vector3(release.get("position", Vector3.INF)).distance_to(HOSPITAL_RELEASE) < 0.3, "the player wakes at the real hospital entrance")
	check(player.global_position.distance_to(HOSPITAL_RELEASE) < 0.1 and capsule_clear(player.global_position), "the hospital release spot is where the player stands, clear of collision")
	check(wallet.debits.size() == debits + 1 and str(wallet.debits[-1].reason) == "hospital_bill" and int(wallet.debits[-1].amount) == Law.HOSPITAL_FEE, "one hospital bill is debited")
	check(combat.health == 100.0 and combat.downed == 0.0 and player.enabled, "recovery heals through combat.recover_player and frees the player")
	await advance(1.0)
	check(wallet.debits.size() == debits + 1 and law.recoveries_completed == completed + 1, "recovery completes once and never bills again")
	# An unaffordable bill: progression keeps the balance non-negative.
	wallet.money = 40
	reset_player(spot)
	await frames(2)
	combat._hurt_player(1000.0)
	await advance_until(func(): return not law.recovering, 4.0)
	check(law.last_fee == 40 and wallet.money == 0, "an unaffordable bill takes only what the player has")
	# Driving: the forced exit happens before relocation, retrying a refusal.
	wallet.money = 500
	reset_player(spot)
	driving.active = true
	driving.refuse = 1
	await frames(2)
	combat._hurt_player(1000.0)
	var exited: bool = await advance_until(func(): return not law.recovering, 4.0)
	check(exited and not driving.active and driving.exits.size() >= 2 and not driving.exits.has(false), "a defeated driver is forced out of the vehicle (retrying once refused)")
	check(bool(law.last_release.get("ok", false)), "relocation proceeded only after the vehicle exit")
	driving.exits.clear()

func _bounded_work() -> void:
	var spot := Vector3(-140, 0, -140)
	reset_player(spot)
	var ring: Array = []
	for i in 14:
		var angle := TAU * float(i) / 14.0
		var at := spot + Vector3(sin(angle), 0, cos(angle)) * 9.0
		ring.append(spawn("civ_ring_%d" % i, "mama", at, spot - at))
	await frames(2)
	var scans: int = law.witness_scans
	var merged: int = law.offenses_merged
	for i in 40:
		law.on_offense("shooting", spot + Vector3(0, 1.3, 0), "")
	check(int(law.get_status().pending_events) == 1 and law.offenses_merged == merged + 39, "an automatic burst folds into one bounded offense event")
	await advance(0.3)
	var scan: Dictionary = law.last_scan
	check(law.witness_scans == scans + 1 and int(scan.rays) <= Law.MAX_WITNESS_CHECKS and int(scan.candidates) <= Law.MAX_WITNESS_RESULTS,
		"one witness scan with at most %d sight rays for 40 rounds" % Law.MAX_WITNESS_CHECKS)
	check(int(scan.count) == 40, "the scan knows the burst size")
	await advance_until(func(): return law.wanted > 0, 2.0)
	for i in 20:
		law._file({"kind": "stomp", "at": spot, "player_at": spot, "identified": true, "severity": 80.0, "lethal": true, "time": law._clock, "source": "police"})
	check(law.wanted == Law.MAX_WANTED and law.heat <= Law.MAX_HEAT, "wanted tier and heat stay bounded (%d, %.0f)" % [law.wanted, law.heat])
	check(int(law.get_status().responder_count) <= Law.MAX_RESPONDERS, "responders stay within the cap")
	await dismiss(ring)
