extends SceneTree
## Prints the rig contract nodes of every character GLB (positions relative to Rig, mouth scale,
## accessories) so contract drift shows up early.
##   python godot/tools/godot_run.py -- --headless --script res://tools/rig_check.gd

const IDS := ["two_pack", "ricky", "granny", "gary", "timmy", "mailman", "cop_dan", "cop_steve", "mama", "dad", "vendor", "liner_1", "liner_2", "liner_3", "liner_4", "baby"]
const H := {"two_pack": 1.8, "ricky": 1.76, "granny": 1.5, "gary": 1.72, "timmy": 0.95, "mailman": 1.75, "cop_dan": 1.8, "cop_steve": 1.88, "mama": 1.68, "dad": 1.8, "vendor": 1.78, "liner_1": 1.7, "liner_2": 1.85, "liner_3": 1.6, "liner_4": 1.78, "baby": 0.55}
const EXTRA := {"two_pack": ["Binoculars", "Cup"], "cop_dan": ["Donut"], "cop_steve": ["Donut"], "mailman": ["Letter"], "gary": ["Pipe", "Ember"]}


func _initialize() -> void:
	for id in IDS:
		var p := "res://assets/models/characters/%s.glb" % id
		if not ResourceLoader.exists(p):
			print("%-10s (no glb yet)" % id)
			continue
		var n: Node = load(p).instantiate()
		var rig: Node3D = n.find_child("Rig", true, false)
		var h: float = H[id]
		var line := "%-10s " % id
		if rig == null:
			print(line, "NO Rig")
			n.free()
			continue
		for nm in ["LegR", "LegL", "Body", "ArmR", "ArmL", "HandR", "HandL", "Head", "Mouth"]:
			var nd: Node3D = n.find_child(nm, true, false)
			if nd == null:
				line += "%s:MISSING " % nm
				continue
			line += "%s(%.3f,%.3f,%.3f)H " % [nm, nd.position.x / h, nd.position.y / h, nd.position.z / h]
		var m: Node3D = n.find_child("Mouth", true, false)
		if m:
			line += "mouth_scale=%s rot=%s " % [m.scale, n.find_child("Body", true, false).rotation]
		for e in EXTRA.get(id, []):
			var nd: Node3D = n.find_child(e, true, false)
			line += "%s:%s(parent %s, vis %s) " % [e, "ok" if nd else "MISSING", nd.get_parent().name if nd else "-", nd.visible if nd else "-"]
		print(line)
		n.free()
	quit()
