class_name ShopPanel
extends Control
## League's in-game item shop, built from the ItemShop layout in UI.wad.client (assets/ui/hud/layout.json) with League's own
## item data (ItemDB) and rules (ShopSession).
##
## Tabs: Recommended / All Items / Item Sets (Ctrl+Tab cycles). Left-click selects (build tree + details), right-click or
## double-click buys, the Purchase button reads PURCHASE ITEM / PURCHASE COMPONENTS / NOT ENOUGH GOLD / TOO FAR FROM SHOP ...
## Search: click the bar or Ctrl+L / Ctrl+Enter, type a name, nickname ("ie", "bc", "dcap"), stat or passive; Enter buys the first hit.
## Left side quick panels: Consumables, Boots, Inventory (click the tab to expand, pin to keep it open).
## Footer: Sell (selected inventory item), Undo (also Ctrl+Z; cleared when leaving the base), gold.
## ARAM rule: buying / selling only while dead or on the spawn platform.

const SH := "Shop:"
const FRAME_KEY := SH + "ItemShop_BackdropFrame_TopLeft"
const C_TEXT := Color(0.941, 0.902, 0.824)
const C_DIM := Color(0.647, 0.627, 0.588)
const C_GOLD := Color(0.784, 0.667, 0.431)
const C_GOLD_TXT := Color(0.94, 0.8, 0.42)
const C_GOLD_POOR := Color(0.55, 0.5, 0.42)
const C_RED := Color(0.92, 0.36, 0.3)
const C_TEAL := Color(0.04, 0.78, 0.73)
const C_LINE := Color(0.47, 0.35, 0.16, 0.9)
const CELL_PITCH := Vector2(56, 78)
const TABS := [["rec", "RECOMMENDED"], ["all", "ALL ITEMS"], ["sets", "ITEM SETS"]]
const TYPE_BUTTONS := [
	["AllBtn_IconDefault", "All", ""], ["AtkBtn_IconDefault", "Fighter", "fighter"], ["MarkBtn_IconDefault", "Marksman", "marksman"],
	["AssBtn_IconDefault", "Assassin", "assassin"], ["MagBtn_IconDefault", "Mage", "mage"], ["DefBtn_IconDefault", "Tank", "tank"],
	["UtilBtn_IconDefault", "Support", "support"],
]
const STAT_KEYS := ["PhysicalDamage", "CriticalStrike", "AttackSpeed", "OnHit", "ArmorPen", "AbilityPower", "Mana", "MagicPen",
	"Health", "Armor", "MagicResist", "AbilityHaste", "Movespeed", "Vamp"]
const PANELS := [
	["cons", "ItemShop_ConsumablesPanel", "ConsumablesPanel_PinBtn", 12, "ItemShop_ConsumablesPanel_Slot%d"],
	["boots", "ItemShop_BootsPanel", "BootsPanel_PinButton", 9, "ItemShop_BootsPanel_Slot%d"],
	["inv", "ItemShop_Inventory_Panel", "InventoryPanel_PinButton", 7, "ItemShop_Inventory_Panel_Slot%d"],
]

var hud = null
var L := HudLayout.new()
var session := ShopSession.new()
var tab := "rec"
var search := ""
var search_focus := false
var type_filter := 0
var stat_filter := -1
var popular_only := false
var invert_groups := false
var selected := -1
var selected_owned = null
var scroll := {"all": 0.0, "sets": 0.0, "search": 0.0, "details": 0.0}
var _scroll_max := {"all": 0.0, "sets": 0.0, "search": 0.0, "details": 0.0}
var _hits: Array = []                 ## [Rect2, kind, value]
var _mouse := Vector2(-1, -1)
var _tip_id := -1                     ## item under the mouse (tooltip)
var _tip_owned = null
var _tip_rect := Rect2()
var _tip_since := 0
var _hover_sound_id := -1
var _panel_open := {"cons": false, "boots": false, "inv": false}
var _panel_pin := {"cons": false, "boots": false, "inv": false}
var _last_click_t := 0
var _last_click_id := -1
var _last_click_pos := Vector2(-9999, -9999)   ## [ui-fix] where the last item click landed (double-click = same spot, not same widget)
var _click_pos := Vector2.ZERO               ## [ui-fix] position of the click being dispatched
const DBL_MS := 380
const DBL_PX := 14.0
var _drop_open := false               ## "builds into" overflow list
var _caret_t := 0.0
var msg := ""
var msg_t := 0.0
var f_title: Font
var f_body: Font
var f_bold: Font
var panel := Rect2()
var _was_visible := false


func _ready() -> void:
	L.font_k = 1.0   # [hud-ref] the shop layout was tuned with League font sizes taken as plain px
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	f_title = Assets.font("beaufort", "Bold")
	f_body = Assets.font("spiegel", "Regular")
	f_bold = Assets.font("spiegel", "Bold")
	visibility_changed.connect(_on_visibility)
	session.message.connect(_msg)


func _on_visibility() -> void:
	if visible == _was_visible:
		return
	_was_visible = visible
	if visible:
		search = ""
		search_focus = false
		_drop_open = false
		for k in scroll:
			scroll[k] = 0.0
		for p in PANELS:
			_panel_open[p[0]] = _panel_pin[p[0]]
		if champ() != null and selected < 0 or (selected >= 0 and not ItemDB.has(selected)):
			var s := ItemDB.suggested(champ(), 1)
			selected = s[0] if not s.is_empty() else -1
		ShopSfx.cue("open")
	else:
		# League clears the undo history when you leave the shop
		session.clear()
		ShopSfx.cue("close")


func refresh() -> void:
	queue_redraw()


func champ():
	return G.player


func _process(delta: float) -> void:
	if not visible:
		return
	msg_t = maxf(0.0, msg_t - delta)
	_caret_t += delta
	var c = champ()
	if c != null:
		session.tick(c)   # leaving the base clears the undo history
	queue_redraw()


func _msg(s: String) -> void:
	msg = s
	msg_t = 2.5


# ===================================================================== geometry helpers
func _sc() -> float:
	return L.scale_of(L.e(FRAME_KEY))


## A rect given in the 1600x1200 layout space -> screen.
func _sr(x: float, y: float, w: float, h: float) -> Rect2:
	return Rect2(L.pt(FRAME_KEY, Vector2(x, y)), Vector2(w, h) * _sc())


# ===================================================================== data
func _owns(id: int) -> bool:
	for it in champ().items:
		if it.item_id == id:
			return true
	return false


func _in_plan(id: int) -> bool:
	return id in ItemDB.rec_plan(champ()).full


func _all_items() -> Array:
	var c = champ()
	var out := []
	var plan: Array = ItemDB.rec_plan(c).full if popular_only else []
	for id in ItemDB.grid_items(c):
		if type_filter > 0 and not ItemDB.matches_class(id, TYPE_BUTTONS[type_filter][2]):
			continue
		if stat_filter >= 0 and not ItemDB.matches_stat_filter(id, stat_filter):
			continue
		if popular_only and not (id in plan or ItemDB.tier_group(id) == "legendary" and _builds_into_plan(id, plan)):
			continue
		out.append(id)
	out.sort_custom(func(a, b): return ItemDB.cost_of(a) < ItemDB.cost_of(b) or (ItemDB.cost_of(a) == ItemDB.cost_of(b) and ItemDB.name_of(a) < ItemDB.name_of(b)))
	return out


func _builds_into_plan(id: int, plan: Array) -> bool:
	for p in plan:
		if p == id:
			return true
	return false


