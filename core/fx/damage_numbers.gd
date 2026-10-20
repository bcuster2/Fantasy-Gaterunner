class_name DamageNumbers
extends Node3D
## Pooled floating text (ring buffer: when all labels are busy the oldest is reused).

const POOL_SIZE := 48

var _labels: Array[Label3D] = []
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _scale := PackedFloat32Array()
var _velocity := PackedVector3Array()
var _next := 0
var _default_life := 0.65
var _rise := 1.6


func setup() -> void:
	_default_life = Balance.f("feel.damage_number_time")
	_rise = Balance.f("feel.damage_number_rise")
	_age.resize(POOL_SIZE)
	_life.resize(POOL_SIZE)
	_scale.resize(POOL_SIZE)
	_velocity.resize(POOL_SIZE)
	for i in POOL_SIZE:
		var l := Placeholders.label(72, 0.006)
		l.visible = false
		l.render_priority = 20
		l.outline_render_priority = 19
		add_child(l)
		_labels.append(l)
		_life[i] = 0.0


func pop(at: Vector3, text: String, color: Color, size := 1.0, life := -1.0) -> void:
	var i := _next
	_next = (_next + 1) % POOL_SIZE
	var l := _labels[i]
	l.text = text
	l.modulate = color
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.position = at
	l.visible = true
	_age[i] = 0.0
	_life[i] = life if life > 0.0 else _default_life
	_scale[i] = size
	_velocity[i] = Vector3(randf_range(-0.6, 0.6), _rise * 2.2, 0.0)


func tick(delta: float) -> void:
	for i in POOL_SIZE:
		if _life[i] <= 0.0:
			continue
		_age[i] += delta
		var t := _age[i] / _life[i]
		var l := _labels[i]
		if t >= 1.0:
			_life[i] = 0.0
			l.visible = false
			continue
		_velocity[i] *= 1.0 - minf(1.0, 5.0 * delta)
		l.position += _velocity[i] * delta
		# Pop in big, settle, then fade.
		var punch := 1.0 + 0.6 * maxf(0.0, 1.0 - t * 6.0)
		l.scale = Vector3.ONE * _scale[i] * punch
		var alpha := clampf((1.0 - t) / 0.4, 0.0, 1.0)
		l.modulate.a = alpha
		l.outline_modulate.a = alpha * 0.9
