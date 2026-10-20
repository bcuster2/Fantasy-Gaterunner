extends Node
## Plays real levels with the autopilot (full game simulation, headless) and compares the outcome to
## the analytic Estimator's best-path prediction for the same plan. Use it to tune balance.json ->
## estimator so the fast simulator matches the real game.
##   godot --headless --path . --fixed-fps 60 res://tools/calibrate.tscn -- --levels=1,5,10,25
## Writes reports/calibration.csv and prints a bias summary.

const RUN_SCENE := preload("res://core/run/run.tscn")
const DEFAULT_LEVELS := [1, 2, 3, 4, 5, 7, 9, 10, 12, 15, 18, 22, 25, 30, 35, 40, 50, 60, 75, 90, 110, 130, 160, 200, 250, 300, 400, 500]


func _ready() -> void:
	var levels: Array = DEFAULT_LEVELS.duplicate()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--levels="):
			levels = Array(arg.get_slice("=", 1).split(",")).map(func(v: String) -> int: return int(v))
	GameState.autopilot = true
	GameState.assume_upgrades = true
	GameState.fast_results = true
	AudioManager.set_sfx_enabled(false)

	var lines: PackedStringArray = ["level,kind,live_won,live_hp_frac,live_kill_frac,live_coins,est_won,est_hp_frac,est_kill_frac,est_coins,difficulty_scale"]
	var hp_diffs: Array[float] = []
	var kill_diffs: Array[float] = []
	var optimistic := 0
	var pessimistic := 0
	for level: int in levels:
		GameState.level = level
		GameState.seed_override = -1
		var run := RUN_SCENE.instantiate()
		add_child(run)
		var live: Dictionary = await run.finished
		run.queue_free()
		await get_tree().process_frame
		Engine.time_scale = 1.0

		var plan := LevelGenerator.get_plan(level)
		var hero := LevelBuilder.expected_hero(level, Content.db, Balance.data)
		var est := Estimator.run(plan, hero, "best", Content.db, Balance.data)
		var live_kill := float(live["kills"]) / maxf(float(live["units"]), 1.0)
		var est_kill := float(est["kills"]) / maxf(float(est["units"]), 1.0)
		if bool(live["won"]) and bool(est["survived"]):
			hp_diffs.append(float(est["hp_frac"]) - float(live["hp_frac"]))
		kill_diffs.append(est_kill - live_kill)
		if bool(est["survived"]) and not bool(live["won"]):
			optimistic += 1
		if not bool(est["survived"]) and bool(live["won"]):
			pessimistic += 1
		lines.append("%d,%s,%s,%.3f,%.3f,%d,%s,%.3f,%.3f,%d,%.3f" % [level, plan["kind"], live["won"], float(live["hp_frac"]), live_kill,
			int(live["coins"]), est["survived"], float(est["hp_frac"]), est_kill, int(est["coins"]), float(plan["debug"]["difficulty_scale"])])
		print("[cal] level %d: live %s hp %.2f kills %.2f | est %s hp %.2f kills %.2f" % [level, "WIN" if live["won"] else "LOSS",
			float(live["hp_frac"]), live_kill, "WIN" if est["survived"] else "LOSS", float(est["hp_frac"]), est_kill])

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports"))
	var file := FileAccess.open("res://reports/calibration.csv", FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	print("[cal] levels %d | est-live hp bias %.3f (both won, n=%d) | kill-rate bias %.3f | est optimistic (said win, live lost) %d | est pessimistic %d" % [
		levels.size(), _mean(hp_diffs), hp_diffs.size(), _mean(kill_diffs), optimistic, pessimistic])
	get_tree().quit()


func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += v
	return total / values.size()
