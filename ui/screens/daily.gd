extends Screen
## Daily challenge lobby: today's seeded run, its modifiers, attempts left, and the reset countdown.

var _date := ""
var _countdown: Label


func build() -> void:
	_date = LevelGenerator.today_utc()
	header("DAILY", "modes")
	var plan := LevelGenerator.get_daily_plan(_date)
	var state := SaveManager.daily(_date)
	var cfg := Balance.section("daily")

	var top := card()
	content.add_child(top)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	top.add_child(col)
	col.add_child(_centered(label("CHALLENGE OF THE DAY", 36, Color(1, 1, 1, 0.6))))
	col.add_child(_centered(label(_date, 72, GOLD)))
	var zone := ZoneTheme.resolve(Content.zones, String(plan.get("zone", "forest")), int(plan.get("zone_cycle", 0)))
	var boss: Dictionary = Content.bosses.get(String(plan.get("boss", {}).get("id", "")), {})
	col.add_child(_centered(label("%s  ·  Boss: %s" % [zone.get("name", ""), boss.get("name", "?")], 34, Color(1, 1, 1, 0.85))))
	var mods := HBoxContainer.new()
	mods.alignment = BoxContainer.ALIGNMENT_CENTER
	mods.add_theme_constant_override("separation", 12)
	col.add_child(mods)
	for mod: String in plan.get("modifiers", []):
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UiTheme.box(Color(0.45, 0.12, 0.5, 0.85), 20, 14))
		chip.add_child(label(String(Content.modifiers.get(mod, {}).get("name", mod)), 32))
		mods.add_child(chip)

	var rules := label("Everyone gets the same run today: same seed, same modifiers, and the same standard hero (shop upgrades don't apply here). One attempt, plus one retry if you watch an ad. Clear it for a bonus of about %d coins." % int(roundf(float(cfg.get("bonus_base", 400)) * Curves.named(Balance.data, "coin_multiplier", SaveManager.unlocked_level()))), 32, Color(1, 1, 1, 0.8))
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(rules)

	var status := label("", 44)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(status)
	content.add_child(spacer())

	if bool(state["completed"]):
		status.text = "CLEARED!  Best score %d" % int(state["best_score"])
		status.modulate = Color("#7CF29A")
	elif SaveManager.daily_can_play(_date):
		status.text = "Ready  ·  %s" % ("final attempt" if bool(state["retry_used"]) else "1 attempt")
		content.add_child(button("PLAY TODAY'S RUN", func() -> void: GameState.play_mode("daily"), Color("#16A085"), Vector2(0, 170)))
	elif SaveManager.daily_can_retry(_date):
		status.text = "Out of attempts"
		status.modulate = Color("#FF8A6B")
		var retry := button("RETRY  (WATCH AD)", func() -> void:
			AdManager.show_rewarded("daily_retry", func() -> void:
				SaveManager.grant_daily_retry(_date)
				GameState.play_mode("daily")), Color("#E67E22"), Vector2(0, 150))
		retry.disabled = not AdManager.is_rewarded_available("daily_retry")
		content.add_child(retry)
	else:
		status.text = "No attempts left today"
		status.modulate = Color("#FF8A6B")
	_countdown = label("", 34, Color(1, 1, 1, 0.6))
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_countdown)


func _process(_delta: float) -> void:
	if _countdown == null:
		return
	if LevelGenerator.today_utc() != _date:
		GameState.go("daily") # the day rolled over while this screen was open
		_countdown = null
		return
	var left := 86400 - int(Time.get_unix_time_from_system()) % 86400
	_countdown.text = "New challenge in %02d:%02d:%02d" % [left / 3600, (left / 60) % 60, left % 60]


func _centered(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
