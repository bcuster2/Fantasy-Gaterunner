extends Screen
## Title screen: play (level map), modes, upgrades, settings.

var _gates: Array[Control] = []
var _time := 0.0


func build() -> void:
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_END
	top.add_child(coin_chip())
	content.add_child(top)

	content.add_child(spacer())
	var art := Control.new()
	art.custom_minimum_size = Vector2(0, 260)
	content.add_child(art)
	for k in 3:
		var gate := Panel.new()
		var tint: Color = [Color("#3FA9FF"), Color("#A24DFF"), Color("#2FD39A")][k]
		var style := UiTheme.box(Color(tint, 0.35), 18, 0)
		style.border_color = tint.lightened(0.3)
		style.set_border_width_all(6)
		gate.add_theme_stylebox_override("panel", style)
		gate.size = Vector2(170, 230)
		gate.position = Vector2(170 + k * 230, 10)
		gate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.add_child(gate)
		_gates.append(gate)

	var title := label("FANTASY\nGATERUNNER", 112, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("outline_size", 22)
	title.add_theme_color_override("font_outline_color", Color("#5A2A00"))
	content.add_child(title)
	var tagline := label("Endless levels. Endless builds.", 40, Color(1, 1, 1, 0.75))
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(tagline)
	content.add_child(spacer())

	var level := SaveManager.unlocked_level()
	content.add_child(button("PLAY  ·  LEVEL %d" % level, func() -> void: GameState.go("map"), Color("#E67E22"), Vector2(0, 170)))
	content.add_child(button("GAME MODES", func() -> void: GameState.go("modes")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	content.add_child(row)
	var shop := button("UPGRADES", func() -> void:
		GameState.return_screen = "menu"
		GameState.go("shop"), Color("#27AE60"))
	shop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(shop)
	var settings := button("SETTINGS", func() -> void:
		GameState.return_screen = "menu"
		GameState.go("settings"), Color("#5D6D7E"))
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(settings)


func _process(delta: float) -> void:
	_time += delta
	for k in _gates.size():
		_gates[k].position.y = 10.0 + sin(_time * 1.6 + k * 1.3) * 12.0