func _search_results() -> Array:
	var out := []
	var c = champ()
	var scored := []
	for id in ItemDB.META:
		if not ItemDB.visible_in_shop(id, c):
			continue
		var sc: int = ItemDB.search_score(id, search)
		if sc > 0:
			scored.append([sc, id])
	scored.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and ItemDB.cost_of(a[1]) < ItemDB.cost_of(b[1])))
	for e in scored:
		out.append(e[1])
	return out


# ===================================================================== actions
func _select(id: int, owned = null) -> void:
	if id == selected and owned == selected_owned:
		return
	selected = id
	selected_owned = owned
	scroll["details"] = 0.0
	_drop_open = false


## [cc-anim] the shop view a double-click must not disturb: what is selected (= root of the recipe tree) and how the
## details pane is scrolled / the "builds into" list is folded.
var _pre_click := {}


func _view_state() -> Dictionary:
	return {"selected": selected, "owned": selected_owned, "details": scroll["details"], "drop": _drop_open}


func _restore_view(v: Dictionary) -> void:
	selected = v.selected
	selected_owned = v.owned
	# the selected owned item may just have been consumed by the purchase (components -> recipe)
	if selected_owned != null and not (selected_owned in champ().items):
		selected_owned = null
	scroll["details"] = v.details
	_drop_open = v.drop


func _buy(id: int) -> void:
	var c = champ()
	if session.buy(c, id):
		selected_owned = null


func _sell() -> void:
	var c = champ()
	if session.sell(c, selected_owned):
		selected_owned = null


func _undo_last() -> void:
	if session.undo_last(champ()):
		selected_owned = null


## Sell a specific owned item (HUD drag-and-drop onto the shop).
func sell_item(it) -> void:
	selected_owned = it
	selected = it.item_id
	_sell()


## [ui-fix] League double-click: two left clicks within DBL_MS at (nearly) the same screen spot. Matching by position, not by
## item id, because the first click re-roots the build tree / re-lays-out the panel, so the second click usually lands on a
## different node (or the root) than the first one. The first-clicked item is the one that gets bought.
func _is_double_click() -> bool:
	return _last_click_id >= 0 and Time.get_ticks_msec() - _last_click_t < DBL_MS and _click_pos.distance_to(_last_click_pos) <= DBL_PX


func _note_click(id: int) -> void:
	_last_click_id = id
	_last_click_t = Time.get_ticks_msec()
	_last_click_pos = _click_pos


## "Item clicked" semantics shared by every item cell (grid, search, recipe tree, builds-into, ...): left = select,
## double-click buys, right = buy.
func _item_click(id: int, right: bool, owned = null) -> void:
	if right:
		_select(id, owned)
		if owned != null:
			_sell()
		else:
			_buy(id)
		_last_click_id = -1
		return
	_select(id, owned)
	ShopSfx.cue("select")
	if owned == null:
		_note_click(id)
	else:
		_last_click_id = -1


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
	if hud != null and champ() != null:
		for i in mini(6, champ().items.size()):
			var ir: Rect2 = hud.L.r("Inventory:InventoryItem%d_Backdrop" % i)
			if ir.has_point(mp) and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT):
				var it = champ().items[i]
				_select(it.item_id, it)
				if mb.button_index == MOUSE_BUTTON_RIGHT:
					_sell()
					get_viewport().set_input_as_handled()
				# left click is left to the HUD so the item can be dragged (swap slots / drop on the shop to sell)
				return
	if not (panel.has_point(mp) or _in_side_panels(mp)):
		return
	get_viewport().set_input_as_handled()
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_wheel(mp, -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0)
		return
	var right := mb.button_index == MOUSE_BUTTON_RIGHT
	if mb.button_index != MOUSE_BUTTON_LEFT and not right:
		return
	_click_pos = mp
	if not right and _is_double_click():
		# [ui-fix] double-click buys the item that was clicked first, wherever the (re-laid-out) panel now has the cursor.
		# [cc-anim] ...and leaves the panel exactly as it was before the first click (League: no navigation to the
		# bought item): the selection / build-tree root / details scroll are put back afterwards.
		var bid := _last_click_id
		_last_click_id = -1
		var pre := _pre_click
		_pre_click = {}
		_buy(bid)
		if not pre.is_empty():
			_restore_view(pre)
		return
	if not right:
		_pre_click = _view_state()
	for i in range(_hits.size() - 1, -1, -1):
		var h: Array = _hits[i]
		if not (h[0] as Rect2).has_point(mp):
			continue
		if h[1] != "item" and h[1] != "rec_item":
			_last_click_id = -1
		_hit(h, right)
		return
	_last_click_id = -1
	# click on empty shop space: unfocus search, fold unpinned quick panels
	search_focus = false
	for p in PANELS:
		if not _panel_pin[p[0]] and _panel_open[p[0]] and not _panel_rect(p).has_point(mp):
			_panel_open[p[0]] = false
			ShopSfx.cue("quicktab_close")
	_drop_open = false


func _in_side_panels(mp: Vector2) -> bool:
	for p in PANELS:
		if _panel_rect(p).has_point(mp):
			return true
	return false


func _panel_rect(p: Array) -> Rect2:
	var key: String = SH + p[1] + ("_ExpandedRegion" if _panel_open[p[0]] else "_Closed")
	var rc := L.r(key)
	if rc.size.x <= 0.0:
		rc = L.r(SH + p[1] + "_Closed")
	return rc


func _hit(h: Array, right: bool) -> void:
	match h[1]:
		"close":
			visible = false
		"tab":
			if tab != h[2]:
				tab = h[2]
				ShopSfx.cue("tab")
		"search":
			search_focus = true
		"clear_search":
			search = ""
			search_focus = false
			ShopSfx.cue("filter_remove")
		"type":
			if type_filter == h[2]:
				if h[2] != 0:
					type_filter = 0
					ShopSfx.cue("filter_remove")
			else:
				type_filter = h[2]
				ShopSfx.cue("filter_class")
			if h[2] == 0:
				stat_filter = -1
				popular_only = false
			scroll["all"] = 0.0
		"popular":
			popular_only = not popular_only
			ShopSfx.cue("filter_class" if popular_only else "filter_remove")
			scroll["all"] = 0.0
		"invert":
			invert_groups = not invert_groups
			ShopSfx.cue("filter_invert")
			scroll["all"] = 0.0
		"stat":
			if stat_filter == h[2]:
				stat_filter = -1
				ShopSfx.cue("filter_remove")
			else:
				stat_filter = h[2]
				ShopSfx.cue("filter_stat")
			scroll["all"] = 0.0
		"buy":
			if selected >= 0:
				_buy(selected)
		"sell":
			_sell()
		"undo":
			_undo_last()
		"panel_tab":
			var k: String = h[2]
			_panel_open[k] = not _panel_open[k]
			ShopSfx.cue(("inventory_open" if _panel_open[k] else "inventory_close") if k == "inv" else ("quicktab_open" if _panel_open[k] else "quicktab_close"))
		"panel_pin":
			var k2: String = h[2]
			_panel_pin[k2] = not _panel_pin[k2]
			ShopSfx.cue("quicktab_pin")
		"inv_item":
			_item_click(h[2].item_id, right, h[2])
		"overflow":
			_drop_open = not _drop_open
			ShopSfx.cue("expand")
		"rec_item":
			if right:
				_select(h[2])
				_buy(h[2])
				_last_click_id = -1
			else:
				_select(h[2])
				_note_click(h[2])
				ShopSfx.cue("rec_select")
		"item":
			_item_click(h[2], right)
			if _drop_open:
				_drop_open = false
		"search_buy":
			if selected >= 0:
				_buy(selected)


