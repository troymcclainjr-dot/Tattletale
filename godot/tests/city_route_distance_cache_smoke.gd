extends SceneTree
## Semantic comparisons with the original uncached planar summation. No world
## setup or traffic spawning is needed; a node in-tree supplies route_position.
var failures := 0
var passes := 0
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool,label: String) -> void:
	failures += int(not ok)
	passes += int(ok)
	print("[route_distance_cache] %s %s"%["PASS" if ok else "FAIL",label])
func original(car: Node3D) -> float:
	if car.route_index >= car.route.size():
		return 0.0
	var at: Vector3 = car.route_position()
	var target: Vector3 = car.route[car.route_index]
	var result := Vector2(target.x-at.x,target.z-at.z).length()
	for i in range(car.route_index+1,car.route.size()):
		var a: Vector3 = car.route[i-1]
		var b: Vector3 = car.route[i]
		result += Vector2(b.x-a.x,b.z-a.z).length()
	return result
func matches(car: Node3D) -> bool:
	var actual: float = car.remaining_route_distance()
	var expected := original(car)
	return absf(actual-expected) <= maxf(.000001,absf(expected)*.000000001)
func _run() -> void:
	var script: Script = load("res://scripts/city/city_vehicle.gd")
	if script == null or not script.can_instantiate():
		quit(1)
		return
	var car: Node3D = script.new()
	root.add_child(car)
	script.use_route_distance_cache = true
	car.route_index = 0
	check(matches(car),"empty route has zero remaining distance")
	var single: Array[Vector3] = [Vector3(3,50,4)]
	car.route = single
	check(matches(car) and is_equal_approx(car.remaining_route_distance(),5.0),"single-point route uses planar current distance")
	car.route_index = 1
	check(matches(car),"completed route stays zero")
	var random := RandomNumberGenerator.new()
	random.seed = 731912
	var route: Array[Vector3] = []
	for i in 96:
		route.append(Vector3(random.randf_range(-100,100),random.randf_range(-40,40),random.randf_range(-100,100)))
		if i%9==0:
			route.append(route[-1])
	car.route = route
	var equal := true
	for index in range(route.size()+2):
		car.route_index = index
		car.position = Vector3(random.randf_range(-120,120),random.randf_range(-50,50),random.randf_range(-120,120))
		equal = equal and matches(car)
	check(equal,"all route cursors match original sum across slopes, bends and duplicate points")
	var builds: int = car._route_distance_cache_builds
	for i in 50:
		car.route_index = 1+i%40
		car.position.x += .15
		equal = equal and matches(car)
	check(equal and car._route_distance_cache_builds==builds,"movement and cursor advances reuse the same suffix cache")
	var flats: Array[int] = [0]
	car.flat_tires = flats
	car._route_position = Vector3(-22,14,31)
	check(matches(car),"damaged car distance follows logical route anchor")
	car.flat_tires.clear()
	var replacement: Array[Vector3] = route.duplicate()
	replacement[20] += Vector3(13,8,19)
	car.route_index = 1
	car.route = replacement
	check(matches(car) and car._route_distance_cache_builds==builds+1,"same-size route assignment invalidates through setter")
	var alias: Array[Vector3] = car.route
	builds = car._route_distance_cache_builds
	alias.append(Vector3(8,14,180))
	check(matches(car) and car._route_distance_cache_builds==builds+1,"traffic-style alias append rebuilds automatically on size change")
	builds = car._route_distance_cache_builds
	alias.remove_at(30)
	check(matches(car) and car._route_distance_cache_builds==builds+1,"alias removal rebuilds automatically")
	builds = car._route_distance_cache_builds
	alias[12] += Vector3(40,-10,12)
	car.invalidate_route_distance_cache()
	check(matches(car) and car._route_distance_cache_builds==builds+1,"explicit invalidation handles same-size in-place element edits")
	builds = car._route_distance_cache_builds
	script.use_route_distance_cache = false
	equal = true
	for index in range(car.route.size()):
		car.route_index = index
		equal = equal and matches(car)
	check(equal and car._route_distance_cache_builds==builds,"benchmark switch executes original sum without rebuilding cache")
	script.use_route_distance_cache = true
	car.route_index = 1
	var compact: Array[Vector3] = []
	compact.assign(car.route.slice(20))
	car.route = compact
	check(matches(car),"junction route compaction is invalidated by assignment")
	car.route.clear()
	car.route_index = 0
	check(matches(car),"clearing an aliased route remains safe")
	car.queue_free()
	await process_frame
	print("[route_distance_cache] %d passed; %d failed"%[passes,failures])
	quit(0 if failures==0 else 1)
