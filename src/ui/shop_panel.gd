class_name ShopPanel
extends Control
## League's in-game item shop, rebuilt from the ItemShop layout in UI.wad.client (assets/ui/hud/layout.json).
## Tabs: Recommended (3 suggested cards + "commonly built" row) and All Items (type + stat filters, tiered grid).
## Search box takes typing as soon as the shop opens. Right side: builds-into row, build tree (owned components
## highlighted, discounted price), purchase button and item details. Footer: Sell, Undo, gold.
## Buy: double-click / right-click / Purchase button / Enter. Sell: select an owned item (HUD inventory) + Sell.
## ARAM rule kept: buying and selling only while dead or on the spawn platform.

const SH := "Shop:"
const C_TEXT := Color(0.941, 0.902, 0.824)
const C_DIM := Color(0.647, 0.627, 0.588)
const C_GOLD := Color(0.784, 0.667, 0.431)
const C_GOLD_TXT := Color(0.94, 0.8, 0.42)
const C_RED := Color(0.92, 0.36, 0.3)
const C_TEAL := Color(0.04, 0.78, 0.73)
const CELL_PITCH := Vector2(56, 78)
const TYPE_BUTTONS := [
	["AllBtn_IconDefault", "All", ""], ["AtkBtn_IconDefault", "Fighter", "fighter"], ["MarkBtn_IconDefault", "Marksman", "marksman"],
	["AssBtn_IconDefault", "Assassin", "assassin"], ["MagBtn_IconDefault", "Mage", "mage"], ["DefBtn_IconDefault", "Tank", "tank"],
	["UtilBtn_IconDefault", "Support", "support"],
]
const STAT_KEYS := ["PhysicalDamage", "CriticalStrike", "AttackSpeed", "OnHit", "ArmorPen", "AbilityPower", "Mana", "MagicPen",
	"Health", "Armor", "MagicResist", "AbilityHaste", "Movespeed", "Vamp"]
const TIER_ORDER := ["Starter", "Boots", "Basic", "Epic", "Legendary"]

var hud = null
var L := HudLayout.new()
var tab := "rec"
var search := ""
var type_filter := 0
var stat_filter := -1
var selected := -1
var selected_owned = null
var scroll := 0.0
var _scroll_max := 0.0
var _hits: Array = []                 ## [Rect2, kind, value]
var _mouse := Vector2(-1, -1)
var _hover_tip := {}
var _hover_key := ""
var _hover_rect := Rect2()
var _tip_seen := false
var _tree_pool: Array = []          ## owned items consumed by the selected recipe (marked "owned" in the tree)
var _last_click_t := 0
var _last_click_id := -1
var _undo: Array = []                 ## snapshots before each buy / sell
var _caret_t := 0.0
var msg := ""
var msg_t := 0.0
var f_title: Font
var f_body: Font
var f_bold: Font
var panel := Rect2()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	f_title = Assets.font("beaufort", "Bold")
	f_body = Assets.font("spiegel", "Regular")
	f_bold = Assets.font("spiegel", "Bold")
	visibility_changed.connect(_on_visibility)


func _on_visibility() -> void:
	if visible:
		search = ""
		scroll = 0.0
		if selected < 0:
			var rec := _rec_cards()
			if not rec.is_empty():
				selected = rec[0]
	else:
		_undo.clear()   # League clears the undo history when you leave the shop


func refresh() -> void:
	queue_redraw()


func champ():
	return G.player


func _process(delta: float) -> void:
	msg_t = maxf(0.0, msg_t - delta)
	_caret_t += delta
	if visible:
		queue_redraw()


# ===================================================================== data
func _rec_cards() -> Array:
	## next three items of the recommended build the player does not own yet
	var c = champ()
	var rec := ItemDB.recommended(c.alias)
	var out := []
	var pool: Array = []
	if c.items.is_empty():
		pool += rec.starter
	pool += rec.core.slice(0, 1) + rec.boots + rec.core.slice(1)
	for id in pool:
		if not _owns(id) and not (id in out):
			out.append(id)
		if out.size() >= 3:
			break
	return out


func _commonly_built() -> Array:
	var rec := ItemDB.recommended(champ().alias)
	return (rec.starter + rec.boots + rec.core).slice(0, 9)


func _owns(id: int) -> bool:
	for it in champ().items:
		if it.item_id == id:
			return true
	return false


func _all_items() -> Array:
	var out := []
	for id in ItemDB.CAT:
		if id == 9999 and champ().level < 16 and search == "":
			continue
		if search != "" and not ItemDB.matches_search(id, search):
			continue
		if type_filter > 0 and not (TYPE_BUTTONS[type_filter][2] in ItemDB.tags_of(id)):
			continue
		if stat_filter >= 0 and not ItemDB.matches_stat_filter(id, stat_filter):
			continue
		out.append(id)
	out.sort_custom(func(a, b): return ItemDB.cost_of(a) < ItemDB.cost_of(b))
	return out


