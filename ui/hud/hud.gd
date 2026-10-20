class_name Hud
extends CanvasLayer
## In-run HUD built in code: HP, coins, progress, stat chips, steering hint, pause and result overlays.

signal restart_requested

const STAT_ORDER := ["damage", "fire_rate", "projectiles"]
const STAT_CAPTIONS := {"damage": "DAMAGE", "fire_rate": "FIRE RATE", "projectiles": "SHOTS"}

var _hp_bar: ProgressBar
var _hp_text: Label
var _coin_label: Label
var _coin_chip: Control
var _progress: ProgressBar
var _chips: Dictionary = {}
var _chip_values: Dictionary = {}
var _flash: ColorRect
var _hint: Label
var _hint_time := 0.0
var _hint_fading := false
var _overlay: Control
var _overlay_title: Label
var _overlay_body: Label
var _overlay_buttons: VBoxContainer


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.get_theme()
	add_child(root)

	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	root.add_child(_flash)

	_build_top_bar(root)
	_build_stat_chips(root)
	_build_hint(root)
	_build_overlay(root)


func _process(delta: float) -> void:
	if _hint.visible and not _hint_fading:
		_hint_time += delta
		_hint.modulate.a = 0.65 + 0.35 * sin(_hint_time * 5.0)
		if _hint_time > 5.0:
			hide_hint()


# --- Public API -------------------------------------------------------------------------------

func set_hp(hp: float, max_hp: float) -> void:
	var dropped := hp < _hp_bar.value
	_hp_bar.max_value = max_hp
	_hp_bar.value = hp
	_hp_text.text = "%d / %d" % [ceili(hp), ceili(max_hp)]
	if dropped:
		flash(Color(1, 0.1, 0.1), 0.28)
		_punch(_hp_bar.get_parent(), 1.06)


func set_coins(coins: int) -> void:
	_coin_label.text = str(coins)
	_punch(_coin_chip, 1.15)


func set_progress(fraction: float) -> void:
	_progress.value = clampf(fraction, 0.0, 1.0) * 100.0


func set_stats(stats: HeroStats, changed_stat := "", good := true) -> void:
	_chip_values["damage"].text = GateInfo.num(snappedf(stats.damage, 0.1))
	_chip_values["fire_rate"].text = "%s/s" % GateInfo.num(snappedf(stats.fire_rate, 0.1))
	_chip_values["projectiles"].text = str(stats.projectiles)
	if _chips.has(changed_stat):
		var chip: Control = _chips[changed_stat]
		_punch(chip, 1.3)
		chip.modulate = Color(0.5, 1.6, 0.6) if good else Color(1.8, 0.5, 0.5)
		create_tween().tween_property(chip, "modulate", Color.WHITE, 0.5)


func flash(color: Color, strength: float) -> void:
	_flash.color = Color(color.r, color.g, color.b, strength)
	create_tween().tween_property(_flash, "color:a", 0.0, 0.3)


func hide_hint() -> void:
	if _hint_fading or not _hint.visible:
		return
	_hint_fading = true
	var tween := create_tween()
	tween.tween_property(_hint, "modulate:a", 0.0, 0.4)
	tween.tween_callback(_hint.hide)


func show_result(won: bool, body: String) -> void:
	_show_overlay("VICTORY!" if won else "DEFEATED", body, [["PLAY AGAIN", _on_restart]])
	_overlay_title.modulate = Color("#FFD166") if won else Color("#FF6B6B")


# --- Layout -----------------------------------------------------------------------------------

