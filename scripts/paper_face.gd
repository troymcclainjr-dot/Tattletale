extends Node3D
## The loose face of a paper character: two eyes, two brows, a mustache and a
## mouth, each its own small card laid on the body card. An expression picks an
## eye drawing, a mouth drawing and where the brows sit; blinking and talking
## swap drawings on top of that.
##
## Built from a rig.json (written by build_lead.py, see the README):
## anchors and part sizes are in pixels of the body drawing.

## Each expression names an eye drawing, a mouth drawing and a brow drawing, then
## places the left and right brow (as seen on screen):
## [lift in eye-heights, tilt in degrees; a positive tilt drops the inner end].
## "eye_l" or "eye_r" gives that one eye a different drawing from "eyes".
const EXPRESSIONS := {
	"neutral": {"eyes": "eye_open", "mouth": "mouth_neutral", "brows": "brow_straight", "l": [0.0, 0.0], "r": [0.0, 0.0]},
	"happy": {"eyes": "eye_open", "mouth": "mouth_smile", "brows": "brow_arched", "l": [0.14, -4.0], "r": [0.14, -4.0]},
	"grin": {"eyes": "eye_happy", "mouth": "mouth_grin", "brows": "brow_arched", "l": [0.16, -6.0], "r": [0.16, -6.0]},
	"laugh": {"eyes": "eye_happy", "mouth": "mouth_laugh", "brows": "brow_arched", "l": [0.22, -8.0], "r": [0.22, -8.0]},
	"wink": {"eyes": "eye_open", "eye_l": "eye_happy", "mouth": "mouth_smirk", "brows": "brow_arched", "l": [-0.12, 0.0], "r": [0.2, -6.0]},
	"calm": {"eyes": "eye_shut", "mouth": "mouth_smile", "brows": "brow_straight", "l": [0.04, -3.0], "r": [0.04, -3.0]},
	"preachy": {"eyes": "eye_shut", "mouth": "mouth_small", "brows": "brow_arched", "l": [0.3, -4.0], "r": [0.3, -4.0]},
	"focused": {"eyes": "eye_glare", "mouth": "mouth_firm", "brows": "brow_straight", "l": [-0.36, 9.0], "r": [-0.36, 9.0]},
	"angry": {"eyes": "eye_open", "mouth": "mouth_grit", "brows": "brow_straight", "l": [-0.2, 24.0], "r": [-0.2, 24.0]},
	"shout": {"eyes": "eye_glare", "mouth": "mouth_shout", "brows": "brow_straight", "l": [-0.32, 24.0], "r": [-0.32, 24.0]},
	"sad": {"eyes": "eye_open", "mouth": "mouth_frown", "brows": "brow_straight", "l": [0.06, -22.0], "r": [0.06, -22.0]},
	"nervous": {"eyes": "eye_wide", "mouth": "mouth_wavy", "brows": "brow_straight", "l": [0.22, -20.0], "r": [0.22, -20.0]},
	"cringe": {"eyes": "eye_squint", "mouth": "mouth_grit", "brows": "brow_straight", "l": [-0.12, -16.0], "r": [-0.12, -16.0]},
	"shocked": {"eyes": "eye_wide", "mouth": "mouth_oh", "brows": "brow_arched", "l": [0.3, -6.0], "r": [0.3, -6.0]},
	"suspicious": {"eyes": "eye_open", "eye_l": "eye_squint", "mouth": "mouth_firm", "brows": "brow_straight", "l": [-0.34, 8.0], "r": [0.22, -8.0]},
	"side_eye": {"eyes": "eye_side", "mouth": "mouth_neutral", "brows": "brow_straight", "l": [-0.3, 4.0], "r": [-0.24, -6.0]},
	"smug": {"eyes": "eye_half", "mouth": "mouth_smirk", "brows": "brow_straight", "l": [-0.08, 0.0], "r": [0.2, -10.0]},
	"bored": {"eyes": "eye_half", "mouth": "mouth_neutral", "brows": "brow_straight", "l": [-0.06, 0.0], "r": [-0.06, 0.0]},
}
const TALK_SHAPES := ["mouth_small", "mouth_ah", "mouth_oh", "mouth_ee", "mouth_ff", "mouth_neutral"]
const BLINKING_EYES := ["eye_open", "eye_half", "eye_wide", "eye_squint", "eye_glare", "eye_side", "eye_look"]
const FACE_SHADER := preload("res://shaders/paper_face.gdshader")
const LIFT := 0.012        # how much nearer the eye than the body card the face is drawn, metres

var expression := "neutral"
var talking := false

