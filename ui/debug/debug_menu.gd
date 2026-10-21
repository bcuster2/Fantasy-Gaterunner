class_name DebugMenu
extends CanvasLayer
## Dev-build-only menu (Run adds it only when OS.is_debug_build()): jump to any level, play any
## seed, god mode, grant coins, generator overlay, and generator stats for the current plan.

var _plan: Dictionary = {}
var _panel: PanelContainer
var _info: Label
var _level_box: SpinBox
var _seed_edit: LineEdit
var _was_paused := false


func setup(plan: Dictionary) -> void:
	_plan = plan
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.get_theme()
	add_child(root)

	var toggle := Button.new()
	toggle.text = "DBG"
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.add_theme_font_size_override("font_size", 30)
	toggle.add_theme_stylebox_override("normal", UiTheme.box(Color(0.6, 0.1, 0.6, 0.75), 18, 10))
	toggle.anchor_left = 1.0
	toggle.anchor_right = 1.0
	toggle.offset_left = -150
	toggle.offset_right = -32
	toggle.offset_top = 440
	toggle.offset_bottom = 510
	toggle.pressed.connect(_toggle)
	root.add_child(toggle)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(940, 0)
	_panel.visible = false
	center.add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	_panel.add_child(col)

	var title := Label.new()
	title.text = "DEV MENU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	col.add_child(title)

	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 28)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_info)

	var level_row := _row(col)
	level_row.add_child(_label("Level"))
	_level_box = SpinBox.new()
	_level_box.min_value = 0
	_level_box.max_value = 100000
	_level_box.value = maxi(0, int(plan.get("level", 1)))
	_level_box.custom_minimum_size = Vector2(260, 90)
	_level_box.get_line_edit().add_theme_font_size_override("font_size", 40)
	level_row.add_child(_level_box)
	level_row.add_child(_button("GO", func() -> void: _play(int(_level_box.value), -1)))
	var jump_row := _row(col)
	for step: int in [-10, -1, 1, 10, 100]:
		jump_row.add_child(_button("%+d" % step, func() -> void: _play(maxi(1, int(_plan.get("level", 1)) + step), -1)))

	var seed_row := _row(col)
	seed_row.add_child(_label("Seed"))
	_seed_edit = LineEdit.new()
	_seed_edit.text = str(plan.get("seed", 0))
	_seed_edit.custom_minimum_size = Vector2(320, 90)
	_seed_edit.add_theme_font_size_override("font_size", 36)
	seed_row.add_child(_seed_edit)
	seed_row.add_child(_button("PLAY", func() -> void: _play(maxi(1, int(_level_box.value)), int(_seed_edit.text))))
	seed_row.add_child(_button("RND", func() -> void: _play(maxi(1, int(_level_box.value)), randi() & 0x7FFFFFFF)))

	col.add_child(_check("God mode", GameState.god_mode, func(on: bool) -> void: GameState.god_mode = on))
	col.add_child(_check("Generator overlay (restarts)", GameState.debug_overlay, func(on: bool) -> void:
		GameState.debug_overlay = on
		_play(int(_plan.get("level", 1)), GameState.seed_override)))
	col.add_child(_check("Assume expected upgrades (restarts)", GameState.assume_upgrades, func(on: bool) -> void:
		GameState.assume_upgrades = on
		_play(int(_plan.get("level", 1)), GameState.seed_override)))
	col.add_child(_check("Autopilot", GameState.autopilot, func(on: bool) -> void: GameState.autopilot = on))

	var misc_row := _row(col)
	misc_row.add_child(_button("+1000 COINS", func() -> void:
		GameState.coins += 1000
		_refresh()))
	misc_row.add_child(_button("TEST LEVEL", func() -> void: _play(0, -1)))
	misc_row.add_child(_button("SKIP TO BOSS", func() -> void:
		GameState.start_distance = -1.0
		_play(int(_plan.get("level", 1)), GameState.seed_override)))
	col.add_child(_button("CLOSE", _toggle))
	_refresh()
	if GameState.open_debug_menu:
		GameState.open_debug_menu = false
		_toggle.call_deferred()


func _toggle() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		_was_paused = get_tree().paused
		get_tree().paused = true
		_refresh()
	else:
		get_tree().paused = _was_paused


func _play(level: int, seed_value: int) -> void:
	GameState.level = level
	GameState.seed_override = seed_value
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().reload_current_scene()


func _refresh() -> void:
	var dbg: Dictionary = _plan.get("debug", {})
	var est: Dictionary = dbg.get("estimate", {})
	var lines: PackedStringArray = [
		"Level %s  seed %s  kind %s  template %s" % [_plan.get("level", "?"), _plan.get("seed", "?"), _plan.get("kind", "?"), _plan.get("template", "-")],
		"Zone %s  palette %s  length %dm  events %d" % [_plan.get("zone", "-"), _plan.get("palette", []), int(_plan.get("length", 0)), (_plan.get("events", []) as Array).size()],
		"Gen %.1f ms  difficulty scale %.2f  fixes %s" % [float(dbg.get("gen_ms", 0)), float(dbg.get("difficulty_scale", 1)), dbg.get("fixes", {})],
		"Estimate (best path): %s, hp %d%%, kills %d/%d" % ["WIN" if est.get("survived", false) else "LOSS", int(float(est.get("hp_frac", 0)) * 100), int(est.get("kills", 0)), int(est.get("units", 0))],
		"Hero power x%.2f  hp x%.2f  coins %d" % [float(_plan.get("hero_power", 1)), float(_plan.get("hero_hp_power", 1)), GameState.coins],
	]
	_info.text = "\n".join(lines)


func _row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	return row


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 38)
	return l


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 90)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 36)
	b.pressed.connect(action)
	return b


func _check(text: String, value: bool, action: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = value
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 36)
	c.toggled.connect(action)
	return c
