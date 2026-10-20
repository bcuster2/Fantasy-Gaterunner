class_name GateInfo
extends RefCounted
## Display text, colors, and scoring for gate definitions ({stat, op, value}).

const STAT_NAMES := {
	"damage": "DAMAGE",
	"fire_rate": "FIRE RATE",
	"projectiles": "SHOTS",
}
const GOOD_COLOR := Color("#3FA9FF")
const BAD_COLOR := Color("#FF4D4D")


static func is_good(gate: Dictionary) -> bool:
	var value := float(gate.get("value", 0))
	if String(gate.get("op", "add")) == "mul":
		return value > 1.0
	return value > 0.0


static func value_text(gate: Dictionary) -> String:
	var value := float(gate.get("value", 0))
	if String(gate.get("op", "add")) == "mul":
		return "x" + num(value)
	return ("+" if value >= 0.0 else "-") + num(absf(value))


static func stat_text(gate: Dictionary) -> String:
	return STAT_NAMES.get(String(gate.get("stat", "")), "???")


static func short_text(gate: Dictionary) -> String:
	return "%s %s" % [value_text(gate), stat_text(gate)]


static func color(gate: Dictionary) -> Color:
	return GOOD_COLOR if is_good(gate) else BAD_COLOR


## Ratio of DPS after/before taking the gate. Used by the autopilot and later by the simulator.
static func score(gate: Dictionary, stats: HeroStats, limits: Dictionary) -> float:
	var after := stats.copy()
	after.apply_gate(gate, limits)
	return after.dps() / maxf(stats.dps(), 0.001)


static func num(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return ("%.2f" % value).rstrip("0").rstrip(".")
