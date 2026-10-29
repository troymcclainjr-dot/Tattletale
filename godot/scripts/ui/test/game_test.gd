extends Node
## HUD-in-the-real-game harness: loads the main scene (G.boot builds the block), then drives the
## real gameplay code into a few HUD states and saves screenshots. Gameplay classes are loaded
## by path, so this file doesn't stop compiling when they change.
##   python godot/tools/godot_run.py --timeout 300 -- --resolution 1600x900 res://scenes/ui/game_test.tscn -- --out C:/abs/dir

var out_dir := ""
var g: Node
var hud: Node


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--out" and i + 1 < a.size():
			out_dir = a[i + 1]
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://").path_join("../.work/ui_shots").simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	g = get_node("/root/G")
	hud = get_node("/root/Hud")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _wait(1.5)
	await _shot("game_title")
	g.start_game()
	await _wait(3.0)
	await _shot("game_play")
	var crimes = load("res://scripts/crimes/crimes_core.gd")
	for id in ["ricky", "timmy", "lawn"]:
		crimes.start_crime(id)
	await _wait(1.2)
	await _shot("game_cases")
	Input.action_press("binoculars")
	await _wait(1.2)
	await _shot("game_bino")
	Input.action_release("binoculars")
	await _wait(0.3)
	var gary = g.C.get("gary")
	if gary:
		gary.si = 1
		var phones = g.W_.get("phones", []) if g.W_ is Dictionary else []
		if phones.size() > 1:
			load("res://scripts/crimes/puzzles.gd").open_puzzle(phones[1], [gary])
			await _wait(0.8)
			await _shot("game_puzzle")
			g.hang_up()
			await _wait(0.3)
	load("res://scripts/crimes/game.gd").game_over()
	await _wait(0.6)
	await _shot("game_over")
	get_tree().quit()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	var p := out_dir.path_join("hud_%s.png" % n)
	get_viewport().get_texture().get_image().save_png(p)
	print("[game_test] saved ", p)
