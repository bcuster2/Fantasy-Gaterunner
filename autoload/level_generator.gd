extends Node
## Produces LevelPlans consumed by the Run scene and the headless simulator.
##
## LevelPlan schema:
##   { "id": String, "level": int, "length": float,
##     "events": [ { "d": float, "type": "enemies" | "gates", ... } ]  # sorted by d }
##
## Milestone 1 serves the hand-made test level. Milestone 3 replaces get_plan() with
## seeded segment assembly; the schema stays the same.


func get_plan(level: int) -> Dictionary:
	var source: Dictionary = Content.levels.get("test_level", {})
	var plan := source.duplicate(true)
	var events: Array = plan.get("events", [])
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	plan["events"] = events
	plan["level"] = level
	plan["length"] = float(plan.get("length", 400.0))
	return plan
