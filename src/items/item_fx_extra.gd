class_name ItemFxExtra
extends RefCounted
## Registry of item behaviour added on top of the legacy ItemFx classes (src/items/item_fx.gd).
##
## Each PART script defines item classes (extends Item) and `static func register(m: Dictionary)` that maps an item id
## (the League id, see data/items/items.json) to a Callable returning a fresh Item. ItemDB.create() asks ItemFxExtra first,
## then falls back to ItemFx / a plain stat stick. Numbers must come from ItemDB.data(id, "Name") (League's own item data,
## including the ARAM / Kiwi overrides) instead of being hard-coded.
##
## To add a part: create src/items/item_fx_x_<name>.gd and list its path in PART_PATHS.

## Part scripts are loaded by path at first use (not preload) so a half-edited part can never stop the game from compiling;
## a part that fails to load just contributes no items.
const PART_PATHS := [
	"res://src/items/item_fx_x_consumables.gd",
	"res://src/items/item_fx_x_marksman.gd",
	"res://src/items/item_fx_x_bruiser.gd",
	"res://src/items/item_fx_x_mage.gd",
	"res://src/items/item_fx_x_tank.gd",
	"res://src/items/item_fx_x_support.gd",
]
static var PARTS: Array = []

static var _makers: Dictionary = {}
static var _ready := false


static func _reg() -> void:
	if _ready:
		return
	_ready = true
	for path in PART_PATHS:
		var scr = load(path)
		if scr == null or not scr.can_instantiate():
			push_error("ItemFxExtra: part %s failed to load" % path)
			continue
		PARTS.append(scr)
		scr.register(_makers)


static func has(item_id: int) -> bool:
	_reg()
	return _makers.has(item_id)


static func make(item_id: int) -> Item:
	_reg()
	return _makers[item_id].call()


## Hook run on every freshly created item (set active_cd / extra fields from League's data).
static func configure(it: Item, item_id: int, e: Dictionary) -> void:
	if it.active_cd <= 0.0 and bool(e.get("clickable", false)) and e.get("cooldown") != null and float(e.cooldown) > 0.0 and has(item_id):
		it.active_cd = float(e.cooldown)


## Items bought with "consume on acquire" (Cappa Juice ...): returns true when handled here.
static func acquire(c, item_id: int) -> bool:
	_reg()
	for p in PARTS:
		if p.has_method("acquire") and p.acquire(c, item_id):
			return true
	return false


## How many consume-on-acquire stacks of `item_id` the champion already holds.
static func acquire_count(c, item_id: int) -> int:
	_reg()
	for p in PARTS:
		if p.has_method("acquire_count"):
			var n: int = p.acquire_count(c, item_id)
			if n >= 0:
				return n
	return 0
