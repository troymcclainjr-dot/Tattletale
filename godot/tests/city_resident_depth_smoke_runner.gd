extends Node
const Daily := preload("res://scripts/city/city_resident_actor.gd")
const Activity := preload("res://scripts/city/city_resident_activity.gd")

class Arena extends Node3D:
	var player: Node3D

var failures := 0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	failures += int(not ok)
	print("[resident_depth] %s %s" % ["PASS" if ok else "FAIL", label])

func box(at: Vector3, size: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	body.position = at
	return body

func settle(actor) -> void:
	actor.activity = "leisure"
	actor.route_completed = true
	actor.route_cursor = actor.route_points.size()
	actor.has_target = false
	actor.moving = false
	actor.local_activity = {"phase": "dwelling", "elapsed": 3.0, "home_path": []}
	actor.social_cooldown = 0.0
	actor.social_remaining = 0.0
	actor._speech_remaining = 0.0

func _run() -> void:
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	var arena := Arena.new()
	add_child(arena)
	arena.player = Node3D.new()
	arena.add_child(arena.player)
	arena.player.position = Vector3(5, 0, 0)
	box(Vector3(0, -.25, 0), Vector3(80, .5, 80), 1)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/pen_lucy_residents.json"))
	var roster_ok: bool = data.residents.size() == 40
	for definition in data.residents:
		roster_ok = roster_ok and definition.schedule.size() == 6
	check(roster_ok, "forty persistent IDs retain six-slot checkpoint-compatible schedules")
	var actor := Daily.new()
	arena.add_child(actor)
	actor.build_resident(arena, data.residents[0])
	actor.position = Vector3(0, .012, 0)
	var partner := Daily.new()
	arena.add_child(partner)
	partner.build_resident(arena, data.residents[1])
	partner.position = Vector3(2, .012, 0)
	var corridor: Array[Vector3] = []
	for i in 25:
		corridor.append(Vector3(0, .012, i))
	var route := {"points": corridor, "anchors": {"work": 0, "home": 0, "sleep": 0, "leisure": 24}}
	var start: Array[Vector3] = [corridor[0]]
	actor.assign_route(start, "work", "Existing work frontage")
	actor.route_completed = true
	actor.local_activity = {"phase": "dwelling", "elapsed": 30.0, "home_path": []}
	var activity := Activity.new()
	activity.tick(actor, route, .1)
	check(actor.route_points.size() >= 9 and actor.route_points.size() <= 19, "purposeful outing selects 8–18 checked sidewalk metres")
	var outbound: Array[Vector3] = actor.route_points.duplicate()
	var returning: Array[Vector3] = actor.local_activity.home_path.duplicate()
	returning.reverse()
	check(returning == outbound and actor.schedule_transitions == 1, "out-and-back retains exact checked route and timetable identity")
	check(actor.get_status().local_destination == Activity.outing(actor.actor_id).label, "visible stop purpose is deterministic per resident")
	partner.assign_route(start, "work", "Existing work frontage")
	partner.global_position = corridor[0]
	partner.route_completed = true
	partner.local_activity = {"phase": "dwelling", "elapsed": 30.0, "home_path": []}
	activity.tick(partner, route, .1)
	check(activity.starts == 1, "only one local route starts per provider tick")
	# A blocked walk cannot transition to a destination pause just because time passes.
	actor.route_completed = false
	actor.has_target = true
	actor.blocked = true
	for i in 30:
		activity.begin_tick()
		activity.tick(actor, route, .25)
	check(actor.local_activity.phase == "short_walk" and activity.returns == 0, "blocked destination never fakes arrival or return")
	actor.assign_route(start, "home", "Home frontage")
	check(actor.local_activity.home_path.is_empty() and actor.local_activity.phase == "travelling", "schedule change discards obsolete outing")
	actor.position = Vector3(0, .012, 0)
	partner.position = Vector3(2, .012, 0)
	settle(actor)
	settle(partner)
	var wall := box(Vector3(1, 1, 0), Vector3(.2, 3, 3), 2)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var social := Activity.new()
	for i in 4:
		social.tick_social([actor, partner], .25)
	check(social.greetings == 0 and social.social_queries == 1, "one visibility ray rejects neighbor greeting through wall")
	wall.free()
	await get_tree().physics_frame
	for i in 4:
		social.tick_social([actor, partner], .25)
	check(social.greetings == 1 and actor.social_partner == partner and partner.social_partner == actor, "clear nearby residents exchange named greetings")
	check(social.social_queries <= 1 and social.social_candidates <= Activity.MAX_SOCIAL_CANDIDATES, "social work respects one ray and forty candidates per second")
	var before: Vector3 = actor.position
	var elapsed: float = actor.local_activity.elapsed
	activity.tick(actor, route, .25)
	check(actor.position == before and actor.local_activity.elapsed == elapsed, "greeting holds local outing without relocating either person")
	partner.combat_override = true
	actor._update_local_greeting(.1)
	check(actor.social_remaining == 0.0 and not Activity.social_ready(partner), "incident immediately releases social ownership")
	partner.combat_override = false
	settle(actor)
	settle(partner)
	actor.set_meta("police_custody", true)
	check(not Activity.social_ready(actor), "custody cannot join greetings")
	actor.remove_meta("police_custody")
	actor.dead = true
	check(not Activity.social_ready(actor), "dead identity cannot join greetings")
	actor.dead = false
	actor.activity = "sleep"
	check(not Activity.social_ready(actor), "sleeping resident is not woken for social animation")
	actor.activity = "leisure"
	arena.player.position = Vector3(200, 0, 0)
	var far_social := Activity.new()
	for i in 4:
		far_social.tick_social([actor, partner], .25)
	check(far_social.greetings == 0 and far_social.social_queries == 0 and far_social.social_candidates == 0, "distant social life adds no query or pair work")
	# A walk begun near the player can cross the 26m presentation boundary.
	# Arrival must still complete its return lifecycle rather than strand a body.
	actor.local_activity = {"phase": "short_pause", "elapsed": 30.0, "home_path": start.duplicate()}
	activity.begin_tick()
	activity.tick(actor, route, .1)
	check(actor.local_activity.phase == "returning", "already-started outing returns even outside presentation radius")
	print("[resident_depth] failures=", failures)
	get_tree().quit(1 if failures else 0)
