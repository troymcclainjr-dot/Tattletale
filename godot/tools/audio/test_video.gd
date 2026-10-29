extends SceneTree
## Checks that Godot loads the converted music video as a VideoStreamTheora and plays it, picture and
## sound. Headless is fine:
##   python godot/tools/godot_run.py --timeout 60 -- --headless --audio-driver Dummy --script res://tools/audio/test_video.gd
## (The headless renderer keeps no pixels, so colors can only be checked in a real window; see
## convert_video.py for why the file is coded as BT.601.)

const PATH := "res://assets/video/still_there.ogv"

var fails := 0


func check(ok: bool, what: String) -> void:
	print("  ok    " if ok else "  FAIL  ", what)
	if not ok:
		fails += 1


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var vs = load(PATH)
	check(vs != null and vs is VideoStreamTheora, "load(\"%s\") is a VideoStreamTheora (class %s)" % [PATH, vs.get_class() if vs else "null"])
	if vs == null:
		quit(1)
		return
	print("  file  ", vs.file)

	var cap := AudioEffectCapture.new()
	cap.buffer_length = 1.0
	AudioServer.add_bus_effect(0, cap)  # the video plays on Master

	var player := VideoStreamPlayer.new()
	player.stream = vs
	root.add_child(player)
	await process_frame
	player.play()
	var peak := 0.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 3000:
		await process_frame
		var n := cap.get_frames_available()
		if n > 0:
			for f in cap.get_buffer(n):
				peak = maxf(peak, maxf(absf(f.x), absf(f.y)))
	check(player.is_playing(), "plays")
	check(player.get_stream_position() > 2.0, "position advances with real time (%.2f s after 3 s)" % player.get_stream_position())
	var tex := player.get_video_texture()
	check(tex != null and tex.get_size() == Vector2(854, 480), "video texture is 854x480 (%s)" % [tex.get_size() if tex else "none"])
	check(peak > 0.02, "the Vorbis track plays (Master peak %.3f in the first 3 s; ffmpeg measures about 0.1)" % peak)
	check(absf(player.get_stream_length() - 192.0) < 0.5, "length is 192 s (%.2f)" % player.get_stream_length())

	player.stop()
	player.queue_free()
	await process_frame
	print("RESULT: ", "ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails else 0)
