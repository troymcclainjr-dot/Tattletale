class_name CityMissions
extends Node3D
## Fictional, local cases. No original-block crime state or coordinates are used.

signal changed
signal notice(text: String)

const CASES := [
	{"id": "lost_satchel", "title": "Lost satchel", "reward": 100},
	{"id": "parcel_report", "title": "The opened parcel", "reward": 150},
	{"id": "dumping", "title": "Keep the sidewalk clear", "reward": 175},
	{"id": "missing_tools", "title": "The missing garden tools", "reward": 125},
	{"id": "torn_notice", "title": "The torn watch notice", "reward": 140},
	{"id": "porch_light", "title": "A light out on the block", "reward": 160},
]
const EXTRA_CONTACTS := {"gardener": "missing_tools", "organizer": "torn_notice", "caretaker": "porch_light"}
const INTERACT_RADIUS := 2.4

var level: Node3D
var npcs: Node3D
var active_id := ""
var stage := 0
var score := 0
var completed_ids: Dictionary = {}
var _steps: Array[Dictionary] = []
var _clue_position := Vector3.ZERO
var _clue: Node3D
var _clue_body: StaticBody3D
var _case_root: Node3D
var _carried: Node3D
var _clue_tag: Label3D
var _cleanup_tag: Label3D
var _effects: Array[Dictionary] = []
var _offer_labels: Dictionary = {}


func setup(owner_level: Node3D, actors: Node3D) -> void:
	level = owner_level
	npcs = actors
	name = "NeighborhoodCases"
	for id in ["resident", "lookout", "gardener", "organizer", "caretaker"]:
		var actor: Node3D = npcs.get_actor(id)
		if actor == null:
			continue
		var label := Label3D.new()
		label.text = "Need a hand?"
		label.position.y = 2.30
		label.font_size = 28
		label.pixel_size = 0.0035
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color("e2ba72")
		label.outline_modulate = Color("16272a")
		label.outline_size = 6
		label.visibility_range_begin = 2.5
		label.visibility_range_end = 18.0
		actor.add_child(label)
		_offer_labels[id] = label

func _available_offers() -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	if npcs == null:
		return offers
	for contact in ["resident", "lookout", "gardener", "organizer", "caretaker"]:
		var id: String = str(EXTRA_CONTACTS.get(contact, "dumping" if contact == "lookout" else ("lost_satchel" if not completed_ids.has("lost_satchel") else "parcel_report")))
		if completed_ids.has(id) or npcs.get_actor(contact) == null:
			continue
		for entry in CASES:
			if entry.id == id:
				offers.append({"id": id, "title": entry.title, "actor_id": contact, "position": npcs.actor_position(contact)})
	return offers

func nearby_offer() -> Dictionary:
	if not active_id.is_empty():
		return {}
	var nearest: Dictionary = {}
	var distance := INF
	for offer in _available_offers():
		var at: Vector3 = offer.position
		var metres: float = level.player.global_position.distance_to(at)
		if metres < distance and _can_interact(at):
			nearest = offer
			distance = metres
	return nearest


