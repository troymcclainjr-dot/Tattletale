extends Node3D
## Speed lines and dust for a paper character at a sprint. paper_actor.gd gives every character one
## and calls `tick` from `walk` each frame; below a sprint nothing shows and nothing is made.
##
## Flat, inked and cheap (shaders/speed_lines.gdshader). Side-on, a few tapered ink strokes trail
## behind him the way he came, on a card just behind his own, redrawn a dozen times a second (like
## drawings on twos) so they flicker as cartoon speed lines do. At every step, in every view, a puff
## of dust is kicked up where his foot leaves the ground: a small inked cloud that stays where it was
## kicked (so it falls behind him, or comes towards us as he runs away, though never over him), swells
## and fades in a third of a second. Running at the camera or away from it there are only the puffs: a stroke along the way
## he runs would be a dot, and strokes standing off his sides (a comic's zoom lines, tried) read as a
## start of fright, not as speed.

const SHADER := preload("res://shaders/speed_lines.gdshader")
const SHOW := 0.6                        # the run (0 walking .. 1 flat out) they start to show at; all there at 1
const BOIL := 0.08                       # seconds between redrawings of the strokes
const CARD := Vector2(3.4, 2.4)          # metres: the card the strokes are drawn on, its foot FOOT below his
const FOOT := 0.2
const LINES := [[0.78, 0.43, 0.6], [0.53, 0.26, 0.8], [0.3, 0.4, 0.56]]    # side-on, each stroke: height (of his), start behind his leaning middle, length (metres)
const LINE_W := 0.017                    # metres: half the width of a stroke at its thick end
const HALO := 0.007                      # metres: the pale edge round it, so it shows on a dark ground too
const PUFF_LIFE := 0.34                  # seconds
const PUFF := 0.105                      # metres: half the size of a new puff (it swells to nearly twice that)
const PUFFS := 4
const LEAD := 1.55                       # the lead's height: everything is sized to the character against it

var _card: MeshInstance3D
var _mat: ShaderMaterial
var _puffs: Array = []                   # each {"node", "mat", "age", "at", "drift"}
var _boil := 0.0
var _jitter: Array = []                  # this drawing's random numbers, three for each stroke
var _shown := 0.0
var _phase := 0.0
var _flip := 1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 1114          # the same flicker every run, so two pictures of a sprint can be compared


## Each frame he walks. `run`: 0 walking .. 1 flat out; `yaw` his card's turn (PI: mirrored, facing left);
## `dir` the way he goes on the floor (x, z), `screen` the same on screen (x right, y towards us);
## `phase` his walk cycle; `tall` his height; `lean` how far his card leans forward from his feet (radians).
func tick(delta: float, run: float, view: String, yaw: float, dir: Vector2, screen: Vector2, phase: float, tall: float, lean: float) -> void:
	var moving := dir.length() > 0.01
	_shown = move_toward(_shown, smoothstep(SHOW, 1.0, run) if moving else 0.0, delta * 5.0)
	var k := tall / LEAD
	var facing := 1.0 if cos(yaw) >= 0.0 else -1.0
	if _shown > 0.0 and view == "side":
		_draw_strokes(delta, k, tall, facing, screen, lean)
	elif _card:
		_card.visible = false
	# A puff each time a foot leaves the ground: twice a cycle. Running away, it is kicked back towards us.
	if moving and _shown > 0.3 and int(floor(phase / PI)) != int(floor(_phase / PI)):
		var x := -facing * 0.19 * k if view == "side" else (-0.17 if int(floor(phase / PI)) % 2 == 0 else 0.17) * k
		_kick(Vector3(x, PUFF * k * 0.62, 0.04 if view == "back" else -0.04), Vector3(-dir.x, 0.0, -dir.y), k)
	_phase = phase
	var cam := get_viewport().get_camera_3d()
	for puff: Dictionary in _puffs:
		if puff["age"] >= 1.0:
			continue
		puff["age"] = minf(float(puff["age"]) + delta / PUFF_LIFE, 1.0)
		puff["at"] += (puff["drift"] as Vector3) * delta
		var node: MeshInstance3D = puff["node"]
		node.visible = puff["age"] < 1.0
		var s: float = 2.0 * PUFF * float(puff["k"]) * (1.0 + 0.85 * sqrt(float(puff["age"])))
		var b := global_transform.basis.orthonormalized()         # it faces the camera, as he does
		var at: Vector3 = puff["at"]
		if cam and cam.projection == Camera3D.PROJECTION_PERSPECTIVE:
			# Running away from us he leaves it nearer us than he is, and it would be drawn over his feet. It is
			# pushed back along the line of sight to just behind him, as big on the screen and in the same place,
			# so he hides it where they overlap.
			var eye := cam.global_position
			var ahead := -cam.global_transform.basis.z
			var depth := (at - eye).dot(ahead)
			var his := (global_position - eye).dot(ahead) + 0.05
			if depth > 0.01 and depth < his:
				at = eye + (at - eye) * (his / depth)
				s *= his / depth
		node.global_transform = Transform3D(Basis(b.x * s, b.y * s, b.z), at)
		(puff["mat"] as ShaderMaterial).set_shader_parameter("age", puff["age"])
		(puff["mat"] as ShaderMaterial).set_shader_parameter("strength", _shown)


