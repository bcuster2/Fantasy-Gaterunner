extends Node
## Cross-scene session state: which mode/level is being played, active hero class, dev toggles.
## Persistent data (coins, upgrades, settings) moves to SaveManager in Milestone 6.
##
## Command line (after `--`): --level=N  --seed=S  --autopilot  --overlay  --god

var mode := "campaign"
var level := 1
## Debug: a custom seed for the current level (-1 = the level's canonical seed).
var seed_override := -1
var hero_class := "battlemage"
## Placeholder wallet until the economy lands in Milestone 6 (debug "grant coins" adds here).
var coins := 0

var god_mode := false
var vibration_enabled := true
## Debug: draws generator segments/roles on the track and plan stats on screen.
var debug_overlay := false
## Until the shop exists (Milestone 6) the hero gets the generator's expected upgrade level so
## generated levels play at their intended difficulty.
var assume_upgrades := true
## Set with `-- --autopilot` on the command line; a simple bot steers (used for smoke tests).
var autopilot := false
## Debug: open the dev menu as soon as a run starts (`--open-debug`, handy for screenshots).
var open_debug_menu := false
## Tools: skip slow-motion/hit-stop so headless harnesses get results immediately.
var fast_results := false


func _ready() -> void:
	assume_upgrades = bool(Balance.get_value("generator.debug_assume_upgrades", true))
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
		elif arg.begins_with("--seed="):
			seed_override = int(arg.get_slice("=", 1))


func is_dev_build() -> bool:
	return OS.is_debug_build()


func vibrate(ms: int) -> void:
	if vibration_enabled and ms > 0:
		Input.vibrate_handheld(ms)