# ===================================================================== actions
func _snapshot() -> Dictionary:
	var c = champ()
	return {"gold": c.gold, "items": c.items.duplicate(), "anvils": c.anvils.size()}


func _buy(id: int) -> void:
	var c = champ()
	var r := ItemDB.buy_block_reason(c, id)
	if r != "":
		_msg(r)
		Sfx.ui("locked")
		return
	var snap := _snapshot()
	if ItemDB.buy(c, id):
		_undo.append(snap)
		Sfx.ui("buy")
		Vfx.rising(c, G.COLOR_GOLD, 0.4, 20)
		selected_owned = null


func _sell() -> void:
	var c = champ()
	if selected_owned == null or not (selected_owned in c.items):
		_msg("Select an item in your inventory to sell")
		Sfx.ui("locked")
		return
	if not c.can_shop():
		_msg("You can only sell while dead or in base")
		Sfx.ui("locked")
		return
	_undo.append(_snapshot())
	ItemDB.sell(c, selected_owned)
	Sfx.ui("gold_click")
	selected_owned = null


func _undo_last() -> void:
	if _undo.is_empty():
		return
	var c = champ()
	var snap: Dictionary = _undo.pop_back()
	for it in c.items.duplicate():
		if not (it in snap.items):
			c.remove_item(it)
	for it in snap.items:
		if not (it in c.items):
			it.removed = false
			c.add_item(it)
	c.items = snap.items.duplicate()
	while c.anvils.size() > snap.anvils:
		var a = c.anvils.pop_back()
		c.remove_effect(a)
	c.gold = snap.gold
	c.items_changed.emit()
	selected_owned = null
	Sfx.ui("click")


func _msg(s: String) -> void:
	msg = s
	msg_t = 2.5


# ===================================================================== input
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed:
		_key(event)
		return
	if event is InputEventMouseMotion:
		_mouse = event.position
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	var mb := event as InputEventMouseButton
	var mp: Vector2 = mb.position
	# HUD inventory slots double as the shop inventory (select to sell, right-click to sell)
	for i in mini(6, champ().items.size()):
		var ir: Rect2 = hud.L.r("Inventory:InventoryItem%d_Backdrop" % i)
		if ir.has_point(mp) and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT):
			selected_owned = champ().items[i]
			selected = selected_owned.item_id
			if mb.button_index == MOUSE_BUTTON_RIGHT:
				_sell()
			get_viewport().set_input_as_handled()
			return
	if not panel.has_point(mp):
		return
	get_viewport().set_input_as_handled()
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		scroll = clampf(scroll + (-1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0) * CELL_PITCH.y * 0.6, 0.0, _scroll_max)
		return
	var right := mb.button_index == MOUSE_BUTTON_RIGHT
	if mb.button_index != MOUSE_BUTTON_LEFT and not right:
		return
	for i in range(_hits.size() - 1, -1, -1):
		var h: Array = _hits[i]
		if not (h[0] as Rect2).has_point(mp):
			continue
		match h[1]:
			"close":
				visible = false
			"tab":
				tab = h[2]
				scroll = 0.0
				Sfx.ui("click")
			"type":
				type_filter = h[2]
				scroll = 0.0
				Sfx.ui("toggle")
			"stat":
				stat_filter = -1 if stat_filter == h[2] else h[2]
				scroll = 0.0
				Sfx.ui("toggle")
			"clear_search":
				search = ""
			"buy":
				if selected >= 0:
					_buy(selected)
			"sell":
				_sell()
			"undo":
				_undo_last()
			"item":
				var id: int = h[2]
				selected = id
				selected_owned = null
				var now := Time.get_ticks_msec()
				if right or (now - _last_click_t < 380 and _last_click_id == id):
					_buy(id)
					_last_click_id = -1
				else:
					_last_click_id = id
					Sfx.ui("click")
				_last_click_t = now
		return


