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
