extends Node
## Real imported-deck support, crowd budget, walk discovery and one-time resolutions.
var passes := 0
var fails := 0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passes += 1
	else:
		fails += 1
	print("[city_expansion] %s %s" % ["PASS" if ok else "FAIL", label])

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn")
	await frames(4)
	var level: Node = get_tree().current_scene
	for i in 600:
		if level != null and level.get("level_ready") == true:
			break
		await frames(1)
		level = get_tree().current_scene
	if level == null or level.get("level_ready") != true:
		check(false, "expanded neighborhood initializes")
		_finish()
		return
	level.pause_exploring()
	var crowd = level.npcs.crowd
	var status: Dictionary = crowd.get_status()
	print("[city_expansion] crowd ", status)
	check(int(status.total) >= 1150, "whole-level population reaches roughly five times the prior 240 residents")
	check(int(status.social) - int(status.park) >= 800, "street population is at least five times the prior 160")
	check(int(status.park) >= 24 and int(status.park) <= 80, "parks retain visitors without concentrating the street population")
	check(int(status.walkers) >= 100, "over one hundred ambient residents have validated walking routes")
	check(int(level.npcs.get_status().foot_patrols) == 6, "all six police have actual sidewalk patrol routes")
	check(int(status.porch) >= 32, "residents inhabit actual raised porches across the neighborhood")
	check(int(status.social) >= 12, "social groups populate sidewalk edges")
	check(int(status.circle_groups) >= 12, "neighbors gather in inward-facing circles")
	check(int(status.seated) >= 16, "porch residents sit in chairs")
	check(float(status.span_x) > 500.0 and float(status.span_z) > 350.0, "population spans the whole mapped neighborhood")
	check(int(status.far_from_intro_route) >= 70 and int(status.occupied_cells) >= 35, "population extends well beyond the introductory walk")
	check(int(status.draw_batches) < int(status.total), "residents share spatial draw batches")
	check(int(status.shared_meshes) <= 3, "standing, porch and bench poses use a bounded shared mesh set")
	var supported := true
	var clear_routes := true
	var clear_stairs := true
	for resident in crowd.residents:
		var at: Vector3 = resident.position
		var mask := 2 if resident.activity == "porch" else 1
		var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.1, at - Vector3.UP * 0.1, mask)
		var hit: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(ray)
		supported = supported and not hit.is_empty()
		clear_routes = clear_routes and level.npcs._route_distance(at) >= 0.8
		clear_stairs = clear_stairs and level.npcs.stair_approach_clear(at, 0.88)
	check(supported, "every resident's feet touch their deck or terrain")
	check(clear_routes, "crowd leaves the authored walking route clear")
	check(clear_stairs, "dense crowd reserves porch stair approaches and landings")
	var inward := true
	for group in crowd._circle_groups:
		for index in group.indices:
			var resident: Dictionary = crowd.residents[index]
			var toward: Vector3 = group.center - resident.position
			toward.y = 0.0
			var facing := Vector3(sin(float(resident.yaw)), 0, cos(float(resident.yaw)))
			inward = inward and facing.dot(toward.normalized()) > 0.95
	check(inward, "circle members face their group center")
	var no_names := true
	for actor in level.npcs.actors.values():
		for label in actor.find_children("*", "Label3D", true, false):
			no_names = no_names and label.text != actor.display_name
	check(no_names, "no contact or walker has an overhead name")
	var before: float = crowd._clock
	await frames(8)
	check(crowd._clock == before, "pause freezes ambient residents")
	var original: Vector3 = level.player.global_position
	if not crowd._walkers.is_empty():
		var walker: Dictionary = crowd.residents[crowd._walkers[0]]
		var before_walk: Vector3 = walker.position
		level.player.global_position = before_walk + Vector3(4, 0, 0)
		crowd.set_presence(level.player.global_position, 55.0, 180.0)
		for i in 30:
			crowd.tick(0.05)
		check(walker.position.distance_to(before_walk) > 0.8, "nearby batched walkers travel rather than only rotating in place")
		check(walker.body.position.distance_to(walker.position) < 0.001, "walking resident collision follows the visible person")
		var forward: Vector3 = (walker.walk_b - walker.walk_a).normalized() * float(walker.walk_direction)
		var blocker := StaticBody3D.new()
		blocker.collision_layer = 8
		blocker.collision_mask = 0
		var capsule := CollisionShape3D.new()
		var shape := CapsuleShape3D.new()
		shape.radius = 0.28
		shape.height = 1.7
		capsule.shape = shape
		capsule.position.y = 0.9
		blocker.add_child(capsule)
		blocker.position = walker.position + forward * 0.9
		level.add_child(blocker)
		await frames(2)
		var closest := INF
		for i in 30:
			crowd.tick(0.05)
			closest = minf(closest, walker.position.distance_to(blocker.position))
		check(closest >= 0.5, "batched walkers yield to actors entering their corridor after placement")
		blocker.queue_free()
		await frames(2)
	level.player.global_position = Vector3(600, 0, 350)
	crowd.tick(0.3)
	check(int(crowd.get_status().near_updates) == 0, "distant residents require no pose updates")
	level.player.global_position = original
	var streaming = level.get("streaming")
	if streaming != null:
		streaming.set_process(false)
	var saved_count: int = crowd.residents.size()
	crowd.set_presence(Vector3(2000, 0, 2000), 55.0, 180.0)
	await frames(2)
	check(int(crowd.get_status().active_cells) == 0 and crowd.residents.size() == saved_count, "far crowd nodes unload while population records survive")
	crowd.set_presence(original, 55.0, 180.0)
	await frames(2)
	check(int(crowd.get_status().active_cells) > 0 and int(crowd.get_status().active_cells) < int(status.occupied_cells), "nearby crowd reloads without spawning the whole level")
	await _check_details(level)
	if streaming != null:
		streaming.set_process(true)
	check(level.missions.get_status().total == 6, "six distinct neighborhood cases")
	for contact in ["gardener", "organizer", "caretaker"]:
		var actor: Node3D = level.npcs.get_actor(contact)
		check(actor != null, "new case contact exists: " + contact)
		if actor == null:
			continue
		var id: String = str(level.missions.EXTRA_CONTACTS[contact])
		var previous_score: int = level.missions.score
		_approach(level, actor.global_position)
		var offer: Dictionary = level.missions.nearby_offer()
		check(str(offer.get("id", "")) == id, "case is discovered by walking to " + contact)
		var before_preview: String = str(level.missions.active_id)
		var preview: Dictionary = level.missions.conversation_preview()
		check(str(level.missions.active_id) == before_preview and level.missions.score == previous_score,
			"conversation preview does not accept or reward " + id)
		var start_node: Dictionary = preview.get("nodes", {}).get(str(preview.get("start", "")), {})
		var accept_hook: Dictionary = {}
		for choice in start_node.get("choices", []):
			var hook: Dictionary = choice.get("hook", {})
			if str(hook.get("kind", "")) == "start_case" and str(hook.get("id", "")) == id:
				accept_hook = hook
				break
		check(not accept_hook.is_empty() and level.missions.commit_dialogue_action(accept_hook)
			and str(level.missions.active_id) == id, "explicit conversation choice accepts " + id)
		var advanced := true
		for step in 8:
			var state: Dictionary = level.missions.get_status()
			if str(state.active_id).is_empty():
				break
			_approach(level, state.target_position)
			if not level.missions.interact():
				advanced = false
				break
			await frames(1)
		check(advanced and level.missions.completed_ids.has(id), "ordered evidence and resolution complete: " + id)
		check(level.missions.score > previous_score, "resolution awards community points: " + id)
		var earned: int = level.missions.score
		check(not level.missions.start_case(id) and level.missions.score == earned, "completed case cannot reward twice: " + id)
		level.missions.cancel_case()
	_finish()

