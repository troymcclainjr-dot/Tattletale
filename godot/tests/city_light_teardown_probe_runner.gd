extends "res://tests/city_priorities_session_fixture.gd"
## Short diagnostic, NOT a sustained-performance acceptance run. The root owns
## renderer execution. Log markers attribute errors to a single light operation.
var probe_finishing := false

func _watchdog() -> void:
	await get_tree().create_timer(240.0, true, false, true).timeout
	if not finished:
		check(false, "light teardown probe watchdog")
		_finish()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "light teardown diagnosis requires real renderer")
		_finish()
		return
	if not await boot_world():
		_finish()
		return
	var mode := option("--teardown-mode", "lights")
	check(mode in ["lights", "reindex", "menu", "menu-reindex", "world"], "known teardown diagnostic mode")
	if failures > 0:
		_finish()
		return
	# Exercise streetlight-pool relocation, daylight changes and streamed cells.
	# Normal simulation remains active throughout this setup.
	for index in 4:
		var location := 0 if index % 2 == 0 else 4
		level.world_time.set_time(600.0 if index < 2 else 1260.0)
		begin_phase("lighting_%s" % location)
		_set_scenario_position(level.vector(level.level_data.landmarks[location].position))
		await get_tree().create_timer(3.0, true, false, true).timeout
	var lights: Array[Node] = level.find_children("*", "Light3D", true, false)
	var inventory: Array[Dictionary] = []
	for node in lights:
		var lamp := node as Light3D
		inventory.append({"path": str(lamp.get_path()), "class": lamp.get_class(), "visible": lamp.visible,
			"energy": lamp.light_energy, "shadow": lamp.shadow_enabled,
			"position": lamp.global_position, "sky_mode": lamp.sky_mode if lamp is DirectionalLight3D else -1})
	print("[light_teardown] INVENTORY " + JSON.stringify(inventory))
	result_details["light_probe"] = {"mode": mode, "inventory": inventory,
		"note": "Engine errors are diagnosed from BEFORE/AFTER markers, never suppressed."}
	if mode in ["menu", "menu-reindex"]:
		if mode == "menu-reindex":
			level.process_mode = Node.PROCESS_MODE_DISABLED
			for node in lights:
				if is_instance_valid(node) and not (node as Light3D).visible:
					print("[light_teardown] BEFORE_REINDEX " + str(node.get_path()))
					(node as Light3D).show()
					await RenderingServer.frame_post_draw
					(node as Light3D).hide()
					await RenderingServer.frame_post_draw
					print("[light_teardown] AFTER_REINDEX " + str(node.get_path()))
		print("[light_teardown] BEFORE_PRODUCTION_MENU_EXIT")
		var music := get_node_or_null("/root/Audio/Music") as AudioStreamPlayer
		var music_was_playing := is_instance_valid(music) and music.playing
		level._finish_exit(true)
		for frame in 120:
			await get_tree().process_frame
			if not is_instance_valid(level) and get_tree().current_scene != null:
				break
		check(not is_instance_valid(level), "production menu transition released city")
		check(get_tree().current_scene != null and get_tree().current_scene.scene_file_path == "res://scenes/main.tscn", "production original-block destination loaded")
		check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and _window_off_desktop(), "menu transition preserves offscreen pointer safety")
		check(music_was_playing and is_instance_valid(music) and music.playing, "production menu transition preserves autoload music playback")
		print("[light_teardown] AFTER_PRODUCTION_MENU_EXIT")
	else:
		level.process_mode = Node.PROCESS_MODE_DISABLED
		if mode in ["lights", "reindex"]:
			for node in lights:
				if not is_instance_valid(node):
					continue
				var label := str(node.get_path())
				if mode == "reindex" and not (node as Light3D).visible:
					print("[light_teardown] BEFORE_REINDEX " + label)
					(node as Light3D).show()
					await RenderingServer.frame_post_draw
					print("[light_teardown] AFTER_REINDEX " + label)
				print("[light_teardown] BEFORE_HIDE " + label)
				(node as Light3D).hide()
				await RenderingServer.frame_post_draw
				print("[light_teardown] BEFORE_FREE " + label)
				node.queue_free()
				await get_tree().process_frame
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
				print("[light_teardown] AFTER_FREE " + label)
		print("[light_teardown] BEFORE_WORLD_FREE")
		level.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		check(not is_instance_valid(level), "world released in diagnostic")
		print("[light_teardown] AFTER_WORLD_FREE")
	_finish()

func _finish() -> void:
	if probe_finishing or finished:
		return
	probe_finishing = true
	sampling = false
	for action in ["move_forward", "move_back", "move_left", "move_right", "run"]:
		if InputMap.has_action(action):
			Input.action_release(action)
	# This occurs after the production menu transition and its assertions. Music
	# remains normal during that transition; only fixture shutdown stops it.
	var stopped := 0
	for kind in ["AudioStreamPlayer", "AudioStreamPlayer2D", "AudioStreamPlayer3D"]:
		for audio_player in get_tree().root.find_children("*", kind, true, false):
			audio_player.stop()
			stopped += 1
	await get_tree().create_timer(0.1, true, false, true).timeout
	result_details["audio_drain"] = {"version": 3, "players_stopped": stopped, "minimum_seconds": 0.1}
	super._finish()
