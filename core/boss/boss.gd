class_name Boss
extends Node3D
## A boss at the end of the level. It only chooses attacks: each tick it may return attack orders
## from its current phase, which BossArena turns into telegraphs, waves, volleys, and adds.
## Phases change as HP drops; phases with min_level appear only at higher levels (or when enraged).

signal phase_changed(index: int)

var def: Dictionary = {}
var boss_id := ""
var display_name := ""
var max_hp := 100.0
var hp := 100.0
var element := "none"
var radius := 2.0
var hit_height := 2.5
var damage_unit := 100.0
var alive := true
var fighting := false
var phases: Array = []
var phase_index := 0

var _timer := 1.5
var _interval_mult := 1.0
var _windup_mult := 1.0
var _cursor := 0
var _rng := RandomNumberGenerator.new()
var _model: Node3D
var _meshes: Array[MeshInstance3D] = []
var _flash := 0.0
var _flash_on := false
var _anim := 0.0
var _charge := 0.0
var _base_scale := 1.0


## Phases available for a boss at this level, ordered by HP threshold (highest first).
static func active_phases(boss_def: Dictionary, level: int, enrage: bool) -> Array:
	var out: Array = []
	for phase: Dictionary in boss_def.get("phases", []):
		if enrage or level >= int(phase.get("min_level", 1)):
			out.append(phase)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("hp", 1.0)) > float(b.get("hp", 1.0)))
	if out.is_empty() and not boss_def.get("phases", []).is_empty():
		out.append(boss_def["phases"][0])
	return out


func setup(event: Dictionary, boss_def: Dictionary, modifiers: Dictionary) -> void:
	def = boss_def
	boss_id = String(event.get("boss", ""))
	display_name = String(def.get("name", boss_id.capitalize()))
	max_hp = maxf(1.0, float(event.get("hp", 100.0)))
	hp = max_hp
	element = String(event.get("element", "none"))
	damage_unit = float(event.get("damage_unit", 100.0))
	_base_scale = float(def.get("scale", 2.0))
	radius = float(def.get("radius", 1.8))
	hit_height = 1.4 * _base_scale
	var enrage := bool(event.get("enrage", false))
	phases = active_phases(def, int(event.get("level", 1)), enrage)
	if enrage:
		var mod: Dictionary = modifiers.get("boss_enrage", {})
		_interval_mult = float(mod.get("interval", 0.75))
		_windup_mult = float(mod.get("windup", 0.85))
	_rng.seed = LevelSeed.fnv1a("boss/%s/%d" % [boss_id, int(event.get("level", 1))])
	_cursor = _rng.randi_range(0, 3)

	_model = Placeholders.make_boss(def)
	_model.scale = Vector3.ONE * _base_scale
	add_child(_model)
	Placeholders.collect_meshes(_model, _meshes)
	var tint := Content.element_color(element) if element != "none" else Color("#FF5A3B")
	for mi in _meshes:
		if mi.name.begins_with("Crystal"):
			mi.material_override = Placeholders.mat(tint, 1.8)
	add_child(Placeholders.blob_shadow(radius * 1.1))
	if element != "none":
		var ring := Placeholders.part(Placeholders.cylinder(radius * 1.3, radius * 1.3, 0.04, 28), Placeholders.overlay(Color(tint, 0.55)), Vector3(0, 0.05, 0))
		add_child(ring)
		var icon := Sprite3D.new()
		icon.texture = Content.element_icon(Content.weakness_of(element))
		icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		icon.no_depth_test = true
		icon.pixel_size = 0.012
		icon.position = Vector3(0, hit_height * 2.0 + 0.8, 0)
		add_child(icon)


func start_fight() -> void:
	fighting = true
	_timer = 1.6


func current_phase() -> Dictionary:
	return phases[phase_index] if phase_index < phases.size() else {}


## Returns attack orders issued this frame (usually none).
func tick(delta: float) -> Array:
	_anim += delta
	_flash = maxf(0.0, _flash - delta)
	_set_flash(_flash > 0.0)
	_charge = maxf(0.0, _charge - delta)
	var breathe := sin(_anim * 2.2) * 0.04
	_model.scale = Vector3.ONE * _base_scale * (1.0 + breathe + _charge * 0.08)
	_model.position.y = sin(_anim * 1.6) * 0.12 if String(def.get("model", "")) == "lich" else 0.0
	if not fighting or not alive or phases.is_empty():
		return []
	_timer -= delta
	if _timer > 0.0:
		return []
	var phase := current_phase()
	var attacks: Array = phase.get("attacks", [])
	if attacks.is_empty():
		return []
	var attack: Dictionary = (attacks[_cursor % attacks.size()] as Dictionary).duplicate()
	_cursor += 1 if _rng.randf() < 0.8 else 2
	attack["windup"] = float(attack.get("windup", 1.0)) * _windup_mult
	attack["damage_abs"] = float(attack.get("damage", 0.1)) * damage_unit
	_timer = float(phase.get("interval", 2.4)) * _interval_mult
	_charge = 0.5
	return [attack]


## Returns true if this killed the boss.
func take_damage(amount: float) -> bool:
	if not alive:
		return false
	hp -= amount
	_flash = 0.06
	while phase_index + 1 < phases.size() and hp / max_hp <= float(phases[phase_index + 1].get("hp", 0.0)):
		phase_index += 1
		_timer = minf(_timer, 1.0)
		phase_changed.emit(phase_index)
	if hp <= 0.0:
		hp = 0.0
		alive = false
		fighting = false
		return true
	return false


func lane_rng() -> RandomNumberGenerator:
	return _rng


func _set_flash(on: bool) -> void:
	if on == _flash_on:
		return
	_flash_on = on
	var m: Material = Placeholders.overlay(Color(1, 1, 1, 0.6)) if on else null
	for mi in _meshes:
		mi.material_overlay = m