func _key(ev: InputEventKey) -> void:
	var handled := true
	if ev.keycode == KEY_ESCAPE:
		if search != "":
			search = ""
		else:
			visible = false
	elif ev.keycode == KEY_Z and ev.ctrl_pressed:
		_undo_last()
	elif ev.keycode == KEY_BACKSPACE:
		search = search.substr(0, maxi(0, search.length() - 1))
		scroll = 0.0
	elif ev.keycode == KEY_ENTER or ev.keycode == KEY_KP_ENTER:
		var list := _all_items() if search != "" else []
		if search != "" and not list.is_empty() and not (selected in list):
			selected = list[0]
		if selected >= 0:
			_buy(selected)
	elif ev.keycode == KEY_P and search == "" and not ev.ctrl_pressed:
		visible = false
	elif ev.keycode == KEY_TAB:
		handled = false     # scoreboard still works
	elif ev.unicode >= 32 and ev.unicode < 127 and not ev.ctrl_pressed and not ev.alt_pressed:
		if search.length() < 28:
			search += char(ev.unicode)
			tab = "all"
			scroll = 0.0
			var list := _all_items()
			if not list.is_empty():
				selected = list[0]
				selected_owned = null
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


# ===================================================================== drawing
func _draw() -> void:
	if not visible:
		return
	L.begin(size)
	_hits.clear()
	_tip_seen = false
	var c = champ()
	panel = L.r(SH + "ItemShop_BackdropFrame_TopLeft").merge(L.r(SH + "ItemShop_BackdropFrame_BottomRight"))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.18))
	for p in ["TopLeft", "Top", "TopRight", "Left", "Fill", "Right", "BottomLeft", "Bottom", "BottomRight"]:
		L.draw(self, SH + "ItemShop_BackdropFrame_" + p)
	L.draw(self, SH + "ItemShop_Magic_ListView", Color(1, 1, 1, 0.5))
	L.draw(self, SH + "ItemShop_Magic_BuildTree", Color(1, 1, 1, 0.55))
	L.draw(self, SH + "ItemShop_KeyLine_Right")
	L.draw(self, SH + "ItemShop_KeyLine_Tabs")
	L.draw(self, SH + "ItemShop_KeyLine_Footer")
	# close
	var cr := L.r(SH + "ItemShop_MenuClose_ButtonDefault")
	L.draw(self, SH + ("ItemShop_MenuClose_ButtonHover" if cr.grow(4).has_point(_mouse) else "ItemShop_MenuClose_ButtonDefault"))
	_hits.append([cr.grow(6.0), "close", 0])
	_draw_tabs()
	_draw_search()
	if tab == "rec" and search == "":
		_draw_recommended()
	else:
		_draw_all_items()
	_draw_build_panel()
	_draw_footer()
	if not _tip_seen:
		_hover_tip = {}
		_hover_key = ""
	if not _hover_tip.is_empty():
		HudTooltip.draw(self, _hover_tip, _hover_rect, size, size.y / 1080.0)


func _draw_tabs() -> void:
	var names := [["rec", "RECOMMENDED"], ["all", "ALL ITEMS"]]
	for i in names.size():
		var off := Vector2(215.0 * i, 0)
		var r := L.r(SH + "ItemShop_TabButton_Default", off)
		var on: bool = (tab == names[i][0]) and not (search != "" and names[i][0] == "rec")
		var hov := r.has_point(_mouse)
		L.draw(self, SH + "ItemShop_TabButton_Default", Color(1, 1, 1, 1.0 if on else (0.7 if hov else 0.45)), off)
		if on:
			draw_rect(Rect2(r.position.x + r.size.x * 0.1, r.end.y - 2.0, r.size.x * 0.8, 2.0), C_GOLD)
		L.text(self, SH + "ItemShop_TabButton_Text", names[i][1], f_title, 13, C_TEXT if on else C_DIM, 1, off, 0.0)
		_hits.append([r, "tab", names[i][0]])


func _draw_search() -> void:
	L.draw(self, SH + "ItemShop_SearchBar_BarLeft")
	L.draw(self, SH + "ItemShop_SearchBar_BarStretch")
	L.draw(self, SH + "ItemShop_SearchBar_BarRight")
	L.draw(self, SH + "ItemShop_SearchBar_SearchIcon")
	var caret := "|" if int(_caret_t * 2.0) % 2 == 0 else " "
	if search == "":
		L.text(self, SH + "ItemShop_SearchBar_Default_Text", "Search (type to filter)" + caret, f_body, 14, Color(0.5, 0.5, 0.48), 0, Vector2.ZERO, 0.0)
	else:
		L.text(self, SH + "ItemShop_SearchBar_Text", search + caret, f_bold, 15, C_TEXT, 0, Vector2.ZERO, 0.0)
		var xr := L.draw(self, SH + "ItemShop_SearchBar_ClearIcon")
		_hits.append([xr.grow(6.0), "clear_search", 0])


