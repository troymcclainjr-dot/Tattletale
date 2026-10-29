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
	body_y = body.position.y if body.position.y > 0.0 else 0.47 * H


## pose(r,p) from characters.js. Arms as [forward-raise (negative = up/forward), outward];
## legs swing with the walk phase.
func pose(p: Dictionary) -> void:
	var walk: float = p.get("walk", 0.0)
	var sw := sin(phase) * walk if walk != 0.0 else 0.0
	legs[0].rotation.x = sw
	legs[1].rotation.x = -sw
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
