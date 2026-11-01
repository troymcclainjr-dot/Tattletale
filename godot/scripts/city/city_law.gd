extends Node
signal offense_observed(kind: String, at: Vector3, victim_id: String)
## Witness-driven law response for the Pen Lucy sandbox.
## Combat emits each player offense once (player_offense). People only report
## what they actually saw (facing, line of sight) or heard (gunfire), after a
## short call delay; police who see it act at once. Real foot patrols respond
## along surveyed streets. Combat owns an officer only while that officer is
## fighting (engage_actor/disengage_actor); law owns reporting, dispatch, the
## last-known-position search, cooldown and the staged hospital/precinct
## recovery. Police learn where the player is only from an officer's own line
## of sight; a report carries where the offender was, never a live position.
## Perception runs at a fixed low rate with bounded queries and rays; nothing
## scans the whole crowd. Law heat is its own score: it never reads or writes
## reputation, and no response depends on anyone's appearance. A police role
## (uniformed cast or patrol identity) is the only identity distinction used.
## Up to two real police cars join the response (city_police_cruisers.gd,
## composed here: set up, ticked and reset with law). A seated player is seen
## only by a ray ending at their seat; their own car is excluded from that ray
## alone, so buildings and other cars still hide them.
const Routes := preload("res://scripts/city/city_law_routes.gd")
const Facilities := preload("res://scripts/city/city_law_facilities.gd")
const Cruisers := preload("res://scripts/city/city_police_cruisers.gd")
const C := preload("res://scripts/city/city_theme.gd")
const T := C.T

const MAX_WANTED := 3
const MAX_HEAT := 100.0
## Heat at which each wanted tier begins (index = tier). An identified offense is always tier 1+.
const TIER_HEAT := [0.0, 1.0, 35.0, 70.0]
## Root sends vehicle_assault (a person struck by the player's car) and
## vehicle_collision (another car struck) only for consequential contacts.
const SEVERITY := {"assault": 12.0, "shooting": 24.0, "stomp": 50.0, "vehicle_assault": 28.0, "vehicle_collision": 8.0}
## Ramming a police car is worse than denting a neighbor's.
const POLICE_RAM_SEVERITY := 20.0
## Bystanders phone in a car crash only as part of a rampage: this many
## consequential collisions within RAMPAGE_SECONDS.
const COLLISION_REPORT_COUNT := 3
const RAMPAGE_SECONDS := 10.0
## Driver's seat, car-local (+X is the driver's side): the end of every ray to a seated player.
const OCCUPANT_LOCAL := Vector3(0.38, 1.05, 0.15)
const DEFAULT_SEVERITY := 12.0
const LETHAL_SEVERITY := 50.0
const MERGED_EXTRA := 2.0
const MAX_MERGED_EXTRA := 12.0
const RESPONDERS_BY_TIER := [1, 1, 2, 3]
const MAX_RESPONDERS := 3
const PERCEPTION_INTERVAL := 0.25
const VISUAL_RADIUS := 24.0
const HEARING_RADIUS := 45.0
## Facing thresholds (dot of forward with the direction to the player).
const VIEW_DOT := -0.2
const PATROL_VIEW_DOT := 0.1
const ALERT_VIEW_DOT := -0.5
## Someone this close notices regardless of facing.
const NOTICE_RADIUS := 1.6
## Sphere-query cap for bystanders; police and victims are added on top (bounded lists).
const MAX_WITNESS_RESULTS := 40
const MAX_WITNESS_CHECKS := 10
const MAX_SCANS_PER_TICK := 1
const MAX_PENDING_EVENTS := 6
const MAX_PENDING_REPORTS := 6
const MAX_REPORTERS := 3
const MERGE_RADIUS := 8.0
const MERGE_SECONDS := 1.5
const EYE_HEIGHT := 1.3
const CHEST_HEIGHT := 1.1
const SIGHT_MASK := 1 | 2 | 16
const PERSON_LAYER := 8
const SIGHT_RANGE := 30.0
const ALERT_RANGE := 37.0
## Combat's unarmed fight drops a target beyond 18 m; engage well inside that.
const MELEE_ENGAGE_RANGE := 14.0
const MAX_RECOGNITION_CHECKS := 2
const DISPATCH_RADIUS := 260.0
const DISPATCH_ROUTE_LIMIT := 380.0
const MAX_ROUTES_PER_TICK := 3
const JOG_SPEED := 3.1
const SEARCH_SPEED := 2.2
const ARRIVE_RADIUS := 1.1
const SEARCH_RADIUS := 8.0
const MAX_TRAIL := 256
const TRAIL_SPACING := 1.5
const STUCK_SECONDS := 2.5
const MAX_UNSTICK := 3
const SURRENDER_RANGE := 22.0
const SURRENDER_KEY := KEY_G
const HOSPITAL_FEE := 150
const ARREST_FINES := [0, 100, 200, 300]
const PATROL_PREFIX := "patrol_officer_"
const MAX_EXIT_TICKS := 120

## Tunables. Fixtures shorten them; production keeps these defaults.
var report_delay_min := 4.0
var report_delay_max := 8.0
var lost_sight_seconds := 3.0
## Search time per wanted tier; index 0 is a shots-fired investigation.
var search_seconds := [16.0, 20.0, 28.0, 36.0]
var cooldown_seconds := [0.0, 12.0, 20.0, 30.0]
var return_speed := 1.6
var stage_seconds := {"down": 2.4, "hands_up": 1.8, "fade_out": 1.0, "fade_in": 1.4}
var use_level_notices := true

var level: Node
var routes: Routes
## Police cruiser manager (law.cruisers); its status is get_status().cruisers.
var cruisers: Cruisers
var wanted := 0
var heat := 0.0
## clear, reported, investigating, responding, pursuit, search, cooldown, arrest, hospital.
var phase := "clear"
var message := ""
var recovering := false
var seen := false
var last_known_position := Vector3.INF
var last_seen_heading := Vector3.ZERO
## Whether the suspect was in a car at the last sighting or report.
var last_seen_seated := false
var incident_armed := false
var incident_lethal := false
var offenses_received := 0
var offenses_ignored := 0
var offenses_merged := 0
var unobserved_offenses := 0
var witness_scans := 0
var witness_rays := 0
var recognition_rays := 0
var reports_scheduled := 0
var reports_filed := 0
var reports_dropped := 0
var report_sources := {"police": 0, "victim": 0, "civilian": 0, "heard": 0}
var dispatches := 0
var engagements := 0
var routes_planned := 0
var sightings := 0
var searches_started := 0
var escapes := 0
var arrests := 0
var hospital_visits := 0
var recovery_requests := 0
var recoveries_completed := 0
var vehicle_exits := 0
var fees_charged := 0
var last_fee := 0
var last_offense: Dictionary = {}
var last_scan: Dictionary = {}
var last_release: Dictionary = {}
var last_recovery: Dictionary = {}
var last_notice := ""
var _clock := 0.0
var _since_perception := 0.0
var _collision_times: Array[float] = []
var _events: Array[Dictionary] = []
var _reports: Array[Dictionary] = []
var _responders: Dictionary = {}
var _was_seen := false
var _lkp_clock := -INF
var _cooldown_left := 0.0
var _recognition_cursor := -1
var _surrender_officer: Node3D
var _surrender_clock := -INF
var _recovery: Dictionary = {}
var _recovery_sequence := 0
var _transient := ""
var _transient_until := -INF
var _overlay: CanvasLayer
var _shade: ColorRect
var _cue: Label
var _shade_alpha := 0.0
var _ray := PhysicsRayQueryParameters3D.new()
var _ground_ray := PhysicsRayQueryParameters3D.new()
var _witness_shape := SphereShape3D.new()
var _witness_query := PhysicsShapeQueryParameters3D.new()
var _sweep_query: PhysicsShapeQueryParameters3D
var _probe_query: PhysicsShapeQueryParameters3D

func setup(owner_level: Node) -> void:
	level = owner_level
	name = "LawResponse"
	_ray.collision_mask = SIGHT_MASK
	_ray.hit_from_inside = false
	_ground_ray.collision_mask = 1
	_witness_query.shape = _witness_shape
	_witness_query.collision_mask = PERSON_LAYER
	routes = Routes.new()
	var data = level.get("level_data")
	routes.setup(data.get("roads", []) if data is Dictionary else [], _link_clear)
	if cruisers == null:
		# Crew identities register here, before any checkpoint restore validates deaths.
		cruisers = Cruisers.new()
		cruisers.setup(self, level)
	if _overlay == null:
		_build_overlay()
	_refresh_message()

# --------------------------------------------------------------- public API