func _check_details(level: Node) -> void:
	var details = level.get("neighborhood_details")
	check(details != null, "whole-neighborhood details initialize")
	if details == null:
		return
	var status: Dictionary = details.get_status()
	print("[city_expansion] details ", status)
	var counts: Dictionary = status.counts
	check(int(counts.get("business", 0)) >= 9, "fictional business functions have readable facade signs")
	check(int(counts.get("mailbox", 0)) + int(counts.get("postal_drop", 0)) >= 24 and int(counts.get("postal_drop", 0)) >= 6, "mailboxes and postal drop boxes are distributed across blocks")
	check(int(counts.get("road_dot", 0)) >= 500 and int(counts.get("pothole", 0)) >= 10 and int(status.crossings) >= 6, "worn yellow dots, occasional potholes and crosswalks populate roads")
	check(int(status.cells) >= 35 and int(status.shared_meshes) <= 4, "street details and hydrants share a bounded mesh set across geographic cells")
	check(int(counts.get("shop_window", 0)) == 0 and int(counts.get("shopfront_trim", 0)) == 0 and level.level_data.get("businesses", []).size() >= 18, "businesses use constructed building facades instead of runtime overlays")
	var clear := true
	var supported := true
	var entrances_clear := true
	var business_cells: Dictionary = {}
	for record in details.records:
		if record.kind == "business":
			business_cells[details._cell(record.position)] = true
			var normal: Vector3 = record.normal
			var ray := PhysicsRayQueryParameters3D.create(record.position + normal * 0.02, record.position - normal * 0.15, 2)
			supported = supported and not level.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
			entrances_clear = entrances_clear and str(record.mesh).is_empty()
		elif record.kind in ["mailbox", "postal_drop"]:
			clear = clear and level.npcs._route_distance(record.position) >= 0.89
	check(supported and business_cells.size() >= 9, "business signs attach to real facades in separate cells")
	check(entrances_clear, "runtime business records contain text only, with no overlaid building geometry")
	var approaches := true
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.7
	for business in level.level_data.get("businesses", []):
		var normal: Vector3 = level.vector(business.normal)
		var door: Vector3 = level.vector(business.door_position)
		var at: Vector3 = door + normal * 1.2
		# New raised corner-store landings belong to architectural collision layer2.
		# Probe below their canopy, at the authored door's floor height.
		var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.65, at - Vector3.UP * 3.0, 1 | 2)
		var ground: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(ray)
		if ground.is_empty():
			approaches = false
			continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(Basis.IDENTITY, ground.position + Vector3.UP * 1.0)
		query.collision_mask = 2
		approaches = approaches and level.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
	check(approaches, "all constructed commercial doors have clear full-height approaches")
	check(clear, "postal fixtures leave the authored walking route clear")
	var count: int = details.records.size()
	details.set_presence(Vector3(2000, 0, 2000), 55.0, 180.0)
	await frames(2)
	check(int(details.get_status().active_cells) == 0 and details.records.size() == count, "far street detail nodes unload without losing data")
	details.set_presence(level.player.global_position, 55.0, 180.0)
	await frames(2)
	check(int(details.get_status().active_postal_colliders) > 0, "nearby postal fixtures regain physical collision after reload")

func _approach(level: Node, target: Vector3) -> void:
	for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
		level._place_player(target + Vector3(sin(angle), 0, cos(angle)) * 1.65, angle + PI)
		if level.missions._can_interact(target):
			return

func _finish() -> void:
	print("[city_expansion] %d passed, %d failed" % [passes, fails])
	get_tree().quit(0 if fails == 0 else 1)
