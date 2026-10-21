class_name LevelMapView
extends Control
## Endless vertical level map, drawn procedurally: only the ~12 visible levels are drawn each
## frame, so it scrolls to any level number. Level 1 is at the bottom; levels climb upward.
## Zone bands (10 levels each) tint the background; boss levels get a crown; unclaimed milestone
## levels show a chest. Drag to scroll (with inertia), tap a level to select it.

signal level_selected(level: int)

const SPACING := 200.0
const RADIUS := 54.0
const BOSS_RADIUS := 68.0
const BOTTOM_PAD := 260.0

var unlocked := 1
var selected := 1
var scroll := 0.0

var _velocity := 0.0
var _dragging := false
var _drag_distance := 0.0
var _press_pos := Vector2.ZERO
var _time := 0.0
var _zone_cache: Dictionary = {}
var _claimed: Array = []
var _center_frames := 3


func setup(unlocked_level: int, claimed: Array) -> void:
	unlocked = unlocked_level
	selected = unlocked_level
	_claimed = claimed
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func center_on(level: int) -> void:
	scroll = maxf(0.0, level * SPACING - size.y * 0.45 + BOTTOM_PAD - SPACING)


func _process(delta: float) -> void:
	_time += delta
	# Centre on the selected level once layout has settled (size is final after a few frames).
	if _center_frames > 0 and size.y > 200.0:
		_center_frames -= 1
		center_on(selected)
	if not _dragging and absf(_velocity) > 1.0:
		scroll = maxf(0.0, scroll + _velocity * delta)
		_velocity *= exp(-4.0 * delta)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			scroll += 120.0
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			scroll = maxf(0.0, scroll - 120.0)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_distance = 0.0
				_press_pos = mb.position
				_velocity = 0.0
			else:
				_dragging = false
				if _drag_distance < 24.0:
					_tap(mb.position)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		scroll = maxf(0.0, scroll + mm.relative.y)
		_drag_distance += mm.relative.length()
		_velocity = mm.relative.y / maxf(get_process_delta_time(), 0.001)


func node_position(level: int) -> Vector2:
	var y := size.y - BOTTOM_PAD - (level - 1) * SPACING + scroll
	var x := size.x * 0.5 + sin(level * 0.85) * size.x * 0.27
	return Vector2(x, y)


func _tap(pos: Vector2) -> void:
	for level in _visible_range():
		var r := BOSS_RADIUS if level % 10 == 0 else RADIUS
		if pos.distance_to(node_position(level)) < r + 16.0:
			selected = level
			level_selected.emit(level)
			return


func _visible_range() -> Array:
	var first := maxi(1, int(floor((scroll - BOTTOM_PAD) / SPACING)))
	var last := int(ceil((scroll + size.y) / SPACING)) + 2
	return range(first, last + 1)


func _zone(level: int) -> Dictionary:
	var band := (level - 1) / 10
	if not _zone_cache.has(band):
		var order: Array = Content.zones.get("order", ["forest"])
		_zone_cache[band] = ZoneTheme.resolve(Content.zones, String(order[band % order.size()]), band / order.size())
	return _zone_cache[band]


func _draw() -> void:
	var font := get_theme_default_font()
	var levels := _visible_range()
	# Zone bands.
	var drawn_bands := {}
	for level: int in levels:
		var band := (level - 1) / 10
		if drawn_bands.has(band):
			continue
		drawn_bands[band] = true
		var zone := _zone(level)
		var top := node_position(band * 10 + 10).y - SPACING * 0.5
		var bottom := node_position(band * 10 + 1).y + SPACING * 0.5
		draw_rect(Rect2(0, top, size.x, bottom - top), Color(ZoneTheme.color(zone, "sky", Color.DIM_GRAY), 0.22))
		draw_string(font, Vector2(30, bottom - 30), String(zone.get("name", "")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(1, 1, 1, 0.45))
	# Path.
	for level: int in levels:
		var a := node_position(level)
		var b := node_position(level + 1)
		var done := level < unlocked
		draw_line(a, b, Color("#FFD166") if done else Color(1, 1, 1, 0.18), 14.0 if done else 10.0, true)
	# Nodes.
	for level: int in levels:
		var p := node_position(level)
		var boss := level % 10 == 0
		var r := BOSS_RADIUS if boss else RADIUS
		var zone := _zone(level)
		var fill: Color
		if level < unlocked:
			fill = ZoneTheme.color(zone, "edge", Color("#3FA9FF")).darkened(0.1)
		elif level == unlocked:
			fill = Color("#FFB000").lerp(Color("#FFE680"), 0.5 + 0.5 * sin(_time * 4.0))
		else:
			fill = Color(0.28, 0.28, 0.34)
		if level == selected:
			draw_circle(p, r + 14.0, Color(1, 1, 1, 0.35 + 0.15 * sin(_time * 5.0)))
		draw_circle(p, r + 6.0, Color(0, 0, 0, 0.5))
		draw_circle(p, r, fill)
		var text := str(level)
		var text_size := 46 if text.length() <= 3 else 34
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
		draw_string_outline(font, p + Vector2(-w * 0.5, text_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, 8, Color(0, 0, 0, 0.8))
		draw_string(font, p + Vector2(-w * 0.5, text_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, Color.WHITE)
		if boss:
			var crown := PackedVector2Array([p + Vector2(-34, -r - 4), p + Vector2(-34, -r - 34), p + Vector2(-17, -r - 18),
				p + Vector2(0, -r - 40), p + Vector2(17, -r - 18), p + Vector2(34, -r - 34), p + Vector2(34, -r - 4)])
			draw_colored_polygon(crown, Color("#FFD166"))
			if not _claimed.has(level):
				var chest := Rect2(p + Vector2(r + 14, -22), Vector2(48, 40))
				draw_rect(chest, Color("#8E5B2B"))
				draw_rect(Rect2(chest.position + Vector2(0, 14), Vector2(48, 8)), Color("#FFD166"))
		if level > unlocked:
			draw_rect(Rect2(p + Vector2(-12, r * 0.45), Vector2(24, 18)), Color(0, 0, 0, 0.55))
