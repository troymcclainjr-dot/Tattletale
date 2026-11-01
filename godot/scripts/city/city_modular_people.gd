extends RefCounted
## Shared low-poly adult topology and forty authored palettes/silhouettes.
## One surface per pose/rig part. Explicit index LODs remove small details;
## no mesh generation or appearance work takes place during gameplay ticks.
const ROSTER_PATH := "res://assets/data/pen_lucy_modular_roster.json"
const SHADER := preload("res://assets/materials/city_modular_people.gdshader")
const ORIGINS := {"Body": Vector3(0, 0.81, 0), "LegR": Vector3(-0.115, 0.81, 0), "LegL": Vector3(0.115, 0.81, 0), "ArmR": Vector3(-0.265, 1.31, 0), "ArmL": Vector3(0.265, 1.31, 0), "HandR": Vector3(-0.285, 0.88, 0.025), "HandL": Vector3(0.285, 0.88, 0.025), "Head": Vector3(0, 1.37, 0), "Mouth": Vector3(0, 1.465, 0.147)}
static var _roster: Array = []
static var _material: ShaderMaterial
static var _poses: Dictionary = {}
static var _rig_meshes: Dictionary = {}
static var _parts: Dictionary = {}

static func roster() -> Array:
	if _roster.is_empty():
		var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROSTER_PATH))
		_roster = parsed.appearances
	return _roster

static func material() -> ShaderMaterial:
	if _material != null:
		return _material
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	for pair in [["skin", "skin_palette"], ["top", "top_palette"], ["pants", "pants_palette"], ["hair", "hair_palette"], ["shoes", "shoe_palette"], ["accent", "accent_palette"]]:
		var colors := PackedVector4Array()
		for look in roster():
			# Vector payloads avoid Color-typed uniform conversion applying gamma twice.
			var color := Color(str(look[pair[0]]))
			if RenderingServer.get_current_rendering_method() != "gl_compatibility":
				color = color.srgb_to_linear()
			colors.append(Vector4(color.r, color.g, color.b, color.a))
		_material.set_shader_parameter(pair[1], colors)
	var shapes := PackedVector4Array()
	var features := PackedVector4Array()
	var face_shapes := PackedVector4Array()
	var face_details := PackedVector4Array()
	var hair_shapes := PackedVector4Array()
	var tailoring := PackedVector4Array()
	for look in roster():
		shapes.append(Vector4(float(look.width), float(look.depth), float(look.face_width), float(look.height) / 1.7))
		features.append(Vector4(float(look.hair_style), float(look.garment_style), float(look.beard), 0))
		face_shapes.append(_vector4(look.face_shape))
		face_details.append(_vector4(look.face_detail))
		hair_shapes.append(_vector4(look.hair_shape))
		tailoring.append(_vector4(look.tailoring))
	_material.set_shader_parameter("proportions", shapes)
	_material.set_shader_parameter("features", features)
	_material.set_shader_parameter("face_shapes", face_shapes)
	_material.set_shader_parameter("face_details", face_details)
	_material.set_shader_parameter("hair_shapes", hair_shapes)
	_material.set_shader_parameter("tailoring", tailoring)
	return _material

static func _vector4(values: Array) -> Vector4:
	return Vector4(float(values[0]), float(values[1]), float(values[2]), float(values[3]))

## CPU counterpart of the shared shader's rig-local fitting, used once by the
## distant render bake. Keep pivots/material sharing intact across the LOD switch.
static func bake_rig_vertex(look: Dictionary, source_point: Vector3, source_normal: Vector3, uv2: Vector2, part: String) -> Dictionary:
	var point := source_point
	var normal := source_normal
	var component := roundi(uv2.x)
	if uv2.y > .5:
		var origin: Vector3 = ORIGINS.get(part, Vector3.ZERO)
		var face := point + origin
		var shape: Array = look.face_shape
		var detail: Array = look.face_detail
		if component >= 1 and component <= 12:
			var hair := Vector3.ONE.lerp(Vector3(float(look.hair_shape[0]), float(look.hair_shape[1]), float(look.hair_shape[2])), smoothstep(1.625,1.68,face.y))
			face = Vector3(0,1.60,-.02) + (face - Vector3(0,1.60,-.02)) * hair
			normal = (normal / hair).normalized()
		else:
			var jaw := lerpf(float(shape[0]), 1.0, smoothstep(1.40,1.53,face.y))
			face.x *= jaw
			normal.x /= jaw
			face.y -= (float(detail[2]) - 1.0) * .045 * (1.0 - smoothstep(1.39,1.47,face.y))
			if component == 60:
				face.x *= float(shape[1])
				face.z = .110 + (face.z - .110) * float(shape[2])
				normal /= Vector3(float(shape[1]),1.0,float(shape[2]))
			if component in [61,62]:
				face.x *= float(shape[3])
				face.y += float(detail[0])
			if component == 64:
				face.x *= float(detail[1])
		face.x *= float(look.face_width)
		normal.x /= float(look.face_width)
		normal = normal.normalized()
		point = face - origin
	if uv2.y < -.5 and uv2.y > -1.5:
		var fit := lerpf(float(look.tailoring[0]), float(look.tailoring[1]), smoothstep(.90,1.29,point.y + .81))
		point.x *= fit
		normal.x /= fit
		normal = normal.normalized()
	if uv2.y < -1.5 and uv2.y > -2.5:
		point.x *= float(look.tailoring[2])
		normal.x /= float(look.tailoring[2])
		normal = normal.normalized()
	return {"point": point, "normal": normal}