# --------------------------------------------------------------------- recommended tab
func _draw_recommended() -> void:
	var c = champ()
	L.text(self, SH + "ItemShop_RecItems_SuggestedItems_HeaderText", "SUGGESTED ITEMS", f_title, 15, C_GOLD, 0, Vector2.ZERO, 0.0)
	var cards := _rec_cards()
	var CE := SH + "ItemShop_RecItems_"
	for i in cards.size():
		var id: int = cards[i]
		var slot := L.r(SH + "ItemShop_RecItems_RecItemSlot%d" % i)
		var off := Vector2(204.0 * i, 0)
		var hov := slot.has_point(_mouse)
		var sel := selected == id
		L.draw(self, CE + ("Card_M_Hover" if sel else ("Card_NM_Hover" if hov else "Card_Default")), Color.WHITE, off)
		L.text(self, CE + "NameText", ItemDB.name_of(id), f_title, 15, C_TEXT, 1, off, 0.0)
		var price: int = ItemDB.price_for(c, id)[0]
		var afford: bool = c.gold >= price
		L.draw(self, CE + ("Item_FrameHover" if hov or sel else "Item_Frame"), Color.WHITE, off)
		var ir := L.r(CE + "Item_Icon", off)
		var icon := _item_icon(id)
		if icon != null:
			draw_texture_rect(icon, ir, false, Color.WHITE if afford else Color(0.5, 0.5, 0.52))
		if not afford:
			L.draw(self, CE + "Item_Unpurchaseable", Color(1, 1, 1, 0.55), off)
		var cr := L.r(CE + "CostText", off)
		_gold_amount(cr, price, 16, C_GOLD_TXT if afford else Color(0.55, 0.5, 0.42))
		L.text(self, CE + "BriefText", ItemDB.blurb(id), f_body, 13, C_DIM, 1, off, 0.0)
		# components with owned ones ticked, like League's card footer
		var comps := ItemDB.components_of(id)
		var cx := slot.get_center().x - (comps.size() * 40.0 * L.s()) * 0.5
		for ci in comps.size():
			var comp: int = comps[ci]
			var r := Rect2(cx + ci * 40.0 * L.s(), slot.position.y + 250.0 * L.s(), 34.0 * L.s(), 34.0 * L.s())
			_item_cell_small(r, comp)
		_hits.append([slot, "item", id])
		if hov:
			_set_tip("rec%d" % id, HudTooltip.item(id, c), slot)
	L.draw(self, CE + "KeyLine_CommonlyBuilt")
	L.text(self, CE + "CommonlyBuilt_HeaderText", "FULL BUILD", f_title, 15, C_GOLD, 0, Vector2.ZERO, 0.0)
	var cb := _commonly_built()
	for i in cb.size():
		var r := L.r(SH + "ItemShop_TabView_RecItems/Slots/ItemShop_RecItems_CommonlyBuilt_Slot%d" % i)
		if r.size.x <= 0.0:
			r = L.r(CE + "CommonlyBuilt_Slot%d" % i)
		_item_cell(r, cb[i], false)
		if i < cb.size() - 1:
			var y := r.get_center().y
			draw_line(Vector2(r.end.x + 3, y), Vector2(r.end.x + 13.0 * L.s(), y), C_GOLD * Color(1, 1, 1, 0.6), 1.0)