## One event per landed punch, stomp or discharged round (combat contract).
## Only recorded here; the bounded witness scan runs on the next perception tick.
func on_offense(kind: String, at: Vector3, victim_id: String) -> void:
	offenses_received += 1
	var player := _player()
	if level == null or player == null or recovering:
		offenses_ignored += 1
		return
	if not at.is_finite():
		at = player.global_position
	var offender := _player_feet()
	var severity := _offense_severity(kind, victim_id)
	var vehicle := _vehicle_body()
	var sight_at := _player_sight_point()
	var rampage := false
	if kind == "vehicle_collision":
		while not _collision_times.is_empty() and (_clock - _collision_times[0] > RAMPAGE_SECONDS or _collision_times.size() >= 16):
			_collision_times.pop_front()
		_collision_times.append(_clock)
		rampage = _collision_times.size() >= COLLISION_REPORT_COUNT
	last_offense = {"kind": kind, "at": at, "victim": victim_id, "time": _clock}
	var target: Dictionary = {}
	for event in _events:
		if str(event.kind) == kind and _flat(Vector3(event.at), at) <= MERGE_RADIUS and _clock - float(event.last) <= MERGE_SECONDS:
			target = event
			break
	if target.is_empty() and _events.size() >= MAX_PENDING_EVENTS:
		target = _events[-1]
	if not target.is_empty():
		# An automatic burst or flurry is one incident: bounded queue, one scan.
		offenses_merged += 1
		target.count = int(target.count) + 1
		target.extra = minf(MAX_MERGED_EXTRA, float(target.extra) + MERGED_EXTRA)
		target.severity = maxf(float(target.severity), severity)
		if kind == "shooting":
			target.kind = "shooting"
		target.last = _clock
		target.player_at = offender
		target.sight_at = sight_at
		target.vehicle = vehicle
		target.seated = vehicle != null
		target.rampage = bool(target.get("rampage", false)) or rampage
		var merged_victims: Array = target.victims
		if not victim_id.is_empty() and merged_victims.size() < 4 and not merged_victims.has(victim_id):
			merged_victims.append(victim_id)
		return
	var victims: Array = []
	if not victim_id.is_empty():
		victims.append(victim_id)
	_events.append({"kind": kind, "at": at, "player_at": offender, "victims": victims, "severity": severity,
		"extra": 0.0, "count": 1, "time": _clock, "last": _clock, "sight_at": sight_at, "vehicle": vehicle,
		"seated": vehicle != null, "rampage": rampage})

## Combat emits this once at zero health. Recovery is staged in tick(), never here.
func on_player_defeated() -> void:
	recovery_requests += 1
	if level == null:
		return
	if recovering:
		if str(_recovery.kind) == "arrest":
			if not bool(_recovery.relocated):
				# Hurt before custody completed: the hospital takes over this transition.
				_recovery.kind = "hospital"
				_recovery.stage = "down"
				_recovery.time = 0.0
				phase = "hospital"
			else:
				_recovery.defeat_after = true
		return
	_begin_recovery("hospital", null)

## Root forwards world input here before driving/shops/combat (G surrenders).
func handle_input(event: InputEvent) -> bool:
	if recovering:
		# Hold combat, driving, shops and interaction still during the staged
		# transition. Mouse motion passes; Esc/M/F6 are handled by root first.
		return event is InputEventKey or event is InputEventMouseButton
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == SURRENDER_KEY:
		if wanted <= 0:
			return false
		request_surrender()
		return true
	return false

func request_surrender() -> bool:
	if level == null or recovering or wanted <= 0 or _world_paused():
		return false
	var combat = _combat()
	var downed = combat.get("downed") if combat != null else null
	if downed != null and float(downed) > 0.0:
		return false
	var officer = _surrender_target()
	if officer == null:
		_show_transient("No officer close enough to surrender to", 2.5)
		_notify("No officer close enough to surrender to.")
		return false
	_begin_recovery("arrest", officer)
	return true

func tick(delta: float) -> void:
	if level == null or delta <= 0.0 or _world_paused():
		return
	delta = minf(delta, 0.1)
	_clock += delta
	if cruisers != null:
		# Cars step every tick (smooth swept motion); their perception runs below.
		cruisers.tick(delta)
	if recovering:
		_tick_recovery(delta)
	else:
		_since_perception += delta
		if _since_perception >= PERCEPTION_INTERVAL:
			var elapsed := _since_perception
			_since_perception = 0.0
			_perceive(elapsed)
	_update_overlay()
	_refresh_message()

## Ends any incident and returns every responder to its beat now (fixtures, debug).
## Cruiser crews are re-seated and every police car claim is released.
func reset_state() -> void:
	if cruisers != null:
		cruisers.reset()
	for state in _responders.values().duplicate():
		var actor = state.actor
		if is_instance_valid(actor) and not (_combat_mode(actor) in ["", "dead", "gone", "downed", "unknown"]):
			_disengage(actor)
		_release(state)
	_responders.clear()
	_events.clear()
	_reports.clear()
	_collision_times.clear()
	if recovering:
		var player := _player()
		if player != null:
			player.set("enabled", true)
	recovering = false
	_recovery = {}
	_end_incident()
	phase = "clear"
	_shade_alpha = 0.0
	_transient_until = -INF
	_update_overlay()
	_refresh_message()

func get_status() -> Dictionary:
	var responders: Array[Dictionary] = []
	for state in _responders.values():
		responders.append({"id": state.id, "mode": state.mode, "purpose": state.purpose, "goal": state.goal,
			"crew": bool(state.get("crew", false))})
	var recovery: Dictionary = {}
	if recovering:
		recovery = {"kind": _recovery.kind, "stage": _recovery.stage, "time": _recovery.time,
			"sequence": _recovery.sequence, "relocated": _recovery.relocated}
	var claimed: int = cruisers.claimed_count() if cruisers != null else 0
	return {"wanted": wanted, "max_wanted": MAX_WANTED, "heat": heat, "phase": phase, "message": message,
		"recovering": recovering, "recovery": recovery, "last_recovery": last_recovery.duplicate(),
		"seen": seen, "last_known_position": last_known_position, "last_seen_seated": last_seen_seated,
		"cooldown": maxf(0.0, _cooldown_left),
		"responders": responders, "responder_count": _active_count(), "max_responders": MAX_RESPONDERS,
		"cruisers": cruisers.get_status() if cruisers != null else {},
		"pending_events": _events.size(), "pending_reports": _reports.size(),
		"busy": wanted > 0 or recovering or not _reports.is_empty() or not _events.is_empty() or claimed > 0,
		"surrender_available": _surrender_ready(), "prompt": "G · Surrender" if _surrender_ready() else "",
		"cue_alpha": _shade_alpha, "cue_visible": _overlay != null and _overlay.visible,
		"offenses": offenses_received, "ignored": offenses_ignored, "merged": offenses_merged,
		"unobserved": unobserved_offenses, "witness_scans": witness_scans, "witness_rays": witness_rays,
		"recognition_rays": recognition_rays, "reports_scheduled": reports_scheduled, "reports_filed": reports_filed,
		"reports_dropped": reports_dropped, "report_sources": report_sources.duplicate(), "dispatches": dispatches,
		"engagements": engagements, "routes": routes_planned, "sightings": sightings, "searches": searches_started,
		"escapes": escapes, "arrests": arrests, "hospital_visits": hospital_visits,
		"recovery_requests": recovery_requests, "recoveries": recoveries_completed, "vehicle_exits": vehicle_exits,
		"fees_charged": fees_charged, "last_fee": last_fee, "last_offense": last_offense.duplicate(),
		"last_scan": last_scan.duplicate(true), "last_release": last_release.duplicate()}

# --------------------------------------------------------------- perception

func _perceive(elapsed: float) -> void:
	if _player() == null:
		return
	var scans := 0
	while not _events.is_empty() and scans < MAX_SCANS_PER_TICK:
		_scan(_events.pop_front())
		scans += 1
	_file_due_reports()
	_was_seen = seen
	seen = false
	var routes_left := MAX_ROUTES_PER_TICK
	for id in _responders.keys():
		if _responders.has(id):
			routes_left = _tick_responder(_responders[id], elapsed, routes_left)
	if cruisers != null:
		cruisers.perceive(elapsed)
	if wanted > 0 and not seen:
		_recognition_sweep()
	_update_phase(elapsed)

