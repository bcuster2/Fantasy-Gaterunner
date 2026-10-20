class_name CameraRig
extends Camera3D
## Chase camera with trauma-based screen shake (shake = trauma^2, so small hits stay subtle).

var _trauma := 0.0
var _time := 0.0
var _x := 0.0
var _noise := FastNoiseLite.new()
var _height := 9.0
var _back := 7.5
var _ahead := 10.0
var _follow_x := 0.55
var _max_offset := 0.5
var _max_roll := 0.04
var _decay := 2.4


func setup() -> void:
	keep_aspect = Camera3D.KEEP_WIDTH
	fov = Balance.f("feel.camera_fov")
	_height = Balance.f("feel.camera_height")
	_back = Balance.f("feel.camera_back")
	_ahead = Balance.f("feel.camera_look_ahead")
	_follow_x = Balance.f("feel.camera_follow_x")
	_max_offset = Balance.f("feel.shake_max_offset")
	_max_roll = deg_to_rad(Balance.f("feel.shake_max_roll_degrees"))
	_decay = Balance.f("feel.shake_decay")
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 0.6
	near = 0.3
	far = 220.0
	current = true


func add_trauma(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)


func follow(target: Vector3, delta: float) -> void:
	_time += delta * 30.0
	_x = lerpf(_x, target.x * _follow_x, 1.0 - exp(-8.0 * delta))
	position = Vector3(_x, _height, target.z + _back)
	look_at(Vector3(_x * 0.6, 0.4, target.z - _ahead), Vector3.UP)

	var shake := _trauma * _trauma
	h_offset = _max_offset * shake * _noise.get_noise_2d(_time, 0.0)
	v_offset = _max_offset * shake * _noise.get_noise_2d(0.0, _time)
	rotate_object_local(Vector3.FORWARD, _max_roll * shake * _noise.get_noise_2d(_time, 50.0))
	_trauma = maxf(0.0, _trauma - _decay * delta)
