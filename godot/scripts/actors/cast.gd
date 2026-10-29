class_name Cast
## Building the clay people (characters.js makePerson + make2Pack/makeRicky/makeCop/makeGranny/makeGary).
## Each character loads characters/<id>.glb when it exists and follows the rig contract;
## otherwise a procedural puppet with the same node names is built from primitives.

const LOOKS := {
	"two_pack": {"h": 1.8, "skin": "#6e4228", "shirtless": true, "pants": "#2a4a7a", "shoes": "#f4f4f4", "style": "bald"},
	"ricky": {"h": 1.76, "skin": "#e8b48a", "stripes": true, "pants": "#1a1a1e", "shoes": "#0a0a0c", "hair": "#141010", "style": "short"},
	"granny": {"h": 1.5, "skin": "#ecc0a0", "top": "#b88ac8", "pants": "#6a5a7a", "shoes": "#4a3a3a", "hair": "#d8d8d8", "style": "bun", "glasses": true},
	"gary": {"h": 1.72, "skin": "#c8a888", "top": "#7a7258", "pants": "#4a4436", "shoes": "#2a2a2a", "hair": "#6a5a3a", "style": "long", "belly": 0.55},
	"timmy": {"h": 0.95, "skin": "#8a5a3c", "top": "#2a8a3a", "pants": "#f2c21a", "shoes": "#c4162a", "hair": "#3a2414", "style": "short"},
	"mailman": {"h": 1.75, "skin": "#e8b48a", "top": "#6a8ac8", "pants": "#2a3a6a", "hair": "#5a3a1a", "style": "short", "mustache": true},
	"cop_dan": {"h": 1.8, "top": "#1a2a5a", "pants": "#1a2a5a", "shoes": "#0a0a0c", "style": "short", "skin": "#e8b48a", "hair": "#5a3a1a", "mustache": true, "belly": 1.45},
	"cop_steve": {"h": 1.88, "top": "#1a2a5a", "pants": "#1a2a5a", "shoes": "#0a0a0c", "style": "short", "skin": "#c48e64", "hair": "#141010", "glasses": true},
	"mama": {"h": 1.68, "skin": "#8a5a3c", "top": "#e84a9a", "pants": "#2a2a30", "shoes": "#f4f0e6", "hair": "#141010", "style": "bun"},
	"dad": {"h": 1.8, "skin": "#8a5a3c", "top": "#f4f0e6", "pants": "#4a4a5a", "shoes": "#2a2a2a", "style": "bald", "belly": 1.4, "mustache": true, "hair": "#141010"},
	"vendor": {"h": 1.78, "skin": "#c48e64", "top": "#f4f0e6", "pants": "#3a3a40", "hair": "#141010", "style": "short"},
	"liner_1": {"h": 1.7, "skin": "#e8b48a", "hair": "#c8642a", "style": "long", "top": "#2ad0a8", "pants": "#2a2a30"},
	"liner_2": {"h": 1.85, "skin": "#5c3a26", "hair": "#141010", "style": "short", "top": "#ff8a1a", "pants": "#2a2a30"},
	"liner_3": {"h": 1.6, "skin": "#c48e64", "hair": "#3a2a1a", "style": "bob", "top": "#8a2ad0", "pants": "#2a2a30"},
	"liner_4": {"h": 1.78, "skin": "#f0c8a8", "hair": "#e8c46a", "style": "short", "top": "#2a6ac8", "pants": "#2a2a30"},
	"baby": {"h": 0.55, "skin": "#f0c8a8", "top": "#f8f4ee", "pants": "#f8f4ee", "shoes": "#f0c8a8", "hair": "#e8c46a", "style": "short"},
}
const PIVOTS := ["Rig", "LegR", "LegL", "Body", "ArmR", "ArmL", "HandR", "HandL", "Head", "Mouth"]


