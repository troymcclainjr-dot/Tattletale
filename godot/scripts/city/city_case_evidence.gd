extends RefCounted
## Photo evidence: what one trusted phone exposure actually showed. Pure math
## plus physics ray queries supplied by the caller; it never opens the gallery
## image or its JSON. A subject counts only when the phone listed it with line
## of sight at shutter time (phone-map-contract §1, context version 2) AND the
## live world agrees: the subject is still where the phone tested it, that
## point is inside the frame from the recorded pose, within the objective's
## distance band and framing, and a ray from the lens reaches it with nothing
## static in between. Strict: a wall a few centimetres in front of the subject
## blocks it; only the subject's own collider may end the ray. A context with
## no subject list (gallery metadata version 1, fixtures) is evaluated from the
## pose against the live subject alone.

const SOURCE := "phone_camera"
## Slightly looser than the phone's 5 % frame margin so its own listings agree.
const FRAME_MARGIN := 0.04
const LIVE_TOLERANCE := 2.5
## Ground/floors (1) and walls, fences, hedges, parked shells (2). People and
## moving cars do not hide a subject.
const STATIC_MASK := 1 | 2
const NEAR := 0.05
const MAX_SUBJECTS := 48
const REASONS := {"not_in_photo": "isn't in this photo", "subject_missing": "isn't here anymore", "subject_moved": "moved before the photo was taken",
	"out_of_frame": "isn't in the frame", "too_far": "is too far away to make out", "too_close": "is too close to frame properly",
	"off_center": "needs to be closer to the middle of the frame", "blocked": "is hidden behind something", "wrong_place": "isn't at the place that matters",
	"missing_tags": "isn't doing anything that counts yet"}

## {"ok", "reason", "photo_id", "minute", "minute_of_day", "camera": {position,
## forward, up, right, fov, aspect, far}, "subjects": [...], "listed": bool}.
static func normalize_context(context) -> Dictionary:
	var result := {"ok": false, "reason": "", "photo_id": "", "minute": 0.0, "minute_of_day": 0.0, "camera": {}, "subjects": [], "listed": false}
	if not context is Dictionary:
		result.reason = "photo context is not a dictionary"
		return result
	var data: Dictionary = context
	var version := int(data.get("version", 1)) if _number(data.get("version", 1), 1.0, 100.0) else 0
	var photo_id := str(data.get("photo_id", data.get("capture_id", "")))
	if photo_id.is_empty() or photo_id.length() > 96:
		result.reason = "photo context has no photo id"
		return result
	result.photo_id = photo_id
	var camera := {}
	var minute := NAN
	if version >= 2:
		if str(data.get("source", "")) != SOURCE or data.get("trusted", false) != true:
			result.reason = "photo context is not from the phone camera"
			return result
		var raw_camera = data.get("camera", {})
		if not raw_camera is Dictionary:
			result.reason = "photo context has no camera pose"
			return result
		camera = {"position": _vector(raw_camera.get("position")), "forward": _vector(raw_camera.get("forward")), "fov": raw_camera.get("fov"),
			"aspect": raw_camera.get("aspect"), "far": raw_camera.get("far", 4000.0), "basis": raw_camera.get("basis")}
		var time = data.get("time", {})
		if time is Dictionary and _number(time.get("total_minutes"), 0.0, 1.0e12):
			minute = float(time.total_minutes)
	else:
		if data.get("clean_capture", false) != true:
			result.reason = "photo metadata is not a clean phone capture"
			return result
		var width := float(data.get("width", 0)) if _number(data.get("width"), 1.0, 100000.0) else 0.0
		var height := float(data.get("height", 0)) if _number(data.get("height"), 1.0, 100000.0) else 0.0
		camera = {"position": _vector(data.get("camera_position")), "forward": _vector(data.get("camera_forward")), "fov": data.get("camera_fov"),
			"aspect": width / height if height > 0.0 else NAN, "far": 4000.0, "basis": data.get("camera_basis")}
		if _number(data.get("world_total_minutes"), 0.0, 1.0e12):
			minute = float(data.world_total_minutes)
	var eye: Vector3 = camera.position
	var forward: Vector3 = camera.forward
	if not eye.is_finite() or not forward.is_finite() or forward.length() < 0.5 or not _number(camera.fov, 1.0, 179.0) or not _number(camera.aspect, 0.05, 20.0) or not is_finite(minute):
		result.reason = "photo context pose or time is incomplete"
		return result
	forward = forward.normalized()
	var up_hint := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.985 else Vector3.BACK
	var right := forward.cross(up_hint).normalized()
	var up := right.cross(forward).normalized()
	var basis = camera.basis
	if basis is Array and basis.size() == 9:
		var columns: Array[Vector3] = []
		for column in 3:
			columns.append(Vector3(float(basis[column * 3]), float(basis[column * 3 + 1]), float(basis[column * 3 + 2])))
		if columns[0].is_finite() and columns[1].is_finite() and columns[0].length() > 0.5 and columns[1].length() > 0.5:
			right = columns[0].normalized()
			up = columns[1].normalized()
	result.camera = {"position": eye, "forward": forward, "up": up, "right": right, "fov": float(camera.fov), "aspect": float(camera.aspect),
		"far": float(camera.far) if _number(camera.far, 1.0, 100000.0) else 4000.0}
	result.minute = minute
	result.minute_of_day = fposmod(minute, 1440.0)
	var subjects = data.get("subjects")
	if subjects is Array:
		result.listed = true
		for entry in subjects:
			if result.subjects.size() >= MAX_SUBJECTS:
				break
			if not entry is Dictionary or entry.get("line_of_sight", false) != true:
				continue
			var at := _vector(entry.get("position"))
			if not at.is_finite():
				continue
			var tags: Array = []
			if entry.get("tags") is Array:
				for tag in entry.tags:
					tags.append(str(tag))
			result.subjects.append({"id": str(entry.get("id", "")), "kind": str(entry.get("kind", "")), "position": at, "tags": tags})
	result.ok = true
	return result

