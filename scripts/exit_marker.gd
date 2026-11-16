extends Node3D
## Over a way out of a place that has no door to show for it (the end of a pavement: "TO THE LIQUOR STORE"): the
## letter E on a key and three chevrons pointing the way, marching, so that it is plain he can go on from here.
## It hangs over the use point, above where its name shows, faces the camera, and is drawn over everything (it is
## a sign to the player, not a thing in the street). main.gd puts one on every "goto:" use point whose name
## begins "TO " when a place opens (`mark_all`), and says when they are not to show (`hidden`).
##
## The E and the arrow are placeholders, like every other sign.

const YELLOW := Color(1.0, 0.84, 0.2)
const INK := Color(0.08, 0.07, 0.1)
const PAPER := Color(0.98, 0.96, 0.9)
const UP := 0.5                 # metres over the use point's name
const KEY := 0.3                # the key's side, metres
const STEP := 0.19              # from one chevron to the next
const MARCH := 5.0              # radians a second

static var hidden := false      # main.gd: a conversation, a menu, the microphone, a video: none of them show
static var still := false       # a picture run: the chevrons hold still (a moving sign reads as flicker to the checks)

var way := Vector2.RIGHT        # across the picture: x to the right, y up
var point: Node3D               # the use point it hangs over
var lead: Node3D
var _t := 0.0
var _chevrons: Array = []
var _key: Node3D


## One on every way out of `site` that is walked off through. `areas`: where the lead may walk here (Rect2 in x, z).
static func mark_all(points: Array, areas: Array, lead: Node3D) -> void:
	for p: Variant in points:
		if not (p is Node3D) or not ("id" in p) or not String(p.id).begins_with("goto:") or not String(p.label).begins_with("TO "):
			continue
		if p.has_node("ExitMarker"):
			continue
		var marker: Node3D = new()
		marker.name = "ExitMarker"
		marker.point = p
		marker.lead = lead
		marker.way = _way_out(p.global_position, areas)
		p.add_child(marker)
		marker.position = Vector3(0.0, float(p.label_height) + UP, 0.0)
		marker._build()


## Which way off the floor that spot is: the end of the longest strip of floor it stands on, left or right; a spot
## in the middle of the floor points away from us (a way through at the back).
static func _way_out(at: Vector3, areas: Array) -> Vector2:
	var best := Rect2()
	for r: Variant in areas:
		var area: Rect2 = r
		if area.grow(1.6).has_point(Vector2(at.x, at.z)) and area.size.x > best.size.x:
			best = area
	if best.size.x <= 0.0:
		return Vector2.RIGHT
	if at.x - best.position.x < 2.5:
		return Vector2.LEFT
	if best.end.x - at.x < 2.5:
		return Vector2.RIGHT
	return Vector2.UP if at.z < best.get_center().y else Vector2.DOWN


func _build() -> void:
	var along := Vector3(way.x, way.y, 0.0)
	# The key, at the tail.
	_key = Node3D.new()
	_key.position = -along * (KEY * 0.5 + 0.06)
	add_child(_key)
	_plate(_key, Vector3(KEY + 0.05, KEY + 0.05, 0.004), Vector3(0, 0, -0.004), INK)
	_plate(_key, Vector3(KEY, KEY, 0.004), Vector3.ZERO, PAPER)
	_plate(_key, Vector3(KEY, 0.045, 0.004), Vector3(0, -KEY * 0.5 + 0.022, 0.002), PAPER.darkened(0.25))
	var e := Label3D.new()
	e.text = "E"
	e.font_size = 96
	e.pixel_size = KEY * 0.78 / 96.0
	e.modulate = INK
	e.outline_size = 0
	e.shaded = false
	e.no_depth_test = true
	e.render_priority = 3
	e.position = Vector3(0, 0.012, 0.006)
	_key.add_child(e)
	# The chevrons, from the key outwards.
	for i in 3:
		var c := Node3D.new()
		c.position = along * (0.16 + i * STEP)
		c.rotation.z = way.angle()
		add_child(c)
		for s: float in [-1.0, 1.0]:
			_plate(c, Vector3(0.2, 0.105, 0.004), Vector3(-0.045, s * 0.058, -0.004), INK, s * -42.0, 1)
			_plate(c, Vector3(0.165, 0.062, 0.004), Vector3(-0.045, s * 0.058, 0.0), YELLOW, s * -42.0, 2)
		_chevrons.append(c)


func _plate(parent: Node3D, size: Vector3, at: Vector3, colour: Color, turn := 0.0, priority := 1) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = colour
	mat.no_depth_test = true
	mat.render_priority = priority
	mi.material_override = mat
	mi.position = at
	mi.rotation_degrees.z = turn
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _process(delta: float) -> void:
	visible = not hidden
	if not visible:
		return
	var cam := get_viewport().get_camera_3d()
	if cam:
		global_basis = cam.global_basis
	if not still:
		_t += delta
	var along := Vector3(way.x, way.y, 0.0)
	for i in _chevrons.size():
		var beat := maxf(sin(_t * MARCH - i * 0.95), 0.0)       # each lights after the one before it: they march
		var c: Node3D = _chevrons[i]
		c.position = along * (0.16 + i * STEP + 0.05 * beat)
		c.scale = Vector3.ONE * (0.82 + 0.3 * beat)
	var near: bool = lead != null and point != null and lead.global_position.distance_to(point.global_position) <= float(point.use_reach) + 0.3
	_key.scale = Vector3.ONE * (1.0 + (0.12 * (0.5 + 0.5 * sin(_t * 9.0)) if near else 0.0))
