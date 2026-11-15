extends Node3D
## The loose face of a paper character: two eyes, two brows, a mustache, a
## goatee and a mouth, each its own small card laid on the body card, and the
## extras an expression can call for (a sweat drop, tears, a blush, an anger
## mark). An expression picks an eye drawing, a mouth drawing and where the
## brows sit; blinking and talking swap drawings on top of that.
##
## Built from a rig.json (written by build_lead.py, see the README):
## anchors and part sizes are in pixels of the body drawing.

## Each expression names an eye drawing, a mouth drawing and a brow drawing, then
## places the left and right brow (as seen on screen):
## [lift in eye-heights, tilt in degrees; a positive tilt drops the inner end].
## "eye_l" or "eye_r" gives that one eye a different drawing from "eyes".
## "fx" lists the extras it shows (see FX); "talk" is the set of mouths it
## talks with (see TALK; "plain" when left out).
## Brows sit under hair and hats: one lifted into the bandana goes under it.
## An expression with an eye that cannot blink (not in BLINKING_EYES: shut, a
## laugh's arcs, hearts, spirals) is a moment, not a face to stand about in: its
## "rest" names the open-eyed expression of the same mood it settles into when
## it is left on someone who is not talking (SETTLE). People are placed with
## open-eyed faces; `--check-faces` counts any that are not.
const EXPRESSIONS := {
	"neutral": {"eyes": "eye_open", "mouth": "mouth_neutral", "brows": "brow_straight", "l": [0.0, 0.0], "r": [0.0, 0.0]},
	"happy": {"eyes": "eye_open", "mouth": "mouth_smile", "brows": "brow_arched", "l": [0.06, -6.0], "r": [0.06, -6.0], "talk": "happy"},
	"grin": {"eyes": "eye_happy", "mouth": "mouth_grin", "brows": "brow_arched", "l": [0.08, -8.0], "r": [0.08, -8.0], "talk": "happy", "rest": "beaming"},
	"laugh": {"eyes": "eye_happy", "mouth": "mouth_laugh", "brows": "brow_arched", "l": [0.1, -10.0], "r": [0.1, -10.0], "talk": "happy", "rest": "beaming"},
	"wink": {"eyes": "eye_open", "eye_l": "eye_happy", "mouth": "mouth_smirk", "brows": "brow_arched", "l": [-0.08, 6.0], "r": [0.1, -6.0], "talk": "sly", "rest": "smug"},
	"calm": {"eyes": "eye_shut", "mouth": "mouth_smile", "brows": "brow_arched", "l": [0.02, -4.0], "r": [0.02, -4.0], "rest": "content"},
	"preachy": {"eyes": "eye_shut", "mouth": "mouth_small", "brows": "brow_arched", "l": [0.12, -8.0], "r": [0.12, -8.0], "rest": "lofty"},
	"focused": {"eyes": "eye_glare", "mouth": "mouth_firm", "brows": "brow_tapered", "l": [-0.16, 10.0], "r": [-0.16, 10.0]},
	"angry": {"eyes": "eye_open", "mouth": "mouth_grit", "brows": "brow_tapered", "l": [-0.14, 24.0], "r": [-0.14, 24.0], "talk": "angry"},
	"shout": {"eyes": "eye_glare", "mouth": "mouth_shout", "brows": "brow_tapered", "l": [-0.18, 22.0], "r": [-0.18, 22.0], "talk": "angry"},
	"sad": {"eyes": "eye_open", "mouth": "mouth_frown", "brows": "brow_worried", "l": [0.0, -16.0], "r": [0.0, -16.0], "talk": "sad"},
	"nervous": {"eyes": "eye_wide", "mouth": "mouth_wavy", "brows": "brow_worried", "l": [0.02, -12.0], "r": [0.02, -12.0], "fx": ["sweat"], "talk": "scared"},
	"cringe": {"eyes": "eye_squint", "mouth": "mouth_yikes", "brows": "brow_worried", "l": [-0.1, -14.0], "r": [-0.1, -14.0]},
	"shocked": {"eyes": "eye_wide", "mouth": "mouth_oh", "brows": "brow_arched", "l": [0.14, -4.0], "r": [0.14, -4.0]},
	"suspicious": {"eyes": "eye_open", "eye_l": "eye_squint", "mouth": "mouth_firm", "brows": "brow_straight", "l": [-0.2, 12.0], "r": [0.1, -8.0]},
	"side_eye": {"eyes": "eye_side", "mouth": "mouth_firm", "brows": "brow_straight", "l": [-0.14, 6.0], "r": [-0.08, -2.0]},
	"smug": {"eyes": "eye_half", "mouth": "mouth_smirk", "brows": "brow_straight", "l": [-0.06, 4.0], "r": [0.1, -10.0], "talk": "sly"},
	"bored": {"eyes": "eye_half", "mouth": "mouth_neutral", "brows": "brow_straight", "l": [-0.1, -2.0], "r": [-0.1, -2.0]},
	"scared": {"eyes": "eye_fear", "mouth": "mouth_wail", "brows": "brow_worried", "l": [0.0, -18.0], "r": [0.0, -18.0], "fx": ["sweat"], "talk": "scared"},
	"crying": {"eyes": "eye_pinch", "mouth": "mouth_wail", "brows": "brow_worried", "l": [-0.04, -22.0], "r": [-0.04, -22.0], "fx": ["tears"], "talk": "sad", "rest": "teary"},
	"hurt": {"eyes": "eye_pinch", "mouth": "mouth_grit", "brows": "brow_worried", "l": [-0.08, -20.0], "r": [-0.08, -20.0], "fx": ["sweat"], "talk": "angry", "rest": "wince"},
	"disgusted": {"eyes": "eye_half", "eye_l": "eye_squint", "mouth": "mouth_bleh", "brows": "brow_tapered", "l": [-0.18, 16.0], "r": [-0.04, -4.0]},
	"confused": {"eyes": "eye_open", "eye_l": "eye_wide", "mouth": "mouth_skew", "brows": "brow_arched", "l": [0.1, -8.0], "r": [-0.12, 10.0]},
	"embarrassed": {"eyes": "eye_happy", "mouth": "mouth_wavy", "brows": "brow_worried", "l": [0.0, -14.0], "r": [0.0, -14.0], "fx": ["blush"], "talk": "scared", "rest": "bashful"},
	"guilty": {"eyes": "eye_side", "mouth": "mouth_eek", "brows": "brow_worried", "l": [0.0, -14.0], "r": [0.0, -14.0], "fx": ["sweat"], "talk": "scared"},
	"pleading": {"eyes": "eye_shine", "mouth": "mouth_wobble", "brows": "brow_worried", "l": [-0.04, -24.0], "r": [-0.04, -24.0], "talk": "sad"},
	"dizzy": {"eyes": "eye_spiral", "mouth": "mouth_wavy", "brows": "brow_arched", "l": [0.1, -10.0], "r": [-0.06, 10.0], "rest": "confused"},
	"love": {"eyes": "eye_heart", "mouth": "mouth_smile", "brows": "brow_arched", "l": [0.08, -8.0], "r": [0.08, -8.0], "fx": ["blush"], "talk": "happy", "rest": "smitten"},
	"furious": {"eyes": "eye_glare", "mouth": "mouth_snarl", "brows": "brow_tapered", "l": [-0.22, 28.0], "r": [-0.22, 28.0], "fx": ["vein"], "talk": "angry"},
	"innocent": {"eyes": "eye_look", "mouth": "mouth_whistle", "brows": "brow_arched", "l": [0.08, -6.0], "r": [0.1, -6.0]},
	"sleepy": {"eyes": "eye_sleepy", "mouth": "mouth_small", "brows": "brow_straight", "l": [0.04, -6.0], "r": [0.04, -6.0]},
	"sly": {"eyes": "eye_glare", "mouth": "mouth_grin", "brows": "brow_tapered", "l": [-0.12, 18.0], "r": [-0.06, 12.0], "talk": "sly"},
	# The open-eyed faces the moments above settle into, each keeping its mood.
	"content": {"eyes": "eye_half", "mouth": "mouth_smile", "brows": "brow_arched", "l": [0.04, -4.0], "r": [0.04, -4.0]},
	"lofty": {"eyes": "eye_half", "mouth": "mouth_small", "brows": "brow_arched", "l": [0.14, -8.0], "r": [0.14, -8.0]},
	"beaming": {"eyes": "eye_open", "mouth": "mouth_grin", "brows": "brow_arched", "l": [0.08, -8.0], "r": [0.08, -8.0], "talk": "happy"},
	"bashful": {"eyes": "eye_side", "mouth": "mouth_wavy", "brows": "brow_worried", "l": [0.0, -14.0], "r": [0.0, -14.0], "fx": ["blush"], "talk": "scared"},
	"teary": {"eyes": "eye_shine", "mouth": "mouth_wobble", "brows": "brow_worried", "l": [-0.04, -22.0], "r": [-0.04, -22.0], "fx": ["tears"], "talk": "sad"},
	"smitten": {"eyes": "eye_shine", "mouth": "mouth_smile", "brows": "brow_arched", "l": [0.08, -8.0], "r": [0.08, -8.0], "fx": ["blush"], "talk": "happy"},
	"wince": {"eyes": "eye_squint", "mouth": "mouth_grit", "brows": "brow_worried", "l": [-0.08, -20.0], "r": [-0.08, -20.0], "fx": ["sweat"], "talk": "angry"},
}
## The mouths a face flaps between while talking, by the feeling it talks with.
## Every set opens and shuts; an angry face talks through its teeth, a sad one
## through a frown.
const TALK := {
	"plain": ["mouth_small", "mouth_ah", "mouth_oh", "mouth_ee", "mouth_ff", "mouth_neutral"],
	"happy": ["mouth_smile", "mouth_laugh", "mouth_ee", "mouth_small", "mouth_ah"],
	"angry": ["mouth_grit", "mouth_shout", "mouth_ee", "mouth_snarl", "mouth_ah"],
	"sad": ["mouth_frown", "mouth_small", "mouth_oh", "mouth_wail", "mouth_wobble"],
	"scared": ["mouth_yikes", "mouth_oh", "mouth_ee", "mouth_wavy", "mouth_small"],
	"sly": ["mouth_smirk", "mouth_small", "mouth_ee", "mouth_ah", "mouth_ff"],
}
## The extras. "part" is the drawing; "front" and "side" say where it goes on
## that view: [the eye it hangs from, eye widths outwards (away from the middle
## of the face; on the profile, towards the back of the head), eye heights
## down]. A "pair" shows by both eyes, the right one mirrored, and goes from
## each eye; on the profile only the near one shows. "clip": shown only over
## skin. "bob": eye heights it drifts up and down; "pulse": how much it swells.
const FX := {
	"sweat": {"part": "fx_sweat", "front": ["r", 1.95, -0.5], "side": ["l", 1.75, -0.45], "bob": 0.04},
	"vein": {"part": "fx_vein", "front": ["r", 1.45, -1.0], "side": ["l", 1.25, -1.0], "pulse": 0.1},
	"tears": {"part": "fx_tear", "pair": true, "front": ["", 0.62, 0.12], "side": ["", 0.15, 0.36], "clip": true, "bob": 0.025},
	"blush": {"part": "fx_blush", "pair": true, "front": ["", 0.6, 0.58], "side": ["", 0.95, 0.5], "clip": true},
}
const BLINKING_EYES := ["eye_open", "eye_half", "eye_wide", "eye_fear", "eye_squint", "eye_glare", "eye_side", "eye_look", "eye_shine", "eye_sleepy"]
## On its way shut and open again a blink shows this drawing for a moment, so the eye does not jump.
const HALF_SHUT := {"eye_open": "eye_half", "eye_shine": "eye_half"}
const BLINK := [0.03, 0.1, 0.13]      # seconds into a blink: half shut until, shut until, half shut until
## Looking aside (look()), an eye under a heavy lid keeps it: it glances sideways under the lid.
const LIDDED := ["eye_half", "eye_glare", "eye_squint", "eye_sleepy"]
## The slots shown only over the skin of the drawing under them (they go under hair, hats and the outline).
const ON_SKIN := ["mouth", "eye_l", "eye_r", "brow_l", "brow_r"]
## A rig made before a drawing was added shows the plain one of its kind instead.
const PLAIN := {"eye_": "eye_open", "mouth_": "mouth_neutral", "brow_": "brow_straight"}
const FACE_SHADER := preload("res://shaders/paper_face.gdshader")
const LIFT := 0.012        # how much nearer the eye than the body card the face is drawn, metres
const SETTLE := 1.5        # seconds a moment (an expression whose eyes cannot blink) lasts on someone not talking