# --------------------------------------------------------------------- all items tab
func _draw_all_items() -> void:
	var c = champ()
	var F := SH
	L.draw(self, F + "ItemShop_KeyLine_Filters")
	# type filter row
	for i in TYPE_BUTTONS.size():
		var key: String = F + "ItemShop_" + TYPE_BUTTONS[i][0]
		var el := L.e(key)
		if el.is_empty():
			continue
		var on := type_filter == i
		var r := L.r(key)
		var hit := Rect2(r.get_center() - Vector2(20, 18) * L.s(), Vector2(40, 36) * L.s())
		L.draw(self, key, C_GOLD if on else (C_TEXT if hit.has_point(_mouse) else C_DIM))
		if on:
			draw_rect(Rect2(hit.position.x + hit.size.x * 0.15, hit.end.y + 1.0, hit.size.x * 0.7, 2.0), C_GOLD)
		_hits.append([hit, "type", i])
		if hit.has_point(_mouse):
			_set_tip("type%d" % i, HudTooltip.simple(TYPE_BUTTONS[i][1], ""), hit)
	# stat filters column
	L.draw(self, F + "ItemShop_StatFilters_KeyLine")
	for p in 3:
		L.draw(self, F + "ItemShop_StatFilters_Pike%d" % (p + 1))
	for i in STAT_KEYS.size():
		var sk: String = STAT_KEYS[i]
		var dk := F + _stat_key(sk, "Default")
		var r := L.r(dk)
		if r.size.x <= 0.0:
			continue
		var hit := Rect2(r.get_center() - Vector2(17, 15) * L.s(), Vector2(34, 30) * L.s())
		var on := stat_filter == i
		if on:
			L.draw_in(self, F + _stat_key(sk, "SelectionHighlight"), hit)
		L.draw(self, dk if on or hit.has_point(_mouse) or stat_filter < 0 else F + _stat_key(sk, "Inactive"))
		_hits.append([hit, "stat", i])
		if hit.has_point(_mouse):
			_set_tip("stat%d" % i, HudTooltip.simple(ItemDB.STAT_FILTERS[i][1], "Show items with this stat"), hit)
	# tiered grid
	var area := Rect2(L.pt(F + "ItemShop_AllItems_HeaderText", Vector2(343, 350)), Vector2(565, 535) * L.s())
	var items := _all_items()
	var groups := {}
	for id in items:
		var t := ItemDB.tier_of(id)
		if t == "Consumable":
			t = "Legendary"
		if not groups.has(t):
			groups[t] = []
		groups[t].append(id)
	var s := L.s()
	var cols := maxi(1, int(area.size.x / (CELL_PITCH.x * s)))
	var y := area.position.y - scroll * s
	var y0 := y
	if items.is_empty():
		HudLayout.text_in(self, Rect2(area.position, Vector2(area.size.x, 60 * s)), "No items match", f_body, maxi(11, int(15 * s)), C_DIM, 1, 0.0)
	for tier in TIER_ORDER:
		if not groups.has(tier):
			continue
		var hr := Rect2(area.position.x, y, area.size.x, 30 * s)
		if hr.position.y >= area.position.y - 2 and hr.end.y <= area.end.y:
			HudLayout.text_in(self, hr, tier.to_upper(), f_title, maxi(11, int(15 * s)), C_GOLD, 0, 0.0)
			draw_line(Vector2(hr.position.x + f_title.get_string_size(tier.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(11, int(15 * s))).x + 10 * s, hr.get_center().y),
				Vector2(hr.end.x - 8 * s, hr.get_center().y), Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.25), 1.0)
		y += 32 * s
		var list: Array = groups[tier]
		for i in list.size():
			var col := i % cols
			if col == 0 and i > 0:
				y += CELL_PITCH.y * s
			var cell := Rect2(area.position.x + col * CELL_PITCH.x * s + 4 * s, y, 44 * s, 44 * s)
			if cell.position.y >= area.position.y - 1 and cell.end.y + 16 * s <= area.end.y:
				_item_cell(cell, list[i], true)
		y += CELL_PITCH.y * s + 4 * s
	_scroll_max = maxf(0.0, (y - y0) / s - area.size.y / s)
	scroll = minf(scroll, _scroll_max)
	if _scroll_max > 0.0:
		var track := Rect2(area.end.x + 2 * s, area.position.y, 6 * s, area.size.y)
		var hgt := maxf(30 * s, track.size.y * area.size.y / (area.size.y + _scroll_max * s))
		var ty := track.position.y + (track.size.y - hgt) * (scroll / _scroll_max)
		HudLayout.region(self, "itemshop_texture_atlas", Rect2(1000, 135, 6, 40), Rect2(track.position.x, ty, track.size.x, hgt))


func _stat_key(sk: String, state: String) -> String:
	var icon := {"PhysicalDamage": "PhysicalDamage", "CriticalStrike": "CriticalStrike", "ArmorPen": "ArmorPen", "MagicPen": "MagicPen"}
	var hl := {"PhysicalDamage": "PD", "CriticalStrike": "CS", "Movespeed": "MoveSpeed"}
	if state == "SelectionHighlight":
		return "%s_SelectionHighlight" % hl.get(sk, sk)
	return "%s_%s" % [icon.get(sk, sk), state]


# --------------------------------------------------------------------- item cells
func _item_icon(id: int) -> Texture2D:
	return Assets.item_icon(id) if id != 9999 else Assets.augment_icon("ARAM_Stats")


## Standard shop cell (ItemShop_ItemPageTemplate): frame, icon, cost under it.
func _item_cell(r: Rect2, id: int, with_cost: bool) -> void:
	var c = champ()
	var price: int = ItemDB.price_for(c, id)[0]
	var afford: bool = c.gold >= price
	var owned := _owns(id)
	var hov := r.grow(4).has_point(_mouse)
	var sel := selected == id and selected_owned == null
	var T := SH + "ItemShop_ItemPageTemplate_Item_"
	if sel:
		L.draw_in(self, T + "SelectedMajor", Rect2(r.position - Vector2(4, 5) * L.s(), Vector2(52, 74) * L.s()))
	elif hov:
		L.draw_in(self, T + "HoverMajor", Rect2(r.position - Vector2(4, 5) * L.s(), Vector2(52, 74) * L.s()), Color(1, 1, 1, 0.7))
	var icon := _item_icon(id)
	var ir := r.grow(-2.0 * L.s())
	if icon != null:
		draw_texture_rect(icon, ir, false, Color.WHITE if afford or owned else Color(0.48, 0.48, 0.5))
	L.draw_in(self, T + ("FrameHover" if hov or sel else "Frame"), r)
	if owned:
		L.draw_in(self, T + "Purchased", Rect2(r.get_center() - Vector2(13, 10.5) * L.s(), Vector2(26, 21) * L.s()))
	if with_cost or true:
		var cr := Rect2(r.position.x - 6 * L.s(), r.end.y + 2 * L.s(), r.size.x + 12 * L.s(), 14 * L.s())
		HudLayout.text_in(self, cr, str(price), f_bold, maxi(10, int(13 * L.s())), C_GOLD_TXT if afford else Color(0.55, 0.5, 0.42), 1, 0.0)
	_hits.append([r.grow(3.0), "item", id])
	if hov:
		_set_tip("cell%d" % id, HudTooltip.item(id, c), r)