## A character by id (see LOOKS). parent gets the root node.
static func person(id: String, parent: Node) -> Puppet:
	var o: Dictionary = LOOKS[id]
	var r := Puppet.new()
	r.id = id
	r.H = o.get("h", 1.8)
	var inst := Assets.glb("characters/" + id)
	if inst:
		var missing := PIVOTS.filter(func(nm): return Assets.find(inst, nm) == null)
		if missing.size():
			Assets.warn_once("rig:" + id, "[assets] characters/%s.glb lacks %s; using the procedural puppet" % [id, str(missing)])
			inst.free()
			inst = null
	if inst:
		r.g = inst
	else:
		r.g = _build(id, o)
		Assets.used_placeholder.append("characters/" + id)
	r.g.name = id
	parent.add_child(r.g)
	r.bind()
	_extras(r)
	return r


## Accessory nodes the code drives (blender/README.md).
static func _extras(r: Puppet) -> void:
	var ctx := "characters/" + r.id
	match r.id:
		"two_pack":
			r.bino = Assets.need(r.g, "Binoculars", ctx)
			r.cup = Assets.need(r.g, "Cup", ctx)
			r.bino.visible = false
			r.cup.visible = false
		"cop_dan", "cop_steve":
			r.donut = Assets.need(r.g, "Donut", ctx)
		"mailman":
			r.letter = Assets.need(r.g, "Letter", ctx)
		"gary":
			r.pipe = Assets.need(r.g, "Pipe", ctx)
			r.ember = Assets.own_materials(Assets.need(r.g, "Ember", ctx))


# ------------------------------------------------------------------ the procedural puppet
static func _c(hex: String, rough := 0.86) -> Material:
	return ClayLib.clay(hex, rough)


static func _rot(n: Node3D, x: float, y: float, z: float) -> Node3D:
	n.rotation_order = EULER_ORDER_XYZ
	n.rotation = Vector3(x, y, z)
	return n