func _wheel(mp: Vector2, dir: float) -> void:
	var area := "all"
	if search != "":
		area = "search"
	elif tab == "sets":
		area = "sets"
	elif tab == "rec":
		area = ""
	var det := L.r(SH + "ItemShop_ItemDescription_Body")
	if det.grow(60).has_point(mp) or mp.x > L.r(SH + "ItemShop_KeyLine_Right").position.x:
		area = "details"
	if area == "":
		return
	scroll[area] = clampf(scroll[area] + dir * CELL_PITCH.y * 0.6, 0.0, _scroll_max[area])


func _key(ev: InputEventKey) -> void:
	var handled := true
	var c = champ()
	if ev.keycode == KEY_ESCAPE:
		if search != "" or search_focus:
			search = ""
			search_focus = false
		else:
			visible = false
	elif ev.keycode == KEY_Z and ev.ctrl_pressed:
		_undo_last()
	elif (ev.keycode == KEY_L and ev.ctrl_pressed) or (ev.ctrl_pressed and (ev.keycode == KEY_ENTER or ev.keycode == KEY_KP_ENTER)):
		search_focus = true
	elif ev.keycode == KEY_TAB and ev.ctrl_pressed:
		var idx := 0
		for i in TABS.size():
			if TABS[i][0] == tab:
				idx = i
		tab = TABS[(idx + (-1 if ev.shift_pressed else 1) + TABS.size()) % TABS.size()][0]
		search = ""
		search_focus = false
		ShopSfx.cue("tab")
	elif search_focus and ev.keycode == KEY_BACKSPACE:
		search = search.substr(0, maxi(0, search.length() - 1))
		scroll["search"] = 0.0
	elif ev.keycode == KEY_ENTER or ev.keycode == KEY_KP_ENTER:
		if search != "":
			var list := _search_results()
			if not list.is_empty() and not (selected in list):
				_select(list[0])
		if selected >= 0:
			_buy(selected)
	elif search_focus and ev.unicode >= 32 and ev.unicode < 127 and not ev.ctrl_pressed and not ev.alt_pressed:
		if search.length() < 28:
			search += char(ev.unicode)
			scroll["search"] = 0.0
			var list2 := _search_results()
			if not list2.is_empty():
				_select(list2[0])
	elif ev.keycode == KEY_P and not ev.ctrl_pressed:
		visible = false
	elif ev.keycode == KEY_DELETE and selected_owned != null:
		_sell()
	elif ev.keycode == KEY_TAB:
		handled = false     # scoreboard still works
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
	_tip_id = -1
	_tip_owned = null
	var c = champ()
	if c == null:
		return
	panel = L.r(SH + "ItemShop_BackdropFrame_TopLeft").merge(L.r(SH + "ItemShop_BackdropFrame_BottomRight"))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.18))
	_draw_side_panels(c)
	for p in ["TopLeft", "Top", "TopRight", "Left", "Fill", "Right", "BottomLeft", "Bottom", "BottomRight"]:
		L.draw(self, SH + "ItemShop_BackdropFrame_" + p)
	L.draw(self, SH + "ItemShop_Magic_ListView", Color(1, 1, 1, 0.5))
	L.draw(self, SH + "ItemShop_Magic_BuildTree", Color(1, 1, 1, 0.55))
	L.draw(self, SH + "ItemShop_KeyLine_Right")
	L.draw(self, SH + "ItemShop_KeyLine_Tabs")
	L.draw(self, SH + "ItemShop_KeyLine_Footer")
	var cr := L.r(SH + "ItemShop_MenuClose_ButtonDefault")
	L.draw(self, SH + ("ItemShop_MenuClose_ButtonHover" if cr.grow(4).has_point(_mouse) else "ItemShop_MenuClose_ButtonDefault"))
	_hits.append([cr.grow(6.0), "close", 0])
	_draw_tabs()
	_draw_search()
	match tab:
		"rec":
			_draw_recommended(c)
		"all":
			_draw_all_items(c)
		"sets":
			_draw_sets(c)
	_draw_build_panel(c)
	_draw_footer(c)
	if search != "":
		_draw_search_view(c)
	_draw_sell_overlay(c)
	# hover tooltip (League shows it after a short delay)
	if _tip_id >= 0:
		if _hover_sound_id != _tip_id:
			_hover_sound_id = _tip_id
			_tip_since = Time.get_ticks_msec()
			ShopSfx.cue("hover", -6.0, 120)
		if Time.get_ticks_msec() - _tip_since > 150:
			ItemTip.draw(self, _tip_id, c, _tip_rect, size, size.y / 1080.0, _tip_owned)
	else:
		_hover_sound_id = -1


func _hover(id: int, r: Rect2, owned = null) -> void:
	if r.has_point(_mouse):
		_tip_id = id
		_tip_owned = owned
		_tip_rect = r


# --------------------------------------------------------------------- tabs / search
func _draw_tabs() -> void:
	for i in TABS.size():
		var off := Vector2(215.0 * i, 0)
		var r := L.r(SH + "ItemShop_TabButton_Default", off)
		var on: bool = tab == TABS[i][0]
		var hov := r.has_point(_mouse)
		L.draw(self, SH + "ItemShop_TabButton_Default", Color(1, 1, 1, 1.0 if on else (0.7 if hov else 0.45)), off)
		if on:
			draw_rect(Rect2(r.position.x + r.size.x * 0.1, r.end.y - 2.0, r.size.x * 0.8, 2.0), C_GOLD)
		L.text(self, SH + "ItemShop_TabButton_Text", TABS[i][1], f_title, 13, C_TEXT if on else C_DIM, 1, off, 0.0)
		_hits.append([r, "tab", TABS[i][0]])


func _draw_search() -> void:
	L.draw(self, SH + "ItemShop_SearchBar_BarLeft")
	var bar := L.draw(self, SH + "ItemShop_SearchBar_BarStretch")
	L.draw(self, SH + "ItemShop_SearchBar_BarRight")
	L.draw(self, SH + "ItemShop_SearchBar_SearchIcon")
	var caret := "|" if search_focus and int(_caret_t * 2.0) % 2 == 0 else " "
	if search == "" and not search_focus:
		L.text(self, SH + "ItemShop_SearchBar_Default_Text", "Click Here to Search", f_body, 14, Color(0.5, 0.5, 0.48), 0, Vector2.ZERO, 0.0)
	else:
		L.text(self, SH + "ItemShop_SearchBar_Text", search + caret, f_bold, 15, C_TEXT, 0, Vector2.ZERO, 0.0)
	if search != "":
		var xr := L.draw(self, SH + "ItemShop_SearchBar_ClearIcon")
		_hits.append([xr.grow(6.0), "clear_search", 0])
	_hits.append([L.r(SH + "ItemShop_SearchBar_BarLeft").merge(L.r(SH + "ItemShop_SearchBar_BarRight")).merge(bar), "search", 0])