## Pinhole projection with the camera's vertical fov (Camera3D KEEP_HEIGHT).
## {"in_front", "inside", "screen": Vector2 (0..1, y down), "centrality", "distance"}.
static func project(camera: Dictionary, point: Vector3) -> Dictionary:
	var offset: Vector3 = point - Vector3(camera.position)
	var depth := offset.dot(camera.forward)
	var result := {"in_front": depth > NEAR, "inside": false, "screen": Vector2(-1, -1), "centrality": 0.0, "distance": offset.length()}
	if depth <= NEAR:
		return result
	var tan_v := tan(deg_to_rad(float(camera.fov)) * 0.5)
	var tan_h := tan_v * float(camera.aspect)
	var sx := offset.dot(camera.right) / (depth * tan_h)
	var sy := offset.dot(camera.up) / (depth * tan_v)
	result.screen = Vector2((sx + 1.0) * 0.5, (1.0 - sy) * 0.5)
	result.centrality = clampf(1.0 - maxf(absf(sx), absf(sy)), 0.0, 1.0)
	var screen: Vector2 = result.screen
	result.inside = screen.x >= FRAME_MARGIN and screen.x <= 1.0 - FRAME_MARGIN and screen.y >= FRAME_MARGIN and screen.y <= 1.0 - FRAME_MARGIN \
		and offset.length() <= float(camera.far)
	return result

## Strict line of sight over static geometry: clear when nothing is hit, or
## when the first hit is one of the subject's own colliders. Never "close
## enough": a hit near the subject point is still a wall.
static func line_of_sight(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID], subject: Array[RID] = [], mask: int = STATIC_MASK) -> bool:
	if space == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	var hit: Dictionary = space.intersect_ray(query)
	return hit.is_empty() or (hit.get("rid") is RID and hit.rid in subject)

