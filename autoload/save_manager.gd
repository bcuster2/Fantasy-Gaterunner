extends Node
## Persistent player data in user://save.json.
## - Versioned: `version` plus a migration chain, so old saves upgrade in place.
## - Atomic: writes go to a temp file that is verified, then swapped in; the previous good save is kept
##   as a backup. A torn write can never destroy progress.
## - Forgiving: a missing file starts fresh; a corrupt file falls back to the backup, then to
##   defaults. Unknown or missing keys are filled from defaults (merge), wrong types are replaced.

signal coins_changed(coins: int)
signal changed

const VERSION := 1

## Folder holding the save files (tests point this at a scratch folder).
var save_dir := "user://"
var SAVE_PATH: String:
	get: return save_dir.path_join("save.json")
var BACKUP_PATH: String:
	get: return save_dir.path_join("save.bak.json")
var TEMP_PATH: String:
	get: return save_dir.path_join("save.tmp.json")

var data: Dictionary = {}
## "new" | "ok" | "restored_backup" | "reset_corrupt" (shown in the dev menu).
var load_status := ""

var _save_queued := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Dev/test: `-- --save-dir=user://demo` uses a separate save folder.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save-dir="):
			save_dir = arg.get_slice("=", 1)
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_dir))
	load_game()
	apply_settings()


static func defaults() -> Dictionary:
	return {
		"version": VERSION,
		"coins": 0,
		"campaign": {"unlocked": 1, "last_played": 1, "best_completed": 0},
		"upgrades": {},
		"milestones_claimed": [],
		"perks": [],
		"skins": ["default"],
		"selected_skin": "default",
		"settings": {"music": true, "sfx": true, "vibration": true},
		"high_scores": {"endless_score": 0, "endless_distance": 0},
		"daily": {"date": "", "attempts": 0, "retry_used": false, "completed": false, "best_score": 0},
		"stats": {"runs": 0, "wins": 0, "kills": 0, "coins_earned": 0, "seconds_played": 0.0},
		"tutorial_done": false,
		"purchases": {"remove_ads": false},
		"privacy": {"consent": "unknown"},
	}


# --- Load / save ------------------------------------------------------------------------------

func load_game() -> void:
	var loaded: Variant = _read(SAVE_PATH)
	if loaded == null:
		if FileAccess.file_exists(SAVE_PATH):
			push_warning("Save file is corrupt; trying the backup")
			loaded = _read(BACKUP_PATH)
			load_status = "restored_backup" if loaded != null else "reset_corrupt"
		else:
			load_status = "new"
	else:
		load_status = "ok"
	data = _merge(defaults(), loaded if loaded is Dictionary else {})
	data = _migrate(data)
	if load_status != "ok":
		save_now()


## Coalesces several changes in one frame into a single write.
func save_soon() -> void:
	if _save_queued:
		return
	_save_queued = true
	save_now.call_deferred()


func save_now() -> bool:
	_save_queued = false
	data["version"] = VERSION
	var text := JSON.stringify(data, "\t")
	var tmp := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if tmp == null:
		push_error("Cannot write save: %s" % error_string(FileAccess.get_open_error()))
		return false
	tmp.store_string(text)
	tmp.close()
	if _read(TEMP_PATH) == null:
		push_error("Save verification failed; keeping the previous save")
		return false
	var dir := DirAccess.open(save_dir)
	if FileAccess.file_exists(SAVE_PATH):
		if FileAccess.file_exists(BACKUP_PATH):
			dir.remove(BACKUP_PATH.get_file())
		dir.rename(SAVE_PATH.get_file(), BACKUP_PATH.get_file())
	var err := dir.rename(TEMP_PATH.get_file(), SAVE_PATH.get_file())
	if err != OK:
		push_error("Save rename failed: %s" % error_string(err))
		return false
	changed.emit()
	return true


func reset_progress() -> void:
	var keep_settings: Dictionary = data.get("settings", {}).duplicate()
	var keep_purchases: Dictionary = data.get("purchases", {}).duplicate()
	var keep_privacy: Dictionary = data.get("privacy", {}).duplicate()
	data = defaults()
	data["settings"] = keep_settings
	data["purchases"] = keep_purchases
	data["privacy"] = keep_privacy
	save_now()
	coins_changed.emit(coins())


func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var json := JSON.new() # quiet parse: corrupt files are an expected case, not an engine error
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return null
	return json.data if json.data is Dictionary else null


