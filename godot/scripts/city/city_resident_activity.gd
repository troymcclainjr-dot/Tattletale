extends RefCounted
## Local errands reuse the resident's checked sidewalk corridor. No new queries,
## destinations or off-corridor shortcuts; the actor still checks each footfall.
const RADIUS := 26.0
const MAX_STARTS_PER_TICK := 1
var starts_this_tick := 0
var starts := 0
var returns := 0
var arrivals := 0
var max_starts := 0

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

func tick(actor, route: Dictionary, delta: float) -> void:
	if not available(actor) or actor.level.player == null or actor.global_position.distance_squared_to(actor.level.player.global_position) > RADIUS * RADIUS:
		return
	var state: Dictionary = actor.local_activity
	if not actor.route_completed or actor.has_target or actor.moving:
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
			if float(state.elapsed) >= 3.0 and starts_this_tick < MAX_STARTS_PER_TICK:
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
	var length := 3 + posmod(actor.actor_id.hash(), 4)
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
		"physics_queries": 0}
