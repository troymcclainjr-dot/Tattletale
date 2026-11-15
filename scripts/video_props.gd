extends RefCounted
## The music video's props, built from boxes and cylinders (kit.gd) like the
## rest of the sets: the camcorder on its tripod in the studio (E on it starts
## a video), the camcorder Large Fry carries on the shoot, the smoke machine,
## the police car's light bar, Miss Bea's slipper, a thrown bill and a puff of
## smoke. Each builder adds its prop to `parent` and returns it.

const Street := preload("res://scripts/props_street.gd")

const BODY := Color(0.12, 0.12, 0.14)
const GREY := Color(0.34, 0.35, 0.38)
const STEEL := Color(0.62, 0.64, 0.67)
const GLASS := Color(0.22, 0.34, 0.46)
const RED := Color(0.92, 0.12, 0.1)
const BILL := "res://assets/video/bill.png"


## A camcorder, its lens pointing along +z: a body, the lens barrel and its
## glass, a viewfinder on the left, a carrying handle, the red tally light.
static func camcorder(parent: Node3D, at: Vector3, yaw := 0.0) -> Node3D:
	var g := Kit.group(parent, at, Vector3(0, yaw, 0), "Camcorder")
	Kit.bevel(g, Vector3(0.11, 0.13, 0.3), Vector3.ZERO, BODY, 0.02)
	Kit.cyl(g, 0.046, 0.1, Vector3(0, 0.004, 0.19), BODY, Vector3(90, 0, 0), 10)
	Kit.cyl(g, 0.036, 0.008, Vector3(0, 0.004, 0.2445), GLASS, Vector3(90, 0, 0), 10)
	Kit.bevel(g, Vector3(0.046, 0.052, 0.13), Vector3(-0.078, 0.034, -0.07), GREY, 0.01)
	Kit.cyl(g, 0.022, 0.05, Vector3(-0.078, 0.038, -0.15), BODY, Vector3(90, 0, 0), 8)
	Kit.bevel(g, Vector3(0.028, 0.03, 0.2), Vector3(0.0, 0.082, 0.015), GREY, 0.008)
	Kit.ball(g, 0.012, Vector3(0.032, 0.05, 0.152), Kit.flat(RED, 2.0), 6)
	return g


## The studio's camcorder on a tripod, its feet `spread` from the middle.
## Returns the group; `footprint` is the floor it takes (x, z).
static func tripod(parent: Node3D, at: Vector3, yaw: float, spread := 0.32) -> Node3D:
	var g := Kit.group(parent, at, Vector3(0, yaw, 0), "Tripod")
	var head := Vector3(0, 1.17, 0)
	for k in 3:
		var a := TAU * k / 3.0 + 0.4
		var foot := Vector3(sin(a) * spread, 0.0, cos(a) * spread)
		Kit.tube(g, head + Vector3(sin(a) * 0.03, 0, cos(a) * 0.03), foot + Vector3(0, 0.02, 0), 0.012, BODY)
		Kit.ball(g, 0.02, foot + Vector3(0, 0.018, 0), Color(0.06, 0.06, 0.07), 6)
	Kit.tube(g, Vector3(0, 0.7, 0), head, 0.014, STEEL)
	Kit.cyl(g, 0.05, 0.05, head + Vector3(0, 0.02, 0), BODY, Vector3.ZERO, 10)
	Kit.tube(g, head + Vector3(-0.02, 0.05, -0.04), Vector3(-0.09, 1.08, -0.4), 0.01, BODY)      # the pan handle
	camcorder(g, head + Vector3(0, 0.115, 0))
	return g


static func footprint(at: Vector3, spread := 0.32) -> Rect2:
	return Rect2(at.x - spread - 0.03, at.z - spread - 0.03, (spread + 0.03) * 2.0, (spread + 0.03) * 2.0)