static func crowd_mesh(seated := false, chair := true) -> ArrayMesh:
	var key := "%s_%s" % [seated, chair]
	if _poses.has(key):
		return _poses[key]
	_ensure_parts()
	var merged := _empty()
	for part in _parts:
		if part == "Chair" and (not seated or not chair):
			continue
		if part == "IdleProps" and seated:
			continue
		_append(merged, _parts[part], str(part), Vector3.ZERO, seated)
	var mesh := _mesh(merged)
	_poses[key] = mesh
	return mesh

static func rig(identity: String, index: int, height: float) -> Node3D:
	_ensure_parts()
	var look: Dictionary = roster()[index]
	var root := Node3D.new()
	root.name = identity
	# Preserve the authored actor height/capsule. Width/depth are visual only.
	root.scale = Vector3(float(look.width), height / 1.7, float(look.depth))
	var rig_node := Node3D.new()
	rig_node.name = "Rig"
	root.add_child(rig_node)
	var nodes: Dictionary = {"Rig": rig_node}
	for part in ["Body", "LegR", "LegL", "ArmR", "ArmL", "HandR", "HandL", "Head", "Mouth"]:
		var parent_name := "Rig"
		if part in ["ArmR", "ArmL", "Head"]:
			parent_name = "Body"
		elif part == "HandR":
			parent_name = "ArmR"
		elif part == "HandL":
			parent_name = "ArmL"
		elif part == "Mouth":
			parent_name = "Head"
		var pivot := Node3D.new()
		pivot.name = part
		nodes[parent_name].add_child(pivot)
		pivot.position = ORIGINS[part] - ORIGINS.get(parent_name, Vector3.ZERO)
		nodes[part] = pivot
		if not _rig_meshes.has(part):
			var data := _empty()
			_append(data, _parts[part], part, ORIGINS[part], false)
			_rig_meshes[part] = _mesh(data)
		var visual := MeshInstance3D.new()
		visual.name = part + "Surface"
		visual.mesh = _rig_meshes[part]
		visual.set_instance_shader_parameter("roster_override", index)
		visual.set_instance_shader_parameter("rigged", true)
		pivot.add_child(visual)
	return root

static func budget() -> Dictionary:
	_ensure_parts()
	var result := {"roster": roster().size(), "materials": 1, "rig_surfaces": ORIGINS.size(), "poses": {}}
	for pose in 3:
		var mesh := crowd_mesh(pose != 0, pose != 2)
		var arrays: Array = mesh.surface_get_arrays(0)
		var levels: Array = mesh.get_meta("lod_triangles")
		result.poses[str(pose)] = {"triangles": arrays[Mesh.ARRAY_INDEX].size() / 3, "vertices": arrays[Mesh.ARRAY_VERTEX].size(), "surfaces": mesh.get_surface_count(), "lod_triangles": levels}
	return result

static func _empty() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "uv2": PackedVector2Array(), "hi": PackedInt32Array(), "mid": PackedInt32Array(), "far": PackedInt32Array()}

static func _vertex(data: Dictionary, point: Vector3, normal: Vector3, slot: int, component: int, face: bool) -> void:
	data.v.append(point)
	data.n.append(normal)
	data.uv.append(Vector2(slot, 0))
	data.uv2.append(Vector2(component, 1.0 if face else 0.0))

static func _triangle(data: Dictionary, a: int, b: int, c: int, tier: int) -> void:
	if tier < 3:
		data.hi.append_array(PackedInt32Array([a, b, c]))
	if tier <= 1:
		data.mid.append_array(PackedInt32Array([a, b, c]))
	if tier == 3:
		data.far.append_array(PackedInt32Array([a, b, c]))

