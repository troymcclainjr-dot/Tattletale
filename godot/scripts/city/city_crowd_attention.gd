extends RefCounted
## Nearby presentation only. No placement, route, identity or population changes.
const RADIUS := 26.0
const MAX_ACTIVE := 24
const MAX_UPDATES := 12
const MAX_DECISIONS := 2
const MAX_MEMBERS := 9
const Life := preload("res://scripts/city/city_crowd_idle_life.gd")
var active: Dictionary = {}
var updates := 0
var decisions := 0
var queries := 0
var selections := 0
var watches := 0
var turns := 0
var max_updates := 0
var max_queries := 0
var _ray := PhysicsRayQueryParameters3D.new()

func begin_tick(crowd: Node3D) -> void:
	max_updates = maxi(max_updates, updates)
	max_queries = maxi(max_queries, queries)
	updates = 0
	decisions = 0
	queries = 0
	for index in active.keys():
		var resident: Dictionary = crowd.residents[index]
		if not eligible(resident, crowd.level.player.global_position):
			active.erase(index)
			resident.erase("attention_kind")
			resident.erase("attention_partner")

static func eligible(resident: Dictionary, player: Vector3) -> bool:
	return Life.owns_idle(resident) and not resident.get("idle_pacing", false) \
		and resident.position.distance_squared_to(player) <= RADIUS * RADIUS

func present(crowd: Node3D, index: int) -> void:
	var resident: Dictionary = crowd.residents[index]
	if updates >= MAX_UPDATES or not eligible(resident, crowd.level.player.global_position):
		return
	if not active.has(index):
		if active.size() >= MAX_ACTIVE or crowd.social_group_id(index).is_empty():
			return
		active[index] = {"next": 0.0, "last": crowd._clock, "partner": -1, "yaw": resident.yaw, "kind": "listening", "serial": 0}
	var state: Dictionary = active[index]
	updates += 1
	if int(state.partner) >= 0 and not eligible(crowd.residents[int(state.partner)], crowd.level.player.global_position):
		state.partner = -1
		state.kind = "listening"
		state.next = crowd._clock
	if crowd._clock >= float(state.next) and decisions < MAX_DECISIONS:
		decisions += 1
		_choose(crowd, index, state)
	# Cap elapsed time on re-entry; never snap to a stale angle after a stall.
	var delta := clampf(crowd._clock - float(state.last), 0.0, 0.35)
	state.last = crowd._clock
	var before: float = resident.yaw
	resident.yaw = rotate_toward(before, float(state.yaw), delta * 1.25)
	turns += int(absf(angle_difference(before, resident.yaw)) > 0.001)
	resident.attention_kind = state.kind
	resident.attention_partner = state.partner

func _choose(crowd: Node3D, index: int, state: Dictionary) -> void:
	var resident: Dictionary = crowd.residents[index]
	state.serial = int(state.serial) + 1
	state.next = crowd._clock + 6.0 + Life.phase_for(index + int(state.serial)) * 5.0
	var target: Vector3 = resident.position
	var partner := -1
	var kind := "listening"
	# Court focus exists only for authored, checked court-edge group anchors.
	if resident.has("attention_court") and int(state.serial) % 3 != 0:
		target = resident.attention_court
		kind = "watching_court"
	else:
		var members: Array[int] = crowd.social_group_members(index, MAX_MEMBERS)
		var start := posmod(index + int(state.serial), maxi(1, members.size()))
		for offset in members.size():
			var candidate: int = members[(start + offset) % members.size()]
			if candidate == index or candidate == int(state.partner):
				continue
			var other: Dictionary = crowd.residents[candidate]
			if not eligible(other, crowd.level.player.global_position) or other.position.distance_squared_to(resident.position) > 36.0:
				continue
			partner = candidate
			target = other.position
			kind = "conversation"
			break
		# Two-person groups retain their partner between glances.
		if partner < 0 and int(state.partner) >= 0:
			var old: Dictionary = crowd.residents[int(state.partner)]
			if eligible(old, crowd.level.player.global_position) and old.position.distance_squared_to(resident.position) <= 36.0:
				partner = int(state.partner)
				target = old.position
				kind = "conversation"
	if target.distance_squared_to(resident.position) < .04:
		state.partner = -1
		state.kind = "listening"
		return
	_ray.from = resident.position + Vector3.UP * 1.45
	_ray.to = target + Vector3.UP * 1.45
	_ray.collision_mask = 2 | 16
	queries += 1
	if not crowd.get_world_3d().direct_space_state.intersect_ray(_ray).is_empty():
		state.partner = -1
		state.kind = "listening"
		return
	var heading: Vector3 = target - resident.position
	state.yaw = atan2(heading.x, heading.z)
	state.partner = partner
	state.kind = kind
	selections += 1
	watches += int(kind == "watching_court")

func status() -> Dictionary:
	return {"active": active.size(), "max_active": MAX_ACTIVE, "last_updates": updates,
		"last_queries": queries, "max_updates": maxi(max_updates, updates),
		"max_queries": maxi(max_queries, queries), "selections": selections,
		"court_watches": watches, "turns": turns, "radius": RADIUS}
