extends Screen
## Settings: audio, vibration, purchases/privacy (wired up with ads in Milestone 9), reset, credits.

const CREDITS := """Fantasy Gaterunner

Made with Godot Engine (MIT).
Default font: Open Sans (OFL), bundled with Godot.
3D models, sound effects, shaders and icons: original,
built in code for this game.

Full list: CREDITS.md in the project."""

var _confirm: PanelContainer


func build() -> void:
	header("SETTINGS", GameState.return_screen)
	content.add_child(_toggle("Music", "music"))
	content.add_child(_toggle("Sound effects", "sfx"))
	content.add_child(_toggle("Vibration", "vibration"))

	var restore := button("RESTORE PURCHASES", func() -> void: pass, Color("#5D6D7E"))
	restore.disabled = true
	restore.tooltip_text = "Available in the store build (Milestone 9)."
	content.add_child(restore)
	var privacy := button("PRIVACY OPTIONS", func() -> void: pass, Color("#5D6D7E"))
	privacy.disabled = true
	content.add_child(privacy)
	content.add_child(button("CREDITS", _show_credits, Color("#5D6D7E")))
	content.add_child(spacer())
	content.add_child(button("RESET PROGRESS", _ask_reset, Color("#922B21"), Vector2(0, 110)))
	var version := label("Save v%d  ·  %s" % [SaveManager.VERSION, ProjectSettings.get_setting("application/config/name")], 26, Color(1, 1, 1, 0.4))
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(version)


func _toggle(text: String, key: String) -> PanelContainer:
	var c := card()
	var check := CheckButton.new()
	check.text = text
	check.button_pressed = SaveManager.setting(key)
	check.focus_mode = Control.FOCUS_NONE
	check.add_theme_font_size_override("font_size", 46)
	check.custom_minimum_size = Vector2(0, 90)
	check.toggled.connect(func(on: bool) -> void: SaveManager.set_setting(key, on))
	c.add_child(check)
	return c


func _show_credits() -> void:
	_popup("CREDITS", CREDITS, [["CLOSE", _close_popup]])


func _ask_reset() -> void:
	_popup("RESET PROGRESS?", "All levels, coins, upgrades and unlocks will be erased.\nSettings and purchases are kept.\nThis cannot be undone.",
		[["ERASE EVERYTHING", func() -> void:
			SaveManager.reset_progress()
			GameState.go("menu")], ["CANCEL", _close_popup]])


func _popup(title: String, body: String, buttons: Array) -> void:
	_close_popup()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	_confirm = PanelContainer.new()
	_confirm.custom_minimum_size = Vector2(880, 0)
	center.add_child(_confirm)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 24)
	_confirm.add_child(col)
	col.add_child(label(title, 60, GOLD))
	var text := label(body, 34)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(text)
	for entry: Array in buttons:
		col.add_child(button(entry[0], entry[1], Color("#922B21") if String(entry[0]).begins_with("ERASE") else UiTheme.ACCENT))
	_confirm.set_meta("dim", dim)


func _close_popup() -> void:
	if _confirm and is_instance_valid(_confirm):
		(_confirm.get_meta("dim") as Node).queue_free()
	_confirm = null