static func _ellipsoid(part: String, center: Vector3, radius: Vector3, slot: int, component := 0, tier := 0, segments := 8, rings := 4) -> void:
	var data: Dictionary = _parts[part]
	var start: int = data.v.size()
	for row in rings + 1:
		var phi := PI * float(row) / rings
		for segment in segments:
			var angle := TAU * float(segment) / segments
			var sphere := Vector3(sin(phi) * sin(angle), cos(phi), sin(phi) * cos(angle))
			_vertex(data, center + sphere * radius, (sphere / radius).normalized(), slot, component, part in ["Head", "Mouth"])
	for row in rings:
		for segment in segments:
			var a := start + row * segments + segment
			var b := start + row * segments + (segment + 1) % segments
			var c := a + segments
			var d := b + segments
			if row != 0:
				_triangle(data, a, b, c, tier)
			if row != rings - 1:
				_triangle(data, b, d, c, tier)

## Elliptical loft: tapered cuffs, calves, upper arms and a shaped shoulder line.
static func _loft(part: String, center: Vector3, levels: Array, slot: int, component := 0, tier := 0, segments := 8) -> void:
	var data: Dictionary = _parts[part]
	var start: int = data.v.size()
	for row in levels.size():
		var level: Array = levels[row]
		var previous: Array = levels[maxi(0, row - 1)]
		var next: Array = levels[mini(levels.size() - 1, row + 1)]
		var rise := maxf(.001, float(next[0]) - float(previous[0]))
		var slope_x := (float(next[1]) - float(previous[1])) / rise
		var slope_z := (float(next[2]) - float(previous[2])) / rise
		for segment in segments:
			var angle := TAU * float(segment) / segments
			var sx := sin(angle)
			var cz := cos(angle)
			# Follow the loft slope: shaped jaws, shoulders and shoe vamps must not
			# inherit cylindrical normals that flatten their fitted silhouette.
			var normal := Vector3(sx / float(level[1]), -sx * sx * slope_x / float(level[1]) - cz * cz * slope_z / float(level[2]), cz / float(level[2])).normalized()
			var ring_x := sx
			var ring_z := cz
			if component in [25,28]:
				# A garment wraps two thighs, not one central elliptical leg. Rounded
				# corners provide clearance at the hip quadrants through the walk arc.
				ring_x = signf(sx) * pow(absf(sx), .65)
				ring_z = signf(cz) * pow(absf(cz), .65)
				normal.x = signf(sx) * pow(absf(sx), 1.35) / float(level[1])
				normal.z = signf(cz) * pow(absf(cz), 1.35) / float(level[2])
				normal.y = -sx * sx * slope_x / float(level[1]) - cz * cz * slope_z / float(level[2])
				normal = normal.normalized()
			_vertex(data, center + Vector3(ring_x * float(level[1]), float(level[0]), ring_z * float(level[2])), normal, slot, component, part == "Head")
	for row in levels.size() - 1:
		for segment in segments:
			var a := start + row * segments + segment
			var b := start + row * segments + (segment + 1) % segments
			_triangle(data, a, a + segments, b, tier)
			_triangle(data, b, a + segments, b + segments, tier)
	for segment in range(1, segments - 1):
		if component not in [25,28]:
			_triangle(data, start, start + segment, start + segment + 1, tier)
		var last := start + (levels.size() - 1) * segments
		_triangle(data, last, last + segment + 1, last + segment, tier)

static func _box(part: String, center: Vector3, size: Vector3, slot: int, component := 0, tier := 0) -> void:
	var primitive := BoxMesh.new()
	primitive.size = size
	var arrays := primitive.get_mesh_arrays()
	var data: Dictionary = _parts[part]
	var start: int = data.v.size()
	for i in arrays[Mesh.ARRAY_VERTEX].size():
		_vertex(data, center + arrays[Mesh.ARRAY_VERTEX][i], arrays[Mesh.ARRAY_NORMAL][i], slot, component, part in ["Head", "Mouth"])
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in range(0, indices.size(), 3):
		_triangle(data, start + indices[i], start + indices[i + 1], start + indices[i + 2], tier)

static func _collar(side: float, cardigan: bool) -> void:
	var data: Dictionary = _parts.Body
	var start: int = data.v.size()
	var points: Array[Vector3] = [Vector3(side*.03,1.33,.105), Vector3(side*.095,1.286,.126), Vector3(side*.055,1.238,.140)]
	if cardigan:
		points = [Vector3(side*.042,1.32,.110), Vector3(side*.09,1.255,.130), Vector3(side*.035,1.13,.142)]
	for point in points:
		_vertex(data, point, Vector3.FORWARD * -1.0, 8, 24 if cardigan else 22, false)
	if side < 0:
		_triangle(data, start, start+2, start+1, 1)
	else:
		_triangle(data, start, start+1, start+2, 1)

