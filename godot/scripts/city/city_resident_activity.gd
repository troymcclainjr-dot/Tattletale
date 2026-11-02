extends RefCounted
## Local outings reuse checked sidewalks; no off-corridor shortcuts. Greetings
## add at most one visibility ray per second across the entire resident roster.
const RADIUS := 26.0
const MAX_STARTS_PER_TICK := 1
const SOCIAL_INTERVAL := 1.0
const SOCIAL_RADIUS := 3.6
const MAX_SOCIAL_CANDIDATES := 40
const OUTINGS := [
	{"label": "Neighborhood check-in", "pause": 7.0, "gesture": "look"},
	{"label": "Stretch break", "pause": 5.0, "gesture": "stretch"},
	{"label": "Quiet moment on the block", "pause": 9.0, "gesture": "rest"},
	{"label": "Fresh-air walk", "pause": 6.0, "gesture": "look"},
]
var starts_this_tick := 0
var starts := 0
var returns := 0
var arrivals := 0
var max_starts := 0
var greetings := 0
var social_queries := 0
var social_candidates := 0
var _social_elapsed := 0.0
var _social_cursor := 0

func begin_tick() -> void:
	max_starts = maxi(max_starts, starts_this_tick)
	starts_this_tick = 0

static func available(actor) -> bool:
	return not actor.dead and actor.enabled and actor.physical and actor.routine_enabled \
		and not actor.combat_override and not actor.bicycle_override and not actor.has_meta("combat_controlled") \
		and not actor.has_meta("police_custody_completed") and not actor.has_meta("police_custody") \
		and not actor.needs_replan and actor.recovery_points.is_empty() and actor.recovery_wait <= 0.0

static func dwell_seconds(identity: String) -> float:
	return 10.0 + float(posmod(identity.hash(), 13))

static func outing(identity: String) -> Dictionary:
	# Stable preferences add readable purpose without changing roster/save IDs or
	# pretending that an arbitrary sidewalk point is a traversable shop interior.
	return OUTINGS[posmod(identity.hash(), OUTINGS.size())]

static func social_ready(actor) -> bool:
	return available(actor) and actor.activity != "sleep" and actor.route_completed \
		and not actor.has_target and not actor.moving and actor._speech_remaining <= 0.0 \
		and actor.social_cooldown <= 0.0 and float(actor.local_activity.elapsed) >= 2.0 \
		and str(actor.local_activity.phase) in ["dwelling", "settled", "short_pause"]

func tick_social(actors: Array, delta: float) -> void:
	social_queries = 0
	social_candidates = 0
	_social_elapsed += minf(delta, 0.25)
	if _social_elapsed < SOCIAL_INTERVAL or actors.is_empty():
		return
	_social_elapsed = 0.0
	# Round-robin one source per second; never an all-pairs crowd query.
	var actor = actors[_social_cursor % actors.size()]
	_social_cursor = (_social_cursor + 1) % actors.size()
	if not social_ready(actor) or actor.level.player == null or actor.global_position.distance_squared_to(actor.level.player.global_position) > RADIUS * RADIUS:
		return
	var partner = null
	var closest := SOCIAL_RADIUS * SOCIAL_RADIUS
	for other in actors:
		if social_candidates >= MAX_SOCIAL_CANDIDATES:
			break
		social_candidates += 1
		if other == actor or not social_ready(other):
			continue
		var distance: float = actor.global_position.distance_squared_to(other.global_position)
		if distance < closest and distance > 0.7 * 0.7:
			partner = other
			closest = distance
	if partner == null:
		return
	# One bounded visibility ray prevents greetings through fences/walls/cars.
	var ray := PhysicsRayQueryParameters3D.create(actor.global_position + Vector3.UP * 1.3, partner.global_position + Vector3.UP * 1.3, 2 | 16)
	social_queries = 1
	if not actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
		return
	actor.begin_local_greeting(partner, false)
	partner.begin_local_greeting(actor, true)
	greetings += 1

func tick(actor, route: Dictionary, delta: float) -> void:
	if not available(actor) or actor.level.player == null:
		return
	var state: Dictionary = actor.local_activity
	# Finish a started outing even if its stop crosses the presentation radius.
	# Only new activity starts are near-gated; distant idle residents stay asleep.
	if actor.global_position.distance_squared_to(actor.level.player.global_position) > RADIUS * RADIUS and str(state.phase) not in ["short_walk", "short_pause", "returning"]:
		return
	if not actor.route_completed or actor.has_target or actor.moving or actor.social_remaining > 0.0:
		return
	state.elapsed = float(state.elapsed) + minf(delta, 0.25)
	match str(state.phase):
		"travelling":
			state.phase = "arriving"
			state.elapsed = 0.0
			arrivals += 1
		"arriving":
			if float(state.elapsed) >= 1.5:
				state.phase = "dwelling"
				state.elapsed = 0.0
		"dwelling":
			if actor.activity != "sleep" and float(state.elapsed) >= dwell_seconds(actor.actor_id):
				_start_walk(actor, route)
		"short_walk":
			state.phase = "short_pause"
			state.elapsed = 0.0
		"short_pause":
			if float(state.elapsed) >= float(outing(actor.actor_id).pause) and starts_this_tick < MAX_STARTS_PER_TICK:
				var path: Array[Vector3] = []
				path.assign(state.home_path)
				actor.assign_activity_route(path)
				state.phase = "returning"
				state.elapsed = 0.0
				starts_this_tick += 1
				returns += 1
		"returning":
			state.phase = "settled"
			state.elapsed = 0.0
			state.home_path = []
		"settled":
			if float(state.elapsed) >= 30.0:
				state.phase = "dwelling"
				state.elapsed = 0.0

func _start_walk(actor, route: Dictionary) -> void:
	if starts_this_tick >= MAX_STARTS_PER_TICK or route.is_empty():
		return
	var corridor: Array[Vector3] = route.points
	var anchor: int = route.anchors.get(actor.activity, -1)
	if anchor < 0 or anchor >= corridor.size() or actor.global_position.distance_to(corridor[anchor]) > .25:
		return
	var length := 8 + posmod(actor.actor_id.hash(), 11)
	var direction := 1 if anchor < corridor.size() / 2 else -1
	var finish := clampi(anchor + direction * length, 0, corridor.size() - 1)
	if absi(finish - anchor) < 3:
		return
	var path: Array[Vector3] = []
	for i in range(anchor, finish + direction, direction):
		path.append(corridor[i])
	var home_path: Array[Vector3] = path.duplicate()
	home_path.reverse()
	actor.assign_activity_route(path)
	actor.local_activity.phase = "short_walk"
	actor.local_activity.elapsed = 0.0
	actor.local_activity.home_path = home_path
	starts_this_tick += 1
	starts += 1

func status() -> Dictionary:
	return {"arrivals": arrivals, "short_walks": starts, "returns": returns,
		"last_starts": starts_this_tick, "max_starts": maxi(max_starts, starts_this_tick), "radius": RADIUS,
		"physics_queries": 0, "greetings": greetings, "social_queries": social_queries,
		"social_candidates": social_candidates, "social_interval": SOCIAL_INTERVAL}