# --------------------------------------------------------------------- recommended tab
func _draw_recommended(c) -> void:
	L.text(self, SH + "ItemShop_RecItems_SuggestedItems_HeaderText", "SUGGESTED ITEMS", f_title, 15, C_GOLD, 0, Vector2.ZERO, 0.0)
	var cards := ItemDB.suggested(c, 3)
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
		_gold_amount(L.r(CE + "CostText", off), price, 16, C_GOLD_TXT if afford else C_GOLD_POOR)
		L.text(self, CE + "BriefText", ItemDB.brief(id), f_body, 13, C_DIM, 1, off, 0.0)
		_hits.append([slot, "rec_item", id])   # [ui-fix] before the component cells: hits are searched last-first, so the small component icons win
		var comps := ItemDB.components_of(id)
		var cx := slot.get_center().x - (comps.size() * 40.0 * L.shop_s()) * 0.5
		for ci in comps.size():
			var r := Rect2(cx + ci * 40.0 * L.shop_s(), slot.position.y + 395.0 * L.shop_s(), 34.0 * L.shop_s(), 34.0 * L.shop_s())
			_item_cell_small(r, comps[ci])
		_hover(id, slot)
	if cards.is_empty():
		HudLayout.text_in(self, L.r(SH + "ItemShop_RecItems_RecItemSlot0").grow(80), "Nothing left to recommend", f_body, 15, C_DIM, 1, 0.0)
	L.draw(self, CE + "KeyLine_CommonlyBuilt")
	L.text(self, CE + "CommonlyBuilt_HeaderText", "COMMONLY BUILT", f_title, 15, C_GOLD, 0, Vector2.ZERO, 0.0)
	var cb := ItemDB.commonly_built(c)
	for i in cb.size():
		var r := L.r(CE + "CommonlyBuilt_Slot%d" % i)
		_item_cell(r, cb[i], false)
		if i < cb.size() - 1:
			var y := r.get_center().y
			draw_line(Vector2(r.end.x + 3, y), Vector2(r.end.x + 13.0 * L.shop_s(), y), C_GOLD * Color(1, 1, 1, 0.6), 1.0)


# --------------------------------------------------------------------- all items tab
func _draw_filters() -> void:
	var F := SH
	L.draw(self, F + "ItemShop_KeyLine_Filters")
	for i in TYPE_BUTTONS.size():
		var key: String = F + "ItemShop_" + TYPE_BUTTONS[i][0]
		if L.e(key).is_empty():
			continue
		var on := type_filter == i
		var r := L.r(key)
		var hit := Rect2(r.get_center() - Vector2(20, 18) * L.shop_s(), Vector2(40, 36) * L.shop_s())
		var active := on and (i != 0 or (type_filter == 0 and stat_filter < 0 and not popular_only))
		L.draw(self, key, C_GOLD if active else (C_TEXT if hit.has_point(_mouse) else C_DIM))
		if active:
			draw_rect(Rect2(hit.position.x + hit.size.x * 0.15, hit.end.y + 1.0, hit.size.x * 0.7, 2.0), C_GOLD)
		_hits.append([hit, "type", i])
		if hit.has_point(_mouse):
			_tip_text(TYPE_BUTTONS[i][1], hit)
	# popular
	var pr := L.r(F + "ItemShop_PopBtn_MarkDefault")
	var phit := L.r(F + "ItemShop_PopBtn_Region")
	L.draw(self, F + ("ItemShop_PopBtn_MarkClicked" if popular_only else ("ItemShop_PopBtn_MarkHover" if phit.has_point(_mouse) else "ItemShop_PopBtn_MarkDefault")))
	if popular_only:
		L.draw(self, F + "ItemShop_PopBtn_Underline")
	_hits.append([phit, "popular", 0])
	if phit.has_point(_mouse):
		_tip_text("Popular items", phit)
	# invert group order
	var ir := L.r(F + "ItemShop_InvertButton_Region")
	L.draw(self, F + ("ItemShop_InvertButton_Clicked" if invert_groups else ("ItemShop_InvertButton_Hover" if ir.has_point(_mouse) else "ItemShop_InvertButton_Default")))
	_hits.append([ir, "invert", 0])
	if ir.has_point(_mouse):
		_tip_text("Reverse the order of the item groups", ir)


func _draw_all_items(c) -> void:
	var F := SH
	_draw_filters()
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
		var hit := Rect2(r.get_center() - Vector2(17, 15) * L.shop_s(), Vector2(34, 30) * L.shop_s())
		var on := stat_filter == i
		if on:
			L.draw_in(self, F + _stat_key(sk, "SelectionHighlight"), hit)
		L.draw(self, dk if on or hit.has_point(_mouse) or stat_filter < 0 else F + _stat_key(sk, "Inactive"))
		_hits.append([hit, "stat", i])
		if hit.has_point(_mouse):
			_tip_text(ItemDB.STAT_FILTERS[i][1], hit)
	# tiered grid
	var area := Rect2(L.pt(F + "ItemShop_AllItems_HeaderText", Vector2(343, 350)), Vector2(565, 535) * L.shop_s())
	var items := _all_items()
	var groups := {}
	for id in items:
		var t := ItemDB.tier_group(id)
		if not groups.has(t):
			groups[t] = []
		groups[t].append(id)
	var s := L.shop_s()
	var cols := maxi(1, int(area.size.x / (CELL_PITCH.x * s)))
	var y: float = area.position.y - scroll["all"] * s
	var y0 := y
	if items.is_empty():
		HudLayout.text_in(self, Rect2(area.position, Vector2(area.size.x, 60 * s)), "No items match", f_body, maxi(11, int(15 * s)), C_DIM, 1, 0.0)
	var order: Array = ItemDB.GROUP_ORDER.duplicate()
	if invert_groups:
		order.reverse()
	for tier in order:
		if not groups.has(tier):
			continue
		var hr := Rect2(area.position.x, y, area.size.x, 30 * s)
		var title: String = ItemDB.GROUP_TITLES.get(tier, tier.to_upper())
		if hr.position.y >= area.position.y - 2 and hr.end.y <= area.end.y:
			HudLayout.text_in(self, hr, title, f_title, maxi(11, int(15 * s)), C_GOLD, 0, 0.0)
			draw_line(Vector2(hr.position.x + f_title.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(11, int(15 * s))).x + 10 * s, hr.get_center().y),
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
	_scroll_max["all"] = maxf(0.0, (y - y0) / s - area.size.y / s)
	scroll["all"] = minf(scroll["all"], _scroll_max["all"])
	_scrollbar("all", area)


func _scrollbar(key: String, area: Rect2) -> void:
	var s := L.shop_s()
	if _scroll_max[key] <= 0.0:
		return
	var track := Rect2(area.end.x + 2 * s, area.position.y, 6 * s, area.size.y)
	var hgt := maxf(30 * s, track.size.y * area.size.y / (area.size.y + _scroll_max[key] * s))
	var ty: float = track.position.y + (track.size.y - hgt) * (scroll[key] / _scroll_max[key])
	HudLayout.region(self, "itemshop_texture_atlas", Rect2(1000, 135, 6, 40), Rect2(track.position.x, ty, track.size.x, hgt))


func _stat_key(sk: String, state: String) -> String:
	var icon := {"PhysicalDamage": "PhysicalDamage", "CriticalStrike": "CriticalStrike", "ArmorPen": "ArmorPen", "MagicPen": "MagicPen"}
	var hl := {"PhysicalDamage": "PD", "CriticalStrike": "CS", "Movespeed": "MoveSpeed"}
	if state == "SelectionHighlight":
		return "%s_SelectionHighlight" % hl.get(sk, sk)
	return "%s_%s" % [icon.get(sk, sk), state]


