extends SceneTree
## In-engine preview renderer. Loads a model or scene into a lit test stage and saves a
## 2x2 contact sheet (or one shot) to a PNG. Run through tools/godot_preview.py, which
## imports first and holds the shared Godot lock. Direct use:
##   Godot_console.exe --path godot --resolution 960x720 --script res://tools/shot.gd -- \
##     --scene res://assets/models/x.glb --out C:/abs/path.png [--eye x,y,z --look x,y,z --fov 40] [--no-ground]
## Coordinates are game coordinates (same as the JS and Godot).

var args := {}
var frames := 0
var views: Array = []
var view_i := 0
var shots: Array[Image] = []
var cam: Camera3D
var target_center := Vector3.ZERO
var target_radius := 1.0
var inst: Node3D

const AUTO_DIRS := [Vector3(0.62, 0.42, 1.0), Vector3(-0.75, 0.5, -1.0), Vector3(0.0, 0.12, 1.0), Vector3(1.0, 0.18, 0.02)]


var started := false


func _initialize() -> void:
	pass


func _setup() -> void:
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		var k: String = a[i].trim_prefix("--")
		if i + 1 < a.size() and not a[i + 1].begins_with("--"):
			args[k] = a[i + 1]
			i += 2
		else:
			args[k] = true
			i += 1
	_build_stage()
	var res: Resource = load(args.get("scene", ""))
	if res == null:
		push_error("shot.gd: can't load %s" % args.get("scene", ""))
		quit(1)
		return
	inst = res.instantiate()
	root.add_child(inst)
	ClayLib.apply(inst)
	_fit()
	if args.has("eye"):
		views = [[_v3(args["eye"]), _v3(args.get("look", "0,0,0")), float(args.get("fov", "40"))]]
	else:
		for d in AUTO_DIRS:
			var fov := 34.0
			var dist := target_radius / sin(deg_to_rad(fov) * 0.5) * 1.12
			views.append([target_center + d.normalized() * dist, target_center, fov])
	_aim(0)


func _v3(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func _build_stage() -> void:
	# A real sky (horizon = the JS sky color) so metal and gloss have something to reflect.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#8fb4dc")
	sky_mat.sky_horizon_color = Color("#b9d0e4")
	sky_mat.ground_horizon_color = Color("#b9d0e4")
	sky_mat.ground_bottom_color = Color("#7d7a70")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_hdr_threshold = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#fff0d8")
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.light_angular_distance = 1.5
	sun.directional_shadow_max_distance = 80.0
	root.add_child(sun)
	sun.look_at_from_position(Vector3(14, 26, 12), Vector3.ZERO, Vector3.UP)
	if not args.has("no-ground"):
		var g := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(400, 400)
		g.mesh = pm
		g.material_override = ClayLib.clay("#7d7a70", 0.95)
		g.position.y = -0.003
		root.add_child(g)
	cam = Camera3D.new()
	cam.far = 1000.0
	root.add_child(cam)
	cam.current = true


func _fit() -> void:
	var box := AABB()
	var first := true
	for n in _all(inst):
		if n is VisualInstance3D and n.visible:
			var b: AABB = n.global_transform * n.get_aabb()
			box = b if first else box.merge(b)
			first = false
	target_center = box.get_center()
	target_radius = maxf(box.size.length() * 0.5, 0.05)


func _all(n: Node) -> Array:
	var out := [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out


func _aim(i: int) -> void:
	var v: Array = views[i]
	cam.fov = v[2]
	cam.look_at_from_position(v[0], v[1], Vector3.UP)
	frames = 0


func _process(_delta: float) -> bool:
	if not started:
		started = true
		_setup()
		return false
	frames += 1
	if frames < 12:
		return false
	shots.append(root.get_texture().get_image())
	view_i += 1
	if view_i < views.size():
		_aim(view_i)
		return false
	_save()
	return true


func _save() -> void:
	var out_path: String = args.get("out", "user://shot.png")
	var img: Image
	if shots.size() == 1:
		img = shots[0]
	else:
		var w := shots[0].get_width()
		var h := shots[0].get_height()
		img = Image.create(w * 2, h * 2, false, shots[0].get_format())
		for k in shots.size():
			img.blit_rect(shots[k], Rect2i(0, 0, w, h), Vector2i((k % 2) * w, (k / 2) * h))
	img.save_png(out_path)
	print("[shot] saved ", out_path)
