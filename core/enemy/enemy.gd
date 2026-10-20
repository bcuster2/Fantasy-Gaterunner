class_name Enemy
extends Node3D
## Pooled enemy. Run calls tick(); there is no per-node _process cost.

var active := false
var enemy_id := ""
var max_hp := 1.0
var hp := 1.0
var speed := 2.0
var contact_damage := 10.0
var radius := 0.5
var coins := 1
var color := Color.WHITE
var hit_height := 0.9
## Damage accumulated since the last floating number (numbers are throttled per enemy).
var pending_damage := 0.0
var number_cooldown := 0.0

var _aggro_range := 24.0
var _lateral := 0.35
var _flash_time := 0.07
var _flash := 0.0
var _flash_on := false
var _squash := 0.0
var _walk := 0.0
var _body: Node3D
var _model: Node3D
var _meshes: Array[MeshInstance3D] = []
var _label: Label3D


func _init() -> void:
	_body = Node3D.new()
	add_child(_body)
	add_child(Placeholders.blob_shadow(0.5))
	_label = Placeholders.label(64, 0.0075)
	_label.position = Vector3(0, 1.75, 0)
	add_child(_label)


func spawn(id: String, def: Dictionary, hp_mult: float, pos: Vector3) -> void:
	if id != enemy_id:
		_rebuild(id, def)
	max_hp = maxf(1.0, float(def.get("hp", 10)) * hp_mult)
	hp = max_hp
	speed = float(def.get("speed", 2.0))
	contact_damage = float(def.get("contact_damage", 10))
	radius = float(def.get("radius", 0.5)) * float(def.get("scale", 1.0))
	coins = int(def.get("coins", 1))
	color = Color(String(def.get("color", "#FFFFFF")))
	_aggro_range = Balance.f("enemy.aggro_range")
	_lateral = Balance.f("enemy.lateral_chase")
	_flash_time = Balance.f("feel.hit_flash_time")
	position = pos
	_walk = randf() * TAU
	_flash = 0.0
	_squash = 0.0
	pending_damage = 0.0
	number_cooldown = 0.0
	_set_flash(false)
	_label.text = str(ceili(hp))
	active = true
	visible = true


func tick(delta: float, hero_pos: Vector3) -> void:
	var ahead := hero_pos.z - position.z
	if ahead < _aggro_range and ahead > -1.0:
		position.z += speed * delta
		position.x = move_toward(position.x, hero_pos.x, speed * _lateral * delta)
		_walk += delta * speed * 4.0
	_model.rotation.z = sin(_walk) * 0.14
	_model.position.y = absf(sin(_walk)) * 0.06

	number_cooldown -= delta
	_squash = maxf(0.0, _squash - delta * 5.0)
	_body.scale = Vector3(1.0 + _squash, 1.0 - _squash, 1.0 + _squash)
	_flash = maxf(0.0, _flash - delta)
	_set_flash(_flash > 0.0)


## Returns true if this hit killed the enemy.
func take_damage(amount: float) -> bool:
	if not active:
		return false
	hp -= amount
	_flash = _flash_time
	_squash = 0.28
	if hp <= 0.0:
		active = false
		visible = false
		return true
	_label.text = str(ceili(hp))
	return false


func _rebuild(id: String, def: Dictionary) -> void:
	enemy_id = id
	if _model:
		_model.queue_free()
	_meshes.clear()
	_model = Placeholders.make_enemy(def)
	_body.add_child(_model)
	_body.scale = Vector3.ONE
	_model.scale = Vector3.ONE * float(def.get("scale", 1.0))
	Placeholders.collect_meshes(_model, _meshes)
	hit_height = 0.9 * float(def.get("scale", 1.0))


func _set_flash(on: bool) -> void:
	if on == _flash_on:
		return
	_flash_on = on
	var m: Material = Placeholders.overlay(Color(1, 1, 1, 0.8)) if on else null
	for mi in _meshes:
		mi.material_overlay = m