## makePerson(o), with the rig contract's node names.
static func _build(id: String, o: Dictionary) -> Node3D:
	var H: float = o.get("h", 1.8)
	var root := Node3D.new()
	var rig := Prim.group(root, 0, 0, 0, "Rig")
	var m_skin := _c(o.skin)
	var m_top: Material = Prim.stripes("#141414", "#f4f0e6") if o.get("stripes") else _c(o.get("top", o.skin))
	var m_pants := _c(o.get("pants", "#33343a"))
	var m_shoe := _c(o.get("shoes", "#1c1c1e"), 0.5)
	var m_sleeve: Material = m_skin if o.get("shirtless") else m_top
	var hip_y := 0.47 * H
	for s in [-1, 1]:
		var p := Prim.group(rig, s * 0.085 * H, hip_y, 0, "LegR" if s < 0 else "LegL")
		Prim.M(Prim.cyl(0.062 * H, 0.055 * H, 0.44 * H, 10), m_pants, 0, -0.22 * H, 0, p)
		Prim.M(Prim.box(0.1 * H, 0.065 * H, 0.18 * H), m_shoe, 0, -0.44 * H, 0.035 * H, p)
	var body := Prim.group(rig, 0, hip_y, 0, "Body")
	Prim.M(Prim.sph(0.135 * H, 14, 10), m_pants, 0, 0.01 * H, 0, body).scale = Vector3(1.05, 0.55, 0.78)
	Prim.M(Prim.cyl(0.15 * H, 0.13 * H, 0.32 * H, 16), m_top, 0, 0.17 * H, 0, body).scale = Vector3(1, 1, 0.74)
	Prim.M(Prim.sph(0.15 * H, 16, 10), m_top, 0, 0.33 * H, 0, body).scale = Vector3(1, 0.42, 0.74)
	if o.has("belly"):
		Prim.M(Prim.sph(0.12 * H, 14, 10), m_top, 0, 0.12 * H, 0.045 * H, body).scale = Vector3(1.05, 1, o.belly)
	for s in [-1, 1]:
		var p := Prim.group(body, s * 0.185 * H, 0.31 * H, 0, "ArmR" if s < 0 else "ArmL")
		Prim.M(Prim.cyl(0.045 * H, 0.04 * H, 0.29 * H, 10), m_sleeve, 0, -0.145 * H, 0, p)
		var hand := Prim.group(p, 0, -0.3 * H, 0, "HandR" if s < 0 else "HandL")
		Prim.M(Prim.sph(0.045 * H, 10, 8), m_skin, 0, 0, 0, hand)
	var head := Prim.group(body, 0, 0.36 * H, 0, "Head")
	Prim.M(Prim.cyl(0.04 * H, 0.045 * H, 0.07 * H, 8), m_skin, 0, 0.02 * H, 0, head)
	var hs := 0.115 * H
	var hy := 0.05 * H + hs
	Prim.M(Prim.lumpy(Prim.sph(hs, 18, 14), 0.004 * H), m_skin, 0, hy, 0, head)
	var white := _c("#f8f6f0", 0.4)
	var black := _c("#0a0a0c", 0.3)
	for s in [-1, 1]:
		Prim.M(Prim.sph(0.026 * H, 10, 8), white, s * 0.042 * H, hy + 0.02 * H, 0.093 * H, head)
		Prim.M(Prim.sph(0.014 * H, 8, 6), black, s * 0.042 * H, hy + 0.02 * H, 0.116 * H, head)
		Prim.M(Prim.sph(0.02 * H, 8, 6), m_skin, s * 0.118 * H, hy, 0, head).scale = Vector3(0.5, 1, 0.8)
	Prim.M(Prim.sph(0.022 * H, 8, 6), m_skin, 0, hy - 0.005 * H, 0.114 * H, head)
	var mouth := Prim.group(head, 0, hy - 0.05 * H, 0.1 * H, "Mouth")
	Prim.M(Prim.sph(0.032 * H, 10, 6), _c("#3a1414", 0.6), 0, 0, 0, mouth).scale = Vector3(1, 1, 0.45)
	mouth.scale = Vector3(1, 0.3, 1)
	var style: String = o.get("style", "")
	if o.has("hair") and style != "bald":
		var mh := _c(o.hair)
		var cap := Prim.M(Prim.sph(hs * 1.05, 18, 10, 0.0, PI * (0.6 if style == "bob" else 0.48)), mh, 0, hy + 0.004 * H, -0.012 * H, head)
		cap.rotation.x = -0.25
		if style == "bun":
			Prim.M(Prim.lumpy(Prim.sph(hs * 0.42, 12, 9), 0.004), mh, 0, hy + hs * 0.78, -hs * 0.55, head)
		if style == "long":
			Prim.M(Prim.box(hs * 1.9, hs * 1.7, hs * 0.45), mh, 0, hy - hs * 0.55, -hs * 0.72, head)
	if o.get("glasses"):
		for s in [-1, 1]:
			Prim.T(0.03 * H, 0.005 * H, black, s * 0.042 * H, hy + 0.02 * H, 0.118 * H, head, 6, 14)
	if o.get("mustache"):
		Prim.M(Prim.box(0.08 * H, 0.018 * H, 0.02 * H), _c(o.get("hair", "#3a2a1a")), 0, hy - 0.03 * H, 0.116 * H, head)
	match id:
		"two_pack":
			_two_pack(H, body, head, hs, hy)
		"ricky":
			_ricky(H, body, head, hs, hy)
		"cop_dan", "cop_steve":
			_cop(H, body, head, hs, hy)
		"granny":
			_granny(rig)
		"gary":
			_gary(H, head, hs, hy)
		"mailman":
			var strap := Prim.M(Prim.box(0.05, 0.62, 0.03), _c("#5a3a24"), 0, 0.2 * 1.75, 0.12, body)
			strap.rotation.z = 0.7
			Prim.M(Prim.box(0.32, 0.3, 0.12), _c("#5a3a24"), -0.2, 0.05, 0.14, body)
			var lt := Prim.M(Prim.box(0.26, 0.14, 0.01), _c("#f4f0e6"), 0, -0.06 * H, 0.08, body.get_node("ArmR/HandR"))
			lt.name = "Letter"
		"vendor":
			Prim.M(Prim.cyl(0.12, 0.12, 0.12, 12), _c("#f4f0e6"), 0, hy + hs * 0.95, 0, head)
	return root