## One bounded scan per offense event: a sphere query on the people layer near
## the incident, then at most MAX_WITNESS_CHECKS facing-filtered sight rays.
func _scan(event: Dictionary) -> void:
	witness_scans += 1
	var kind := str(event.kind)
	var audible := kind == "shooting"
	var offender: Vector3 = event.player_at
	# Where the offender was seen from: their seat if driving, else their chest.
	var target: Vector3 = event.get("sight_at", offender + Vector3.UP * CHEST_HEIGHT)
	if not target.is_finite():
		target = offender + Vector3.UP * CHEST_HEIGHT
	var lethal := kind == "stomp"
	for victim in event.victims:
		lethal = lethal or _is_dead_id(str(victim))
	var candidates := _witness_candidates(Vector3(event.at).lerp(offender, 0.5), HEARING_RADIUS if audible else VISUAL_RADIUS, event.victims)
	var space := _space()
	var vehicle = event.get("vehicle")
	if not is_instance_valid(vehicle):
		vehicle = null
	var checked := 0
	var rays := 0
	var police_saw: Array[Dictionary] = []
	var civilians_saw: Array[Dictionary] = []
	var police_heard: Array[Dictionary] = []
	var civilians_heard: Array[Dictionary] = []
	for candidate in candidates:
		var eye: Vector3 = Vector3(candidate.position) + Vector3.UP * EYE_HEIGHT
		var toward := Vector3(target.x - eye.x, 0.0, target.z - eye.z)
		var saw := false
		if checked < MAX_WITNESS_CHECKS:
			# Gunfire turns heads and a victim knows who hit them; others must be facing it.
			var facing := audible or bool(candidate.victim) or toward.length() <= NOTICE_RADIUS
			if not facing:
				var forward := Vector3(sin(float(candidate.yaw)), 0.0, cos(float(candidate.yaw)))
				facing = forward.dot(toward.normalized()) >= VIEW_DOT
			if facing:
				checked += 1
				rays += 1
				saw = _ray_clear(space, eye, target, _sight_skip(candidate.rid, vehicle))
		if saw:
			if bool(candidate.police):
				police_saw.append(candidate)
			else:
				civilians_saw.append(candidate)
		elif audible:
			if bool(candidate.police):
				police_heard.append(candidate)
			else:
				civilians_heard.append(candidate)
	witness_rays += rays
	var severity := maxf(float(event.severity), LETHAL_SEVERITY if lethal else 0.0) + float(event.extra)
	var outcome := "unobserved"
	if not police_saw.is_empty():
		# Police detection: no phone call. Witnessing officers join before dispatch.
		outcome = "police"
		for entry in police_saw:
			if entry.has("vehicle"):
				if cruisers != null:
					cruisers.on_witness(entry.vehicle, offender)
			else:
				_enlist_witness(entry.node)
		_file({"kind": kind, "at": event.at, "player_at": offender, "identified": true, "severity": severity,
			"lethal": lethal, "time": float(event.last), "source": "police", "seated": bool(event.get("seated", false))})
	elif not civilians_saw.is_empty():
		if kind == "vehicle_collision" and not bool(event.get("rampage", false)):
			# A single crash is seen but not phoned in; a rampage is.
			outcome = "civilian_ignored"
		else:
			outcome = "victim" if bool(civilians_saw[0].victim) else "civilian"
			_schedule_report(event, true, civilians_saw, severity, lethal, outcome)
	if audible:
		for entry in police_heard:
			_enlist_investigator(entry.node, Vector3(event.at))
		if police_saw.is_empty() and civilians_saw.is_empty():
			if not civilians_heard.is_empty():
				outcome = "heard"
				_schedule_report(event, false, civilians_heard, 0.0, lethal, "heard")
			elif not police_heard.is_empty():
				outcome = "police_heard"
	if outcome == "unobserved":
		unobserved_offenses += 1
	var observed: Array[String] = []
	for entry in police_saw + civilians_saw:
		observed.append(str(entry.id))
	var heard: Array[String] = []
	for entry in police_heard + civilians_heard:
		heard.append(str(entry.id))
	last_scan = {"kind": kind, "outcome": outcome, "candidates": candidates.size(), "checked": checked, "rays": rays,
		"observed": observed, "heard": heard, "lethal": lethal, "count": int(event.count), "severity": severity}
	if not observed.is_empty():
		offense_observed.emit(kind, Vector3(event.at), str(event.victims[0]) if not event.victims.is_empty() else "")

