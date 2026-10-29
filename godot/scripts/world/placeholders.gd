class_name Placeholders
## Stand-ins for missing GLBs, built from primitives in the JS shapes and colors (world.js,
## characters.js). Same origins, facings and contracted node names as the Blender assets
## (blender/README.md), so the game drives either one the same way.

static var _rng := RandomNumberGenerator.new()


static func build(id: String) -> Node3D:
	_rng.seed = hash(id)
	var g := Node3D.new()
	match id:
		"street": _street(g)
		"houses": _houses(g)
		"shops": _shops(g)
		"furniture": _furniture(g)
		"gary_spot": _gary_spot(g)
		"lawn": _lawn(g)
		"payphone": _payphone(g)
		"lemonade_stand": _stand(g)
		"cop_car": _cop_car(g)
		"sedan": _sedan(g)
		"traffic_light": _traffic_light(g)
		"hammock": _hammock(g)
		"county_jail": _jail(g)
		"ice_cream_cart": _cart(g)
		"cash_bill": _bill(g)
		"squirrel": _squirrel(g)
		_:
			push_warning("[placeholders] no placeholder for " + id)
	return g


static func _c(hex: String, rough := 0.86) -> Material:
	return ClayLib.clay(hex, rough)


static func _r(a: float, b: float) -> float:
	return _rng.randf_range(a, b)


static func _street(g: Node3D) -> void:
	var asphalt := _c("#3a3a40", 0.95)
	var side := _c("#a8a49a")
	var curb := _c("#c8c4b8")
	Prim.M(Prim.box(130, 0.1, 14), asphalt, 6, -0.05, 7, g, false)
	Prim.M(Prim.box(130, 0.16, 3.2), side, 6, 0.08, -1.6, g, false)
	Prim.M(Prim.box(130, 0.18, 0.25), curb, 6, 0.09, 0, g, false)
	Prim.M(Prim.box(130, 0.12, 4), _c("#6a8a3a", 0.95), 6, 0.06, -5, g, false)
	Prim.M(Prim.box(130, 0.16, 6), side, 6, 0.08, 16, g, false)
	for k in 26:
		Prim.M(Prim.box(2, 0.012, 0.15), _c("#f2c21a"), -50 + k * 5, 0.006, 7, g, false)
	for k in 20:
		var c := Prim.M(Prim.box(_r(0.4, 1.2), 0.01, 0.03), _c("#5a5a54"), _r(-30, 44), 0.166, -_r(0.4, 2.8), g, false)
		c.rotation.y = _r(-1, 1)
	# the crosswalk Grandma is NOT using
	for k in 5:
		Prim.M(Prim.box(0.55, 0.012, 12.6), _c("#e8e4d6"), 1.3 + k * 1.0, 0.007, 6.7, g, false)
	# chain-link fence, end walls, the fire lane, the power line, the stage 2 stop line
	Prim.M(Prim.box(100, 2, 0.05), Prim.glass_mat("#9aa0a8", 0.45), 6, 1, 18.9, g, false)
	for x in [World.BOUNDS.x0 - 1.2, World.BOUNDS.x1 + 1.6]:
		Prim.M(Prim.box(1, 5, 10.4), _c("#4a4a52"), x, 2.5, -4.9, g, false)
		Prim.M(Prim.box(1, 5, 7), _c("#4a4a52"), x, 2.5, 16.5, g, false)
	Prim.M(Prim.box(5, 0.19, 0.27), _c("#c4162a", 0.5), 9.6, 0.1, 0, g, false)
	Prim.sign("FIRE LANE", 1.4, 0.12, {"fg": "#f4f0e6"}, 9.6, 0.03, 0.6, g).rotation.x = -PI / 2
	Prim.M(Prim.cyl(0.03, 0.03, 80, 6), _c("#141414"), 6, 6.4, 0.3, g).rotation.z = PI / 2
	for s in [-1, 1]:
		Prim.M(Prim.box(0.15, 0.12, 0.3), _c("#f4f4f4"), 13 + s * 0.15, 6.0, 0.3, g)
	Prim.M(Prim.box(0.3, 0.012, 5.6), _c("#f4f0e6"), -0.9, 0.008, World.LANE2, g, false)


