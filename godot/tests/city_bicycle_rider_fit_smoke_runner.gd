extends Node3D
## Production visual hand-contact solver, including steering and world tilt.
const BICYCLE := preload("res://scripts/city/city_bicycle.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var bike = BICYCLE.new()
	add_child(bike)
	bike.set_process(false)
	bike.set_physics_process(false)
	bike._build_model()
	var failures: Array[String] = []
	var rows: Array[Dictionary] = []
	for tilt in [Vector3.ZERO, Vector3(.2, .6, -.12)]:
		bike.rotation = tilt
		bike.position = Vector3(3, .4, -2)
		for steer in [-3.2, -1.0, 0.0, 1.0, 3.2]:
			bike._phase += PI / 2.0
			bike._animate(1.0, steer)
			for i in 2:
				var side := -1.0 if i == 0 else 1.0
				var grip: Vector3 = bike._front.to_global(Vector3(side * .30, .22, -.04))
				var gap: float = bike._rider.hand_pos(i).distance_to(grip)
				var length_scale: float = bike._rider.arms[i].scale.y
				rows.append({"steer": steer, "tilt": [tilt.x, tilt.y, tilt.z], "hand": i, "gap_m": gap, "longitudinal_scale": length_scale})
				if gap > .001 or length_scale < .70 or length_scale > 1.25:
					failures.append("steer=%s hand=%d gap=%.6fm length=%.3f" % [steer, i, gap, length_scale])
	var path := "res://../.work/model-quality-20261101/bicycle-hand-contact.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"failures": failures, "contacts": rows}, "\t"))
	file.close()
	for failure in failures:
		print("[bicycle_rider_fit] FAIL ", failure)
	print("[bicycle_rider_fit] %d contacts measured, %d failed" % [rows.size(), failures.size()])
	bike.free()
	get_tree().quit(0 if failures.is_empty() else 1)