func _item_cell_small(r: Rect2, id: int) -> void:
	var owned := _owns(id)
	var icon := _item_icon(id)
	if icon != null:
		draw_texture_rect(icon, r, false, Color.WHITE if owned or champ().gold >= ItemDB.price_for(champ(), id)[0] else Color(0.5, 0.5, 0.52))
	draw_rect(r, C_TEAL if owned else Color(0.47, 0.35, 0.16), false, 1.5 if owned else 1.0)
	_hits.append([r, "item", id])
	if r.has_point(_mouse):
		_set_tip("small%d" % id, HudTooltip.item(id, champ()), r)


func _gold_amount(r: Rect2, amount: int, size_src: float, col: Color) -> void:
	var px := maxi(10, int(size_src * L.s()))
	var s := str(amount)
	var w := f_bold.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var coin := Vector2(px * 0.95, px * 0.85)
	var x := r.get_center().x - (w + coin.x + 4) * 0.5
	HudLayout.region(self, "itemshop_texture_atlas", Rect2(2, 2, 32, 28), Rect2(Vector2(x, r.get_center().y - coin.y * 0.5), coin))
	HudLayout.text_in(self, Rect2(x + coin.x + 4, r.position.y, w, r.size.y), s, f_bold, px, col, 0, 0.0)


func _set_tip(key: String, t: Dictionary, r: Rect2) -> void:
	_tip_seen = true
	if key != _hover_key:
		_hover_key = key
		_hover_tip = t
	_hover_rect = r


