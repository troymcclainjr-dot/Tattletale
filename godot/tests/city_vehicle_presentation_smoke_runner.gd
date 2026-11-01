extends Node
## Production meshes/puppet/audio with a minimal ownership fixture. No movement
## mocks are used to assert movement; these checks isolate presentation only.
const Presentation := preload("res://scripts/city/city_vehicle_presentation.gd")
const Interior := preload("res://scripts/city/city_vehicle_interior.gd")
const Models := preload("res://scripts/city/city_car_models.gd")
class LevelFixture:
	extends Node3D
	var paused := false
	var driving: Node3D
class DrivingFixture:
	extends Node3D
	var active := false
	var vehicle: Node3D
	var _controls: Dictionary = {"throttle": 0.0, "handbrake": false}
	func current_controls() -> Dictionary:
		return _controls.duplicate()
class CarFixture:
	extends Node3D
	var prototype_kind := "hatchback"
	var model: Node3D
	var speed := 0.0
	var drive_velocity := Vector3.ZERO
	var drive_steer := 0.0
	var drive_airborne := false
	var body_disabled := false
var passes := 0
var failures := 0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	passes += int(ok)
	failures += int(not ok)
	print("[vehicle_presentation] %s %s" % ["PASS" if ok else "FAIL", label])

func _run() -> void:
	G.built = false
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	var level := LevelFixture.new()
	add_child(level)
	var driving := DrivingFixture.new()
	level.add_child(driving)
	level.driving = driving
	var view := Presentation.new()
	level.add_child(view)
	view.setup(level)
	var car := CarFixture.new()
	level.add_child(car)
	car.position = Vector3(7, 0, -11)
	car.rotation.y = 0.7
	car.model = Models.make("hatchback", 3)
	car.add_child(car.model)
	var body: MeshInstance3D = car.model.get_node("Body")
	var original := body.mesh
	var original_paint := body.get_surface_override_material(0)
	driving.active = true
	driving.vehicle = car
	view.tick(1.0 / 60.0)
	check(view.vehicle == car and view.driver.g.visible and view.driver.id == "two_pack", "actual 2Pack rig attaches to the active car")
	check(view.global_transform.is_equal_approx(car.global_transform), "posed driver follows complete car basis and location")
	check(body.mesh != original and original == Models.prototype("hatchback").body, "window openings never mutate shared prototype")
	check(body.get_surface_override_material(0) == original_paint, "car paint override survives occupied body replacement")
	var zones := view.get_occupant_hit_zones(car)
	check(zones.size() == 2 and zones[0].center.distance_to(view.driver.head.global_transform * Vector3(0, view.driver.hy, 0)) < 0.001, "virtual head target follows exact visible rig")
	var local_head: Vector3 = car.to_local(zones[0].center)
	check(local_head.x > 0 and local_head.x + float(zones[0].radius) < Models.dimensions("hatchback").x * 0.5
		and local_head.y + float(zones[0].radius) < Models.dimensions("hatchback").y, "head stays inside driver side cabin below roof")
	# The anatomical driver head now sits behind the B-pillar in a perfectly
	# broadside view (hatchback pane gap z=-0.08..0). An observer forward of
	# the driver sees it through the actual front side pane. Keep the target
	# on the visible head and preserve the pillar as cover; do not move the
	# seat or loosen the production window-intersection test to satisfy this.
	check(view.ray_hits_window(car, car.to_global(local_head + Vector3(3, 0, 1.5)), zones[0].center), "driver head can be reached through actual driver-side glass")
	check(not view.ray_hits_window(car, car.to_global(Vector3(3, 0.35, 0)), car.to_global(Vector3(0, 0.35, 0))), "low chassis shots do not count as window penetration")
	check(view.engine.bus == &"SFX" and view.skid.bus == &"SFX" and view.horn.bus == &"SFX", "all three voices obey existing SFX slider")
	check(view.engine.stream != null and view.skid.stream != null and view.horn.stream != null, "all original PCM assets load after import")
	check(view.engine.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and view.skid.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "engine and friction use continuous loops")
	check(view.honk() and not view.honk() and view.horns_played == 1, "rapid horn presses cannot stack or bypass cooldown")
	car.speed = 18.0
	car.drive_velocity = car.global_basis.z * 18.0 + car.global_basis.x * 4.0
	driving._controls.throttle = 1.0
	view.tick(0.25)
	check(float(view.get_status().engine_pitch) > 0.85 and float(view.get_status().skid_gain) > 0.0, "speed/load raises engine pitch and actual slip starts tire friction")
	# AudioStreamPlayer3D starts play requests on the next physics/audio tick.
	# Pause actual live playback, as the existing world-audio regression does.
	await get_tree().physics_frame
	await get_tree().process_frame
	level.paused = true
	view.sync_pause()
	var paused_pitch: float = view.get_status().engine_pitch
	view.tick(1.0)
	check(view.engine.stream_paused and view.skid.stream_paused and view.horn.stream_paused and not view.honk(), "level pause suspends every voice and rejects horn")
	check(view.get_status().engine_pitch == paused_pitch, "paused tick does not advance engine presentation")
	level.paused = false
	get_tree().paused = true
	view.sync_pause()
	check(view.engine.stream_paused and not view.honk(), "tree pause independently suspends vehicle audio")
	get_tree().paused = false
	view.sync_pause()
	car.speed = 0.0
	car.drive_velocity = Vector3.ZERO
	driving._controls = {"throttle": 0.0, "handbrake": false}
	view.tick(1.0)
	check(float(view.get_status().skid_gain) == 0.0 and not view.skid.playing, "standing car cannot emit tire squeal")
	car.body_disabled = true
	view.tick(0.1)
	check(not view.engine.playing, "disabled vehicle stops its engine sound")
	car.body_disabled = false
	view.detach()
	check(body.mesh == original and body.get_surface_override_material(0) == original_paint, "detach restores exact original mesh and paint")
	check(not view.driver.g.visible and view.get_occupant_hit_zones(car).is_empty() and not view.engine.playing and not view.horn.playing, "detach removes visible and hittable occupant and stops sounds")
	view.detach()
	var retained_driver := view.driver.g.get_instance_id()
	for repeat in 3:
		view.attach(car)
		view.reset()
	check(view.driver.g.get_instance_id() == retained_driver and view.get_child_count() == 4, "repeated board/reset reuses one rig and exactly three voices")
	view.attach(car)
	car.free()
	driving.vehicle = null
	driving.active = false
	view.tick(0.1)
	check(not view.driver.g.visible and not view.engine.playing, "freed active car safely cleans presentation")
	for kind in Models.ALL_KINDS:
		_check_openings(kind)
	level.free()
	print("[vehicle_presentation] %d passed; %d failed" % [passes, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _check_openings(kind: String) -> void:
	var source: Mesh = Models.prototype(kind).body
	var opened := Interior.open_windows(source, kind)
	var paint: Array = []
	var source_paint: Array = []
	var panes: Array = []
	var original_area := 0.0
	var opened_area := 0.0
	for surface in source.get_surface_count():
		var material := source.surface_get_material(surface)
		if material.resource_name == "city_vehicle_glass":
			panes.append_array(Interior._triangles(source.surface_get_arrays(surface)))
		if material.resource_name == "city_vehicle_paint":
			source_paint = Interior._triangles(source.surface_get_arrays(surface))
			for triangle in source_paint:
				original_area += _area(triangle)
			paint = Interior._triangles(opened.surface_get_arrays(surface))
			for triangle in paint:
				opened_area += _area(triangle)
	check(opened_area < original_area - 0.1 and opened_area > original_area * 0.5, "%s opens real windows while retaining painted shell" % kind)
	var bounds := Interior.cabin_bounds(kind)
	var center := bounds.get_center()
	var above := Vector3(0.12, bounds.end.y - 0.01, center.z)
	var below := Vector3(0.12, bounds.position.y + 0.01, center.z)
	check(_paint_hit(source_paint, above, below) and not _paint_hit(paint, above, below), "%s occupied cabin has no opaque sill-height cap" % kind)
	check(_paint_hit(paint, Vector3(0.12, 0.44, center.z), Vector3(0.12, 0.05, center.z)), "%s retains opaque chassis underfloor" % kind)
	var hood_z := bounds.end.z + 0.10
	var rear_z := bounds.position.z - 0.10
	check(_paint_hit(paint, Vector3(0.12, bounds.end.y, hood_z), Vector3(0.12, 0.45, hood_z))
		and _paint_hit(paint, Vector3(0.12, bounds.end.y, rear_z), Vector3(0.12, 0.45, rear_z)), "%s retains cap outside cabin at hood/rear boundary" % kind)
	var clear := 0
	for pane in panes:
		var pane_center: Vector3 = (pane[0].p + pane[1].p + pane[2].p) / 3.0
		var normal: Vector3 = (pane[1].p - pane[0].p).cross(pane[2].p - pane[0].p).normalized()
		# A nearly-collinear sill triangle has an ill-conditioned normal
		# pointing mostly downward. That ray would hit valid painted sill
		# below the opening. Probe actual side-window backing along +/−X.
		if Interior.is_sliver(pane) and absf(pane_center.x) > Models.dimensions(kind).x * 0.3:
			normal = Vector3(signf(pane_center.x), 0, 0)
		var blocked := false
		for triangle in paint:
			if Geometry3D.segment_intersects_triangle(pane_center + normal * 0.09, pane_center - normal * 0.09, triangle[0].p, triangle[1].p, triangle[2].p) != null:
				blocked = true
				var paint_normal: Vector3 = (triangle[1].p - triangle[0].p).cross(triangle[2].p - triangle[0].p).normalized()
				var distance := 0.0
				for vertex in pane:
					distance = maxf(distance, absf(paint_normal.dot(vertex.p - triangle[0].p)))
				print("[vehicle_presentation] RESIDUAL ", kind, " pane=", [pane[0].p, pane[1].p, pane[2].p],
					" paint=", [triangle[0].p, triangle[1].p, triangle[2].p], " normal_dot=", absf(normal.dot(paint_normal)), " plane_distance=", distance)
				break
		clear += int(not blocked)
	check(clear == panes.size(), "%s each authored pane center has no opaque paint underneath (%d/%d)" % [kind, clear, panes.size()])

func _area(triangle: Array) -> float:
	return (triangle[1].p - triangle[0].p).cross(triangle[2].p - triangle[0].p).length() * 0.5

func _paint_hit(triangles: Array, a: Vector3, b: Vector3) -> bool:
	for triangle in triangles:
		if Geometry3D.segment_intersects_triangle(a, b, triangle[0].p, triangle[1].p, triangle[2].p) != null:
			return true
	return false
