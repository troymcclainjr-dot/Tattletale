extends Node
## The song system's studio half (main.gd's `_songs`): the NOTEBOOK on the yellow pad on the control room's
## coffee table, where he writes a song (song_notebook.gd), and the booth mic, where a written song waiting
## is sung instead of the freestyle (song_take.gd). The sheet is song_sheet.gd's, the score song_score.gd's,
## what it does to the music video song_video.gd's; every word and number is assets/data/songs.json's.
##
## main.gd's hooks (each marked `# notebook:`): the preloads, `_songs`, setup() after the video's,
## take_mic() in _start_perform (false: the booth as it was), face_is_mine() in _perform_cam (his face is the
## take's while it runs), the song: --do steps (song_steps.gd). video_shoot.gd asks at_mic() (the booth's own
## REC and sixteen-beat count stand aside) and freestyle_sheet() (a song recorded with nothing written).

const UsePoint := preload("res://scripts/use_point.gd")
const Notebook := preload("res://scripts/song_notebook.gd")
const Take := preload("res://scripts/song_take.gd")
const Sheet := preload("res://scripts/song_sheet.gd")
const Score := preload("res://scripts/song_score.gd")
const PAD := Vector3(1.94, 0.0, 0.17)      # the yellow legal pad on the coffee table (studio_set.gd's table group at 2.05, 0.55)

var main: Node
var notebook: CanvasLayer
var take: CanvasLayer
var point: Node3D             # E at the pad
var auto := -1.0              # a --do step's player for the next take (song:auto)
var seed_value := 1

var _turn := false            # this turn at the mic began with a written song


func setup(main_node: Node) -> void:
	main = main_node
	notebook = Notebook.new()
	notebook.name = "Notebook"
	add_child(notebook)
	notebook.setup(main)
	notebook.closed.connect(_on_closed)
	take = Take.new()
	take.name = "SongTake"
	add_child(take)
	take.setup(main)
	take.finished.connect(_on_take_done)
	var studio: Node3D = main._site("studio")
	point = UsePoint.new()
	point.name = "NotebookPad"
	point.id = "notebook"
	point.label = Score.word("use")
	point.use_reach = 1.0
	point.label_height = 0.85
	point.position = PAD
	studio.control.add_child(point)
	studio.use_points.append(point)
	point.used.connect(_on_pad)
	if main._building == studio and not main._usables.has(point):
		main._usables.append(point)


## E at the pad.
func _on_pad(_id: String, _by: Node3D) -> void:
	if main._mode != "play" or main._performing:
		return
	open_notebook()


func open_notebook() -> void:
	main._set_mode("notebook")
	notebook.open()
	print("[use] notebook: open (%d songs waiting at the mic)" % (main._state.song_written as Array).size())


func _on_closed() -> void:
	main._set_mode("play")
	main._save_game()


## main.gd _start_perform: with a written song waiting he sings it (true); else false, and the booth is as it was.
func take_mic() -> bool:
	var waiting: Array = main._state.song_written
	if waiting.is_empty() or typeof(waiting[0]) != TYPE_DICTIONARY:
		return false
	take.auto = auto
	take.seed_value = seed_value
	_turn = take.start(waiting[0])
	return _turn


## This turn at the mic is a written song's (the take, its score, or stepping away after either): video_shoot.gd's
## REC and sixteen-beat count stand aside, or a stopped take would be counted as a freestyle.
func at_mic() -> bool:
	if not main._performing:
		_turn = false
	return take != null and (take.showing() or _turn)


## His face is the take's while it runs (main.gd's _perform_cam leaves it be).
func face_is_mine() -> bool:
	return at_mic()


## The sheet of a song recorded with nothing written: its beat, the day, a fixed low score (video_shoot.gd).
func freestyle_sheet() -> Dictionary:
	return Sheet.freestyle(String(main._conductor.id), int(main._day) + 1, Score.freestyle())


func _on_take_done(_recorded: bool) -> void:
	main._stop_perform()