## The smoke machine: a dark box on the ground with its nozzle to +z.
static func smoke_machine(parent: Node3D, at: Vector3, yaw: float) -> Node3D:
	var g := Kit.group(parent, at, Vector3(0, yaw, 0), "SmokeMachine")
	Kit.bevel_block(g, Vector3(0.36, 0.2, 0.26), Vector3.ZERO, Color(0.16, 0.16, 0.18), 0.02)
	Kit.cyl(g, 0.035, 0.12, Vector3(0, 0.11, 0.17), STEEL, Vector3(90, 0, 0), 8)
	Kit.bevel(g, Vector3(0.24, 0.03, 0.04), Vector3(0, 0.215, -0.06), GREY, 0.008)      # the handle
	Kit.ball(g, 0.012, Vector3(0.13, 0.15, 0.132), Kit.flat(RED, 2.0), 6)
	return g


## The police car: a white sedan (props_street.gd's car_model) with a light bar
## on its roof and POLICE on its doors. `bar` gets the two lamp materials, red
## then blue, so they can be flashed.
static func police_car(parent: Node3D, at: Vector3, yaw: float, bar: Array) -> Node3D:
	var car := Street.car_model(parent, at, yaw, "box_sedan", Color(0.92, 0.92, 0.9))
	for colour: Color in [Color(0.95, 0.12, 0.1), Color(0.15, 0.3, 0.98)]:
		var lamp := StandardMaterial3D.new()
		lamp.albedo_color = colour.darkened(0.5)
		lamp.emission_enabled = true
		lamp.emission = colour
		lamp.emission_energy_multiplier = 0.0
		bar.append(lamp)
	Kit.bevel(car, Vector3(1.2, 0.07, 0.26), Vector3(0, 1.505, -0.28), Color(0.1, 0.1, 0.11), 0.02)
	for i in 2:
		Kit.bevel(car, Vector3(0.54, 0.09, 0.22), Vector3(-0.3 + i * 0.6, 1.58, -0.28), bar[i], 0.02)
	for s: float in [-1.0, 1.0]:
		var word := Kit.label(car, "POLICE", Vector3(s * 0.955, 0.62, 0.3), 0.17, Color(0.08, 0.12, 0.3), Vector3(0, 90.0 * s, 0))
		word.double_sided = false
		Kit.box(car, Vector3(0.012, 0.12, 2.4), Vector3(s * 0.943, 0.47, 0.05), Color(0.1, 0.14, 0.36))
	return car


## Miss Bea's slipper: a pink sole with a fluffy strap.
static func slipper(parent: Node3D) -> Node3D:
	var g := Kit.group(parent, Vector3.ZERO, Vector3.ZERO, "Slipper")
	Kit.bevel(g, Vector3(0.11, 0.035, 0.27), Vector3.ZERO, Color(0.95, 0.55, 0.7), 0.012)
	Kit.bevel(g, Vector3(0.12, 0.05, 0.09), Vector3(0, 0.04, 0.05), Color(1.0, 0.82, 0.88), 0.02)
	return g


## A bill, flat, both sides the same.
static func bill(parent: Node3D, look: Material) -> MeshInstance3D:
	var card := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.2, 0.092)
	card.mesh = quad
	card.material_override = look
	parent.add_child(card)
	return card


static func bill_look() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(BILL) if ResourceLoader.exists(BILL) else null
	m.albedo_color = Color.WHITE if m.albedo_texture else Color(0.5, 0.75, 0.45)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## A puff of smoke: a soft round card that always faces the camera. Each has
## its own material so it can fade on its own.
static func puff(parent: Node3D, soft: Texture2D) -> MeshInstance3D:
	var card := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	card.mesh = quad
	var m := StandardMaterial3D.new()
	m.albedo_texture = soft
	m.albedo_color = Color(0.86, 0.86, 0.9, 0.0)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	card.material_override = m
	card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(card)
	return card


## The soft round picture the puffs use.
static func soft_texture() -> Texture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.95))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	grad.add_point(0.55, Color(1, 1, 1, 0.6))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	return tex
