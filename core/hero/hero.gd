class_name Hero
extends Node3D
## The player character. Driven by Run each frame (no _process), so update order stays explicit.

signal died
signal hp_changed(hp: float, max_hp: float)

var stats: HeroStats
var target_x := 0.0
var alive := true
var radius := 0.45

var _speed := 8.0
var _half_width := 3.4
var _smoothing := 16.0
var _key_speed := 11.0
var _lean := 0.28
var _fire_cooldown := 0.0
var _flash := 0.0
var _flash_on := false
var _anim_time := 0.0
var _orb_pop := 0.0
var _model: Node3D
var _orb: MeshInstance3D
var _meshes: Array[MeshInstance3D] = []
var _hp_label: Label3D
var _ring: MeshInstance3D
## 1 = running, 0 = stopped (boss arena). Eases toward _run_target.
var _run := 1.0
var _run_target := 1.0
var _stop_time := 0.6


func setup(class_def: Dictionary) -> void:
	stats = HeroStats.from_class(class_def)
	_speed = Balance.f("hero.run_speed")
	radius = Balance.f("hero.radius")
	_half_width = Balance.f("track.width") * 0.5 - Balance.f("track.hero_margin")
	_smoothing = Balance.f("hero.steer_smoothing")
	_key_speed = Balance.f("hero.keyboard_steer_speed")
	_lean = deg_to_rad(Balance.f("hero.lean_degrees"))

	_model = Placeholders.make_hero(class_def)
	add_child(_model)
	_orb = _model.get_node("Orb")
	Placeholders.collect_meshes(_model, _meshes)
	add_child(Placeholders.blob_shadow(0.55))
	_ring = Placeholders.part(Placeholders.cylinder(0.8, 0.8, 0.03, 24), null, Vector3(0, 0.05, 0))
	add_child(_ring)

	_hp_label = Placeholders.label(64, 0.0065)
	_hp_label.position = Vector3(0, 2.45, 0)
	_hp_label.modulate = Color("#FFE9A8")
	add_child(_hp_label)
	_refresh_label()
	set_element(stats.element)


## Retints the staff orb and aura ring to the current element.
func set_element(element: String) -> void:
	var color := Content.element_color(element)
	_orb.material_override = Placeholders.mat(color, 2.5)
	_ring.visible = element != "none"
	if _ring.visible:
		_ring.material_override = Placeholders.overlay(Color(color, 0.55))
	_orb_pop = 1.5


func refresh_hp() -> void:
	_refresh_label()
	hp_changed.emit(stats.hp, stats.max_hp)


## Stops (false) or resumes (true) the forward run with a short ease.
func set_running(running: bool, ease_time := 0.6) -> void:
	_run_target = 1.0 if running else 0.0
	_stop_time = maxf(ease_time, 0.01)


func steer_by(dx_world: float) -> void:
	target_x = clampf(target_x + dx_world, -_half_width, _half_width)


func update_motion(delta: float) -> void:
	if not alive:
		return
	var keys := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		keys -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		keys += 1.0
	if keys != 0.0:
		steer_by(keys * _key_speed * delta)

	var prev_x := position.x
	position.x = lerpf(position.x, target_x, 1.0 - exp(-_smoothing * delta))
	_run = move_toward(_run, _run_target, delta / _stop_time)
	position.z -= _speed * _run * delta

	# Lean into turns and bob while running.
	var vx := (position.x - prev_x) / maxf(delta, 0.0001)
	_model.rotation.z = lerpf(_model.rotation.z, clampf(-vx * 0.06, -_lean, _lean), 1.0 - exp(-12.0 * delta))
	_anim_time += delta * lerpf(4.0, 11.0, _run)
	_model.position.y = absf(sin(_anim_time)) * 0.12
	_model.rotation.x = -0.08

	_orb_pop = maxf(0.0, _orb_pop - delta * 8.0)
	_orb.scale = Vector3.ONE * (1.0 + _orb_pop * 0.7)

	_flash = maxf(0.0, _flash - delta)
	_set_flash(_flash > 0.0)


## Returns how many volleys to fire this frame (fire_rate can exceed frame rate at low fps).
func shots_due(delta: float) -> int:
	_fire_cooldown -= delta
	var interval := 1.0 / maxf(stats.fire_rate, 0.01)
	var shots := 0
	while _fire_cooldown <= 0.0 and shots < 4:
		_fire_cooldown += interval
		shots += 1
	_fire_cooldown = maxf(_fire_cooldown, 0.0)
	return shots


func muzzle_position() -> Vector3:
	return _orb.global_position


func on_fired() -> void:
	_orb_pop = 1.0


func take_hit(amount: float) -> void:
	if not alive:
		return
	_flash = 0.12
	if not GameState.god_mode:
		stats.hp = maxf(0.0, stats.hp - amount)
	_refresh_label()
	hp_changed.emit(stats.hp, stats.max_hp)
	if stats.hp <= 0.0:
		alive = false
		died.emit()


func _refresh_label() -> void:
	_hp_label.text = str(ceili(stats.hp))


func _set_flash(on: bool) -> void:
	if on == _flash_on:
		return
	_flash_on = on
	var m: Material = Placeholders.overlay(Color(1, 0.2, 0.2, 0.75)) if on else null
	for mi in _meshes:
		mi.material_overlay = m