func start_case(id: String) -> bool:
	if level == null or npcs == null or completed_ids.has(id):
		return false
	var known := false
	for entry in CASES:
		known = known or entry.id == id
	if not known:
		return false
	var required: Array = ["resident"] if id == "lost_satchel" else (["lookout", "officer"] if id == "dumping" else ["resident", "lookout", "officer"])
	if id == "missing_tools":
		required = ["gardener", "ambient_mailman"]
	elif id == "torn_notice":
		required = ["organizer", "lookout"]
	elif id == "porch_light":
		required = ["caretaker", "officer"]
	for actor_id in required:
		var actor_location: Vector3 = npcs.actor_position(str(actor_id))
		if not actor_location.is_finite():
			notice.emit("A contact for this case is unavailable. Choose another case or keep exploring.")
			return false
	# Find space before replacing a live case, so a placement failure loses no progress.
	var distance := 35.0 if id == "lost_satchel" else (55.0 if id == "parcel_report" else 155.0)
	if id == "missing_tools":
		distance = 88.0
	elif id == "torn_notice":
		distance = 137.0
	elif id == "porch_light":
		distance = 181.0
	var radius := 0.55 if id == "dumping" else (0.42 if id == "parcel_report" else 0.32)
	var placement: Dictionary = {}
	# Dense porch approaches and police beats can fill a whole short block.
	# Search farther along the walk before giving up, keeping exactly the same
	# capsule, pavement, route and stair-clearance requirements at every spot.
	for offset in [0.0, 8.0, -8.0, 16.0, -16.0, 24.0, -24.0, 32.0, -32.0, 48.0, -48.0, 64.0, -64.0, 96.0, -96.0]:
		placement = npcs.find_safe_position(_route_point(distance + offset), radius)
		if bool(placement.get("ok", false)) and _route_distance(placement.position) <= 2.2:
			break
		placement = {}
	if not bool(placement.get("ok", false)):
		notice.emit("This case needs a clear patch of sidewalk. Try another neighborhood case.")
		return false
	cancel_case()
	active_id = id
	_clue_position = placement.position
	_case_root = Node3D.new()
	_case_root.name = "FictionalCase_" + id
	add_child(_case_root)
	_clue = Node3D.new()
	_clue.position = _clue_position
	_case_root.add_child(_clue)
	match id:
		"lost_satchel":
			_steps = [
				_step("resident", "Ask the resident about the missing satchel", "E  Ask about the satchel", "That blue satchel is mine. Look for a brass clasp, then bring it back to me."),
				_step("clue", "Find the blue satchel along Old York Road", "E  Pick up the blue satchel", "Blue fabric, brass clasp. This matches the resident's description."),
				_step("resident", "Return the satchel to its owner", "E  Return the satchel", "That's it! Everything is still inside. Thank you for bringing it back."),
			]
			_satchel(_clue)
			_make_body(Vector3(0.48, 0.43, 0.3), Vector3(0, 0.215, 0))
		"parcel_report":
			_steps = [
				_step("resident", "Ask the resident about an opened delivery", "E  Ask about the delivery", "My delivery is missing. There may be some packing material farther up Old York. Please check before reporting anything."),
				_step("clue", "Inspect the opened parcel on Old York Road", "E  Inspect the packing label", "The empty carton has the resident's delivery label. Record the location; leave the evidence here."),
				_step("lookout", "Ask the witness at Dumbarton what happened", "E  Ask the witness", "I saw someone remove a parcel from that doorstep. I couldn't identify them. Tell the officer exactly that."),
				_step("officer", "Report the evidence to the officer near Wyanoke", "E  File the parcel report", "I'll record the missing delivery and the witness account. We will investigate; a report is not proof of who took it."),
			]
			_parcel(_clue)
			_make_body(Vector3(0.7, 0.38, 0.44), Vector3(0, 0.19, 0))
		"dumping":
			_steps = [
				_step("lookout", "Ask the Dumbarton witness about dumped waste", "E  Ask about the waste", "Someone left bags beside the sidewalk toward Rose Hill. Please record where they are and tell the officer."),
				_step("clue", "Inspect the dumped bags near Rose Hill", "E  Record the dumped waste", "Three dumped bags, beside the walking route. Location and description recorded. Do not open them."),
				_step("officer", "Report the dumped waste to the officer", "E  Request a cleanup", "The location is logged. A cleanup team will remove the bags. Please check that the spot is clear afterward."),
				_step("clue", "Return to Rose Hill and confirm the cleanup", "E  Confirm the cleared site", "The bags are gone and the sidewalk is clear. Cleanup confirmed."),
			]
			_dumped_bags(_clue)
			_make_body(Vector3(0.9, 0.7, 0.6), Vector3(0, 0.35, 0))
		"missing_tools":
			_steps = [
				_step("gardener", "Ask the gardener about the missing tools", "E  Ask about the garden tools", "Our green tool caddy vanished after the planting day. The mail carrier passed here; could you ask what they saw?"),
				_step("ambient_mailman", "Ask the mail carrier where the caddy went", "E  Ask about the green caddy", "A volunteer set a green caddy farther along Old York while carrying a planter. I saw no theft. Check beside the walk."),
				_step("clue", "Recover the green garden caddy along Old York", "E  Recover the garden tools", "The caddy still holds the hand tools, marked for the community garden. Bring it back."),
				_step("gardener", "Return the tools and clear up the misunderstanding", "E  Return the garden tools", "All accounted for! I'm glad we checked instead of accusing somebody. We can finish planting now."),
			]
			_tool_caddy(_clue)
			_make_body(Vector3(0.5, 0.6, 0.32), Vector3(0, 0.3, 0))
		"torn_notice":
			_steps = [
				_step("organizer", "Ask the organizer about the damaged watch notice", "E  Ask about the torn notice", "Our neighborhood watch meeting notice was torn down. Please inspect the pieces, then ask the witness before we report vandalism."),
				_step("clue", "Inspect the torn notice beside the sidewalk", "E  Inspect the notice pieces", "The paper is rain-soaked and split around a rusty fastening. Nothing here identifies a person."),
				_step("lookout", "Ask the Dumbarton witness what happened to the notice", "E  Ask about the fallen notice", "The wind pulled it loose in the rain. I saw it happen. Nobody tore it down."),
				_step("organizer", "Share the evidence and arrange a weatherproof replacement", "E  Resolve the notice report", "Weather damage, then. I'll put up a covered notice. Thanks for checking the facts and keeping the meeting on track."),
			]
			_box(_clue, Vector3(0.55, 0.035, 0.4), Vector3(0, 0.025, 0), "#d7c6a0")
			_box(_clue, Vector3(0.24, 0.045, 0.3), Vector3(0.3, 0.03, 0.08), "#e5d7b5")
			_box(_clue, Vector3(0.3, 0.008, 0.04), Vector3(0, 0.049, 0), "#496372")
			_make_body(Vector3(0.75, 0.05, 0.5), Vector3(0, 0.025, 0))
		"porch_light":
			_steps = [
				_step("caretaker", "Ask the caretaker about the damaged porch light", "E  Ask about the porch light", "I found our porch lantern cracked. I've disconnected it and set it beside the walk. Could you record the damage? The dark entrance worries our neighbors."),
				_step("clue", "Inspect the disconnected lantern near Cator", "E  Record the damaged lantern", "The disconnected lantern has a cracked shade. Record the damage and the dark entrance; the cause is unknown. Leave it for the caretaker."),
				_step("officer", "Report the damage without naming a suspect", "E  Report the damaged light", "I'll record the damage, with the cause unknown. Ask the caretaker to restore the light so the entrance is visible again."),
				_step("caretaker", "Confirm the porch light repair is arranged", "E  Confirm the repair", "The replacement is ready and the repair is scheduled before dark. Thank you for looking out for the block."),
			]
			_box(_clue, Vector3(0.32, 0.08, 0.3), Vector3(0, 0.04, 0), "#343d40")
			_box(_clue, Vector3(0.22, 0.3, 0.2), Vector3(0, 0.23, 0), "#b3aa85")
			_box(_clue, Vector3(0.025, 0.27, 0.22), Vector3(0.03, 0.23, 0), "#3b3831")
			_make_body(Vector3(0.38, 0.42, 0.35), Vector3(0, 0.21, 0))
	var clue_titles := {"lost_satchel": "BLUE SATCHEL", "parcel_report": "OPENED PARCEL", "dumping": "DUMPED BAGS", "missing_tools": "GARDEN TOOL CADDY", "torn_notice": "TORN WATCH NOTICE", "porch_light": "DAMAGED LANTERN"}
	_clue_tag = _tag(_clue, str(clue_titles.get(id, "CLUE")), 0.95)
	_update_clue_tags()
	changed.emit()
	notice.emit("New case: " + _title() + ". Follow the case marker; press E at each step.")
	return true


