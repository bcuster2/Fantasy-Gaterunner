class_name UiTheme
extends RefCounted
## Shared UI theme built in code (rounded, chunky, readable on small screens).

const ACCENT := Color("#2E86DE")
const PANEL := Color(0.07, 0.06, 0.12, 0.8)
const MUTED := Color(1, 1, 1, 0.6)

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 44

	t.set_color("font_color", "Label", Color.WHITE)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	t.set_constant("outline_size", "Label", 10)

	t.set_stylebox("normal", "Button", box(ACCENT, 28, 26))
	t.set_stylebox("hover", "Button", box(ACCENT.lightened(0.12), 28, 26))
	t.set_stylebox("pressed", "Button", box(ACCENT.darkened(0.25), 28, 26))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("disabled", "Button", box(Color(0.3, 0.3, 0.35), 28, 26))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(state, "Button", Color.WHITE)
	t.set_color("font_outline_color", "Button", Color(0, 0, 0, 0.6))
	t.set_constant("outline_size", "Button", 8)
	t.set_font_size("font_size", "Button", 52)

	t.set_stylebox("panel", "PanelContainer", box(PANEL, 30, 28))
	_theme = t
	return t


static func box(color: Color, radius := 24, padding := 20.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(padding)
	s.anti_aliasing = true
	return s