static func _houses(g: Node3D) -> void:
	var curb := _c("#c8c4b8")
	var cols := ["#8a4a3a", "#6a5a7a", "#4a6a7a", "#8a7a4a", "#7a3a3a", "#5a6a4a", "#7a6a5a", "#4a4a5a"]
	var xs := [-30, -24, -18, -12, -6, 6, 12, 17]
	for k in xs.size():
		var x: float = xs[k]
		var hg := Prim.group(g, 0, 0, 0, ("House_m%d" if x < 0 else "House_p%d") % absi(int(x)))
		var w := 5.0 if x == 17 else 5.6
		var graf := x == -6 or x == 6 or x == 12
		var h := 7.6 if graf else 5.6 + float((k * 37) % 25) / 10.0
		Prim.M(Prim.box(w, h, 7), _c(cols[k % cols.size()]), x, h / 2, -10.5, hg)
		Prim.M(Prim.box(w + 0.2, 0.3, 7.2), _c("#2a2624"), x, h + 0.15, -10.5, hg)
		for wx in [-1.5, 1.4]:
			for wz in ([2.0] if graf else [2.0, 4.3]):
				var boarded := int(k * 7 + wx * 3 + wz) % 3 == 0
				Prim.M(Prim.box(1.1, 1.2, 0.06), _c("#8a6a3a") if boarded else _c("#1a2230", 0.15), x + wx, wz, -6.98, hg, false)
				if boarded:
					for b in 2:
						var bd := Prim.M(Prim.box(1.3, 0.18, 0.05), _c("#9a7a4a"), x + wx, wz + 0.25 - 0.5 * b, -6.93, hg, false)
						bd.rotation.z = 0.3 if b else -0.3
		Prim.M(Prim.box(1, 2.1, 0.08), _c("#3a2414"), x + 0.1, 1.05, -6.97, hg, false)
		Prim.M(Prim.box(1.6, 0.4, 0.9), curb, x + 0.1, 0.2, -6.55, hg)
	Prim.sign("2-PACK IS A\nSNITCH", 4.6, 1.6, {"fg": "#e84a9a"}, -6, 4.8, -6.94, g)
	Prim.sign("SNITCHES GET\nSTITCHES", 4.4, 1.5, {"fg": "#2ad0e8"}, 6, 4.8, -6.94, g)
	Prim.sign("STILL THERE", 4.4, 0.8, {"fg": "#f2c21a"}, 12, 4.8, -6.94, g)
	# 2-Pack's house
	var tp := Prim.group(g, 0, 0, 0, "House_2Pack")
	Prim.M(Prim.box(5.6, 7, 7), _c("#b8a070"), 0, 3.5, -10.5, tp)
	Prim.M(Prim.box(5.8, 0.3, 7.2), _c("#2a2624"), 0, 7.15, -10.5, tp)
	Prim.M(Prim.box(1.4, 1.2, 0.06), _c("#1a2230", 0.15), 1.8, 1.75, -6.98, tp, false)
	for k in 9:
		Prim.M(Prim.box(1.4, 0.04, 0.1), _c("#f4f0e6"), 1.8, 2.25 - k * 0.11, -6.9, tp, false)
	Prim.M(Prim.box(1, 2.1, 0.08), _c("#c4162a", 0.5), -1, 1.05, -6.97, tp, false)
	Prim.M(Prim.box(1.6, 0.4, 0.9), curb, -1, 0.2, -6.55, tp)
	Prim.M(Prim.box(1.9, 0.3, 0.04), _c("#1a3a8a"), -1, 2.6, -6.93, tp, false)
	Prim.sign("NEIGHBORHOOD WATCH", 1.8, 0.18, {"fg": "#f2c21a"}, -1, 2.6, -6.9, tp)


