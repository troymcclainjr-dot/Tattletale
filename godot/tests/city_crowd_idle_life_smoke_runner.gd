extends Node
const Crowd := preload("res://scripts/city/city_crowd.gd")
const Life := preload("res://scripts/city/city_crowd_idle_life.gd")
const People := preload("res://scripts/city/city_modular_people.gd")
class Level extends Node3D:
	var player: Node3D
	var civic_district: Node
class Neighbors extends Node3D:
	func _street_info(_at: Vector3) -> Dictionary:
		return {"distance": 50.0, "width": 9.5}
	func _route_distance(_at: Vector3) -> float:
		return 100.0
var failures := 0
func _ready() -> void:
	_run.call_deferred()
func check(ok: bool, label: String) -> void:
	failures += int(not ok)
	print("[crowd_idle_life] %s %s" % ["PASS" if ok else "FAIL", label])
func _box(at: Vector3, size: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = layer
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	return body
func _run() -> void:
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	var modes := {1: 0, 2: 0, 3: 0}
	for index in 1200:
		modes[Life.activity_for(index)] += 1
		if index < 3:
			check(Life.phase_for(index) >= 0.0 and Life.phase_for(index) < 1.0, "phase bounded %d" % index)
	check(modes[1] > 800 and modes[2] > 100 and modes[3] > 100, "deterministic mix includes subtle idle, smoking and bagged-bottle drinking")
	var resident := {"pose": 0, "activity": "social"}
	check(Life.owns_idle(resident), "standing social resident can idle")
	for flag in ["dead", "combat_controlled", "panic", "police_custody", "bicycle_avoiding", "identity_unplaced"]:
		resident[flag] = true
		check(not Life.owns_idle(resident), "idle yields ownership: " + flag)
		resident.erase(flag)
	resident.bicycle_rejoin = Vector3.ZERO
	check(not Life.owns_idle(resident), "idle cannot steal bicycle rejoin")
	resident.erase("bicycle_rejoin")
	resident.pose = 1
	check(not Life.owns_idle(resident), "seated poses untouched")
	resident.pose = 0
	resident.activity = "porch"
	check(not Life.owns_idle(resident), "porch ownership untouched")
	resident.activity = "walking"
	check(not Life.owns_idle(resident), "authored walker ownership untouched")
	var standing := People.crowd_mesh(false)
	var seated := People.crowd_mesh(true)
	var standing_arrays := standing.surface_get_arrays(0)
	var seated_arrays := seated.surface_get_arrays(0)
	var props := {50: 0, 51: 0}
	for value in standing_arrays[Mesh.ARRAY_TEX_UV2]:
		if props.has(roundi(value.x)):
			props[roundi(value.x)] += 1
	var seat_props := false
	for value in seated_arrays[Mesh.ARRAY_TEX_UV2]:
		seat_props = seat_props or roundi(value.x) in [50, 51]
	check(standing.get_surface_count() == 1 and seated.get_surface_count() == 1 and props[50] > 0 and props[51] > 0 and not seat_props, "props share standing surface and never enter seated mesh")
	check(standing.get_meta("lod_triangles")[1] < 900, "existing far geometry budget remains bounded")
	_box(Vector3(10, -.25, 10), Vector3(80,.5,80), 1)
	var level := Level.new()
	add_child(level)
	level.player = Node3D.new()
	level.add_child(level.player)
	level.player.position = Vector3(10,0,10)
	var neighbors := Neighbors.new()
	level.add_child(neighbors)
	var crowd := Crowd.new()
	level.add_child(crowd)
	crowd.level = level
	crowd.npcs = neighbors
	crowd._shape = CapsuleShape3D.new()
	crowd._shape.radius = .24
	crowd._shape.height = 1.65
	crowd._meshes = [standing, seated, People.crowd_mesh(true, false)]
	for index in 72:
		crowd._add_resident(Vector3((index % 8) * 3.0, .012, floori(float(index) / 8.0) * 3.0), 0.0, "social", false)
	crowd._build_batches()
	await get_tree().physics_frame
	var life = crowd._idle_life
	for index in [5,16,27,38,49,60,71]:
		crowd._clock += 1.6
		life.tick(crowd)
		life.consider(crowd, index)
	check(life.pacers.size() == Life.MAX_PACERS, "checked pace promotions stop at six nearby people")
	check(life.max_tick_queries <= 11, "route planning and movement share an eleven-query tick ceiling")
	var protected := 5
	var was_pacing: bool = life.pacers.has(protected)
	crowd.residents[protected].combat_controlled = true
	var protected_at: Vector3 = crowd.residents[protected].position
	life.tick(crowd)
	check(was_pacing and not life.pacers.has(protected) and crowd.residents[protected].position == protected_at, "combat interruption releases active pacing without teleporting")
	var bounded := true
	for step in 90:
		crowd._clock += .1
		life.tick(crowd)
		bounded = bounded and life.last_tick_moves <= Life.MAX_MOVES_PER_TICK and life.last_tick_queries <= 6
		await get_tree().physics_frame
	check(bounded and life.moves > 0, "actual physics pacing moves people with two-update/six-query tick cap")
	var life_blocked := Life.new()
	var candidate := 71
	var before: Vector3 = crowd.residents[candidate].position
	crowd.residents[candidate].erase("idle_pace_after")
	_box(before + Vector3(-.5,.9,0), Vector3(.3,1.8,.7), 2)
	await get_tree().physics_frame
	crowd._clock += 2.0
	life_blocked.consider(crowd, candidate)
	check(life_blocked.pacers.is_empty() and crowd.residents[candidate].position == before, "blocked pacing path refuses motion instead of crossing obstacle")
	check(crowd.residents.size() == 72 and crowd._meshes.size() == 3, "idle life preserves resident count and shared pose count")
	print("[crowd_idle_life] metrics=", life.status(), " failures=", failures)
	get_tree().quit(1 if failures else 0)
