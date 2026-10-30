extends Node3D
## An interpreted signalized junction at the exported Old York/Wyanoke crossing.
## This is a gameplay control plan, not a survey of Baltimore signal equipment.
## No realtime lights: the original GLB lamp lenses share six emissive materials.

const CYCLE := 36.0
const STOP_LINE := 9.0
var elapsed := 0.0
var junction := Vector3.ZERO
var heads: Array[Dictionary] = []
var _materials: Dictionary = {}
var _last_phase := ""

func setup(level: Node3D) -> void:
	name = "OldYorkWyanokeSignals"
	# Wyanoke's east segment begins at the shared map node (0,0,0).
	var found := false
	for road in level.level_data.get("roads", []):
		if str(road.get("name", "")) != "Wyanoke Avenue":
			continue
		for point in road.get("points", []):
			var p: Vector3 = level.vector(point)
			if Vector2(p.x, p.z).length() < 0.5:
				junction = p
				found = true
	if not found:
		return
	for color_name in ["Red", "Yellow", "Green"]:
		var color: Color = {"Red": Color("ff2a2a"), "Yellow": Color("ffc21a"), "Green": Color("2aff6a")}[color_name]
		for active in [false, true]:
			var material := StandardMaterial3D.new()
			material.albedo_color = color if active else color.darkened(0.88)
			material.roughness = 0.55
			material.emission_enabled = active
			material.emission = color
			material.emission_energy_multiplier = 2.0 if active else 0.0
			_materials[color_name + str(active)] = material
	var placements := [
		[Vector3(5.6, 0, -8.0), PI / 2.0, "old_york"],
		[Vector3(-5.6, 0, 8.0), -PI / 2.0, "old_york"],
		[Vector3(8.0, 0, 5.6), 0.0, "wyanoke"],
		[Vector3(-8.0, 0, -5.6), PI, "wyanoke"]]
	for placement in placements:
		var at: Vector3 = junction + placement[0]
		var anchor := CityDressing.fixture_position(level, at, 0.25, 4.8)
		if anchor.is_empty():
			continue
		var model := Assets.glb("traffic_light")
		if model == null:
			continue
		add_child(model)
		# Original model's mounting plate starts at .16, matching its old curb.
		model.position = anchor.position - Vector3.UP * 0.16
		model.rotation.y = float(placement[1])
		model.set_meta("dressing_kind", "traffic_light")
		model.set_meta("placement", "Interpreted signal control at Old York / Wyanoke")
		var lenses: Dictionary = {}
		for color_name in ["Red", "Yellow", "Green"]:
			var lens := Assets.find(model, "Lamp" + color_name) as MeshInstance3D
			if lens:
				lenses[color_name] = lens
		heads.append({"axis": str(placement[2]), "lenses": lenses})
		var body := CityDressing._body(model)
		CityDressing._solid_pole(body, 0.20, 4.8, Vector3(0, 2.4, 0))
		CityDressing._solid_box(body, Vector3(0.46, 0.3, 3.5), Vector3(0, 4.5, -1.6))
		CityDressing._solid_box(body, Vector3(0.65, 1.4, 0.7), Vector3(-0.1, 3.95, -3.1))
	update_lenses()

func phase(axis: String) -> String:
	var t := fposmod(elapsed, CYCLE)
	if axis == "old_york":
		return "Green" if t < 16.0 else ("Yellow" if t < 19.0 else "Red")
	return "Green" if t >= 21.0 and t < 31.0 else ("Yellow" if t >= 31.0 and t < 34.0 else "Red")

func tick(dt: float) -> void:
	elapsed = fposmod(elapsed + maxf(0.0, dt), CYCLE)
	update_lenses()

func update_lenses() -> void:
	var state := phase("old_york") + phase("wyanoke")
	if state == _last_phase:
		return
	_last_phase = state
	for head in heads:
		for color_name in head.lenses:
			var lens: MeshInstance3D = head.lenses[color_name]
			lens.material_override = _materials[color_name + str(color_name == phase(head.axis))]

## Distance from the leading bumper to its near-side stop line. Once across
## the line a car clears the junction even when the signal phase changes.
func stopping_distance(at: Vector3, forward: Vector3, half_length: float) -> float:
	if heads.is_empty():
		return INF
	if absf(forward.x) > 0.8:
		if phase("wyanoke") == "Green" or absf(at.z - junction.z) > 4.5:
			return INF
		var direction_x := signf(forward.x)
		var distance_x := (junction.x - direction_x * STOP_LINE - at.x) * direction_x - half_length
		return maxf(0, distance_x) if distance_x >= -0.12 and distance_x <= 70 else INF
	if phase("old_york") == "Green" or absf(forward.z) < 0.8:
		return INF
	var direction := signf(forward.z)
	var stop_z := junction.z - direction * STOP_LINE
	var distance := (stop_z - at.z) * direction - half_length
	if distance < -0.12 or distance > 70.0 or absf(at.x - junction.x) > 4.5:
		return INF
	return maxf(0.0, distance)

func get_status() -> Dictionary:
	return {"heads": heads.size(), "old_york": phase("old_york"), "wyanoke": phase("wyanoke"), "elapsed": elapsed}
