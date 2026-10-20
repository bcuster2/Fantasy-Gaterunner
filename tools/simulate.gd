extends Node
## Level validation simulator. For every level it generates the plan exactly as the game would, then
## runs the analytic Estimator with an expected-upgrade hero along three gate paths:
##   best   - always the highest-scoring gate
##   median - always the median-ranked gate (2 options: the weaker one)
##   casual - best gate ~65% of the time, otherwise a random other gate; sampled N times -> win rate
## Outputs reports/sim_levels.csv (one row per level) and reports/sim_report.md (bands + flags).
##   godot --headless --path . res://tools/simulate.tscn -- --from=1 --to=500 --samples=25
## Calibrate the Estimator against real autopilot runs with tools/calibrate.tscn.

const BAND := 50


func _ready() -> void:
	var from := 1
	var to := 500
	var balance := Balance.data
	var sim: Dictionary = balance.get("simulator", {})
	var samples := int(sim.get("casual_samples", 25))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--from="):
			from = int(arg.get_slice("=", 1))
		elif arg.begins_with("--to="):
			to = int(arg.get_slice("=", 1))
		elif arg.begins_with("--samples="):
			samples = int(arg.get_slice("=", 1))
	var db := Content.db
	var speed := float(balance.get("hero", {}).get("run_speed", 8.0))
	var targets: Dictionary = sim.get("target_casual_win", {})
	var run_range: Array = sim.get("run_seconds", [35, 80])
	var started := Time.get_ticks_msec()

	var rows: Array[Dictionary] = []
	var cumulative_coins := 0.0
	for level in range(from, to + 1):
		var plan := LevelGenerator.get_plan(level)
		var hero := LevelBuilder.expected_hero(level, db, balance)
		var best := Estimator.run(plan, hero, "best", db, balance)
		var median := Estimator.run(plan, hero, "median", db, balance)
		var rng := RandomNumberGenerator.new()
		rng.seed = LevelSeed.fnv1a("sim/%d" % level)
		var wins := 0
		var casual_coins := 0.0
		var casual_hp := 0.0
		for k in samples:
			var r := Estimator.run(plan, hero, "casual", db, balance, rng)
			if bool(r["survived"]):
				wins += 1
				casual_hp += float(r["hp_frac"])
			casual_coins += float(r["coins"])
		var win_rate := float(wins) / maxf(samples, 1)
		casual_coins /= maxf(samples, 1)
		# Expected coins per level for a player who retries until they win (losses still pay).
		cumulative_coins += casual_coins / maxf(win_rate, 0.2)
		var kind := String(plan["kind"])
		var seconds := float(plan["length"]) / speed
		var flags: PackedStringArray = []
		if not bool(best["survived"]):
			flags.append("BROKEN")
		var band: Array = targets.get(kind, [0.5, 0.95])
		if win_rate < float(band[0]):
			flags.append("HARD")
		elif win_rate > float(band[1]):
			flags.append("EASY")
		if float(plan["debug"]["difficulty_scale"]) < float(sim.get("max_repair", 0.75)):
			flags.append("REPAIRED")
		if seconds < float(run_range[0]):
			flags.append("SHORT")
		elif seconds > float(run_range[1]):
			flags.append("LONG")
		rows.append({
			"level": level, "kind": kind, "template": plan["template"], "length": int(plan["length"]), "seconds": seconds,
			"best_win": best["survived"], "best_hp": float(best["hp_frac"]), "median_win": median["survived"], "median_hp": float(median["hp_frac"]),
			"casual_win": win_rate, "casual_hp": casual_hp / maxf(wins, 1), "coins_best": float(best["coins"]), "coins_casual": casual_coins,
			"cumulative_coins": cumulative_coins, "scale": float(plan["debug"]["difficulty_scale"]), "flags": " ".join(flags),
		})

	_write_csv(rows)
	_write_report(rows, samples, Time.get_ticks_msec() - started)
	get_tree().quit()


