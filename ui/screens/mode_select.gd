extends Screen
## Game modes: campaign now; endless and daily challenge arrive in Milestone 7.


func build() -> void:
	header("GAME MODES", "menu")
	content.add_child(_mode_card("CAMPAIGN", "Numbered levels, forever. Level %d unlocked." % SaveManager.unlocked_level(),
		Color("#E67E22"), func() -> void: GameState.go("map"), true))
	content.add_child(_mode_card("ENDLESS", "One run, rising difficulty, bosses every few minutes.\nComing soon.",
		Color("#8E44AD"), func() -> void: pass, false))
	content.add_child(_mode_card("DAILY CHALLENGE", "A new seeded run every day. One try (plus a retry).\nComing soon.",
		Color("#16A085"), func() -> void: pass, false))
	content.add_child(spacer())


func _mode_card(title: String, desc: String, color: Color, action: Callable, enabled: bool) -> PanelContainer:
	var c := card()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	c.add_child(col)
	col.add_child(label(title, 56, color.lightened(0.3)))
	var d := label(desc, 34, Color(1, 1, 1, 0.75))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(d)
	var b := button("PLAY" if enabled else "LOCKED", action, color if enabled else Color(0.3, 0.3, 0.35))
	b.disabled = not enabled
	col.add_child(b)
	return c