# --------------------------------------------------------------------- item sets tab
## Item sets: the champion's recommended set split into League's usual blocks.
func _set_blocks(c) -> Array:
	var plan := ItemDB.rec_plan(c)
	var starting := []
	for b in plan.starting:
		for id in b:
			if not (id in starting):
				starting.append(id)
	var boots := []
	var core := []
	var situational := []
	for st in plan.steps:
		for i in st.items.size():
			var id: int = st.items[i]
			if ItemDB.is_boots(id):
				boots.append(id)
			elif i == 0 and core.size() < 5:
				core.append(id)
			else:
				situational.append(id)
	var out := []
	if not starting.is_empty():
		out.append(["Starting Items", starting])
	if not boots.is_empty():
		out.append(["Boots", boots])
	if not core.is_empty():
		out.append(["Core Items", core])
	if not situational.is_empty():
		out.append(["Situational Items", situational])
	out.append(["Consumables", ItemDB.quick_consumables().filter(func(x): return ItemDB.visible_in_shop(x, c) or true)])
	return out


func _draw_sets(c) -> void:
	var F := SH
	# combo box (one set: the champion's recommended set)
	var cb := L.r(F + "ItemSets_ComboBox_ButtonHitArea")
	draw_rect(cb, Color(0.02, 0.05, 0.08, 0.9))
	draw_rect(cb, C_LINE, false, 1.0)
	L.text(self, F + "ItemSets_ComboBox_ButtonText", "%s  -  Recommended" % c.display_name, f_body, 14, C_TEXT, 0, Vector2.ZERO, 0.0)
	L.draw(self, F + "ItemShop_ItemSets_Keyline")
	var area := Rect2(L.pt(F + "ItemShop_ItemSets_HeaderText", Vector2(342, 350)), Vector2(597, 538) * L.shop_s())
	var s := L.shop_s()
	var y: float = area.position.y - scroll["sets"] * s
	var y0 := y
	for blk in _set_blocks(c):
		var hr := Rect2(area.position.x, y, area.size.x, 30 * s)
		if hr.position.y >= area.position.y - 2 and hr.end.y <= area.end.y:
			HudLayout.text_in(self, hr, String(blk[0]).to_upper(), f_title, maxi(11, int(15 * s)), C_GOLD, 0, 0.0)
		y += 32 * s
		var ids: Array = blk[1]
		var cols := maxi(1, int(area.size.x / (CELL_PITCH.x * s)))
		for i in ids.size():
			if i % cols == 0 and i > 0:
				y += CELL_PITCH.y * s
			var cell := Rect2(area.position.x + (i % cols) * CELL_PITCH.x * s + 4 * s, y, 44 * s, 44 * s)
			if cell.position.y >= area.position.y - 1 and cell.end.y + 16 * s <= area.end.y:
				_item_cell(cell, ids[i], true)
		y += CELL_PITCH.y * s + 4 * s
	_scroll_max["sets"] = maxf(0.0, (y - y0) / s - area.size.y / s)
	scroll["sets"] = minf(scroll["sets"], _scroll_max["sets"])
	_scrollbar("sets", area)


# --------------------------------------------------------------------- search overlay (League's ItemShop_SearchView)
func _draw_search_view(c) -> void:
	var F := SH
	draw_rect(L.r(F + "ItemShop_SearchDimBackdrop"), Color(0, 0, 0, 0.55))
	var bd := L.draw(self, F + "ItemShop_SearchMenu_Backdrop")
	_hits.append([bd, "search_bg", 0])
	var s := L.shop_s()
	var res := _search_results()
	var area := L.r(F + "ItemShop_SearchView_ItemRegion")
	L.text(self, F + "ItemShop_SearchView_Rec_Label", "%d RESULTS" % res.size() if not res.is_empty() else "NO RESULTS", f_title, 13, C_GOLD, 0, Vector2.ZERO, 0.0)
	var row_h := 62.0 * s
	var y: float = area.position.y - scroll["search"] * s
	for id in res:
		var row := Rect2(area.position.x, y, area.size.x, row_h)
		if row.position.y >= area.position.y - 2 and row.end.y <= area.end.y + 2:
			var sel: bool = selected == id and selected_owned == null
			var hov := row.has_point(_mouse) and area.has_point(_mouse)
			if sel or hov:
				var uv := L.uv_of(F + "ItemShop_ItemPageTemplate_Item_Full_FrameHover")
				if uv.size.x > 0.0:
					HudLayout.hslice(self, "itemshop_texture_atlas", uv, row, 10.0, Color(1, 1, 1, 1.0 if sel else 0.6))
				else:
					draw_rect(row, Color(0.4, 0.3, 0.1, 0.25))
			var price: int = ItemDB.price_for(c, id)[0]
			var afford: bool = c.gold >= price
			var icon_r := Rect2(row.position + Vector2(6, 8) * s, Vector2(40, 40) * s)
			var icon := _item_icon(id)
			if icon != null:
				draw_texture_rect(icon, icon_r, false, Color.WHITE if afford else Color(0.5, 0.5, 0.52))
			L.draw_in(self, F + "ItemShop_ItemPageTemplate_Item_Frame", icon_r.grow(2 * s))
			HudLayout.text_in(self, Rect2(row.position + Vector2(54, 6) * s, Vector2(row.size.x - 60 * s, 20 * s)), ItemDB.name_of(id), f_title, maxi(11, int(13 * s)), C_TEXT, 0, 0.0)
			_gold_amount(Rect2(row.position + Vector2(54, 28) * s, Vector2(80 * s, 18 * s)), price, 13, C_GOLD_TXT if afford else C_GOLD_POOR, 0)
			_hits.append([row.intersection(area), "item", id])
			if hov:
				_hover(id, row.intersection(area))
		y += row_h + 4 * s
	_scroll_max["search"] = maxf(0.0, (y - (area.position.y - scroll["search"] * s) - area.size.y) / s)
	scroll["search"] = minf(scroll["search"], _scroll_max["search"])
	_scrollbar("search", area)
	# description of the selected result
	if selected >= 0 and ItemDB.has(selected):
		var head := L.r(F + "ItemShop_SearchItemDescription_ClickRegion")
		var hov2 := head.has_point(_mouse)
		if hov2:
			L.draw(self, F + "ItemShop_SearchItemDescription_HoverIcon")
		var icon2 := _item_icon(selected)
		var ir := L.r(F + "ItemShop_SearchItemDescription_ItemIcon")
		if icon2 != null:
			draw_texture_rect(icon2, ir, false)
		draw_rect(ir, C_LINE, false, 1.0)
		L.text(self, F + "ItemShop_SearchItemDescription_TitleText", ItemDB.name_of(selected), f_title, 16, C_TEXT, 0, Vector2.ZERO, 0.0)
		L.draw(self, F + "ItemShop_SearchItemDescription_GoldIcon")
		var price2: int = ItemDB.price_for(c, selected)[0]
		L.text(self, F + "ItemShop_SearchItemDescription_CostText", str(price2), f_bold, 14, C_GOLD_TXT if c.gold >= price2 else C_GOLD_POOR, 0, Vector2.ZERO, 0.0)
		_hits.append([head, "search_buy", 0])
		var body := L.r(F + "ItemShop_SearchItemDescription_Body")
		var px := maxi(11, int(14 * s))
		var rws := ItemTip.rows_for(selected, c, px, body.size.x)
		ItemText.draw(self, rws, body.position, px, f_body, f_bold, 1.0, body.end.y + 40 * s)


# --------------------------------------------------------------------- item cells
func _item_icon(id: int) -> Texture2D:
	return Assets.item_icon(id) if id != 9999 else Assets.augment_icon("ARAM_Stats")


