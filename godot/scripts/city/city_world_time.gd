extends Node
## One unpaused clock for residents, daylight and animation. 48 real minutes/day.
var total_minutes := 540.0
var elapsed_seconds := 0.0
var minutes_per_second := 0.5
var frozen := false
var minute_of_day: float:
	get: return fposmod(total_minutes, 1440.0)
var day_index: int:
	get: return floori(total_minutes / 1440.0)

func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	elapsed_seconds += delta
	if not frozen:
		total_minutes += delta * minutes_per_second

func set_time(minutes: float, day: int = 0) -> void:
	total_minutes = maxf(0.0, float(day) * 1440.0 + minutes)

func get_status() -> Dictionary:
	var whole := floori(minute_of_day)
	return {"minute_of_day": minute_of_day, "day_index": day_index, "total_minutes": total_minutes,
		"elapsed_seconds": elapsed_seconds, "label": "DAY %d  ·  %02d:%02d" % [day_index + 1, whole / 60, whole % 60]}
