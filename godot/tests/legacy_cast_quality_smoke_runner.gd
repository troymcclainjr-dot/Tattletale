extends Node3D
## Actual imported cast geometry, actor binding, rest height and pose contracts.
## Loads only the sixteen authored characters; no city/world construction.

const BEFORE_TRIANGLES := {"baby": 20810, "cop_dan": 23936, "cop_steve": 24837,
	"dad": 19608, "gary": 24277, "granny": 24708, "liner_1": 23712,
	"liner_2": 21861, "liner_3": 22152, "liner_4": 21612, "mailman": 24360,
	"mama": 24572, "ricky": 24443, "timmy": 22170, "two_pack": 24996, "vendor": 24322}
const PARENTS := {"LegR": "Rig", "LegL": "Rig", "Body": "Rig",
	"ArmR": "Body", "ArmL": "Body", "HandR": "ArmR", "HandL": "ArmL",
	"Head": "Body", "Mouth": "Head"}
const ACCESSORIES := {"two_pack": {"Binoculars": "Head", "Cup": "HandL"},
	"cop_dan": {"Donut": "HandR"}, "cop_steve": {"Donut": "HandR"},
	"mailman": {"Letter": "HandR"}, "gary": {"Pipe": "HandR", "Ember": "Pipe"}}
var passes := 0
var failures: Array[String] = []
var measurements := {}
var pose_measurements := {}

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passes += 1
	else:
		failures.append(label)
		# Accumulate every identity's findings before the runner exits nonzero.
		print("[legacy_cast_quality] FAIL " + label)

func _run() -> void:
	check(Cast.LOOKS.size() == 16, "Cast.LOOKS contains all sixteen legacy identities")
	for identity in Cast.LOOKS:
		_check_character(str(identity))
	_check_contact_poses()
	var output := "res://../.work/model-quality-20261101/legacy-cast-engine-measurements.json"
	var args := OS.get_cmdline_user_args()
	var index := args.find("--report-out")
	if index >= 0 and index + 1 < args.size():
		output = args[index + 1]
	var absolute := ProjectSettings.globalize_path(output)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	check(file != null, "measurement report is writable")
	if file != null:
		file.store_string(JSON.stringify({"passes": passes, "failures": failures, "characters": measurements, "contact_poses": pose_measurements}, "\t"))
		file.close()
	print("[legacy_cast_quality] %d passed, %d failed; report %s" % [passes, failures.size(), absolute])
	get_tree().quit(0 if failures.is_empty() else 1)