## make2Pack(): bandana, gold chain, hall-monitor sash, tattoos, binoculars, the lemonade cup.
static func _two_pack(H: float, b: Node3D, head: Node3D, hs: float, hy: float) -> void:
	var skin := _c("#6e4228", 0.6)
	var red := _c("#c4162a", 0.8)
	var gold := _c("#f2c230", 0.15)
	for s in [-1, 1]:
		Prim.M(Prim.sph(0.08 * H, 12, 8), skin, s * 0.07 * H, 0.27 * H, 0.085 * H, b).scale = Vector3(1, 0.7, 0.4)
		for k in 3:
			Prim.M(Prim.sph(0.03 * H, 8, 6), skin, s * 0.032 * H, (0.17 - 0.045 * k) * H, 0.093 * H, b).scale = Vector3(1, 0.7, 0.4)
	var ink := {"fg": "#1a2030"}
	Prim.sign("911", 0.11 * H, 0.04 * H, ink, 0, 0.305 * H, 0.117 * H, b)
	Prim.sign("SNITCH 4 LIFE", 0.2 * H, 0.03 * H, ink, 0, 0.045 * H, 0.102 * H, b)
	Prim.sign("NEIGHBORHOOD\nWATCH", 0.25 * H, 0.1 * H, ink, 0, 0.2 * H, -0.12 * H, b, PI)
	var band := Prim.T(hs * 0.98, hs * 0.17, red, 0, hy + hs * 0.42, 0, head, 8, 24)
	band.rotation.x = PI / 2 + 0.12
	Prim.M(Prim.sph(hs * 0.24, 10, 8), red, 0, hy + hs * 0.45, -hs * 0.98, head)
	for s in [-1, 1]:
		_rot(Prim.M(Prim.cone(hs * 0.13, hs * 0.6, 6), red, s * 0.07 * H * 0.4, hy + hs * 0.12, -hs * 1.08, head), -2.6, 0, s * 0.35)
	Prim.M(Prim.sph(0.01 * H, 6, 6), _c("#1a2030"), -0.042 * H, hy - 0.035 * H, 0.11 * H, head).scale = Vector3(0.8, 1.6, 0.6)
	var ch := Prim.T(0.105 * H, 0.011 * H, gold, 0, 0.335 * H, 0.03 * H, b, 6, 22)
	ch.rotation.x = PI / 2 - 0.45
	Prim.M(Prim.cyl(0.025 * H, 0.025 * H, 0.07 * H, 8), gold, 0, 0.25 * H, 0.12 * H, b).rotation.z = PI / 2
	Prim.M(Prim.box(0.07 * H, 0.5 * H, 0.012 * H), _c("#ff8a1a", 0.8), 0, 0.17 * H, 0.112 * H, b).rotation.z = 0.62
	Prim.M(Prim.box(0.07 * H, 0.5 * H, 0.012 * H), _c("#ff8a1a", 0.8), 0, 0.17 * H, -0.112 * H, b).rotation.z = -0.62
	for k in 3:
		Prim.T(0.135 * H, 0.012 * H, _c("#f4f0e6" if k % 2 else "#c4162a", 0.8), 0, 0.06 * H + 0.02 * H * k, 0, b, 6, 22).rotation.x = PI / 2
	var bn := Prim.group(head, 0, hy + 0.02 * H, 0.17 * H, "Binoculars")
	for s in [-1, 1]:
		Prim.M(Prim.cyl(0.025 * H, 0.03 * H, 0.1 * H, 10), _c("#1a1a1e", 0.4), s * 0.042 * H, 0, 0, bn).rotation.x = PI / 2
	var cup := Prim.M(Prim.cyl(0.05, 0.04, 0.13, 10), _c("#f8e04a", 0.25), 0, -0.03 * H, 0.04, b.get_node("ArmL/HandL"))
	cup.name = "Cup"


