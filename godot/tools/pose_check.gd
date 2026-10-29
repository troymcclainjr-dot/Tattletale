extends SceneTree
## Where do the hands land? Poses a few puppets and prints the distance (in m) from the right hand
## to the mouth or the right ear, so hand-to-face poses can be checked without screenshots.
##   python godot/tools/godot_run.py -- --headless --script res://tools/pose_check.gd
## The checks live in pose_check_driver.gd, loaded once the autoloads exist (a --script file is
## compiled before them, so it can't reference G, Cast or Animate directly).

var _started := false


func _initialize() -> void:
	# never hold the shared Godot lock on a script error: quit after 30 s regardless
	create_timer(30.0).timeout.connect(func(): quit(1))


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		root.add_child(load("res://tools/pose_check_driver.gd").new())
	return false