var _dir := ""
var _rig := {}
var _m := 0.001            # metres per pixel of the body drawing
var _body := Vector2.ONE   # body drawing size, pixels
var _tilt := 0.0
var _eye_h := 0.1          # metres
var _nodes := {}           # slot name: MeshInstance3D
var _textures := {}
var _eyes := ["eye_open", "eye_open"]            # left, right as seen on screen
var _mouth := "mouth_neutral"
var _held_mouth := ""
var _brow_now := [Vector2.ZERO, Vector2.ZERO]   # x lift, y tilt
var _brow_goal := [Vector2.ZERO, Vector2.ZERO]
var _look := 0.0           # -1: he looks to the left of the screen, 1: to the right, 0: wherever the expression looks
var _blink_in := 2.0
var _blink_left := 0.0
var _talk_in := 0.0
var _rng := RandomNumberGenerator.new()
var _layout := {}          # how the face sits on the drawing on show; empty for the front
var _mouth_now := ""       # the mouth on show, by its front name
var _under: Texture2D      # the body drawing on show (profile mouths are cut off by its outline)


func setup(dir: String, rig: Dictionary, card_height: float, body_px: Vector2) -> void:
	_dir = dir
	_rig = rig
	_body = body_px
	_m = card_height / body_px.y
	_tilt = deg_to_rad(float(rig["tilt_deg"]))
	_eye_h = float(rig["parts"]["eye_open"]["h"]) * _m
	var layer := 0
	for slot in ["goatee", "stache_l", "stache_r", "mouth", "eye_l", "eye_r", "brow_l", "brow_r"]:
		var node := MeshInstance3D.new()
		node.mesh = QuadMesh.new()
		# The parts lie flat on the card. The shader draws each one over the card
		# and over the parts under it (see paper_face.gdshader).
		var mat := ShaderMaterial.new()
		mat.shader = FACE_SHADER
		mat.set_shader_parameter("toward", LIFT + 0.002 * layer)
		node.material_override = mat
		node.set_meta("layer", layer)
		node.rotation.z = _tilt
		add_child(node)
		_nodes[slot] = node
		layer += 1
	for slot in ["goatee", "stache_l", "stache_r"]:
		_put(slot, slot)
		_nodes[slot].rotation.z = 0.0      # cut from the drawing, so already tilted
	_nodes["brow_r"].scale.x = -1.0        # the right brow is the left one mirrored; so are the eyes, in _put
	set_side(1.0)
	set_expression("neutral", true)


func names() -> Array:
	return EXPRESSIONS.keys()


## The mouth on show right now, by its front name.
func shown_mouth() -> String:
	return _mouth_now


func set_expression(wanted: String, snap := false) -> void:
	if not EXPRESSIONS.has(wanted):
		push_warning("No expression called %s" % wanted)
		return
	expression = wanted
	var e: Dictionary = EXPRESSIONS[wanted]
	_eyes = [e.get("eye_l", e["eyes"]), e.get("eye_r", e["eyes"])]
	_mouth = e["mouth"]
	_put("brow_l", e["brows"])
	_put("brow_r", e["brows"])
	_brow_goal = [Vector2(e["l"][0], e["l"][1]), Vector2(e["r"][0], e["r"][1])]
	if snap:
		_brow_now = _brow_goal.duplicate()
	_blink_left = 0.0
	_show_eyes(false)
	_show_mouth(_mouth)
	_place_brows()


## Hold one mouth drawing whatever the expression says ("" lets go). For stills.
func hold_mouth(part: String) -> void:
	_held_mouth = part
	_show_mouth(part if part != "" else _mouth)


## Fit the face to one of the body's drawings. An empty layout is the front: the
## rig's own anchors and head tilt, every slot shown. A layout can give its own
## "anchors" and "tilt_deg", "hide" slots (a profile shows one eye and one
## brow), and name a "mouth_prefix" for mouth drawings made for that view.
func set_layout(layout: Dictionary, drawing: Texture2D = null) -> void:
	_layout = layout
	_under = drawing
	_tilt = deg_to_rad(float(layout.get("tilt_deg", _rig["tilt_deg"])))
	var hidden: Array = layout.get("hide", [])
	for slot: String in _nodes:
		var node: MeshInstance3D = _nodes[slot]
		node.visible = not slot in hidden
		if slot.begins_with("eye"):
			node.rotation.z = _tilt
		var at := _spot(slot)
		node.position.x = at.x
		node.position.y = at.y
	if _mouth_now != "":
		_show_mouth(_mouth_now)
	_place_brows()


## Which face of the body card the camera sees: 1 as drawn, -1 mirrored. The
## parts lie on the card either way, so there is nothing to move.
func set_side(_side: float) -> void:
	pass


func _process(delta: float) -> void:
	# Brows ease to where the expression wants them.
	var k := 1.0 - exp(-16.0 * delta)
	for i in 2:
		_brow_now[i] = _brow_now[i].lerp(_brow_goal[i], k)
	_place_brows()

	# Blink.
	if _blink_left > 0.0:
		_blink_left -= delta
		if _blink_left <= 0.0:
			_show_eyes(false)
	elif _eyes[0] in BLINKING_EYES or _eyes[1] in BLINKING_EYES:
		_blink_in -= delta
		if _blink_in <= 0.0:
			_blink_in = _rng.randf_range(2.2, 5.5)
			_blink_left = 0.11
			_show_eyes(true)

	# Talk: flap between mouth shapes, never the same one twice running.
	if _held_mouth != "":
		return
	if talking:
		_talk_in -= delta
		if _talk_in <= 0.0:
			_talk_in = _rng.randf_range(0.07, 0.15)
			var shape: String = TALK_SHAPES[_rng.randi() % TALK_SHAPES.size()]
			while shape == _mouth_now:
				shape = TALK_SHAPES[_rng.randi() % TALK_SHAPES.size()]
			_show_mouth(shape)
	elif _mouth_now != _mouth:
		_talk_in = 0.0
		_show_mouth(_mouth)