func _witness_candidates(center: Vector3, radius: float, victims: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var space := _space()
	if space == null:
		return result
	# Police and the victims always count, even in a crowd denser than the query
	# cap; everyone else comes from one sphere query on the people layer.
	var bodies: Array = _police()
	for victim in victims:
		var body = _victim_body(str(victim))
		if body != null:
			bodies.append(body)
	_witness_shape.radius = radius
	_witness_query.transform = Transform3D(Basis.IDENTITY, center + Vector3.UP)
	var exclude: Array[RID] = []
	var player := _player()
	if player != null:
		exclude.append(player.get_rid())
	_witness_query.exclude = exclude
	for hit in space.intersect_shape(_witness_query, MAX_WITNESS_RESULTS):
		bodies.append(hit.get("collider"))
	var known: Dictionary = {}
	for body in bodies:
		var entry := _person_entry(body)
		if entry.is_empty() or known.has(entry.id) or _is_dead_id(str(entry.id)):
			continue
		var at: Vector3 = entry.position
		entry.distance = Vector2(at.x - center.x, at.z - center.z).length()
		if float(entry.distance) > radius:
			continue
		known[entry.id] = true
		entry.victim = victims.has(entry.id)
		result.append(entry)
	if cruisers != null:
		# Crewed police cars watch through their windows (bounded: two to four cars).
		for entry in cruisers.witness_entries(center, radius, victims, EYE_HEIGHT):
			if not known.has(entry.id):
				known[entry.id] = true
				result.append(entry)
	result.sort_custom(_witness_order)
	return result

## The victim's own body (actor or primitive crowd slot), if it still stands.
func _victim_body(id: String):
	if id.is_empty():
		return null
	if id.begins_with("crowd_") and id.substr(6).is_valid_int():
		var crowd = _crowd()
		var records = crowd.get("residents") if crowd != null else null
		var index := int(id.substr(6))
		if records is Array and index >= 0 and index < records.size():
			var body = records[index].get("body")
			if is_instance_valid(body):
				return body
		return null # A promoted crowd victim is a combat actor; the query finds it.
	var npcs = level.get("npcs") if level != null else null
	if npcs != null and npcs.has_method("get_actor"):
		var actor = npcs.get_actor(id)
		if is_instance_valid(actor):
			return actor
	return null

## Police first (they act immediately), then the victim, then the nearest.
func _witness_order(a: Dictionary, b: Dictionary) -> bool:
	if bool(a.police) != bool(b.police):
		return bool(a.police)
	if bool(a.victim) != bool(b.victim):
		return bool(a.victim)
	return float(a.distance) < float(b.distance)

func _person_entry(body) -> Dictionary:
	if not is_instance_valid(body):
		return {}
	if body.has_meta("city_crowd_index"):
		var crowd = _crowd()
		var records = crowd.get("residents") if crowd != null else null
		var index := int(body.get_meta("city_crowd_index"))
		if not records is Array or index < 0 or index >= records.size():
			return {}
		var record: Dictionary = records[index]
		# A promoted resident is represented by its combat actor instead.
		if bool(record.get("dead", false)) or bool(record.get("combat_controlled", false)):
			return {}
		return {"id": "crowd_%d" % index, "node": null, "rid": body.get_rid(), "position": record.get("position", body.global_position),
			"yaw": float(record.get("yaw", 0.0)), "police": false}
	if body is CharacterBody3D and body.get("actor_id") != null:
		if body.get("dead") == true or body.get("enabled") != true:
			return {}
		return {"id": str(body.actor_id), "node": body, "rid": body.get_rid(), "position": body.global_position,
			"yaw": float(body.yaw), "police": _is_police(body)}
	return {}

func _schedule_report(event: Dictionary, identified: bool, witnesses: Array, severity: float, lethal: bool, source: String) -> void:
	# Calling takes a moment; farther witnesses take a little longer. Geometry
	# only: no identity-based variation.
	var nearest := float(witnesses[0].distance)
	var delay := clampf(report_delay_min + nearest * 0.08, report_delay_min, maxf(report_delay_min, report_delay_max))
	var reporters: Array = []
	for entry in witnesses:
		if reporters.size() >= MAX_REPORTERS:
			break
		reporters.append({"id": str(entry.id), "node": entry.node})
	if _reports.size() >= MAX_PENDING_REPORTS:
		var newest: Dictionary = _reports[-1]
		if identified and not bool(newest.identified):
			newest.source = source
		newest.identified = bool(newest.identified) or identified
		newest.severity = minf(maxf(float(newest.severity), severity) + MERGED_EXTRA, MAX_HEAT)
		newest.lethal = bool(newest.lethal) or lethal
		newest.player_at = event.player_at
		newest.seated = bool(event.get("seated", false))
		newest.time = float(event.last)
		offenses_merged += 1
		return
	_reports.append({"kind": str(event.kind), "at": event.at, "player_at": event.player_at, "identified": identified,
		"severity": severity, "lethal": lethal, "time": float(event.last), "due": _clock + delay,
		"reporters": reporters, "source": source, "seated": bool(event.get("seated", false))})
	reports_scheduled += 1

func _file_due_reports() -> void:
	for report in _reports.duplicate():
		if float(report.due) > _clock:
			continue
		_reports.erase(report)
		if _reporter_able(report):
			_file(report)
		else:
			reports_dropped += 1

## A silenced witness never calls; any surviving co-witness still can.
func _reporter_able(report: Dictionary) -> bool:
	for reporter in report.reporters:
		var node = reporter.get("node")
		if typeof(node) == TYPE_OBJECT and (not is_instance_valid(node) or node.get("dead") == true):
			continue
		if _is_dead_id(str(reporter.id)):
			continue
		return true
	return false

func _file(report: Dictionary) -> void:
	reports_filed += 1
	var source := str(report.get("source", "civilian"))
	report_sources[source] = int(report_sources.get(source, 0)) + 1
	if not bool(report.identified):
		# Shots fired, nobody seen: one officer checks the sound location.
		_dispatch(Vector3(report.at), 1, "investigate")
		return
	var where: Vector3 = report.player_at
	var before := wanted
	heat = clampf(heat + float(report.severity), 0.0, MAX_HEAT)
	incident_armed = incident_armed or str(report.kind) == "shooting"
	incident_lethal = incident_lethal or bool(report.lethal)
	wanted = clampi(maxi(wanted, _tier_for(heat)), 1, MAX_WANTED)
	if float(report.time) > _lkp_clock:
		last_known_position = where
		last_seen_seated = bool(report.get("seated", false))
		_lkp_clock = float(report.time)
	_cooldown_left = float(cooldown_seconds[wanted])
	if wanted > before:
		_notify("Wanted %d/%d · %s" % [wanted, MAX_WANTED, "police saw you" if source == "police" else "a witness called the police"])
	_dispatch(where, int(RESPONDERS_BY_TIER[wanted]), "wanted")
	if cruisers != null:
		# The report's position, never a live fix; cruisers by tier follow in perception.
		cruisers.request(where, wanted, source)

func _tier_for(value: float) -> int:
	var tier := 0
	for index in range(1, TIER_HEAT.size()):
		if value >= float(TIER_HEAT[index]):
			tier = index
	return mini(tier, MAX_WANTED)

## Officers on their beats recognise a wanted player only by their own sight.
func _recognition_sweep() -> void:
	var officers := _police()
	var count := officers.size()
	if count == 0:
		return
	var feet := _player_feet()
	var rays := 0
	for attempt in count:
		if rays >= MAX_RECOGNITION_CHECKS:
			break
		_recognition_cursor = (_recognition_cursor + 1) % count
		var actor = officers[_recognition_cursor]
		var id := str(actor.actor_id)
		if _responders.has(id) and str(_responders[id].mode) != "return":
			continue
		if _combat_mode(actor) in ["downed", "dead", "gone", "unknown"]:
			continue
		if _flat(actor.global_position, feet) > SIGHT_RANGE or not _in_view(actor, false):
			continue
		rays += 1
		if not _ray_sees(actor):
			continue
		_spotted(actor, {})
		if _is_patrol(actor):
			var state := _enlist(actor, "wanted")
			if not state.is_empty():
				state.seen_clock = _clock
				state.search_info = _clock
				if str(state.mode) != "engaged":
					state.mode = "pursue"
					state.path = []
					state.index = 0
				actor.speak("That's them!", 1.6)
		return

func _update_phase(elapsed: float) -> void:
	var active := 0
	var en_route := 0
	var investigating := 0
	for state in _responders.values():
		if str(state.mode) == "return":
			continue
		if str(state.purpose) == "investigate":
			investigating += 1
			continue
		active += 1
		en_route += int(str(state.mode) == "respond")
	if cruisers != null:
		# Cruisers still driving or searching count; a parked one's crew is counted above.
		var units: Dictionary = cruisers.summary()
		active += int(units.active)
		en_route += int(units.en_route)
	if wanted > 0:
		if seen:
			phase = "pursuit"
			_cooldown_left = float(cooldown_seconds[wanted])
		elif active > 0:
			phase = "responding" if en_route == active else "search"
			_cooldown_left = float(cooldown_seconds[wanted])
		else:
			# Nobody is looking any more: lie low until the heat is off.
			phase = "cooldown"
			_cooldown_left -= elapsed
			if _cooldown_left <= 0.0:
				_resolve_escape()
	elif investigating > 0:
		phase = "investigating"
	elif not _reports.is_empty():
		phase = "reported"
	else:
		phase = "clear"

func _resolve_escape() -> void:
	escapes += 1
	_end_incident()
	phase = "clear"
	_show_transient("Lost the police", 5.0)
	_notify("You lost the police. Wanted level cleared.")

func _end_incident() -> void:
	wanted = 0
	heat = 0.0
	seen = false
	_was_seen = false
	incident_armed = false
	incident_lethal = false
	last_known_position = Vector3.INF
	last_seen_heading = Vector3.ZERO
	last_seen_seated = false
	_lkp_clock = -INF
	_cooldown_left = 0.0
	_surrender_officer = null
	if cruisers != null:
		# Behind a recovery fade every crew is re-seated and every car released now;
		# after an escape crews walk back and drive off before release.
		cruisers.stand_down(recovering)
	for state in _responders.values().duplicate():
		var actor = state.actor
		if not _usable(actor):
			_forget(state)
			continue
		if str(state.mode) == "return" or str(state.purpose) == "investigate":
			continue
		if _combat_mode(actor) in ["aggro", "gun", "return"]:
			_disengage(actor)
		_begin_return(state, 1)

func _has_identified_pending() -> bool:
	for report in _reports:
		if bool(report.identified):
			return true
	return false

# --------------------------------------------------------------- responders

func _dispatch(goal: Vector3, count: int, purpose: String) -> void:
	if not goal.is_finite() or routes == null:
		return
	if purpose == "wanted":
		for state in _responders.values():
			if str(state.purpose) == "investigate":
				state.purpose = "wanted"
	var needed := count - _active_count()
	if needed <= 0:
		return
	var candidates: Array[Dictionary] = []
	for actor in _police():
		# Cruiser crews deploy only from their own car, never by foot dispatch.
		if not _is_patrol(actor) or _is_crew(actor):
			continue
		var id := str(actor.actor_id)
		if _responders.has(id) and str(_responders[id].mode) != "return":
			continue
		if _combat_mode(actor) in ["dead", "gone", "downed", "unknown", "aggro", "gun"]:
			continue
		var distance := _flat(actor.global_position, goal)
		if distance <= DISPATCH_RADIUS:
			candidates.append({"actor": actor, "distance": distance})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
	var planned := 0
	for candidate in candidates:
		if needed <= 0 or planned >= MAX_ROUTES_PER_TICK:
			break
		planned += 1
		var actor = candidate.actor
		routes_planned += 1
		if _assign(actor, purpose, goal, routes.route(actor.global_position, goal, DISPATCH_ROUTE_LIMIT)):
			actor.speak("Dispatch, I'm responding." if purpose == "wanted" else "Shots fired? I'll check it out.", 2.0)
			needed -= 1

## An officer who only heard gunfire checks the sound location now.
func _enlist_investigator(actor, at: Vector3) -> void:
	if not _usable(actor) or not _is_patrol(actor) or _is_crew(actor) or routes == null:
		return
	var id := str(actor.actor_id)
	if _responders.has(id) and str(_responders[id].mode) != "return":
		return
	if _combat_mode(actor) in ["aggro", "gun", "downed", "dead", "gone", "unknown"]:
		return
	routes_planned += 1
	if _assign(actor, "investigate", at, routes.route(actor.global_position, at, DISPATCH_ROUTE_LIMIT)):
		actor.speak("Shots fired. Checking it out.", 1.8)

## An officer who watched the offense happen pursues from where they stand.
func _enlist_witness(actor) -> void:
	if not _usable(actor) or not _is_patrol(actor):
		return
	var state := _enlist(actor, "wanted")
	if state.is_empty():
		return
	state.seen_clock = _clock
	state.search_info = _clock
	if str(state.mode) != "engaged":
		state.mode = "pursue"
		state.path = []
		state.index = 0

func _assign(actor, purpose: String, goal: Vector3, plan: Dictionary) -> bool:
	var points: PackedVector3Array = plan.get("points", PackedVector3Array())
	if points.is_empty():
		return false
	if _combat_mode(actor) != "":
		# Combat holds them as an alerted bystander; law needs them on foot now.
		_disengage(actor)
		if bool(actor.combat_override):
			return false
	var state := _enlist(actor, purpose)
	if state.is_empty():
		return false
	var path: Array = []
	for point in points:
		path.append(point)
	state.mode = "respond"
	state.goal = goal
	state.path = path
	state.index = 0
	state.stuck = 0.0
	state.unstick = 0
	state.search_info = _lkp_clock
	state.deadline = _clock + float(plan.get("length", 0.0)) / JOG_SPEED + 25.0
	_steer(actor, path[0], JOG_SPEED)
	dispatches += 1
	return true

func _enlist(actor, purpose: String) -> Dictionary:
	if is_instance_valid(actor) and actor.has_meta("police_assist"):
		# Answering a neighbor's call (city_police_assistance.gd); that service
		# hands the officer back to the beat before law may enlist them again.
		return {}
	var id := str(actor.actor_id)
	# A cruiser crew is bounded by its car (two at most), not the foot cap.
	var crew := _is_crew(actor)
	if _responders.has(id):
		var known: Dictionary = _responders[id]
		if str(known.mode) == "return":
			if not crew and _active_count() >= MAX_RESPONDERS:
				return {}
			known.mode = "respond"
			known.unstick = 0
		if purpose == "wanted":
			known.purpose = "wanted"
		return known
	if not crew and _active_count() >= MAX_RESPONDERS:
		return {}
	var at: Vector3 = actor.global_position
	var home := at
	var best := INF
	for point in actor.patrol_points:
		var distance: float = at.distance_squared_to(point)
		if distance < best:
			best = distance
			home = point
	if crew and cruisers != null:
		# Home is the door they stepped out of.
		var door: Vector3 = cruisers.crew_door(actor)
		if door.is_finite():
			home = door
	var state := {"actor": actor, "id": id, "purpose": purpose, "mode": "respond", "path": [], "index": 0,
		"goal": at, "home": home, "home_speed": float(actor.speed), "trail": [home, at], "trail_overflow": false,
		"stuck": 0.0, "unstick": 0, "last_at": at, "deadline": _clock + 120.0, "seen_clock": -INF,
		"search_points": [], "search_index": 0, "search_origin": Vector3.INF, "search_info": -INF,
		"announced": false, "assigned": _clock, "replan_at": 0.0, "crew": crew}
	_responders[id] = state
	# Read-only hint for other owners (combat/minimap); cleared on release.
	actor.set_meta("law_responder", true)
	return state

## Foot patrol responders (the dispatch cap); cruiser crews are reported separately.
func _active_count() -> int:
	var count := 0
	for state in _responders.values():
		count += int(str(state.mode) != "return" and not bool(state.get("crew", false)))
	return count

## Drop a responder who died, despawned or was disabled (no beat to walk back to).
func _forget(state: Dictionary) -> void:
	_responders.erase(state.id)
	var actor = state.actor
	if is_instance_valid(actor):
		actor.speed = float(state.home_speed)
		if actor.has_meta("law_responder"):
			actor.remove_meta("law_responder")
	if bool(state.get("crew", false)) and cruisers != null:
		cruisers.crew_lost(actor)

## A cruiser officer who just stepped out of a stopped car joins the foot
## response: pursuing what they can see, otherwise searching the last known spot.
func _enlist_crew(actor, door: Vector3, sighted: bool) -> Dictionary:
	var state := _enlist(actor, "wanted")
	if state.is_empty():
		return state
	state.home = door
	state.trail = [door, actor.global_position]
	state.search_info = _lkp_clock
	if sighted:
		state.mode = "pursue"
		state.seen_clock = _clock
		state.path = []
		state.index = 0
	else:
		_begin_search(state, 1)
	return state

## The crew's walk back to its car door (the return leg of a normal responder).
func _send_crew_home(actor, door: Vector3) -> void:
	if not _usable(actor) or bool(actor.combat_override) or not door.is_finite():
		return
	var state := _enlist(actor, "wanted")
	if state.is_empty():
		return
	state.home = door
	state.trail = [door, actor.global_position]
	state.trail_overflow = false
	_begin_return(state, 1)

## Leave the response without walking anywhere (re-seated behind a fade or reset).
func _drop_crew(actor) -> void:
	var id := str(actor.get("actor_id")) if is_instance_valid(actor) else ""
	if not _responders.has(id):
		return
	var state: Dictionary = _responders[id]
	_responders.erase(id)
	actor.speed = float(state.home_speed)
	if actor.has_meta("law_responder"):
		actor.remove_meta("law_responder")
	if not bool(actor.combat_override):
		actor.manual_target = false
		actor.has_target = false
		actor.blocked = false
		actor.blocked_seconds = 0.0
	if _surrender_officer == actor:
		_surrender_officer = null

func _tick_responder(state: Dictionary, elapsed: float, routes_left: int) -> int:
	var actor = state.actor
	if not _usable(actor):
		_forget(state)
		return routes_left
	var mode := _combat_mode(actor)
	if mode in ["dead", "gone", "downed", "unknown"]:
		return routes_left
	_record_trail(state)
	var hunting := wanted > 0 and str(state.mode) != "return"
	var sees := hunting and _in_view(actor, true) and _ray_sees(actor)
	if sees:
		_spotted(actor, state)
	if mode in ["aggro", "gun"]:
		state.mode = "engaged"
		if not sees and _clock - float(state.seen_clock) >= lost_sight_seconds:
			# Combat would stand and stare at a corner; law walks them to the last known spot.
			_disengage(actor)
			if not bool(actor.combat_override):
				routes_left = _begin_search(state, routes_left) if hunting else _begin_return(state, routes_left)
		return routes_left
	if mode != "":
		# Combat holds them as an alerted bystander or a fighter walking back.
		if not _wants_control(state):
			return routes_left
		_disengage(actor)
		if bool(actor.combat_override):
			return routes_left
	var current := str(state.mode)
	if (not sees and hunting and bool(state.get("crew", false)) and last_seen_seated and current != "return"
			and cruisers != null and cruisers.crew_should_remount(actor)):
		# The suspect drove off: back to the cruiser rather than searching yards.
		return _begin_return(state, routes_left)
	if sees:
		if _try_engage(actor, state):
			return routes_left
		routes_left = _pursue(state, routes_left)
	elif current == "engaged" or (current == "pursue" and _clock - float(state.seen_clock) >= lost_sight_seconds):
		routes_left = _begin_search(state, routes_left) if hunting else _begin_return(state, routes_left)
	elif (hunting and str(state.purpose) == "wanted" and (current == "respond" or current == "search")
			and _lkp_clock > float(state.search_info) + 1.0 and _clock >= float(state.replan_at)):
		# Another officer saw them more recently: search there instead.
		state.replan_at = _clock + 2.0
		routes_left = _begin_search(state, routes_left)
	return _advance(state, elapsed, routes_left)

func _wants_control(state: Dictionary) -> bool:
	return str(state.mode) != "return" and (wanted > 0 or str(state.purpose) == "investigate")

func _try_engage(actor, state: Dictionary) -> bool:
	var combat = _combat()
	if combat == null or not combat.has_method("engage_actor"):
		return false
	var armed := wanted >= 2 or incident_armed or incident_lethal
	if _flat(actor.global_position, _player_feet()) > (ALERT_RANGE if armed else MELEE_ENGAGE_RANGE):
		return false
	if not bool(combat.engage_actor(actor, armed)):
		return false
	engagements += 1
	state.mode = "engaged"
	state.path = []
	state.index = 0
	if not bool(state.announced):
		state.announced = true
		actor.speak("Police! Drop it!" if armed else "Police! Stop right there!", 1.8)
	return true

## Close in on a player the officer can see (fight budget full or still too far).
func _pursue(state: Dictionary, routes_left: int) -> int:
	var actor = state.actor
	var target := _player_feet()
	var at: Vector3 = actor.global_position
	var path: Array = state.path
	var keep := str(state.mode) == "pursue" and int(state.index) < path.size() and _flat(Vector3(state.goal), target) <= 3.0
	state.mode = "pursue"
	if keep or _clock < float(state.replan_at):
		return routes_left
	var offset := Vector3(target.x - at.x, 0.0, target.z - at.z)
	state.index = 0
	state.stuck = 0.0
	if offset.length() <= 2.2:
		state.path = []
		state.goal = at
		return routes_left
	var goal := target - offset.normalized() * 1.8
	state.goal = goal
	if _link_clear(at, goal):
		state.path = [goal]
	elif routes_left > 0:
		# Seen across a fence or corner: take the street around, not the obstacle.
		routes_left -= 1
		state.path = _route(at, goal)
		if (state.path as Array).is_empty():
			state.replan_at = _clock + 1.0
	else:
		state.path = []
	if not (state.path as Array).is_empty():
		_steer(actor, state.path[0], JOG_SPEED)
	return routes_left

func _begin_search(state: Dictionary, routes_left: int) -> int:
	var actor = state.actor
	var hunting := str(state.purpose) == "wanted" and last_known_position.is_finite()
	var origin: Vector3 = last_known_position if hunting else Vector3(state.goal)
	if str(state.mode) != "search":
		searches_started += 1
		if hunting:
			actor.speak("Lost them. Checking where they went." if is_finite(float(state.seen_clock)) else "Checking the area.", 2.0)
	state.mode = "search"
	state.search_origin = origin
	state.search_info = _lkp_clock
	state.deadline = _clock + float(search_seconds[clampi(wanted if hunting else 0, 0, MAX_WANTED)])
	state.search_index = 0
	state.unstick = 0
	var from: Vector3 = actor.global_position
	routes_left = _plan_path(state, origin, routes_left)
	if (state.path as Array).is_empty() and _flat(from, origin) > ARRIVE_RADIUS * 2.0:
		# The last known spot is unreachable from here: look around where we are.
		state.search_points = _search_points(from, origin)
	else:
		state.search_points = _search_points(origin, from)
	return routes_left

func _begin_return(state: Dictionary, routes_left: int) -> int:
	var actor = state.actor
	state.mode = "return"
	state.stuck = 0.0
	state.unstick = 0
	var at: Vector3 = actor.global_position
	var home: Vector3 = state.home
	var path: Array = []
	if bool(state.trail_overflow) and routes_left > 0:
		routes_left -= 1
		path = _route(at, home)
	if path.is_empty():
		# Retrace the ground this officer actually covered, newest first.
		var trail: Array = state.trail
		var last := at
		for i in range(trail.size() - 1, -1, -1):
			var point: Vector3 = trail[i]
			if _flat(point, last) >= 1.0:
				path.append(point)
				last = point
	if path.is_empty() or _flat(Vector3(path[-1]), home) > 0.5:
		path.append(home)
	state.path = path
	state.index = 0
	state.goal = home
	var length := 0.0
	var previous := at
	for point in path:
		length += previous.distance_to(point)
		previous = point
	state.deadline = _clock + length / maxf(return_speed, 0.5) + 20.0
	_steer(actor, path[0], return_speed)
	return routes_left

func _release(state: Dictionary) -> void:
	_responders.erase(state.id)
	var actor = state.actor
	if not is_instance_valid(actor):
		return
	actor.speed = float(state.home_speed)
	if actor.has_meta("law_responder"):
		actor.remove_meta("law_responder")
	if bool(state.get("crew", false)):
		# Back at the car door: the cruiser re-seats them (or keeps them until unseen).
		if not bool(actor.combat_override):
			actor.manual_target = false
			actor.has_target = false
			actor.blocked = false
			actor.blocked_seconds = 0.0
		if cruisers != null:
			cruisers.crew_arrived(actor, state)
		return
	if bool(actor.combat_override):
		return # Combat owns them now; its own release restores the beat.
	actor.manual_target = false
	actor.has_target = false
	actor.blocked = false
	actor.blocked_seconds = 0.0
	var points: Array = actor.patrol_points
	if not points.is_empty():
		var nearest := 0
		var best := INF
		for i in points.size():
			var distance: float = actor.global_position.distance_squared_to(points[i])
			if distance < best:
				best = distance
				nearest = i
		actor.patrol_index = nearest

func _plan_path(state: Dictionary, goal: Vector3, routes_left: int) -> int:
	var actor = state.actor
	var from: Vector3 = actor.global_position
	state.goal = goal
	state.index = 0
	state.stuck = 0.0
	var path: Array = []
	if _flat(from, goal) > ARRIVE_RADIUS:
		if routes_left > 0:
			routes_left -= 1
			path = _route(from, goal)
		elif _link_clear(from, goal):
			path = [goal]
	state.path = path
	if not path.is_empty():
		_steer(actor, path[0], _speed_for(state))
	return routes_left

func _advance(state: Dictionary, elapsed: float, routes_left: int) -> int:
	var actor = state.actor
	var mode := str(state.mode)
	if mode == "engaged":
		return routes_left
	if (mode == "respond" or mode == "search") and _clock >= float(state.deadline):
		return _begin_return(state, routes_left)
	if mode == "return" and _clock >= float(state.deadline):
		_release(state)
		return routes_left
	var at: Vector3 = actor.global_position
	var path: Array = state.path
	var index := int(state.index)
	if index < path.size():
		var point: Vector3 = path[index]
		if _flat(at, point) <= ARRIVE_RADIUS:
			index += 1
			state.index = index
			state.stuck = 0.0
			if index < path.size():
				_steer(actor, path[index], _speed_for(state))
		else:
			if not bool(actor.has_target) or _flat(Vector3(actor.target), point) > 0.25:
				_steer(actor, point, _speed_for(state))
			var moved := _flat(at, Vector3(state.last_at))
			state.stuck = float(state.stuck) + elapsed if moved < 0.12 else 0.0
			if float(state.stuck) >= STUCK_SECONDS:
				routes_left = _unstick(state, routes_left)
	state.last_at = at
	if _responders.has(state.id) and int(state.index) >= (state.path as Array).size():
		routes_left = _arrived(state, routes_left)
	return routes_left

func _arrived(state: Dictionary, routes_left: int) -> int:
	match str(state.mode):
		"respond":
			return _begin_search(state, routes_left)
		"pursue":
			if _clock - float(state.seen_clock) >= lost_sight_seconds:
				return _begin_search(state, routes_left) if wanted > 0 else _begin_return(state, routes_left)
		"search":
			var points: Array = state.search_points
			var next := int(state.search_index)
			if next < points.size():
				state.search_index = next + 1
				state.path = [points[next]]
				state.index = 0
				state.stuck = 0.0
				state.unstick = 0
				_steer(state.actor, points[next], SEARCH_SPEED)
		"return":
			_release(state)
	return routes_left

## Bounded recovery from a blocked step: step aside, replan once, skip a
## waypoint, then stop pushing. Never moves anyone through geometry.
func _unstick(state: Dictionary, routes_left: int) -> int:
	var actor = state.actor
	state.stuck = 0.0
	state.unstick = int(state.unstick) + 1
	var attempt := int(state.unstick)
	var path: Array = state.path
	var index := int(state.index)
	if attempt > MAX_UNSTICK or index >= path.size():
		match str(state.mode):
			"return":
				_release(state)
			"respond", "pursue":
				state.mode = "search"
				state.path = []
				state.index = 0
				state.search_origin = actor.global_position
				state.search_points = []
				state.search_index = 0
				state.deadline = _clock + float(search_seconds[clampi(wanted, 0, MAX_WANTED)])
			_:
				state.path = []
				state.index = 0
		return routes_left
	var point: Vector3 = path[index]
	var at: Vector3 = actor.global_position
	if attempt == 2 and routes_left > 0 and str(state.mode) != "return":
		routes_left -= 1
		var fresh := _route(at, Vector3(state.goal))
		if not fresh.is_empty():
			state.path = fresh
			state.index = 0
			_steer(actor, fresh[0], _speed_for(state))
			return routes_left
	var forward := Vector3(point.x - at.x, 0.0, point.z - at.z).normalized()
	var side := Vector3(-forward.z, 0.0, forward.x) * (1.0 if attempt % 2 == 1 else -1.0)
	for offset in [side, -side]:
		var ground := _walkable(at + offset * 1.4 + forward * 0.4)
		if not ground.is_empty() and _link_clear(at, ground.position):
			path.insert(index, ground.position)
			_steer(actor, ground.position, _speed_for(state))
			return routes_left
	if index + 1 < path.size() and _link_clear(at, path[index + 1]):
		state.index = index + 1
		_steer(actor, path[index + 1], _speed_for(state))
	return routes_left

func _record_trail(state: Dictionary) -> void:
	if str(state.mode) == "return" or bool(state.trail_overflow):
		return
	var at: Vector3 = state.actor.global_position
	var trail: Array = state.trail
	if trail.is_empty() or _flat(at, trail[-1]) >= TRAIL_SPACING:
		if trail.size() >= MAX_TRAIL:
			state.trail_overflow = true
			return
		trail.append(at)

func _search_points(origin: Vector3, officer_at: Vector3) -> Array:
	var result: Array = []
	if not origin.is_finite():
		return result
	# The heading is what an officer saw at the last sighting, never a live fix.
	var heading := last_seen_heading
	if heading.length_squared() < 0.01:
		heading = Vector3(origin.x - officer_at.x, 0.0, origin.z - officer_at.z)
	heading = heading.normalized() if heading.length_squared() > 0.0001 else Vector3.BACK
	for angle in [0.0, 1.0, -1.0]:
		var ground := _walkable(origin + heading.rotated(Vector3.UP, float(angle)) * SEARCH_RADIUS)
		if not ground.is_empty() and _link_clear(origin, ground.position):
			result.append(ground.position)
	return result

func _speed_for(state: Dictionary) -> float:
	match str(state.mode):
		"return":
			return return_speed
		"search":
			return JOG_SPEED if _flat(state.actor.global_position, Vector3(state.search_origin)) > 12.0 else SEARCH_SPEED
	return JOG_SPEED

## Movement always goes through the actor's own collision-swept tick
## (turn in place first, then forward). Never while combat owns the body.
func _steer(actor, point: Vector3, speed: float) -> void:
	if not is_instance_valid(actor) or bool(actor.combat_override):
		return
	actor.speed = speed
	actor.set_target(point, true)

func _route(from: Vector3, goal: Vector3) -> Array:
	routes_planned += 1
	var result: Array = []
	if routes == null:
		return result
	var plan := routes.route(from, goal, DISPATCH_ROUTE_LIMIT)
	for point in plan.points:
		result.append(point)
	return result

func _spotted(actor, state: Dictionary) -> void:
	var feet := _player_feet()
	_observe_player(feet)
	if not state.is_empty():
		state.seen_clock = _clock
	if cruisers != null:
		# Radioed: cruisers without their own sight head for this spot.
		cruisers.radio(feet)
	if _flat(actor.global_position, feet) <= SURRENDER_RANGE:
		_surrender_officer = actor
		_surrender_clock = _clock

## Bookkeeping for one real sighting (an officer's or a cruiser crew's own ray):
## the only way the last known position and heading change between reports.
func _observe_player(feet: Vector3) -> void:
	if not seen and not _was_seen:
		sightings += 1
	seen = true
	last_known_position = feet
	_lkp_clock = _clock
	var body = _vehicle_body()
	last_seen_seated = body != null
	if body == null:
		body = _player()
	if body is CharacterBody3D:
		var motion := Vector3(body.velocity.x, 0.0, body.velocity.z)
		if motion.length() > 0.5:
			last_seen_heading = motion.normalized()
		elif body.get("yaw") != null:
			last_seen_heading = Vector3(sin(float(body.yaw)), 0.0, cos(float(body.yaw)))

func last_known_clock() -> float:
	return _lkp_clock

func _in_view(actor, alerted: bool) -> bool:
	var feet := _player_feet()
	if not feet.is_finite():
		return false
	var offset := Vector3(feet.x - actor.global_position.x, 0.0, feet.z - actor.global_position.z)
	var distance := offset.length()
	if distance > (ALERT_RANGE if alerted else SIGHT_RANGE):
		return false
	if distance <= NOTICE_RADIUS:
		return true
	var forward := Vector3(sin(float(actor.yaw)), 0.0, cos(float(actor.yaw)))
	return forward.dot(offset / distance) >= (ALERT_VIEW_DOT if alerted else PATROL_VIEW_DOT)

func _ray_sees(actor) -> bool:
	recognition_rays += 1
	return _sees_player(actor.global_position + Vector3.UP * EYE_HEIGHT, actor.get_rid())

## One sight ray to the player. Driving, it ends at the occupant's seat and
## excludes their own car (that ray only); on foot it ends at the chest.
func _sees_player(eye: Vector3, observer: RID) -> bool:
	return _ray_clear(_space(), eye, _player_sight_point(), _sight_skip(observer, _vehicle_body()))

func _player_sight_point() -> Vector3:
	var vehicle = _vehicle_body()
	if vehicle is Node3D:
		return (vehicle as Node3D).global_transform * OCCUPANT_LOCAL
	var feet := _player_feet()
	return feet + Vector3.UP * CHEST_HEIGHT if feet.is_finite() else Vector3.INF

func _sight_skip(observer: RID, vehicle) -> Array[RID]:
	var skip: Array[RID] = []
	if observer.is_valid():
		skip.append(observer)
	if is_instance_valid(vehicle) and vehicle is CollisionObject3D:
		var own := (vehicle as CollisionObject3D).get_rid()
		if own != observer:
			skip.append(own)
	return skip

func _ray_clear(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, skip: Array[RID]) -> bool:
	if space == null or not from.is_finite() or not to.is_finite():
		return false
	_ray.from = from
	_ray.to = to
	_ray.exclude = skip
	return space.intersect_ray(_ray).is_empty()

## Legacy fixture helper: a ray that may end on `target_body` (kept for callers).
func _clear_sight(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: RID, target_body: Object = null) -> bool:
	if space == null or not from.is_finite() or not to.is_finite():
		return false
	_ray.from = from
	_ray.to = to
	var skip: Array[RID] = []
	if exclude.is_valid():
		skip.append(exclude)
	_ray.exclude = skip
	var hit := space.intersect_ray(_ray)
	return hit.is_empty() or (target_body != null and hit.get("collider") == target_body)

## Swept walking link (ankle-to-hip sphere) against buildings, props and cars.
func _link_clear(a: Vector3, b: Vector3) -> bool:
	if not a.is_finite() or not b.is_finite():
		return false
	if a.distance_squared_to(b) < 0.04:
		return true
	var space := _space()
	if space == null:
		return false
	if _sweep_query == null:
		_sweep_query = PhysicsShapeQueryParameters3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.26
		_sweep_query.shape = sphere
		_sweep_query.collision_mask = 2 | 16
		_sweep_query.margin = 0.02
	var from := a + Vector3.UP * 0.65
	_sweep_query.transform = Transform3D(Basis.IDENTITY, from)
	_sweep_query.motion = b + Vector3.UP * 0.65 - from
	var fraction := space.cast_motion(_sweep_query)
	return fraction.size() < 2 or fraction[0] >= 0.999

func _walkable(point: Vector3) -> Dictionary:
	var space := _space()
	if space == null or not point.is_finite():
		return {}
	_ground_ray.from = point + Vector3.UP * 1.6
	_ground_ray.to = point - Vector3.UP * 2.0
	var hit := space.intersect_ray(_ground_ray)
	if hit.is_empty() or Vector3(hit.normal).y < 0.75:
		return {}
	var foot: Vector3 = Vector3(hit.position) + Vector3.UP * 0.012
	if _probe_query == null:
		_probe_query = PhysicsShapeQueryParameters3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.3
		capsule.height = 1.6
		_probe_query.shape = capsule
		_probe_query.collision_mask = 2 | 16
		_probe_query.margin = 0.02
	_probe_query.transform = Transform3D(Basis.IDENTITY, foot + Vector3.UP * 0.9)
	if not space.intersect_shape(_probe_query, 1).is_empty():
		return {}
	return {"position": foot}

# --------------------------------------------------------------- recovery

func _surrender_ready() -> bool:
	return wanted > 0 and not recovering and is_instance_valid(_surrender_officer) and _clock - _surrender_clock <= 1.0

func _surrender_target():
	var feet := _player_feet()
	var candidates: Array = []
	if is_instance_valid(_surrender_officer) and _clock - _surrender_clock <= 1.5:
		candidates.append(_surrender_officer)
	for actor in _police():
		if not candidates.has(actor):
			candidates.append(actor)
	var rays := 0
	for actor in candidates:
		if rays >= 4:
			break
		if not _usable(actor) or _combat_mode(actor) in ["downed", "dead", "gone"]:
			continue
		if _flat(actor.global_position, feet) > SURRENDER_RANGE:
			continue
		rays += 1
		if _sees_player(actor.global_position + Vector3.UP * EYE_HEIGHT, actor.get_rid()):
			return actor
	return null

func _begin_recovery(kind: String, officer) -> void:
	_recovery_sequence += 1
	recovering = true
	_recovery = {"kind": kind, "stage": "down" if kind == "hospital" else "hands_up", "time": 0.0,
		"sequence": _recovery_sequence, "relocated": false, "charged": false, "fee": 0, "tier": wanted,
		"facility": {}, "exit_ticks": 0, "defeat_after": false}
	phase = "hospital" if kind == "hospital" else "arrest"
	_events.clear()
	_reports.clear()
	var combat = _combat()
	if combat != null and combat.has_method("cancel_player_actions"):
		combat.cancel_player_actions()
	# Officers stop fighting someone who is down or has given up.
	for state in _responders.values():
		var actor = state.actor
		if is_instance_valid(actor) and _combat_mode(actor) in ["aggro", "gun", "return"]:
			_disengage(actor)
	if cruisers != null:
		cruisers.hold_all()
	_exit_vehicle()
	if kind == "arrest":
		if is_instance_valid(officer):
			officer.speak("Hands where I can see them. You're coming with me.", 2.2)
			var id := str(officer.actor_id)
			if _responders.has(id) and not bool(officer.combat_override):
				var feet := _player_feet()
				var offset := Vector3(feet.x - officer.global_position.x, 0.0, feet.z - officer.global_position.z)
				if offset.length() > 2.0:
					_steer(officer, feet - offset.normalized() * 1.5, SEARCH_SPEED)
		_notify("You surrendered. Hands up.")
	else:
		_notify("You're down. An ambulance is on the way.")

func _tick_recovery(delta: float) -> void:
	var player := _player()
	if player == null:
		_finish_recovery()
		return
	_recovery.time = float(_recovery.time) + delta
	var stage := str(_recovery.stage)
	var arrest := str(_recovery.kind) == "arrest"
	if arrest or stage == "relocate" or stage == "fade_in":
		_hold_player(player, arrest and stage != "fade_in")
	match stage:
		"down", "hands_up":
			_exit_vehicle()
			if float(_recovery.time) >= float(stage_seconds.get(stage, 1.5)):
				_next_stage("fade_out")
		"fade_out":
			if float(_recovery.time) >= float(stage_seconds.get("fade_out", 1.0)):
				_next_stage("relocate")
		"relocate":
			if _relocate():
				_next_stage("fade_in")
		"fade_in":
			if float(_recovery.time) >= float(stage_seconds.get("fade_in", 1.2)):
				_finish_recovery()

func _next_stage(stage: String) -> void:
	_recovery.stage = stage
	_recovery.time = 0.0

## Runs once per recovery, behind a full fade: vehicle exit, a validated release
## point at the real facility, heal + clear aggro, then exactly one fee.
func _relocate() -> bool:
	if bool(_recovery.relocated):
		return true
	var player := _player()
	var driving = _ridden_transport()
	var hospital := str(_recovery.kind) == "hospital"
	var release: Dictionary = {"ok": false, "reason": "vehicle exit refused", "site": "hospital" if hospital else "police"}
	if driving != null and driving.get("active") == true:
		_recovery.exit_ticks = int(_recovery.exit_ticks) + 1
		_exit_vehicle()
		# A car under a low canopy can have no safe local dismount. Behind the
		# full fade, release authority directly at a surveyed clear facility.
		if driving.get("active") == true and driving.has_method("recovery_exit_at"):
			var destination: Dictionary = Facilities.release_point(level, "hospital" if hospital else "police", player)
			if bool(destination.get("ok", false)) and driving.recovery_exit_at(Vector3(destination.position), float(destination.yaw)):
				release = destination
		if driving.get("active") == true and int(_recovery.exit_ticks) < MAX_EXIT_TICKS:
			return false
	if driving == null or driving.get("active") != true:
		if not bool(release.get("ok", false)):
			release = Facilities.release_point(level, "hospital" if hospital else "police", player)
		if bool(release.get("ok", false)):
			_place_player(player, Vector3(release.position), float(release.yaw))
	_recovery.facility = release
	last_release = release.duplicate()
	_recovery.relocated = true
	var assistance = level.get("police_assistance")
	if assistance != null and assistance.has_method("reset_state"):
		assistance.reset_state()
	var combat = _combat()
	if combat != null and combat.has_method("recover_player"):
		combat.recover_player()
	_end_incident()
	_events.clear()
	_reports.clear()
	if not bool(_recovery.charged):
		_recovery.charged = true
		_recovery.fee = _charge(hospital, int(_recovery.tier))
	var place := str(release.get("name", "the hospital" if hospital else "the police station"))
	if not bool(release.get("ok", false)):
		# No clear entrance (or the car would not let go): never teleport into geometry.
		place = "the spot where you stood"
	if hospital:
		_notify("Treated at %s · bill $%d" % [place, int(_recovery.fee)])
	else:
		_notify("Booked and released at %s · fine $%d" % [place, int(_recovery.fee)])
	return true

func _charge(hospital: bool, tier: int) -> int:
	var amount: int = HOSPITAL_FEE if hospital else int(ARREST_FINES[clampi(tier, 1, MAX_WANTED)])
	var charged := 0
	var progression = _progression()
	if progression != null and progression.has_method("debit"):
		charged = maxi(0, int(progression.debit(amount, "hospital_bill" if hospital else "arrest_fine")))
	fees_charged += charged
	last_fee = charged
	return charged

func _finish_recovery() -> void:
	var finished := _recovery
	recovering = false
	recoveries_completed += 1
	var hospital := str(finished.get("kind", "hospital")) == "hospital"
	if hospital:
		hospital_visits += 1
	else:
		arrests += 1
	var player := _player()
	if player != null:
		player.set("enabled", true)
		var puppet = player.get("puppet")
		if puppet != null and puppet.has_method("pose"):
			puppet.pose({"walk": 0.0})
	var facility: Dictionary = finished.get("facility", {})
	var place := str(facility.get("name", "the hospital" if hospital else "the police station"))
	if not bool(facility.get("ok", false)):
		place = "the spot where you stood"
	last_recovery = {"kind": finished.get("kind", ""), "sequence": finished.get("sequence", 0), "fee": finished.get("fee", 0),
		"place": place, "relocated": bool(facility.get("ok", false))}
	_recovery = {}
	_shade_alpha = 0.0
	phase = "clear"
	_show_transient(("Treated at %s · $%d bill" if hospital else "Released from %s · $%d fine") % [place, int(finished.get("fee", 0))], 6.0)
	if bool(finished.get("defeat_after", false)):
		var combat = _combat()
		var downed = combat.get("downed") if combat != null else null
		if downed != null and float(downed) > 0.0:
			_begin_recovery("hospital", null)

func _hold_player(player: CharacterBody3D, hands_up: bool) -> void:
	player.set("enabled", false)
	player.velocity = Vector3.ZERO
	player.set("current_speed", 0.0)
	var puppet = player.get("puppet")
	if hands_up and puppet != null and puppet.has_method("pose"):
		puppet.pose({"walk": 0.0, "armR": [-2.75, 0.3], "armL": [-2.75, 0.3]})

func _place_player(player: CharacterBody3D, at: Vector3, heading: float) -> void:
	var basketball = level.get("basketball")
	if basketball != null and basketball.has_method("suspend"):
		basketball.suspend(true)
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.set("current_speed", 0.0)
	if player.has_method("reset_jump"):
		player.reset_jump()
	if player.has_method("set_orbiting"):
		player.set_orbiting(false)
	player.set("_orbit_basis_latched", false)
	player.set("yaw", heading)
	player.set("camera_yaw", heading)
	player.set("camera_pitch", 0.24)
	var puppet = player.get("puppet")
	if puppet != null and puppet.get("g") is Node3D:
		puppet.g.rotation.y = heading
	if player.has_method("update_camera"):
		player.update_camera()
	if player.has_method("reset_physics_interpolation"):
		player.reset_physics_interpolation()
	var camera = player.get("camera")
	if camera is Node and camera.has_method("reset_physics_interpolation"):
		camera.reset_physics_interpolation()
	# The level's fall guard snaps back to its last safe point; move it with us.
	if level.get("_safe_position") != null:
		level.set("_safe_position", at)

func _exit_vehicle() -> bool:
	var driving = _ridden_transport()
	if driving == null or driving.get("active") != true:
		return true
	if driving.has_method("exit_vehicle"):
		vehicle_exits += 1
		driving.exit_vehicle(true)
	return driving.get("active") != true

func _ridden_transport():
	var bicycle = level.get("bicycle") if level != null else null
	if bicycle != null and bicycle.get("active") == true:
		return bicycle
	return _driving()

# --------------------------------------------------------------- cue + text

func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.name = "LawRecoveryCue"
	# Below the HUD/menu layer (12): menus and the status ledger stay readable.
	_overlay.layer = 11
	add_child(_overlay)
	_shade = ColorRect.new()
	_shade.name = "Shade"
	_shade.color = Color(0.02, 0.03, 0.04, 0.0)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_shade)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cue = Label.new()
	_cue.name = "Cue"
	_cue.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cue.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	C.text(_cue, "display", 30, T.PAPER)
	_overlay.add_child(_cue)
	_cue.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.hide()

