extends Node
## In-game screenshots (driver; tools/game_shot.gd starts it). Loads main.tscn, sets up a scenario through the debug hooks, advances
## game time with G.tick(), and saves one PNG per view.
##   python godot/tools/godot_run.py --timeout 300 -- --resolution 1600x900 --script res://tools/game_shot.gd -- \
##       --views overview,lineup_a,play --outdir C:/abs/dir [--t 2.0]
## Views: the web reference views (.work/ref/ref.html: overview, houses_west, tp_house, shops,
## precinct, gary_spot, stand_phone, west_stage2, crosswalk, ice_cream, lineup_a, lineup_b, cars,
## tp_close) and gameplay views: title, play, run, bino_gary, stage2, puzzle, finale.

const REF := {
	"overview": [Vector3(6, 18, 34), Vector3(6, 0, -4), 50.0],
	"houses_west": [Vector3(-20, 4, 10), Vector3(-20, 3.2, -7), 55.0],
	"tp_house": [Vector3(0, 3.5, 8), Vector3(0, 3, -7), 55.0],
	"shops": [Vector3(33, 5, 12), Vector3(33, 3, -7), 55.0],
	"precinct": [Vector3(37, 2.8, 3), Vector3(36.5, 2, -6), 55.0],
	"gary_spot": [Vector3(-2.5, 2.6, 5.5), Vector3(-3.6, 0.6, 0.8), 45.0],
	"stand_phone": [Vector3(18, 2.2, 2.2), Vector3(17.5, 1, -3.3), 50.0],
	"west_stage2": [Vector3(-13, 3.2, 4), Vector3(-13.3, 1, -4.8), 55.0],
	"crosswalk": [Vector3(5, 3, 19), Vector3(-1, 2.5, 11), 55.0],
	"ice_cream": [Vector3(21.5, 2.2, 2.8), Vector3(23, 1, -2.2), 50.0],
	"lineup_a": [Vector3(0, 1.5, 12.8), Vector3(0, 1.0, 6), 50.0],
	"lineup_b": [Vector3(0, 1.5, 12.8), Vector3(0, 1.0, 6), 50.0],
	"cars": [Vector3(4, 2.5, 9.5), Vector3(4, 0.8, 2.7), 50.0],
	"tp_close": [Vector3(0, 1.6, 3.6), Vector3(0, 1.25, 0.4), 40.0],
}

var args := {}
var views: Array = []
var vi := 0
var frames := 0
var phase := 0
var main: Node
var _calib := 0
var _perf := 0
var _view_t0 := 0
var _perf_t0 := 0
var _calib_c := Lighting.HORIZON_IN
var _fog_in := Color()


func _ready() -> void:
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
	views = str(args.get("views", "overview")).split(",")


