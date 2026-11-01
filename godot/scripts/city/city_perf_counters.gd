extends RefCounted
## Opt-in benchmark counters for production hot paths. Inert unless the
## benchmark driver sets `enabled`; a guarded hook then costs one static read:
##     if PerfCounters.enabled: PerfCounters.add(PerfCounters.TRAFFIC_ON_ROAD)
##     var began := PerfCounters.begin() if PerfCounters.enabled else 0
##     ...
##     if PerfCounters.enabled: PerfCounters.end(PerfCounters.VEHICLE_POSE_CLEAR, began)
## No class_name: consumers preload this script, so no global class cache refresh.
## Fixed IDs keep enabled hooks to packed-array writes. Rare or experimental
## sites may use add_named()/end_named() instead (a Dictionary update each call).

const TRAFFIC_ON_ROAD := 0
const TRAFFIC_LEADERS := 1
const TRAFFIC_CONTROL := 2
const TRAFFIC_EXIT_CLEAR := 3
const TRAFFIC_PRESENCE := 4
const VEHICLE_TICK_NEAR := 5
const VEHICLE_TICK_FAR := 6
const VEHICLE_POSE_CLEAR := 7
const VEHICLE_GROUND_POSE := 8
const VEHICLE_CAST := 9
const VEHICLE_ROTATION_SAMPLE := 10
const VEHICLE_SHAPE_QUERY := 11
const VEHICLE_RAY_QUERY := 12
const VEHICLE_ADVANCE_ROUTE := 13
const VEHICLE_TRANSFORM_COMMIT := 14
const LEVEL_UI_UPDATE := 15
const LEVEL_NEAREST_STREET := 16
const LAW_TICK := 17
const LAW_LOS_RAY := 18
const COMBAT_TICK := 19
const COMBAT_SCAN := 20
const NPC_TICK := 21
const NPC_QUERY := 22
const RESIDENT_TICK := 23
const DRIVING_TICK := 24
const PROGRESSION_TICK := 25
const SHOP_TICK := 26
const POLICE_CRUISER_TICK := 27
const POLICE_ROUTE_QUERY := 28
const MINIMAP_REDRAW := 29
const STATUS_SNAPSHOT := 30
const COUNT := 31
const NAMES: Array[String] = ["traffic_on_road", "traffic_leaders", "traffic_control", "traffic_exit_clear",
	"traffic_presence", "vehicle_tick_near", "vehicle_tick_far", "vehicle_pose_clear", "vehicle_ground_pose",
	"vehicle_cast", "vehicle_rotation_sample", "vehicle_shape_query", "vehicle_ray_query", "vehicle_advance_route",
	"vehicle_transform_commit", "level_ui_update", "level_nearest_street", "law_tick", "law_los_ray", "combat_tick",
	"combat_scan", "npc_tick", "npc_query", "resident_tick", "driving_tick", "progression_tick", "shop_tick",
	"police_cruiser_tick", "police_route_query", "minimap_redraw", "status_snapshot"]

static var enabled := false
# Arrays share one buffer. A static PackedInt64Array would be copied on every
# indexed write (temporary reference + copy-on-write), defeating the low cost.
static var counts: Array[int] = []
static var usec: Array[int] = []
static var max_usec: Array[int] = []
static var named: Dictionary = {}

static func _static_init() -> void:
	reset()

## Zero every counter. The driver calls this immediately before a sample.
static func reset() -> void:
	counts.resize(COUNT)
	usec.resize(COUNT)
	max_usec.resize(COUNT)
	counts.fill(0)
	usec.fill(0)
	max_usec.fill(0)
	named.clear()

## Count events (calls, queries, samples) without timing them.
static func add(id: int, amount := 1) -> void:
	counts[id] += amount

## Start a timed region. Pair with end(); nested regions are inclusive.
static func begin() -> int:
	return Time.get_ticks_usec()

## Close a timed region: one call, its microseconds and the worst single call.
static func end(id: int, began: int) -> void:
	var elapsed := Time.get_ticks_usec() - began
	counts[id] += 1
	usec[id] += elapsed
	if elapsed > max_usec[id]:
		max_usec[id] = elapsed

static func add_named(key: String, amount := 1) -> void:
	var entry: Dictionary = named.get(key, {})
	if entry.is_empty():
		entry = {"count": 0, "usec": 0, "max_usec": 0}
		named[key] = entry
	entry.count = int(entry.count) + amount

static func end_named(key: String, began: int) -> void:
	var elapsed := Time.get_ticks_usec() - began
	var entry: Dictionary = named.get(key, {})
	if entry.is_empty():
		entry = {"count": 0, "usec": 0, "max_usec": 0}
		named[key] = entry
	entry.count = int(entry.count) + 1
	entry.usec = int(entry.usec) + elapsed
	entry.max_usec = maxi(int(entry.max_usec), elapsed)

## Non-zero counters keyed by name. Timed entries carry usec/max_usec; pure
## counts report zero time. Divide by the sample duration for per-second rates.
static func snapshot() -> Dictionary:
	var result := {}
	for id in mini(COUNT, counts.size()):
		if counts[id] != 0 or usec[id] != 0:
			result[NAMES[id]] = {"count": counts[id], "usec": usec[id], "max_usec": max_usec[id]}
	for key in named:
		result["named:" + str(key)] = (named[key] as Dictionary).duplicate()
	return result
