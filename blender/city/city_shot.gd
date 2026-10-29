extends "res://tools/shot.gd"
## City preview: tools/shot.gd's stage and clay materials, but the GLB is read at runtime with
## GLTFDocument from anywhere on disk, so it never has to be imported into the Godot project.
## Run through blender/city/godot_shot.py (holds the shared Godot lock):
##   --glb C:/abs/pen_lucy.glb --out C:/abs/out.png --views "ex,ey,ez|lx,ly,lz|fov;..." [--shadow 400]


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
	args["no-ground"] = true
	_build_stage()
	cam.far = 4000.0
	for n in root.get_children():
		if n is DirectionalLight3D:
			n.directional_shadow_max_distance = float(args.get("shadow", "400"))
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(String(args.get("glb", "")), state)
	if err != OK:
		push_error("city_shot.gd: can't read %s (error %d)" % [args.get("glb", ""), err])
		quit(1)
		return
	inst = doc.generate_scene(state)
	root.add_child(inst)
	ClayLib.apply(inst)
	_fit()
	views = []
	for v in String(args.get("views", "")).split(";", false):
		var p := v.split("|")
		views.append([_v3(p[0]), _v3(p[1]), float(p[2]) if p.size() > 2 else 40.0])
	if views.is_empty():
		views.append([target_center + Vector3(-0.6, 0.5, 0.8) * target_radius * 1.6, target_center, 40.0])
	print("[city_shot] loaded %s, radius %.0f m, %d views" % [args.get("glb", ""), target_radius, views.size()])
	_aim(0)