## The strokes behind him, side-on: from just clear of his back (and of an arm or leg swung back), the way he came.
func _draw_strokes(delta: float, k: float, tall: float, facing: float, screen: Vector2, lean: float) -> void:
	if _card == null:
		_card = MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = CARD
		_card.mesh = quad
		_card.position = Vector3(0.0, CARD.y * 0.5 - FOOT, -0.03)       # just behind his card
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
		_mat.set_shader_parameter("mode", 0)
		_mat.set_shader_parameter("size", CARD)
		_mat.set_shader_parameter("halo", HALO * k)
		_card.material_override = _mat
		_card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_card)
	_card.visible = true
	_boil -= delta
	if _boil <= 0.0 or _jitter.is_empty():
		_boil = BOIL
		_jitter = []
		for i in LINES.size() * 3:
			_jitter.append(_rng.randf_range(-1.0, 1.0))
	# The way he goes, as it looks on screen (x right, y up): going towards the camera is down the screen, foreshortened.
	var way := Vector2(screen.x, -screen.y * 0.35)
	way = way.normalized() if way.length() > 0.01 else Vector2(facing, 0.0)
	var from := PackedVector2Array()
	var to := PackedVector2Array()
	var widths := PackedFloat32Array()
	var mid := Vector2(0.0, CARD.y * 0.5 - FOOT)
	for i in 5:
		if i >= LINES.size():
			from.append(Vector2.ZERO)
			to.append(Vector2.ZERO)
			widths.append(0.0)
			continue
		var row: Array = LINES[i]
		var y := float(row[0]) * tall + 0.025 * k * float(_jitter[i * 3])
		var out := (float(row[1]) + 0.03 * float(_jitter[i * 3 + 1])) * k
		var reach := float(row[2]) * k * (1.0 + 0.22 * float(_jitter[i * 3 + 2]))
		var a := Vector2(facing * (y * tan(lean) - out), y)          # leaning, he is further forward the higher up
		var b := a - way * reach
		from.append(a - mid)
		to.append(b - mid)
		widths.append(LINE_W * k)
	_mat.set_shader_parameter("seg_a", from)
	_mat.set_shader_parameter("seg_b", to)
	_mat.set_shader_parameter("seg_w", widths)
	_mat.set_shader_parameter("strength", _shown)


## A puff of dust at `at` (on his card, metres from his feet), which drifts `away` (on the floor) a little.
func _kick(at: Vector3, away: Vector3, k: float) -> void:
	var puff: Dictionary = {}
	for p: Dictionary in _puffs:
		if p["age"] >= 1.0:
			puff = p
			break
	if puff.is_empty():
		if _puffs.size() >= PUFFS:
			puff = _puffs[0]
			for p: Dictionary in _puffs:
				if p["age"] > puff["age"]:
					puff = p
		else:
			var node := MeshInstance3D.new()
			node.mesh = QuadMesh.new()
			node.top_level = true            # it stays where it was kicked up
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mat := ShaderMaterial.new()
			mat.shader = SHADER
			mat.set_shader_parameter("mode", 1)
			node.material_override = mat
			add_child(node)
			puff = {"node": node, "mat": mat}
			_puffs.append(puff)
	_flip = -_flip
	(puff["mat"] as ShaderMaterial).set_shader_parameter("flip", _flip)
	puff["age"] = 0.0
	puff["k"] = k
	puff["at"] = global_transform * at
	puff["drift"] = away.normalized() * 0.3 * k + Vector3(0.0, 0.22 * k, 0.0) if away.length() > 0.01 else Vector3(0.0, 0.22 * k, 0.0)
	(puff["node"] as Node3D).visible = true
