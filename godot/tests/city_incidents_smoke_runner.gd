extends Node
## Neighborhood incidents in a small physics arena with real combat and police:
## a jaywalk the player watched is reported from the phone and ends with an
## officer's warning (status callbacks report_received → responding → on_scene →
## resolved); an unwitnessed act cannot be reported (the phone falls back to the
## ordinary call) and later expires; a wall blocks the player's sight while a
## neighbor's clear line counts; duplicates never dispatch twice; the offender
## cannot report and the caller is never a suspect; an unreachable scene closes
## as unanswered; a theft the victim calls in ends in custody; a street fight is
## called in by a witness; records save, validate and restore; observation stays
## inside its ray budget and failed spawns never consume an incident ID.
const Incidents := preload("res://scripts/city/city_incidents.gd")
const Assistance := preload("res://scripts/city/city_police_assistance.gd")
const Combat := preload("res://scripts/city/city_combat.gd")
const Law := preload("res://scripts/city/city_law.gd")
const Player := preload("res://scripts/city/city_player.gd")
const Actor := preload("res://scripts/city/city_npc_actor.gd")

class PeopleFixture:
	extends Node3D
	var actors: Dictionary = {}
	var crowd: Node3D
	func _route_distance(_at: Vector3) -> float:
		return 0.0

class PhoneFixture:
	extends Node3D
	var active := false
	var statuses: Array[String] = []
	func set_report_status(message: String) -> void:
		statuses.append(message)
	func suspend() -> void:
		pass

class Arena:
	extends Node3D
	var player: CharacterBody3D
	var npcs: Node3D
	var residents: Node3D
	var combat: Node3D
	var law: Node
	var police_assistance: Node
	var paused := false

var arena: Arena
var player: CharacterBody3D
var phone: PhoneFixture
var combat: Node3D
var law: Node
var assistance: Node3D
var incidents: Node3D
var officer: CharacterBody3D
var witness: CharacterBody3D
var failures := 0
var statuses: Array[Dictionary] = []
var tracked: Node3D
var max_step := 0.0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	failures += int(not ok)
	print("[incidents] %s %s" % ["PASS" if ok else "FAIL", label])

func tick_once() -> void:
	combat.health = maxf(combat.health, 60.0)
	var before := tracked.global_position if is_instance_valid(tracked) else Vector3.INF
	combat.tick(1.0 / 60.0)
	assistance.tick(1.0 / 60.0)
	incidents.tick(1.0 / 60.0)
	if is_instance_valid(tracked) and before.is_finite():
		max_step = maxf(max_step, Vector2(tracked.global_position.x - before.x, tracked.global_position.z - before.z).length())
	await get_tree().physics_frame

func step(seconds: float) -> void:
	for i in ceili(seconds * 60.0):
		await tick_once()

func advance_until(condition: Callable, limit: float) -> bool:
	for i in ceili(limit * 60.0):
		if condition.call():
			return true
		await tick_once()
	return bool(condition.call())

