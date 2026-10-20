extends Node
## Produces LevelPlans consumed by the Run scene. Thin wrapper over the pure LevelBuilder
## (gen/level_builder.gd), which the headless tools call directly.
##
## LevelPlan schema (see README): { id, level, seed, kind, length, events[], palette, zone, boss,
##   modifiers, coin_mult, hero_power, hero_hp_power, ally_power, debug }
## Level 0 is the hand-made test level (data/levels/test_level.json).

const CACHE_SIZE := 8

var _cache: Dictionary = {}


func seed_for(level: int) -> int:
	return LevelSeed.for_level(level)


## seed_override < 0 uses the level's canonical seed. A custom seed keeps the level's difficulty.
func get_plan(level: int, seed_override := -1) -> Dictionary:
	if level <= 0:
		return _test_level()
	var seed_value := seed_override if seed_override >= 0 else seed_for(level)
	var key := "%d:%d" % [level, seed_value]
	if not _cache.has(key):
		if _cache.size() >= CACHE_SIZE:
			_cache.clear()
		_cache[key] = LevelBuilder.build(level, seed_value, Content.db, Balance.data)
		var dbg: Dictionary = _cache[key]["debug"]
		print_verbose("[gen] level %d seed %d: %.1f ms, scale %.2f" % [level, seed_value, dbg["gen_ms"], dbg["difficulty_scale"]])
	return (_cache[key] as Dictionary).duplicate(true)


func _test_level() -> Dictionary:
	var plan: Dictionary = (Content.levels.get("test_level", {}) as Dictionary).duplicate(true)
	var events: Array = plan.get("events", [])
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	plan["events"] = events
	plan["level"] = 0
	plan["seed"] = 0
	plan["kind"] = "test"
	plan["length"] = float(plan.get("length", 400.0))
	return plan
