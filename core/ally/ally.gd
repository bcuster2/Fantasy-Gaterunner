class_name Ally
extends Node3D
## A summoned unit running in formation with the hero. Pooled and driven by Squad.

var active := false
var ally_id := ""
var def: Dictionary = {}
var kind := "melee"
var row := "front"
var max_hp := 1.0
var hp := 1.0
var damage := 1.0
var attack_rate := 1.0
var attack_range := 1.5
var contact_damage := 1.0
var radius := 0.4
## Formation offset from the hero: (x, z). Negative z is ahead of the hero.
var slot := Vector2.ZERO

var _cooldown := 0.0
var _flash := 0.0
var _flash_on := false
var _swing := 0.0
var _anim := 0.0
var _pop := 0.0
var _body: Node3D
var _model: Node3D
var _meshes: Array[MeshInstance3D] = []


func _init() -> void:
	_body = Node3D.new()
	add_child(_body)
	add_child(Placeholders.blob_shadow(0.45))


func spawn(id: String, ally_def: Dictionary, at: Vector3, power_mult := 1.0) -> void:
	def = ally_def
	if id != ally_id:
		ally_id = id
		if _model:
			_model.queue_free()
		_meshes.clear()
		_model = Placeholders.make_ally(def)
		_model.scale = Vector3.ONE * float(def.get("scale", 1.0))
		_body.add_child(_model)
		Placeholders.collect_meshes(_model, _meshes)
	kind = String(def.get("kind", "melee"))
	row = String(def.get("row", "front"))
	max_hp = float(def.get("hp", 20)) * power_mult
	hp = max_hp
	damage = float(def.get("damage", 5)) * power_mult
	attack_rate = float(def.get("attack_rate", 1.0))
	attack_range = float(def.get("range", 1.5))
	contact_damage = float(def.get("contact_damage", 5)) * power_mult
	radius = float(def.get("radius", 0.4)) * float(def.get("scale", 1.0))
	position = at
	_cooldown = randf() / maxf(attack_rate, 0.01)
	_anim = randf() * TAU
	_pop = 1.0
	_flash = 0.0
	_set_flash(false)
	active = true
	visible = true


func set_element_tint(color: Color) -> void:
	for mi in _meshes:
		if mi.name.begins_with("Crystal"):
			mi.material_override = Placeholders.mat(color, 2.0)


func follow(delta: float, hero_pos: Vector3, half_width: float, smoothing: float) -> void:
	var target_x := clampf(hero_pos.x + slot.x, -half_width, half_width)
	position.x = lerpf(position.x, target_x, 1.0 - exp(-smoothing * delta))
	position.z = lerpf(position.z, hero_pos.z + slot.y, 1.0 - exp(-smoothing * 1.5 * delta))
	_anim += delta * 11.0
	_cooldown -= delta
	_swing = maxf(0.0, _swing - delta * 5.0)
	_pop = maxf(0.0, _pop - delta * 3.0)
	_body.scale = Vector3.ONE * (1.0 - _pop * _pop)
	_model.position.y = absf(sin(_anim)) * 0.1
	_model.rotation.x = -_swing * 0.6
	_flash = maxf(0.0, _flash - delta)
	_set_flash(_flash > 0.0)


func attack_ready() -> bool:
	return _cooldown <= 0.0


func on_attacked() -> void:
	_cooldown = 1.0 / maxf(attack_rate, 0.01)
	_swing = 1.0


## Returns true if the ally died.
func take_damage(amount: float) -> bool:
	hp -= amount
	_flash = 0.1
	if hp <= 0.0:
		active = false
		visible = false
		return true
	return false


func _set_flash(on: bool) -> void:
	if on == _flash_on:
		return
	_flash_on = on
	var m: Material = Placeholders.overlay(Color(1, 0.25, 0.25, 0.7)) if on else null
	for mi in _meshes:
		mi.material_overlay = m