func _tip_text(text: String, r: Rect2) -> void:
	HudTooltip.draw(self, HudTooltip.simple(text, ""), r, size, size.y / 1080.0)


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
		L.draw_in(self, T + "SelectedMajor", Rect2(r.position - Vector2(4, 5) * L.shop_s(), Vector2(52, 74) * L.shop_s()))
	elif hov:
		L.draw_in(self, T + "HoverMajor", Rect2(r.position - Vector2(4, 5) * L.shop_s(), Vector2(52, 74) * L.shop_s()), Color(1, 1, 1, 0.7))
	var icon := _item_icon(id)
	var ir := r.grow(-2.0 * L.shop_s())
	if icon != null:
		draw_texture_rect(icon, ir, false, Color.WHITE if afford or owned else Color(0.48, 0.48, 0.5))
	L.draw_in(self, T + ("FrameHover" if hov or sel else "Frame"), r)
	if owned:
		L.draw_in(self, T + "Purchased", Rect2(r.get_center() - Vector2(13, 10.5) * L.shop_s(), Vector2(26, 21) * L.shop_s()))
	var reason := ItemDB.buy_block_reason(c, id)
	if reason == "unique" or reason == "level":
		L.draw_in(self, T + "Locked", Rect2(r.get_center() - Vector2(11, 11) * L.shop_s(), Vector2(22, 22) * L.shop_s()), Color(1, 1, 1, 0.9))
	if with_cost:
		var cr := Rect2(r.position.x - 6 * L.shop_s(), r.end.y + 2 * L.shop_s(), r.size.x + 12 * L.shop_s(), 14 * L.shop_s())
		HudLayout.text_in(self, cr, str(price), f_bold, maxi(10, int(13 * L.shop_s())), C_GOLD_TXT if afford else C_GOLD_POOR, 1, 0.0)
	_hits.append([r.grow(3.0), "item", id])
	_hover(id, r)


func _item_cell_small(r: Rect2, id: int) -> void:
	var owned := _owns(id)
	var icon := _item_icon(id)
	if icon != null:
		draw_texture_rect(icon, r, false, Color.WHITE if owned or champ().gold >= ItemDB.price_for(champ(), id)[0] else Color(0.5, 0.5, 0.52))
	draw_rect(r, C_TEAL if owned else Color(0.47, 0.35, 0.16), false, 1.5 if owned else 1.0)
	_hits.append([r, "item", id])
	_hover(id, r)


func _gold_amount(r: Rect2, amount: int, size_src: float, col: Color, align := 1) -> void:
	var px := maxi(10, int(size_src * L.shop_s()))
	var s := str(amount)
	var w := f_bold.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var coin := Vector2(px * 0.95, px * 0.85)
	var x := r.get_center().x - (w + coin.x + 4) * 0.5 if align == 1 else r.position.x
	HudLayout.region(self, "itemshop_texture_atlas", Rect2(2, 2, 32, 28), Rect2(Vector2(x, r.get_center().y - coin.y * 0.5), coin))
	HudLayout.text_in(self, Rect2(x + coin.x + 4, r.position.y, w, r.size.y), s, f_bold, px, col, 0, 0.0)


# --------------------------------------------------------------------- left quick panels
func _quick_items(key: String, c) -> Array:
	match key:
		"cons":
			return ItemDB.quick_consumables().filter(func(x): return ItemDB.has(x))
		"boots":
			return ItemDB.quick_boots().filter(func(x): return ItemDB.has(x) and ItemDB.visible_in_shop(x, c))
	return []


func _draw_side_panels(c) -> void:
	for p in PANELS:
		var k: String = p[0]
		var open: bool = _panel_open[k]
		var tab_r := L.r(SH + p[1] + "_Closed")
		if open:
			L.draw(self, SH + p[1] + "_Opened")
			var pin_r := L.r(SH + p[2] + "_HitRegion")
			var pin_hov := pin_r.has_point(_mouse)
			var pk: String = "_Clicked" if _panel_pin[k] else ("_Hover" if pin_hov else "_Default")
			L.draw(self, SH + p[2] + pk)
			_hits.append([pin_r, "panel_pin", k])
			# slots
			if k == "inv":
				for i in p[3]:
					var r := L.r(SH + p[4] % i)
					var it = c.items[i] if i < c.items.size() and i < 6 else null
					_draw_slot(r, it.item_id if it != null else -1, it, k)
			else:
				var ids := _quick_items(k, c)
				for i in p[3]:
					var r := L.r(SH + p[4] % i)
					if i < ids.size():
						_draw_slot(r, ids[i], null, k)
			# the tab is still clickable (folds the panel)
			var fold := Rect2(L.r(SH + p[1] + "_ExpandedRegion").end.x - 18 * L.shop_s(), L.r(SH + p[1] + "_ExpandedRegion").position.y, 26 * L.shop_s(), L.r(SH + p[1] + "_ExpandedRegion").size.y)
			_hits.append([fold, "panel_tab", k])
		else:
			var hov := tab_r.has_point(_mouse)
			L.draw(self, SH + p[1] + "_Closed", Color(1, 1, 1, 1.0 if hov else 0.9))
			_hits.append([tab_r, "panel_tab", k])
			if hov:
				_tip_text({"cons": "Consumables", "boots": "Boots", "inv": "Inventory"}[k], tab_r)


func _draw_slot(r: Rect2, id: int, owned_item, panel_key: String) -> void:
	var c = champ()
	var T := SH + "ItemShop_ItemPageTemplate_Item_"
	var hov := r.has_point(_mouse)
	if id < 0:
		draw_rect(r, Color(0, 0, 0, 0.35))
		draw_rect(r, Color(0.3, 0.25, 0.15, 0.7), false, 1.0)
		return
	var price: int = ItemDB.price_for(c, id)[0]
	var afford: bool = c.gold >= price or owned_item != null
	var icon := _item_icon(id)
	if icon != null:
		draw_texture_rect(icon, r, false, Color.WHITE if afford else Color(0.5, 0.5, 0.52))
	var sel: bool = (selected_owned == owned_item and owned_item != null) or (owned_item == null and selected == id and selected_owned == null)
	draw_rect(r, C_TEAL if sel else (C_GOLD if hov else Color(0.47, 0.35, 0.16)), false, 2.0 if sel or hov else 1.0)
	if owned_item != null:
		var st = owned_item.get("stacks")
		if st != null and int(st) > 1 or (st != null and ItemDB.max_stack(id) > 1):
			HudLayout.text_in(self, Rect2(r.end - Vector2(18, 14) * L.shop_s(), Vector2(16, 12) * L.shop_s()), str(int(st)), f_bold, maxi(9, int(11 * L.shop_s())), C_TEXT, 2, 2.0)
		_hits.append([r, "inv_item", owned_item])
		_hover(id, r, owned_item)
	else:
		if owned_item == null and _owns(id) and ItemDB.is_consumable(id):
			pass
		_hits.append([r, "item", id])
		_hover(id, r)


