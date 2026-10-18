extends RefCounted
## Potions, elixirs and consumable-on-purchase items of the ARAM shop (numbers from League's item data).

const ID_HEALTH_POTION := 2003
const ID_REFILLABLE := 2031
const ID_ELIXIR_IRON := 2138
const ID_ELIXIR_SORCERY := 2139
const ID_ELIXIR_WRATH := 2140
const ID_CAPPA_JUICE := 2141


static func register(m: Dictionary) -> void:
	m[ID_HEALTH_POTION] = func(): return HealthPotion.new()
	m[ID_REFILLABLE] = func(): return RefillablePotion.new()
	m[ID_ELIXIR_IRON] = func(): return ElixirIron.new()
	m[ID_ELIXIR_SORCERY] = func(): return ElixirSorcery.new()
	m[ID_ELIXIR_WRATH] = func(): return ElixirWrath.new()
	m[ID_CAPPA_JUICE] = func(): return CappaJuiceItem.new()


## Cappa Juice (and any future "consumed on acquire" stat item): one hidden effect per purchase, tracked in champion.anvils so
## the shop's Undo can take it back.
static func acquire(c, item_id: int) -> bool:
	if item_id != ID_CAPPA_JUICE:
		return false
	var it := ItemDB.create(ID_CAPPA_JUICE)
	if it == null:
		return false
	it.hidden = true
	c.add_effect(it)
	c.anvils.append(it)
	c.items_changed.emit()
	return true


static func acquire_count(c, item_id: int) -> int:
	return juice_stacks(c) if item_id == ID_CAPPA_JUICE else -1


static func juice_stacks(c) -> int:
	var n := 0
	for e in c.effects:
		if e.id == "item_%d" % ID_CAPPA_JUICE:
			n += 1
	return n


## ---------------------------------------------------------------------------------------------- base
class Consumable extends Item:
	var stacks := 1
	var max_stacks := 1
	var play_cue := ""

	func _init() -> void:
		active_cd = 1.0

	func add_stack(n: int = 1) -> void:
		stacks = mini(max_stacks, stacks + n)

	func activate(_pos: Vector3, _hovered) -> void:
		var o = owner
		if o == null or o.dead or active_left > 0.0 or stacks <= 0:
			return
		if not consume(o):
			return
		active_left = active_cd
		if play_cue != "":
			ShopSfx.world(o, play_cue)
		if remove_when_empty():
			stacks -= 1
			if stacks <= 0:
				o.remove_item(self)
			else:
				o.items_changed.emit()

	func remove_when_empty() -> bool:
		return true

	func consume(_o) -> bool:
		return false

	static func regen(o, bid: String, bname: String, total: float, dur: float) -> void:
		var b: Buff = K.buff(o, bid, dur, {}, o, {"name": bname})
		if b == null:
			return
		b.tick_interval = 0.5
		var per_tick := total / (dur / 0.5)
		b.on_interval = func(bb): Combat.heal(o, o, per_tick, {"is_vamp": true, "show": false, "tag": "potion"})


## ---------------------------------------------------------------------------------------------- potions
class HealthPotion extends Consumable:
	func _init() -> void:
		super._init()
		max_stacks = ItemDB.max_stack(ID_HEALTH_POTION)
		play_cue = "potion"

	func consume(o) -> bool:
		if o.has_buff("health_potion"):
			return false
		var total := float(ItemDB.data(ID_HEALTH_POTION, "HealAmount", 120.0))
		var dur := float(ItemDB.data(ID_HEALTH_POTION, "PotionDuration", 15.0))
		Consumable.regen(o, "health_potion", "Health Potion", total, dur)
		return true


class RefillablePotion extends Consumable:
	func _init() -> void:
		super._init()
		max_stacks = int(ItemDB.data(ID_REFILLABLE, "MaxCharges", 2.0))
		stacks = max_stacks
		play_cue = "potion"

	func remove_when_empty() -> bool:
		return false

	func activate(pos: Vector3, hovered) -> void:
		var o = owner
		if o == null or o.dead or active_left > 0.0 or stacks <= 0:
			return
		if o.has_buff("refillable_potion"):
			return
		var total := float(ItemDB.data(ID_REFILLABLE, "HealAmount", 100.0))
		var dur := float(ItemDB.data(ID_REFILLABLE, "PotionDuration", 12.0))
		Consumable.regen(o, "refillable_potion", "Refillable Potion", total, dur)
		stacks -= 1
		active_left = active_cd
		ShopSfx.world(o, "potion_refill")
		o.items_changed.emit()

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		# League: "Refills upon visiting the shop"
		if stacks < max_stacks and u.can_shop():
			stacks = max_stacks
			u.items_changed.emit()