func _update_overlay() -> void:
	if _overlay == null:
		return
	var alpha := 0.0
	var text := ""
	if recovering:
		var hospital := str(_recovery.kind) == "hospital"
		var time := float(_recovery.time)
		var heading := "DOWN · AN AMBULANCE IS ON THE WAY" if hospital else "HANDS UP · YOU'RE UNDER ARREST"
		match str(_recovery.stage):
			"down", "hands_up":
				alpha = 0.35 * clampf(time / 0.6, 0.0, 1.0)
				text = heading
			"fade_out":
				alpha = lerpf(0.35, 1.0, clampf(time / maxf(float(stage_seconds.get("fade_out", 1.0)), 0.01), 0.0, 1.0))
				text = heading
			"relocate":
				alpha = 1.0
			"fade_in":
				alpha = 1.0 - clampf(time / maxf(float(stage_seconds.get("fade_in", 1.2)), 0.01), 0.0, 1.0)
				var facility: Dictionary = _recovery.get("facility", {})
				text = str(facility.get("name", "")).to_upper()
	_shade_alpha = alpha
	_shade.color.a = alpha
	_cue.text = text
	_cue.modulate.a = clampf(alpha * 1.6, 0.0, 1.0)
	_overlay.visible = alpha > 0.001 and not _world_paused()