# --------------------------------------------------------------------- right panel: builds into, tree, details
func _draw_build_panel() -> void:
	var c = champ()
	L.text(self, SH + "ItemShop_BuildsInto_Label", "BUILDS INTO", f_title, 13, C_DIM, 0, Vector2.ZERO, 0.0)
	var into := ItemDB.builds_into(selected) if selected >= 0 else []
	for i in 7:
		var r := L.r(SH + "ItemShop_BuildsInto_Slot%d" % (i + 1))
		if i < into.size():
			_item_cell(r, into[i], false)
		else:
			L.draw(self, SH + "ItemShop_BuildsInto_EmptyState%d" % (i + 1), Color(1, 1, 1, 0.5))
	L.draw(self, SH + "ItemShop_KeyLine_ItemDetailsTop")
	if selected < 0 or not ItemDB.has(selected):
		return
	# build tree: selected item on top, components below, their components below that
	var tree_top := L.pt(SH + "ItemShop_KeyLine_ItemDetailsTop", Vector2(1131, 306))
	var s := L.s()
	var node := Vector2(40, 40) * s
	var root_r := Rect2(tree_top - Vector2(node.x * 0.5, 0), node)
	_tree_pool = ItemDB.price_for(c, selected)[1].duplicate()
	_tree_node(root_r, selected, true)
	var comps := ItemDB.components_of(selected)
	if not comps.is_empty():
		var lvl1_y := root_r.end.y + 52 * s
		var span := 372.0 * s
		var n := comps.size()
		var line_col := Color(0.47, 0.35, 0.16, 0.9)
		var mid_y := root_r.end.y + 26 * s
		draw_line(Vector2(root_r.get_center().x, root_r.end.y + 14 * s), Vector2(root_r.get_center().x, mid_y), line_col, 1.5)
		var xs := []
		for i in n:
			xs.append(tree_top.x + span * ((i + 0.5) / n - 0.5))
		if n > 1:
			draw_line(Vector2(xs[0], mid_y), Vector2(xs[n - 1], mid_y), line_col, 1.5)
		for i in n:
			var x: float = xs[i]
			draw_line(Vector2(x, mid_y), Vector2(x, lvl1_y), line_col, 1.5)
			var r := Rect2(Vector2(x - node.x * 0.5, lvl1_y), node)
			_tree_node(r, comps[i])
			var sub := ItemDB.components_of(comps[i])
			if not sub.is_empty():
				var sy := r.end.y + 46 * s
				var sm := r.end.y + 22 * s
				draw_line(Vector2(x, r.end.y + 14 * s), Vector2(x, sm), line_col, 1.5)
				var sw := span / n * 0.9
				var sxs := []
				for j in sub.size():
					sxs.append(x + sw * ((j + 0.5) / sub.size() - 0.5))
				if sub.size() > 1:
					draw_line(Vector2(sxs[0], sm), Vector2(sxs[sub.size() - 1], sm), line_col, 1.5)
				for j in sub.size():
					draw_line(Vector2(sxs[j], sm), Vector2(sxs[j], sy), line_col, 1.5)
					_tree_node(Rect2(Vector2(sxs[j] - node.x * 0.42, sy), node * 0.84), sub[j])
	# purchase button
	var reason := ItemDB.buy_block_reason(c, selected)
	var br := L.r(SH + "ItemShop_PurchaseButton_Default")
	var hov := br.has_point(_mouse)
	var can := reason == ""
	L.draw(self, SH + ("ItemShop_PurchaseButton_Disabled" if not can else ("ItemShop_PurchaseButton_Hover" if hov else "ItemShop_PurchaseButton_Default")))
	var price: int = ItemDB.price_for(c, selected)[0]
	var label := "PURCHASE"
	if not can:
		label = {"You can only shop while dead or in base": "DEAD OR IN BASE ONLY", "Not enough gold": "NOT ENOUGH GOLD",
			"Inventory full": "INVENTORY FULL", "Requires level 16": "REQUIRES LEVEL 16"}.get(reason, "UNAVAILABLE")
	if _owns(selected) and can:
		label = "PURCHASE ANOTHER"
	L.text(self, SH + "ItemShop_PurchaseButton_Text", label, f_title, 14, C_TEXT if can else Color(0.6, 0.58, 0.55), 1, Vector2(-30, 0), 0.0)
	var pr := L.r(SH + "ItemShop_PurchaseButton_Text")
	_gold_amount(Rect2(pr.end.x - 70 * s, pr.position.y, 70 * s, pr.size.y), price, 15, C_GOLD_TXT if c.gold >= price else C_RED)
	_hits.append([br, "buy", 0])
	L.draw(self, SH + "ItemShop_KeyLine_ItemDetailsBottom")
	# details: icon, name, cost, stats + passive text
	var ir := L.r(SH + "ItemShop_ItemDescription_ItemIcon")
	var icon := _item_icon(selected)
	if icon != null:
		draw_texture_rect(icon, ir, false)
	draw_rect(ir, Color(0.47, 0.35, 0.16), false, 1.0)
	L.text(self, SH + "ItemShop_ItemDescription_TitleText", ItemDB.name_of(selected), f_title, 16, C_TEXT, 0, Vector2.ZERO, 0.0)
	L.draw(self, SH + "ItemShop_ItemDescription_GoldIcon")
	var cost_s := str(ItemDB.cost_of(selected))
	if price != ItemDB.cost_of(selected):
		cost_s = "%d  (%d)" % [price, ItemDB.cost_of(selected)]
	L.text(self, SH + "ItemShop_ItemDescription_CostText", cost_s, f_bold, 14, C_GOLD_TXT, 0, Vector2.ZERO, 0.0)
	L.draw(self, SH + "ItemShop_KeyLine_ItemDetailsTooltip")
	var tip := HudTooltip.item(selected, c, selected_owned)
	var body := L.r(SH + "ItemShop_ItemDescription_Body")
	var px := maxi(11, int(14 * s))
	var lh := px * 1.4
	var y := body.position.y + px
	var limit := panel.end.y - 70 * s
	for ln in tip.lines:
		var f: Font = f_bold if ln[2] else f_body
		if String(ln[0]) == "":
			y += lh * 0.5
			continue
		for wl in HudTooltip.wrap_text(String(ln[0]), f, px, body.size.x):
			if y > limit:
				break
			draw_string(f, Vector2(body.position.x, y), wl, HORIZONTAL_ALIGNMENT_LEFT, -1, px, ln[1])
			y += lh