var expression := "neutral"     # the expression on show (a moment may have settled into its "rest")
var asked := "neutral"          # the expression last asked for with set_expression
var talking := false
var hold := false               # keep a moment as it is: someone asleep or out cold, or a still picture of it

var _dir := ""
var _rig := {}
var _m := 0.001            # metres per pixel of the body drawing
var _body := Vector2.ONE   # body drawing size, pixels
var _tilt := 0.0
var _eye_h := 0.1          # metres
var _eye_w := 0.05         # metres
var _nodes := {}           # slot name: MeshInstance3D
var _textures := {}
var _eyes := ["eye_open", "eye_open"]            # left, right as seen on screen
var _mouth := "mouth_neutral"
var _held_mouth := ""
var _talk_set: Array = TALK["plain"]
var _fx: Array = []                              # the extras on show
var _fx_time := 0.0
var _brow_now := [Vector2.ZERO, Vector2.ZERO]   # x lift, y tilt
var _brow_goal := [Vector2.ZERO, Vector2.ZERO]
var _look := 0.0           # -1: he looks to the left of the screen, 1: to the right, 0: wherever the expression looks
var _blink_in := 2.0
var _blink_t := -1.0       # seconds into a blink, or -1
var _blink_stage := 0      # 0 open, 1 half shut, 2 shut
var _talk_in := 0.0
var _rng := RandomNumberGenerator.new()
var _layout := {}          # how the face sits on the drawing on show; empty for the front
var _hidden: Array = []    # slots the drawing on show leaves out
var _mouth_now := ""       # the mouth on show, by its front name
var _under: Texture2D      # the body drawing on show (parts on skin are cut off by what is not skin)
var _still := 0.0          # seconds a moment has been on show without talking (it settles at SETTLE)