func _build_top_bar(root: Control) -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 70)
	root.add_child(margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 20)
	column.add_child(row)

	var pause := Button.new()
	pause.text = "II"
	pause.custom_minimum_size = Vector2(112, 112)
	pause.focus_mode = Control.FOCUS_NONE
	pause.pressed.connect(_on_pause)
	row.add_child(pause)

	var hp_holder := Control.new()
	hp_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_holder.custom_minimum_size = Vector2(0, 112)
	hp_holder.resized.connect(func() -> void: hp_holder.pivot_offset = hp_holder.size * 0.5)
	row.add_child(hp_holder)
	_hp_bar = _make_bar(Color("#E84855"), 112)
	_hp_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hp_holder.add_child(_hp_bar)
	_hp_text = Label.new()
	_hp_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_text.add_theme_font_size_override("font_size", 48)
	hp_holder.add_child(_hp_text)

	_coin_chip = PanelContainer.new()
	_coin_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coin_chip.custom_minimum_size = Vector2(200, 112)
	_coin_chip.resized.connect(func() -> void: _coin_chip.pivot_offset = _coin_chip.size * 0.5)
	row.add_child(_coin_chip)
	var coin_row := HBoxContainer.new()
	coin_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin_row.alignment = BoxContainer.ALIGNMENT_CENTER
	coin_row.add_theme_constant_override("separation", 14)
	_coin_chip.add_child(coin_row)
	var coin_icon := Panel.new()
	coin_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin_icon.custom_minimum_size = Vector2(52, 52)
	coin_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var coin_style := UiTheme.box(Color("#FFC93C"), 26, 0)
	coin_style.border_color = Color("#B8860B")
	coin_style.set_border_width_all(5)
	coin_icon.add_theme_stylebox_override("panel", coin_style)
	coin_row.add_child(coin_icon)
	_coin_label = Label.new()
	_coin_label.text = "0"
	_coin_label.add_theme_font_size_override("font_size", 52)
	coin_row.add_child(_coin_label)

	_progress = _make_bar(Color("#FFD166"), 20)
	column.add_child(_progress)


func _build_stat_chips(root: Control) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.anchor_left = 0.0
	row.anchor_right = 1.0
	row.anchor_top = 1.0
	row.anchor_bottom = 1.0
	row.offset_top = -270
	row.offset_bottom = -110
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	root.add_child(row)
	for stat: String in STAT_ORDER:
		var chip := PanelContainer.new()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.custom_minimum_size = Vector2(300, 0)
		chip.resized.connect(func() -> void: chip.pivot_offset = chip.size * 0.5)
		row.add_child(chip)
		var column := VBoxContainer.new()
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		chip.add_child(column)
		var caption := Label.new()
		caption.text = STAT_CAPTIONS[stat]
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.add_theme_font_size_override("font_size", 30)
		caption.modulate = UiTheme.MUTED
		column.add_child(caption)
		var value := Label.new()
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value.add_theme_font_size_override("font_size", 60)
		column.add_child(value)
		_chips[stat] = chip
		_chip_values[stat] = value


func _build_hint(root: Control) -> void:
	_hint = Label.new()
	_hint.text = "<   DRAG TO STEER   >"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 56)
	_hint.anchor_left = 0.0
	_hint.anchor_right = 1.0
	_hint.anchor_top = 0.68
	_hint.anchor_bottom = 0.68
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hint)


func _build_overlay(root: Control) -> void:
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	root.add_child(_overlay)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 0)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 30)
	panel.add_child(column)
	_overlay_title = Label.new()
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_title.add_theme_font_size_override("font_size", 104)
	column.add_child(_overlay_title)
	_overlay_body = Label.new()
	_overlay_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_body.add_theme_font_size_override("font_size", 44)
	column.add_child(_overlay_body)
	_overlay_buttons = VBoxContainer.new()
	_overlay_buttons.add_theme_constant_override("separation", 22)
	column.add_child(_overlay_buttons)


func _show_overlay(title: String, body: String, buttons: Array) -> void:
	_overlay_title.text = title
	_overlay_title.modulate = Color.WHITE
	_overlay_body.text = body
	_overlay_body.visible = not body.is_empty()
	for child in _overlay_buttons.get_children():
		child.queue_free()
	for entry: Array in buttons:
		var button := Button.new()
		button.text = entry[0]
		button.custom_minimum_size = Vector2(0, 140)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(entry[1])
		_overlay_buttons.add_child(button)
	_overlay.visible = true
	_overlay.modulate.a = 0.0
	create_tween().tween_property(_overlay, "modulate:a", 1.0, 0.25)


func _make_bar(fill: Color, height: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, height)
	bar.max_value = 100.0
	bar.value = 0.0
	var radius := int(height * 0.5)
	bar.add_theme_stylebox_override("background", UiTheme.box(Color(0, 0, 0, 0.55), radius, 0))
	bar.add_theme_stylebox_override("fill", UiTheme.box(fill, radius, 0))
	return bar


func _punch(control: Control, amount: float) -> void:
	control.scale = Vector2.ONE * amount
	create_tween().tween_property(control, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# --- Buttons ----------------------------------------------------------------------------------

func _on_pause() -> void:
	if _overlay.visible:
		return
	get_tree().paused = true
	_show_overlay("PAUSED", "", [["RESUME", _on_resume], ["RESTART", _on_restart]])


func _on_resume() -> void:
	_overlay.visible = false
	get_tree().paused = false


func _on_restart() -> void:
	restart_requested.emit()
