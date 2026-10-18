class_name ShopSession
extends RefCounted
## One player's shopping session: League's purchase / sell / undo rules on top of ItemDB, with the shop sounds.
##
##  * every buy / sell / combine pushes an undo snapshot; Undo restores items, stack counts, anvils and gold
##  * the history is cleared the moment the champion leaves the base (can_shop() false), like League's shop
##  * buying an item the champion cannot afford buys the affordable components instead ("PURCHASE COMPONENTS")

signal changed
signal message(text: String)

var undo: Array = []
var last_kind := ""


func tick(c) -> void:
	if not undo.is_empty() and (c == null or not c.can_shop()):
		undo.clear()
		changed.emit()


func can_undo() -> bool:
	return not undo.is_empty()


func clear() -> void:
	undo.clear()


## State of the Purchase button for `id`: {"label": String, "enabled": bool, "reason": String, "price": int, "mode": "item"|"components"|"none"}
## Labels are League's shop_autobuild strings.
func button_state(c, id: int) -> Dictionary:
	var price: int = ItemDB.price_for(c, id)[0]
	var reason := ItemDB.buy_block_reason(c, id)
	if reason == "":
		return {"label": "PURCHASE ITEM", "enabled": true, "reason": "", "price": price, "mode": "item"}
	match reason:
		"far":
			return {"label": "TOO FAR FROM SHOP", "enabled": false, "reason": reason, "price": price, "mode": "none"}
		"gold":
			if not ItemDB.components_to_buy(c, id).is_empty():
				return {"label": "PURCHASE COMPONENTS", "enabled": true, "reason": reason, "price": price, "mode": "components"}
			return {"label": "NOT ENOUGH GOLD", "enabled": false, "reason": reason, "price": price, "mode": "none"}
		"level":
			return {"label": "REQUIRES LEVEL %d" % int(ItemDB.meta(id).get("req_level", 0)), "enabled": false, "reason": reason, "price": price, "mode": "none"}
		"full":
			return {"label": "INVENTORY FULL", "enabled": false, "reason": reason, "price": price, "mode": "none"}
	return {"label": "ITEM UNAVAILABLE", "enabled": false, "reason": reason, "price": price, "mode": "none"}


## The shop's buy action (right-click, double-click, Purchase button, Enter). Returns true when something was bought.
func buy(c, id: int) -> bool:
	id = ItemDB.canon(id)
	var st := button_state(c, id)
	if not st.enabled:
		message.emit(ItemDB.reason_text(st.reason, c, id))
		ShopSfx.cue("deny")
		return false
	if st.mode == "components":
		var plan := ItemDB.components_to_buy(c, id)
		var any := false
		for cid in plan:
			var snap := ItemDB.snapshot(c)
			if ItemDB.buy(c, cid):
				undo.append(snap)
				any = true
		if any:
			last_kind = "components"
			ShopSfx.cue("buy_components")
			Vfx.rising(c, G.COLOR_GOLD, 0.4, 20)
			changed.emit()
		return any
	var consumed: Array = ItemDB.price_for(c, id)[1]
	var snap2 := ItemDB.snapshot(c)
	var stacked = _would_stack(c, id)
	if not ItemDB.buy(c, id):
		ShopSfx.cue("deny")
		return false
	undo.append(snap2)
	if stacked:
		last_kind = "basic"
	elif not consumed.is_empty():
		last_kind = "upgrade"
	elif ItemDB.tier_group(id) == "legendary":
		last_kind = "legendary"
	else:
		last_kind = "basic"
	ShopSfx.cue("buy_" + last_kind)
	Vfx.rising(c, G.COLOR_GOLD, 0.4, 20)
	changed.emit()
	return true


func _would_stack(c, id: int) -> bool:
	if not ItemDB.is_consumable(id) or ItemDB.max_stack(id) <= 1:
		return false
	for it in c.items:
		if it.item_id == id:
			return true
	return false


func sell(c, it) -> bool:
	if it == null or not (it in c.items):
		message.emit("Select an item in your inventory to sell")
		ShopSfx.cue("deny")
		return false
	if not c.can_shop():
		message.emit(ItemDB.reason_text("far"))
		ShopSfx.cue("deny")
		return false
	if not ItemDB.can_sell(it):
		message.emit("This item cannot be sold")
		ShopSfx.cue("deny")
		return false
	undo.append(ItemDB.snapshot(c))
	ItemDB.sell(c, it)
	ShopSfx.cue("sell")
	changed.emit()
	return true


func undo_last(c) -> bool:
	if undo.is_empty() or not c.can_shop():
		return false
	var snap: Dictionary = undo.pop_back()
	ItemDB.restore(c, snap)
	ShopSfx.cue("undo")
	changed.emit()
	return true
