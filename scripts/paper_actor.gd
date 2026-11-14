extends Node3D
## A flat paper character: a drawing on a card that always shows its face to the
## camera. It can have up to three drawings (front, side, back); it shows the one
## that matches the way it is walking, and the side drawing is mirrored to walk
## left. Changing drawing flips the card over like a sheet of paper. The limbs
## are moved inside the drawing by shaders/paper_card.gdshader: legs step, arms
## swing, the body bobs. The drawing is unlit so it reads anywhere; a soft blob
## underneath ties it to the floor.
##
## He can run (`sprinting`), hold a pistol, an Uzi or an AK (`weapon`) and point
## it (`aiming`), and wear his clothes in other colours (`set_outfit`).

const PaperFace := preload("res://scripts/paper_face.gd")
const CARD_SHADER := preload("res://shaders/paper_card.gdshader")
const PROP_SHADER := preload("res://shaders/paper_prop.gdshader")
const WEAPONS := "res://assets/weapons/"

const WALK_SPEED := 1.9
const FLIP_TIME := 0.16
const RADIUS := 0.26          # how close its middle may come to a wall or a prop in front of it or behind it
const REACH := 0.4            # and to one beside it: the lead's hands and feet reach this far across the card
const PULL := 0.5             # an open doorway this close to where he is pushing at a wall draws him into line with it
const STEP_RATE := 9.0        # radians of walk cycle per second; two steps per turn
const BEAT := 60.0 / 92.0     # seconds: the tempo he performs to at a microphone
const ARM_ROOM := 0.45        # the card is this much wider than the drawing at each side, so a raised arm is not cut off
const RUN := 1.8              # sprinting covers the ground this many times faster than walking
const RUN_STEPS := 1.38       # and the steps come this much faster; the rest of the speed is a longer stride
const SLOT_ID := {"hat": 1, "jacket": 2, "shirt": 3, "trousers": 4, "shoes": 5}      # a wardrobe slot's number on the card (REGIONS)
const REGIONS := ["", "hat", "jacket", "shirt", "trousers", "shoes", "sleeve"]     # the clothes a drawing can have (outfit.py), by number
const ARM_BEND := 0.1            # an arm swinging at his side has turned all the way this far from its shoulder (paper_card.gdshader's arm_reach)
const ARM_BEND_HELD := 0.06     # holding something it turns at the shoulder, stiffly, or it would hook
const ARM_JOINT := 0.034        # what was drawn this close to a shoulder stays put under the moving arm (paper_card.gdshader's arm_joint)...
const ARM_JOINT_HELD := 0.04    # ...and a little more of it when the arm is turned a long way, to something he holds
const AWAY_LEAN := 0.3           # pointing away, it leans no further than this from straight up the screen, radians
const ARM_ROOT := 0.075           # an arm that goes behind him to a rifle's handguard: this much of it, from the shoulder, is not drawn
const FIST_NEAR := 0.05         # the fists are drawn this much nearer the eye than his card: over what he holds and over his arm's end
const FIST_IN := 13.0           # the arm runs this many pixels past the wrist, into the fist that covers its end
const RIM_INK := 11.0           # a held arm's cut end and the rim of its shoulder disc are inked this wide, pixels of his drawing
const THIN_ARM := 4.3           # an arm longer than this many of its own widths (the lead's) bows less, or it loops
const WIDE_ARM := 3.5           # an arm shorter than this many of its own widths is a wide sleeve: holding something it bends at the elbow (_hold)
const ELBOW := 0.4              # ...which is this far down it, of its length
const ELBOW_BEND := 0.008      # ...where it turns this sharply (the card's arm_reach)
const ELBOW_STUB := 0.2         # ...below which this much of the forearm's length stays as drawn, for the forearm to come out of
const ELBOW_FLAT := 0.4         # ...and a rifle across the chest lies this much flatter, or a short forearm must fold back to reach it
const FORE_IN := 3.0            # the second arm, which comes at its fist from below, stops shorter, or its end shows under the fist
const FORE_BACK := 9.0          # and aims this many pixels behind that fist's middle (towards the butt), to end well inside it
const LEAD_ARM := 0.083       # metres: how thick the lead's arm is drawn. What someone holds is sized to their own arm against this