func _check_character(identity: String) -> void:
	var placeholder_count := Assets.used_placeholder.size()
	var person := Cast.person(identity, self)
	check(Assets.used_placeholder.size() == placeholder_count, identity + " uses authored GLB")
	var rig := Assets.find(person.g, "Rig")
	check(rig != null, identity + " has Rig")
	if rig == null:
		person.g.free()
		return
	var landmarks: Dictionary = rig.get_meta("extras", {})
	var expected_version := 2 if identity in ["baby", "timmy"] else 1
	check(int(landmarks.get("anatomy_version", 0)) == expected_version, identity + " imported anatomy version")
	check(str(landmarks.get("anatomy_id", "")) == identity, identity + " imported identity metadata")
	check(is_equal_approx(float(landmarks.get("nominal_height", 0.0)), person.H), identity + " nominal height retained")
	check(rig.scale.is_equal_approx(Vector3.ONE) and person.g.scale.is_equal_approx(Vector3.ONE), identity + " unit actor/rig scale")
	check(rig.position.length() < .0001, identity + " origin remains grounded")
	check(landmarks.has("head_center_y") and landmarks.has("head_radius"), identity + " imported head landmarks")
	check(is_equal_approx(person.hy, float(landmarks.get("head_center_y", -1.0))), identity + " Puppet uses actual head center")
	if identity == "baby":
		check(person.hy > .17 * person.H and person.hy < .19 * person.H, "Baby retains infant head height")
		check(2.0 * person.hs > .25 * person.H and 2.0 * person.hs < .28 * person.H, "Baby reads about four heads tall")
	elif identity == "timmy":
		check(person.hy > .14 * person.H and person.hy < .16 * person.H, "Timmy retains older-child head height")
		check(person.hs > .11 * person.H and person.hs < .12 * person.H, "Timmy retains round child head")
	else:
		check(person.hy > .09 * person.H and person.hy < .14 * person.H, identity + " compact head center")
		check(person.hs > .085 * person.H and person.hs < .11 * person.H, identity + " compact head radius")
	for pivot in PARENTS:
		var node := Assets.find(person.g, str(pivot))
		check(node != null and str(node.get_parent().name) == str(PARENTS[pivot]), identity + " hierarchy " + str(pivot))
	var stats := {"points": [], "triangles": 0, "surfaces": 0, "meshes": 0}
	_collect(person.g, person.g.global_transform.affine_inverse(), stats)
	var bounds := _bounds(stats.points)
	check(stats.meshes > 0, identity + " imported mesh geometry")
	check(absf(bounds.position.y) < .008, identity + " sole/walker ground contact")
	check(bounds.end.y >= .98 * person.H and bounds.end.y <= 1.08 * person.H, identity + " actual adult/child height matches nominal plus hair/hat")
	check(int(stats.triangles) <= int(BEFORE_TRIANGLES[identity]), identity + " triangle budget did not increase")
	check(int(stats.surfaces) <= 80, identity + " bounded material surfaces")
	if identity == "two_pack":
		check(bounds.size.y > 1.77 and bounds.size.y < 1.83, "Two-Pack actual height is ordinary adult 1.8m")
		check(bounds.size.x > .62 and bounds.size.x < .75, "Two-Pack width matches adult/collision scale")
		check(not person.bino.visible and not person.cup.visible, "Two-Pack held items start hidden")
		person.bino.visible = true
		person.cup.visible = true
		check(person.bino.is_visible_in_tree() and person.cup.is_visible_in_tree(), "Two-Pack held item visibility toggles")
		person.bino.visible = false
		person.cup.visible = false
	var props: Dictionary = ACCESSORIES.get(identity, {})
	var prop_locals := {}
	for prop in props:
		var node := Assets.find(person.g, str(prop))
		check(node != null and str(node.get_parent().name) == str(props[prop]), identity + " accessory hierarchy " + str(prop))
		if node != null:
			prop_locals[prop] = node.transform
	if identity == "gary":
		check(not person.ember.is_empty(), "Gary Ember material hook binds")
	var rest_hip := person.body.position.y
	var hip_ratio: float = {"baby": .34, "timmy": .42}.get(identity, .49)
	check(absf(rest_hip - hip_ratio * person.H) < .001, identity + " anatomical hip pivot")
	person.phase = PI / 2.0
	person.pose({"walk": .4, "bob": .025, "look": .25, "nod": -.12, "mouth": 1.0})
	check(absf(person.body.position.y-rest_hip-.025) < .0001, identity + " animation bob preserves hip baseline")
	check(absf(person.legs[0].rotation.x-.4) < .0001 and absf(person.legs[1].rotation.x+.4) < .0001, identity + " walk leg pivots animate")
	check(is_equal_approx(person.mouth.scale.y, 1.0), identity + " mouth opens")
	check(person.hand_pos(0).is_finite() and person.hand_pos(1).is_finite(), identity + " hand world positions finite")
	person.pose({"armR": [-2.45, .42], "armL": [-2.45, .42], "look": -.2})
	check(absf(person.arms[0].rotation.x+2.45) < .0001, identity + " binocular arm pose available")
	for prop in prop_locals:
		var node := Assets.find(person.g, str(prop))
		check(node.transform.is_equal_approx(prop_locals[prop]), identity + " accessory remains attached during pose " + str(prop))
	if identity == "baby":
		person.pose({"armR": [-1.2, .05], "armL": [-1.2, .05], "nod": -1.0})
		person.g.rotation.x = 1.15
		check(person.head.global_transform.origin.is_finite(), "Baby crawl hierarchy remains finite")
		person.g.rotation.x = 0.0
	if identity == "dad":
		person.g.rotation.x = -PI / 2.0
		check(person.head.global_transform.origin.is_finite(), "Dad hammock hierarchy remains finite")
		person.g.rotation.x = 0.0
	person.pose({})
	check(absf(person.body.position.y-rest_hip) < .0001 and is_equal_approx(person.mouth.scale.y, .3), identity + " rest pose restores hip and closed mouth")
	measurements[identity] = {"nominal_height": person.H, "aabb_min": _v(bounds.position), "aabb_size": _v(bounds.size),
		"triangles": stats.triangles, "surfaces": stats.surfaces, "meshes": stats.meshes,
		"hip_y": rest_hip, "head_center_y": person.hy, "head_radius": person.hs}
	print("[legacy_cast_quality] %s H=%.3f actual=%.3f width=%.3f tris=%d surfaces=%d" % [identity, person.H, bounds.size.y, bounds.size.x, stats.triangles, stats.surfaces])
	person.g.free()