## Closed crown with a fitted hairline and nape. The lower rim remains attached
## while per-style morphs affect only the upper silhouette.
static func _scalp_shell(component: int, fringe: float, nape: float) -> void:
	var data: Dictionary = _parts.Head
	var start: int = data.v.size()
	var segments := 12
	for row in 4:
		for segment in segments:
			var angle := TAU * float(segment) / segments
			var front := maxf(0.0, cos(angle))
			var y: float = lerpf(nape, fringe, pow(front, .45)) if row == 0 else [0.0,1.625,1.665,1.688][row]
			if component in [3,7] and row == 0:
				# Keep nape coverage, but lift the side edge above the ear root.
				y = maxf(y, lerpf(nape,1.535,pow(absf(sin(angle)),4.0)))
			var rx: float = [.128,.114,.066,.001][row]
			var rz: float = [.126,.112,.064,.001][row]
			if component == 6 and row < 2:
				rx *= 1.0 + .025 * cos(angle * 6.0)
				rz *= 1.0 + .025 * cos(angle * 6.0)
			var point := Vector3(sin(angle)*rx,y,cos(angle)*rz-.006)
			var normal := Vector3(sin(angle), .12 if row == 0 else float(row)*.55, cos(angle)).normalized()
			_vertex(data, point, normal, 3, component, true)
	for row in 3:
		for segment in segments:
			var a := start + row * segments + segment
			var b := start + row * segments + (segment + 1) % segments
			_triangle(data,a,a+segments,b,0)
			_triangle(data,b,a+segments,b+segments,0)
	for segment in range(1,segments-1):
		_triangle(data,start+3*segments,start+3*segments+segment+1,start+3*segments+segment,0)

static func _shirt_v() -> void:
	var data: Dictionary = _parts.Body
	var start: int = data.v.size()
	for point in [Vector3(-.086,1.313,.111),Vector3(.086,1.313,.111),Vector3(0,1.075,.145)]:
		_vertex(data,point,Vector3(0,0,1),8,27,false)
	_triangle(data,start,start+1,start+2,0)

