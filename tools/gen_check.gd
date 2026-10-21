extends Node
## Headless generator check: determinism, fairness rules, and generation speed.
##   godot --headless --path . res://tools/gen_check.tscn -- --levels=500
## Exits with code 1 if any check fails. Writes reports/gen_check.txt.

func _ready() -> void:
	var count := 500
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--levels="):
			count = int(arg.get_slice("=", 1))
		elif arg.begins_with("--trace="):
			_trace(int(arg.get_slice("=", 1)))
			get_tree().quit()
			return
	var db := Content.db
	var balance := Balance.data
	var gen: Dictionary = balance.get("generator", {})
	var failures: PackedStringArray = []
	var total_ms := 0.0
	var max_ms := 0.0
	var max_level := 0
	var repaired_levels := 0
	var est_losses := 0
	var kinds := {}
	var templates := {}
	var segments := {}
	var lines: PackedStringArray = ["level,seed,kind,template,length,events,gen_ms,difficulty_scale,est_win,est_hp,zone,boss,modifiers"]

	for level in range(1, count + 1):
		var seed_value := LevelSeed.for_level(level)
		var plan := LevelBuilder.build(level, seed_value, db, balance)
		var again := LevelBuilder.build(level, seed_value, db, balance)
		if _fingerprint(plan) != _fingerprint(again):
			failures.append("level %d: non-deterministic" % level)

		var dbg: Dictionary = plan["debug"]
		var ms := float(dbg["gen_ms"])
		total_ms += ms
		if ms > max_ms:
			max_ms = ms
			max_level = level
		var ctx := LevelBuilder.make_context(level, db, balance, RandomNumberGenerator.new())
		ctx["modifiers"] = plan.get("modifiers", [])
		var problems := Fairness.validate(plan, ctx, db["enemies"], float(gen.get("density_window", 25.0)),
			Curves.named(balance, "max_density", level), float(gen.get("wall_lookback", 140.0)))
		for p in problems:
			failures.append("level %d: %s" % [level, p])
		var est: Dictionary = dbg["estimate"]
		if not bool(est["survived"]):
			est_losses += 1
		if float(dbg["difficulty_scale"]) < 0.999:
			repaired_levels += 1
		kinds[plan["kind"]] = int(kinds.get(plan["kind"], 0)) + 1
		templates[plan["template"]] = int(templates.get(plan["template"], 0)) + 1
		for seg: Dictionary in dbg["segments"]:
			segments[seg["id"]] = int(segments.get(seg["id"], 0)) + 1
		lines.append("%d,%d,%s,%s,%d,%d,%.2f,%.3f,%s,%.2f,%s%s,%s,%s" % [level, seed_value, plan["kind"], plan["template"],
			int(plan["length"]), (plan["events"] as Array).size(), ms, float(dbg["difficulty_scale"]), est["survived"], float(est["hp_frac"]),
			plan["zone"], ("+%d" % int(plan["zone_cycle"])) if int(plan["zone_cycle"]) > 0 else "", plan["boss"].get("id", ""), "|".join(plan["modifiers"])])

	var summary: PackedStringArray = [
		"Levels checked: %d" % count,
		"Generation: avg %.2f ms, max %.2f ms (level %d), budget 50 ms" % [total_ms / count, max_ms, max_level],
		"Difficulty repaired on %d levels; estimator losses after repair: %d" % [repaired_levels, est_losses],
		"Kinds: %s" % kinds,
		"Templates: %s" % templates,
		"Segment usage: %s" % segments,
		"Failures: %d" % failures.size(),
	]
	for f in failures.slice(0, 40):
		summary.append("  " + f)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports"))
	var file := FileAccess.open("res://reports/gen_check.csv", FileAccess.WRITE)
	if file:
		file.store_string("\n".join(lines) + "\n")
	print("\n".join(summary))
	if max_ms > 50.0:
		failures.append("generation exceeded 50 ms")
	get_tree().quit(1 if not failures.is_empty() else 0)


## Prints the estimator's best-path walkthrough of one level (after repairs).
func _trace(level: int) -> void:
	var plan := LevelBuilder.build(level, LevelSeed.for_level(level), Content.db, Balance.data)
	var log: Array = []
	var hero := LevelBuilder.expected_hero(level, Content.db, Balance.data)
	print("level %d kind %s scale %.2f hero dmg %.1f hp %.0f" % [level, plan["kind"], plan["debug"]["difficulty_scale"], hero.damage, hero.hp])
	var result := Estimator.run(plan, hero, "best", Content.db, Balance.data, null, log)
	print("\n".join(log))
	print(result)


func _fingerprint(plan: Dictionary) -> String:
	var copy := plan.duplicate(true)
	copy.erase("debug")
	return JSON.stringify(copy, "", true)