## Recursively fills missing keys from defaults and replaces values of the wrong type.
static func _merge(base: Dictionary, loaded: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for key: String in loaded:
		if not out.has(key):
			out[key] = loaded[key] # keep unknown keys (newer data written by a later version)
			continue
		var want: Variant = out[key]
		var got: Variant = loaded[key]
		if want is Dictionary and got is Dictionary:
			out[key] = _merge(want, got)
		elif typeof(want) == typeof(got) or (want is float and got is int) or (want is int and got is float):
			out[key] = got
	return out


## Upgrades older save formats step by step. Add a branch per version bump.
static func _migrate(d: Dictionary) -> Dictionary:
	var version := int(d.get("version", 0))
	while version < VERSION:
		match version:
			0:
				pass # pre-release saves had no version field; the merge already filled everything
		version += 1
	d["version"] = VERSION
	# JSON numbers load as floats; keep list entries that are compared with ints as ints.
	d["milestones_claimed"] = (d["milestones_claimed"] as Array).map(func(v: Variant) -> int: return int(v))
	return d


# --- Coins ------------------------------------------------------------------------------------

func coins() -> int:
	return int(data["coins"])


func add_coins(amount: int) -> void:
	data["coins"] = coins() + amount
	if amount > 0:
		data["stats"]["coins_earned"] = int(data["stats"]["coins_earned"]) + amount
	coins_changed.emit(coins())
	save_soon()


func spend(amount: int) -> bool:
	if amount < 0 or coins() < amount:
		return false
	data["coins"] = coins() - amount
	coins_changed.emit(coins())
	save_soon()
	return true


# --- Upgrades, perks, skins -------------------------------------------------------------------

func upgrade_level(id: String) -> int:
	return int(data["upgrades"].get(id, 0))


func upgrade_levels() -> Dictionary:
	return data["upgrades"]


func buy_upgrade(id: String) -> bool:
	var def: Dictionary = Content.upgrades.get(id, {})
	var price := Economy.cost(def, upgrade_level(id))
	if def.is_empty() or price < 0 or not spend(price):
		return false
	data["upgrades"][id] = upgrade_level(id) + 1
	save_soon()
	return true


func perks() -> Array:
	return data["perks"]


func owns_skin(id: String) -> bool:
	return (data["skins"] as Array).has(id)


func select_skin(id: String) -> void:
	if owns_skin(id):
		data["selected_skin"] = id
		save_soon()


# --- Campaign ---------------------------------------------------------------------------------

func unlocked_level() -> int:
	return int(data["campaign"]["unlocked"])


## Records a finished campaign run and banks its coins. Returns the milestone reward unlocked by
## this win ({} if none).
func record_campaign_run(level: int, won: bool, payout: int, kills: int, seconds: float) -> Dictionary:
	var stats: Dictionary = data["stats"]
	stats["runs"] = int(stats["runs"]) + 1
	stats["kills"] = int(stats["kills"]) + kills
	stats["seconds_played"] = float(stats["seconds_played"]) + seconds
	data["campaign"]["last_played"] = level
	add_coins(payout)
	var reward := {}
	if won:
		stats["wins"] = int(stats["wins"]) + 1
		data["campaign"]["best_completed"] = maxi(int(data["campaign"]["best_completed"]), level)
		data["campaign"]["unlocked"] = maxi(unlocked_level(), level + 1)
		if level == 1:
			data["tutorial_done"] = true
		reward = _claim_milestone(level)
	save_soon()
	return reward


func _claim_milestone(level: int) -> Dictionary:
	var reward := Economy.milestone(level, Content.milestones, Balance.data)
	if reward.is_empty() or (data["milestones_claimed"] as Array).has(level):
		return {}
	(data["milestones_claimed"] as Array).append(level)
	match String(reward.get("type", "")):
		"perk":
			if not perks().has(reward["id"]):
				perks().append(reward["id"])
		"skin":
			if not owns_skin(reward["id"]):
				(data["skins"] as Array).append(reward["id"])
	add_coins(int(reward.get("coins", 0)))
	return reward


# --- Settings ---------------------------------------------------------------------------------

func setting(key: String) -> bool:
	return bool(data["settings"].get(key, true))


func set_setting(key: String, value: bool) -> void:
	data["settings"][key] = value
	apply_settings()
	save_soon()


func apply_settings() -> void:
	AudioManager.set_music_enabled(setting("music"))
	AudioManager.set_sfx_enabled(setting("sfx"))
	GameState.vibration_enabled = setting("vibration")