func setup(dir: String, rig: Dictionary, card_height: float, body_px: Vector2) -> void:
	_dir = dir
	_rig = rig
	_body = body_px
	_m = card_height / body_px.y
	_tilt = deg_to_rad(float(rig["tilt_deg"]))
	_eye_h = float(rig["parts"]["eye_open"]["h"]) * _m
	_eye_w = float(rig["parts"]["eye_open"]["w"]) * _m
	# Bottom to top. The extras are made only for a rig that has their drawings.
	var slots := ["goatee", "stache_l", "stache_r", "mouth"]
	slots += _fx_slots("blush")
	slots += ["eye_l", "eye_r"]
	slots += _fx_slots("tears")
	slots += ["brow_l", "brow_r"]
	slots += _fx_slots("sweat") + _fx_slots("vein")
	var layer := 0
	for slot: String in slots:
		var node := MeshInstance3D.new()
		node.mesh = QuadMesh.new()
		# The parts lie flat on the card. The shader draws each one over the card
		# and over the parts under it (see paper_face.gdshader).
		var mat := ShaderMaterial.new()
		mat.shader = FACE_SHADER
		mat.set_shader_parameter("toward", LIFT + 0.002 * layer)
		node.material_override = mat
		node.set_meta("layer", layer)
		node.set_meta("clip", slot in ON_SKIN)
		node.rotation.z = _tilt
		add_child(node)
		_nodes[slot] = node
		layer += 1
	for slot in ["goatee", "stache_l", "stache_r"]:
		_put(slot, slot)
		_nodes[slot].rotation.z = 0.0      # cut from the drawing, so already tilted
	_nodes["brow_r"].scale.x = -1.0        # the right brow is the left one mirrored; so are the eyes, in _put
	for kind: String in FX:
		for slot: String in _fx_slots(kind):
			var node: MeshInstance3D = _nodes[slot]
			node.set_meta("clip", FX[kind].get("clip", false))
			node.visible = false
			_put(slot, FX[kind]["part"])
	set_side(1.0)
	set_expression("neutral", true)


