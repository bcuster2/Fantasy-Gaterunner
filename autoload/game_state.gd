extends Node
## Cross-scene session state: which mode/level is being played, active hero class, dev toggles.
## Persistent data (coins, upgrades, settings) moves to SaveManager in Milestone 6.
##
## Command line (after `--`): --level=N  --seed=S  --autopilot  --overlay  --god

const SCREENS := {
	"menu": "res://ui/screens/main_menu.tscn",
	"modes": "res://ui/screens/mode_select.tscn",
	"map": "res://ui/screens/level_map.tscn",
	"shop": "res://ui/screens/shop.tscn",
	"settings": "res://ui/screens/settings.tscn",
	"run": "res://core/run/run.tscn",
}

var mode := "campaign"
## Screen to return to from the shop/settings.
var return_screen := "menu"
var level := 1
## Debug: a custom seed for the current level (-1 = the level's canonical seed).
var seed_override := -1
var hero_class := "battlemage"

var god_mode := false
var vibration_enabled := true
## Debug: draws generator segments/roles on the track and plan stats on screen.
var debug_overlay := false
## Debug/tools: give the hero the generator's expected upgrade level instead of the player's real
## shop upgrades (used by calibration; toggle in the dev menu).
var assume_upgrades := false
## Set with `-- --autopilot` on the command line; a simple bot steers (used for smoke tests).
var autopilot := false
## Debug: open the dev menu as soon as a run starts (`--open-debug`, handy for screenshots).
var open_debug_menu := false
## Tools: skip slow-motion/hit-stop so headless harnesses get results immediately.
var fast_results := false
## Debug: start the run this many meters in (events before it are skipped). `--start=N`, or the
## dev menu's SKIP TO BOSS. A negative value means "just before the boss arena".
var start_distance := 0.0


func _ready() -> void:
	assume_upgrades = bool(Balance.get_value("generator.debug_assume_upgrades", false))
	for arg in OS.get_cmdline_user_args():
		if arg == "--autopilot":
			autopilot = true
		elif arg == "--overlay":
			debug_overlay = true
		elif arg == "--open-debug":
			open_debug_menu = true
		elif arg == "--god":
			god_mode = true
		elif arg.begins_with("--level="):
			level = int(arg.get_slice("=", 1))
		elif arg.begins_with("--start="):
			start_distance = float(arg.get_slice("=", 1))
		elif arg.begins_with("--seed="):
			seed_override = int(arg.get_slice("=", 1))


## Switches to a screen by name (see SCREENS). Always unpauses and resets time scale.
func go(screen: String) -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file.call_deferred(SCREENS.get(screen, SCREENS["menu"]))


func play_level(level_number: int) -> void:
	mode = "campaign"
	level = level_number
	seed_override = -1
	go("run")


func is_dev_build() -> bool:
	return OS.is_debug_build()


func vibrate(ms: int) -> void:
	if vibration_enabled and ms > 0:
		Input.vibrate_handheld(ms)
