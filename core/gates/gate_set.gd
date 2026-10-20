class_name GateSet
extends Node3D
## A row of 2-3 gate panels spanning the track. Run detects the crossing and calls trigger().

const GATE_SHADER := preload("res://core/shaders/gate.gdshader")

var gates: Array = []
var triggered := false

var _width := 8.0
var _panel_width := 4.0
var _materials: Array[ShaderMaterial] = []
var _panels: Array[Node3D] = []


func setup(gate_list: Array, track_width: float) -> void:
	gates = gate_list
	_width = track_width
	var count := gates.size()
	_panel_width = _width / count
	var height := Balance.f("gates.panel_height")

	for k in count:
		var gate: Dictionary = gates[k]
		var panel := Node3D.new()
		panel.position = Vector3(lane_center(k), 0, 0)
		add_child(panel)
		_panels.append(panel)

		var quad := QuadMesh.new()
		quad.size = Vector2(_panel_width - 0.22, height)
		var material := ShaderMaterial.new()
		material.shader = GATE_SHADER
		material.set_shader_parameter("tint", GateInfo.color(gate))
		_materials.append(material)
		var pane := MeshInstance3D.new()
		pane.mesh = quad
		pane.material_override = material
		pane.position.y = height * 0.5
		pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		panel.add_child(pane)

		var value := _make_text(GateInfo.value_text(gate), 150, height * 0.66)
		var stat := _make_text(GateInfo.stat_text(gate), 70, height * 0.33)
		panel.add_child(value)
		panel.add_child(stat)

	# Posts between and at the edges of panels.
	var post_mat := Placeholders.mat(Color("#D9D2C3"))
	for k in count + 1:
		var x := -_width * 0.5 + _panel_width * k
		add_child(Placeholders.part(Placeholders.box(Vector3(0.24, height + 0.35, 0.24)), post_mat, Vector3(x, (height + 0.35) * 0.5, 0)))
		add_child(Placeholders.part(Placeholders.sphere(0.2), Placeholders.mat(Placeholders.GOLD, 0.6), Vector3(x, height + 0.5, 0)))


func lane_center(lane: int) -> float:
	return -_width * 0.5 + _panel_width * (lane + 0.5)


func lane_at(x: float) -> int:
	return clampi(int(floor((x + _width * 0.5) / _panel_width)), 0, gates.size() - 1)


func trigger(lane: int) -> void:
	triggered = true
	var fade := Balance.f("gates.fade_time")
	for k in _panels.size():
		var panel := _panels[k]
		var material := _materials[k]
		var tween := create_tween().set_parallel()
		if k == lane:
			material.set_shader_parameter("flash", 1.0)
			tween.tween_property(panel, "scale", Vector3(1.25, 1.2, 1.0), fade).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_method(func(v: float) -> void: material.set_shader_parameter("flash", v), 1.0, 0.0, fade)
			tween.tween_method(func(v: float) -> void: material.set_shader_parameter("alpha_mul", v), 1.0, 0.0, fade * 1.5)
		else:
			tween.tween_property(panel, "position:y", -3.5, fade * 1.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tween.tween_method(func(v: float) -> void: material.set_shader_parameter("alpha_mul", v), 1.0, 0.25, fade)
		for child in panel.get_children():
			if child is Label3D:
				tween.tween_property(child, "modulate:a", 0.0, fade * 1.2)
				tween.tween_property(child, "outline_modulate:a", 0.0, fade * 1.2)
	get_tree().create_timer(2.0).timeout.connect(queue_free)


func _make_text(text: String, font_size: int, y: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	# Shrink to fit narrow panels (three-gate rows).
	var estimated_px := maxf(1.0, text.length() * 0.62 * font_size)
	l.pixel_size = minf(0.0075, (_panel_width - 0.5) / estimated_px)
	l.position = Vector3(0, y, 0.06)
	l.no_depth_test = true
	l.outline_size = 18
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.render_priority = 6
	l.outline_render_priority = 5
	return l