## The slots an extra needs: none if the rig has no drawing for it.
func _fx_slots(kind: String) -> Array:
	if not _rig["parts"].has(FX[kind]["part"]):
		return []
	return [kind + "_l", kind + "_r"] if FX[kind].get("pair", false) else [kind]


func names() -> Array:
	return EXPRESSIONS.keys()


## The mouth on show right now, by its front name.
func shown_mouth() -> String:
	return _mouth_now


func set_expression(wanted: String, snap := false) -> void:
	if not EXPRESSIONS.has(wanted):
		push_warning("No expression called %s" % wanted)
		return
	asked = wanted
	_still = 0.0
	_apply(wanted, snap)


## Can both eyes of this expression blink? If not it is a moment (see EXPRESSIONS).
static func blinks(name: String) -> bool:
	var e: Dictionary = EXPRESSIONS.get(name, EXPRESSIONS["neutral"])
	return e.get("eye_l", e["eyes"]) in BLINKING_EYES and e.get("eye_r", e["eyes"]) in BLINKING_EYES


## The open-eyed expression a moment settles into (itself, for one that can blink).
static func rest_of(name: String) -> String:
	return String(EXPRESSIONS.get(name, {}).get("rest", name))


## Can the eyes on show blink? True where the drawing on show hides them (shades, the back of his head).
func can_blink() -> bool:
	for i in 2:
		if not ["eye_l", "eye_r"][i] in _hidden and not _eyes[i] in BLINKING_EYES:
			return false
	return true