func _tree_node(r: Rect2, id: int, root := false) -> void:
	var c = champ()
	var owned := false
	if root:
		owned = _owns(id)
	else:
		# depth-first like ItemDB._discount, so each owned item marks exactly one recipe slot
		for it in _tree_pool:
			if it.item_id == id:
				owned = true
				_tree_pool.erase(it)
				break
	var icon := _item_icon(id)
	var price: int = ItemDB.price_for(c, id)[0]
	var hov := r.has_point(_mouse)
	if icon != null:
		draw_texture_rect(icon, r, false, Color.WHITE if owned or c.gold >= price else Color(0.55, 0.55, 0.58))
	if owned:
		# League marks owned components with a teal frame and a check
		draw_rect(r.grow(1.0), C_TEAL, false, 2.0)
		L.draw_in(self, SH + "ItemShop_ItemPageTemplate_Item_Purchased", Rect2(r.get_center() - Vector2(13, 10.5) * L.s(), Vector2(26, 21) * L.s()))
	else:
		L.draw_in(self, SH + "ItemShop_ItemPageTemplate_Item_" + ("FrameHover" if hov or selected == id else "Frame"), r.grow(2.0 * L.s()))
	var cr := Rect2(r.position.x - 10 * L.s(), r.end.y + 1 * L.s(), r.size.x + 20 * L.s(), 13 * L.s())
	HudLayout.text_in(self, cr, "Owned" if owned else str(price), f_bold, maxi(10, int(12 * L.s())), C_TEAL if owned else (C_GOLD_TXT if c.gold >= price else Color(0.55, 0.5, 0.42)), 1, 0.0)
	_hits.append([r, "item", id])
	if hov:
		_set_tip("tree%d" % id, HudTooltip.item(id, c), r)


# --------------------------------------------------------------------- footer
func _draw_footer() -> void:
	var c = champ()
	var can_sell: bool = selected_owned != null and c.can_shop()
	var sr := L.r(SH + "ItemShop_SellButton_ButtonDefault")
	L.draw(self, SH + ("ItemShop_SellButton_ButtonDisabled" if not can_sell else ("ItemShop_SellButton_ButtonHover" if sr.has_point(_mouse) else "ItemShop_SellButton_ButtonDefault")))
	var sell_txt := "SELL" if selected_owned == null else "SELL %d" % int(selected_owned.cost * 0.7)
	L.text(self, SH + "ItemShop_SellButton_Text", sell_txt, f_title, 13, C_TEXT if can_sell else Color(0.5, 0.5, 0.5), 1, Vector2.ZERO, 0.0)
	_hits.append([sr, "sell", 0])
	var ur := L.r(SH + "ItemShop_UndoButton_ButtonDefault")
	var can_undo := not _undo.is_empty()
	L.draw(self, SH + ("ItemShop_UndoButton_ButtonDisabled" if not can_undo else ("ItemShop_UndoButton_ButtonHover" if ur.has_point(_mouse) else "ItemShop_UndoButton_ButtonDefault")))
	L.text(self, SH + "ItemShop_UndoButton_Text", "UNDO", f_title, 13, C_TEXT if can_undo else Color(0.5, 0.5, 0.5), 1, Vector2.ZERO, 0.0)
	_hits.append([ur, "undo", 0])
	L.draw(self, SH + "ItemShop_Footer_GoldIcon")
	L.text(self, SH + "ItemShop_Footer_GoldText", str(int(c.gold)), f_bold, 18, C_GOLD_TXT, 0, Vector2(0, 2), 0.0)
	# ARAM rule, shown the way League shows a shop lock: a clear line in the footer
	var info := Rect2(L.pt(SH + "ItemShop_Footer_GoldText", Vector2(660, 900)), Vector2(250, 34) * L.s())
	if not c.can_shop():
		_draw_lock(info)
	if msg_t > 0.0:
		var a := minf(1.0, msg_t * 2.0)
		var mr := Rect2(L.pt(SH + "ItemShop_Footer_GoldText", Vector2(940, 900)), Vector2(382, 34) * L.s())
		HudLayout.text_in(self, mr, msg, f_bold, maxi(11, int(14 * L.s())), Color(C_RED.r, C_RED.g, C_RED.b, a), 1, 2.0)
	var hint := Rect2(L.pt(SH + "ItemShop_Footer_GoldText", Vector2(660, 930)), Vector2(250, 20) * L.s())
	HudLayout.text_in(self, hint, "Right-click or double-click to buy  ·  Ctrl+Z undo", f_body, maxi(9, int(11 * L.s())), Color(0.5, 0.5, 0.48), 0, 0.0)


func _draw_lock(r: Rect2) -> void:
	var px := maxi(10, int(13 * L.s()))
	HudLayout.region(self, "itemshop_texture_atlas", Rect2(38, 2, 68, 68), Rect2(r.position + Vector2(0, (r.size.y - 22 * L.s()) * 0.5), Vector2(22, 22) * L.s()))
	HudLayout.text_in(self, Rect2(r.position + Vector2(26 * L.s(), 0), r.size), "Shopping only while dead or in base", f_bold, px, C_RED, 0, 0.0)
