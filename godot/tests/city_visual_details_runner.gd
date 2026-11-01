extends Node3D
## Small geometry fixture: no full city, streaming cache, or renderer needed.
const Windows := preload("res://scripts/city/city_windows.gd")
const Dressing := preload("res://scripts/city/city_dressing.gd")
var failures := 0

class FixtureWindows extends "res://scripts/city/city_windows.gd":
	var fixture: Dictionary
	func _load_homes() -> Dictionary:
		return fixture

func ground_at(_point: Vector3) -> Dictionary:
	return {"position": Vector3.ZERO}

func check(ok: bool, message: String) -> void:
	print("[visual_details] %s %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var windows := FixtureWindows.new()
	var selected := ""
	var unselected := ""
	for index in 100:
		var id := "fixture_home_%d" % index
		if Windows.home_seed(id) % 10 < 8:
			selected = id
		else:
			unselected = id
		if not selected.is_empty() and not unselected.is_empty():
			break
	windows.fixture = {"Row_fixture": [
		{"id": selected, "residential": true, "center": Vector2(1, 2), "polygon": PackedVector2Array([Vector2(0, 0), Vector2(2, 0), Vector2(2, 4), Vector2(0, 4), Vector2(0, 0)])},
		{"id": unselected, "residential": true, "center": Vector2(3, 2), "polygon": PackedVector2Array([Vector2(2, 0), Vector2(4, 0), Vector2(4, 4), Vector2(2, 4), Vector2(2, 0)])}]}
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pane := BoxMesh.new()
	pane.size = Vector3(1, 1.2, 0.025)
	for x in [1.0, 3.0]:
		for y in [1.7, 4.7]:
			for z in [-0.02, 4.02]:
				surface.append_from(pane, 0, Transform3D(Basis.IDENTITY, Vector3(x, y, z)))
	var glass := StandardMaterial3D.new()
	glass.resource_name = Windows.GLASS_NAME
	surface.set_material(glass)
	var city := Node3D.new()
	add_child(city)
	var row := MeshInstance3D.new()
	row.name = "Row_fixture"
	row.mesh = surface.commit()
	city.add_child(row)
	var report := windows.build(self, city)
	check(int(report.eligible_house_windows) == 8, "both floors and both facades are measured")
	check(int(report.window_homes[selected].barred) == 4, "every window of selected home receives bars")
	check(int(report.window_homes[unselected].barred) == 0, "adjacent home in same row keeps its own decision")
	check(int(report.window_bar_triangles) == 8, "grilles remain two triangles per window")
	var loaded := Windows.new()._load_homes()
	check(loaded.size() > 100, "committed house ownership covers the city")
	var sign := Node3D.new()
	add_child(sign)
	Dressing._stop_sign(sign)
	var label: Label3D = sign.find_children("*", "Label3D", true, false)[0]
	check(not label.double_sided and not label.no_depth_test, "STOP lettering is front-only and depth-tested")
	var arrays := Dressing._stop_sign_mesh().surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var pole_behind := true
	var rear_opaque := false
	var front_clear := true
	for index in vertices.size():
		if colors[index].is_equal_approx(Color(Dressing.IRON)):
			pole_behind = pole_behind and vertices[index].z < -0.025
		if colors[index].is_equal_approx(Color("#777f80")) and normals[index].z < -0.99:
			rear_opaque = true
		front_clear = front_clear and vertices[index].z < label.position.z
	check(pole_behind and front_clear, "rear-mounted pole and solid plate stay behind lettering")
	check(rear_opaque, "stop sign has a separate unlettered opaque rear face")
	print("[visual_details] failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
