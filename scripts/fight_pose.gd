extends RefCounted
## How someone with his hands up is drawn (melee.gd calls this each frame, after he has been posed for standing).
##
## The arms are never bowed into a punch. Each hand has a place to be, measured from its shoulder, and the arm
## is the straight piece between the two: turned to point at the hand and made shorter or longer along its own
## length to reach it (paper_actor.gd's _reach_for, as for something held). Short, it reads as a bent arm seen
## end-on with the fist in front of it; long, as a straight one. So a punch is a hand going from one place to
## another, and nothing between can knot. A drawn fist (the one that holds the pistol) covers the arm's end.
##
## Side-on he stands as a boxer: feet apart, knees a little bent, both fists up (the far arm is the copy of the
## near one that comes out from behind his chest, as when he holds a rifle), and he bounces. He throws with the
## near arm and steps in with it; hit, he rocks back. Square to the camera (someone with no side drawing) both
## fists are up beside his chin and the one on the other man's side goes out to him.
##
## A pose is a Dictionary: "near" and "far" (where each hand is: x forward, y down, in lengths of the arm from
## shoulder to wrist), "to" and "reach" (the near hand is `reach` of the way, 0 .. 1, from "near" to "to", which
## is in metres: where a punch lands does not depend on how long his arm was drawn), "lean" (how far he tips
## forward: his card is sheared, so his feet stay flat on the floor), "step" (metres forward), "duck" (metres
## down, by his knees), "out" (0 .. 1: how far the punch is thrown, for the square-on drawing).

const GUARD_NEAR := Vector2(0.5, -0.3)        # the near fist by his chin
const GUARD_FAR := Vector2(0.85, -0.52)      # the far one out in front of his face, a little higher
const JAB_M := Vector2(0.47, -0.07)          # a jab at full reach, in METRES from his shoulder: straight out to the other man's chin. (His
                                             # arm is drawn as long as it takes: a short arm stretches, as a cartoon's does)
const BACK := Vector2(-0.12, 0.3)            # a hook drawn back: the fist by his hip, behind the line of his body
const HOOK_MID := Vector2(1.15, 0.5)         # ...it comes round low...
const HOOK_M := Vector2(0.45, -0.2)          # ...and ends high (metres), where the chin was
const FACE := 0.24                           # the front of the other man's face is this far from his middle, metres
const MOST := 3.6                            # an arm is drawn no longer than this many times its own length
const CURL := 0.22                           # every arm bowed this little, so a short one is not a stump
const STANCE := 0.035                        # each foot slid this far from where it was drawn, of the drawing's width
const KNEES := 0.0                           # his feet come up his drawing this much (and he comes down): knees bent. 0: on a raised floor (the
                                             # park's court) a card let down at all has its shoes cut off by the floor
const BOUNCE := 0.012                        # metres he bobs
const BOUNCE_RATE := 7.5                     # radians a second
const FIST_TURN := 0.6                       # radians: a fist is turned no further than this from level
const FRONT_GUARD := Vector2(0.3, -0.72)     # square on: each fist out from its shoulder this far, and up
const FRONT_OUT_M := Vector2(0.6, -0.05)     # ...and the one that is thrown, out to the side (metres)

static var _made := {}                       # actor: {"near": Node3D, "far": Node3D}, the fists drawn on him


static func guard() -> Dictionary:
	return {"near": GUARD_NEAR, "far": GUARD_FAR, "to": JAB_M, "reach": 0.0, "lean": 0.05, "step": 0.0, "duck": 0.0, "out": 0.0}


