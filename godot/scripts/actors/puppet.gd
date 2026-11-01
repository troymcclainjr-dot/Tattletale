class_name Puppet
extends RefCounted
## One clay person (the JS rig object from makePerson): pivot nodes posed every frame by
## pose(), placed by place(). Built by Cast from a GLB or the procedural fallback; the node
## names are the same either way (blender/README.md), so this code doesn't care which.

var id := ""
var g: Node3D                     # root: placed in the world
var legs: Array[Node3D] = []      # [LegR, LegL]  (JS legs[0] is the right leg, x = -0.085H)
var arms: Array[Node3D] = []      # [ArmR, ArmL]  (JS arms[0] is the right arm, x = -0.185H)
var hands: Array[Node3D] = []     # [HandR, HandL]
var body: Node3D
var head: Node3D
var mouth: Node3D
var H := 1.8
var hy := 0.0
var hs := 0.0
var talk := 0.0
var phase := 0.0
var body_y := 0.0
# accessories the game toggles (null if this character has none)
var bino: Node3D
var cup: Node3D
var donut: Node3D
var letter: Node3D
var pipe: Node3D
var ember: Array[StandardMaterial3D] = []
# lying down (Gary, Daddy): outer turns him along the ground, inner lays him on his back
var outer: Node3D
var inner: Node3D
# Daddy
var on := false
var awake := false
var fall := -1.0
var snd := false
var _crawl_support: Dictionary = {}
var _binocular_grips := PackedVector3Array()


## Look up the pivots by name and switch them to three.js rotation order.
func bind() -> void:
	var ctx := "characters/" + id
	legs = [Assets.need(g, "LegR", ctx), Assets.need(g, "LegL", ctx)]
	arms = [Assets.need(g, "ArmR", ctx), Assets.need(g, "ArmL", ctx)]
	hands = [Assets.need(g, "HandR", ctx), Assets.need(g, "HandL", ctx)]
	body = Assets.need(g, "Body", ctx)
	head = Assets.need(g, "Head", ctx)
	mouth = Assets.need(g, "Mouth", ctx)
	for n in [legs[0], legs[1], arms[0], arms[1], body, head]:
		n.rotation_order = EULER_ORDER_XYZ
	hs = 0.115 * H
	hy = 0.05 * H + hs
	# Authored anatomical exports keep nominal H but have a smaller adult head.
	# Read the baked landmark so vehicle occupant hit regions track the face.
	var rig := Assets.find(g, "Rig")
	# Godot preserves glTF custom properties in one metadata/extras dictionary.
	var landmarks: Dictionary = rig.get_meta("extras", {}) if rig != null else {}
	if landmarks.has("head_center_y"):
		hy = float(landmarks["head_center_y"])
		hs = float(landmarks.get("head_radius", hs))
	body_y = body.position.y if body.position.y > 0.0 else 0.47 * H


## pose(r,p) from characters.js. Arms as [forward-raise (negative = up/forward), outward];
## legs swing with the walk phase.
func pose(p: Dictionary) -> void:
	var walk: float = p.get("walk", 0.0)
	var sw := sin(phase) * walk if walk != 0.0 else 0.0
	legs[0].rotation = Vector3(sw, 0.0, 0.0)
	legs[1].rotation = Vector3(-sw, 0.0, 0.0)
	# Accessory contact fits may temporarily adjust longitudinal arm scale.
	# A normal pose always restores the authored proportions.
	arms[0].scale = Vector3.ONE
	arms[1].scale = Vector3.ONE
	var a_r = p.get("armR")
	var a_l = p.get("armL")
	if a_r == null:
		a_r = [-sw * 0.8, 0.08]
	if a_l == null:
		a_l = [sw * 0.8, 0.08]
	arms[0].rotation = Vector3(a_r[0], 0.0, -a_r[1])
	arms[1].rotation = Vector3(a_l[0], 0.0, a_l[1])
	body.rotation = Vector3(p.get("lean", 0.0), 0.0, p.get("tilt", 0.0))
	head.rotation = Vector3(p.get("nod", 0.0), p.get("look", 0.0), 0.0)
	body.position.y = body_y + p.get("bob", 0.0)
	var open: float = 0.35 + 0.65 * absf(sin(G.clock * 17.0 + H * 9.0)) if talk > 0.0 else p.get("mouth", 0.0)
	# the mouth is modeled open at scale 1 and squashed to 0.3 when shut
	mouth.scale.y = minf(1.0, 0.3 + open * 0.9)