## How each thing is held, for each way he can face and for carrying it or
## pointing it. Every number is tuned by eye against screenshots.
##   grip   where the fist on the grip goes, from the shoulder of the arm that holds it, in arm lengths
##          (shoulder to wrist): x to the right of the picture, y down. Left out: the hand stays where it hangs.
##   angle  how far the muzzle dips below level, degrees (below zero: it points up)
##   flip   it points to the left of the picture
##   curl   how much the holding arm bows (paper_card.gdshader); fore_curl: the other arm
##   arm    which arm holds the grip: "l" (the left of the picture) unless it says "r"
##   far    side-on, both hands on it: where the far arm comes out from behind him, from the near shoulder, in arm lengths
##   over   the holding arm passes in front of it (a rifle's stock)
##   gun_under  the thing goes behind him while the fist on it stays in front (held at his side, part of it behind his leg)
##   under  seen from the back, both hands on it in front of him: it goes behind him, the fists are not drawn, and his
##          arms go to spots of their own behind his body: "grip" for the arm that holds it, "fore_at" for the other
##          (each from its own shoulder), while "at" says where the thing's grip is (from the holding arm's shoulder)
##   art    which drawing of the thing this pose shows: "toward" is the muzzle-on one, "away" the short one that runs away from us
##          (weapons.json; it is turned to point up the screen, aim_lean off straight up); left out, the side-on one
##   behind the thing and its fists go behind his body too (it is further off than his head), and his forearm over the fist
##   arms_under  his arms go behind his body (he faces away, they are in front of him) while the thing and its fists stay in front
##   hidden the thing and its fists are not drawn at all (pointed away from us, his body is in the way)
## view_carry is how it is carried and view_aim how it is pointed across the screen; view_point is how it is pointed
## along the line of sight: front_point at the camera, back_point away from it (aim_way).
## A thing with a "fore" point (weapons.json) is held with both hands: the other fist goes there.
const HOLDS := {
	"pistol": {
		"side_carry": {"grip": [0.3, 1.02], "angle": 52.0, "curl": 0.3},
		"side_aim": {"grip": [1.3, 0.4], "angle": 0.0, "curl": 0.18},
		"front_carry": {"angle": 82.0, "flip": true},
		"front_aim": {"grip": [-1.18, -0.06], "angle": 0.0, "flip": true, "curl": -0.2},
		"back_carry": {"angle": 82.0, "arm": "r"},
		"front_point": {"art": "toward", "grip": [0.56, 0.46], "angle": 0.0, "flip": true},
		"back_point": {"art": "away", "arms_under": true, "behind": true, "flip": true, "arm": "r", "grip": [0.62, -0.86]},
	},
	"uzi": {
		"side_carry": {"grip": [0.74, 1.08], "angle": 52.0, "curl": 0.3},
		"side_aim": {"grip": [1.4, 0.56], "angle": 0.0, "curl": 0.24},
		"front_carry": {"angle": 80.0, "flip": true, "gun_under": true},
		"front_aim": {"grip": [-1.12, 0.04], "angle": 0.0, "flip": true, "curl": -0.3},
		"back_carry": {"angle": 80.0, "arm": "r", "gun_under": true},
		"front_point": {"art": "toward", "grip": [0.56, 0.5], "angle": 0.0, "flip": true},
		"back_point": {"art": "away", "arms_under": true, "behind": true, "flip": true, "arm": "r", "grip": [0.62, -0.86]},
	},
	"ak": {
		"side_carry": {"grip": [0.62, 1.02], "angle": 20.0, "curl": 0.5, "fore_curl": 0.3, "far": [0.45, 0.6], "over": true},
		"side_aim": {"grip": [0.98, 0.84], "angle": 0.0, "curl": 0.72, "fore_curl": 0.35, "far": [0.45, 0.78], "over": true},
		"front_carry": {"grip": [0.44, 1.0], "angle": -21.0, "curl": 0.0, "fore_curl": -0.7},
		"back_carry": {"at": [-0.44, 1.0], "angle": -24.0, "flip": true, "arm": "r", "grip": [-0.5, 0.96], "curl": -0.3, "fore_at": [0.45, 0.86], "fore_curl": 0.3, "under": true},
		"front_point": {"art": "toward", "grip": [0.3, 0.5], "angle": 0.0, "curl": 0.0, "fore_curl": 0.0},
		"back_point": {"art": "away", "arms_under": true, "behind": true, "flip": true, "arm": "r", "grip": [0.56, -0.5], "curl": 0.0, "fore_curl": 0.0},
	},
}

static var _weapon_data := {}       # assets/weapons/weapons.json, read once
static var _layers := {}            # wardrobe layers already read: path -> Image
static var _stacks := {}            # stacks already made: who and what is worn -> _stack
static var _holds_for := {}         # assets/weapons/holds_for.json, read with it: one character's own numbers for a hold

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
var sprinting := false                           # running: faster, longer steps, more lean, arms pumping
var weapon := ""                                 # what is in his hands: "" nothing, "pistol", "uzi" or "ak" (assets/weapons)
var aiming := false                              # he points it. Side-on if he has a side drawing; not while walking towards or away
var aim_way := ""                                # along the line of sight instead: "toward" the camera or "away" from it ("": across the screen)
var aim_lean := 0.2                              # pointing away, how far to the right of straight up the screen it points, radians
var aim_pitch := 0.0                             # side-on, how far above level he points it, radians (below zero: down)
var aim_to := 0.0                                # which side of the screen he points it at (-1 left, 1 right); 0: the way he is facing
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
var _run := 0.0             # 0 walking .. 1 running; eases
var _armed := 0.0           # 0 hands empty .. 1 the thing is in his hands; eases
var _aim := 0.0             # 0 carrying it .. 1 pointing it; eases
var _rig := {}              # rig.json
var _dir := ""              # the folder it came from, whole
var _wardrobe := {}         # wardrobe.json beside it, if its clothes are layers (has_wardrobe)
var _worn := {}             # ...and what it has on: slot -> {"item", "colour"}
var _stack := {}            # ...stacked into the card's pictures, one set for each way it faces (_restack)
var _who := ""              # the folder it came from: "fry"
var _px := Vector2.ONE      # the drawing on show, in pixels
var _pivots := {}           # where each arm turns as drawn (the card's arm_l_pivot, arm_r_pivot), "l" and "r"
var _arms := {}             # how its arms are drawn (rig.json's "arms": outfit.py's arm_info), "l" and "r"
var _arm_from := Vector2.ZERO   # where the near arm hangs from in this drawing, against where it is in the drawing it comes from (pixels)
var _outfit := {}           # piece of clothing: the Color he wears it in
var _over: MeshInstance3D   # a second card over what he holds, carrying only the near arm
var _over_mat: ShaderMaterial
var _held: Node3D           # what he holds: the thing and the fists, two drawings on the card
var _gun: MeshInstance3D
var _fist: MeshInstance3D
var _held_art := ""          # which drawing of it is on the cards: "" the side-on one, or "toward"
var _held_name := ""        # the thing those two drawings show now
var _bend := ARM_BEND       # how far from the shoulder his arms have turned all the way, now


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
	_over = MeshInstance3D.new()
	_over_mat = ShaderMaterial.new()
	_over_mat.shader = CARD_SHADER
	_over_mat.set_shader_parameter("layer", 2)
	_over_mat.set_shader_parameter("toward", 0.04)
	_over.material_override = _over_mat
	_over.visible = false
	_card.add_child(_over)
	_held = Node3D.new()
	_held.visible = false
	_card.add_child(_held)
	_gun = _prop_card(0.03)
	_fist = _prop_card(FIST_NEAR)


## A drawing laid on the card: the thing he holds, or the fists on it.
func _prop_card(toward: float) -> MeshInstance3D:
	var card := MeshInstance3D.new()
	card.mesh = QuadMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = PROP_SHADER
	mat.set_shader_parameter("toward", toward)
	card.material_override = mat
	_held.add_child(card)
	return card


