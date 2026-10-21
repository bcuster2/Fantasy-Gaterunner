extends Screen
## Shop: permanent upgrades, hero skins, and milestone perks.

const TABS := ["UPGRADES", "SKINS", "PERKS"]

var _tab := "UPGRADES"
var _list: VBoxContainer
var _tab_buttons: Dictionary = {}


func build() -> void:
	header("UPGRADES", GameState.return_screen)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 14)
	content.add_child(tabs)
	for tab: String in TABS:
		var b := button(tab, func() -> void: _show(tab), UiTheme.ACCENT, Vector2(0, 100))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(b)
		_tab_buttons[tab] = b
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 20)
	scroll.add_child(_list)
	_show("UPGRADES")


func _show(tab: String) -> void:
	_tab = tab
	for key: String in _tab_buttons:
		(_tab_buttons[key] as Button).modulate = Color.WHITE if key == tab else Color(1, 1, 1, 0.5)
	for child in _list.get_children():
		child.queue_free()
	match tab:
		"UPGRADES":
			for id: String in Content.upgrades:
				_list.add_child(_upgrade_card(id))
		"SKINS":
			for id: String in Content.skins:
				_list.add_child(_skin_card(id))
		"PERKS":
			_perk_cards()


func _upgrade_card(id: String) -> PanelContainer:
	var def: Dictionary = Content.upgrades[id]
	var level := SaveManager.upgrade_level(id)
	var price := Economy.cost(def, level)
	var c := card()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	c.add_child(row)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(label("%s  ·  Lv %d" % [def.get("name", id), level], 44, GOLD))
	var now := Economy.describe(def, level) if level > 0 else "Not learned"
	var next := ("Next: " + Economy.describe(def, level + 1)) if price >= 0 else "MAXED"
	var soft := int(def.get("soft_cap", 0))
	var note := "  (reduced gains past Lv %d)" % soft if soft > 0 and level >= soft else ""
	var text := label("%s\n%s%s" % [now, next, note], 32, Color(1, 1, 1, 0.8))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(text)
	var buy := button("MAX" if price < 0 else Screen._format_coins(price), func() -> void:
		if SaveManager.buy_upgrade(id):
			AudioManager.play("gate_good", -4.0, 0.0)
			_show(_tab), Color("#27AE60"), Vector2(230, 130))
	buy.disabled = price < 0 or SaveManager.coins() < price
	row.add_child(buy)
	return c


func _skin_card(id: String) -> PanelContainer:
	var def: Dictionary = Content.skins[id]
	var c := card()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	c.add_child(row)
	var swatch := Panel.new()
	swatch.custom_minimum_size = Vector2(110, 110)
	swatch.add_theme_stylebox_override("panel", UiTheme.box(Color(String(def.get("robe", "#3F6FD8"))), 55, 0))
	row.add_child(swatch)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(label(String(def.get("name", id)), 44, GOLD))
	var owned := SaveManager.owns_skin(id)
	var selected := String(SaveManager.data.get("selected_skin", "default")) == id
	var unlock: Variant = def.get("unlock", "default")
	col.add_child(label("Owned" if owned else "Unlocks at level %d" % int(unlock), 32, Color(1, 1, 1, 0.75)))
	var b := button("EQUIPPED" if selected else ("EQUIP" if owned else "LOCKED"), func() -> void:
		SaveManager.select_skin(id)
		_show(_tab), UiTheme.ACCENT, Vector2(230, 120))
	b.disabled = selected or not owned
	row.add_child(b)
	return c


func _perk_cards() -> void:
	var owned := SaveManager.perks()
	var rewards: Dictionary = Content.milestones.get("rewards", {})
	for key: String in rewards:
		var reward: Dictionary = rewards[key]
		if String(reward.get("type", "")) != "perk":
			continue
		var c := card()
		var col := VBoxContainer.new()
		c.add_child(col)
		var has := owned.has(reward.get("id", ""))
		col.add_child(label(String(reward.get("title", "")).replace("Perk: ", ""), 44, GOLD if has else Color(1, 1, 1, 0.5)))
		col.add_child(label("%s\n%s" % [reward.get("desc", ""), "Active" if has else "Reward for finishing level %s" % key], 32, Color(1, 1, 1, 0.75)))
		_list.add_child(c)