## A punch `t` seconds in: drawn back until `back`, there by `lands`, home by `over`.
static func punch(kind: String, t: float, back: float, lands: float, over: float) -> Dictionary:
	var pose := guard()
	var hook := kind == "hook"
	var pull := maxf(back, lands * (0.34 if hook else 0.18))       # a moment of drawing back even when none was asked for
	var held := 0.07 if hook else 0.05                              # it stays out this long: the moment that reads
	if t < pull:
		var k := _ease_out(t / maxf(pull, 0.001))
		if hook:
			pose["near"] = GUARD_NEAR.lerp(BACK, k)
			pose["lean"] = lerpf(0.05, -0.2, k)
			pose["step"] = -0.07 * k
			pose["duck"] = 0.03 * k
		else:
			pose["near"] = GUARD_NEAR.lerp(GUARD_NEAR + Vector2(-0.18, 0.05), k)
			pose["lean"] = lerpf(0.05, -0.04, k)
		pose["out"] = -k * (1.0 if hook else 0.4)
	elif t < lands + held:
		var k := clampf((t - pull) / maxf(lands - pull, 0.001), 0.0, 1.0)
		if hook:
			k = k * k                                               # it gathers speed
			pose["near"] = BACK.lerp(HOOK_MID, minf(k * 1.6, 1.0))   # round, low, not straight across...
			pose["to"] = HOOK_M
			pose["reach"] = smoothstep(0.35, 1.0, k)                 # ...and up to where it lands
			pose["lean"] = lerpf(-0.2, 0.3, k)
			pose["step"] = lerpf(-0.07, 0.25, k)
			pose["duck"] = lerpf(0.03, 0.0, k)
			pose["far"] = GUARD_FAR.lerp(GUARD_NEAR + Vector2(0.1, 0.05), k)     # the other hand comes home
		else:
			k = _ease_out(k)
			pose["near"] = GUARD_NEAR + Vector2(-0.18, 0.05)
			pose["reach"] = k
			pose["lean"] = lerpf(-0.04, 0.22, k)
			pose["step"] = 0.2 * k
		pose["out"] = k
	else:
		var k := _ease(clampf((t - lands - held) / maxf(over - lands - held, 0.001), 0.0, 1.0))
		pose["to"] = HOOK_M if hook else JAB_M
		pose["reach"] = 1.0 - k
		pose["lean"] = lerpf(0.3 if hook else 0.22, 0.05, k)
		pose["step"] = lerpf(0.25 if hook else 0.2, 0.0, k)
		if hook:
			pose["far"] = (GUARD_NEAR + Vector2(0.1, 0.05)).lerp(GUARD_FAR, k)
		pose["out"] = 1.0 - k
	return pose


## The fist held back, waiting to be let go (the lead holding the button down).
static func drawn() -> Dictionary:
	var pose := guard()
	pose["near"] = BACK
	pose["lean"] = -0.2
	pose["step"] = -0.07
	pose["duck"] = 0.03
	pose["out"] = -1.0
	return pose


## A slip: `k` 0 .. 1 .. 0 through it. Down and back, hands kept up.
static func slip(k: float) -> Dictionary:
	var pose := guard()
	pose["lean"] = -0.3 * k
	pose["step"] = -0.1 * k
	pose["duck"] = 0.16 * k
	pose["near"] = GUARD_NEAR + Vector2(-0.08, 0.1) * k
	pose["far"] = GUARD_FAR + Vector2(-0.2, 0.12) * k
	return pose


## Rocked by a punch: `k` 1 the moment it lands .. 0 over it; `hard` 0 .. 1 (a jab on raised hands is soft).
static func rock(pose: Dictionary, k: float, hard: float) -> Dictionary:
	if k <= 0.0:
		return pose
	var j := k * k * (0.45 + 0.55 * hard)
	pose["lean"] = float(pose["lean"]) - 0.34 * j
	pose["step"] = float(pose["step"]) - 0.14 * j
	pose["reach"] = float(pose["reach"]) * (1.0 - j)
	pose["near"] = (pose["near"] as Vector2) + Vector2(-0.15, 0.22) * j
	pose["far"] = (pose["far"] as Vector2) + Vector2(-0.3, 0.3) * j
	return pose