func _process(_delta: float) -> void:
	# Menus and the inspector must never sit behind a black recovery fade.
	if _overlay != null:
		var showing := recovering and _shade_alpha > 0.001 and not _world_paused()
		if _overlay.visible != showing:
			_overlay.visible = showing

func _refresh_message() -> void:
	if recovering:
		var hospital := str(_recovery.kind) == "hospital"
		match str(_recovery.stage):
			"down":
				message = "Down · an ambulance is on the way"
			"hands_up":
				message = "Surrendering · hands up"
			"fade_in":
				message = "Recovering at %s" % str((_recovery.get("facility", {}) as Dictionary).get("name", "the hospital" if hospital else "the police station"))
			_:
				message = "Taken to the hospital…" if hospital else "Taken to the precinct…"
		return
	if wanted > 0:
		var label := "WANTED %d/%d" % [wanted, MAX_WANTED]
		var tail := " · G surrender" if _surrender_ready() else ""
		match phase:
			"pursuit":
				message = "%s · Police have eyes on you%s" % [label, tail]
			"responding":
				message = "%s · A patrol is responding to a report" % label
			"search":
				message = "%s · Police are searching where you were last seen%s" % [label, tail]
			_:
				message = "%s · Lying low · clears in %d s" % [label, ceili(maxf(_cooldown_left, 0.0))]
		return
	if _clock < _transient_until:
		message = _transient
	elif phase == "reported":
		message = "Someone is calling the police"
	elif phase == "investigating":
		message = "Police are checking out shots fired nearby"
	else:
		message = ""

