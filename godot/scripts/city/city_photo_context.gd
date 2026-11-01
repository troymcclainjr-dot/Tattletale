extends RefCounted
## Trusted description of one phone exposure: camera pose, game time and the
## identified world subjects actually in frame with line of sight. Built from
## the live world on the main thread at the shutter, never from pixels.
const GROUP := "photo_subjects"
const VERSION := 2
const MAX_SUBJECTS := 24
const MAX_TAGS := 8
const MAX_TAG_LENGTH := 96
## Leave room for camera/time and gallery fields in the 16 KiB sidecar limit.
const MAX_SUBJECT_JSON_BYTES := 10000
const MAX_RAYS := 48
const MAX_CANDIDATES := 512
const DEFAULT_RANGE := 60.0
const MAX_RANGE := 120.0
const FRAME_TOLERANCE := 0.02
const ACTOR_HEIGHT := 1.2
## Tolerance for a subject point that lies on a surface (ground clue, facade).
const SURFACE_EPSILON := 0.15
## Match case evidence: terrain and static scenery occlude, transient people
## and moving cars do not. Parked shells on layer 2 still block the photo.
const STATIC_MASK := 1 | 2

## Bounded subject candidates from named actors, the `photo_subjects` group
## and registered providers. The 1200 ambient crowd and traffic are never
## enumerated per photo; incident/case providers supply known participants.
## Built places are absent: their map point lies inside the building, so
## strict line of sight could only waste rays (the photo records its street).
static func candidates(level: Node, providers: Array[Callable]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	if level != null:
		for owner_name in ["npcs", "residents"]:
			var owner: Variant = level.get(owner_name)
			if is_instance_valid(owner) and owner.get("actors") is Dictionary:
				var actors: Dictionary = owner.get("actors")
				for id in actors:
					_add_actor(result, seen, str(id), actors[id])
		if level.is_inside_tree():
			for node in level.get_tree().get_nodes_in_group(GROUP):
				_add_group_node(result, seen, node)
	for provider in providers:
		if not provider.is_valid():
			continue
		var supplied: Variant = provider.call()
		if not supplied is Array:
			continue
		for entry in supplied:
			if entry is Dictionary:
				_add(result, seen, entry, true)
	return result

static func _add_actor(result: Array[Dictionary], seen: Dictionary, id: String, actor: Variant) -> void:
	if not is_instance_valid(actor) or not actor is Node3D or not actor.is_inside_tree() or not actor.is_visible_in_tree():
		return
	if actor.get_meta("police_custody", false) or actor.get_meta("police_custody_completed", false):
		return
	var tags: Array = []
	if actor.get_meta("city_dead", false):
		tags.append("down")
	var label: Variant = actor.get("display_name")
	_add(result, seen, {"id": id, "kind": "actor", "label": str(label) if label != null else id,
		"position": actor.global_position + Vector3.UP * ACTOR_HEIGHT, "radius": 0.6,
		"node": actor, "tags": tags})

static func _add_group_node(result: Array[Dictionary], seen: Dictionary, node: Node) -> void:
	if not node is Node3D or not node.is_visible_in_tree():
		return
	var entry: Dictionary = {}
	if node.has_method("get_photo_subject"):
		var supplied: Variant = node.call("get_photo_subject")
		if not supplied is Dictionary:
			return
		entry = supplied.duplicate()
	entry["id"] = str(entry.get("id", node.get_meta("photo_subject_id", node.name)))
	entry["kind"] = str(entry.get("kind", node.get_meta("photo_subject_kind", "object")))
	entry["label"] = str(entry.get("label", node.get_meta("photo_subject_label", node.name)))
	entry["position"] = entry.get("position", node.global_position)
	entry["radius"] = float(entry.get("radius", node.get_meta("photo_subject_radius", 0.6)))
	entry["tags"] = entry.get("tags", node.get_meta("photo_subject_tags", []))
	entry["node"] = node
	_add(result, seen, entry, true)

static func _add(result: Array[Dictionary], seen: Dictionary, entry: Dictionary, prioritize_tags: bool = false) -> void:
	var id := str(entry.get("id", ""))
	var kind := str(entry.get("kind", "object"))
	var position: Variant = entry.get("position")
	if id.is_empty() or not position is Vector3 or not position.is_finite():
		return
	var key := kind + ":" + id
	if seen.has(key):
		var existing: Dictionary = result[int(seen[key])]
		var first: Array = _tags(entry.get("tags", [])) if prioritize_tags else _tags(existing.get("tags", []))
		var second: Array = _tags(existing.get("tags", [])) if prioritize_tags else _tags(entry.get("tags", []))
		existing["tags"] = _tags(first + second)
		# Enrichment must not replace the live actor's position or collider.
		existing["max_distance"] = maxf(_reach(existing), _reach(entry))
		return
	if result.size() >= MAX_CANDIDATES:
		return
	seen[key] = result.size()
	var copy := entry.duplicate()
	copy.id = id
	copy.kind = kind
	copy.tags = _tags(entry.get("tags", []))
	copy.max_distance = _reach(entry)
	result.append(copy)

static func _reach(entry: Dictionary) -> float:
	var distance := float(entry.get("max_distance", DEFAULT_RANGE))
	return clampf(distance, 1.0, MAX_RANGE) if is_finite(distance) else DEFAULT_RANGE

## Subjects visible from `camera`, nearest first. `exclude` holds body RIDs
## that never occlude (the photographer).
static func visible_subjects(camera: Camera3D, frame_size: Vector2, entries: Array[Dictionary], exclude: Array[RID]) -> Dictionary:
	var eye := camera.global_position
	var framed: Array[Dictionary] = []
	for entry in entries:
		var point: Vector3 = entry.position
		var distance := eye.distance_to(point)
		var reach := _reach(entry)
		if distance < 0.2 or distance > reach or camera.is_position_behind(point):
			continue
		var screen := camera.unproject_position(point) / frame_size
		if screen.x < -FRAME_TOLERANCE or screen.y < -FRAME_TOLERANCE or screen.x > 1.0 + FRAME_TOLERANCE or screen.y > 1.0 + FRAME_TOLERANCE:
			continue
		var framed_entry := entry.duplicate()
		framed_entry.distance = distance
		framed_entry.screen = screen
		framed.append(framed_entry)
	framed.sort_custom(func(a: Dictionary, b: Dictionary): return a.distance < b.distance)
	var space: PhysicsDirectSpaceState3D = null
	if camera.is_inside_tree():
		space = camera.get_world_3d().direct_space_state
	var subjects: Array[Dictionary] = []
	var subject_json_bytes := 2 # The JSON array's brackets.
	var rays := 0
	for entry in framed:
		if subjects.size() >= MAX_SUBJECTS or rays >= MAX_RAYS:
			break
		var clear := true
		if space != null:
			rays += 1
			var query := PhysicsRayQueryParameters3D.create(eye, entry.position, STATIC_MASK)
			query.exclude = exclude
			var hit := space.intersect_ray(query)
			clear = hit.is_empty() or _hit_is_subject(hit, entry)
		if not clear:
			continue
		var screen: Vector2 = entry.screen
		var subject := {"id": entry.id, "kind": entry.kind, "label": str(entry.get("label", entry.id)).left(64),
			"position": entry.position, "distance": entry.distance, "screen": screen,
			"centrality": 1.0 - clampf(maxf(absf(screen.x - 0.5), absf(screen.y - 0.5)) * 2.0, 0.0, 1.0),
			"line_of_sight": true, "tags": _tags(entry.get("tags", []))}
		subject_json_bytes = _append_subject(subjects, subject, subject_json_bytes)
	return {"subjects": subjects, "subjects_considered": framed.size(), "rays_cast": rays}

## Skip an oversized subject intact rather than silently changing evidence tags.
static func _append_subject(subjects: Array[Dictionary], subject: Dictionary, used_bytes: int) -> int:
	if subjects.size() >= MAX_SUBJECTS:
		return used_bytes
	var bytes := JSON.stringify(json_safe(subject)).to_utf8_buffer().size()
	var total := used_bytes + bytes + (0 if subjects.is_empty() else 1)
	if total > MAX_SUBJECT_JSON_BYTES:
		return used_bytes
	subjects.append(subject)
	return total

## Strict line of sight: the first hit is the subject's own collider, or the
## line is clear up to a point lying on a surface. A wall near the subject is
## never accepted, whatever the subject's framing radius.
static func _hit_is_subject(hit: Dictionary, entry: Dictionary) -> bool:
	var collider: Variant = hit.get("collider")
	for owner_key in ["collider", "node"]:
		var owner: Variant = entry.get(owner_key)
		if is_instance_valid(owner) and owner is Node and is_instance_valid(collider) and collider is Node and (collider == owner or owner.is_ancestor_of(collider)):
			return true
	return (hit.position as Vector3).distance_to(entry.position) <= SURFACE_EPSILON

static func _tags(value: Variant) -> Array:
	var result: Array = []
	if value is Array:
		for tag in value:
			if result.size() >= MAX_TAGS:
				break
			# Tags are exact identifiers. Never truncate one into a different tag.
			if tag is String and not tag.is_empty() and tag.length() <= MAX_TAG_LENGTH and not result.has(tag):
				result.append(tag)
	return result

## Converts vectors to arrays for the gallery's JSON sidecar.
static func json_safe(value: Variant) -> Variant:
	if value is Vector3:
		return [value.x, value.y, value.z]
	if value is Vector2:
		return [value.x, value.y]
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			if key != "node" and key != "collider":
				result[str(key)] = json_safe(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(json_safe(item))
		return result
	if value is Object:
		return null
	return value
