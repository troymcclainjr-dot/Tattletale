extends SceneTree
## Loads (compiles) every script under res://scripts, res://tests and res://tools with the
## autoloads in place, and prints the ones that fail. Exit code = number of failures.
##   python godot/tools/godot_run.py -- --headless --script res://tools/check.gd

var bad := 0


func _initialize() -> void:
	for dir in ["res://scripts", "res://tests", "res://tools"]:
		_scan(dir)
	print("[check] %d script(s) failed" % bad)
	quit(bad)


func _scan(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd") and f != "check.gd":
			var p := dir.path_join(f)
			var s = ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_IGNORE)
			if s == null or not (s is GDScript) or not s.can_instantiate():
				print("[check] FAIL ", p)
				bad += 1
	for d in DirAccess.get_directories_at(dir):
		_scan(dir.path_join(d))
