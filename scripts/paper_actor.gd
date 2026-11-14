extends Node3D
## A flat paper character: a drawing on a card that always shows its face to the
## camera. It can have up to three drawings (front, side, back); it shows the one
## that matches the way it is walking, and the side drawing is mirrored to walk
## left. Changing drawing flips the card over like a sheet of paper. The limbs
## are moved inside the drawing by shaders/paper_card.gdshader: legs step, arms
## swing, the body bobs. The drawing is unlit so it reads anywhere; a soft blob
## underneath ties it to the floor.

const PaperFace := preload("res://scripts/paper_face.gd")
const CARD_SHADER := preload("res://shaders/paper_card.gdshader")

const WALK_SPEED := 1.9
const FLIP_TIME := 0.16
const RADIUS := 0.26          # how close its middle may come to a wall or a prop in front of it or behind it
const REACH := 0.4            # and to one beside it: the lead's hands and feet reach this far across the card
const PULL := 0.5             # an open doorway this close to where he is pushing at a wall draws him into line with it
const STEP_RATE := 9.0        # radians of walk cycle per second; two steps per turn
const BEAT := 60.0 / 92.0     # seconds: the tempo he performs to at a microphone
const ARM_ROOM := 0.45        # the card is this much wider than the drawing at each side, so a raised arm is not cut off

## Something the player can use, like a door: with a name set, E talks to it.
signal used(by: Node3D)

var display_name := ""
var use_reach := 1.6        # metres: talking distance
var height := 1.8
var areas: Array = [Rect2(-1.0, -1.0, 2.0, 2.0)]   # Rect2 in x, z: where its middle may be (rooms, open doorways)
var obstacles: Array = []                        # Rect2 in x, z: props it must walk round
var others: Array = []                           # other paper actors it must walk round
var speed := 1.0                                 # 1 walks at WALK_SPEED; above 1 the steps come faster to match
var performing := false                          # at a microphone: he bobs to the beat and his arms work (_perform_pose)
var reach := REACH                               # how far the drawing reaches either side of its middle, metres
var face: Node3D            # the loose face parts, or null when the drawing has its face baked in
var view := "front"         # the drawing on show

var _pivot: Node3D
var _card: MeshInstance3D
var _mat: ShaderMaterial
var _views := {}            # name: {"art": Texture2D, "limbs": Texture2D or null, "data": Dictionary}
var _want_view := "front"
var _want_yaw := 0.0        # 0 = as drawn, PI = mirrored
var _yaw := 0.0
var _phase := 0.0
var _gait := 0.0            # 0 standing .. 1 walking; eases, so limbs settle and do not snap
var _groove := 0.0          # 0 still .. 1 performing; eases the same way
var _beat := 0.0            # beats since he started performing
var _stride := 0.0          # side view: how far the feet are apart as drawn, as a fraction of the drawing's height
var _arm_rest := 0.0        # how far the near arm is turned to hang straight in this drawing


func _init() -> void:
	var shadow := MeshInstance3D.new()
	var blob := CylinderMesh.new()
	blob.top_radius = 0.36
	blob.bottom_radius = 0.36
	blob.height = 0.004
	blob.radial_segments = 14
	blob.rings = 0
	shadow.mesh = blob
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.05, 0.02, 0.08, 0.38)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow.material_override = sm
	shadow.position.y = 0.02
	shadow.scale = Vector3(1.0, 1.0, 0.45)
	add_child(shadow)

	_pivot = Node3D.new()
	add_child(_pivot)
	_card = MeshInstance3D.new()
	_mat = ShaderMaterial.new()
	_mat.shader = CARD_SHADER
	_card.material_override = _mat
	_pivot.add_child(_card)


## Put a single drawing on the card. Its feet must touch the bottom edge of the image.
func set_art(texture: Texture2D) -> void:
	_clear()
	_views = {"front": {"art": texture, "limbs": null, "data": {}}}
	_show("front")


## Put a rigged character on the card: a drawing for each way it can face, each
## with a blank face, plus loose eyes, brows and mouth. `dir` holds rig.json.
func set_rig(dir: String) -> bool:
	var rig = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("rig.json")))
	if typeof(rig) != TYPE_DICTIONARY:
		push_warning("Could not read %s" % dir.path_join("rig.json"))
		return false
	_clear()
	height = float(rig["height_m"])
	for name: String in rig["views"]:
		var data: Dictionary = rig["views"][name]
		_views[name] = {"art": load(dir.path_join(data["art"])), "limbs": load(dir.path_join(data["limbs"])), "data": data}
		_views[name]["legs"] = load(dir.path_join(data["legs"]))
		if data.has("arm_art"):      # this drawing has no arms: they are taken from another one
			_views[name]["arm_art"] = load(dir.path_join(data["arm_art"]))
	var body: Texture2D = _views["front"]["art"]
	face = PaperFace.new()
	face.name = "Face"
	_card.add_child(face)
	face.setup(dir, rig, height, Vector2(body.get_size()))
	_show("front")
	return true