static func _shops(g: Node3D) -> void:
	var curb := _c("#c8c4b8")
	for s in [[22.5, "CORNER STORE", "#4a6a4a", 6.0, "CornerStore"], [28.0, "BANK", "#c8c0a8", 5.0, "Bank"], [43.5, "LIQUOR", "#6a4a7a", 6.0, "Liquor"]]:
		var x: float = s[0]
		var w: float = s[3]
		var sg := Prim.group(g, 0, 0, 0, s[4])
		Prim.M(Prim.box(w, 7, 7), _c(s[2]), x, 3.5, -10.5, sg)
		Prim.M(Prim.box(w * 0.8, 0.7, 0.1), _c("#f4f0e6"), x, 4.2, -6.95, sg, false)
		Prim.sign(s[1], w * 0.75, 0.55, {"fg": "#c4162a" if s[1] == "LIQUOR" else "#141414"}, x, 4.2, -6.89, sg)
		Prim.M(Prim.box(1.4, 2.4, 0.08), _c("#1a2230", 0.15), x, 1.2, -6.96, sg, false)
	var p := Prim.group(g, 0, 0, 0, "Precinct9")
	Prim.M(Prim.box(9, 8, 8), _c("#5a6a8a"), 36, 4, -11, p)
	Prim.M(Prim.box(6.5, 0.9, 0.12), _c("#1a2a5a"), 36, 5.6, -6.94, p, false)
	Prim.sign("POLICE  ·  PRECINCT 9", 6.1, 0.6, {"fg": "#f4f0e6"}, 36, 5.6, -6.87, p)
	Prim.M(Prim.box(2.2, 2.8, 0.08), _c("#1a2230", 0.15), 36, 1.4, -6.96, p, false)
	for s in [-1, 1]:
		Prim.M(Prim.sph(0.3), ClayLib.glow("#3a8aff", 2.0), 36 + s * 1.8, 3, -6.8, p)
	for k in 4:
		Prim.M(Prim.box(5, 0.18 * (k + 1), 0.62), curb, 36, 0.09 * (k + 1), -(3.6 + 0.6 * k), p)
	Prim.M(Prim.box(0.6, 0.12, 0.6), _c("#f4e2d4"), 37.6, 0.8, -5.0, p)
	for k in 3:
		Prim.T(0.12, 0.05, _c("#e84a9a", 0.3), 37.45 + 0.15 * k, 0.88, -5.0, p, 8, 14).rotation.x = PI / 2


static func _furniture(g: Node3D) -> void:
	for x in [-24, -12, 4, 14, 30, 40]:
		Prim.M(Prim.cyl(0.07, 0.07, 5, 8), _c("#2a2a2e"), x, 2.5, -0.2, g)
		Prim.M(Prim.box(0.9, 0.2, 0.35), _c("#2a2a2e"), x, 5, 0.2, g)
	for x in [-8.5, 9.6, 25]:
		Prim.M(Prim.cyl(0.15, 0.17, 0.7, 10), _c("#c4162a", 0.3), x, 0.5, -0.32, g)
		Prim.M(Prim.sph(0.17), _c("#c4162a", 0.3), x, 0.86, -0.32, g)
	for x in [-15.8, 4.8, 26.4]:
		Prim.M(Prim.cyl(0.3, 0.27, 0.9, 12), _c("#5a6a5a", 0.4), x, 0.57, -3.5, g)
	Prim.M(Prim.cyl(0.03, 0.03, 0.7, 6), _c("#7a4a24"), 9.5, 0.4, -3.5, g)
	Prim.sign("THE JOHNSONS", 0.9, 0.16, {"fg": "#2a1a10", "bg": "#f4f0e6"}, 9.5, 0.8, -3.47, g)
	for x in [-27, -21.2, -14.2]:
		Prim.M(Prim.cyl(0.04, 0.04, 1, 6), _c("#7a4a24"), x, 0.6, -3.0, g)
		Prim.M(Prim.box(0.3, 0.3, 0.5), _c("#2a3a6a", 0.4), x, 1.15, -3.0, g)
	# the blue mail drop
	var mb := Prim.group(g, 5.9, 0.16, -3.0)
	Prim.M(Prim.box(0.62, 0.85, 0.56), _c("#1f4fa8", 0.4), 0, 0.72, 0, mb)
	Prim.M(Prim.cyl(0.28, 0.28, 0.62, 14), _c("#1f4fa8", 0.4), 0, 1.14, 0, mb).rotation.z = PI / 2
	for sx in [-0.26, 0.26]:
		for sz in [-0.22, 0.22]:
			Prim.M(Prim.box(0.06, 0.3, 0.06), _c("#1a1a1e"), sx, 0.15, sz, mb)
	Prim.M(Prim.box(0.4, 0.05, 0.02), _c("#141414"), 0, 1.0, 0.29, mb)
	Prim.sign("MAIL", 0.42, 0.14, {"fg": "#f4f0e6"}, 0, 0.75, 0.285, mb)
	# pines past the fence
	for k in 12:
		var x := -34.0 + k * 7 + _r(-1.5, 1.5)
		var z := 21.0 + _r(0, 3)
		var s := _r(1, 1.6)
		Prim.M(Prim.cyl(0.12 * s, 0.15 * s, 0.8 * s, 8), _c("#5a3a24"), x, 0.4 * s, z, g)
		for j in 3:
			Prim.M(Prim.cone((1 - j * 0.25) * s, 1.3 * s, 9), _c("#2f5a3a"), x, (1.1 + j * 0.75) * s, z, g)