func cancel_case() -> void:
	if is_instance_valid(_case_root):
		# Disable collision immediately; queue_free completes at the frame boundary.
		if is_instance_valid(_clue_body):
			_clue_body.collision_layer = 0
		_case_root.queue_free()
	_case_root = null
	_clue = null
	_clue_body = null
	_carried = null
	_clue_tag = null
	_cleanup_tag = null
	_steps.clear()
	active_id = ""
	stage = 0
	changed.emit()


func _step(target: String, objective: String, prompt: String, dialogue: String) -> Dictionary:
	return {"target": target, "objective": objective, "prompt": prompt, "dialogue": dialogue}


func get_status() -> Dictionary:
	var catalog: Array[Dictionary] = []
	for entry in CASES:
		catalog.append({"id": entry.id, "title": entry.title, "completed": completed_ids.has(entry.id)})
	var status := {"active_id": active_id, "title": _title(), "objective": "Walk the neighborhood. Talk to people who need a hand.", "prompt": "", "target_position": Vector3.ZERO, "stage": stage, "stage_count": _steps.size(), "completed": completed_ids.size(), "total": CASES.size(), "score": score, "cases": catalog, "offers": _available_offers()}
	if not active_id.is_empty() and stage < _steps.size():
		var target := _target_position()
		status.objective = _steps[stage].objective
		status.target_position = target
		status.prompt = _steps[stage].prompt if _can_interact(target) else ""
	else:
		var offer := nearby_offer()
		status.nearby_offer = offer
		if not offer.is_empty():
			status.prompt = "E  Talk about " + str(offer.title).to_lower()
	return status