## ---------------------------------------------------------------------------------------------- elixirs
class Elixir extends Consumable:
	var elixir_id := 0
	var buff_id := ""

	func _init() -> void:
		super._init()
		play_cue = "elixir"

	func duration() -> float:
		var ea: Array = ItemDB.meta(elixir_id).get("effect_amount", [])
		return float(ea[2]) * 60.0 if ea.size() > 2 and float(ea[2]) > 0.0 else 180.0

	func consume(o) -> bool:
		# League: only one elixir at a time
		for bid in ["elixir_iron", "elixir_sorcery", "elixir_wrath"]:
			if o.has_buff(bid):
				return false
		apply(o)
		return true

	func apply(_o) -> void:
		pass


class ElixirIron extends Elixir:
	func _init() -> void:
		super._init()
		elixir_id = ID_ELIXIR_IRON
		max_stacks = 1

	func apply(o) -> void:
		var ea: Array = ItemDB.meta(elixir_id).effect_amount
		K.buff(o, "elixir_iron", duration(), {"hp": float(ea[0]), "tenacity": float(ea[1]), "size": float(ea[4]) if ea.size() > 4 else 0.15},
			o, {"name": "Elixir of Iron"})


class ElixirSorcery extends Elixir:
	func _init() -> void:
		super._init()
		elixir_id = ID_ELIXIR_SORCERY
		max_stacks = 1

	func apply(o) -> void:
		var ea: Array = ItemDB.meta(elixir_id).effect_amount
		K.buff(o, "elixir_sorcery", duration(), {"ap": float(ea[0]), "mana_regen%": 0.15}, o, {"name": "Elixir of Sorcery"})
		var fx := SorceryProc.new()
		fx.true_dmg = float(ea[2]) if ea.size() > 2 else 25.0
		fx.id = "elixir_sorcery_proc"
		o.add_effect(fx)
		fx.expire_at = o.match_ref.time + duration() if o.match_ref != null else 180.0


class SorceryProc extends Effect:
	var true_dmg := 25.0
	var expire_at := 0.0
	var _cd := {}

	func on_damage_dealt(info) -> void:
		var o = owner
		if o == null or info == null or info.is_proc or info.target == null:
			return
		var t = info.target
		if not is_instance_valid(t) or t.dead:
			return
		var champ_t: bool = t.kind == G.Kind.CHAMPION
		if not champ_t and t.kind != G.Kind.TURRET and t.kind != G.Kind.INHIBITOR and t.kind != G.Kind.NEXUS:
			return
		var now: float = o.match_ref.time if o.match_ref != null else 0.0
		if now < float(_cd.get(t, -99.0)) + (5.0 if champ_t else 0.0):
			return
		_cd[t] = now
		Combat.deal(o, t, true_dmg, G.DmgType.TRUE, {"is_proc": true, "tag": "elixir"})

	func on_tick(u, _dt: float) -> void:
		if u.match_ref != null and u.match_ref.time > expire_at:
			u.remove_effect(self)


class ElixirWrath extends Elixir:
	func _init() -> void:
		super._init()
		elixir_id = ID_ELIXIR_WRATH
		max_stacks = 1

	func apply(o) -> void:
		var ea: Array = ItemDB.meta(elixir_id).effect_amount
		K.buff(o, "elixir_wrath", duration(), {"ad": float(ea[0])}, o, {"name": "Elixir of Wrath"})
		var fx := WrathVamp.new()
		fx.vamp = float(ea[2]) if ea.size() > 2 else 0.12
		fx.id = "elixir_wrath_vamp"
		o.add_effect(fx)
		fx.expire_at = o.match_ref.time + duration() if o.match_ref != null else 180.0


class WrathVamp extends Effect:
	var vamp := 0.12
	var expire_at := 0.0

	func on_damage_dealt(info) -> void:
		var o = owner
		if o == null or info == null or info.target == null or info.type != G.DmgType.PHYSICAL:
			return
		if info.target.kind != G.Kind.CHAMPION:
			return
		Combat.heal(o, o, info.final * vamp, {"is_vamp": true, "show": false, "tag": "elixir_wrath"})

	func on_tick(u, _dt: float) -> void:
		if u.match_ref != null and u.match_ref.time > expire_at:
			u.remove_effect(self)


## ---------------------------------------------------------------------------------------------- Cappa Juice
class CappaJuiceItem extends Item:
	func on_attach(_u) -> void:
		stats = {
			"ap": float(ItemDB.data(ID_CAPPA_JUICE, "APPerStack", 10.0)),
			"ad": float(ItemDB.data(ID_CAPPA_JUICE, "ADPerStack", 6.0)),
			"hp": float(ItemDB.data(ID_CAPPA_JUICE, "HPPerStack", 100.0)),
			"size": float(ItemDB.data(ID_CAPPA_JUICE, "PercentSizeIncrease", 10.0)) / 100.0,
		}
		refresh_stats()
