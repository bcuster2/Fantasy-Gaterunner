extends Node
## Save system tests (isolated folder, never touches the real save):
##   godot --headless --path . res://tools/save_test.tscn
## Covers: fresh start, round trip, atomic write + backup, corrupt main -> backup, both corrupt ->
## defaults, wrong types / missing keys merged, unknown keys kept, migration of a version-0 save.

var _failures: PackedStringArray = []


func _ready() -> void:
	var dir := "user://save_test"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var real_dir := SaveManager.save_dir
	var real_data := SaveManager.data.duplicate(true)
	SaveManager.save_dir = dir
	_clean(dir)

	SaveManager.load_game()
	_check(SaveManager.load_status == "new", "fresh start reports new")
	_check(SaveManager.coins() == 0 and SaveManager.unlocked_level() == 1, "fresh defaults")

	SaveManager.add_coins(500)
	SaveManager.data["upgrades"]["damage"] = 3
	SaveManager.save_now()
	SaveManager.save_now()
	SaveManager.load_game()
	_check(SaveManager.load_status == "ok", "round trip ok")
	_check(SaveManager.coins() == 500 and SaveManager.upgrade_level("damage") == 3, "round trip values")
	_check(FileAccess.file_exists(dir.path_join("save.bak.json")), "backup written")
	_check(not FileAccess.file_exists(dir.path_join("save.tmp.json")), "temp file cleaned up")

	_write(dir.path_join("save.json"), "{ this is not json")
	SaveManager.load_game()
	_check(SaveManager.load_status == "restored_backup", "corrupt main falls back to backup")
	_check(SaveManager.coins() == 500, "backup data restored")

	_write(dir.path_join("save.json"), "garbage")
	_write(dir.path_join("save.bak.json"), "[1,2,3]")
	SaveManager.load_game()
	_check(SaveManager.load_status == "reset_corrupt", "both corrupt -> defaults")
	_check(SaveManager.coins() == 0, "defaults after reset")

	_write(dir.path_join("save.json"), JSON.stringify({"coins": "lots", "campaign": {"unlocked": 7}, "future_feature": {"x": 1}, "milestones_claimed": [10.0, 20.0]}))
	SaveManager.load_game()
	_check(SaveManager.coins() == 0, "wrong type replaced by default")
	_check(SaveManager.unlocked_level() == 7, "partial nested data kept")
	_check(int(SaveManager.data["campaign"]["best_completed"]) == 0, "missing nested key filled")
	_check(SaveManager.data.has("future_feature"), "unknown keys preserved")
	_check((SaveManager.data["milestones_claimed"] as Array).has(10), "claimed milestones normalized to ints")
	_check(int(SaveManager.data["version"]) == SaveManager.VERSION, "migrated to current version")

	var reward := SaveManager.record_campaign_run(30, true, 100, 50, 60.0)
	_check(not reward.is_empty() and SaveManager.unlocked_level() == 31 and SaveManager.perks().has("thick_hide"), "milestone claimed, perk granted, level unlocked")
	_check(SaveManager.record_campaign_run(30, true, 0, 0, 1.0).is_empty(), "milestone only claimed once")

	# Daily challenge: one attempt, one ad retry, then locked; resets with the date.
	var day := "2030-01-01"
	_check(SaveManager.daily_can_play(day) and not SaveManager.daily_can_retry(day), "daily: fresh day playable")
	SaveManager.start_daily_attempt(day)
	_check(not SaveManager.daily_can_play(day) and SaveManager.daily_can_retry(day), "daily: after a loss, retry offered")
	SaveManager.grant_daily_retry(day)
	_check(SaveManager.daily_can_play(day), "daily: retry grants one more attempt")
	SaveManager.start_daily_attempt(day)
	_check(not SaveManager.daily_can_play(day) and not SaveManager.daily_can_retry(day), "daily: no third attempt")
	SaveManager.record_daily_result(day, true, 900, 50, 10, 60.0)
	_check(bool(SaveManager.daily(day)["completed"]) and int(SaveManager.daily(day)["best_score"]) == 900, "daily: win recorded")
	_check(SaveManager.daily_can_play("2030-01-02"), "daily: new date resets")
	_check(LevelGenerator.get_daily_plan(day)["seed"] == LevelGenerator.get_daily_plan(day)["seed"] and LevelGenerator.get_daily_plan(day)["modifiers"] == LevelGenerator.get_daily_plan(day)["modifiers"], "daily: plan deterministic")
	_check(LevelGenerator.get_daily_plan(day)["seed"] != LevelGenerator.get_daily_plan("2030-01-02")["seed"], "daily: different days differ")

	# Endless high scores.
	_check(SaveManager.record_endless(1200, 900.0, 40, 300, 120.0), "endless: first score is a best")
	_check(not SaveManager.record_endless(800, 950.0, 10, 100, 60.0), "endless: lower score is not a best")
	_check(int(SaveManager.data["high_scores"]["endless_score"]) == 1200 and int(SaveManager.data["high_scores"]["endless_distance"]) == 950, "endless: bests kept")

	_clean(dir)
	SaveManager.save_dir = real_dir
	SaveManager.data = real_data
	if _failures.is_empty():
		print("[save_test] all checks passed")
	else:
		print("[save_test] FAILED:\n  " + "\n  ".join(_failures))
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _clean(dir: String) -> void:
	for name in ["save.json", "save.bak.json", "save.tmp.json"]:
		if FileAccess.file_exists(dir.path_join(name)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(name)))