# --------------------------------------------------------------------- right panel: builds into, tree, details
func _draw_build_panel(c) -> void:
	L.text(self, SH + "ItemShop_BuildsInto_Label", "BUILDS INTO", f_title, 13, C_DIM, 0, Vector2.ZERO, 0.0)
	var into := ItemDB.builds_into(selected) if selected >= 0 else []
	var show := mini(into.size(), 7 if into.size() <= 7 else 6)
	for i in 7:
		var r := L.r(SH + "ItemShop_BuildsInto_Slot%d" % (i + 1))
		if i < show:
			_item_cell(r, into[i], false)
		elif i == 6 and into.size() > 7:
			var orr := L.r(SH + "ItemShop_BuildsInto_Overflow_Region")
			var hov := orr.has_point(_mouse) or _drop_open
			L.draw(self, SH + ("ItemShop_BuildsInto_Overflow_Hover" if hov else "ItemShop_BuildsInto_Overflow_Default"))
			L.text(self, SH + ("ItemShop_BuildsInto_Overflow_TextHover" if hov else "ItemShop_BuildsInto_Overflow_Text"), "+%d" % (into.size() - 6), f_bold, 13, C_TEXT, 1, Vector2.ZERO, 0.0)
			_hits.append([orr, "overflow", 0])
		else:
			L.draw(self, SH + "ItemShop_BuildsInto_EmptyState%d" % (i + 1), Color(1, 1, 1, 0.5))
	L.draw(self, SH + "ItemShop_KeyLine_ItemDetailsTop")
	if selected < 0 or not ItemDB.has(selected):
		return
	_draw_tree(c)
	_draw_purchase_and_details(c)
	if _drop_open and into.size() > 6:
		_draw_droplist(c, into.slice(6))


func _draw_droplist(c, ids: Array) -> void:
	var s := L.shop_s()
	var bd := L.r(SH + "ItemShop_BuildsInto_Droplist_Backdrop")
	var row_h := 60.0 * s
	var rect := Rect2(bd.position, Vector2(bd.size.x, maxf(bd.size.y, 14 * s + row_h * ids.size())))
	L.draw_in(self, SH + "ItemShop_BuildsInto_Droplist_Backdrop", rect)
	_hits.append([rect, "overflow_bg", 0])
	for i in ids.size():
		var row := Rect2(rect.position + Vector2(14 * s, 12 * s + row_h * i), Vector2(rect.size.x - 28 * s, row_h))
		var hov := row.has_point(_mouse)
		if hov:
			L.draw_in(self, SH + "ItemShop_BuildsIntoDroplistItem_Hover", row)
		var icon_r := Rect2(row.position + Vector2(10, 10) * s, Vector2(40, 40) * s)
		var icon := _item_icon(ids[i])
		if icon != null:
			draw_texture_rect(icon, icon_r, false)
		L.draw_in(self, SH + "ItemShop_BuildsIntoDroplistItem_Frame", icon_r.grow(2 * s))
		HudLayout.text_in(self, Rect2(row.position + Vector2(60, 10) * s, Vector2(row.size.x - 70 * s, 20 * s)), ItemDB.name_of(ids[i]), f_title, maxi(11, int(14 * s)), C_TEXT, 0, 0.0)
		_gold_amount(Rect2(row.position + Vector2(60, 32) * s, Vector2(90 * s, 18 * s)), ItemDB.price_for(c, ids[i])[0], 13, C_GOLD_TXT, 0)
		_hits.append([row, "item", ids[i]])
		_hover(ids[i], row)


## Build tree: selected item on top, recipe components below (duplicates shown once per slot), owned parts ticked.
func _draw_tree(c) -> void:
	var s := L.shop_s()
	var tree_top := L.pt(SH + "ItemShop_KeyLine_ItemDetailsTop", Vector2(1131, 306))
	var node := Vector2(40, 40) * s
	var root_r := Rect2(tree_top - Vector2(node.x * 0.5, 0), node)
	var consumed: Array = ItemDB.price_for(c, selected)[1].duplicate()
	_tree_node(root_r, selected, true, consumed, 0)
	var comps := ItemDB.components_of(selected)
	if comps.is_empty():
		return
	var span := 372.0 * s
	_tree_children(root_r, comps, tree_top.x, span, consumed, 1, node)


func _tree_children(parent_r: Rect2, comps: Array, cx: float, span: float, consumed: Array, depth: int, node: Vector2) -> void:
	var s := L.shop_s()
	var n := comps.size()
	var line_col := C_LINE
	var gap := 52.0 * s if depth == 1 else 46.0 * s
	var y := parent_r.end.y + gap
	var mid_y := parent_r.end.y + gap * 0.5
	draw_line(Vector2(parent_r.get_center().x, parent_r.end.y + 14 * s), Vector2(parent_r.get_center().x, mid_y), line_col, 1.5)
	var xs := []
	for i in n:
		xs.append(cx + span * ((i + 0.5) / n - 0.5))
	if n > 1:
		draw_line(Vector2(xs[0], mid_y), Vector2(xs[n - 1], mid_y), line_col, 1.5)
	var scale := 1.0 if depth == 1 else (0.84 if depth == 2 else 0.7)
	for i in n:
		var x: float = xs[i]
		draw_line(Vector2(x, mid_y), Vector2(x, y), line_col, 1.5)
		var nsz := node * scale
		var r := Rect2(Vector2(x - nsz.x * 0.5, y), nsz)
		_tree_node(r, comps[i], false, consumed, depth)
		var sub := ItemDB.components_of(comps[i])
		if not sub.is_empty() and depth < 3:
			_tree_children(r, sub, x, span / n * 0.92, consumed, depth + 1, node)


func _tree_node(r: Rect2, id: int, root: bool, consumed: Array, depth: int) -> void:
	var c = champ()
	var owned := false
	if root:
		owned = _owns(id) and ItemDB.max_stack(id) <= 1 and false
	else:
		# same depth-first matching as ItemDB.price_for, so each owned item marks exactly one recipe slot
		for it in consumed:
			if it.item_id == id:
				owned = true
				consumed.erase(it)
				break
	var icon := _item_icon(id)
	var price: int = ItemDB.price_for(c, id)[0]
	var hov := r.has_point(_mouse)
	if icon != null:
		draw_texture_rect(icon, r, false, Color.WHITE if owned or c.gold >= price else Color(0.55, 0.55, 0.58))
	if owned:
		draw_rect(r.grow(1.0), C_TEAL, false, 2.0)
		L.draw_in(self, SH + "ItemShop_ItemPageTemplate_Item_Purchased", Rect2(r.get_center() - Vector2(13, 10.5) * L.shop_s(), Vector2(26, 21) * L.shop_s()))
	else:
		L.draw_in(self, SH + "ItemShop_ItemPageTemplate_Item_" + ("FrameHover" if hov or selected == id else "Frame"), r.grow(2.0 * L.shop_s()))
	var cr := Rect2(r.position.x - 10 * L.shop_s(), r.end.y + 1 * L.shop_s(), r.size.x + 20 * L.shop_s(), 13 * L.shop_s())
	var label := "Owned" if owned else str(price)
	HudLayout.text_in(self, cr, label, f_bold, maxi(10, int(12 * L.shop_s())), C_TEAL if owned else (C_GOLD_TXT if c.gold >= price else C_GOLD_POOR), 1, 0.0)
	_hits.append([r, "item", id])   # [ui-fix] the tree root is clickable too (double-click / right-click buys it)
	_hover(id, r)