static func _gary_spot(g: Node3D) -> void:
	var alu := _c("#c8ccd4", 0.25)
	Prim.M(Prim.box(0.9, 0.02, 0.6), _c("#8a6a3a", 0.95), -1.1, 0.012, 1.4, g, false)
	Prim.sign("WELCOME", 0.7, 0.18, {"fg": "#2a1a10"}, -1.1, 0.026, 1.4, g).rotation.x = -PI / 2
	var cart := Prim.group(g, -5.9, 0, 1.15)
	cart.rotation.y = 0.3
	for sx in [-0.4, 0.4]:
		Prim.M(Prim.box(0.03, 0.55, 0.9), alu, sx, 0.75, 0, cart)
		for sy in [-0.4, 0.4]:
			Prim.M(Prim.sph(0.07, 8, 6), _c("#141414"), sx, 0.07, sy, cart)
			Prim.M(Prim.cyl(0.02, 0.02, 0.45, 6), alu, sx, 0.3, sy, cart)
	for sy in [-0.45, 0.45]:
		Prim.M(Prim.box(0.83, 0.55, 0.03), alu, 0, 0.75, sy, cart)
	var bags := ["#6a5a3a", "#3a5a6a", "#8a3a3a", "#c8c0a8"]
	for k in 4:
		Prim.M(Prim.lumpy(Prim.sph(0.3, 12, 9), 0.05), _c(bags[k], 0.95), (k % 2 - 0.5) * 0.35, 1.05, (k / 2 - 0.5) * 0.4, cart).scale = Vector3(1.15, 1, 1)
	Prim.M(Prim.cyl(0.04, 0.04, 0.9, 6), _c("#7a4a24"), -4.55, 0.45, 0.6, g)
	Prim.M(Prim.box(0.8, 0.4, 0.04), _c("#f4f0e6"), -4.55, 0.95, 0.58, g)
	Prim.sign("WELCOME\nHOME", 0.7, 0.32, {"fg": "#c4162a"}, -4.55, 0.95, 0.61, g)
	Prim.M(Prim.cyl(0.06, 0.06, 1, 6), _c("#7a4a24"), -1.25, 0.5, 0.35, g)
	Prim.M(Prim.box(0.3, 0.3, 0.5), _c("#2a3a6a", 0.4), -1.25, 1.1, 0.35, g)
	Prim.sign("GARY", 0.26, 0.08, {"fg": "#f4f0e6"}, -1.25, 1.1, 0.61, g)
	Prim.M(Prim.sph(0.38, 12, 8), _c("#141414"), -7.2, 0.62, 0.4, g).scale = Vector3(1, 0.6, 1)
	Prim.M(Prim.cyl(0.04, 0.04, 0.5, 6), alu, -7.2, 0.25, 0.4, g)
	# Gary's blanket and clutter (makeGary)
	Prim.M(Prim.lumpy(Prim.sph(1, 20, 12), 0.06), _c("#6a4a6a", 0.98), -2.55, 0.28, 0.73, g).scale = Vector3(0.82, 0.24, 0.44)
	for k in 4:
		Prim.M(Prim.sph(0.17, 8, 6), _c("#4a3a2a", 0.95), -3.1 + 0.33 * k, 0.5, 0.73 + 0.1 * sin(k * 3), g, false).scale = Vector3(1, 0.25, 1)