static func _ricky(H: float, body: Node3D, head: Node3D, hs: float, hy: float) -> void:
	Prim.M(Prim.box(hs * 2.05, hs * 0.3, hs * 0.4), _c("#0a0a0c", 0.3), 0, hy + 0.02 * H, hs * 0.82, head)
	Prim.M(Prim.sph(hs * 1.06, 16, 10, 0.0, PI * 0.5), _c("#141414", 0.95), 0, hy + 0.01, 0, head)
	var bag := Prim.group(body, 0.12 * H, 0.3 * H, -0.2 * H)
	Prim.M(Prim.lumpy(Prim.sph(0.26, 14, 10), 0.03), _c("#c8b080", 0.95), 0, 0, 0, bag).scale = Vector3(1, 1.1, 0.9)
	Prim.M(Prim.cyl(0.07, 0.07, 0.12, 8), _c("#c8b080", 0.95), 0, 0.3, 0, bag)
	Prim.sign("$", 0.26, 0.26, {"fg": "#2a7a3a"}, 0, 0, 0.24, bag)


static func _cop(H: float, body: Node3D, head: Node3D, hs: float, hy: float) -> void:
	var cop := _c("#1a2a5a", 0.6)
	Prim.M(Prim.cyl(hs * 0.98, hs * 0.98, hs * 0.4, 16), cop, 0, hy + hs * 0.72, 0, head)
	Prim.M(Prim.cyl(hs * 1.12, hs * 1.12, hs * 0.1, 16), cop, 0, hy + hs * 0.95, 0, head)
	Prim.M(Prim.box(hs * 0.9, hs * 0.06, hs * 0.5), _c("#0a0a0c", 0.15), 0, hy + hs * 0.55, hs * 0.85, head).rotation.x = 0.25
	Prim.M(Prim.sph(hs * 0.14, 8, 6), _c("#f2c230", 0.15), 0, hy + hs * 0.8, hs * 0.98, head)
	Prim.M(Prim.sph(0.03 * H, 8, 6), _c("#f2c230", 0.15), 0.07 * H, 0.27 * H, 0.11 * H, body)
	var d := Prim.T(0.08, 0.035, _c("#e84a9a", 0.3), 0, -0.03 * H, 0.03, body.get_node("ArmR/HandR"), 8, 14)
	d.rotation.y = PI / 2
	d.name = "Donut"


static func _granny(rig: Node3D) -> void:
	var wk := Prim.group(rig, 0, 0, 0.48)
	var alu := _c("#c8ccd4", 0.25)
	for sx in [-0.24, 0.24]:
		for sz in [-0.14, 0.14]:
			Prim.M(Prim.cyl(0.025, 0.025, 0.8, 6), alu, sx, 0.4, sz, wk)
		Prim.M(Prim.cyl(0.03, 0.03, 0.36, 6), alu, sx, 0.8, 0, wk).rotation.x = PI / 2
		Prim.M(Prim.sph(0.06, 8, 6), _c("#e8f040"), sx, 0.04, -0.14, wk)


static func _gary(H: float, head: Node3D, hs: float, hy: float) -> void:
	Prim.M(Prim.lumpy(Prim.sph(hs * 0.92, 14, 10, 0.0, PI * 0.55), 0.01), _c("#3a4a2a", 0.95), 0, hy + hs * 0.15, 0, head)
	Prim.M(Prim.lumpy(Prim.sph(hs * 0.6, 12, 8), 0.01), _c("#6a5a3a"), 0, hy - hs * 0.7, hs * 0.35, head).scale = Vector3(1, 1.1, 0.7)
	for s in [-1, 1]:
		Prim.M(Prim.sph(hs * 0.18, 8, 6), _c("#5a3a4a"), s * 0.042 * H, hy - 0.005 * H, 0.1 * H, head).scale = Vector3(1, 0.45, 0.4)
	var hand: Node3D = head.get_parent().get_node("ArmR/HandR")
	var pipe := Prim.group(hand, 0, -0.02 * H, 0.04, "Pipe")
	Prim.M(Prim.cyl(0.018, 0.018, 0.18, 8), Prim.glass_mat("#e8f0ff", 0.6, 0.1), 0, 0, 0, pipe).rotation.x = PI / 2
	var em := Prim.M(Prim.sph(0.03, 8, 6), Prim.glow_mat("#ff8a1a", 3.0), 0, 0, 0.1, pipe)
	em.name = "Ember"