static func _ease_out(k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	return 1.0 - (1.0 - k) * (1.0 - k) * (1.0 - k)


static func _ease(k: float) -> float:
	return smoothstep(0.0, 1.0, k)


## Draw `a` in `pose`. `toward`: which way across the screen the other man is (for someone square to the camera).
## `clock`: seconds, for the bounce. `gap`: metres to the other man's middle: a punch is thrown to where his face
## is, however wide the man throwing it (measured from his own shoulder, a fat man's fist stopped at his belly).
static func apply(a: Node3D, pose: Dictionary, toward: float, clock: float, gap := 1.2) -> void:
	if a.fallen > 0.0 or a.weapon != "" or not a._arms.has("l") or a.view == "back":      # (from behind his fists are in front of him, out of sight)
		release(a)
		return
	var fists: Dictionary = _fists(a)
	var bob := BOUNCE * (0.5 + 0.5 * sin(clock * BOUNCE_RATE + float(a.get_instance_id() % 7)))
	var legs: bool = a._views[a.view]["limbs"] != null
	var px: Vector2 = a._px
	var m: float = a.height / px.y
	a._bend = a.ARM_BEND_HELD
	a._put("arm_reach", a._bend)
	a._put("arm_joint", a.ARM_JOINT_HELD)
	a._put("arm_l_hand", 9.0)
	a._put("arm_r_hand", 9.0)
	a._put("arm_elbow", Vector2.ZERO)
	if a.view == "side":
		var arm: Dictionary = a._arms["l"]
		var pivot := Vector2(arm["pivot"][0], arm["pivot"][1])
		var shoulder: Vector2 = pivot + a._arm_from
		var axis := (Vector2(arm["wrist"][0], arm["wrist"][1]) - pivot).normalized()
		var wrist := float(arm["wrist_r"])
		var length := float(arm["len"])
		var hand := wrist + 0.25 * (length - wrist)
		# The near arm.
		var aim: Vector2 = pose["to"]
		var up := (px.y - shoulder.y) * m - aim.y                  # how high the fist ends, metres
		aim.x = clampf(gap - FACE - float(pose["step"]) - tan(float(pose["lean"])) * up - (shoulder.x - px.x * 0.5) * m, 0.3, 1.2)
		var want: Vector2 = ((pose["near"] as Vector2) * wrist).lerp(aim / m, float(pose["reach"]))
		var bow := CURL * (1.0 - float(pose["reach"]))             # thrown, it is straight
		var reach: Vector2 = a._reach_for(axis, hand / px.y, length / px.y, want / px.y, bow, MOST)
		a._put("arm_l_angle", reach.x)
		a._put("arm_l_curl", bow)
		a._put("arm_l_stretch", reach.y)
		a._put("arm_l_cut", (wrist + a.FIST_IN / maxf(reach.y, 1.0)) / px.y)
		var at: Vector2 = shoulder + a._hand_at(axis, hand / px.y, length / px.y, reach.x, bow, reach.y) * px.y
		_place(fists["near"], at, want, px, m, a.FIST_NEAR)
		# The far arm: a copy of it, from behind his chest.
		var far := Vector2(0.4, 0.1) * wrist
		var want2: Vector2 = (pose["far"] as Vector2) * wrist
		var reach2: Vector2 = a._reach_for(axis, hand / px.y, length / px.y, want2 / px.y, CURL, 3.2)
		a._put("far_arm_copy", true)
		a._put("far_arm_shift", far / px)
		a._put("arm_r_angle", reach2.x)
		a._put("arm_r_curl", CURL)
		a._put("arm_r_stretch", reach2.y)
		a._put("arm_r_cut", (wrist + a.FIST_IN / maxf(reach2.y, 1.0)) / px.y)
		var at2: Vector2 = shoulder + far + a._hand_at(axis, hand / px.y, length / px.y, reach2.x, CURL, reach2.y) * px.y
		_place(fists["far"], at2, want2, px, m, -0.02)
		_body(a, float(pose["lean"]), float(pose["step"]), float(pose["duck"]), bob, legs)
		if legs:      # a boxer's feet: one forward, one back
			a._put("swing_l", STANCE + float(pose["step"]) * 0.12)
			a._put("swing_r", -STANCE)
		return
	if not a._arms.has("r"):
		release(a)
		return
	# Square to the camera: a fist each side of his chin; the one on the other man's side is the one he throws.
	var out := clampf(float(pose["out"]), 0.0, 1.0)
	var pulled := clampf(-float(pose["out"]), 0.0, 1.0)
	for side: String in ["l", "r"]:
		var arm: Dictionary = a._arms[side]
		var pivot := Vector2(arm["pivot"][0], arm["pivot"][1])
		var axis := (Vector2(arm["wrist"][0], arm["wrist"][1]) - pivot).normalized()
		var wrist := float(arm["wrist_r"])
		var length := float(arm["len"])
		var hand := wrist + 0.25 * (length - wrist)
		var way := -1.0 if side == "l" else 1.0                 # this arm is on that side of the picture
		var throws := way == (1.0 if toward >= 0.0 else -1.0)
		var spot := Vector2(FRONT_GUARD.x * way, FRONT_GUARD.y)
		if throws:
			spot += Vector2(-0.25 * way, 0.3) * pulled
		var want: Vector2 = spot * wrist
		if throws:
			var up := (px.y - pivot.y) * m - FRONT_OUT_M.y
			var across := way * (gap - FACE) - way * float(pose["step"]) - tan(way * float(pose["lean"]) * 0.8) * up      # where the fist ends, from his middle
			var reach_m := clampf(way * (across - (pivot.x - px.x * 0.5) * m), 0.3, 1.2)
			want = want.lerp(Vector2(reach_m * way, FRONT_OUT_M.y) / m, out)
		var bow := -CURL * way * (1.0 - out if throws else 1.0)
		var reach: Vector2 = a._reach_for(axis, hand / px.y, length / px.y, want / px.y, bow, MOST)
		var pre := "arm_%s_" % side
		a._put(pre + "angle", reach.x)
		a._put(pre + "curl", bow)
		a._put(pre + "stretch", reach.y)
		a._put(pre + "cut", (wrist + a.FIST_IN / maxf(reach.y, 1.0)) / px.y)
		var at: Vector2 = pivot + (a._arm_from if side == "l" else Vector2.ZERO) + a._hand_at(axis, hand / px.y, length / px.y, reach.x, bow, reach.y) * px.y
		_place(fists["near" if side == "l" else "far"], at, want, px, m, a.FIST_NEAR, way < 0.0)
	a._put("far_arm_copy", false)
	var to := 1.0 if toward >= 0.0 else -1.0
	_body(a, to * float(pose["lean"]) * 0.8, to * float(pose["step"]), float(pose["duck"]), bob, legs)


## His card for this frame: sheared forward by `lean` (so his head goes that way and his feet stay flat where
## they are), moved `step` metres, and let down by his knees: `duck` metres, on top of a fighter's bent knees.
static func _body(a: Node3D, lean: float, step: float, duck: float, bob: float, legs: bool) -> void:
	a._card.basis = Basis(Vector3.RIGHT, Vector3(tan(clampf(lean, -0.6, 0.6)), 1.0, 0.0), Vector3.BACK)
	a._card.position.x = step
	if legs:
		var hip := float(a._mat.get_shader_parameter("hip_v"))
		var knee := float(a._mat.get_shader_parameter("knee_v"))
		var lift := minf(KNEES + maxf(duck - bob, 0.0) / a.height, minf(0.14, 0.8 * maxf(knee - hip, 0.0)))
		a._put("lift_l", lift)
		a._put("lift_r", lift)
		a._card.position.y = -lift * a.height
	else:
		a._card.position.y = bob - duck


## He is not fighting any more: his fists are taken off him and his card goes back where it was. (His arms and
## legs are put back by paper_actor.gd, which poses him afresh every frame.)
static func release(a: Node3D) -> void:
	if not _made.has(a):
		return
	for key: String in _made[a]:
		var node: Node3D = _made[a][key]
		if is_instance_valid(node):
			node.queue_free()
	_made.erase(a)
	if is_instance_valid(a):
		a._card.position.x = 0.0
		a._card.basis = Basis()
		a._put("far_arm_copy", false)
		a._put("arm_l_cut", 9.0)
		a._put("arm_r_cut", 9.0)
		a._put("arm_l_stretch", 1.0)
		a._put("arm_r_stretch", 1.0)


## Everyone's fists off (the place is left, the game is closing).
static func release_all() -> void:
	for a: Variant in _made.keys():
		if is_instance_valid(a):
			release(a)
	_made.clear()


static func _fists(a: Node3D) -> Dictionary:
	if _made.has(a) and is_instance_valid(_made[a]["near"]):
		return _made[a]
	var info: Dictionary = a.weapons().get("weapons", {}).get("pistol", {})
	var arm: Dictionary = a._arms["l"]
	var m: float = a.height / a._px.y
	var unit := clampf(float(arm["width"]) * m / a.LEAD_ARM, 0.8, 1.3) / float(a.weapons()["px_per_m"])
	var size := Vector2(float(info["w"]), float(info["h"]))
	var grip := Vector2(float(info["grip"][0]), float(info["grip"][1]))
	var out := {}
	for key: String in ["near", "far"]:
		var holder := Node3D.new()
		holder.name = "Fist_" + key
		a._card.add_child(holder)
		var card := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = size * unit
		quad.center_offset = Vector3(-(grip.x - size.x * 0.5) * unit, (grip.y - size.y * 0.5) * unit, 0.0)
		card.mesh = quad
		var mat := ShaderMaterial.new()
		mat.shader = a.PROP_SHADER
		mat.set_shader_parameter("art", load(a.WEAPONS + String(info["hands"])))
		mat.set_shader_parameter("tint", a.skin())
		card.material_override = mat
		holder.add_child(card)
		out[key] = holder
	_made[a] = out
	return out


## A fist at `at` (pixels of his drawing), turned the way its arm runs (`along`: from the shoulder, y down).
static func _place(holder: Node3D, at: Vector2, along: Vector2, px: Vector2, m: float, toward: float, mirrored := false) -> void:
	holder.position = Vector3((at.x - px.x * 0.5) * m, (px.y - at.y) * m, 0.0)
	holder.rotation.z = clampf(atan2(-along.y, absf(along.x)), -FIST_TURN, FIST_TURN) * (-1.0 if mirrored else 1.0)
	holder.scale = Vector3(-1.0 if mirrored else 1.0, 1.0, 1.0)
	((holder.get_child(0) as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("toward", toward)


## The burst where a punch lands: a white flash and spokes, gone in a moment. `at` in the world; `hard` 0 .. 1.
static func burst(parent: Node3D, at: Vector3, face: Basis, hard: float) -> void:
	var g := Node3D.new()
	parent.add_child(g)
	g.global_position = at
	g.global_basis = face
	var white := StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.albedo_color = Color(1.0, 1.0, 0.94)
	white.no_depth_test = true
	var gold := white.duplicate() as StandardMaterial3D
	gold.albedo_color = Color(1.0, 0.82, 0.2)
	var size := 0.2 + 0.16 * hard
	var n := 7 if hard > 0.5 else 5
	for i in n:
		var spoke := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(size * (0.9 if i % 2 == 0 else 0.6), 0.035, 0.004)
		spoke.mesh = box
		spoke.material_override = white if i % 2 == 0 else gold
		var turn := TAU * i / n + 0.3
		spoke.rotation.z = turn
		spoke.position = Vector3(cos(turn), sin(turn), 0.0) * size * 0.75 + Vector3(0, 0, 0.05)
		g.add_child(spoke)
	var core := MeshInstance3D.new()
	var disc := QuadMesh.new()
	disc.size = Vector2(size, size) * 0.7
	core.mesh = disc
	core.material_override = white
	core.rotation.z = PI * 0.25
	core.position.z = 0.05
	g.add_child(core)
	g.scale = Vector3.ONE * 0.5
	var tween := g.create_tween()
	tween.tween_property(g, "scale", Vector3.ONE * 1.25, 0.09).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(g, "scale", Vector3.ONE * 0.2, 0.06)
	tween.tween_callback(g.queue_free)