## Set a number or a picture on the card, and on the copy of it that carries the near arm.
func _put(param: String, value: Variant) -> void:
	_mat.set_shader_parameter(param, value)
	_over_mat.set_shader_parameter(param, value)


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
	_rig = rig
	_who = dir.get_file()
	_dir = dir
	_wardrobe = {}
	_worn = {}
	_stack = {}
	var layers = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("wardrobe.json"))) if FileAccess.file_exists(dir.path_join("wardrobe.json")) else null
	if typeof(layers) == TYPE_DICTIONARY and layers.has("base") and layers.has("items"):
		_wardrobe = layers
	height = float(rig["height_m"])
	for name: String in rig["views"]:
		var data: Dictionary = rig["views"][name]
		# A drawing with no "limbs" or "legs" stands still (the people in the places: build_npc.py).
		_views[name] = {"art": load(dir.path_join(data["art"])), "limbs": load(dir.path_join(data["limbs"])) if data.has("limbs") else null, "data": data}
		if data.has("legs"):
			_views[name]["legs"] = load(dir.path_join(data["legs"]))
		if data.has("arm_art"):      # this drawing has no arms: they are taken from another one
			_views[name]["arm_art"] = load(dir.path_join(data["arm_art"]))
		if data.has("regions"):      # which piece of clothing each pixel is (outfit.py)
			_views[name]["regions"] = load(dir.path_join(data["regions"]))
	var body: Texture2D = _views["front"]["art"]
	face = PaperFace.new()
	face.name = "Face"
	_card.add_child(face)
	face.setup(dir, rig, height, Vector2(body.get_size()))
	if has_wardrobe():
		wear({})                # what he was drawn in, from its layers
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


## Turn side-on to face left or right on screen without walking (to talk to
## someone). Someone with only a front drawing stays as they are.
func face_side(screen_x: float) -> void:
	if not _views.has("side"):
		return
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
	_run = move_toward(_run, 1.0 if sprinting and moving else 0.0, delta * 5.0)
	if moving:
		_step(dir.limit_length(1.0) * WALK_SPEED * speed * (1.0 + (RUN - 1.0) * _run) * delta)
		_phase += delta * STEP_RATE * maxf(speed, 1.0) * (1.0 + (RUN_STEPS - 1.0) * _run)
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
	# Pointing what he holds: side-on, if he has a side drawing, and not while he
	# walks towards the camera or away from it (he faces the way he walks).
	var pointing := aiming and weapon != "" and not performing
	var point_view := "side"
	if aim_way == "toward" and _views.has("front"):
		point_view = "front"
	elif aim_way == "away" and _views.has("back"):
		point_view = "back"
	if pointing and _views.has("side") and (not moving or _want_view == point_view):
		_want_view = point_view
		if point_view != "side":
			_want_yaw = 0.0
		elif aim_to != 0.0 and not moving:
			_want_yaw = 0.0 if aim_to > 0.0 else PI
	elif pointing and _views.has("side"):
		pointing = false
	_armed = move_toward(_armed, 1.0 if weapon != "" and not performing else 0.0, delta * 6.0)
	_aim = move_toward(_aim, 1.0 if pointing else 0.0, delta * 7.0)
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
	var r := _run * g
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
		var apart := (1.0 - sin(step) * sin(step)) * r      # running, his feet reach further apart than he was drawn...
		var lift := (0.045 + 0.04 * r) * sin(step) * g      # ...and come up higher
		var slide := _stride * 0.5 * together - _stride * 0.2 * apart
		_put("swing_l", slide)
		_put("swing_r", -slide)
		_put("lift_l", 0.0 if passed else lift)
		_put("lift_r", lift if passed else 0.0)
		_put("near_leg_right", far_goes != passed)
		_put("far_leg_shade", 1.0)
		_put("leg_ink", 0.006 * g)
		# The arm swings against the legs; running, it swings twice as far and bends at the elbow.
		_put("arm_l_angle", _arm_rest - (0.5 + 0.55 * r) * cos(_phase) * g - 0.25 * r)
		_put("arm_l_curl", 0.95 * r)
		_put("arm_r_angle", 0.0)
		_put("arm_r_curl", 0.0)
		_card.position.y = 0.035 * together * (1.0 - _run) + 0.075 * apart     # walking he is highest as the legs pass; running, in mid-stride
		_card.rotation.z = -(0.045 + 0.11 * _run) * g      # lean into it
	else:
		# Seen from the front or back the feet lift in turn and the body rocks over the planted one.
		_put("swing_l", 0.0)
		_put("swing_r", 0.0)
		_put("far_leg_shade", 1.0)
		_put("leg_ink", 0.0)
		_put("lift_l", (0.045 + 0.035 * r) * maxf(s, 0.0) * g)
		_put("lift_r", (0.045 + 0.035 * r) * maxf(-s, 0.0) * g)
		# Walking, the arms sway together. Running they pump: each bends at the
		# elbow and its fist comes up in front of him as the other goes down.
		_put("arm_l_angle", 0.2 * s * g - 0.12 * r)
		_put("arm_r_angle", 0.2 * s * g + 0.12 * r)
		_put("arm_l_curl", (0.5 + 0.5 * s) * r)
		_put("arm_r_curl", -(0.5 - 0.5 * s) * r)
		_card.position.y = (0.045 + 0.04 * r) * absf(s) * g
		_card.rotation.z = (0.045 + 0.03 * r) * s * g
		if _groove > 0.0:
			_perform_pose()
	_hold()


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
	_put("lift_l", dip)
	_put("lift_r", dip)
	_card.position.y = -dip * height
	_card.rotation.z = 0.04 * sin(PI * _beat) * k
	var lead := smoothstep(-0.35, 0.35, sin(TAU * _beat / 16.0))     # 1: the arm on the left of the picture is the high one
	var high := 1.5 + 0.65 * hit + 0.12 * sin(TAU * _beat * 2.0)
	var low := 0.5 + 0.4 * off
	_put("arm_l_angle", -lerpf(low, high, lead) * k)
	_put("arm_r_angle", lerpf(low, high, 1.0 - lead) * k)
	_put("arm_l_curl", 0.0)
	_put("arm_r_curl", 0.0)


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
	_px = px
	var quad := QuadMesh.new()
	quad.size = Vector2(height * px.x / px.y * (1.0 + 2.0 * ARM_ROOM), height)
	quad.center_offset = Vector3(0, height * 0.5, 0)
	_card.mesh = quad
	_over.mesh = quad
	# A wardrobe character's pictures are its layers stacked; side-on its arms are the front stack's.
	var stack: Dictionary = _stack.get(wanted, {})
	var arms_stack: Dictionary = _stack.get("front", {}) if v.has("arm_art") else stack
	_put("art", stack.get("art", art))
	_put("aspect", px.x / px.y)
	_put("pad", ARM_ROOM)
	_put("has_limbs", v["limbs"] != null)
	_put("far_arm_hidden", bool(data.get("far_arm_hidden", false)))
	_put("arm_art", arms_stack.get("art", v.get("arm_art", art)))
	_put("arms_drawn_here", not v.has("arm_art"))
	_put("has_under", stack.has("under"))
	if stack.has("under"):
		_put("under", stack["under"])
		_put("under_regions", stack["under_regions"])
	var shift: Array = data.get("arm_l_shift", [0.0, 0.0])
	_arm_from = Vector2(float(shift[0]), float(shift[1]))
	_put("arm_l_shift", _arm_from / px)
	var top := float(data.get("arm_l_top", 0.0))
	var sides: Array = data.get("arm_l_top_x", [-9.0 * px.x, 9.0 * px.x])
	if not stack.is_empty():        # which of what he has on covers the top of that arm, if any does
		var cap: Array = stack.get("arm_top", [0.0, -9.0 * px.x, 9.0 * px.x])
		top = float(cap[0])
		sides = [cap[1], cap[2]]
	_put("arm_l_top", top / px.y)
	_put("arm_l_top_x", Vector2(float(sides[0]), float(sides[1])) / px.x)
	_arm_rest = float(data.get("arm_l_rest", 0.0))
	if v["limbs"] != null:
		_put("limbs", arms_stack.get("limbs", v["limbs"]))
		_pivots = {"l": Vector2(data["arm_l"][0], data["arm_l"][1]) / px, "r": Vector2(data["arm_r"][0], data["arm_r"][1]) / px}
		_put("arm_l_pivot", _pivots["l"])
		_put("arm_r_pivot", _pivots["r"])
		_put("arm_elbow", Vector2.ZERO)
	# How the arms are drawn: this drawing's own, or those of the drawing its arms are taken from.
	_arms = data.get("arms", {})
	if _arms.is_empty() and v.has("arm_art") and _views.has("front"):
		_arms = _views["front"]["data"].get("arms", {})
	if float(arms_stack.get("arm_width", 0.0)) > 0.0:      # a sleeve makes the arm as wide as it is
		_arms = _arms.duplicate(true)
		for key: String in _arms:
			_arms[key]["width"] = maxf(float(_arms[key]["width"]), float(arms_stack["arm_width"]))
	for key: String in _arms:
		var arm: Dictionary = _arms[key]
		_put("arm_%s_axis" % key, (Vector2(arm["wrist"][0], arm["wrist"][1]) - Vector2(arm["pivot"][0], arm["pivot"][1])).normalized())
		_put("arm_len", float(arm["len"]) / px.y)
	# A drawing with no rig keeps its legs still: a hip line below the picture moves nothing.
	_put("hip_v", float(data.get("hip", px.y * 2.0)) / px.y)
	_put("knee_v", float(data.get("knee", px.y * 3.0)) / px.y)
	if v.has("legs"):
		_put("legs", v["legs"])
	_stride = float(data.get("stride", 0.0)) / px.y
	_put("arm_ink", float(data.get("arm_ink", 0.0)) / px.y)
	_dress()
	_held_name = ""             # what he holds is sized and placed for this drawing's arms
	if face:
		face.visible = data.has("face")
		if data.has("face"):
			face.set_layout(data["face"], art)