func _collect(node: Node, inverse: Transform3D, stats: Dictionary) -> void:
	if node is MeshInstance3D and node.mesh != null:
		stats.meshes += 1
		stats.surfaces += node.mesh.get_surface_count()
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices = arrays[Mesh.ARRAY_INDEX]
			stats.triangles += (indices.size() if indices != null and indices.size() > 0 else vertices.size()) / 3
			if node.is_visible_in_tree():
				var transform: Transform3D = inverse * node.global_transform
				for point in vertices:
					stats.points.append(transform * point)
	for child in node.get_children():
		_collect(child, inverse, stats)

func _bounds(points: Array) -> AABB:
	if points.is_empty():
		return AABB()
	var result := AABB(points[0], Vector3.ZERO)
	for point in points:
		result = result.expand(point)
	return result

func _v(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _actual_bounds(node: Node3D) -> AABB:
	var stats := {"points": [], "triangles": 0, "surfaces": 0, "meshes": 0}
	_collect(node, Transform3D.IDENTITY, stats)
	return _bounds(stats.points)

func _check_contact_poses() -> void:
	var infant := Cast.person("baby", self)
	var crawl_rows: Array[Dictionary] = []
	infant.g.position = Vector3(1, .16, 2)
	infant.g.rotation.y = .45
	for phase in 4:
		infant.crawl(float(phase) * PI / 2.0, .16)
		var heights: Array[float] = []
		for limb in infant.arms + infant.legs:
			heights.append(_actual_bounds(limb).position.y - .16)
		check(absf(minf(heights[0], heights[1])) < .003, "Baby crawl plants a real hand at phase %d" % phase)
		check(absf(minf(heights[2], heights[3])) < .003, "Baby crawl plants a real foot at phase %d" % phase)
		check(heights.min() >= -.003 and _actual_bounds(infant.head).position.y > .20, "Baby crawl limbs/head stay above ground at phase %d" % phase)
		crawl_rows.append({"phase": phase, "hand_foot_heights_above_ground": heights, "root_y": infant.g.position.y, "torso_lean": infant.body.rotation.x})
	pose_measurements["baby_crawl"] = crawl_rows
	infant.g.free()
	var child := Cast.person("timmy", self)
	var lane_gaps: Array[float] = []
	for phase in 4:
		child.phase = float(phase) * PI / 2.0
		child.pose({"walk": .42})
		var right := _actual_bounds(child.legs[0])
		var left := _actual_bounds(child.legs[1])
		var gap := left.position.x - right.end.x
		lane_gaps.append(gap)
		check(gap > .03, "Timmy entire leg meshes have separate X lanes at phase %d" % phase)
		check(is_zero_approx(child.legs[0].rotation.y) and is_zero_approx(child.legs[0].rotation.z), "Timmy leg swing has no sideways/yaw component")
	pose_measurements["timmy_leg_lane_gaps_m"] = lane_gaps
	child.g.free()
	var player := Cast.person("two_pack", self)
	player.pose_binoculars()
	var grips: Array[float] = []
	for i in 2:
		var gap := player.hand_pos(i).distance_to(player.binocular_grip_pos(i))
		grips.append(gap)
		check(gap < .001, "Two-Pack hand %d meets actual binocular grip" % i)
	player.pose({"walk": .4})
	check(player.arms[0].scale.is_equal_approx(Vector3.ONE) and player.arms[1].scale.is_equal_approx(Vector3.ONE), "Accessory contact arm scales reset for normal walking")
	pose_measurements["binocular_hand_grip_gaps_m"] = grips
	player.g.free()
