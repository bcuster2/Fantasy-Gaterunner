class_name ProjectileSystem
extends MultiMeshInstance3D
## All hero projectiles as packed data drawn with one MultiMesh (one draw call). Acts as the
## projectile pool: spawning reuses slots, removal swaps the last live slot into the hole.

signal hit(enemy: Enemy, damage: float, at: Vector3)

## Rotates the Y-aligned capsule mesh onto -Z so Basis.looking_at() points it along travel.
const MESH_ALIGN := Basis(Vector3.RIGHT, -PI * 0.5)

var _max := 400
var _speed := 34.0
var _range := 30.0
var _radius := 0.25
var _count := 0
var _pos := PackedVector3Array()
var _dir := PackedVector3Array()
var _left := PackedFloat32Array()
var _dmg := PackedFloat32Array()
var _basis: Array[Basis] = []


func setup(color: Color) -> void:
	_max = Balance.i("combat.max_live_projectiles")
	_speed = Balance.f("combat.projectile_speed")
	_range = Balance.f("combat.projectile_range")
	_radius = Balance.f("combat.projectile_radius")
	_pos.resize(_max)
	_dir.resize(_max)
	_left.resize(_max)
	_dmg.resize(_max)
	_basis.resize(_max)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = Placeholders.capsule(0.15, 0.85)
	mm.instance_count = _max
	mm.visible_instance_count = 0
	mm.custom_aabb = AABB(Vector3(-50, -10, -100000), Vector3(100, 40, 200000))
	multimesh = mm
	material_override = Placeholders.mat(color, 1.4)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func spawn(origin: Vector3, direction: Vector3, damage: float) -> void:
	if _count >= _max:
		return
	_pos[_count] = origin
	_dir[_count] = direction
	_left[_count] = _range
	_dmg[_count] = damage
	_basis[_count] = Basis.looking_at(direction) * MESH_ALIGN
	_count += 1


func tick(delta: float, enemies: Array[Enemy]) -> void:
	var step := _speed * delta
	var i := 0
	while i < _count:
		var p := _pos[i] + _dir[i] * step
		_left[i] -= step
		var consumed := _left[i] <= 0.0
		if not consumed:
			for e in enemies:
				if not e.active:
					continue
				var dx := p.x - e.position.x
				var dz := p.z - e.position.z
				var r := _radius + e.radius
				if dx * dx + dz * dz < r * r:
					consumed = true
					hit.emit(e, _dmg[i], Vector3(p.x, e.hit_height, p.z))
					break
		if consumed:
			_remove(i)
			continue
		_pos[i] = p
		i += 1

	var mm := multimesh
	for k in _count:
		mm.set_instance_transform(k, Transform3D(_basis[k], _pos[k]))
	mm.visible_instance_count = _count


func _remove(i: int) -> void:
	_count -= 1
	if i != _count:
		_pos[i] = _pos[_count]
		_dir[i] = _dir[_count]
		_left[i] = _left[_count]
		_dmg[i] = _dmg[_count]
		_basis[i] = _basis[_count]
