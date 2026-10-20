class_name Enemy
extends Node3D
## Pooled enemy. Run calls tick(); there is no per-node _process cost.
## Behaviors (from enemies.json): walker, charger, ranged, weaver, static.

var active := false
var enemy_id := ""
var element := "none"
var behavior := "walker"
var max_hp := 1.0
var hp := 1.0
var speed := 2.0
var contact_damage := 10.0
var radius := 0.5
var coins := 1
var color := Color.WHITE
var hit_height := 0.9
var immune_unless_weak := false
var knockback_resist := 0.0
var def: Dictionary = {}
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
var _age := 0.0
var _base_x := 0.0
var _slow := 0.0
var _slow_time := 0.0
var _burn_dps := 0.0
var _burn_time := 0.0
var _shot_timer := 0.0
var _charging := false
var _body: Node3D
var _model: Node3D
var _meshes: Array[MeshInstance3D] = []
var _label: Label3D
var _ring: MeshInstance3D
var _icon: Sprite3D


func _init() -> void:
	_body = Node3D.new()
	add_child(_body)
	add_child(Placeholders.blob_shadow(0.5))
	_ring = Placeholders.part(Placeholders.cylinder(0.72, 0.72, 0.03, 20), null, Vector3(0, 0.04, 0))
	add_child(_ring)
	_label = Placeholders.label(64, 0.0075)
	add_child(_label)
	_icon = Sprite3D.new()
	_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_icon.no_depth_test = true
	_icon.render_priority = 11
	_icon.pixel_size = 0.0055
	add_child(_icon)


func spawn(id: String, enemy_def: Dictionary, hp_mult: float, pos: Vector3, element_id: String) -> void:
	def = enemy_def
	if id != enemy_id:
		_rebuild(id)
	var scale_f := float(def.get("scale", 1.0))
	max_hp = maxf(1.0, float(def.get("hp", 10)) * hp_mult)
	hp = max_hp
	behavior = String(def.get("behavior", "walker"))
	speed = float(def.get("speed", 2.0))
	contact_damage = float(def.get("contact_damage", 10))
	radius = float(def.get("radius", 0.5)) * scale_f
	coins = int(def.get("coins", 1))
	color = Color(String(def.get("color", "#FFFFFF")))
	immune_unless_weak = bool(def.get("immune_unless_weak", false))
	knockback_resist = float(def.get("knockback_resist", 0.0))
	_aggro_range = float(def.get("aggro_range", Balance.f("enemy.aggro_range")))
	_lateral = float(def.get("lateral_chase", Balance.f("enemy.lateral_chase")))
	_flash_time = Balance.f("feel.hit_flash_time")
	_shot_timer = float(def.get("shot_interval", 2.0)) * randf_range(0.5, 1.0)
	position = pos
	_base_x = pos.x
	_walk = randf() * TAU
	_age = randf() * 10.0
	_flash = 0.0
	_squash = 0.0
	_slow_time = 0.0
	_burn_time = 0.0
	_charging = false
	pending_damage = 0.0
	number_cooldown = 0.0
	_set_flash(false)
	_set_element(element_id)
	_label.position = Vector3(0, 1.55 * scale_f + 0.25, 0)
	_icon.position = Vector3(0, 1.55 * scale_f + 0.8, 0)
	_refresh_label()
	active = true
	visible = true


## Returns true if a damage-over-time effect killed the enemy this frame.
func tick(delta: float, hero_pos: Vector3) -> bool:
	_age += delta
	number_cooldown -= delta
	var ahead := hero_pos.z - position.z
	var slow_factor := 1.0 - (_slow if _slow_time > 0.0 else 0.0)
	_slow_time -= delta
	var move := speed * slow_factor * delta

	match behavior:
		"charger":
			if ahead < _aggro_range and ahead > -1.0:
				_charging = true
			if _charging:
				position.z += move
				position.x = move_toward(position.x, hero_pos.x, speed * _lateral * slow_factor * delta)
				_walk += delta * 14.0
		"weaver":
			if ahead < _aggro_range and ahead > -1.0:
				position.z += move
				_walk += delta * 10.0
			var amp := float(def.get("weave_amplitude", 1.8))
			var limit := Balance.f("track.width") * 0.5 - radius
			position.x = clampf(_base_x + sin(_age * float(def.get("weave_frequency", 1.6))) * amp, -limit, limit)
		"ranged", "static":
			_walk += delta * 2.0
		_:
			if ahead < _aggro_range and ahead > -1.0:
				position.z += move
				position.x = move_toward(position.x, hero_pos.x, speed * _lateral * slow_factor * delta)
				_walk += delta * speed * 4.0

	_animate(delta)

	if _burn_time > 0.0:
		_burn_time -= delta
		hp -= _burn_dps * delta
		_refresh_label()
		if hp <= 0.0:
			_die()
			return true
	return false


