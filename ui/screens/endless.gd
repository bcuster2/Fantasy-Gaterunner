extends Screen
## Endless mode lobby: best score, where the run starts, and play.


func build() -> void:
	header("ENDLESS", "modes")
	var hs: Dictionary = SaveManager.data["high_scores"]
	var best := card()
	content.add_child(best)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	best.add_child(col)
	col.add_child(_centered(label("BEST SCORE", 36, Color(1, 1, 1, 0.6))))
	col.add_child(_centered(label(GateInfo.num(float(hs["endless_score"])), 120, GOLD)))
	col.add_child(_centered(label("Longest run  %dm" % int(hs["endless_distance"]), 38, Color(1, 1, 1, 0.8))))

	var info := card()
	content.add_child(info)
	var info_col := VBoxContainer.new()
	info_col.add_theme_constant_override("separation", 10)
	info.add_child(info_col)
	var cfg := Balance.section("endless")
	var tier := EndlessDirector.start_tier_for(SaveManager.unlocked_level(), cfg)
	var rules := label("One run that never ends. It starts at tier %d (half your campaign level) and gets harder every stretch. A boss blocks the road every few minutes; beating it keeps you going.\n\nScore = meters run + enemies defeated. Your shop upgrades apply, and you keep every coin you collect." % tier, 34, Color(1, 1, 1, 0.85))
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_col.add_child(rules)
	content.add_child(spacer())
	content.add_child(button("START RUN", func() -> void: GameState.play_mode("endless"), Color("#8E44AD"), Vector2(0, 170)))
	content.add_child(button("UPGRADES", func() -> void:
		GameState.return_screen = "endless"
		GameState.go("shop"), Color("#27AE60")))


func _centered(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
