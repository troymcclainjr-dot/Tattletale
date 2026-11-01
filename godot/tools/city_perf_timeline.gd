extends RefCounted
## Splits each main-loop cycle into engine phases from microsecond timestamps.
## A cycle runs from one SceneTree.process_frame emission to the next:
##   process_frame -> driver bookkeeping -> first _process -> last _process ->
##   frame_pre_draw -> frame_post_draw -> tail (audio, frame delay, next
##   iteration's physics sync/flush) -> per physics tick: physics_frame ->
##   first _physics_process -> last _physics_process -> engine (timers,
##   deferred calls, transform flush, navigation, PhysicsServer step) -> next.
## Callers pass timestamps, so fixtures replay synthetic sequences exactly.
## Phases telescope: their sum equals the cycle unless events arrive out of
## order, in which case the residue is reported as unattributed_ms.

const COLUMNS: Array[String] = ["cycle_ms", "driver_ms", "process_pre_ms", "process_scripts_ms",
	"process_post_ms", "render_ms", "tail_ms", "physics_ticks", "physics_pre_ms", "physics_scripts_ms",
	"physics_engine_ms", "unattributed_ms"]

var recording := false
var anomalies := 0
var cycle_ms := PackedFloat64Array()
var driver_ms := PackedFloat64Array()
var process_pre_ms := PackedFloat64Array()
var process_scripts_ms := PackedFloat64Array()
var process_post_ms := PackedFloat64Array()
var render_ms := PackedFloat64Array()
var tail_ms := PackedFloat64Array()
var physics_ticks := PackedFloat64Array()
var physics_pre_ms := PackedFloat64Array()
var physics_scripts_ms := PackedFloat64Array()
var physics_engine_ms := PackedFloat64Array()
var unattributed_ms := PackedFloat64Array()
## One entry per physics tick: script time, engine time and its cycle index.
var tick_scripts_ms := PackedFloat64Array()
var tick_engine_ms := PackedFloat64Array()
var tick_pre_ms := PackedFloat64Array()
var tick_cycle := PackedInt32Array()

var _cycle_start := -1
var _driver_done := -1
var _process_begin := -1
var _process_end := -1
var _draw_begin := -1
var _draw_end := -1
var _first_tick := -1
var _tick_signal := -1
var _tick_begin := -1
var _tick_end := -1
var _tick_pre := 0
var _tick_scripts := 0
var _ticks := 0
var _physics_pre := 0
var _physics_scripts := 0
var _physics_engine := 0

## Begin recording at a process_frame boundary; earlier partial data is dropped.
func start(now: int) -> void:
	for key in COLUMNS:
		set(key, PackedFloat64Array())
	tick_scripts_ms = PackedFloat64Array()
	tick_engine_ms = PackedFloat64Array()
	tick_pre_ms = PackedFloat64Array()
	tick_cycle = PackedInt32Array()
	anomalies = 0
	recording = true
	_open_cycle(now)

func stop() -> void:
	recording = false

func cycles() -> int:
	return cycle_ms.size()

func column(name: String) -> PackedFloat64Array:
	return get(name) as PackedFloat64Array

func physics_frame(now: int) -> void:
	if not recording:
		return
	if _tick_end >= 0:
		_close_tick(now)
	elif _tick_signal >= 0:
		# A tick never reached its last _physics_process (removed or paused
		# mark); its whole span stays in this cycle as engine time.
		anomalies += 1
		_physics_engine += now - _tick_signal
	_tick_signal = now
	_tick_begin = -1
	if _first_tick < 0:
		_first_tick = now

func physics_begin(now: int) -> void:
	if not recording:
		return
	if _tick_signal < 0:
		anomalies += 1
		_tick_signal = now
		if _first_tick < 0:
			_first_tick = now
	_tick_begin = now

func physics_end(now: int) -> void:
	if not recording:
		return
	if _tick_begin < 0:
		anomalies += 1
		return
	_tick_pre = _tick_begin - _tick_signal
	_tick_scripts = now - _tick_begin
	_physics_pre += _tick_pre
	_physics_scripts += _tick_scripts
	_ticks += 1
	_tick_end = now
	_tick_begin = -1

func driver_done(now: int) -> void:
	if recording:
		_driver_done = now

func process_begin(now: int) -> void:
	if recording and _process_begin < 0:
		_process_begin = now

func process_end(now: int) -> void:
	if recording:
		_process_end = now

func draw_begin(now: int) -> void:
	if recording and _draw_begin < 0:
		_draw_begin = now

func draw_end(now: int) -> void:
	if recording:
		_draw_end = now

## Close the cycle opened at the previous process_frame; returns false when
## nothing was recorded (not recording yet).
func process_frame(now: int) -> bool:
	if not recording or _cycle_start < 0:
		_open_cycle(now)
		return false
	if _tick_end >= 0:
		_close_tick(now)
	elif _tick_signal >= 0:
		anomalies += 1
		_physics_engine += now - _tick_signal
	var t0 := _cycle_start
	var t_driver := _clamp_after(_driver_done, t0)
	var t_begin := _clamp_after(_process_begin, t_driver)
	var t_end := _clamp_after(_process_end, t_begin)
	var t_draw := _clamp_after(_draw_begin, t_end)
	var t_drawn := _clamp_after(_draw_end, t_draw)
	var tail_end := now
	if _first_tick >= 0:
		if _first_tick < t_drawn:
			anomalies += 1
		tail_end = maxi(_first_tick, t_drawn)
	var physics_total := _physics_pre + _physics_scripts + _physics_engine
	var cycle := now - t0
	var attributed := (t_drawn - t0) + (tail_end - t_drawn) + physics_total
	cycle_ms.append(cycle / 1000.0)
	driver_ms.append((t_driver - t0) / 1000.0)
	process_pre_ms.append((t_begin - t_driver) / 1000.0)
	process_scripts_ms.append((t_end - t_begin) / 1000.0)
	process_post_ms.append((t_draw - t_end) / 1000.0)
	render_ms.append((t_drawn - t_draw) / 1000.0)
	tail_ms.append((tail_end - t_drawn) / 1000.0)
	physics_ticks.append(float(_ticks))
	physics_pre_ms.append(_physics_pre / 1000.0)
	physics_scripts_ms.append(_physics_scripts / 1000.0)
	physics_engine_ms.append(_physics_engine / 1000.0)
	unattributed_ms.append((cycle - attributed) / 1000.0)
	_open_cycle(now)
	return true

## Every finished cycle as one row, in COLUMNS order.
func row(index: int) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	for key in COLUMNS:
		result.append(column(key)[index])
	return result

func _clamp_after(stamp: int, floor_stamp: int) -> int:
	if stamp < 0:
		return floor_stamp
	if stamp < floor_stamp:
		anomalies += 1
		return floor_stamp
	return stamp

func _close_tick(next_event: int) -> void:
	var engine := maxi(0, next_event - _tick_end)
	_physics_engine += engine
	tick_pre_ms.append(_tick_pre / 1000.0)
	tick_scripts_ms.append(_tick_scripts / 1000.0)
	tick_engine_ms.append(engine / 1000.0)
	tick_cycle.append(cycle_ms.size())
	_tick_end = -1
	_tick_signal = -1
	_tick_begin = -1

func _open_cycle(now: int) -> void:
	_cycle_start = now
	_driver_done = -1
	_process_begin = -1
	_process_end = -1
	_draw_begin = -1
	_draw_end = -1
	_first_tick = -1
	_tick_signal = -1
	_tick_begin = -1
	_tick_end = -1
	_ticks = 0
	_physics_pre = 0
	_physics_scripts = 0
	_physics_engine = 0