# ---------------------------------------------------------------- his clothes

## Wear his clothes in other colours. `wear` is {piece: Color}: "hat",
## "jacket", "shirt", "trousers", "shoes", and "sleeve" (long sleeves, in that
## colour, where his arms were drawn bare). A piece left out is as it was
## drawn. Only for a character whose rig.json lists its "clothes" (outfit.py).
func set_outfit(wear: Dictionary) -> void:
	_outfit = wear.duplicate()
	_dress()


## The pieces of clothing this character has that can be changed.
func clothes() -> Array:
	return _rig.get("clothes", {}).keys()


func skin() -> Color:
	return _colour(_rig.get("skin", [188.0, 94.0, 42.0]))


## Tell the card what he is wearing: which picture says where his clothes are,
## the colour each piece was drawn in and the colour it is now.
func _dress() -> void:
	if has_wardrobe() and _stack.has(view):
		var mine: Dictionary = _stack[view]
		var theirs: Dictionary = _stack.get("front", mine) if _views[view].has("arm_art") else mine
		_put("has_regions", true)
		_put("regions", mine["regions"])
		_put("arm_regions", theirs["regions"])
		var was := PackedColorArray()
		var now := PackedColorArray()
		for piece: String in REGIONS:
			var on: Dictionary = _worn.get(piece, {})
			var item: Dictionary = _wardrobe["items"].get(on.get("item", ""), {})
			var drawn := _colour(item.get("colour", [0, 0, 0]))
			was.append(drawn)
			now.append(on.get("colour", drawn) if not item.is_empty() else drawn)
		_put("dress_from", was)
		_put("dress_to", now)
		_put("cuffs", false)
		return
	var v: Dictionary = _views.get(view, {})
	var drawn_in: Dictionary = _rig.get("clothes", {})
	var known: bool = v.has("regions") and not drawn_in.is_empty()
	_put("has_regions", known)
	if not known:
		return
	_put("regions", v["regions"])
	var arms_from: Dictionary = _views["front"] if v.has("arm_art") and _views.has("front") else v
	_put("arm_regions", arms_from.get("regions", v["regions"]))
	var from := PackedColorArray()
	var to := PackedColorArray()
	for piece: String in REGIONS:
		var drawn := skin() if piece == "sleeve" else (_colour(drawn_in[piece]) if drawn_in.has(piece) else Color.BLACK)
		var worn: Color = _outfit.get(piece, drawn)
		from.append(drawn)
		to.append(worn)
	_put("dress_from", from)
	_put("dress_to", to)
	_put("cuffs", _outfit.has("sleeve"))


