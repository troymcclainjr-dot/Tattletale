extends SceneTree
## In-game screenshots. Loads main.tscn, sets up a scenario through the debug hooks, advances
## game time with G.tick(), and saves one PNG per view (the work is in game_shot_driver.gd,
## loaded at runtime so it compiles after the autoloads exist).
##   python godot/tools/godot_run.py --timeout 300 -- --resolution 1600x900 --script res://tools/game_shot.gd -- ##       --views overview,lineup_a,play --outdir C:/abs/dir [--t 2.0] [--frames 10]


func _initialize() -> void:
	var d: Node = load("res://tools/game_shot_driver.gd").new()
	d.name = "GameShot"
	root.add_child.call_deferred(d)
