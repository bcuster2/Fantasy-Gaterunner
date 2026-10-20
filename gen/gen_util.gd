class_name GenUtil
extends RefCounted
## Deterministic random helpers for the generator. Always pass the level's RNG.


static func available(item: Dictionary, level: int) -> bool:
	if level < int(item.get("min_level", 1)):
		return false
	var max_level := int(item.get("max_level", 0))
	return max_level <= 0 or level <= max_level


## Weighted pick among items available at this level. Returns {} when nothing qualifies.
static func pick_weighted(rng: RandomNumberGenerator, items: Array, level: int) -> Dictionary:
	var total := 0.0
	for item: Dictionary in items:
		if available(item, level):
			total += float(item.get("weight", 1.0))
	if total <= 0.0:
		return {}
	var roll := rng.randf() * total
	for item: Dictionary in items:
		if not available(item, level):
			continue
		roll -= float(item.get("weight", 1.0))
		if roll <= 0.0:
			return item
	for k in range(items.size() - 1, -1, -1):
		if available(items[k], level):
			return items[k]
	return {}


## Fixed number, or [min, max] -> uniform random float.
static func value(rng: RandomNumberGenerator, v: Variant) -> float:
	if v is Array:
		var range_values: Array = v
		return rng.randf_range(float(range_values[0]), float(range_values[1]))
	return float(v)


## [min, max] interpolated by t (0..1) and rounded; used for density-scaled counts.
static func scaled_int(v: Variant, t: float) -> int:
	if v is Array:
		var range_values: Array = v
		return int(roundf(lerpf(float(range_values[0]), float(range_values[1]), clampf(t, 0.0, 1.0))))
	return int(v)


static func shuffle(rng: RandomNumberGenerator, items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = items[i]
		items[i] = items[j]
		items[j] = tmp