func interact() -> bool:
	if active_id.is_empty():
		var offer := nearby_offer()
		if offer.is_empty() or not start_case(str(offer.id)):
			return false
		# The first conversation is the discovery itself, not a menu selection.
		return interact()
	if stage >= _steps.size():
		return false
	var target := _target_position()
	if not _can_interact(target):
		return false
	var action: Dictionary = _steps[stage]
	if str(action.target) != "clue":
		npcs.speak(str(action.target), str(action.dialogue), 6.0)
	notice.emit(str(action.dialogue))
	if (active_id == "lost_satchel" and stage == 1) or (active_id == "missing_tools" and stage == 2):
		_clue.hide()
		_clue_body.collision_layer = 0
		_carried = Node3D.new()
		_case_root.add_child(_carried)
		if active_id == "missing_tools":
			_tool_caddy(_carried)
		else:
			_satchel(_carried)
		_carried.scale = Vector3.ONE * 0.65
		_update_carried()
	elif active_id == "dumping" and stage == 2:
		_clue.hide()
		_clue_body.collision_layer = 0
		var cleared := Node3D.new()
		cleared.position = _clue_position
		_case_root.add_child(cleared)
		_cleanup_tag = _tag(cleared, "CLEANUP COMPLETE\nCHECK THIS SPOT", 0.85)
		_ring(cleared, Color("81c8a0"))
	stage += 1
	_update_clue_tags()
	if stage >= _steps.size():
		_complete(target)
	else:
		changed.emit()
	return true


func _complete(at: Vector3) -> void:
	var finished := active_id
	if completed_ids.has(finished):
		return
	var reward := 0
	for entry in CASES:
		if entry.id == finished:
			reward = int(entry.reward)
	completed_ids[finished] = true
	score += reward
	var message := "PROPERTY RETURNED" if finished == "lost_satchel" else ("REPORT FILED" if finished == "parcel_report" else "SIDEWALK CLEAR")
	if finished == "missing_tools":
		message = "TOOLS RETURNED"
	elif finished == "torn_notice":
		message = "NOTICE MYSTERY RESOLVED"
	elif finished == "porch_light":
		message = "DAMAGE REPORTED · REPAIR ARRANGED"
	var effect := Node3D.new()
	effect.position = at
	add_child(effect)
	_tag(effect, "%s\n+%d community points" % [message, reward], 2.0)
	_ring(effect, Color("81c8a0"))
	_effects.append({"node": effect, "remaining": 5.0})
	cancel_case()
	# Dialogue was emitted above; include the resolution without replacing it with a bare score.
	notice.emit("%s. +%d community points. Keep an eye out for neighbors who need a hand." % [message.capitalize(), reward])