static func _colour(rgb: Array) -> Color:
	return Color(float(rgb[0]) / 255.0, float(rgb[1]) / 255.0, float(rgb[2]) / 255.0)


# ------------------------------------------------- clothes that are layers

## Has this character a wardrobe (wardrobe.json beside its rig: wardrobe.py)? Then its clothes are layers:
## a bare base and, over it, one item or none in each slot ("shoes", "trousers", "shirt", "jacket", "hat"),
## each in any colour. wear() dresses it.
func has_wardrobe() -> bool:
	return not _wardrobe.is_empty()


## wardrobe.json: "items" (each with its "slot", "name", "colour" and "colours"), "worn" (what it was drawn in).
func wardrobe() -> Dictionary:
	return _wardrobe


## What he has on: slot -> {"item": its id ("" for nothing), "colour": Color}.
func worn() -> Dictionary:
	return _worn.duplicate(true)


## Dress him. `outfit` is slot -> {"item": id, "colour": Color}; the colour may be left out (the item's own),
## the item may be "" (a hat or a jacket left off), and a slot left out is what he was drawn in.
func wear(outfit: Dictionary) -> void:
	if _wardrobe.is_empty():
		return
	var items: Dictionary = _wardrobe.get("items", {})
	var drawn: Dictionary = _wardrobe.get("worn", {})
	_worn = {}
	for slot: String in SLOT_ID:
		var want: Dictionary = outfit.get(slot, {})
		var id := String(want.get("item", drawn.get(slot, "")))
		if id == "none":
			id = ""
		if id != "" and not items.has(id):
			id = String(drawn.get(slot, ""))            # something this body has no drawing of
		if id == "" and not slot in ["hat", "jacket"]:
			id = String(drawn.get(slot, ""))            # he always has a shirt, trousers and shoes on
		var colour := Color.BLACK
		if id != "":
			colour = want["colour"] if want.has("colour") else _colour(items[id].get("colour", [128, 128, 128]))
		_worn[slot] = {"item": id, "colour": colour}
	_restack()
	if _views.has(view):
		_show(view)


## A layer's picture, as an image the others can be laid on.
static func _layer(path: String) -> Image:
	if _layers.has(path):
		return _layers[path]
	var image: Image = null
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		if tex:
			image = tex.get_image()
			if image and image.is_compressed():
				image.decompress()
			if image and image.get_format() != Image.FORMAT_RGBA8:
				image.convert(Image.FORMAT_RGBA8)
	_layers[path] = image
	return image


## Lay a layer on `onto` and mark where it is on `marks` as piece number `id` (the card's regions).
func _lay(onto: Image, marks: Image, file: String, id: int) -> void:
	if file == "":
		return
	var image := _layer(_dir.path_join(file))
	if image == null or image.get_size() != onto.get_size():
		push_warning("Wardrobe layer missing or the wrong size: %s" % _dir.path_join(file))
		return
	var all := Rect2i(Vector2i.ZERO, image.get_size())
	onto.blend_rect(image, all, Vector2i.ZERO)
	var flat := Image.create(all.size.x, all.size.y, false, Image.FORMAT_RGBA8)
	flat.fill(Color(id * 40.0 / 255.0, 0.0, 0.0, 1.0))
	marks.blit_rect_mask(flat, image, all, Vector2i.ZERO)


static func _texture(image: Image, mipmaps: bool) -> ImageTexture:
	if mipmaps:
		image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## Stack what he has on into the pictures the card draws, one set for each way he faces:
##   art      everything, arms and all            regions        which piece each pixel of it is
##   under    the same without the arms           under_regions  ...and of that
##   limbs    which pixels are which arm          arm_top, arm_width: from the items (see wardrobe.md)
## Side-on there are no arms in the picture: they are the front view's.
func _restack() -> void:
	_stack = {}
	if _wardrobe.is_empty():
		return
	var key := _who
	for slot: String in SLOT_ID:
		var on: Dictionary = _worn.get(slot, {})
		key += "|%s" % on.get("item", "")
	if _stacks.has(key):
		_stack = _stacks[key]
		return
	var items: Dictionary = _wardrobe.get("items", {})
	var base: Dictionary = _wardrobe.get("base", {})
	for name: String in base:
		if not _views.has(name):
			continue
		var data: Dictionary = _views[name]["data"]
		var size := Vector2i((_views[name]["art"] as Texture2D).get_size())
		var all := Rect2i(Vector2i.ZERO, size)
		var under := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		var arms := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		var under_marks := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		under_marks.fill(Color(0, 0, 0, 1))
		var arm_marks := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		arm_marks.fill(Color(0, 0, 0, 1))
		var made := {"arm_width": 0.0}
		_lay(under, under_marks, String(base[name].get("art", "")), 0)
		_lay(arms, arm_marks, String(base[name].get("arms", "")), 0)
		for slot: String in _wardrobe.get("order", ["shoes", "trousers", "shirt", "jacket", "hat"]):
			var id := String(_worn.get(slot, {}).get("item", ""))
			if id == "":
				continue
			var drawing: Dictionary = items[id].get("views", {}).get(name, {})
			_lay(under, under_marks, String(drawing.get("art", "")), SLOT_ID[slot])
			_lay(arms, arm_marks, String(drawing.get("arms", "")), SLOT_ID[slot])
			if drawing.has("arm_top"):
				made["arm_top"] = drawing["arm_top"]
			made["arm_width"] = maxf(made["arm_width"], float(drawing.get("arm_width", 0.0)))
		if base[name].has("arms"):
			var full: Image = under.duplicate()
			full.blend_rect(arms, all, Vector2i.ZERO)
			var marks: Image = under_marks.duplicate()
			marks.blit_rect_mask(arm_marks, arms, all, Vector2i.ZERO)
			# Which arm a pixel belongs to: the side of the picture it is on.
			var mid := int((float(data["arm_l"][0]) + float(data["arm_r"][0])) * 0.5)
			var limbs := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
			limbs.fill(Color(0, 0, 0, 1))
			var flat := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
			flat.fill(Color(1, 0, 0, 1))
			limbs.blit_rect_mask(flat, arms, Rect2i(0, 0, mid, size.y), Vector2i.ZERO)
			flat.fill(Color(0, 1, 0, 1))
			limbs.blit_rect_mask(flat, arms, Rect2i(mid, 0, size.x - mid, size.y), Vector2i(mid, 0))
			made["art"] = _texture(full, true)
			made["regions"] = _texture(marks, false)
			made["under"] = _texture(under, true)
			made["under_regions"] = _texture(under_marks, false)
			made["limbs"] = _texture(limbs, false)
		else:
			made["art"] = _texture(under, true)
			made["regions"] = _texture(under_marks, false)
		_stack[name] = made
	_stacks[key] = _stack