## For ranged enemies: true on the frame a shot should be released. Winds up (glows) beforehand.
func wants_shot(delta: float, hero_pos: Vector3) -> bool:
	if behavior != "ranged":
		return false
	var ahead := hero_pos.z - position.z
	if ahead > float(def.get("shot_range", 24.0)) or ahead < 3.0:
		return false
	_shot_timer -= delta
	var windup := float(def.get("shot_windup", 0.5))
	_set_flash(_shot_timer < windup or _flash > 0.0)
	if _shot_timer <= 0.0:
		_shot_timer = float(def.get("shot_interval", 2.4))
		_squash = 0.3
		return true
	return false


## Applies already-multiplied damage. Returns true if this hit killed the enemy.
func take_damage(amount: float) -> bool:
	if not active:
		return false
	hp -= amount
	_flash = _flash_time
	_squash = 0.28
	if hp <= 0.0:
		_die()
		return true
	_refresh_label()
	return false


func apply_slow(amount: float, duration: float) -> void:
	_slow = clampf(amount, 0.0, 0.9)
	_slow_time = maxf(_slow_time, duration)


func apply_burn(total_damage: float, duration: float) -> void:
	# Refresh rather than stack, keeping the stronger burn.
	var dps := total_damage / maxf(duration, 0.01)
	if _burn_time <= 0.0 or dps > _burn_dps:
		_burn_dps = dps
	_burn_time = duration


func knock_back(distance: float) -> void:
	position.z -= distance * (1.0 - knockback_resist)


func _die() -> void:
	active = false
	visible = false


func _animate(delta: float) -> void:
	var fly := float(def.get("fly_height", 0.0))
	match behavior:
		"weaver":
			_model.position.y = fly + sin(_age * 6.0) * 0.15
			_model.rotation.z = cos(_age * float(def.get("weave_frequency", 1.6))) * 0.35
		"static":
			_model.position.y = 0.0
		_:
			_model.rotation.z = sin(_walk) * 0.14
			_model.position.y = fly + absf(sin(_walk)) * 0.06
	_squash = maxf(0.0, _squash - delta * 5.0)
	_body.scale = Vector3(1.0 + _squash, 1.0 - _squash, 1.0 + _squash)
	_flash = maxf(0.0, _flash - delta)
	if behavior != "ranged":
		_set_flash(_flash > 0.0)
	# Frozen shiver while slowed.
	_model.rotation.y = sin(_age * 30.0) * 0.05 if _slow_time > 0.0 else 0.0


func _rebuild(id: String) -> void:
	enemy_id = id
	if _model:
		_model.queue_free()
	_meshes.clear()
	_model = Placeholders.make_enemy(def)
	_body.add_child(_model)
	_body.scale = Vector3.ONE
	var scale_f := float(def.get("scale", 1.0))
	_model.scale = Vector3.ONE * scale_f
	Placeholders.collect_meshes(_model, _meshes)
	hit_height = 0.9 * scale_f + float(def.get("fly_height", 0.0))


func _set_element(element_id: String) -> void:
	element = element_id if Content.elements.has(element_id) else "none"
	var has_element := element != "none"
	_ring.visible = has_element
	_icon.visible = has_element
	if has_element:
		var ring_color := Content.element_color(element)
		ring_color.a = 0.6
		_ring.material_override = Placeholders.overlay(ring_color)
		_icon.texture = Content.element_icon(Content.weakness_of(element))
	# Meshes named "Crystal*" (wards, imp horns...) glow in the enemy's element color.
	var tint := Content.element_color(element) if has_element else Color("#B9B3A3")
	for mi in _meshes:
		if mi.name.begins_with("Crystal"):
			mi.material_override = Placeholders.mat(tint, 0.7)


func _refresh_label() -> void:
	_label.text = str(ceili(maxf(hp, 0.0)))


func _set_flash(on: bool) -> void:
	if on == _flash_on:
		return
	_flash_on = on
	var m: Material = Placeholders.overlay(Color(1, 1, 1, 0.8)) if on else null
	for mi in _meshes:
		mi.material_overlay = m