func _draw_purchase_and_details(c) -> void:
	var s := L.shop_s()
	var st := session.button_state(c, selected)
	var br := L.r(SH + "ItemShop_PurchaseButton_Default")
	var hov := br.has_point(_mouse)
	var can: bool = st.enabled
	L.draw(self, SH + ("ItemShop_PurchaseButton_Disabled" if not can else ("ItemShop_PurchaseButton_Hover" if hov else "ItemShop_PurchaseButton_Default")))
	L.text(self, SH + "ItemShop_PurchaseButton_Text", st.label, f_title, 14, C_TEXT if can else Color(0.6, 0.58, 0.55), 1, Vector2(-30, 0), 0.0)
	var pr := L.r(SH + "ItemShop_PurchaseButton_Text")
	var price: int = st.price
	_gold_amount(Rect2(pr.end.x - 70 * s, pr.position.y, 70 * s, pr.size.y), price, 15, C_GOLD_TXT if c.gold >= price else C_RED)
	_hits.append([br, "buy", 0])
	L.draw(self, SH + "ItemShop_KeyLine_ItemDetailsBottom")
	# header: icon, name, cost
	var ir := L.r(SH + "ItemShop_ItemDescription_ItemIcon")
	var icon := _item_icon(selected)
	if icon != null:
		draw_texture_rect(icon, ir, false)
	draw_rect(ir, C_LINE, false, 1.0)
	L.text(self, SH + "ItemShop_ItemDescription_TitleText", ItemDB.name_of(selected), f_title, 16, C_TEXT, 0, Vector2.ZERO, 0.0)
	L.draw(self, SH + "ItemShop_ItemDescription_GoldIcon")
	var cost_s := str(ItemDB.cost_of(selected))
	if price != ItemDB.cost_of(selected):
		cost_s = "%d  (%d)" % [price, ItemDB.cost_of(selected)]
	var owned_sel = selected_owned
	if owned_sel != null:
		cost_s = "Sells for %d" % ItemDB.sell_price(owned_sel)
	L.text(self, SH + "ItemShop_ItemDescription_CostText", cost_s, f_bold, 14, C_GOLD_TXT, 0, Vector2.ZERO, 0.0)
	var brief := ItemDB.brief(selected)
	if brief != "":
		var cr2 := L.r(SH + "ItemShop_ItemDescription_CostText")
		HudLayout.text_in(self, Rect2(cr2.position + Vector2(96 * s, 0), Vector2(cr2.size.x + 120 * s, cr2.size.y)), brief, f_body, maxi(10, int(12 * s)), Color(0.42, 0.64, 0.87), 0, 0.0)
	L.draw(self, SH + "ItemShop_KeyLine_ItemDetailsTooltip")
	# body: League's tooltip text
	var body := L.r(SH + "ItemShop_ItemDescription_Body")
	var px := maxi(11, int(14 * s))
	var rws := ItemTip.rows_for(selected, c, px, body.size.x)
	var limit := panel.end.y - 62 * s
	var total_h := ItemText.height(rws, px)
	var vis_h := limit - body.position.y
	_scroll_max["details"] = maxf(0.0, (total_h - vis_h) / s)
	scroll["details"] = minf(scroll["details"], _scroll_max["details"])
	ItemText.draw(self, rws, body.position - Vector2(0, scroll["details"] * s), px, f_body, f_bold, 1.0, limit)
	if _scroll_max["details"] > 0.0:
		draw_string(f_body, Vector2(body.end.x - 10 * s, limit + 12 * s), "v", HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(9, int(11 * s)), C_DIM)


# --------------------------------------------------------------------- footer
func _draw_footer(c) -> void:
	var can_sell: bool = selected_owned != null and c.can_shop() and selected_owned in c.items and ItemDB.can_sell(selected_owned)
	var sr := L.r(SH + "ItemShop_SellButton_ButtonDefault")
	L.draw(self, SH + ("ItemShop_SellButton_ButtonDisabled" if not can_sell else ("ItemShop_SellButton_ButtonHover" if sr.has_point(_mouse) else "ItemShop_SellButton_ButtonDefault")))
	var sell_txt := "SELL" if selected_owned == null else "SELL %d" % ItemDB.sell_price(selected_owned)
	L.text(self, SH + "ItemShop_SellButton_Text", sell_txt, f_title, 13, C_TEXT if can_sell else Color(0.5, 0.5, 0.5), 1, Vector2.ZERO, 0.0)
	_hits.append([sr, "sell", 0])
	var ur := L.r(SH + "ItemShop_UndoButton_ButtonDefault")
	var can_undo: bool = session.can_undo() and c.can_shop()
	L.draw(self, SH + ("ItemShop_UndoButton_ButtonDisabled" if not can_undo else ("ItemShop_UndoButton_ButtonHover" if ur.has_point(_mouse) else "ItemShop_UndoButton_ButtonDefault")))
	L.text(self, SH + "ItemShop_UndoButton_Text", "UNDO", f_title, 13, C_TEXT if can_undo else Color(0.5, 0.5, 0.5), 1, Vector2.ZERO, 0.0)
	_hits.append([ur, "undo", 0])
	L.draw(self, SH + "ItemShop_Footer_GoldIcon")
	L.text(self, SH + "ItemShop_Footer_GoldText", str(int(c.gold)), f_bold, 18, C_GOLD_TXT, 0, Vector2(0, 2), 0.0)
	var info := Rect2(L.pt(SH + "ItemShop_Footer_GoldText", Vector2(660, 900)), Vector2(250, 34) * L.shop_s())
	if not c.can_shop():
		_draw_lock(info)
	if msg_t > 0.0:
		var a := minf(1.0, msg_t * 2.0)
		var mr := Rect2(L.pt(SH + "ItemShop_Footer_GoldText", Vector2(940, 900)), Vector2(382, 34) * L.shop_s())
		HudLayout.text_in(self, mr, msg, f_bold, maxi(11, int(14 * L.shop_s())), Color(C_RED.r, C_RED.g, C_RED.b, a), 1, 2.0)
	var hint := Rect2(L.pt(SH + "ItemShop_Footer_GoldText", Vector2(660, 930)), Vector2(250, 20) * L.shop_s())
	HudLayout.text_in(self, hint, "Right-click or double-click to buy  |  Ctrl+Z undo  |  Ctrl+L search", f_body, maxi(9, int(11 * L.shop_s())), Color(0.5, 0.5, 0.48), 0, 0.0)


func _draw_lock(r: Rect2) -> void:
	var px := maxi(10, int(13 * L.shop_s()))
	HudLayout.region(self, "itemshop_texture_atlas", Rect2(38, 2, 68, 68), Rect2(r.position + Vector2(0, (r.size.y - 22 * L.shop_s()) * 0.5), Vector2(22, 22) * L.shop_s()))
	HudLayout.text_in(self, Rect2(r.position + Vector2(26 * L.shop_s(), 0), r.size), "Shopping only while dead or in base", f_bold, px, C_RED, 0, 0.0)


# --------------------------------------------------------------------- sell overlay (dragging an inventory item onto the shop)
func _draw_sell_overlay(c) -> void:
	if hud == null or not hud.get("_drag") is Dictionary or not hud._drag.get("active", false):
		return
	var slot: int = hud._drag.get("slot", -1)
	if slot < 0 or slot >= c.items.size():
		return
	var it = c.items[slot]
	var over := panel.has_point(_mouse)
	var area := L.r(SH + "ItemShop_SellOverlay_DragArea")
	L.draw(self, SH + "ItemShop_SellOverlay_DragArea", Color(1, 1, 1, 0.9 if over else 0.6))
	L.draw(self, SH + ("ItemShop_SellOverlay_SellIconHover" if over else "ItemShop_SellOverlay_SellIconDefault"))
	var txt := "Drop here to sell for %d gold" % ItemDB.sell_price(it) if c.can_shop() else "You can only sell in base"
	L.text(self, SH + "ItemShop_SellOverlay_SellItemText", txt, f_title, 16, C_GOLD_TXT if c.can_shop() else C_RED, 1, Vector2.ZERO, 2.0)
	var _unused := area
