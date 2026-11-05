class_name CoinShower
extends MultiMeshInstance3D
## Coin pickups: kills burst into spinning coins that hop, then home in on the hero and pay out
## when they arrive. All coins in one MultiMesh (one draw call). Anything still flying when the
## run ends is paid out by collect_all(), so no coin is ever lost.

signal collected(value: int, at: Vector3)

const MAX := 160
const HOP_TIME := 0.32

var _count := 0
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _age := PackedFloat32Array()
var _value := PackedInt32Array()


func setup() -> void:
	_pos.resize(MAX)
	_vel.resize(MAX)
	_age.resize(MAX)
	_value.resize(MAX)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = Placeholders.cylinder(0.27, 0.27, 0.07, 12)
	mm.instance_count = MAX
	mm.visible_instance_count = 0
	mm.custom_aabb = AABB(Vector3(-50, -10, -100000), Vector3(100, 40, 200000))
	multimesh = mm
	material_override = Placeholders.mat(Color("#FFC93C"), 0.6)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Splits `value` coins into a few pieces flying out of `at`.
func spawn(at: Vector3, value: int, pieces := -1) -> void:
	if value <= 0:
		return
	var n := clampi(value if pieces < 0 else pieces, 1, 8 if pieces < 0 else 40)
	var each := value / n
	var extra := value - each * n
	for k in n:
		if _count >= MAX:
			# Pool full: pay the rest straight away rather than dropping it.
			collected.emit(each * (n - k) + extra, at)
			return
		_pos[_count] = at + Vector3(randf_range(-0.3, 0.3), 0.6, randf_range(-0.3, 0.3))
		_vel[_count] = Vector3(randf_range(-3.0, 3.0), randf_range(5.0, 8.0), randf_range(-2.0, 2.0))
		_age[_count] = randf_range(0.0, 0.08)
		_value[_count] = each + (extra if k == 0 else 0)
		_count += 1


func tick(delta: float, target: Vector3) -> void:
	var goal := target + Vector3(0, 1.0, 0)
	var i := 0
	while i < _count:
		_age[i] += delta
		var p := _pos[i]
		var v := _vel[i]
		if _age[i] < HOP_TIME:
			v.y -= 22.0 * delta
		else:
			var to := goal - p
			var speed := 10.0 + (_age[i] - HOP_TIME) * 40.0
			v = v.lerp(to.normalized() * speed, minf(1.0, 8.0 * delta))
		p += v * delta
		if p.y < 0.2:
			p.y = 0.2
			v.y = absf(v.y) * 0.4
		if _age[i] > HOP_TIME and p.distance_to(goal) < 0.8:
			collected.emit(_value[i], p)
			_remove(i)
			continue
		_pos[i] = p
		_vel[i] = v
		i += 1
	var mm := multimesh
	for k in _count:
		var basis := Basis(Vector3.UP, _age[k] * 9.0 + k) * Basis(Vector3.RIGHT, PI * 0.5)
		mm.set_instance_transform(k, Transform3D(basis, _pos[k]))
	mm.visible_instance_count = _count


func collect_all() -> int:
	var total := 0
	for k in _count:
		total += _value[k]
	_count = 0
	multimesh.visible_instance_count = 0
	return total


func _remove(i: int) -> void:
	_count -= 1
	if i != _count:
		_pos[i] = _pos[_count]
		_vel[i] = _vel[_count]
		_age[i] = _age[_count]
		_value[i] = _value[_count]