static func _lawn(g: Node3D) -> void:
	Prim.M(Prim.box(5.4, 0.03, 3.4), _c("#8a6a3a", 0.95), 0, 0.015, 0, g, false).name = "Brown"
	var gr := Prim.M(Prim.box(5.4, 0.03, 3.4), _c("#6a8a3a", 0.95), 0, 0.015, 0, g, false)
	gr.name = "Green"
	gr.visible = false


static func _payphone(g: Node3D) -> void:
	Prim.M(Prim.cyl(0.06, 0.06, 1.3, 8), _c("#6a7078", 0.4), 0, 0.65, -0.05, g)
	Prim.M(Prim.box(0.55, 0.8, 0.3), _c("#2c5bd6", 0.35), 0, 1.45, 0, g)
	Prim.M(Prim.box(0.38, 0.24, 0.04), _c("#c8ccd4", 0.3), 0, 1.6, 0.16, g)
	Prim.M(Prim.box(0.1, 0.42, 0.1), _c("#141414"), -0.2, 1.42, 0.18, g)
	for k in 6:
		Prim.M(Prim.box(0.08, 0.06, 0.03), _c("#f4f0e6"), -0.03 + (k % 3) * 0.08, 1.36 - (k / 3) * 0.08, 0.16, g, false)
	Prim.sign("PHONE", 0.5, 0.13, {"fg": "#f4f0e6", "bg": "#14203f"}, 0, 1.97, 0.16, g)
	Prim.sign("OUT OF\nORDER", 0.42, 0.24, {"fg": "#c4162a", "bg": "#f2d24a", "font": "mono"}, 0.03, 1.18, 0.155, g).rotation.z = 0.12


static func _stand(g: Node3D) -> void:
	var wd := _c("#c8a060", 0.7)
	Prim.M(Prim.box(1.4, 0.06, 0.6), wd, 0, 0.8, 0, g)
	Prim.M(Prim.box(1.4, 0.75, 0.05), wd, 0, 0.42, 0.3, g)
	for s in [-1, 1]:
		Prim.M(Prim.box(0.06, 1.6, 0.06), wd, s * 0.67, 0.8, -0.25, g)
	Prim.M(Prim.box(1.5, 0.3, 0.05), wd, 0, 1.6, -0.25, g)
	Prim.M(Prim.cyl(0.12, 0.12, 0.28, 10), _c("#f8e04a", 0.1), -0.35, 0.97, 0, g)
	for k in 3:
		Prim.M(Prim.cyl(0.05, 0.04, 0.12, 8), _c("#f4f0e6", 0.3), 0.1 + k * 0.15, 0.89, 0.05, g)
	Prim.sign("LEMONADE\n25 CENTS", 1.25, 0.55, {"fg": "#c4162a"}, 0, 0.48, 0.33, g)
	Prim.sign("OPEN", 1.3, 0.26, {"fg": "#14203f", "bg": "#f2d24a"}, 0, 1.6, -0.22, g).name = "SignOpen"
	Prim.sign("CLOSED", 1.3, 0.26, {"fg": "#f4f0e6", "bg": "#c4162a"}, 0, 1.6, -0.215, g).name = "SignClosed"


static func _wheel(g: Node3D, nm: String, x: float, z: float, r: float, w: float) -> void:
	var pv := Prim.group(g, x, r, z, nm)
	Prim.M(Prim.cyl(r, r, w, 14), _c("#121214", 0.5), 0, 0, 0, pv).rotation.x = PI / 2
	Prim.M(Prim.cyl(r * 0.45, r * 0.45, w + 0.02, 10), _c("#8a8a90", 0.4), 0, 0, 0, pv).rotation.x = PI / 2