func _write_csv(rows: Array[Dictionary]) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports"))
	var lines: PackedStringArray = ["level,kind,template,length_m,run_seconds,best_win,best_hp,median_win,median_hp,casual_win_rate,casual_hp,coins_best,coins_casual,cumulative_coins,difficulty_scale,flags"]
	for r in rows:
		lines.append("%d,%s,%s,%d,%.1f,%s,%.3f,%s,%.3f,%.3f,%.3f,%.1f,%.1f,%.0f,%.3f,%s" % [r["level"], r["kind"], r["template"], r["length"], r["seconds"],
			r["best_win"], r["best_hp"], r["median_win"], r["median_hp"], r["casual_win"], r["casual_hp"], r["coins_best"], r["coins_casual"],
			r["cumulative_coins"], r["scale"], r["flags"]])
	FileAccess.open("res://reports/sim_levels.csv", FileAccess.WRITE).store_string("\n".join(lines) + "\n")


func _write_report(rows: Array[Dictionary], samples: int, ms: int) -> void:
	var md: PackedStringArray = [
		"# Level simulation report",
		"",
		"Levels %d-%d, %d casual samples per level, %.1f s. Expected-upgrade hero (player_power / player_hp curves)." % [rows[0]["level"], rows[-1]["level"], samples, ms / 1000.0],
		"",
		"| levels | casual win | best hp | median win | spike win | reward win | repair scale | run s | coins/level | cumulative coins |",
		"|---|---|---|---|---|---|---|---|---|---|",
	]
	var flag_counts := {}
	var i := 0
	while i < rows.size():
		var band := rows.slice(i, i + BAND)
		var avg := func(key: String, filter := "") -> float:
			var total := 0.0
			var n := 0
			for r: Dictionary in band:
				if filter != "" and r["kind"] != filter:
					continue
				var v: Variant = r[key]
				total += (1.0 if v else 0.0) if v is bool else float(v)
				n += 1
			return total / n if n > 0 else NAN
		md.append("| %d-%d | %.0f%% | %.0f%% | %.0f%% | %.0f%% | %.0f%% | %.2f | %.0f | %.0f | %.0f |" % [band[0]["level"], band[-1]["level"],
			avg.call("casual_win") * 100, avg.call("best_hp") * 100, avg.call("median_win") * 100, avg.call("casual_win", "spike") * 100,
			avg.call("casual_win", "reward") * 100, avg.call("scale"), avg.call("seconds"), avg.call("coins_casual"), band[-1]["cumulative_coins"]])
		i += BAND
	var flagged: PackedStringArray = []
	for r in rows:
		for f in String(r["flags"]).split(" ", false):
			flag_counts[f] = int(flag_counts.get(f, 0)) + 1
		if String(r["flags"]) != "":
			flagged.append("- L%d (%s, %s): casual %.0f%%, best hp %.0f%%, scale %.2f -> %s" % [r["level"], r["kind"], r["template"],
				float(r["casual_win"]) * 100, float(r["best_hp"]) * 100, float(r["scale"]), r["flags"]])
	md.append("")
	md.append("## Flags")
	md.append("")
	md.append("Counts: %s" % (flag_counts if not flag_counts.is_empty() else "none"))
	md.append("")
	md.append("BROKEN = best path loses; HARD/EASY = casual win rate outside the target band for the level kind;")
	md.append("REPAIRED = generator had to scale enemies below simulator.max_repair; SHORT/LONG = run length.")
	md.append("")
	md.append_array(flagged.slice(0, 60))
	if flagged.size() > 60:
		md.append("- ... %d more in sim_levels.csv" % (flagged.size() - 60))
	FileAccess.open("res://reports/sim_report.md", FileAccess.WRITE).store_string("\n".join(md) + "\n")
	print("\n".join(md.slice(0, 16)))
	print("Flags: %s" % flag_counts)
