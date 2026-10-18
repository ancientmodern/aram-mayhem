extends Node
## Headless check of ItemDB + shop rules inside a running match:
##   tools/check.sh 400 -- --sim --time=2 --harness=res://src/items/tests/db_harness.gd
## Prints "ITEMTEST ..." lines.

var match_ref = null
var main = null


func _ready() -> void:
	await get_tree().create_timer(0.5, true, false, true).timeout
	_run()
	get_tree().quit()


func _p(s: String) -> void:
	print("ITEMTEST ", s)


func _run() -> void:
	_p("items %d version %s grid %d" % [ItemDB.META.size(), ItemDB.VERSION, ItemDB.grid_items().size()])
	var bad := 0
	for id in ItemDB.META:
		var it := ItemDB.create(id)
		if it == null:
			_p("CREATE FAILED %d" % id)
			bad += 1
	for alias in ItemDB.BUILDS:
		for id in ItemDB.BUILDS[alias]:
			if not ItemDB.has(id):
				_p("BUILD ITEM MISSING %s %d" % [alias, id])
				bad += 1
	_p("IE total %d combine %d from %s sell %d" % [ItemDB.cost_of(3031), ItemDB.combine_cost(3031), str(ItemDB.components_of(3031)), ItemDB.sell_value_of(3031)])
	_p("search ie=%d bc=%d dcap=%d hat=%d armor=%d" % [ItemDB.search_score(3031, "ie"), ItemDB.search_score(3071, "bc"), ItemDB.search_score(3089, "dcap"), ItemDB.search_score(3089, "hat"), ItemDB.search_score(1031, "armor")])
	var c: Champion = G.player
	if c == null:
		_p("no player")
		return
	c.in_fountain = true
	c.gold = 5000
	for id in [1036, 1036, 3133]:
		var r := ItemDB.purchase(c, id)
		_p("buy %s -> %s gold %d items %d" % [ItemDB.name_of(id), str(r), c.gold, c.items.size()])
	var p := ItemDB.price_for(c, 3074)
	_p("ravenous hydra price with comps = %d (total %d)" % [p[0], ItemDB.cost_of(3074)])
	c.gold = 400
	var plan := ItemDB.components_to_buy(c, 3031)
	_p("components plan for IE with 400g: %s" % str(plan))
	c.gold = 5000
	var rp := ItemDB.rec_plan(c)
	_p("rec plan %s suggested %s" % [str(rp.full), str(ItemDB.suggested(c))])
	# boots rule
	ItemDB.buy(c, 1001)
	ItemDB.buy(c, 3006)
	_p("second boots reason: %s" % ItemDB.buy_block_reason(c, 3020))
	var snap := ItemDB.snapshot(c)
	_p("potion block reason %s" % ItemDB.buy_block_reason(c, 2003))
	_p("buy1 %s" % str(ItemDB.buy(c, 2003)))
	_p("buy2 %s reason %s" % [str(ItemDB.buy(c, 2003)), ItemDB.buy_block_reason(c, 2003)])
	for it in c.items:
		_p("  item %s id %d stacks %s" % [it.display_name, it.item_id, str(it.get("stacks"))])
	_p("potions stack: %d items, stacks=%s" % [c.items.size(), str(c.items[c.items.size() - 1].get("stacks"))])
	ItemDB.restore(c, snap)
	_p("after undo items=%d gold=%d" % [c.items.size(), c.gold])
	_p("done bad=%d" % bad)