## A moment has lasted long enough: the open-eyed face of its mood, the eyes opening as from a blink.
func _settle() -> void:
	_still = 0.0
	_apply(rest_of(expression), false)
	_blink_t = BLINK[0]
	_blink_stage = 2
	_show_eyes()


func _apply(wanted: String, snap: bool) -> void:
	expression = wanted
	var e: Dictionary = EXPRESSIONS[wanted]
	_eyes = [e.get("eye_l", e["eyes"]), e.get("eye_r", e["eyes"])]
	_mouth = e["mouth"]
	_talk_set = TALK.get(e.get("talk", "plain"), TALK["plain"])
	_fx = e.get("fx", [])
	_put("brow_l", _part(e["brows"]))
	_put("brow_r", _part(e["brows"]))
	_brow_goal = [Vector2(e["l"][0], e["l"][1]), Vector2(e["r"][0], e["r"][1])]
	if snap:
		_brow_now = _brow_goal.duplicate()
	_blink_t = -1.0
	_blink_stage = 0
	_show_eyes()
	_show_mouth(_mouth)
	_place_brows()
	_place_fx()


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
	_hidden = layout.get("hide", [])
	for slot: String in _nodes:
		var node: MeshInstance3D = _nodes[slot]
		if not FX.has(_fx_name(slot)):     # the extras are shown by _place_fx
			node.visible = not slot in _hidden
		if slot.begins_with("eye"):
			node.rotation.z = _tilt
		var at := _spot(slot) if _rig["anchors"].has(slot) else Vector2.ZERO
		node.position.x = at.x
		node.position.y = at.y
		_clip(node)
	if _mouth_now != "":
		_show_mouth(_mouth_now)
	_place_brows()
	_place_fx()


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
	if not _fx.is_empty():
		_fx_time += delta
		_place_fx()

	# A moment (eyes that cannot blink) left on someone who is not talking settles into its open-eyed rest.
	if talking or hold or not EXPRESSIONS[expression].has("rest"):
		_still = 0.0
	else:
		_still += delta
		if _still >= SETTLE:
			_settle()

	# Blink: half shut, shut, half shut, open.
	if _blink_t >= 0.0:
		_blink_t += delta
		var stage: int = 1 if _blink_t < BLINK[0] else 2 if _blink_t < BLINK[1] else 1 if _blink_t < BLINK[2] else 0
		if stage == 0:
			_blink_t = -1.0
		if stage != _blink_stage:
			_blink_stage = stage
			_show_eyes()
	elif _eyes[0] in BLINKING_EYES or _eyes[1] in BLINKING_EYES:
		_blink_in -= delta
		if _blink_in <= 0.0:
			_blink_in = _rng.randf_range(2.2, 5.5)
			_blink_t = 0.0
			_blink_stage = 1
			_show_eyes()

	# Talk: flap between the expression's talking mouths, never the same one twice running.
	if _held_mouth != "":
		return
	if talking:
		_talk_in -= delta
		if _talk_in <= 0.0:
			_talk_in = _rng.randf_range(0.07, 0.15)
			var shape: String = _talk_set[_rng.randi() % _talk_set.size()]
			while shape == _mouth_now:
				shape = _talk_set[_rng.randi() % _talk_set.size()]
			_show_mouth(shape)
	elif _mouth_now != _mouth:
		_talk_in = 0.0
		_show_mouth(_mouth)