static func _ensure_parts() -> void:
	if not _parts.is_empty():
		return
	for part in ORIGINS:
		_parts[part] = _empty()
	_parts.Chair = _empty()
	_parts.IdleProps = _empty()
	# Shared standing-mesh props: hidden per instance except their idle activity.
	# Mid/far LOD omits these tiny details, with no extra surface or draw batch.
	_box("IdleProps", Vector3(-.285,.86,.075), Vector3(.012,.012,.10), 5, 50, 2)
	_box("IdleProps", Vector3(-.285,.86,.128), Vector3(.013,.013,.008), 15, 50, 2)
	_box("IdleProps", Vector3(-.285,.78,.055), Vector3(.085,.19,.075), 13, 51, 2)
	_box("IdleProps", Vector3(-.285,.88,.055), Vector3(.070,.035,.065), 13, 51, 2)
	_loft("IdleProps", Vector3(-.285,0,.055), [[.875,.028,.028],[.925,.016,.016],[.965,.016,.016]], 14, 51, 2, 6)
	# Shaped clothed torso, pelvic transition, neck and shoulder caps.
	_loft("Body", Vector3.ZERO, [[0.78,.17,.105],[.90,.155,.11],[1.12,.205,.13],[1.29,.225,.12],[1.34,.13,.095]], 1, 0, 0, 10)
	# The trouser pelvis terminates inside the shirt, rather than intersecting
	# its hem and leaving dark interpenetration patches around every waist.
	_ellipsoid("Body", Vector3(0,.80,0), Vector3(.159,.065,.095), 2)
	_loft("Body", Vector3.ZERO, [[1.30,.065,.065],[1.39,.061,.058]], 0)
	for side in [-1.0, 1.0]:
		var leg := "LegR" if side < 0 else "LegL"
		var arm := "ArmR" if side < 0 else "ArmL"
		var hand := "HandR" if side < 0 else "HandL"
		_loft(leg, Vector3(side * .115,0,0), [[.095,.067,.065],[.40,.065,.067],[.47,.074,.074],[.77,.087,.095]], 2)
		_loft(leg, Vector3(side * .115,0,.044), [[.025,.080,.145],[.052,.082,.148],[.095,.076,.130],[.138,.054,.080]], 4, 0, 0, 8)
		_loft(leg, Vector3(side * .115,0,.044), [[.002,.079,.141],[.018,.084,.150],[.035,.081,.147]], 10, 0, 1, 8)
		_box(leg, Vector3(side * .115,.112,.105), Vector3(.09,.009,.028), 8, 0, 2)
		_ellipsoid(arm, Vector3(side * .247,1.265,0), Vector3(.082,.10,.087), 1)
		_loft(arm, Vector3(side * .281,0,.008), [[1.02,.050,.055],[1.18,.056,.066],[1.29,.066,.070]], 1)
		_loft(arm, Vector3(side * .285,0,.015), [[.91,.038,.040],[1.06,.047,.049]], 0, 0, 0, 6)
		_loft(hand, Vector3(side * .285,0,.025), [[.798,.027,.023],[.817,.039,.027],[.863,.042,.030],[.905,.033,.026]], 0, 0, 0, 6)
		_ellipsoid(hand, Vector3(side * .251,.875,.041), Vector3(.019,.038,.022), 0, 0, 1, 6, 3)
		# Short and long sleeve cuffs remain above articulated wrists.
		_loft(arm, Vector3(side * .281,0,.008), [[1.018,.051,.056],[1.042,.052,.057]], 9, 0, 1)
		_loft(arm, Vector3(side * .285,0,.015), [[.916,.043,.046],[1.06,.051,.054]], 1, 29, 0, 6)
		_loft(arm, Vector3(side * .285,0,.015), [[.912,.044,.047],[.936,.045,.048]], 9, 29, 1, 6)
	# A dimensional face: oval cranium, jaw, ears, bridge/tip, inset eyes and brows.
	_loft("Head", Vector3.ZERO, [[1.365,.056,.062],[1.405,.086,.090],[1.475,.115,.112],[1.555,.121,.116],[1.620,.101,.099],[1.658,.058,.057],[1.669,.015,.015]], 0, 0, 0, 12)
	# Jaw contour is integrated into the head loft: no intersecting jaw ball.
	_ellipsoid("Head", Vector3(0,1.505,.116), Vector3(.022,.040,.027), 0, 60, 1, 8, 4)
	_ellipsoid("Head", Vector3(0,1.485,.141), Vector3(.027,.016,.021), 0, 60, 1, 8, 3)
	for side in [-1.0, 1.0]:
		_ellipsoid("Head", Vector3(side * .122,1.50,.002), Vector3(.026,.044,.023), 0, 0, 1, 6, 4)
		_ellipsoid("Head", Vector3(side * .046,1.532,.115), Vector3(.022,.010,.007), 5, 61, 1, 8, 3)
		_ellipsoid("Head", Vector3(side * .046,1.532,.123), Vector3(.008,.008,.003), 6, 61, 1, 6, 3)
		_ellipsoid("Head", Vector3(side * .043,1.536,.126), Vector3(.002,.002,.002), 5, 61, 2, 4, 2)
		_ellipsoid("Head", Vector3(side * .046,1.559,.117), Vector3(.030,.006,.009), 3, 62, 1, 6, 3)
		_ellipsoid("Head", Vector3(side * .018,1.478,.155), Vector3(.006,.003,.004), 7, 60, 2, 6, 2)
	_ellipsoid("Mouth", Vector3(0,1.457,.112), Vector3(.037,.010,.009), 7, 64, 1, 8, 3)
	_ellipsoid("Mouth", Vector3(0,1.457,.122), Vector3(.029,.002,.003), 10, 64, 1, 8, 2)
	_loft("Head", Vector3(0,0,.086), [[1.375,.032,.012],[1.395,.058,.023],[1.425,.061,.019],[1.434,.043,.010]], 3, 40, 1, 8)
	# Eight interchangeable silhouettes: cropped, natural, bun, bob, locs,
	# braids, ponytail, and a bare scalp. No boxes are used for heads or hair.
	_scalp_shell(1, 1.595, 1.525)
	_ellipsoid("Head", Vector3(0,1.641,-.019), Vector3(.157,.128,.143), 3, 2, 0, 10, 5)
	# The natural crown is one coherent faceted volume, without bead-like curls.
	_scalp_shell(3, 1.590, 1.425)
	_ellipsoid("Head", Vector3(0,1.692,-.083), Vector3(.071,.065,.067), 3, 3)
	_scalp_shell(4, 1.575, 1.395)
	_ellipsoid("Head", Vector3(0,1.478,-.098), Vector3(.116,.147,.048), 3, 4, 0, 10, 4)
	for side in [-1.0, 1.0]:
		_ellipsoid("Head", Vector3(side*.114,1.477,-.035), Vector3(.034,.141,.078), 3, 4)
	_scalp_shell(5, 1.590, 1.425)
	for i in 7:
		var a := -PI * .5 + PI * float(i) / 6.0
		_loft("Head", Vector3(sin(a)*.108,0,-.055-cos(a)*.075), [[1.28,.016,.017],[1.47,.019,.020],[1.61,.021,.022]], 3, 5, 0, 6)
	_scalp_shell(6, 1.590, 1.425)
	for side in [-1.0, 1.0]:
		_loft("Head", Vector3(side*.109,0,-.067), [[1.285,.013,.014],[1.33,.019,.021],[1.38,.016,.018],[1.43,.021,.023],[1.48,.018,.020],[1.53,.023,.024],[1.58,.020,.022],[1.62,.024,.025]], 3, 6, 0, 6)
	_scalp_shell(7, 1.590, 1.425)
	_ellipsoid("Head", Vector3(0,1.49,-.129), Vector3(.052,.16,.049), 3, 7)
	_ellipsoid("Head", Vector3(0,1.625,-.120), Vector3(.038,.024,.031), 8, 7, 1)
	# Four additional authored hair silhouettes: side part, tapered high fade,
	# swept crown and angled pixie. All share the same material and LOD surface.
	_scalp_shell(9, 1.595, 1.49)
	_ellipsoid("Head", Vector3(-.036,1.665,.026), Vector3(.084,.039,.078), 3, 9, 1, 8, 3)
	_loft("Head", Vector3(0,0,-.015), [[1.612,.113,.103],[1.680,.096,.086],[1.718,.073,.065]], 3, 10, 0, 8)
	_scalp_shell(11, 1.595, 1.49)
	_ellipsoid("Head", Vector3(-.038,1.658,.025), Vector3(.074,.042,.068), 3, 11, 1, 8, 3)
	_scalp_shell(12, 1.585, 1.48)
	_ellipsoid("Head", Vector3(.060,1.601,.064), Vector3(.065,.048,.064), 3, 12, 1, 6, 3)
	# Clothing seams, collars, jacket opening, hoodie cords and skirt are modules.
	_loft("Body", Vector3.ZERO, [[.80,.175,.110],[.824,.173,.112]], 9, 0, 1, 10)
	_loft("Body", Vector3.ZERO, [[1.304,.083,.076],[1.333,.073,.067]], 9, 20, 1)
	_ellipsoid("Body", Vector3(0,1.31,-.083), Vector3(.105,.09,.069), 1, 21)
	for side in [-1.0, 1.0]:
		_box("Body", Vector3(side*.046,1.23,.127), Vector3(.008,.14,.006), 8, 21, 1)
		_collar(side, false)
		_box("Body", Vector3(side*.094,1.11,.132), Vector3(.09,.065,.006), 9, 22, 1)
		_loft("Body", Vector3(side*.115,0,.08), [[.85,.064,.048],[1.12,.079,.061],[1.28,.074,.042]], 1, 23, 0, 6)
		_box("Body", Vector3(side*.045,1.084,.139), Vector3(.013,.40,.008), 8, 23, 1)
		_collar(side, true)
	_loft("Body", Vector3.ZERO, [[.53,.30,.32],[.80,.26,.23],[.89,.19,.15]], 1, 25, 0, 10)
	for i in 4:
		_ellipsoid("Body", Vector3(0,1.03+float(i)*.065,.135), Vector3(.008,.008,.004), 12, 22, 2, 4, 2)
	# Varsity rib collar, fitted waistcoat panels, and a hip-length tunic hem.
	_loft("Body", Vector3.ZERO, [[1.304,.083,.076],[1.340,.074,.067]], 8, 26, 1, 8)
	_loft("Body", Vector3.ZERO, [[.795,.177,.113],[.835,.172,.114]], 8, 26, 1, 10)
	for side in [-1.0, 1.0]:
		_loft("Body", Vector3(side*.107,0,.087), [[.83,.068,.044],[1.09,.084,.058],[1.29,.056,.032]], 1, 27, 0, 6)
		_box("Body", Vector3(side*.060,1.065,.140), Vector3(.012,.35,.007), 8, 27, 1)
	_loft("Body", Vector3.ZERO, [[.675,.25,.255],[.810,.245,.195],[.90,.18,.135]], 1, 28, 0, 10)
	_loft("Body", Vector3.ZERO, [[.675,.252,.257],[.696,.251,.250]], 8, 28, 1, 10)
	_shirt_v()
	# Only furniture retains rectangular planks; the human silhouette is curved.
	_box("Chair", Vector3(0,.38,0), Vector3(.52,.07,.50), 11)
	_box("Chair", Vector3(0,.71,-.23), Vector3(.52,.62,.055), 11)
	for x in [-.21,.21]:
		for z in [-.19,.19]:
			_box("Chair", Vector3(x,.18,z), Vector3(.045,.36,.045), 11)
	# Dedicated distant topology: curved silhouettes and palette remain, while
	# small face/clothing/hair pieces do not consume distant triangle submissions.
	_loft("Body", Vector3.ZERO, [[.78,.17,.105],[1.12,.205,.13],[1.34,.13,.095]], 1, 0, 3, 6)
	_ellipsoid("Head", Vector3(0,1.50,0), Vector3(.123,.169,.119), 0, 0, 3, 8, 4)
	for side in [-1.0, 1.0]:
		var leg := "LegR" if side < 0 else "LegL"
		var arm := "ArmR" if side < 0 else "ArmL"
		var hand := "HandR" if side < 0 else "HandL"
		_loft(leg, Vector3(side*.115,0,0), [[.08,.067,.065],[.43,.07,.07],[.79,.087,.095]], 2, 0, 3, 6)
		_ellipsoid(leg, Vector3(side*.115,.07,.05), Vector3(.083,.07,.15), 4, 0, 3, 6, 3)
		_loft(arm, Vector3(side*.277,0,0), [[1.02,.049,.054],[1.31,.07,.07]], 1, 0, 3, 6)
		_loft(hand, Vector3(side*.285,0,.015), [[.81,.038,.035],[1.03,.043,.045]], 0, 0, 3, 6)
	for style in 12:
		if style == 7: # Bare scalp has no hair geometry.
			continue
		var radius := Vector3(.128,.074,.118)
		if style == 9:
			radius = Vector3(.110,.10,.10)
		if style == 1:
			radius = Vector3(.157,.128,.143)
		_ellipsoid("Head", Vector3(0,1.62,-.02), radius, 3, style + 1, 3, 6, 3)
		if style in [3, 4, 5, 6]:
			_ellipsoid("Head", Vector3(0,1.46,-.085), Vector3(.125,.14,.07), 3, style + 1, 3, 6, 3)
		elif style == 2:
			_ellipsoid("Head", Vector3(0,1.69,-.08), Vector3(.07,.065,.067), 3, style + 1, 3, 6, 3)
	_loft("Body", Vector3.ZERO, [[.53,.30,.32],[.80,.26,.23],[.89,.19,.15]], 1, 25, 3, 6)
	_loft("Body", Vector3.ZERO, [[.675,.25,.255],[.810,.245,.195],[.90,.18,.135]], 1, 28, 3, 6)
	_box("Chair", Vector3(0,.38,0), Vector3(.52,.07,.50), 11, 0, 3)
	_box("Chair", Vector3(0,.71,-.23), Vector3(.52,.62,.055), 11, 0, 3)
	for side in [-1.0, 1.0]:
		_box("Chair", Vector3(side*.21,.18,0), Vector3(.045,.36,.43), 11, 0, 3)