# ------------------------------------------------------------ what he holds

## assets/weapons/weapons.json (build_weapons.py): the things that can be held.
static func weapons() -> Dictionary:
	if _weapon_data.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(WEAPONS + "weapons.json"))
		if typeof(data) == TYPE_DICTIONARY:
			_weapon_data = data
		var own = JSON.parse_string(FileAccess.get_file_as_string(WEAPONS + "holds_for.json"))
		if typeof(own) == TYPE_DICTIONARY:
			_holds_for = own
	return _weapon_data


## How this character holds `held` facing `way` ("side_aim"): HOLDS, with its own
## numbers from assets/weapons/holds_for.json laid over (a big belly, short arms).
func _hold_row(held: String, way: String) -> Dictionary:
	var row: Dictionary = HOLDS.get(held, {}).get(way, {})
	var own: Dictionary = _holds_for.get(_who, {}).get(held, {}).get(way, {})
	if own.is_empty():
		return row
	row = row.duplicate()
	row.merge(own, true)
	return row


## Face a way without walking: "front", "side" or "back", and whether the
## drawing is mirrored (side-on: facing the left of the screen). For stills.
func face_way(way: String, mirrored := false) -> void:
	if _views.has(way):
		_want_view = way
		_want_yaw = PI if mirrored else 0.0


