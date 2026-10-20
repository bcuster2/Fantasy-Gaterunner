class_name EnemyShots
extends MultiMeshInstance3D
## Hostile projectiles (archer arrows/bolts) as packed data in one MultiMesh. They fly along a
## fixed line toward where the hero was, so steering out of the way dodges them.

signal hit_hero(damage: float, at: Vector3)
signal hit_ally(ally: Ally, damage: float)

const MAX_SHOTS := 64

var _count := 0
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _life := PackedFloat32Array()
var _dmg := PackedFloat32Array()
var _color: Array[Color] = []
var _radius := 0.35
var _spin := 0.0


func setup() -> void:
	_radius = Balance.f("enemy.enemy_shot_radius")
	_pos.resize(MAX_SHOTS)
	_vel.resize(MAX_SHOTS)
	_life.resize(MAX_SHOTS)
	_dmg.resize(MAX_SHOTS)
	_color.resize(MAX_SHOTS)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = Placeholders.crystal_mesh()
	mm.instance_count = MAX_SHOTS
	mm.visible_instance_count = 0
	mm.custom_aabb = AABB(Vector3(-50, -10, -100000), Vector3(100, 40, 200000))
	multimesh = mm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func spawn(origin: Vector3, target: Vector3, speed: float, damage: float, color: Color, max_range: float) -> void:
	if _count >= MAX_SHOTS:
		return
	var dir := Vector3(target.x - origin.x, 0, target.z - origin.z).normalized()
	_pos[_count] = origin
	_vel[_count] = dir * speed
	_life[_count] = (max_range + 6.0) / maxf(speed, 0.1)
	_dmg[_count] = damage
	_color[_count] = color
	_count += 1


func clear() -> void:
	_count = 0
	multimesh.visible_instance_count = 0


func tick(delta: float, hero: Hero, allies: Array[Ally]) -> void:
	_spin += delta * 12.0
	var i := 0
	while i < _count:
		_pos[i] += _vel[i] * delta
		_life[i] -= delta
		var p := _pos[i]
		var consumed := _life[i] <= 0.0
		if not consumed and hero.alive:
			var r := _radius + hero.radius
			if Vector2(p.x - hero.position.x, p.z - hero.position.z).length_squared() < r * r:
				hit_hero.emit(_dmg[i], p)
				consumed = true
		if not consumed:
			for a in allies:
				if not a.active:
					continue
				var ar := _radius + a.radius
				if Vector2(p.x - a.position.x, p.z - a.position.z).length_squared() < ar * ar:
					hit_ally.emit(a, _dmg[i])
					consumed = true
					break
		if consumed:
			_count -= 1
			_pos[i] = _pos[_count]
			_vel[i] = _vel[_count]
			_life[i] = _life[_count]
			_dmg[i] = _dmg[_count]
			_color[i] = _color[_count]
			continue
		i += 1
	var mm := multimesh
	var basis := Basis(Vector3.UP, _spin).scaled(Vector3(0.45, 0.45, 0.45))
	for k in _count:
		mm.set_instance_transform(k, Transform3D(basis, _pos[k]))
		mm.set_instance_color(k, _color[k])
	mm.visible_instance_count = _count