## Look to one side of the screen (-1 left, 1 right) whatever the expression's
## eyes are doing, or 0 to go back to them. He still blinks.
func look(side: float) -> void:
	_look = signf(side)
	_show_eyes()


## Each eye shows its own drawing; in a blink, an eye that is open shuts.
## Looking aside, both show a looking-aside drawing (a white eye, the pupil hard
## against one side; under a lid if the eye had one), turned to look that way.
func _show_eyes() -> void:
	for i in 2:
		var slot: String = ["eye_l", "eye_r"][i]
		var part: String = _eyes[i]
		if _look != 0.0 and part in BLINKING_EYES:
			part = "eye_side" if part in LIDDED or not _rig["parts"].has("eye_look") else "eye_look"
		if _blink_stage == 2 and part in BLINKING_EYES:
			part = "eye_shut"
		elif _blink_stage == 1 and HALF_SHUT.has(part) and _rig["parts"].has(HALF_SHUT[part]):
			part = HALF_SHUT[part]
		part = _part(part)
		_put(slot, part)
		if part in ["eye_look", "eye_side"] and _look != 0.0:
			_nodes[slot].scale.x = _look            # as drawn, it looks to the right
		else:
			var mirrored: bool = i == 1 and _rig["parts"][part].get("mirror", true)
			_nodes[slot].scale.x = -1.0 if mirrored else 1.0
		_clip(_nodes[slot])


func _show_mouth(part: String) -> void:
	_mouth_now = part
	# A view can have its own drawing of each mouth (the profile's are cut to the edge of the face).
	var drawing: String = str(_layout.get("mouth_prefix", "")) + part
	if not _rig["parts"].has(drawing):
		drawing = _part(part)
	_put("mouth", drawing)
	var info: Dictionary = _rig["parts"][drawing]
	var node: MeshInstance3D = _nodes["mouth"]
	if info.has("at"):      # made for one view: it says exactly where its middle goes
		node.rotation.z = 0.0
		node.position.x = (float(info["at"][0]) - _body.x * 0.5) * _m
		node.position.y = (_body.y - float(info["at"][1])) * _m
	else:
		# The anchor is the lip line. A part says how far below its top edge that
		# line is ("lip"); without it the part is centred on the line.
		node.rotation.z = _tilt
		var half := float(info["h"]) * 0.5
		var drop := (half - float(info.get("lip", half))) * _m
		var at := _spot("mouth")
		node.position.x = at.x + sin(_tilt) * drop
		node.position.y = at.y - cos(_tilt) * drop
	_clip(node)


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
		_clip(node)