## makeCar(): faces +x.
static func _cop_car(g: Node3D) -> void:
	var bk := _c("#141418", 0.35)
	var wh := _c("#f4f2ee", 0.35)
	Prim.M(Prim.box(4.4, 0.9, 1.9), bk, 0, 0.75, 0, g)
	Prim.M(Prim.box(2.2, 0.5, 1.94), wh, 0.1, 0.8, 0, g)
	Prim.M(Prim.box(2.4, 0.75, 1.7), wh, -0.2, 1.5, 0, g)
	for x in [-0.75, 0.45]:
		Prim.M(Prim.box(1, 0.5, 1.74), _c("#1a2230", 0.1), x, 1.55, 0, g, false)
	Prim.M(Prim.box(0.08, 0.4, 1.5), _c("#1a2230", 0.1), 0.9, 1.5, 0, g, false)
	for s in [-1, 1]:
		Prim.sign("POLICE", 1.6, 0.3, {"fg": "#141414"}, 0.1, 0.85, s * 0.98, g, 0.0 if s > 0 else PI)
	_wheel(g, "WheelFL", 1.4, -0.9, 0.36, 0.3)
	_wheel(g, "WheelFR", 1.4, 0.9, 0.36, 0.3)
	_wheel(g, "WheelRL", -1.4, -0.9, 0.36, 0.3)
	_wheel(g, "WheelRR", -1.4, 0.9, 0.36, 0.3)
	var hl := Prim.group(g, 0, 0, 0, "Headlights")
	for z in [-0.6, 0.6]:
		Prim.M(Prim.box(0.05, 0.18, 0.3), ClayLib.glow("#fff6c8", 1.0), 2.2, 0.85, z, hl, false)
	Prim.M(Prim.box(0.4, 0.18, 0.35), Prim.glow_mat("#ff1a1a", 1.0), -0.2, 1.97, -0.25, g).name = "LightRed"
	Prim.M(Prim.box(0.4, 0.18, 0.35), Prim.glow_mat("#1a4aff", 1.0), -0.2, 1.97, 0.25, g).name = "LightBlue"


## makeSedan(): Mama's pink car, faces +x. Plate = empty at the rear plate, facing -x.
static func _sedan(g: Node3D) -> void:
	var m := _c("#e84a9a", 0.3)
	Prim.M(Prim.box(4.2, 0.85, 1.85), m, 0, 0.72, 0, g)
	Prim.M(Prim.box(2.3, 0.7, 1.7), m, -0.2, 1.45, 0, g)
	for x in [-0.75, 0.4]:
		Prim.M(Prim.box(0.95, 0.48, 1.74), _c("#1a2230", 0.1), x, 1.5, 0, g, false)
	Prim.M(Prim.box(0.08, 0.4, 1.5), _c("#1a2230", 0.1), 0.9, 1.45, 0, g, false)
	_wheel(g, "WheelFL", 1.35, -0.88, 0.36, 0.3)
	_wheel(g, "WheelFR", 1.35, 0.88, 0.36, 0.3)
	_wheel(g, "WheelRL", -1.35, -0.88, 0.36, 0.3)
	_wheel(g, "WheelRR", -1.35, 0.88, 0.36, 0.3)
	for z in [-0.6, 0.6]:
		Prim.M(Prim.box(0.05, 0.16, 0.3), ClayLib.glow("#fff6c8", 1.0), 2.11, 0.8, z, g, false)
		Prim.M(Prim.box(0.05, 0.14, 0.3), ClayLib.glow("#ff2a2a", 1.2), -2.11, 0.8, z, g, false)
	var plate := Prim.group(g, -2.12, 0.62, 0, "Plate")
	plate.rotation.y = -PI / 2
	var q := QuadMesh.new()
	q.size = Vector2(0.62, 0.24)
	Prim.M(q, _c("#f4f4ee", 0.6), 0, 0, -0.004, plate, false)
	Prim.M(Prim.sph(0.12, 10, 8), _c("#e84a9a", 0.6), 0.3, 1.95, -0.3, g)


static func _traffic_light(g: Node3D) -> void:
	Prim.M(Prim.cyl(0.09, 0.11, 4.6, 8), _c("#2a2a2e"), 0, 2.3, 0, g)
	Prim.M(Prim.cyl(0.06, 0.06, 3.3, 6), _c("#2a2a2e"), 0, 4.5, -1.6, g).rotation.x = PI / 2
	Prim.M(Prim.box(0.4, 1.15, 0.42), _c("#1c1c20"), 0, 3.95, -3.1, g)
	for l in [["LampRed", "#ff2a2a", 4.3], ["LampYellow", "#ffc21a", 3.95], ["LampGreen", "#2aff6a", 3.6]]:
		Prim.M(Prim.sph(0.13, 10, 8), Prim.glow_mat(l[1], 0.08), -0.22, l[2], -3.1, g).name = l[0]