func _process(_delta: float) -> void:
	if phase == 0:
		main = load("res://scenes/main.tscn").instantiate()
		get_tree().root.add_child(main)
		phase = 1
		return
	if phase == 1:
		frames += 1
		if frames < 3:
			return
		G.manual = true
		seed(7)
		phase = 2
		_setup(views[vi])
		frames = 0
		return
	frames += 1
	if _calib > 0:
		_calib_step()
		return
	if _perf > 0:
		if frames == 60:
			_perf_t0 = Time.get_ticks_usec()
			G.K["move_forward"] = true
		if frames == 360:
			var sec := (Time.get_ticks_usec() - _perf_t0) / 1e6
			print("[perf] %.1f fps average over 300 frames (%s, %s)" % [300.0 / sec, RenderingServer.get_video_adapter_name(), str(get_viewport().get_visible_rect().size)])
			print("[perf] draw calls %d, primitives %d" % [RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
			get_tree().quit()
		return
	if frames < int(args.get("frames", "10")) or Time.get_ticks_msec() - _view_t0 < float(args.get("wait", "0")) * 1000.0:
		_keep(views[vi])
		return
	var dir: String = args.get("outdir", OS.get_user_data_dir())
	DirAccess.make_dir_recursive_absolute(dir)
	var p := dir.path_join(views[vi] + ".png")
	get_viewport().get_texture().get_image().save_png(p)
	print("[game_shot] saved ", p)
	vi += 1
	if vi >= views.size():
		print("[game_shot] glb: ", Assets.used_glb)
		print("[game_shot] placeholders: ", Assets.used_placeholder)
		get_tree().quit()
		return
	_setup(views[vi])
	frames = 0
	return


func _run(sec: float, dt := 1.0 / 60.0) -> void:
	var n := int(sec / dt)
	for k in n:
		G.tick(dt)


## Everybody out where the camera can see them (like ref.html).
func _ref_cast() -> void:
	var W := G.W
	G.S.mode = "ref"
	G.W_.stand_sign.visible = true
	G.W_.stand_closed.visible = false
	G.timmy.g.visible = true
	W.mama.g.visible = true
	W.dad.on = true
	for L in W.liners:
		L.rig.g.visible = true
	W.baby.visible = true
	W.baby_rig.g.visible = true
	W.baby.x = 22.4
	W.baby.z = -1.38
	W.ricky.visible = true
	G.ricky.g.visible = true
	W.ricky.x = 26.0
	W.ricky.z = -1.05
	W.granny.visible = true
	G.granny.g.visible = true
	W.granny.x = 7.2
	W.granny.z = 3.0
	W.mail.visible = true
	G.mailman.g.visible = true
	W.mail.x = -20.45
	W.mail.z = -2.3
	W.sq.g.visible = true
	W.sq.x = -8.0
	W.sq.z = -2.2
	W.mama_car.g.visible = true
	W.mama_car.x = -3.0
	Stage2Crimes.place2(W.mama_car)
	World.set_plate("4721")


func _lineup(view: String) -> void:
	var W := G.W
	var all: Array = [G.tp, G.ricky, G.granny, G.timmy, G.mailman, G.dan, G.steve, W.mama, W.vendor]
	for L in W.liners:
		all.append(L.rig)
	all.append(W.baby_rig)
	var rigs: Array = all.slice(0, 8) if view == "lineup_a" else all.slice(8)
	W.mama_car.g.visible = false
	for i in rigs.size():
		var r: Puppet = rigs[i]
		r.g.visible = true
		r.g.rotation = Vector3.ZERO
		r.place((i - (rigs.size() - 1) / 2.0) * 1.2, 6.0, 0.0, 0.0)
		r.pose({"armR": [-0.2, 0.15], "armL": [-0.2, 0.15]})


func _setup(view: String) -> void:
	_view_t0 = Time.get_ticks_msec()
	G.cam_override = null
	G.K.clear()
	G.S.bino_on = false
	if REF.has(view):
		Hud.hide_screens()
		Hud.show_hud(false)
		Hud.clear_subs()
		_ref_cast()
		if view == "cars":
			G.car.x = 7.0
			G.W.mama_car.x = 0.5
			G.W.mama_car.z = 2.7
			Stage2Crimes.place2(G.W.mama_car)
		var v: Array = REF[view]
		G.cam_override = {"p": v[0], "l": v[1], "f": v[2]}
		_run(float(args.get("t", "1.0")))
		_keep(view)
		return
	match view:
		"perf":
			# real-time play for a while; prints the average frame rate
			G.start_game()
			G.manual = false
			_perf = 1
		"calib_sky":
			# find the background color that displays as #b9d0e4 through AgX and the adjustments
			Hud.hide_screens()
			Hud.show_hud(false)
			G.cam_override = {"p": Vector3(0, 120, 0), "l": Vector3(0, 120, -100), "f": 20.0}
			_calib = 1
		"title":
			G.S.mode = "title"
			_run(2.0)
		"play":
			G.start_game()
			_run(float(args.get("t", "3.0")))
		"run":
			G.start_game()
			G.K["move_forward"] = true
			G.K["run"] = true
			_run(1.2)
			G.K.clear()
		"bino_gary":
			G.start_game()
			G.tt_teleport(3.0, -2.2, -PI / 2 - 0.15)
			G.K["binoculars"] = true
			_run(0.3)
			var eye := Vector3(G.P.x, World.ground_y(G.P.x, G.P.z) + 1.68, G.P.z)
			var v := Vector3(-3.55, 0.45, 0.73) - eye
			G.tt_aim(atan2(v.x, v.z), asin(v.y / v.length()))
			_run(0.8)
		"stage2":
			G.start_stage(2, false)
			_run(float(args.get("t", "3.0")))
		"puzzle":
			G.start_game()
			G.C.gary.si = 1
			G.tt_teleport(2.8, -2.2, PI)
			Interact.interact()
			_run(1.0)
		"squirrel_held", "squirrel_jail":
			G.start_stage(2, false)
			G.S.spawn_t = 1e9
			Crimes.start_crime("squirrel")
			_run(0.5)
			var q = G.W.sq
			G.tt_teleport(q.x + 0.6, q.z, -PI / 2)
			Interact.interact()
			_run(0.6)
			if view == "squirrel_jail":
				G.tt_teleport(World.JAIL[0], World.JAIL[1] + 1.1, PI)
				Interact.interact()
				_run(1.0)
				G.cam_override = {"p": Vector3(World.JAIL[0] + 1.2, 1.6, World.JAIL[1] + 2.2), "l": Vector3(World.JAIL[0], 0.7, World.JAIL[1]), "f": 40.0}
			else:
				G.cam_override = {"p": Vector3(G.P.x - 1.6, 1.6, G.P.z + 1.4), "l": Vector3(G.P.x, 1.0, G.P.z), "f": 45.0}
			_keep(view)
		"plate":
			G.start_stage(2, false)
			G.S.spawn_t = 1e9
			Crimes.start_crime("mama")
			_run(4.0)
			var mc = G.W.mama_car
			G.cam_override = {"p": Vector3(mc.x - 4.2, 1.3, mc.z + 1.6), "l": Vector3(mc.x - 2.1, 0.7, mc.z), "f": 40.0}
		"dad_fall":
			G.start_stage(2, false)
			G.S.spawn_t = 1e9
			Crimes.start_crime("daddy")
			G.C.daddy.si = 1
			G.tt_teleport(World.HAMMOCK[0] - 0.9, World.HAMMOCK[1] + 1.05, PI)
			Interact.interact()
			_run(0.95)
			G.cam_override = {"p": Vector3(World.HAMMOCK[0] + 1.5, 1.8, World.HAMMOCK[1] + 4.5), "l": Vector3(World.HAMMOCK[0], 0.7, World.HAMMOCK[1]), "f": 45.0}
		"siren":
			G.start_game()
			G.S.spawn_t = 1e9
			G.C.gary.si = 1
			Crimes.dispatch(["gary"])
			_run(4.2)
			G.cam_override = {"p": Vector3(G.car.x - 5.0, 3.0, 7.5), "l": Vector3(G.car.x, 1.0, 2.7), "f": 45.0}
		"bills":
			G.start_game()
			G.S.spawn_t = 1e9
			Crimes.start_crime("ricky")
			_run(13.0)
			var w: Walker = G.W.ricky
			G.cam_override = {"p": Vector3(w.x + 3.0, 2.4, w.z + 3.5), "l": Vector3(w.x + 2.0, 0.5, w.z), "f": 45.0}
		"granny_walk":
			# Grandma mid-stride with her walker: the hands should stay on the grips
			G.start_game()
			G.S.spawn_t = 1e9
			Crimes.start_crime("granny")
			_run(float(args.get("t", "4.0")))
			var gw: Walker = G.W.granny
			var side := Vector3(cos(gw.yaw), 0, -sin(gw.yaw))
			var at := Vector3(gw.x, 0.8, gw.z)
			G.cam_override = {"p": at + side * 2.6 + Vector3(0, 0.5, 0) + Vector3(sin(gw.yaw), 0, cos(gw.yaw)) * 1.2, "l": at, "f": 40.0}
			_keep(view)
		"finale":
			G.start_stage(2, false)
			Game.start_finale_setup()
			_run(6.0)
			Game.start_finale()
			_run(float(args.get("t", "5.0")))


func _keep(view: String) -> void:
	if view != "play" and view != "bino_gary" and not args.has("hud"):
		Hud.show_hud(false)
		Hud.clear_subs()
	if view.begins_with("lineup"):
		_lineup(view)
	if view == "tp_close":
		G.tp.g.visible = true
		G.tp.place(0, 0.4, 0, 0.0)
		G.tp.pose({"armR": [-0.3, 0.3], "armL": [-0.3, 0.3]})
	if G.cam_override != null:
		Player.update_camera(0.0, true)


func _calib_step() -> void:
	# phase 1 (_calib 1..12): background as a flat color = the fog's pipeline -> SKY_IN
	# phase 2 (_calib 13..24): the procedural sky's horizon -> HORIZON_IN
	Player.update_camera(0.0, true)
	if frames % 4 != 0:
		return
	var env: Environment = G.world_root.get_node("WorldEnvironment").environment
	if _calib == 1:
		env.background_mode = Environment.BG_COLOR
		_calib_c = Lighting.SKY_IN
		env.background_color = _calib_c
		_calib = 2
		return
	if _calib == 13:
		print("[calib] SKY_IN := ", _calib_c)
		_fog_in = _calib_c
		env.background_mode = Environment.BG_SKY
		_calib_c = Lighting.HORIZON_IN
		env.sky.sky_material = Lighting.sky_material(_calib_c)
		_calib = 14
		return
	var img := get_viewport().get_texture().get_image()
	var m := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
	var want := Color("#b9d0e4")
	print("[calib] in %s -> out %s (want %s)" % [_calib_c, m.to_html(false), want.to_html(false)])
	var lin := _calib_c.srgb_to_linear()
	var ml := m.srgb_to_linear()
	var wl := want.srgb_to_linear()
	lin = Color(lin.r * wl.r / maxf(ml.r, 0.001), lin.g * wl.g / maxf(ml.g, 0.001), lin.b * wl.b / maxf(ml.b, 0.001))
	_calib_c = lin.linear_to_srgb()
	if _calib < 13:
		env.background_color = _calib_c
	else:
		env.sky.sky_material = Lighting.sky_material(_calib_c)
	_calib += 1
	if _calib > 25:
		print("[calib] HORIZON_IN := ", _calib_c)
		# ambient that matches the art previews' sky (horizon #b9d0e4 uncalibrated) at 0.75
		var mine := _calib_c.srgb_to_linear().get_luminance()
		var theirs := Color("#b9d0e4").srgb_to_linear().get_luminance()
		print("[calib] AMBIENT := %.3f" % (0.75 * theirs / mine))
		get_tree().quit()