func box(at: Vector3, size_: Vector3, layer := 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	var shape := CollisionShape3D.new()
	var form := BoxShape3D.new()
	form.size = size_
	shape.shape = form
	body.add_child(shape)
	arena.add_child(body)
	body.global_position = at
	return body

func person(id: String, cast: String, at: Vector3, yaw: float) -> CharacterBody3D:
	var actor := Actor.new()
	arena.npcs.add_child(actor)
	actor.build(arena, id, cast, "Neighbor")
	arena.npcs.actors[id] = actor
	actor.global_position = at
	actor.yaw = yaw
	actor.puppet.g.rotation.y = yaw
	return actor

func id_where(prefix: String, test: Callable) -> String:
	for i in 4000:
		var id := "%s_%d" % [prefix, i]
		if test.call(id):
			return id
	return prefix

func place_officer(at: Vector3, yaw: float) -> void:
	officer.global_position = at
	officer.yaw = yaw
	officer.puppet.g.rotation.y = yaw

func record(id: String) -> Dictionary:
	return incidents.get_incident(id)

func witness_ids(id: String) -> Array:
	var ids: Array = []
	for entry in record(id).get("witnesses", []):
		ids.append(str(entry.id))
	return ids

func status_names(id: String) -> Array:
	var names: Array = []
	for status in statuses:
		if str(status.incident_id) == id:
			names.append(str(status.status))
	return names

func police_incident_for(ref: String) -> Dictionary:
	for incident in assistance.get_status().incidents:
		if str(incident.get("ref", "")) == ref:
			return incident
	return {}

func calm() -> void:
	assistance.reset_state()
	incidents.reset_state()
	combat.recover_player()
	combat.health = 100.0
	tracked = null
	max_step = 0.0
	await step(0.2)

func _run() -> void:
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	arena = Arena.new()
	add_child(arena)
	box(Vector3(0, -0.5, 0), Vector3(240, 1, 240))
	player = Player.new()
	arena.add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector3(0, 0.012, 0)
	player.enabled = true
	player.camera_yaw = 0.0
	phone = PhoneFixture.new()
	arena.add_child(phone)
	player.phone = phone
	arena.player = player
	arena.npcs = PeopleFixture.new()
	arena.add_child(arena.npcs)
	arena.residents = PeopleFixture.new()
	arena.add_child(arena.residents)
	officer = person("patrol_officer_0", "cop_dan", Vector3(16, 0.012, 2), -PI * 0.5)
	var beat: Array[Vector3] = [Vector3(16, 0.012, 2), Vector3(16, 0.012, 8)]
	officer.set_patrol(beat)
	witness = person("neighbor_w", "liner_2", Vector3(0, 0.012, 22), PI)
	combat = Combat.new()
	arena.add_child(combat)
	combat.setup(arena)
	arena.combat = combat
	law = Law.new()
	arena.law = law
	assistance = Assistance.new()
	arena.add_child(assistance)
	assistance.setup(arena)
	assistance.search_seconds = 3.0
	assistance.secure_seconds = 1.0
	arena.police_assistance = assistance
	incidents = Incidents.new()
	arena.add_child(incidents)
	incidents.setup(arena)
	incidents.set_spawning_enabled(false)
	# Match pen_lucy_level._on_incident_report_status: the incident service
	# owns linked phone transitions; police keeps only unlinked/interim notices.
	incidents.report_status_changed.connect(func(status: Dictionary):
		statuses.append(status)
		if bool(status.get("phone", false)):
			phone.set_report_status(str(status.get("text", "Report updated."))))
	await step(0.1)
	check(assistance.incident_handler == incidents, "the incident service registers itself with police assistance")

	# ---- 1. A witnessed jaywalk, reported from the phone, ends with a warning.
	var walker := person("walker_a", "granny", Vector3(6, 0.012, 14), -PI * 0.5)
	var spawned: Dictionary = incidents.spawn_template_now("jaywalking", {"offender": "walker_a", "route": [Vector3(-6, 0.012, 14)]})
	var first := str(spawned.incident_id)
	check(bool(spawned.ok) and first == "inc_000001", "a jaywalk starts with a stable ID (%s)" % str(spawned))
	check(walker.combat_override and walker.has_meta("incident_performer") and combat.actor_mode(walker) == "unknown",
		"the real neighbor performs it under the incident service's control")
	tracked = walker
	max_step = 0.0
	var ended: bool = await advance_until(func(): return str(record(first).state) != "active", 20.0)
	check(ended and str(record(first).state) == "ended", "the act finishes on its own")
	check(Vector2(walker.global_position.x + 6.0, walker.global_position.z - 14.0).length() < 0.6,
		"the neighbor physically walked across (%s)" % str(walker.global_position))
	check(max_step <= 1.15 / 60.0 + 0.01, "no frame moved the performer more than one walking step (%.3f m)" % max_step)
	tracked = null
	check(witness_ids(first).has("player") and witness_ids(first).has("neighbor_w"),
		"the player and a facing neighbor with a clear line are recorded as witnesses: %s" % str(witness_ids(first)))
	var reportable: Array = incidents.reportable_for("player")
	check(reportable.size() == 1 and str(reportable[0].id) == first, "the player may report what they saw")
	var reply: Dictionary = incidents.report_from_phone(player.global_position)
	check(bool(reply.ok) and not bool(reply.fallback) and str(reply.incident_id) == first and not bool(reply.duplicate)
		and not str(reply.police_incident_id).is_empty(), "the phone files the witnessed incident (%s)" % str(reply.message))
	var linked := police_incident_for(first)
	check(not linked.is_empty() and str(linked.policy) == "warn" and (linked.suspects as Array).size() == 1
		and str(linked.suspects[0].id) == "walker_a", "police open a linked call naming only the offender, policy warn")
	var resolved: bool = await advance_until(func(): return str(record(first).state) == "resolved", 45.0)
	var rec := record(first)
	check(resolved and str(rec.resolution.get("outcome", "")) == "warned" and str(rec.resolution.get("by", "")) == "police",
		"an officer walked up and issued a warning (%s)" % str(rec.get("resolution", {})))
	var names := status_names(first)
	var ordered := names.find("report_received") >= 0 and names.find("report_received") < names.find("responding") \
		and names.find("responding") < names.find("on_scene") and names.find("on_scene") < names.find("resolved")
	check(ordered and str(rec.report.status) == "resolved", "status callbacks arrive in order: %s" % str(names))
	check(phone.statuses.any(func(text): return text.contains("issued a warning")), "the phone hears the outcome")
	var counters: Dictionary = assistance.get_status().counters
	check(int(counters.citations) == 1 and int(counters.rounds) == 0 and assistance.custody.records.is_empty() and not assistance.custody.has("walker_a"),
		"an infraction ends with a warning: no force and no custody")
	check(not walker.combat_override and not walker.has_meta("incident_performer") and not walker.dead,
		"the neighbor goes back to normal life after the warning")
	check((rec.evidence as Array).any(func(item): return str(item.ref) == "police_warning"), "the warning is on the record as evidence")
	await calm()
	walker.set_enabled(false)

	# ---- 2. Nobody saw it: it cannot be reported, and it expires.
	var hidden := person("walker_b", "granny", Vector3(-40, 0.012, -30), PI * 0.5)
	spawned = incidents.spawn_template_now("jaywalking", {"offender": "walker_b", "route": [Vector3(-28, 0.012, -30)]})
	var unseen := str(spawned.incident_id)
	check(bool(spawned.ok) and unseen == "inc_000002", "a second incident gets the next ID")
	ended = await advance_until(func(): return str(record(unseen).state) != "active", 20.0)
	check(ended and (record(unseen).witnesses as Array).is_empty() and int(incidents.get_status().counters.unwitnessed) >= 1,
		"behind the player and away from everyone, nobody witnessed it")
	var police_before: int = (assistance.get_status().incidents as Array).size()
	var refused: Dictionary = incidents.report_incident(unseen, "player")
	check(not bool(refused.ok) and str(refused.reason) == "not_witnessed" and (record(unseen).report as Dictionary).is_empty()
		and (assistance.get_status().incidents as Array).size() == police_before, "an unwitnessed report is refused and dispatches nobody")
	check(not incidents.reportable_for("player").any(func(item): return str(item.id) == unseen), "it is not offered as reportable")
	var fallback: Dictionary = incidents.report_from_phone(player.global_position)
	check(bool(fallback.fallback) and (record(unseen).report as Dictionary).is_empty(),
		"the phone falls back to the ordinary neighborhood call without touching the record")
	assistance.reset_state()
	incidents._clock += 2.0 * (Incidents.REPORT_WINDOW_MINUTES + 10.0) # Fixture clock: the window passes.
	await step(0.6)
	check(str(record(unseen).state) == "expired" and str(record(unseen).resolution.outcome) == "expired" and not hidden.combat_override,
		"unreported, it expires and the neighbor is released")
	check(str(incidents.report_incident(unseen, "player").reason) == "expired", "an expired incident cannot be reported")
	await calm()
	hidden.set_enabled(false)

	# ---- 3. Line of sight decides; duplicates never dispatch twice.
	var wall := box(Vector3(0, 1.5, 7), Vector3(30, 3, 0.4), 2)
	var second_witness := person("neighbor_d", "mailman", Vector3(-2, 0.012, 20), PI)
	var screened := person("walker_c", "granny", Vector3(6, 0.012, 14), -PI * 0.5)
	spawned = incidents.spawn_template_now("jaywalking", {"offender": "walker_c", "route": [Vector3(-6, 0.012, 14)]})
	var behind_wall := str(spawned.incident_id)
	await step(2.0)
	var faked: Dictionary = incidents.evaluate_photo(behind_wall, {"version": 2, "source": "phone_camera", "trusted": true,
		"photo_id": "photo_wall", "time": {"total_minutes": float(record(behind_wall).created_minutes) + 0.5},
		"camera": {"position": Vector3(0, 1.6, 0), "forward": Vector3(0, 0, 1)},
		"subjects": [{"id": "walker_c", "distance": 14.0, "line_of_sight": true, "position": screened.global_position + Vector3.UP * 1.2}]})
	check(not bool(faked.ok) and str(faked.reason) == "subject_not_visible" and not witness_ids(behind_wall).has("player"),
		"a photo listing the offender behind a wall is rejected by the live line-of-sight check")
	ended = await advance_until(func(): return str(record(behind_wall).state) != "active", 20.0)
	check(ended and not witness_ids(behind_wall).has("player") and witness_ids(behind_wall).has("neighbor_w") and witness_ids(behind_wall).has("neighbor_d"),
		"a wall blocks the player's line of sight; neighbors with a clear line still count: %s" % str(witness_ids(behind_wall)))
	check(str(incidents.report_incident(behind_wall, "player").reason) == "not_witnessed", "the player cannot report what the wall hid")
	check(str(incidents.report_incident(behind_wall, "walker_c").reason) == "reporter_is_offender", "the offender cannot file the report")
	var reports_before := int(assistance.get_status().counters.incident_reports)
	var dispatches_before := int(assistance.get_status().counters.foot_dispatches)
	var filed: Dictionary = incidents.report_incident(behind_wall, "neighbor_w", {"channel": "witness_call", "phone": false})
	check(bool(filed.ok) and not bool(filed.duplicate) and str(record(behind_wall).report.by) == "neighbor_w"
		and int(assistance.get_status().counters.incident_reports) == reports_before + 1, "a neighbor who saw it can report it")
	var dispatches_after := int(assistance.get_status().counters.foot_dispatches)
	var again: Dictionary = incidents.report_incident(behind_wall, "neighbor_w")
	var other: Dictionary = incidents.report_incident(behind_wall, "neighbor_d")
	check(bool(again.duplicate) and bool(other.duplicate) and (record(behind_wall).report.corroborating as Array) == ["neighbor_d"],
		"repeat reports are duplicates; a second witness corroborates")
	check(int(assistance.get_status().counters.incident_reports) == reports_before + 1 and int(assistance.get_status().counters.foot_dispatches) == dispatches_after
		and dispatches_after <= dispatches_before + 1, "duplicates never reach dispatch again")
	assistance.reset_state()
	check(str(record(behind_wall).resolution.get("outcome", "")) == "interrupted", "a called-off response closes honestly as interrupted")
	wall.queue_free()
	await calm()
	screened.set_enabled(false)

	# ---- 4. The caller is never a suspect; a provoked bike grudge is not a crime.
	var guarded: Dictionary = assistance.report_incident({"incident_ref": "fixture_ref", "policy": "detain", "kind": "theft",
		"suspects": ["player", "neighbor_d"], "at": Vector3(2, 0.012, 6), "reporter_id": "neighbor_d", "phone": false})
	var guarded_call := police_incident_for("fixture_ref")
	check(bool(guarded.ok) and not guarded_call.is_empty() and (guarded_call.suspects as Array).is_empty() and str(guarded_call.reporter) == "neighbor_d",
		"neither the player nor the reporting neighbor can be named a suspect")
	assistance.reset_state()
	var rammed_id := id_where("rammed", func(id: String) -> bool: return Combat.is_armed_id(id))
	var rammed := person(rammed_id, "ricky", Vector3(2, 0.012, 2), PI)
	combat.knockdown_from_bicycle(rammed, 4.0, Vector3(0, 0, 1))
	combat.recover_from_bicycle(rammed_id)
	check(combat.actor_mode(rammed) == "aggro", "fixture: a bike-crash grudge is attacking the rider")
	var call: Dictionary = assistance.request_help(player.global_position)
	check(int(call.suspects) == 0 and str(call.threat) == "none", "police do not treat retaliation for the rider's crash as a crime")
	combat.disengage_actor(rammed)
	rammed.set_enabled(false)
	await calm()

	# ---- 5. No officer can reach the scene: the report closes as unanswered.
	place_officer(Vector3(60, 0.012, 0), PI * 0.5)
	var stranded := person("walker_e", "granny", Vector3(6, 0.012, 14), -PI * 0.5)
	spawned = incidents.spawn_template_now("jaywalking", {"offender": "walker_e", "route": [Vector3(-6, 0.012, 14)]})
	var unreachable := str(spawned.incident_id)
	ended = await advance_until(func(): return str(record(unreachable).state) != "active", 20.0)
	var failures_before := int(assistance.get_status().counters.route_failures)
	var notices_before := phone.statuses.size()
	reply = incidents.report_incident(unreachable, "player")
	check(bool(reply.ok) and str(reply.message).contains("dispatch will keep trying"), "the report is taken honestly: %s" % str(reply.message))
	resolved = await advance_until(func(): return str(record(unreachable).state) == "resolved", 40.0)
	rec = record(unreachable)
	names = status_names(unreachable)
	check(resolved and str(rec.resolution.outcome) == "unanswered" and str(rec.report.status) == "unavailable"
		and names.has("report_received") and names.has("unavailable") and not names.has("responding"),
		"with no route the report resolves as unanswered: %s" % str(names))
	var route_notices := phone.statuses.slice(notices_before).filter(func(text): return text.contains("No officers could respond"))
	check(int(assistance.get_status().counters.route_failures) > failures_before and route_notices.size() == 1,
		"route failures are counted and the phone is told exactly once for this call")
	check(not stranded.combat_override and not stranded.has_meta("incident_performer"), "the neighbor is released after the unanswered call")
	await calm()
	stranded.set_enabled(false)

	# ---- 6. A theft the victim calls in ends in custody (performer handed over).
	place_officer(Vector3(16, 0.012, 2), PI * 0.5)
	var snatcher := person("snatcher_f", "ricky", Vector3(6, 0.012, 10), -PI * 0.5)
	var victim := person("victim_f", "granny", Vector3(3, 0.012, 10), PI * 0.5)
	spawned = incidents.spawn_template_now("bag_snatch", {"offender": "snatcher_f", "victim": "victim_f", "route": [Vector3(12, 0.012, 18)]})
	var theft := str(spawned.incident_id)
	check(bool(spawned.ok), "a bag snatch starts between two real neighbors")
	var called: bool = await advance_until(func(): return not (record(theft).report as Dictionary).is_empty(), 25.0)
	rec = record(theft)
	check(called and str(rec.report.by) == "victim_f" and str(rec.report.channel) == "witness_call" and witness_ids(theft).has("victim_f"),
		"the victim (a witness by being robbed) calls it in after a short delay")
	check((rec.evidence as Array).any(func(item): return str(item.kind) == "statement" and str(item.by) == "victim_f"), "the victim's statement is evidence")
	resolved = await advance_until(func(): return str(record(theft).state) == "resolved", 60.0)
	rec = record(theft)
	check(resolved and str(rec.resolution.outcome) == "arrested" and assistance.custody.has("snatcher_f") and int(assistance.get_status().counters.rounds) == 0,
		"police warned, detained and arrested the thief without a shot (%s)" % str(rec.get("resolution", {})))
	check(int(assistance.get_status().counters.handoffs) >= 1 and int(incidents.get_status().counters.handoffs) >= 1,
		"the incident service handed its performer to custody")
	await calm()
	check(not snatcher.combat_override and not snatcher.has_meta("police_custody"), "reset returns the held thief to normal life")
	snatcher.set_enabled(false)
	victim.set_enabled(false)

	# ---- 7. A street fight: combat runs it, a witness calls it in.
	var brawler_id := id_where("brawler", func(id: String) -> bool: return Combat.default_reaction(id) != "flee")
	var brawler := person(brawler_id, "ricky", Vector3(-8, 0.012, 12), PI * 0.5)
	var rival := person("victim_g", "granny", Vector3(-5.5, 0.012, 12), -PI * 0.5)
	spawned = incidents.spawn_template_now("street_fight", {"offender": brawler_id, "victim": "victim_g"})
	var fight := str(spawned.incident_id)
	check(bool(spawned.ok) and bool(combat.npc_fight_status(brawler_id).fighting) and witness_ids(fight).has("victim_g"),
		"a fight starts in combat; the person hit is a witness")
	called = await advance_until(func(): return not (record(fight).report as Dictionary).is_empty(), 20.0)
	rec = record(fight)
	var caller := str(rec.get("report", {}).get("by", ""))
	check(called and not caller in ["player", brawler_id] and witness_ids(fight).has(caller), "a witness calls the fight in (%s)" % caller)
	var fight_call := police_incident_for(fight)
	check(not fight_call.is_empty() and (fight_call.suspects as Array).any(func(s): return str(s.id) == brawler_id) and str(fight_call.policy) == "detain",
		"police respond to the attacker as a violent suspect")
	check(combat.deaths == 0 and not rival.dead, "nobody dies in the fight")
	await calm()
	combat.stop_npc_fight(brawler_id)
	await step(0.5)
	for body in [brawler, rival]:
		combat.disengage_actor(body)
		body.set_enabled(false)

	# ---- 8. Records save, validate and restore; tampering is rejected.
	var snap: Dictionary = incidents.snapshot_state()
	check(incidents.validate_state(snap).is_empty(), "the snapshot validates")
	var json = JSON.parse_string(JSON.stringify(snap))
	check(json is Dictionary and incidents.validate_state(json).is_empty(), "it survives a JSON round trip")
	var copy := Incidents.new()
	arena.add_child(copy)
	copy.level = arena
	var restored: Dictionary = copy.restore_state(json)
	check(bool(restored.ok) and int(restored.restored) == (snap.incidents as Array).size() and copy.next_sequence == incidents.next_sequence,
		"a fresh service restores every record and the ID sequence")
	check(str(copy.get_incident(first).resolution.outcome) == "warned" and str(copy.get_incident(unseen).state) == "expired",
		"outcomes survive the reload")
	var direct: Dictionary = incidents.snapshot_state().duplicate(true)
	check(bool(copy.restore_state(direct).ok) and copy.snapshot_state() == direct,
		"restore is faithful: snapshot_state() equals the restored section (world save rollback check)")
	var staged: Dictionary = (json as Dictionary).duplicate(true)
	staged.incidents[0].state = "active"
	staged.incidents[0].report = {}
	staged.incidents[0].resolution = {}
	staged.incidents[1].state = "active"
	staged.incidents[1].resolution = {}
	staged.incidents[2].state = "responding"
	staged.incidents[2].report = {"by": "neighbor_w", "channel": "witness_call", "minutes": 600.0, "police_incident_id": "incident_9",
		"status": "responding", "corroborating": [], "phone": false}
	staged.incidents[2].resolution = {}
	var reloaded := Incidents.new()
	arena.add_child(reloaded)
	reloaded.level = arena
	reloaded.set_spawning_enabled(false)
	check(bool(reloaded.restore_state(staged).ok) and str(reloaded.get_incident(behind_wall).state) == "responding",
		"a checkpoint taken mid-act and mid-response restores as written")
	reloaded.tick(0.1)
	check(str(reloaded.get_incident(first).state) == "ended" and str(reloaded.get_incident(unseen).state) == "cancelled"
		and str(reloaded.get_incident(behind_wall).resolution.get("outcome", "")) == "interrupted",
		"on the next tick: a witnessed act ends, an unwitnessed one is cancelled, a response with no open call is interrupted")
	var tampered: Array = []
	var bad_id: Dictionary = staged.duplicate(true)
	bad_id.incidents[0].id = "inc_999999"
	tampered.append(bad_id)
	var twin: Dictionary = staged.duplicate(true)
	twin.incidents[1].id = twin.incidents[0].id
	tampered.append(twin)
	var unknown: Dictionary = staged.duplicate(true)
	unknown.incidents[0].template = "arson"
	tampered.append(unknown)
	var nan_point: Dictionary = staged.duplicate(true)
	nan_point.incidents[0].at = [0.0, "x", 1.0]
	tampered.append(nan_point)
	var future: Dictionary = staged.duplicate(true)
	future.version = 2
	tampered.append(future)
	var bad_role: Dictionary = staged.duplicate(true)
	bad_role.incidents[0].participants[0].role = "mastermind"
	tampered.append(bad_role)
	var all_rejected := true
	for value in tampered:
		all_rejected = all_rejected and not copy.validate_state(value).is_empty() and not bool(copy.restore_state(value).ok)
	check(all_rejected and str(copy.get_incident(first).resolution.outcome) == "warned", "tampered checkpoints are rejected without changing anything")
	copy.queue_free()
	reloaded.queue_free()

	# ---- 9. Observation stays inside its ray budget.
	var crowded := person("walker_h", "granny", Vector3(6, 0.012, 14), -PI * 0.5)
	var lookers: Array = []
	for i in 12:
		lookers.append(person("looker_%d" % i, "liner_2", Vector3(-11 + i * 2.0, 0.012, 20), PI))
	spawned = incidents.spawn_template_now("jaywalking", {"offender": "walker_h", "route": [Vector3(-6, 0.012, 14)]})
	var busy := str(spawned.incident_id)
	await step(0.2)
	var rays_before := int(incidents.rays)
	incidents._observe_pass()
	check(int(incidents.rays) - rays_before <= Incidents.MAX_RAYS_PER_PASS, "one observation pass casts at most %d rays (%d)" % [Incidents.MAX_RAYS_PER_PASS, int(incidents.rays) - rays_before])
	await advance_until(func(): return str(record(busy).state) != "active", 20.0)
	check((record(busy).witnesses as Array).size() <= Incidents.MAX_WITNESSES and (record(busy).witnesses as Array).size() >= 6,
		"over the act many neighbors are checked, capped at %d witnesses" % Incidents.MAX_WITNESSES)
	await calm()
	crowded.set_enabled(false)
	for body in lookers:
		body.set_enabled(false)

	# ---- 10. IDs are never consumed by failed spawns; case hooks are authoritative.
	var sequence: int = incidents.next_sequence
	var count: int = incidents.records.size()
	check(str(incidents._try_spawn().reason) == "no_free_neighbors" and str(incidents.spawn_template_now("jaywalking", {"offender": "nobody"}).reason) == "offender_unavailable"
		and str(incidents.spawn_template_now("red_light", {}).reason) == "unknown_template", "spawns without a free real neighbor are refused")
	check(incidents.next_sequence == sequence and incidents.records.size() == count, "refused spawns consume no ID and create no record")
	var opened: Dictionary = incidents.open_incident({"template": "case", "at": Vector3(1, 0.012, 1), "offender_id": "walker_a",
		"source": "case:lost_satchel", "case_id": "lost_satchel"})
	var case_id := str(opened.incident_id)
	check(bool(opened.ok) and case_id == "inc_%06d" % sequence and str(record(case_id).state) == "ended", "a case incident takes the next ID")
	check(str(incidents.report_incident(case_id, "player").reason) == "not_witnessed", "a case incident still needs a witness")
	var photo: Dictionary = incidents.evaluate_photo(case_id, {"by": "player", "position": Vector3(1, 0, -5), "minutes": float(record(case_id).created_minutes),
		"visible": [{"id": "walker_a", "los": false, "distance": 6.0}]})
	check(not bool(photo.ok) and str(photo.reason) == "subject_not_visible", "a photo without line of sight to the subject is not evidence")
	var phone_context := {"version": 2, "source": "phone_camera", "trusted": false, "photo_id": "photo_case",
		"time": {"total_minutes": float(record(case_id).created_minutes)}, "camera": {"position": Vector3(1, 1.6, -5), "forward": Vector3(0, 0, 1)},
		"subjects": [{"id": "walker_a", "distance": 6.0, "line_of_sight": true, "position": Vector3(1, 1.2, 1)}]}
	check(str(incidents.evaluate_photo(case_id, phone_context).reason) == "untrusted_context", "an untrusted capture context is refused")
	phone_context.trusted = true
	photo = incidents.evaluate_photo(case_id, phone_context)
	check(bool(photo.ok) and incidents.reportable_for("player").any(func(item): return str(item.id) == case_id)
		and (record(case_id).evidence as Array).any(func(item): return str(item.ref) == "photo_case" and bool(item.verified)),
		"the phone's v2 capture of the subject is evidence and makes the photographer a witness")
	var heard: Dictionary = incidents.open_incident({"template": "case", "at": Vector3(2, 0.012, 2), "offender_id": "walker_a",
		"source": "case:lost_satchel", "case_id": "lost_satchel"})
	var heard_id := str(heard.incident_id)
	check(incidents.note_observation(heard_id, "neighbor_w", {"via": "case"}) and not incidents.note_observation(heard_id, "walker_a"),
		"a trusted observation adds a witness; the offender cannot be one")
	check(not incidents.attach_evidence(heard_id, {"kind": "rumor", "by": "player"}) and str(incidents.report_incident(heard_id, "player").reason) == "not_witnessed",
		"unknown evidence kinds are refused and hearsay alone is not a report")
	check(incidents.attach_evidence(heard_id, {"kind": "statement", "by": "player", "subject_id": "neighbor_w", "verified": true, "ref": "interview"})
		and witness_ids(heard_id).has("player"), "verified testimony from a recorded witness gives the listener report context")
	var via_case: Dictionary = incidents.file_report(heard_id, {"reporter": "player", "case_id": "lost_satchel"})
	check(bool(via_case.ok) and str(record(heard_id).report.channel) == "case", "the cases-contract file_report alias files through the same gate")
	assistance.reset_state()
	check(str(record(heard_id).state) == "resolved", "calling the response off closes the case report honestly")
	check(incidents.resolve_incident(case_id, "case_resolved") and not incidents.resolve_incident(case_id, "case_resolved")
		and str(record(case_id).state) == "resolved", "case closure is once-only")
	var ids: Dictionary = {}
	for item in incidents.list_incidents():
		ids[str(item.id)] = true
	check(ids.size() == incidents.records.size(), "every incident ID is unique")

	print("[incidents] rays=%d records=%d counters=%s" % [int(incidents.rays), incidents.records.size(), str(incidents.get_status().counters)])
	law.free()
	arena.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)