func use_name() -> String:
	return display_name


func use_spot() -> Vector3:
	return position


func label_spot() -> Vector3:
	return position + Vector3(0, height + 0.2, 0)


func use(by: Node3D = null) -> void:
	used.emit(by)


## Turn side-on to face left or right on screen without walking (to talk to someone).
func face_side(screen_x: float) -> void:
	if _views.has("side"):
		_want_view = "side"
	_want_yaw = 0.0 if screen_x >= 0.0 else PI


## Make sure his face can be seen (for talking): if he has his back to the
## camera he turns round. Takes one paper flip.
func show_face() -> void:
	if not _views[_want_view]["data"].has("face"):
		_want_view = "front"
		_want_yaw = 0.0


## Walk in a direction on the floor (x, z in metres). `screen` is the same
## direction as it looks on screen (x right, y towards the viewer); it picks the
## drawing. The node's own yaw is set by the scene so the card faces the camera.
func walk(dir: Vector2, screen: Vector2, delta: float) -> void:
	var moving := dir.length() > 0.01
	if moving:
		_step(dir.limit_length(1.0) * WALK_SPEED * speed * delta)
		_phase += delta * STEP_RATE * maxf(speed, 1.0)
		if _views.has("side") and absf(screen.x) >= absf(screen.y) * 0.7:
			_want_view = "side"
			_want_yaw = 0.0 if screen.x > 0.0 else PI
		elif _views.has("back") and screen.y < 0.0:
			_want_view = "back"
			_want_yaw = 0.0
		elif _views.size() > 1:
			_want_view = "front"
			_want_yaw = 0.0
		elif absf(screen.x) > 0.1:      # one drawing only: mirror it to walk left
			_want_yaw = 0.0 if screen.x > 0.0 else PI
	_gait = move_toward(_gait, 1.0 if moving else 0.0, delta * 7.0)
	if _gait == 0.0:
		_phase = 0.0
	if performing:
		_want_view = "front"
		_want_yaw = 0.0
	_groove = move_toward(_groove, 1.0 if performing and not moving else 0.0, delta * 2.5)
	_beat = _beat + delta / BEAT if _groove > 0.0 else 0.0

	# Changing drawing: turn the card edge-on, swap, turn back.
	var aim := _want_yaw if view == _want_view else PI * 0.5
	_yaw = move_toward(_yaw, aim, PI * delta / FLIP_TIME)
	if view != _want_view and is_equal_approx(_yaw, PI * 0.5):
		_show(_want_view)
	_pivot.rotation.y = _yaw
	if face:
		face.set_side(1.0 if cos(_yaw) >= 0.0 else -1.0)
	_pose()


## Where the limbs are at this point of the walk cycle.
func _pose() -> void:
	var s := sin(_phase)
	var g := _gait
	if view == "side":
		# He is drawn mid-stride, one leg back and one forward. The drawing has
		# a back leg and a front leg, and they never swap sides (crossing them
		# over tangles the jeans). A step is: the two close together under him,
		# then open again. What changes is which leg is which. The leg coming
		# forward starts as the back one with its foot lifted; as the two meet,
		# one hidden behind the other, it becomes the front one and comes down.
		# Both legs stay the colour they were drawn (shading the far one read
		# as the trouser bottoms changing colour mid-stride).
		var step := fposmod(_phase, PI)                     # 0 feet apart .. PI/2 together .. PI apart
		var passed := step >= PI * 0.5
		var far_goes := int(floor(_phase / PI)) % 2 == 0    # this step the far leg comes forward; next step the near one
		var together := sin(step) * sin(step) * g
		var lift := 0.045 * sin(step) * g
		_mat.set_shader_parameter("swing_l", _stride * 0.5 * together)
		_mat.set_shader_parameter("swing_r", -_stride * 0.5 * together)
		_mat.set_shader_parameter("lift_l", 0.0 if passed else lift)
		_mat.set_shader_parameter("lift_r", lift if passed else 0.0)
		_mat.set_shader_parameter("near_leg_right", far_goes != passed)
		_mat.set_shader_parameter("far_leg_shade", 1.0)
		_mat.set_shader_parameter("leg_ink", 0.006 * g)
		_mat.set_shader_parameter("arm_l_angle", _arm_rest - 0.5 * cos(_phase) * g)
		_mat.set_shader_parameter("arm_r_angle", 0.0)
		_card.position.y = 0.035 * together                 # highest as the legs pass
		_card.rotation.z = -0.045 * g                       # lean into the walk
	else:
		# Seen from the front or back the feet lift in turn and the body rocks over the planted one.
		_mat.set_shader_parameter("swing_l", 0.0)
		_mat.set_shader_parameter("swing_r", 0.0)
		_mat.set_shader_parameter("far_leg_shade", 1.0)
		_mat.set_shader_parameter("leg_ink", 0.0)
		_mat.set_shader_parameter("lift_l", 0.045 * maxf(s, 0.0) * g)
		_mat.set_shader_parameter("lift_r", 0.045 * maxf(-s, 0.0) * g)
		_mat.set_shader_parameter("arm_l_angle", 0.2 * s * g)
		_mat.set_shader_parameter("arm_r_angle", 0.2 * s * g)
		_card.position.y = 0.045 * absf(s) * g
		_card.rotation.z = 0.045 * s * g
		if _groove > 0.0:
			_perform_pose()