## Seated garments use explicit waist/lap/hem rings, not a translated standing
## silhouette. The skirt drops over knees; the shorter tunic ends on the lap
## while its sides fall beside the thighs. Their lower rims remain open cloth.
static func _seated_garment_position(point: Vector3, component: int) -> Vector3:
	var skirt := component == 25
	# source y/radii; target y, centre z, width, depth, front-hem lift.
	var rows: Array = [[.53,.30,.32,.425,.19,.265,.315,0.0],[.80,.26,.23,.625,.17,.26,.30,0.0],[.89,.19,.15,.655,0.0,.205,.15,0.0]] if skirt else [[.675,.25,.255,.45,.075,.235,.205,.18],[.810,.245,.195,.63,.055,.235,.185,0.0],[.90,.18,.135,.655,0.0,.195,.145,0.0]]
	var lower: Array = rows[0]
	var upper: Array = rows[1]
	for row in rows.size()-1:
		if point.y >= float(rows[row][0]):
			lower = rows[row]
			upper = rows[row+1]
	var blend := clampf((point.y-float(lower[0]))/(float(upper[0])-float(lower[0])),0.0,1.0)
	var values: Array[float] = []
	for column in range(1,8):
		values.append(lerpf(float(lower[column]),float(upper[column]),blend))
	var across := point.x/values[0]
	var depth := point.z/values[1]
	var front_lift := values[6]*pow(maxf(0.0,depth),.35)
	return Vector3(across*values[4],values[2]+front_lift,values[3]+depth*values[5])