## Look to one side of the screen (-1 left, 1 right) whatever the expression's
## eyes are doing, or 0 to go back to them. He still blinks.
func look(side: float) -> void:
	_look = signf(side)
	_show_eyes(_blink_left > 0.0)


## Each eye shows its own drawing; in a blink, an eye that is open shuts.
## Looking aside, both show the looking-aside drawing (a white eye, the pupil
## hard against one side), turned to look that way.
func _show_eyes(blink: bool) -> void:
	for i in 2:
		var slot: String = ["eye_l", "eye_r"][i]
		var part: String = _eyes[i]
		if _look != 0.0 and part in BLINKING_EYES:
			part = "eye_look" if _rig["parts"].has("eye_look") else "eye_side"
		if blink and part in BLINKING_EYES:
			part = "eye_shut"
		_put(slot, part)
		if part in ["eye_look", "eye_side"] and _look != 0.0:
			_nodes[slot].scale.x = _look            # as drawn, it looks to the right
		else:
			var mirrored: bool = i == 1 and _rig["parts"][part].get("mirror", true)
			_nodes[slot].scale.x = -1.0 if mirrored else 1.0


func _show_mouth(part: String) -> void:
	_mouth_now = part
	# A view can have its own drawing of each mouth (the profile's are cut to the edge of the face).
	var drawing: String = str(_layout.get("mouth_prefix", "")) + part
	if not _rig["parts"].has(drawing):
		drawing = part
	_put("mouth", drawing)
	var info: Dictionary = _rig["parts"][drawing]
	var node: MeshInstance3D = _nodes["mouth"]
	var mat: ShaderMaterial = node.material_override
	mat.set_shader_parameter("clip", info.has("at") and _under != null)
	if info.has("at"):      # made for one view: it says exactly where its middle goes
		node.rotation.z = 0.0
		node.position.x = (float(info["at"][0]) - _body.x * 0.5) * _m
		node.position.y = (_body.y - float(info["at"][1])) * _m
		# It runs under the head outline: the shader shows it only over skin.
		var size := Vector2(float(info["w"]), float(info["h"]))
		var corner := Vector2(float(info["at"][0]), float(info["at"][1])) - size * 0.5
		mat.set_shader_parameter("body", _under)
		mat.set_shader_parameter("body_rect", Vector4(corner.x / _body.x, corner.y / _body.y, size.x / _body.x, size.y / _body.y))
		return
	# The anchor is the lip line. A part says how far below its top edge that
	# line is ("lip"); without it the part is centred on the line.
	node.rotation.z = _tilt
	var half := float(info["h"]) * 0.5
	var drop := (half - float(info.get("lip", half))) * _m
	var at := _spot("mouth")
	node.position.x = at.x + sin(_tilt) * drop
	node.position.y = at.y - cos(_tilt) * drop


func _place_brows() -> void:
	for i in 2:
		var slot: String = ["brow_l", "brow_r"][i]
		var node: MeshInstance3D = _nodes[slot]
		var at := _spot(slot)
		var lift: float = _brow_now[i].x * _eye_h
		node.position.x = at.x - sin(_tilt) * lift
		node.position.y = at.y + cos(_tilt) * lift
		# The inner end is the right end of the left brow and the left end of the right.
		var lean := deg_to_rad(_brow_now[i].y) * (-1.0 if i == 0 else 1.0)
		node.rotation.z = _tilt + lean


## Put a drawing in a slot, centred on the slot's anchor.
func _put(slot: String, part: String) -> void:
	var node: MeshInstance3D = _nodes[slot]
	if node.get_meta("part", "") == part:
		return
	if not _rig["parts"].has(part):
		push_warning("No face part called %s" % part)
		return
	var info: Dictionary = _rig["parts"][part]
	if not _textures.has(part):
		_textures[part] = load(_dir.path_join(info["file"]))
	(node.mesh as QuadMesh).size = Vector2(float(info["w"]), float(info["h"])) * _m
	(node.material_override as ShaderMaterial).set_shader_parameter("art", _textures[part])
	node.set_meta("part", part)
	if slot == "eye_r":    # mirrored, unless the drawing looks one way (the side-eye)
		node.scale.x = -1.0 if info.get("mirror", true) else 1.0
	var at := _spot(slot)
	node.position.x = at.x
	node.position.y = at.y


## An anchor in card space (x right from the centre line, y up from the feet).
func _spot(slot: String) -> Vector2:
	var a: Array = _layout.get("anchors", {}).get(slot, _rig["anchors"][slot])
	return Vector2((float(a[0]) - _body.x * 0.5) * _m, (_body.y - float(a[1])) * _m)
