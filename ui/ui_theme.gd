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

	# Big readable switches for CheckButton (the default icons are tiny at 1080p).
	for state in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		t.set_stylebox(state, "CheckButton", StyleBoxEmpty.new())
	t.set_icon("checked", "CheckButton", _switch_texture(true))
	t.set_icon("unchecked", "CheckButton", _switch_texture(false))
	t.set_color("font_color", "CheckButton", Color.WHITE)
	t.set_color("font_pressed_color", "CheckButton", Color.WHITE)
	t.set_color("font_hover_color", "CheckButton", Color.WHITE)
	_theme = t
	return t


## A pill switch drawn into an image: green with the knob right when on, grey with it left when off.
static func _switch_texture(on: bool) -> ImageTexture:
	var w := 132
	var h := 72
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var track := Color("#2ECC71") if on else Color("#5D6D7E")
	var knob_x := w - h * 0.5 if on else h * 0.5
	for y in h:
		for x in w:
			var cx := clampf(x, h * 0.5, w - h * 0.5)
			var d := Vector2(x - cx, y - h * 0.5).length()
			var a := clampf(h * 0.5 - d, 0.0, 1.0)
			var c := Color(track, a)
			var kd := Vector2(x - knob_x, y - h * 0.5).length()
			var ka := clampf(h * 0.5 - 7.0 - kd, 0.0, 1.0)
			c = c.lerp(Color(1, 1, 1, maxf(a, ka)), ka)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


static func box(color: Color, radius := 24, padding := 20.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(padding)
	s.anti_aliasing = true
	return s
