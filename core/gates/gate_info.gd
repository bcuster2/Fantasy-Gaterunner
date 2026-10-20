class_name GateInfo
extends RefCounted
## Display text, colors, and classification for gate definitions.
## Kinds: "stat" {stat, op, value} | "element" {element} | "summon" {ally, count} | "curse" {effects: [...]}.

const STAT_NAMES := {
	"damage": "DAMAGE",
	"fire_rate": "FIRE RATE",
	"projectiles": "SHOTS",
	"hp": "HP",
	"max_hp": "MAX HP",
	"hp_pct": "HP",
	"allies_pct": "ALLIES",
}
const GOOD_COLOR := Color("#3FA9FF")
const BAD_COLOR := Color("#FF4D4D")
const SUMMON_COLOR := Color("#2FD39A")
const CURSE_COLOR := Color("#A24DFF")


static func kind(gate: Dictionary) -> String:
	return String(gate.get("kind", "stat"))


## "good" | "bad" | "curse" | "element" | "summon". Fairness rules treat only "bad" as harmful.
static func category(gate: Dictionary) -> String:
	match kind(gate):
		"element", "summon", "curse":
			return kind(gate)
	return "good" if is_good(gate) else "bad"


static func is_good(gate: Dictionary) -> bool:
	match kind(gate):
		"element", "summon":
			return true
		"curse":
			return false
	return effect_is_good(gate)


static func effect_is_good(effect: Dictionary) -> bool:
	var value := float(effect.get("value", 0))
	if String(effect.get("op", "add")) == "mul":
		return value > 1.0
	return value > 0.0


static func color(gate: Dictionary) -> Color:
	match kind(gate):
		"element":
			return Content.element_color(String(gate.get("element", "")))
		"summon":
			return SUMMON_COLOR
		"curse":
			return CURSE_COLOR
	return GOOD_COLOR if is_good(gate) else BAD_COLOR


## Big top line on the gate panel.
static func value_text(gate: Dictionary) -> String:
	match kind(gate):
		"element":
			return Content.element_name(String(gate.get("element", "")))
		"summon":
			return "+%d" % int(gate.get("count", 1))
		"curse":
			var gains: PackedStringArray = []
			for effect: Dictionary in gate.get("effects", []):
				if effect_is_good(effect):
					gains.append(effect_text(effect))
			return "\n".join(gains)
	return _effect_value(gate)


## Smaller second line on the gate panel.
static func stat_text(gate: Dictionary) -> String:
	match kind(gate):
		"element":
			return "ELEMENT"
		"summon":
			var def := Content.ally(String(gate.get("ally", "")))
			var count := int(gate.get("count", 1))
			return String(def.get("plural" if count > 1 else "name", "ALLY")).to_upper()
		"curse":
			var costs: PackedStringArray = []
			for effect: Dictionary in gate.get("effects", []):
				if not effect_is_good(effect):
					costs.append(effect_text(effect))
			return "\n".join(costs)
	return STAT_NAMES.get(String(gate.get("stat", "")), "???")


## One-line summary used for the floating pickup text.
static func short_text(gate: Dictionary) -> String:
	match kind(gate):
		"element":
			return value_text(gate) + "!"
		"curse":
			var parts: PackedStringArray = []
			for effect: Dictionary in gate.get("effects", []):
				parts.append(effect_text(effect))
			return "  ".join(parts)
	return "%s %s" % [value_text(gate), stat_text(gate)]


static func effect_text(effect: Dictionary) -> String:
	return "%s %s" % [_effect_value(effect), STAT_NAMES.get(String(effect.get("stat", "")), "???")]


static func _effect_value(effect: Dictionary) -> String:
	var value := float(effect.get("value", 0))
	var stat := String(effect.get("stat", ""))
	if String(effect.get("op", "add")) == "mul":
		return "x" + num(value)
	var sign_text := "+" if value >= 0.0 else "-"
	var suffix := "%" if stat.ends_with("_pct") else ""
	return sign_text + num(absf(value)) + suffix


static func num(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return ("%.2f" % value).rstrip("0").rstrip(".")
