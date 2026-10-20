class_name LevelSeed
extends RefCounted
## Stable seeds. Uses our own FNV-1a so seeds never change with engine versions or platforms:
## every player gets the same "Level 57" forever.


static func fnv1a(text: String) -> int:
	var h := 2166136261
	for b in text.to_utf8_buffer():
		h = ((h ^ b) * 16777619) & 0xFFFFFFFF
	return h


static func for_level(level: int) -> int:
	return fnv1a("gaterunner/level/%d" % level)


## date = "YYYY-MM-DD" (used by the daily challenge in Milestone 7).
static func for_daily(date: String) -> int:
	return fnv1a("gaterunner/daily/%s" % date)