static func _seated_garment(point: Vector3, source_normal: Vector3, component: int) -> Dictionary:
	var step := .0005
	var dx := (_seated_garment_position(point+Vector3(step,0,0),component)-_seated_garment_position(point-Vector3(step,0,0),component))/(2.0*step)
	var dy := (_seated_garment_position(point+Vector3(0,step,0),component)-_seated_garment_position(point-Vector3(0,step,0),component))/(2.0*step)
	var dz := (_seated_garment_position(point+Vector3(0,0,step),component)-_seated_garment_position(point-Vector3(0,0,step),component))/(2.0*step)
	var jacobian := Basis(dx,dy,dz)
	var normal := source_normal
	if absf(jacobian.determinant()) > .000001:
		normal = (jacobian.inverse().transposed()*source_normal).normalized()
	return {"point": _seated_garment_position(point,component), "normal": normal}

static func _append(target: Dictionary, source: Dictionary, part: String, origin: Vector3, seated: bool) -> void:
	var offset: int = target.v.size()
	var part_code := 0 if seated else int({"Body": 1, "Head": 2, "Mouth": 2, "ArmR": 3, "HandR": 7, "IdleProps": 7, "ArmL": 4, "HandL": 4, "LegR": 5, "LegL": 6}.get(part, 0))
	for i in source.v.size():
		var point: Vector3 = source.v[i]
		var normal: Vector3 = source.n[i]
		if seated and part != "Chair":
			if part == "Body" and roundi(source.uv2[i].x) in [25, 28]:
				var cloth := _seated_garment(point,normal,roundi(source.uv2[i].x))
				point = cloth.point
				normal = cloth.normal
			elif part in ["LegR", "LegL"]:
				if point.y >= .43:
					point = Vector3(point.x, .50 + point.z, .81 - point.y)
					normal = Vector3(normal.x, normal.z, -normal.y)
				else:
					point.y *= .50 / .43
					point.z += .38
			elif part == "Body":
				var slot := roundi(source.uv[i].x)
				if slot == 2:
					# A seated waistband bridges the raised thighs to the bunched hem.
					point.y = .55 + (point.y-.80)*1.2
					normal.y /= 1.2
				elif slot != 0:
					# Shirts/waistcoats stop above the lap instead of intersecting thighs.
					var hem := clampf((point.y-.78)/.27,0.0,1.0)
					point.y += -.31 + .15*(1.0-smoothstep(0.0,1.0,hem))
					normal.y /= maxf(.16,1.0-(.15/.27)*6.0*hem*(1.0-hem))
				else:
					point.y -= .31
				normal = normal.normalized()
			else:
				point.y -= .31
		target.v.append(point - origin)
		target.n.append(normal)
		# UV.y tags articulated standing parts. The rigged path ignores it, and
		# seated geometry remains untagged so chairs/porch poses are untouched.
		target.uv.append(Vector2(source.uv[i].x, part_code))
		var region: float = -1.0 if part == "Body" else (-2.0 if part in ["LegR", "LegL"] else (-3.0 if part in ["ArmR", "ArmL"] else source.uv2[i].y))
		target.uv2.append(Vector2(source.uv2[i].x, region))
	for tier in ["hi", "mid", "far"]:
		for index in source[tier]:
			target[tier].append(index + offset)

static func _mesh(data: Dictionary) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data.v
	arrays[Mesh.ARRAY_NORMAL] = data.n
	arrays[Mesh.ARRAY_TEX_UV] = data.uv
	arrays[Mesh.ARRAY_TEX_UV2] = data.uv2
	arrays[Mesh.ARRAY_INDEX] = data.hi
	var mesh := ArrayMesh.new()
	# Errors in metres: facial/curl accents disappear first, then eyes/seams.
	var far_indices: PackedInt32Array = data.far if not data.far.is_empty() else PackedInt32Array([0, 0, 0])
	var lods: Dictionary = {}
	# Some rig parts contain no tiny accents. Godot rejects a redundant LOD
	# whose index count equals the base surface, even when indices are valid.
	if not data.mid.is_empty() and data.mid.size() < data.hi.size():
		lods[0.025] = data.mid
	if far_indices.size() < data.hi.size():
		lods[0.09] = far_indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], lods)
	mesh.surface_set_material(0, material())
	mesh.set_meta("lod_triangles", [data.mid.size() / 3, data.far.size() / 3])
	# Shader proportions can exceed the source mesh, so culling must include them.
	var bounds := mesh.get_aabb()
	mesh.custom_aabb = bounds.grow(.25)
	return mesh


