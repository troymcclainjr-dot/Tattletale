extends Node
## Driver for tools/pose_check.gd.

const CASES := [
	# id, label, armR, target ("mouth" or "ear")
	["cop_dan", "donut bite (JS)", [-2.4, 0.25], "mouth"],
	["cop_dan", "donut bite (now)", Animate.HAND_TO_MOUTH, "mouth"],
	["gary", "pipe (JS)", [-2.6, 0.35], "mouth"],
	["gary", "pipe (now)", Animate.HAND_TO_MOUTH, "mouth"],
	["gary", "phone (JS)", [-2.9, 0.75], "ear"],
	["gary", "phone (now)", Animate.PHONE_AT_EAR, "ear"],
	["two_pack", "payphone (JS)", [-2.75, 0.55], "ear"],
	["two_pack", "payphone (now)", Animate.PHONE_AT_EAR, "ear"],
]


func _ready() -> void:
	var holder := Node3D.new()
	add_child(holder)
	var made := {}
	for c in CASES:
		var id: String = c[0]
		if not made.has(id):
			made[id] = Cast.person(id, holder)
		var r: Puppet = made[id]
		r.g.global_transform = Transform3D.IDENTITY
		r.pose({"armR": c[2], "armL": [-0.3, 0.1]})
		var hand: Vector3 = r.hands[0].global_position
		var face: Vector3
		if c[3] == "mouth":
			face = r.mouth.global_position + r.head.global_basis.z * 0.02 * r.H
		else:
			face = r.head.to_global(Vector3(-0.118 * r.H, r.hy, 0.0))
		print("%-9s %-17s hand->%-5s %.2f m" % [id, c[1], c[3], hand.distance_to(face)])
	get_tree().quit()