## What he holds, and what his arms do about it. The fist on the grip goes
## where HOLDS says for the way he is facing; the arm that holds it is turned
## and stretched until its hand is there, and cut off at the wrist, where the
## fist takes over. If the thing has a second fist on it (the AK's handguard)
## the other arm reaches that one. Side-on that is the far arm, which comes out
## from behind his chest.
func _hold() -> void:
	var held := weapon if weapon != "" else _held_name
	weapons()
	var carry := _hold_row(held, view + "_carry")
	var info: Dictionary = weapons().get("weapons", {}).get(held, {})
	var key: String = carry.get("arm", "l")
	var k := smoothstep(0.0, 1.0, _armed)
	if k <= 0.0 or carry.is_empty() or info.is_empty() or not _arms.has(key):
		_held.visible = false
		_over.visible = false
		_mat.set_shader_parameter("layer", 0)
		_bend = ARM_BEND
		_put("arm_reach", _bend)
		_put("arm_joint", ARM_JOINT)
		_put("rim_ink", 0.0)
		_put("joint_half", false)
		_put("arm_from", Vector2.ZERO)
		_put("arm_elbow", Vector2.ZERO)
		for side: String in ["l", "r"]:
			_put("arm_%s_stretch" % side, 1.0)
			_put("arm_%s_cut" % side, 9.0)
			if _pivots.has(side):
				_put("arm_%s_pivot" % side, _pivots[side])
		_put("far_arm_copy", false)
		_put("arms_under", view == "back" and _run * _gait > 0.3)      # running away from us, his fists pump in front of him
		if _armed <= 0.0:
			_held_name = ""
		return
	var m := height / _px.y                                   # metres to a pixel of his drawing
	_bend = lerpf(ARM_BEND, ARM_BEND_HELD, k)
	_put("arm_reach", _bend)
	var arm: Dictionary = _arms[key]
	# A wide sleeve (a jersey, a puffer jacket) cannot turn at the shoulder like a hose: its cut edge would swing
	# out as a shard. It bends at the elbow: the sleeve above stays as drawn and the forearm goes to the fist.
	# Pointing it, the whole arm goes out from the shoulder, sleeve and all.
	var stout: bool = float(arm["len"]) < WIDE_ARM * float(arm["width"])
	var wide: bool = stout and k > 0.5 and view != "side" and _aim < 0.5
	var down := ELBOW * float(arm["len"]) if wide else 0.0                  # shoulder to where it bends, pixels
	if not wide:
		for side: String in _pivots:
			_put("arm_%s_pivot" % side, _pivots[side])
	# A long thin arm turns at the shoulder, but what is drawn above that point stays put, as above an elbow:
	# turned with the arm, the top of the sleeve swings out as a flap.
	var lanky: bool = not stout and k > 0.5 and view != "side" and _aim < 0.5 and float(arm["len"]) > THIN_ARM * float(arm["width"])
	_put("arm_joint", lerpf(ARM_JOINT, ARM_JOINT_HELD, k))
	_put("arm_stub", ELBOW_STUB * (float(arm["len"]) - down) / _px.y)
	_put("rim_ink", RIM_INK / _px.y if k > 0.5 else 0.0)
	_put("joint_half", k > 0.5 and view != "side" and not stout)
	var thin := minf(1.0, THIN_ARM * float(arm["width"]) / float(arm["len"]))      # 1 for an arm as stout as the lead's or stouter
	thin *= thin
	# Pointed along the line of sight (at the camera, or away) it has a pose of its own; else the one across the screen.
	var point := _hold_row(held, view + "_point") if aim_way != "" and view != "side" else {}
	if point.is_empty():
		point = _hold_row(held, view + "_aim")
	if point.is_empty():
		point = carry
	var a := smoothstep(0.0, 1.0, _aim)
	var pose: Dictionary = point if a > 0.5 else carry          # what is drawn over what, and which drawing, changes half way up
	var art: String = pose.get("art", "")
	if art != "" and info.has(art):
		info = info[art]
	else:
		art = ""
	var unit := clampf(float(arm["width"]) * m / LEAD_ARM, 0.8, 1.3) * float(info.get("size", 1.0)) / float(weapons()["px_per_m"])    # metres to a unit of the thing's drawing
	if pose.get("hidden", false):       # nothing of it shows: his arms are whole, with no cut ends to ink
		_put("rim_ink", 0.0)
		_put("joint_half", false)
	if pose.get("arms_under", false):   # his arms go behind him from the shoulder: straight from it, no joint disc left outside his body
		_bend = 0.012
		_put("arm_reach", _bend)
		_put("arm_joint", 0.0)
		_put("joint_half", false)
	if _held_name != held or _held_art != art:
		_take(held, info, unit)
		_held_art = art
	var flip: bool = pose.get("flip", carry.get("flip", false))
	var dip := lerpf(carry.get("angle", 0.0), point.get("angle", 0.0), a)
	if art == "away":         # it points up the screen, at the cross
		# (the drawing is flipped so that its grip is on the side of his head and the rest of it stands clear)
		var lean := rad_to_deg(clampf(aim_lean, -AWAY_LEAN, AWAY_LEAN))
		dip = -(90.0 + lean) if flip else -(90.0 - lean)
	var curl := lerpf(carry.get("curl", 0.0), point.get("curl", 0.0), a) * thin
	var pitch := aim_pitch * a if view == "side" else 0.0        # side-on he points it up or down at what the cross is on
	dip -= rad_to_deg(pitch)
	if wide and info.has("fore") and not pose.get("under", false):
		dip *= ELBOW_FLAT

	# The arm that holds the grip.
	var pivot := Vector2(arm["pivot"][0], arm["pivot"][1])
	var shoulder := pivot + (_arm_from if key == "l" else Vector2.ZERO)      # where it hangs from in this drawing, pixels
	var axis := (Vector2(arm["wrist"][0], arm["wrist"][1]) - pivot).normalized()
	var wrist := float(arm["wrist_r"])
	var hand := wrist + 0.25 * (float(arm["len"]) - wrist)                    # shoulder to the middle of the hand, pixels
	var hangs := axis.rotated(-_arm_rest if view == "side" else 0.0) * hand   # where the hand is with the arm at rest
	var want := _grip(carry, hangs, wrist).lerp(_grip(point, hangs, wrist), a)
	want += Vector2(0.03 * sin(_phase), 0.02 * absf(sin(_phase))) * wrist * _gait * (1.0 - a)      # it moves a little as he walks
	want = want.rotated(-pitch)
	var elbow := Vector2.ZERO                                                 # which arms bend at the elbow, for the card
	if lanky:
		elbow = Vector2.ONE
	if wide:
		# From here on the arm is its forearm: everything is measured from the elbow.
		shoulder += axis * down
		want -= axis * down
		hand -= down
		wrist -= down
		curl = 0.0
		elbow[0 if key == "l" else 1] = 1.0
		_bend = ELBOW_BEND                  # an elbow is a sharp joint: turned gently, a short forearm swirls
		_put("arm_reach", _bend)
		_put("arm_%s_pivot" % key, (pivot + axis * down) / _px)
	var length := float(arm["len"]) - down
	var reach := _reach_for(axis, hand / _px.y, length / _px.y, want / _px.y, curl)
	var pre := "arm_%s_" % key
	var angle := lerp_angle(float(_mat.get_shader_parameter(pre + "angle")), reach.x, k)
	var bow := lerpf(float(_mat.get_shader_parameter(pre + "curl")), curl, k)
	var stretch := lerpf(1.0, reach.y, k)
	var under: bool = pose.get("under", false)
	var cut := (wrist + FIST_IN / maxf(stretch, 1.0)) / _px.y if k > 0.5 and not under else 9.0
	_put(pre + "angle", angle)
	_put(pre + "curl", bow)
	_put(pre + "stretch", stretch)
	_put(pre + "cut", cut)

	# The thing itself, its grip in that hand.
	var at := shoulder + _hand_at(axis, hand / _px.y, length / _px.y, angle, bow, stretch) * _px.y
	if under and pose.has("at"):
		at = shoulder - axis * down + Vector2(pose["at"][0], pose["at"][1]) * (wrist + down)
	_held.visible = k > 0.5 and not pose.get("hidden", false)
	_held.position = Vector3((at.x - _px.x * 0.5) * m, (_px.y - at.y) * m, 0.0)
	_held.rotation.z = deg_to_rad(dip) * (1.0 if flip else -1.0)
	_held.scale = Vector3(-1.0 if flip else 1.0, 1.0, 1.0)
	var behind: bool = pose.get("behind", false)
	_put("arm_from", Vector2.ZERO)
	(_gun.material_override as ShaderMaterial).set_shader_parameter("toward", -0.03 if under or behind or pose.get("gun_under", false) else 0.03)
	(_fist.material_override as ShaderMaterial).set_shader_parameter("toward", -0.02 if behind else FIST_NEAR)
	_fist.visible = not under
	_put("arms_under", (under or pose.get("arms_under", false)) and k > 0.5)
	var over: bool = pose.get("over", false) and key == "l" and k > 0.5
	_over.visible = over
	_mat.set_shader_parameter("layer", 1 if over else 0)

	# The other hand, on the second fist.
	var other := "r" if key == "l" else "l"
	if not info.has("fore") and not pose.has("fore_at"):
		_put("arm_elbow", elbow)
		_put("far_arm_copy", false)
		_put("arm_%s_stretch" % other, 1.0)
		_put("arm_%s_cut" % other, 9.0)
		return
	var fore := at
	if info.has("fore"):
		var off := Vector2(float(info["fore"][0]) - float(info["grip"][0]), float(info["fore"][1]) - float(info["grip"][1])) * (unit / m)
		if flip:
			off.x = -off.x
		fore = at + off.rotated(deg_to_rad(dip) * (-1.0 if flip else 1.0))      # where that fist is, in pixels of his drawing
		fore -= Vector2(-FORE_BACK if flip else FORE_BACK, 0.0).rotated(deg_to_rad(dip) * (-1.0 if flip else 1.0))
	var fore_cut := (wrist + FORE_IN) / _px.y if k > 0.5 and not under and info.has("fore") else 9.0
	if pose.has("fore_at") and _arms.has(other) and (under or not info.has("fore")):       # a spot of its own for the other hand
		fore = Vector2(_arms[other]["pivot"][0], _arms[other]["pivot"][1]) + Vector2(pose["fore_at"][0], pose["fore_at"][1]) * float(_arms[other]["wrist_r"])
	var fore_curl := lerpf(carry.get("fore_curl", 0.0), point.get("fore_curl", 0.0), a) * thin
	if view == "side" or not _arms.has(other):
		# One arm is drawn: the far one is a copy of it, hung from a point behind his chest.
		var far0: Array = carry.get("far", [0.4, 0.1])
		var far1: Array = point.get("far", far0)
		var far := Vector2(far0[0], far0[1]).lerp(Vector2(far1[0], far1[1]), a) * wrist
		if pitch > 0.0:        # pointing up, the far arm comes out higher and straighter, or it hangs below the thing like a strap
			far += Vector2(0.0, -0.95) * pitch * wrist
			fore_curl *= maxf(1.0 - 1.6 * pitch, 0.0)
		var far_reach := _reach_for(axis, hand / _px.y, length / _px.y, (fore - shoulder - far) / _px.y, fore_curl, 3.2)      # most of it is behind him
		_put("arm_elbow", elbow)
		_put("far_arm_copy", k > 0.5)
		_put("far_arm_shift", far / _px)
		_put("arm_r_angle", far_reach.x)
		_put("arm_r_curl", fore_curl)
		_put("arm_r_stretch", far_reach.y)
		_put("arm_r_cut", fore_cut)
		return
	_put("far_arm_copy", false)
	var arm2: Dictionary = _arms[other]
	var pivot2 := Vector2(arm2["pivot"][0], arm2["pivot"][1])
	var shoulder2 := pivot2 + (_arm_from if other == "l" else Vector2.ZERO)
	var axis2 := (Vector2(arm2["wrist"][0], arm2["wrist"][1]) - pivot2).normalized()
	var wrist2 := float(arm2["wrist_r"])
	var hand2 := wrist2 + 0.25 * (float(arm2["len"]) - wrist2)
	var length2 := float(arm2["len"])
	if wide:
		var down2 := ELBOW * length2
		shoulder2 += axis2 * down2
		hand2 -= down2
		wrist2 -= down2
		length2 -= down2
		fore_curl = 0.0
		elbow[0 if other == "l" else 1] = 1.0
		_put("arm_%s_pivot" % other, (pivot2 + axis2 * down2) / _px)
	_put("arm_elbow", elbow)
	var reach2 := _reach_for(axis2, hand2 / _px.y, length2 / _px.y, (fore - shoulder2) / _px.y, fore_curl, 3.2 if pose.get("arms_under", false) else 1.9)      # behind him it may be as long as it must
	if pose.get("arms_under", false) and k > 0.5:      # ...and its root, which would stick out of his far shoulder, is not drawn
		_put("arm_from", Vector2(ARM_ROOT, 0.0) if other == "l" else Vector2(0.0, ARM_ROOT))
	var pre2 := "arm_%s_" % other
	_put(pre2 + "angle", lerp_angle(float(_mat.get_shader_parameter(pre2 + "angle")), reach2.x, k))
	_put(pre2 + "curl", lerpf(float(_mat.get_shader_parameter(pre2 + "curl")), fore_curl, k))
	_put(pre2 + "stretch", lerpf(1.0, reach2.y, k))
	_put(pre2 + "cut", (wrist2 + FORE_IN) / _px.y if k > 0.5 and not under else 9.0)