func tick(delta: float) -> void:
	_update_carried()
	var available: Dictionary = {}
	for offer in _available_offers():
		available[str(offer.actor_id)] = true
	for id in _offer_labels:
		_offer_labels[id].visible = active_id.is_empty() and available.has(id)
	for i in range(_effects.size() - 1, -1, -1):
		_effects[i].remaining = float(_effects[i].remaining) - delta
		if float(_effects[i].remaining) <= 0.0:
			_effects[i].node.queue_free()
			_effects.remove_at(i)


func _update_clue_tags() -> void:
	var seeking_clue := not active_id.is_empty() and stage < _steps.size() and str(_steps[stage].target) == "clue"
	if is_instance_valid(_clue_tag):
		_clue_tag.visible = seeking_clue
	if is_instance_valid(_cleanup_tag):
		_cleanup_tag.visible = seeking_clue


func _update_carried() -> void:
	if not is_instance_valid(_carried):
		return
	# Small carried bag remains within the player's existing capsule footprint.
	_carried.global_position = level.player.global_position + Vector3(0, 0.9, -0.12).rotated(Vector3.UP, level.player.yaw)
	_carried.rotation.y = level.player.yaw


func _title() -> String:
	for entry in CASES:
		if entry.id == active_id:
			return str(entry.title)
	return "Neighborhood cases"


func _target_position() -> Vector3:
	var who: String = str(_steps[stage].target)
	return _clue_position if who == "clue" else npcs.actor_position(who)


func _can_interact(target: Vector3) -> bool:
	if not target.is_finite():
		return false
	var here: Vector3 = level.player.global_position
	if Vector2(here.x - target.x, here.z - target.z).length() > INTERACT_RADIUS or absf(here.y - target.y) > 1.5:
		return false
	var exclusions: Array[RID] = [level.player.get_rid()]
	if is_instance_valid(_clue_body):
		exclusions.append(_clue_body.get_rid())
	var end := target + Vector3.UP * 0.85
	var query := PhysicsRayQueryParameters3D.create(here + Vector3.UP * 1.2, end, 2, exclusions)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	# Actors use layer 8. Only obstacles on layer 2 block this ray; no wall tolerance.
	return hit.is_empty()


func _route_point(metres: float) -> Vector3:
	var route: Dictionary = level.level_data.get("route", {})
	var points: Array = route.get("points", [])
	if points.is_empty():
		return level.player.global_position
	var previous: Vector3 = level.vector(points[0])
	var remaining := maxf(0.0, metres)
	for i in range(1, points.size()):
		var next: Vector3 = level.vector(points[i])
		var length := Vector2(next.x - previous.x, next.z - previous.z).length()
		if length > 0.001 and remaining <= length:
			return previous.lerp(next, remaining / length)
		remaining -= length
		previous = next
	return previous


func _route_distance(point: Vector3) -> float:
	var route: Dictionary = level.level_data.get("route", {})
	var points: Array = route.get("points", [])
	var closest := INF
	for i in range(1, points.size()):
		var a: Vector3 = level.vector(points[i - 1])
		var b: Vector3 = level.vector(points[i])
		var flat := Vector2(point.x, point.z)
		closest = minf(closest, flat.distance_to(Geometry2D.get_closest_point_to_segment(flat, Vector2(a.x, a.z), Vector2(b.x, b.z))))
	return closest