## At a microphone, feeling it. His knees dip on every beat (both boots
## come up the card and the card comes down by as much, so his feet stay on
## the floor and the rest of him drops), he rocks from foot to foot over two
## beats, and his arms work: one hand up high, chopping at the beat, the
## other lower and catching the off-beat. Every eight beats they change over.
func _perform_pose() -> void:
	var k := _groove
	var hit := pow(0.5 + 0.5 * cos(TAU * _beat), 2.0)               # 1 on the beat, falling away fast
	var off := pow(0.5 + 0.5 * cos(TAU * (_beat + 0.5)), 2.0)       # the same on the off-beat
	var dip := 0.034 * hit * k                                        # as a fraction of the drawing's height
	_mat.set_shader_parameter("lift_l", dip)
	_mat.set_shader_parameter("lift_r", dip)
	_card.position.y = -dip * height
	_card.rotation.z = 0.04 * sin(PI * _beat) * k
	var lead := smoothstep(-0.35, 0.35, sin(TAU * _beat / 16.0))     # 1: the arm on the left of the picture is the high one
	var high := 1.5 + 0.65 * hit + 0.12 * sin(TAU * _beat * 2.0)
	var low := 0.5 + 0.4 * off
	_mat.set_shader_parameter("arm_l_angle", -lerpf(low, high, lead) * k)
	_mat.set_shader_parameter("arm_r_angle", lerpf(low, high, 1.0 - lead) * k)


## Move by a step, sliding along walls and props instead of stopping dead.
func _step(by: Vector2) -> void:
	var at := Vector2(position.x, position.z)
	var start := at
	var stuck_x := by.x != 0.0 and _blocked(Vector2(at.x + by.x, at.y))
	if not stuck_x:
		at.x += by.x
	var stuck_z := by.y != 0.0 and _blocked(Vector2(at.x, at.y + by.y))
	if not stuck_z:
		at.y += by.y
	elif not stuck_x and by.x != 0.0:
		# Sliding along a wall he may pass a doorway narrower than this one
		# step (a slow frame): look for it along the way rather than skip it.
		var n := int(ceil(absf(by.x) / 0.03))
		for i in range(1, n):
			var x := at.x - by.x * float(i) / float(n)
			if not _blocked(Vector2(x, at.y + by.y)):
				at = Vector2(x, at.y + by.y)
				break
	# Doorways are only a little wider than he is, so the strip his middle may
	# walk down is narrow. Walking along a wall he slides into it. Walking
	# mostly AT a wall with a doorway just to one side, he is drawn over into
	# line with it instead of sliding off the other way: push at a door and
	# you go through it.
	if stuck_z and absf(by.y) >= absf(by.x):
		if not _blocked(Vector2(start.x, start.y + by.y)):
			at = Vector2(start.x, start.y + by.y)      # in line with it already: go through, do not slide off
		else:
			var x := _line_up(start, Vector2(start.x, start.y + by.y), 0, by.length())
			if x != start.x:
				at.x = x
	elif stuck_x and absf(by.x) >= absf(by.y):
		if not _blocked(Vector2(start.x + by.x, start.y)):
			at = Vector2(start.x + by.x, start.y)
		else:
			var z := _line_up(start, Vector2(start.x + by.x, start.y), 1, by.length())
			if z != start.y:
				at.y = z
	position.x = at.x
	position.z = at.y


