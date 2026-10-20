extends Node
## Cross-scene session state: which mode/level is being played, active hero class, dev toggles.
## Persistent data (coins, upgrades, settings) moves to SaveManager in Milestone 6.

var mode := "campaign"
var level := 1
var hero_class := "battlemage"

var god_mode := false
var vibration_enabled := true
## Set with `-- --autopilot` on the command line; a simple bot steers (used for smoke tests).
var autopilot := false


func _ready() -> void:
	autopilot = OS.get_cmdline_user_args().has("--autopilot")


func vibrate(ms: int) -> void:
	if vibration_enabled and ms > 0:
		Input.vibrate_handheld(ms)
