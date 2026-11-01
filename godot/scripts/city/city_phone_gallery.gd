extends RefCounted
## Private game storage. No export, clipboard or OS shell integration.
const DIRECTORY := "user://phone_gallery"
const LIMIT := 48
const MAX_EDGE := 1280
const MAX_FILE_BYTES := 8 * 1024 * 1024
var directory := DIRECTORY
var entries: Array[Dictionary] = []

func valid_directory() -> bool:
	return directory == DIRECTORY or (directory.begins_with("user://phone_gallery_test_") and "/" not in directory.trim_prefix("user://") and "\\" not in directory)

func reload() -> void:
	entries.clear()
	if not valid_directory() or not DirAccess.dir_exists_absolute(directory):
		return
	var names := DirAccess.get_files_at(directory)
	names.sort()
	for index in range(names.size() - 1, -1, -1):
		var filename: String = names[index]
		if not filename.begins_with("photo_") or not filename.ends_with(".json"):
			continue
		var file := FileAccess.open(directory.path_join(filename), FileAccess.READ)
		if file == null or file.get_length() > 16384:
			continue
		var decoded = JSON.parse_string(file.get_as_text())
		file.close()
		if not decoded is Dictionary:
			continue
		var id := filename.get_basename()
		var png := directory.path_join(id + ".png")
		if not FileAccess.file_exists(png):
			continue
		entries.append({"id": id, "filename": id + ".png", "image_path": png,
			"metadata_path": directory.path_join(filename), "metadata": decoded})
		if entries.size() >= LIMIT:
			break

func store(photo: Image, metadata: Dictionary) -> Dictionary:
	if not valid_directory():
		return {"ok": false, "reason": "Phone storage is unavailable."}
	if photo == null or photo.is_empty():
		return {"ok": false, "reason": "Photo unavailable; nothing was saved."}
	reload()
	if entries.size() >= LIMIT:
		return {"ok": false, "reason": "Phone gallery is full. Delete a photo to make room."}
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return {"ok": false, "reason": "Could not save to the phone gallery."}
	var image: Image = photo.duplicate()
	var scale := minf(1.0, float(MAX_EDGE) / maxf(image.get_width(), image.get_height()))
	if scale < 1.0:
		image.resize(maxi(1, roundi(image.get_width() * scale)), maxi(1, roundi(image.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
	var id := "photo_%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	while FileAccess.file_exists(directory.path_join(id + ".png")) or FileAccess.file_exists(directory.path_join(id + ".json")):
		id += "_new"
	var png := directory.path_join(id + ".png")
	var json := directory.path_join(id + ".json")
	if image.save_png(png + ".tmp") != OK:
		_remove_if_present(png + ".tmp")
		return {"ok": false, "reason": "Could not save photo; previous photos retained."}
	var details := metadata.duplicate(true)
	details["width"] = image.get_width()
	details["height"] = image.get_height()
	var file := FileAccess.open(json + ".tmp", FileAccess.WRITE)
	if file == null:
		_remove_if_present(png + ".tmp")
		return {"ok": false, "reason": "Could not save photo details."}
	file.store_string(JSON.stringify(details))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(png + ".tmp", png) != OK:
		_remove_if_present(png + ".tmp")
		_remove_if_present(json + ".tmp")
		return {"ok": false, "reason": "Photo save failed; previous photos retained."}
	if DirAccess.rename_absolute(json + ".tmp", json) != OK:
		_remove_if_present(png)
		_remove_if_present(json + ".tmp")
		return {"ok": false, "reason": "Photo details save failed; previous photos retained."}
	reload()
	return {"ok": true, "id": id, "filename": id + ".png", "image_path": png,
		"metadata_path": json, "width": image.get_width(), "height": image.get_height()}

func load_image(id: String) -> Image:
	if not valid_directory():
		return null
	for entry in entries:
		if str(entry.id) != id:
			continue
		var file := FileAccess.open(str(entry.image_path), FileAccess.READ)
		if file == null or file.get_length() > MAX_FILE_BYTES:
			return null
		file.close()
		return Image.load_from_file(str(entry.image_path))
	return null

func remove(id: String) -> bool:
	if not valid_directory():
		return false
	for entry in entries:
		if str(entry.id) == id:
			if DirAccess.remove_absolute(str(entry.image_path)) != OK:
				return false
			_remove_if_present(str(entry.metadata_path))
			reload()
			return true
	return false

func _remove_if_present(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