## He is at `at` and cannot step to `want`. If some floor he may stand on lies
## at `want` but a little to one side (along `axis`: 0 is x, 1 is z), take a
## step that way. Returns where he should be along that axis.
func _line_up(at: Vector2, want: Vector2, axis: int, step: float) -> float:
	var other := 1 - axis
	var best := INF
	var goal: float = at[axis]
	for area: Rect2 in areas:
		if want[other] < area.position[other] or want[other] > area.end[other]:
			continue
		var gap := 0.0
		var to: float = at[axis]
		if at[axis] < area.position[axis]:
			gap = area.position[axis] - at[axis]
			to = area.position[axis] + 0.002
		elif at[axis] > area.end[axis]:
			gap = at[axis] - area.end[axis]
			to = area.end[axis] - 0.002
		else:
			continue      # already in line with it: something else is in the way
		if gap <= PULL and gap < best:
			best = gap
			goal = to
	if best == INF:
		return at[axis]
	var p := at
	p[axis] = move_toward(at[axis], goal, step)
	return at[axis] if _blocked(p) else p[axis]


func _blocked(p: Vector2) -> bool:
	if not _on_floor(p):
		return true
	for prop: Rect2 in obstacles:
		if prop.grow_individual(reach, RADIUS, reach, RADIUS).has_point(p):
			return true
	for other: Node3D in others:
		# Someone standing in the way blocks a step towards them, never a step away.
		var gap := Vector2(other.position.x, other.position.z) - p
		if gap.length() < RADIUS * 2.0 and gap.length() < (Vector2(other.position.x, other.position.z) - Vector2(position.x, position.z)).length():
			return true
	return false


## True if this spot on the floor is clear of walls and props (others are not counted).
func can_stand(p: Vector2) -> bool:
	if not _on_floor(p):
		return false
	for prop: Rect2 in obstacles:
		if prop.grow_individual(reach, RADIUS, reach, RADIUS).has_point(p):
			return false
	return true


func _on_floor(p: Vector2) -> bool:
	for area: Rect2 in areas:
		if area.has_point(p):
			return true
	return false


func _clear() -> void:
	if face:
		face.queue_free()
		face = null
	_views = {}


## Put one of the drawings on the card.
func _show(wanted: String) -> void:
	view = wanted
	_want_view = wanted
	var v: Dictionary = _views[wanted]
	var art: Texture2D = v["art"]
	var data: Dictionary = v["data"]
	var px := Vector2(art.get_size())
	var quad := QuadMesh.new()
	quad.size = Vector2(height * px.x / px.y * (1.0 + 2.0 * ARM_ROOM), height)
	quad.center_offset = Vector3(0, height * 0.5, 0)
	_card.mesh = quad
	_mat.set_shader_parameter("art", art)
	_mat.set_shader_parameter("aspect", px.x / px.y)
	_mat.set_shader_parameter("pad", ARM_ROOM)
	_mat.set_shader_parameter("has_limbs", v["limbs"] != null)
	_mat.set_shader_parameter("far_arm_hidden", bool(data.get("far_arm_hidden", false)))
	_mat.set_shader_parameter("arm_art", v.get("arm_art", art))
	_mat.set_shader_parameter("arms_drawn_here", not v.has("arm_art"))
	var shift: Array = data.get("arm_l_shift", [0.0, 0.0])
	_mat.set_shader_parameter("arm_l_shift", Vector2(float(shift[0]), float(shift[1])) / px)
	_mat.set_shader_parameter("arm_l_top", float(data.get("arm_l_top", 0.0)) / px.y)
	_arm_rest = float(data.get("arm_l_rest", 0.0))
	if v["limbs"] != null:
		_mat.set_shader_parameter("limbs", v["limbs"])
		_mat.set_shader_parameter("arm_l_pivot", Vector2(data["arm_l"][0], data["arm_l"][1]) / px)
		_mat.set_shader_parameter("arm_r_pivot", Vector2(data["arm_r"][0], data["arm_r"][1]) / px)
	# A drawing with no rig keeps its legs still: a hip line below the picture moves nothing.
	_mat.set_shader_parameter("hip_v", float(data.get("hip", px.y * 2.0)) / px.y)
	_mat.set_shader_parameter("knee_v", float(data.get("knee", px.y * 3.0)) / px.y)
	if v.has("legs"):
		_mat.set_shader_parameter("legs", v["legs"])
	_stride = float(data.get("stride", 0.0)) / px.y
	_mat.set_shader_parameter("arm_ink", float(data.get("arm_ink", 0.0)) / px.y)
	if face:
		face.visible = data.has("face")
		if data.has("face"):
			face.set_layout(data["face"], art)
