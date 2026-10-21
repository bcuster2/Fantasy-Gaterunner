extends Screen
## Campaign level map: endless scrolling map plus details for the selected level.

var _view: LevelMapView
var _info_title: Label
var _info_body: Label
var _play: Button


func build() -> void:
	header("CAMPAIGN", "menu")
	_view = LevelMapView.new()
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_view)
	_view.setup(SaveManager.unlocked_level(), SaveManager.data.get("milestones_claimed", []))
	_view.level_selected.connect(_select)

	var info := card()
	content.add_child(info)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	info.add_child(col)
	_info_title = label("", 52, GOLD)
	col.add_child(_info_title)
	_info_body = label("", 32, Color(1, 1, 1, 0.8))
	_info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_info_body)
	_play = button("PLAY", func() -> void: GameState.play_level(_view.selected), Color("#E67E22"), Vector2(0, 140))
	col.add_child(_play)
	var shop := button("UPGRADES", func() -> void:
		GameState.return_screen = "map"
		GameState.go("shop"), Color("#27AE60"), Vector2(0, 100))
	col.add_child(shop)
	_select(SaveManager.unlocked_level())


func _select(level: int) -> void:
	var plan := LevelGenerator.get_plan(level)
	var zone := ZoneTheme.resolve(Content.zones, String(plan.get("zone", "forest")), int(plan.get("zone_cycle", 0)))
	var boss: Dictionary = Content.bosses.get(String(plan.get("boss", {}).get("id", "")), {})
	var kind := String(plan.get("kind", "normal"))
	var tags := {"spike": "  ·  HARD", "reward": "  ·  BONUS", "boss": "  ·  BOSS"}
	_info_title.text = "LEVEL %d%s" % [level, tags.get(kind, "")]
	var lines: PackedStringArray = [String(zone.get("name", "")), "Boss: %s" % boss.get("name", "?")]
	var mods: PackedStringArray = []
	for mod: String in plan.get("modifiers", []):
		mods.append(String(Content.modifiers.get(mod, {}).get("name", mod)))
	if not mods.is_empty():
		lines.append("Modifiers: " + ", ".join(mods))
	var reward := Economy.milestone(level, Content.milestones, Balance.data)
	if not reward.is_empty() and not (SaveManager.data.get("milestones_claimed", []) as Array).has(level):
		lines.append("Milestone: %s (+%d coins)" % [reward.get("title", ""), int(reward.get("coins", 0))])
	_info_body.text = "\n".join(lines)
	var locked := level > SaveManager.unlocked_level()
	_play.disabled = locked
	_play.text = "LOCKED" if locked else ("PLAY" if level == SaveManager.unlocked_level() else "REPLAY")