## Where a hold puts the fist on the grip, from the shoulder, in pixels. With no
## "grip" the hand stays where it hangs.
func _grip(hold: Dictionary, hangs: Vector2, wrist: float) -> Vector2:
	if not hold.has("grip"):
		return hangs
	return Vector2(hold["grip"][0], hold["grip"][1]) * wrist


## How to turn and stretch an arm so that its hand is at `to` (from its
## shoulder). `axis` is the way the arm runs as drawn, `hand` how far along it
## the middle of the hand is, `length` the whole arm; all in fractions of the
## drawing's height. Returns (angle, stretch) for paper_card.gdshader.
func _reach_for(axis: Vector2, hand: float, length: float, to: Vector2, curl: float, most := 1.9) -> Vector2:
	var bow := curl * clampf((hand - _bend) / maxf(length - _bend, 0.01), 0.0, 1.2)
	return Vector2(wrapf(axis.angle() - to.angle() - bow, -PI, PI), clampf(to.length() / hand, 0.42, most))


## And the other way: where the hand is, from the shoulder, for an arm turned, bowed and stretched like that.
func _hand_at(axis: Vector2, hand: float, length: float, angle: float, curl: float, stretch: float) -> Vector2:
	var turn := angle + curl * clampf((hand - _bend) / maxf(length - _bend, 0.01), 0.0, 1.2)
	return (axis * hand * stretch).rotated(-turn)


## Put a thing's drawings on the two cards he holds it with, its grip at their middle.
func _take(held: String, info: Dictionary, unit: float) -> void:
	_held_name = held
	var size := Vector2(float(info["w"]), float(info["h"]))
	var grip := Vector2(float(info["grip"][0]), float(info["grip"][1]))
	for card: MeshInstance3D in [_gun, _fist]:
		var quad: QuadMesh = card.mesh
		quad.size = size * unit
		quad.center_offset = Vector3(-(grip.x - size.x * 0.5) * unit, (grip.y - size.y * 0.5) * unit, 0.0)
	(_gun.material_override as ShaderMaterial).set_shader_parameter("art", load(WEAPONS + String(info["file"])))
	(_fist.material_override as ShaderMaterial).set_shader_parameter("art", load(WEAPONS + String(info["hands"])))
	(_fist.material_override as ShaderMaterial).set_shader_parameter("tint", skin())