static func _hammock(g: Node3D) -> void:
	for sx in [-1, 1]:
		Prim.M(Prim.cyl(0.1, 0.12, 1.7, 8), _c("#7a4a24"), sx * 1.4, 0.95, 0, g)
	Prim.M(Prim.lumpy(Prim.sph(1, 18, 10), 0.03), _c("#d8c8a0", 0.95), 0, 0.82, 0, g).scale = Vector3(1.35, 0.22, 0.45)


static func _jail(g: Node3D) -> void:
	var iron := _c("#3a3a3e", 0.35)
	Prim.M(Prim.box(1.0, 0.5, 0.8), _c("#8a8a90"), 0, 0.25, 0, g)
	Prim.M(Prim.box(1.0, 0.06, 0.8), iron, 0, 1.2, 0, g)
	for k in 8:
		Prim.M(Prim.cyl(0.025, 0.025, 0.7, 6), iron, -0.44 + k * 0.126, 0.85, 0.4, g)
		Prim.M(Prim.cyl(0.025, 0.025, 0.7, 6), iron, -0.44 + k * 0.126, 0.85, -0.4, g)
	for sx in [-0.5, 0.5]:
		for k in 6:
			Prim.M(Prim.cyl(0.025, 0.025, 0.7, 6), iron, sx, 0.85, -0.34 + k * 0.136, g)
	Prim.sign("COUNTY JAIL", 0.8, 0.16, {"fg": "#141414", "bg": "#f4f0e6"}, 0, 1.38, 0.4, g)


static func _cart(g: Node3D) -> void:
	Prim.M(Prim.box(1.1, 0.85, 0.9), _c("#f4f2ee", 0.35), 0, 0.62, 0, g)
	Prim.M(Prim.cyl(0.04, 0.04, 1.3, 6), _c("#c8ccd4", 0.3), 0, 1.55, 0, g)
	Prim.M(Prim.cone(1.1, 0.45, 16), Prim.stripes("#e84a9a", "#f4f0e6"), 0, 2.25, 0, g)
	for sx in [-0.4, 0.4]:
		for sz in [-0.35, 0.35]:
			Prim.M(Prim.cyl(0.12, 0.12, 0.06, 10), _c("#141414"), sx, 0.12, sz, g).rotation.z = PI / 2
	Prim.sign("ICE CREAM", 0.85, 0.2, {"fg": "#e84a9a"}, -0.56, 0.75, 0, g, -PI / 2)


static func _bill(g: Node3D) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#5ab05a")
	m.emission_enabled = true
	m.emission = Color("#2a7a2a")
	m.emission_energy_multiplier = 0.5
	m.roughness = 0.6
	Prim.M(Prim.box(0.24, 0.012, 0.11), m, 0, 0, 0, g, false)


static func _squirrel(g: Node3D) -> void:
	var fur := _c("#8a5a34", 0.85)
	Prim.M(Prim.lumpy(Prim.sph(0.2, 12, 9), 0.01), fur, 0, 0.2, 0, g).scale = Vector3(0.8, 0.85, 1.25)
	Prim.M(Prim.sph(0.15, 12, 9), fur, 0, 0.36, 0.2, g)
	var tail := Prim.group(g, 0, 0.26, -0.16, "Tail")
	var tm := Prim.M(Prim.lumpy(Prim.sph(0.2, 12, 9), 0.03), fur, 0, 0.16, -0.12, tail)
	tm.scale = Vector3(0.7, 1.5, 0.7)
	tm.rotation.x = -0.4
	for sx in [-1, 1]:
		Prim.M(Prim.sph(0.03, 8, 6), _c("#0a0a0c", 0.3), sx * 0.07, 0.4, 0.33, g)
		Prim.M(Prim.cone(0.04, 0.09, 6), fur, sx * 0.07, 0.52, 0.17, g)
	Prim.M(Prim.box(0.16, 0.05, 0.12), _c("#e8c890"), 0, 0.3, 0.36, g).name = "Sandwich"