## First listed subject with this id carrying every required tag, or {}.
static func listed_subject(ctx: Dictionary, subject_id: String, required_tags: Array) -> Dictionary:
	for entry in ctx.subjects:
		if str(entry.id) != subject_id:
			continue
		var tags: Array = entry.tags
		var complete := true
		for tag in required_tags:
			complete = complete and str(tag) in tags
		if complete:
			return entry
	return {}

## candidate: {"id", "position" (live photo point, INF when gone), "lift"
## (metres to a second, higher sample point), "colliders" (Array[RID] of the
## subject itself), "area_center" (INF = none), "area_radius"}; objective: a
## normalized photo objective. {"ok", "reason", "distance", "centrality", "screen", "point"}.
static func evaluate(ctx: Dictionary, candidate: Dictionary, objective: Dictionary, space: PhysicsDirectSpaceState3D, exclude: Array[RID]) -> Dictionary:
	var result := {"ok": false, "reason": "", "distance": 0.0, "centrality": 0.0, "screen": Vector2(-1, -1), "point": Vector3.INF}
	var live: Vector3 = candidate.get("position", Vector3.INF)
	var point := live
	if bool(ctx.listed):
		var entry := listed_subject(ctx, str(candidate.id), objective.get("require_tags", []))
		if entry.is_empty():
			result.reason = "missing_tags" if not listed_subject(ctx, str(candidate.id), []).is_empty() else "not_in_photo"
			return result
		point = entry.position
	elif not (objective.get("require_tags", []) as Array).is_empty():
		result.reason = "missing_tags"
		return result
	if not live.is_finite():
		result.reason = "subject_missing"
		return result
	if live.distance_to(point) > LIVE_TOLERANCE:
		result.reason = "subject_moved"
		return result
	result.point = point
	var view := project(ctx.camera, point)
	result.distance = float(view.distance)
	result.centrality = float(view.centrality)
	result.screen = view.screen
	if not bool(view.inside):
		result.reason = "out_of_frame"
		return result
	if result.distance > float(objective.get("max_distance", 25.0)):
		result.reason = "too_far"
		return result
	if result.distance < float(objective.get("min_distance", 0.0)):
		result.reason = "too_close"
		return result
	if result.centrality < float(objective.get("min_centrality", 0.0)):
		result.reason = "off_center"
		return result
	var own: Array[RID] = []
	for rid in candidate.get("colliders", []):
		if rid is RID:
			own.append(rid)
	var eye: Vector3 = ctx.camera.position
	var upper: Vector3 = point + Vector3.UP * float(candidate.get("lift", 0.0))
	# The tested point, or a higher point of the same subject (a low curb may
	# hide the bottom of a parcel but not the whole parcel).
	if not line_of_sight(space, eye, point, exclude, own) and (float(candidate.get("lift", 0.0)) <= 0.0 or not line_of_sight(space, eye, upper, exclude, own)):
		result.reason = "blocked"
		return result
	var center: Vector3 = candidate.get("area_center", Vector3.INF)
	if center.is_finite() and Vector2(point.x - center.x, point.z - center.z).length() > float(candidate.get("area_radius", 10.0)):
		result.reason = "wrong_place"
		return result
	result.ok = true
	return result

## Minute-of-day window; "from" > "to" wraps past midnight.
static func in_window(minute_of_day: float, window: Dictionary) -> bool:
	if window.is_empty():
		return true
	var start := float(window.from)
	var finish := float(window.to)
	if start <= finish:
		return minute_of_day >= start and minute_of_day <= finish
	return minute_of_day >= start or minute_of_day <= finish

static func reason_text(reason: String) -> String:
	return str(REASONS.get(reason, "doesn't show what the case needs"))

static func _vector(value) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() == 3:
		for component in value:
			if not _number(component, -1.0e9, 1.0e9):
				return Vector3.INF
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.INF

static func _number(value, low: float, high: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= low and float(value) <= high