func place(x: float, z: float, yaw: float, y = null) -> void:
	g.position = Vector3(x, World.ground_y(x, z) if y == null else float(y), z)
	g.rotation.y = yaw


## World position of a hand (held props, the squirrel).
func hand_pos(i: int) -> Vector3:
	return hands[i].global_position


## Reach the real binocular barrel sides, following current exported anatomy.
func pose_binoculars() -> void:
	pose({"armR": [-2.45, -.42], "armL": [-2.45, -.42]})
	if bino == null:
		return
	if _binocular_grips.is_empty():
		var points: Array[Vector3] = []
		_crawl_vertices(bino, Transform3D.IDENTITY, points)
		if points.is_empty():
			return
		var bounds := AABB(points[0], Vector3.ZERO)
		for point in points:
			bounds = bounds.expand(point)
		for i in 2:
			var outside := bounds.position.x - .008 * H if i == 0 else bounds.end.x + .008 * H
			_binocular_grips.append(Vector3(outside, bounds.position.y + bounds.size.y * .30, bounds.get_center().z))
	for i in 2:
		var arm := arms[i]
		var target: Vector3 = body.to_local(bino.to_global(_binocular_grips[i])) - arm.position
		var rest := hands[i].position
		var length_scale := sqrt(maxf(.000001, target.length_squared() - rest.x * rest.x - rest.z * rest.z)) / maxf(absf(rest.y), .0001)
		arm.scale = Vector3(1, length_scale, 1)
		arm.quaternion = Quaternion((rest * arm.scale).normalized(), target.normalized())


func binocular_grip_pos(i: int) -> Vector3:
	return bino.to_global(_binocular_grips[i])


## Ground the infant's real hands and feet after anatomical proportion changes.
## The rigid rig has no elbows/knees: fit a near-horizontal torso, then alternate
## the limbs a little around vertical. Only the lower support pair plants at each
## half-step; the opposite pair can lift naturally. No collision shapes change.
func crawl(cycle: float, ground_y: float) -> void:
	if _crawl_support.is_empty():
		for limb in arms + legs:
			var points: Array[Vector3] = []
			_crawl_vertices(limb, Transform3D.IDENTITY, points)
			var support: Array[Vector3] = []
			# A bounded support polygon of the actual limb, not its loose AABB.
			# Crawl rotates only about local X; yaw does not change world height.
			for step in 64:
				var angle := TAU * float(step) / 64.0
				var direction := Vector3(0, cos(angle), sin(angle))
				var best := Vector3.ZERO
				var distance := INF
				for point in points:
					var projected := point.dot(direction)
					if projected < distance:
						distance = projected
						best = point
				if not support.has(best):
					support.append(best)
			_crawl_support[limb] = support
	g.position.y = ground_y
	g.rotation.x = 1.15
	g.rotation.z = 0.0
	var swing := .18 * sin(cycle)
	# More forward torso pitch lowers the shoulder contact plane relative to hips.
	var low := 0.0
	var high := 1.0
	for iteration in 12:
		var lean := (low + high) * .5
		_crawl_pose(lean, swing)
		var hands_low := minf(_crawl_low(arms[0]), _crawl_low(arms[1]))
		var feet_low := minf(_crawl_low(legs[0]), _crawl_low(legs[1]))
		if hands_low > feet_low:
			low = lean
		else:
			high = lean
	_crawl_pose((low + high) * .5, swing)
	var contact := minf(minf(_crawl_low(arms[0]), _crawl_low(arms[1])), minf(_crawl_low(legs[0]), _crawl_low(legs[1])))
	g.position.y += ground_y - contact


func _crawl_pose(lean: float, swing: float) -> void:
	var vertical := -1.15 - lean
	pose({"lean": lean, "armR": [vertical + swing, 0.0], "armL": [vertical - swing, 0.0], "nod": vertical + .15})
	legs[0].rotation.x = -1.30 - swing
	legs[1].rotation.x = -1.30 + swing


func _crawl_low(limb: Node3D) -> float:
	var result := INF
	var transform := limb.global_transform
	for point in _crawl_support[limb]:
		result = minf(result, (transform * point).y)
	return result


func _crawl_vertices(node: Node3D, transform: Transform3D, points: Array[Vector3]) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			for point in arrays[Mesh.ARRAY_VERTEX]:
				points.append(transform * point)
	for child in node.get_children():
		if child is Node3D:
			_crawl_vertices(child, transform * child.transform, points)
