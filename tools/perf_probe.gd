extends Node
## CPU frame-time probe: plays a level (or endless) with the autopilot and reports process time per
## frame (wall clock: avg / p95 / max), node count, and live projectiles. GPU cost is measured on device.
##   godot --headless --path . --fixed-fps 60 res://tools/perf_probe.tscn -- --level=300 --seconds=60
##   godot --headless --path . --fixed-fps 60 res://tools/perf_probe.tscn -- --mode=endless --seconds=300

const RUN_SCENE := preload("res://core/run/run.tscn")

var _samples: PackedFloat32Array = []
var _frames := 0
var _target := 3600
var _run: Node
var _max_nodes := 0
var _last_us := 0
var _bucket: PackedFloat32Array = []


func _ready() -> void:
	var seconds := 60.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="):
			seconds = float(arg.get_slice("=", 1))
	_target = int(seconds * 60.0)
	GameState.autopilot = true
	GameState.fast_results = true
	_run = RUN_SCENE.instantiate()
	add_child(_run)


func _process(_delta: float) -> void:
	_frames += 1
	# Wall time between frames: with --fixed-fps in headless the loop runs flat out, so this is
	# the whole frame's CPU cost (the TIME_PROCESS monitor only refreshes once a second).
	var now := Time.get_ticks_usec()
	var ms := (now - _last_us) / 1000.0
	_last_us = now
	if _frames > 30:
		_samples.append(ms)
		_bucket.append(ms)
		if _bucket.size() >= 3600:
			var sum := 0.0
			for v: float in _bucket:
				sum += v
			print("[perf] minute %d avg %.2f ms, nodes %d" % [_frames / 3600, sum / _bucket.size(), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
			_bucket.clear()
		_max_nodes = maxi(_max_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	var done: bool = _frames >= _target or (_run != null and bool(_run.get("_ended")))
	if done:
		var sorted := Array(_samples)
		sorted.sort()
		var total := 0.0
		for v: float in sorted:
			total += v
		var n := maxi(sorted.size(), 1)
		print("[perf] mode %s level %d frames %d | process ms avg %.2f p95 %.2f max %.2f | max nodes %d" % [GameState.mode, GameState.level,
			sorted.size(), total / n, float(sorted[int(n * 0.95)]) if not sorted.is_empty() else 0.0, float(sorted[-1]) if not sorted.is_empty() else 0.0, _max_nodes])
		get_tree().quit()
