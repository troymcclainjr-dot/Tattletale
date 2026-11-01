extends Node
const Crowd := preload("res://scripts/city/city_crowd.gd")
const Attention := preload("res://scripts/city/city_crowd_attention.gd")
const Daily := preload("res://scripts/city/city_resident_actor.gd")
const Activity := preload("res://scripts/city/city_resident_activity.gd")
class Arena extends Node3D:
	var player: Node3D
	var park_courts: Node3D
var failures := 0
func _ready() -> void:
	_run.call_deferred()
func check(ok: bool, label: String) -> void:
	failures += int(not ok)
	print("[neighborhood_activity] %s %s" % ["PASS" if ok else "FAIL", label])
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
func _run() -> void:
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	var arena := Arena.new()
	add_child(arena)
	arena.player = Node3D.new()
	arena.add_child(arena.player)
	arena.player.position = Vector3(0, 0, -5)
	var crowd := Crowd.new()
	arena.add_child(crowd)
	crowd.level = arena
	for index in 48:
		crowd.residents.append({"position": Vector3(float(index % 8) * 1.2, .012, float(index / 8) * 1.2), "yaw": 0.0, "pose": 0, "activity": "circle", "stable_id": "crowd_%d" % index})
	for group in 12:
		crowd._circle_groups.append({"indices": [group * 4, group * 4 + 1, group * 4 + 2, group * 4 + 3]})
	crowd._index_social_groups()
	var attention := Attention.new()
	await get_tree().physics_frame
	var partners := {}
	var positions: Array[Vector3] = []
	for resident in crowd.residents:
		positions.append(resident.position)
	var bounded := true
	for frame in 800:
		crowd._clock += .1
		attention.begin_tick(crowd)
		# Rotate fixture cohorts, matching the provider's strided fairness.
		for index in range(frame % 4, 48, 4):
			attention.present(crowd, index)
		bounded = bounded and attention.updates <= Attention.MAX_UPDATES and attention.queries <= Attention.MAX_DECISIONS and attention.active.size() <= Attention.MAX_ACTIVE
		if attention.active.has(0) and int(attention.active[0].partner) >= 0:
			partners[attention.active[0].partner] = true
	check(bounded and attention.selections > 10 and attention.turns > 0, "crowd attention performs real selections/turns within 24 actors, 12 updates and 2 rays per tick")
	check(partners.size() >= 2, "conversation changes partners within the retained group")
	var unchanged := crowd.residents.size() == 48
	for index in 48:
		unchanged = unchanged and positions[index] == crowd.residents[index].position and crowd.residents[index].stable_id == "crowd_%d" % index
	check(unchanged, "attention never changes placement, roster or stable identities")
	crowd.residents[0].panic = true
	attention.begin_tick(crowd)
	check(not attention.active.has(0), "panic immediately releases attention ownership")
	crowd.residents[0].erase("panic")
	crowd.residents[0].attention_court = Vector3(0, .012, 6)
	var watch := Attention.new()
	watch.begin_tick(crowd)
	watch.present(crowd, 0)
	check(watch.watches == 1 and watch.active[0].kind == "watching_court", "safe existing court-edge anchor can watch court")
	var wall := box(Vector3(0, 1, 3), Vector3(2, 3, .2), 2)
	await get_tree().physics_frame
	var occluded := Attention.new()
	occluded.begin_tick(crowd)
	occluded.present(crowd, 0)
	check(occluded.watches == 0 and occluded.active[0].kind == "listening", "wall prevents watching through buildings")
	wall.free()
	arena.player.position = Vector3(200, 0, 0)
	attention.begin_tick(crowd)
	attention.present(crowd, 0)
	check(attention.active.is_empty() and attention.updates == 0 and attention.queries == 0, "far attention sleeps without query or turn work")
	crowd.free()
	arena.player.position = Vector3(8, 0, -5)
	box(Vector3(0, -.25, 0), Vector3(80, .5, 80), 1)
	var actor := Daily.new()
	arena.add_child(actor)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/pen_lucy_residents.json"))
	var definition: Dictionary = data.residents[0].duplicate(true)
	definition.id = "daily_activity_fixture"
	actor.build_resident(arena, definition)
	actor.global_position = Vector3(0, .012, 0)
	var corridor: Array[Vector3] = []
	for index in 9:
		corridor.append(Vector3(0, .012, index))
	var route := {"points": corridor, "anchors": {"home": 0, "work": 0, "sleep": 0, "leisure": 8}}
	var entry: Array[Vector3] = [corridor[0]]
	actor.assign_route(entry, "work", "Fixture frontage")
	var activity := Activity.new()
	await get_tree().physics_frame
	var phases := {}
	var continuous := true
	for frame in 3900:
		var before: Vector3 = actor.position
		activity.begin_tick()
		actor.tick(1.0 / 60.0)
		activity.tick(actor, route, 1.0 / 60.0)
		phases[actor.local_activity.phase] = true
		continuous = continuous and before.distance_to(actor.position) <= actor.speed / 60.0 + .002 and absf(actor.position.x) < .01
		if actor.local_activity.phase == "settled":
			break
		if frame % 60 == 0:
			await get_tree().physics_frame
	check(phases.has("arriving") and phases.has("dwelling") and phases.has("short_pause") and phases.has("returning") and phases.has("settled"), "real actor arrives, dwells, takes short walk and returns")
	check(continuous and actor.position.distance_to(corridor[0]) < .21 and actor.distance_walked > 5.0, "short trip follows physical corridor and returns without teleporting")
	check(actor.actor_id == definition.id and actor.activity == "work" and actor.schedule_transitions == 1, "local trip retains identity and timetable destination")
	check(activity.status().max_starts <= 1 and activity.status().physics_queries == 0, "activity planning adds no physics queries and starts at most one route per tick")
	var held: Dictionary = actor.local_activity.duplicate(true)
	actor.bicycle_override = true
	var before: Vector3 = actor.position
	actor.tick(.1)
	activity.tick(actor, route, .1)
	check(actor.local_activity == held and actor.position == before, "bicycle interruption pauses activity and movement")
	actor.bicycle_override = false
	actor.set_meta("police_custody_completed", true)
	check(not Activity.available(actor), "custody cannot restart routines")
	actor.remove_meta("police_custody_completed")
	actor.dead = true
	check(not Activity.available(actor), "dead identity cannot restart routines")
	actor.dead = false
	arena.player.position = Vector3(200, 0, 0)
	activity.tick(actor, route, 10.0)
	check(actor.local_activity == held, "distant resident dwell remains asleep")
	actor.assign_route(entry, "home", "Home frontage")
	check(actor.local_activity.phase == "travelling" and actor.local_activity.home_path.is_empty(), "schedule/recovery assignment discards stale local excursion")
	print("[neighborhood_activity] attention=", attention.status(), " daily=", activity.status(), " failures=", failures)
	get_tree().quit(1 if failures else 0)