func _show_transient(text: String, seconds: float) -> void:
	_transient = text
	_transient_until = _clock + seconds

func _notify(text: String) -> void:
	last_notice = text
	if use_level_notices and level != null and level.has_method("show_notice"):
		level.show_notice(text)

# --------------------------------------------------------------- lookups

func _world_paused() -> bool:
	if level == null:
		return true
	if level.get("paused") == true:
		return true
	var inspector = level.get("inspector")
	if inspector != null and inspector.get("active") == true:
		return true
	return is_inside_tree() and get_tree().paused

func _space() -> PhysicsDirectSpaceState3D:
	if level is Node3D and (level as Node3D).is_inside_tree():
		var world := (level as Node3D).get_world_3d()
		if world != null:
			return world.direct_space_state
	return null

func _player() -> CharacterBody3D:
	var value = level.get("player") if level != null else null
	return value if is_instance_valid(value) and value is CharacterBody3D else null

func _combat():
	return level.get("combat") if level != null else null

func _driving():
	return level.get("driving") if level != null else null

func _progression():
	return level.get("progression") if level != null else null

func _crowd():
	var npcs = level.get("npcs") if level != null else null
	return npcs.get("crowd") if npcs != null else null

func _vehicle_body() -> Object:
	var driving = _driving()
	if driving != null and driving.get("active") == true:
		var vehicle = driving.get("vehicle")
		if is_instance_valid(vehicle):
			return vehicle
	return null