func _make_body(size_: Vector3, center: Vector3) -> void:
	_clue_body = StaticBody3D.new()
	_clue_body.name = "SolidCaseClue"
	# Loose rubbish stays inspectable without catching feet, even during a case.
	_clue_body.collision_layer = 0 if active_id in ["parcel_report", "dumping", "torn_notice"] else 2
	_clue_body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size_
	collision.shape = shape
	collision.position = center
	_clue_body.add_child(collision)
	_clue.add_child(_clue_body)


func _box(parent: Node3D, dimensions: Vector3, center: Vector3, color: String) -> MeshInstance3D:
	return Prim.M(Prim.box(dimensions.x, dimensions.y, dimensions.z), ClayLib.clay(color), center.x, center.y, center.z, parent)


func _satchel(parent: Node3D) -> void:
	_box(parent, Vector3(0.44, 0.3, 0.25), Vector3(0, 0.16, 0), "#36568a")
	_box(parent, Vector3(0.46, 0.07, 0.28), Vector3(0, 0.3, 0), "#2a3a6a")
	_box(parent, Vector3(0.075, 0.07, 0.025), Vector3(0, 0.25, 0.15), "#c8a060")
	var handle := Prim.T(0.10, 0.018, ClayLib.clay("#5a3a24"), 0, 0.34, 0, parent, 5, 12)
	handle.scale = Vector3(1.3, 0.65, 1)

func _tool_caddy(parent: Node3D) -> void:
	_box(parent, Vector3(0.46, 0.28, 0.3), Vector3(0, 0.14, 0), "#507746")
	_box(parent, Vector3(0.36, 0.04, 0.08), Vector3(0, 0.43, 0), "#b49b68")
	for x in [-0.14, 0.14]:
		_box(parent, Vector3(0.035, 0.33, 0.035), Vector3(x, 0.35, 0), "#b49b68")
	_box(parent, Vector3(0.1, 0.15, 0.035), Vector3(0.14, 0.54, 0), "#777d7e")


func _parcel(parent: Node3D) -> void:
	_box(parent, Vector3(0.5, 0.27, 0.4), Vector3(0, 0.135, 0), "#b8925a")
	_box(parent, Vector3(0.45, 0.018, 0.35), Vector3(0, 0.279, 0), "#4a3424")
	var flap := _box(parent, Vector3(0.25, 0.025, 0.4), Vector3(-0.22, 0.31, 0), "#c8b080")
	flap.rotation.z = 0.4
	_box(parent, Vector3(0.17, 0.1, 0.013), Vector3(0.07, 0.16, 0.21), "#f4f0e6")
	for y in [0.14, 0.17, 0.19]:
		_box(parent, Vector3(0.12, 0.008, 0.007), Vector3(0.07, y, 0.221), "#3a3a3e")


func _dumped_bags(parent: Node3D) -> void:
	for entry in [Vector3(-0.23, 0.26, 0.04), Vector3(0.21, 0.24, 0.02), Vector3(0, 0.32, -0.14)]:
		var bag := Prim.M(Prim.sph(0.26, 12, 8), ClayLib.clay("#3a4a2a"), entry.x, entry.y, entry.z, parent)
		bag.scale = Vector3(0.95, 1.15, 0.8)
		Prim.M(Prim.cyl(0.035, 0.07, 0.1, 6), ClayLib.clay("#2f4f34"), entry.x, entry.y + 0.3, entry.z, parent)


func _tag(parent: Node3D, text: String, height: float) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = Prim.font("mono")
	label.font_size = 28
	label.pixel_size = 0.0035
	label.modulate = Color("f4f0e6")
	label.position.y = height
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.shaded = false
	label.outline_size = 6
	label.outline_modulate = Color("182a2a")
	label.visibility_range_begin = 4.0
	label.visibility_range_end = 22.0
	parent.add_child(label)
	return label


func _ring(parent: Node3D, color: Color) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.75
	mesh.outer_radius = 0.8
	mesh.rings = 24
	mesh.ring_segments = 6
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	Prim.M(mesh, material, 0, 0.025, 0, parent, false)
