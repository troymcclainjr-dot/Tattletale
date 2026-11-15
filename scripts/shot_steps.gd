extends RefCounted
## More --do steps for a screenshot run (tools/shot.py), so that one run can
## take many pictures from anywhere, in more than one place:
##
##   snap:name                 save a picture now, beside the --shot file, as name.png, and carry on
##   eye:x:y:z:x:y:z[:fov]     from now on the pictures are taken from the first point, looking at the
##                             second (fov in degrees, 50 if left out); eye: alone goes back to the
##                             camera that follows him
##   place:id                  go to that place at once (as the travel list does, with no fade)
##   at:x:z                    stand him there, without walking
##   room:NAME                 stand him in the middle of the room of that name (BAR, BACK_ROOM)
##   beat:n                    everyone here who is dancing holds the dance at beat n (a beat is a step)
##   stats                     print what drawing the picture costs: draw calls, objects, milliseconds a frame
##   check                     --check-walk and --check-faces for the place he is in now (it opens its doors)
##
## main.gd's _take_shot hands these here.

const FlickerCheck := preload("res://scripts/flicker_check.gd")

static var _fov := 50.0


static func step(main: Node, bits: PackedStringArray) -> void:
	match bits[0]:
		"snap":
			await _snap(main, bits[1] if bits.size() > 1 and bits[1] != "" else "snap")
		"eye":
			if bits.size() < 7:
				main._shot_eye = PackedFloat64Array()
			else:
				main._shot_eye = PackedFloat64Array([float(bits[1]), float(bits[2]), float(bits[3]), float(bits[4]), float(bits[5]), float(bits[6])])
				_fov = float(bits[7]) if bits.size() > 7 else 50.0
		"place":
			main._travel_to(bits[1], true)
			print("[shot] place: %s, at %.2f, %.2f" % [main._place, main._actor.position.x, main._actor.position.z])
		"at":
			_stand(main, Vector3(float(bits[1]), 0.0, float(bits[2])))
		"room":
			_stand(main, main._spot_in_room(bits[1]))
		"beat":
			var held := 0
			for member: Dictionary in main._cast.get(main._place, []):
				var npc: Node3D = member["actor"]
				if npc.performing:
					npc._beat = float(bits[1])
					npc._groove = 1.0                                 # in full swing: a shot run has had no frames to get going
					npc.walk(Vector2.ZERO, Vector2.ZERO, 0.0)        # pose him at that beat now (a snap stops the clock)
					held += 1
			print("[shot] beat %s: %d dancing" % [bits[1], held])
		"stats":
			main.set_process(false)
			if main._cam_name == "follow":
				main._follow(0.0, true)
			var vsync := DisplayServer.window_get_vsync_mode()
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)    # time the drawing, not the screen's refresh
			for i in 20:
				await main.get_tree().process_frame
			var from := Time.get_ticks_usec()
			for i in 120:
				await main.get_tree().process_frame
			var ms := (Time.get_ticks_usec() - from) / 120000.0
			DisplayServer.window_set_vsync_mode(vsync)
			var meshes: int = main._building.find_children("*", "MeshInstance3D", true, false).size()
			print("[shot] stats: %s: %d draw calls, %d objects in the picture, %d meshes in the place, %.1f ms a frame" % [main._place,
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), meshes, ms])
			main.set_process(true)
		"check":
			print("[shot] check: %s" % main._place)
			main._check_walk()
			main._building.show_room(0)
			var seen := {}
			for line: String in FlickerCheck.find(main._building):
				if not seen.has(line):
					seen[line] = true
					print("[shot] faces: ", line)
			print("[shot] faces: %d overlapping pairs" % seen.size())
			main._building.show_room(main._room)


static func _stand(main: Node, at: Vector3) -> void:
	main._actor.position = at
	main._actor.areas = main._building.walk_areas()
	main._change_room(main._building.room_at_pos(at, main._room), true)
	print("[shot] at %.2f, %.2f, in the %s" % [at.x, at.z, main._building.rooms[main._room]["name"]])


## As the end of _take_shot does, without quitting: the camera to its place, a few frames, the picture.
static func _snap(main: Node, name: String) -> void:
	main.set_process(false)
	main._fade.color.a = 0.0                  # (as _take_shot does: a fade from a door or a trip may still be up)
	main._change_room(main._building.room_at_pos(main._actor.position, main._room), true)
	if main._close:
		main._frame_close()
	elif main._cam_name == "follow":
		main._follow(0.0, true)
	main._show_doors()
	var eye: PackedFloat64Array = main._shot_eye
	if eye.size() == 6:
		main._camera.fov = _fov
		main._camera.look_at_from_position(Vector3(eye[0], eye[1], eye[2]), Vector3(eye[3], eye[4], eye[5]))
		main._face_cards()
	main._find_nearest()
	for i in 12:
		await main.get_tree().process_frame
	await RenderingServer.frame_post_draw
	main._save_frame(String(main._shot_path).get_base_dir().path_join(name + ".png"))
	main.set_process(true)
