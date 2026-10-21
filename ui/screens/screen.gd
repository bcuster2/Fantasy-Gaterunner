class_name Screen
extends Control
## Base for full-screen menus: themed background, safe margins, header with back button and coin
## counter, and small widget helpers. Screens override build().

const BG_TOP := Color("#2B1B4A")
const BG_BOTTOM := Color("#0F1430")
const GOLD := Color("#FFD166")

var content: VBoxContainer
var _coin_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	_build_background()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 70)
	margin.add_theme_constant_override("margin_bottom", 60)
	add_child(margin)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 26)
	margin.add_child(content)
	build()
	SaveManager.coins_changed.connect(_on_coins_changed)


func build() -> void:
	pass


## Back button (to `back_screen`, or none if empty), title, and coin chip.
func header(title: String, back_screen := "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	content.add_child(row)
	if back_screen != "":
		var back := button("<", func() -> void: GameState.go(back_screen), UiTheme.ACCENT, Vector2(120, 110))
		row.add_child(back)
	var title_label := label(title, 64)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title_label)
	row.add_child(coin_chip())
	return row


func coin_chip() -> PanelContainer:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PANEL, 28, 18))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	chip.add_child(row)
	var icon := Panel.new()
	icon.custom_minimum_size = Vector2(50, 50)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style := UiTheme.box(Color("#FFC93C"), 25, 0)
	style.border_color = Color("#B8860B")
	style.set_border_width_all(5)
	icon.add_theme_stylebox_override("panel", style)
	row.add_child(icon)
	_coin_label = label(_format_coins(SaveManager.coins()), 48)
	row.add_child(_coin_label)
	return chip


func button(text: String, action: Callable, color := UiTheme.ACCENT, min_size := Vector2(0, 130)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	if color != UiTheme.ACCENT:
		b.add_theme_stylebox_override("normal", UiTheme.box(color, 28, 26))
		b.add_theme_stylebox_override("hover", UiTheme.box(color.lightened(0.12), 28, 26))
		b.add_theme_stylebox_override("pressed", UiTheme.box(color.darkened(0.25), 28, 26))
	b.pressed.connect(func() -> void:
		AudioManager.play("coin", -10.0, 0.05)
		action.call())
	return b


func label(text: String, size := 44, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.modulate = color
	return l


func card() -> PanelContainer:
	var c := PanelContainer.new()
	c.add_theme_stylebox_override("panel", UiTheme.box(Color(1, 1, 1, 0.07), 30, 28))
	return c


func spacer() -> Control:
	var s := Control.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return s


static func _format_coins(value: int) -> String:
	if value >= 1000000:
		return "%.1fM" % (value / 1000000.0)
	if value >= 10000:
		return "%.1fK" % (value / 1000.0)
	return str(value)


func _on_coins_changed(value: int) -> void:
	if _coin_label:
		_coin_label.text = _format_coins(value)


func _build_background() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, BG_TOP)
	gradient.set_color(1, BG_BOTTOM)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	var bg := TextureRect.new()
	bg.texture = texture
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
