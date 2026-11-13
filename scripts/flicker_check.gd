extends RefCounted
## Finds box faces that lie exactly on top of one another: two surfaces in one
## place, facing the same way, in different materials. The renderer cannot tell
## which is in front, so the patch flickers as the camera moves.
##
##   python popup/tools/shot.py out.png --check-faces
##
## Only upright, unturned boxes that are on show are looked at (turned props do
## not line up with anything), and only the faces the game camera can see: it
## looks from the street side, from the right and from above, so those are the
## faces that point to +x, +y or +z. The fix is to move one of the two a
## centimetre.

const TOLERANCE := 0.0005     # metres: closer than this is the same plane
const MIN_AREA := 0.0004      # square metres of overlap worth reporting (2 cm x 2 cm)


static func find(root: Node) -> Array:
	var buckets := {}          # "axis sign plane": [face, ...]
	_collect(root, buckets)
	var out: Array = []
	for key: String in buckets:
		var faces: Array = buckets[key]
		for i in faces.size():
			for j in range(i + 1, faces.size()):
				var a: Dictionary = faces[i]
				var b: Dictionary = faces[j]
				if a["look"] == b["look"]:
					continue
				var both: Rect2 = (a["rect"] as Rect2).intersection(b["rect"])
				if both.get_area() < MIN_AREA:
					continue
				out.append("%s  |  %s  on %s = %.3f, %.0f x %.0f cm" % [a["name"], b["name"], key.get_slice(" ", 0) + key.get_slice(" ", 1), a["plane"], both.size.x * 100.0, both.size.y * 100.0])
	return out


static func _collect(node: Node, buckets: Dictionary) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and child.mesh is BoxMesh and child.is_visible_in_tree():
			_add_faces(child, buckets)
		_collect(child, buckets)


static func _add_faces(box: MeshInstance3D, buckets: Dictionary) -> void:
	var xf := box.global_transform
	for i in 3:        # each side of the box must run along one of the world's axes
		var v := xf.basis[i].normalized().abs()
		if maxf(v.x, maxf(v.y, v.z)) < 0.99999:
			return
	var half := (box.mesh as BoxMesh).size * 0.5
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var p := xf * Vector3(half.x * sx, half.y * sy, half.z * sz)
				lo = lo.min(p)
				hi = hi.max(p)
	var path := str(box.get_path()).trim_prefix("/root/")
	for axis in 3:
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		var rect := Rect2(lo[u], lo[v], hi[u] - lo[u], hi[v] - lo[v])
		for side in [1]:       # the +x, +y and +z faces; 0 would be the far sides
			var plane: float = hi[axis] if side == 1 else lo[axis]
			# Faces within the tolerance of each other land in the same or the next bucket: file under both.
			for slot in [floori(plane / TOLERANCE), floori(plane / TOLERANCE) + 1]:
				var key := "%s %s %d" % ["xyz"[axis], "+" if side == 1 else "-", slot]
				if not buckets.has(key):
					buckets[key] = []
				buckets[key].append({"name": path, "rect": rect, "plane": plane, "look": box.material_override})
