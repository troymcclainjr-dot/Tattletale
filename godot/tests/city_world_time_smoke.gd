extends SceneTree
const Clock := preload("res://scripts/city/city_world_time.gd")
func _initialize() -> void:
	var clock := Clock.new()
	assert(is_equal_approx(clock.minute_of_day, 540.0))
	clock.tick(120.0)
	assert(is_equal_approx(clock.minute_of_day, 600.0))
	clock.set_time(1439.5, 3)
	clock.tick(1.0)
	assert(clock.day_index == 4 and is_zero_approx(clock.minute_of_day))
	assert(clock.get_status().label == "DAY 5  ·  00:00")
	clock.frozen = true
	clock.tick(20.0)
	assert(clock.day_index == 4 and is_zero_approx(clock.minute_of_day))
	assert(is_equal_approx(clock.elapsed_seconds, 141.0))
	clock.frozen = false
	clock.tick(2880.0)
	assert(clock.day_index == 5 and is_zero_approx(clock.minute_of_day))
	clock.tick(-1.0)
	assert(clock.day_index == 5 and is_zero_approx(clock.minute_of_day))
	clock.free()
	print("[city_world_time] 8 clock, rollover, freeze and full-day checks passed")
	quit()
