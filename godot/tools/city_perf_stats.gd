extends RefCounted
## Pure benchmark statistics shared by the life benchmark and its fixtures.
## Nothing here reads the scene, clocks or engine monitors.

## Copy any numeric array-like value into a PackedFloat64Array.
static func to_packed(values: Variant) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	if values is PackedFloat64Array:
		result = (values as PackedFloat64Array).duplicate()
	elif values is Array or values is PackedFloat32Array or values is PackedInt32Array or values is PackedInt64Array:
		result.resize(values.size())
		for i in values.size():
			result[i] = float(values[i])
	return result

static func total(values: Variant) -> float:
	var sum := 0.0
	for value in to_packed(values):
		sum += value
	return sum

## Nearest-rank summary, compatible with earlier metrics: the median is the
## upper middle element for even counts and p95/p99 use ceil(rank) - 1.
## Empty input returns {} so callers can tell "not measured" from zero.
static func distribution(values: Variant) -> Dictionary:
	var sorted := to_packed(values)
	if sorted.is_empty():
		return {}
	sorted.sort()
	var count := sorted.size()
	var sum := 0.0
	for value in sorted:
		sum += value
	return {"median": sorted[int(count / 2.0)], "p95": sorted[mini(count - 1, ceili(count * 0.95) - 1)],
		"p99": sorted[mini(count - 1, ceili(count * 0.99) - 1)], "min": sorted[0], "max": sorted[count - 1],
		"mean": sum / count, "sum": sum, "count": count}

## Milliseconds of work per wall-clock second: periodic work (10 Hz UI, 2 Hz
## residents) is compared by budget, independent of how many frames it hits.
static func per_second(values: Variant, seconds: float) -> float:
	if seconds <= 0.0:
		return 0.0
	return total(values) / seconds

## Frame length below which `fraction` of the elapsed time was spent. Unlike a
## frame-count percentile it does not shift when the frame rate changes the
## mixture of short render-only frames and longer physics frames.
static func time_weighted_percentile(frame_ms: Variant, fraction: float) -> float:
	var sorted := to_packed(frame_ms)
	if sorted.is_empty():
		return 0.0
	sorted.sort()
	var target := total(sorted) * clampf(fraction, 0.0, 1.0)
	var running := 0.0
	for value in sorted:
		running += value
		if running >= target:
			return value
	return sorted[sorted.size() - 1]

static func count_over(values: Variant, threshold: float) -> int:
	var count := 0
	for value in to_packed(values):
		if value > threshold:
			count += 1
	return count

## Distribution plus per-second budget for each named column.
static func summarize_columns(columns: Dictionary, seconds: float) -> Dictionary:
	var result := {}
	for key in columns:
		var summary := distribution(columns[key])
		if summary.is_empty():
			continue
		summary["per_second"] = per_second(columns[key], seconds)
		result[key] = summary
	return result