## Put the extras the expression wants where FX says, and hide the rest.
func _place_fx() -> void:
	var profile: bool = "eye_r" in _hidden
	for kind: String in FX:
		var info: Dictionary = FX[kind]
		var slots := _fx_slots(kind)
		for n in slots.size():
			var slot: String = slots[n]
			var node: MeshInstance3D = _nodes[slot]
			var right: bool = slot.ends_with("_r") or (slots.size() == 1 and info["front"][0] == "r" and not profile)
			node.visible = kind in _fx and not "eye_l" in _hidden and not (profile and slot.ends_with("_r"))
			if not node.visible:
				continue
			var where: Array = info["side" if profile else "front"]
			var eye := "eye_r" if right else "eye_l"
			var out := 1.0 if right else -1.0     # outwards, as seen on screen
			var at := _spot(eye)
			var across: float = float(where[1]) * _eye_w * out
			var down: float = float(where[2]) * _eye_h + sin(_fx_time * 3.1) * float(info.get("bob", 0.0)) * _eye_h
			node.rotation.z = _tilt
			node.position.x = at.x + cos(_tilt) * across + sin(_tilt) * down
			node.position.y = at.y + sin(_tilt) * across - cos(_tilt) * down
			var swell := 1.0 + sin(_fx_time * 9.0) * float(info.get("pulse", 0.0))
			var mirrored: bool = right and slots.size() == 2 and _rig["parts"][info["part"]].get("mirror", true)
			node.scale = Vector3(-swell if mirrored else swell, swell, 1.0)
			_clip(node)


func _fx_name(slot: String) -> String:
	return slot.trim_suffix("_l").trim_suffix("_r")


## The drawing to show for `part`: itself, or the plain one of its kind if the rig has no such drawing.
func _part(part: String) -> String:
	if _rig["parts"].has(part):
		return part
	for kind: String in PLAIN:
		if part.begins_with(kind):
			return PLAIN[kind]
	return part


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
	if FX.has(_fx_name(slot)):
		return              # the extras are placed by _place_fx
	if slot == "eye_r":    # mirrored, unless the drawing looks one way (the side-eye)
		node.scale.x = -1.0 if info.get("mirror", true) else 1.0
	var at := _spot(slot)
	node.position.x = at.x
	node.position.y = at.y
	_clip(node)


## Tell a part's shader where it lies on the drawing under it, so that one kept
## to the skin is drawn only where that drawing is bare skin: not over hair, a
## hat, the outline or nothing. The skin is the drawing's colour at an eye
## anchor (the faces are drawn blank, so that is always bare skin).
func _clip(node: MeshInstance3D) -> void:
	var mat: ShaderMaterial = node.material_override
	var on: bool = _under != null and node.get_meta("clip", false)
	mat.set_shader_parameter("clip", on)
	if not on:
		return
	var size: Vector2 = (node.mesh as QuadMesh).size
	var c := cos(node.rotation.z)
	var s := sin(node.rotation.z)
	var sx: float = node.scale.x
	var sy: float = node.scale.y
	# Card space (metres, y up) of the art's top-left corner, and how far its UV x and y run.
	var corner := Vector2(node.position.x, node.position.y) + Vector2(-c * 0.5 * size.x * sx - s * 0.5 * size.y * sy, -s * 0.5 * size.x * sx + c * 0.5 * size.y * sy)
	var du := Vector2(c * size.x * sx, s * size.x * sx)
	var dv := Vector2(s * size.y * sy, -c * size.y * sy)
	mat.set_shader_parameter("body", _under)
	mat.set_shader_parameter("body_o", _to_uv(corner))
	mat.set_shader_parameter("body_u", Vector2(du.x / _m / _body.x, -du.y / _m / _body.y))
	mat.set_shader_parameter("body_v", Vector2(dv.x / _m / _body.x, -dv.y / _m / _body.y))
	mat.set_shader_parameter("skin_at", _to_uv(_spot("eye_l")))


## A point in card space as a UV of the body drawing.
func _to_uv(p: Vector2) -> Vector2:
	return Vector2((p.x / _m + _body.x * 0.5) / _body.x, (_body.y - p.y / _m) / _body.y)


## An anchor in card space (x right from the centre line, y up from the feet).
func _spot(slot: String) -> Vector2:
	var a: Array = _layout.get("anchors", {}).get(slot, _rig["anchors"][slot])
	return Vector2((float(a[0]) - _body.x * 0.5) * _m, (_body.y - float(a[1])) * _m)