func _player_feet() -> Vector3:
	var vehicle = _vehicle_body()
	if vehicle is Node3D:
		return (vehicle as Node3D).global_position
	var player := _player()
	return player.global_position if player != null else Vector3.INF

func _police() -> Array:
	var result: Array = []
	var npcs = level.get("npcs") if level != null else null
	var actors = npcs.get("actors") if npcs != null else null
	if not actors is Dictionary:
		return result
	for actor in actors.values():
		if _usable(actor) and actor.get("actor_id") != null and _is_police(actor):
			result.append(actor)
	return result

func _is_police(actor) -> bool:
	var id := str(actor.get("actor_id"))
	return str(actor.get("cast_id")).begins_with("cop_") or id == "officer" or id.begins_with(PATROL_PREFIX)

## Only foot patrols are dispatched; mission contacts (Officer Dan) never move.
func _is_patrol(actor) -> bool:
	return str(actor.get("actor_id")).begins_with(PATROL_PREFIX)

## Dedicated cruiser officers (patrol identities that travel by car).
func _is_crew(actor) -> bool:
	return str(actor.get("actor_id")).begins_with(Cruisers.CREW_PREFIX)

func _usable(actor) -> bool:
	return is_instance_valid(actor) and actor.get("dead") != true and actor.get("enabled") == true

func _is_dead_id(id: String) -> bool:
	if id.is_empty():
		return false
	var combat = _combat()
	if combat != null and combat.has_method("is_actor_dead") and bool(combat.is_actor_dead(id)):
		return true
	if id.begins_with("crowd_") and id.substr(6).is_valid_int():
		var crowd = _crowd()
		if crowd != null and crowd.has_method("is_dead") and bool(crowd.is_dead(int(id.substr(6)))):
			return true
	return false

## "" when combat does not own the body; otherwise combat's current mode.
## Reads combat's state without changing it (prefers a public actor_mode()).
func _combat_mode(actor) -> String:
	if not is_instance_valid(actor):
		return "gone"
	if actor.get("dead") == true:
		return "dead"
	if actor.get("combat_override") != true:
		return ""
	var combat = _combat()
	if combat == null:
		return "unknown"
	if combat.has_method("actor_mode"):
		return str(combat.actor_mode(actor))
	var key: int = actor.get_instance_id()
	var active = combat.get("_active")
	if active is Dictionary and active.has(key):
		return str(active[key].get("mode", "aggro"))
	var panic = combat.get("_panic")
	if panic is Dictionary and panic.has(key):
		return "panic:" + str(panic[key].get("mode", ""))
	var knocked = combat.get("_knocked")
	if knocked is Dictionary and knocked.has(str(actor.get("actor_id"))):
		return "downed"
	return "unknown"

func _disengage(actor) -> void:
	var combat = _combat()
	if combat != null and combat.has_method("disengage_actor") and is_instance_valid(actor):
		combat.disengage_actor(actor)

func _base_severity(kind: String) -> float:
	return float(SEVERITY.get(kind, DEFAULT_SEVERITY))

func _offense_severity(kind: String, victim_id: String) -> float:
	if kind == "vehicle_collision" and cruisers != null and cruisers.is_police_vehicle_id(victim_id):
		return POLICE_RAM_SEVERITY
	return _base_severity(kind)

static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
