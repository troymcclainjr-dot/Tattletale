extends Node
const Emergency := preload("res://scripts/city/city_emergency_response.gd")
const Collision := preload("res://scripts/city/city_car_collision.gd")
const District := preload("res://scripts/city/city_civic_district.gd")
const Clearance := preload("res://scripts/city/city_civic_clearance.gd")
var failures := 0
var passes := 0

class ParkingLevelFixture:
	extends Node3D
	var civic_district: Node3D

func check(ok: bool, label: String) -> void:
	if ok:
		passes += 1
	else:
		failures += 1
	print("[ems_parking] ", "PASS " if ok else "FAIL ", label)

func _ready() -> void:
	var ambulance := Emergency._parking_footprint(Transform3D.IDENTITY, "minivan")
	check(Emergency._footprints_overlap(ambulance, ambulance), "coincident full vehicle envelopes are blocked")
	var alongside := Emergency._parking_footprint(Transform3D(Basis.IDENTITY, Vector3(4, 0, 0)), "minivan")
	check(not Emergency._footprints_overlap(ambulance, alongside), "clear parallel vehicles within old five-metre disk are permitted")
	var nose := Emergency._parking_footprint(Transform3D(Basis.IDENTITY, Vector3(0, 0, 4)), "minivan")
	check(Emergency._footprints_overlap(ambulance, nose), "same centre distance in the long direction remains blocked")
	var crossing := Emergency._parking_footprint(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(3.1, 0, 0)), "minivan")
	check(Emergency._footprints_overlap(ambulance, crossing), "rotated crossing vehicle full envelopes remain blocked")
	var width: float = Collision.envelope("minivan").shape.size.x
	var too_close := Emergency._parking_footprint(Transform3D(Basis.IDENTITY, Vector3(width + 0.10, 0, 0)), "minivan")
	var clear_gap := Emergency._parking_footprint(Transform3D(Basis.IDENTITY, Vector3(width + 0.25, 0, 0)), "minivan")
	check(Emergency._footprints_overlap(ambulance, too_close), "ten-centimetre side clearance is refused")
	check(not Emergency._footprints_overlap(ambulance, clear_gap), "twenty-five-centimetre side clearance is accepted")
	check(Emergency._footprints_overlap(crossing, ambulance) == Emergency._footprints_overlap(ambulance, crossing), "separating-axis decision is symmetric")
	var tilted := Emergency._parking_footprint(Transform3D(Basis(Vector3.FORWARD, 0.35), Vector3.ZERO), "minivan")
	var max_flat := 0.0
	var max_tilt := 0.0
	for point in ambulance:
		max_flat = maxf(max_flat, absf(point.x))
	for point in tilted:
		max_tilt = maxf(max_tilt, absf(point.x))
	check(max_tilt > max_flat, "footprint includes lateral projection of tilted full-height body")
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(District.PLAN))
	var hospital: Dictionary = {}
	for site in plan.sites:
		if site.id == "hospital":
			hospital = site
	var world := ParkingLevelFixture.new()
	var district := District.new()
	world.civic_district = district
	world.add_child(district)
	district._region(hospital.emergency_driveway_xz, [], true)
	check(Clearance.parking_blocked(world, Vector3(391.985, 0, -144.9334), 2.5), "actual southern curb car cannot block emergency approach")
	check(Clearance.parking_blocked(world, Vector3(394.1447, 0, -137.23), 2.5), "actual northern curb car cannot block emergency approach")
	check(not Clearance.parking_blocked(world, Vector3(389.8248, 0, -152.6362), 2.5), "adjacent southern parking outside driveway remains eligible")
	check(not Clearance.parking_blocked(world, Vector3(396.3086, 0, -129.689), 2.5), "adjacent northern parking outside driveway remains eligible")
	check(not Clearance.parking_blocked(world, Vector3(383.0, 0, -145.0), 2.5), "opposite curb outside hospital driveway remains eligible")
	check(not Clearance.blocked(world, Vector3(391.985, 0, -144.9334), 2.5), "parking-only reservation does not expand general population clearance")
	world.free()
	print("[ems_parking] COMPLETE ", passes, " passed; ", failures, " failed")
	get_tree().quit(1 if failures else 0)

