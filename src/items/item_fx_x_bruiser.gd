class_name ItemFxBruiser
extends RefCounted
## Item behaviour: bruiser family (see ItemFxExtra): hydras, spellblades, fighters, assassins, lethality.
## Numbers come from ItemDB.data(id, "Name") (League data with the ARAM / Kiwi overrides). Where League's data only
## carries a calculation text (no data value) the number is taken from the tooltip and marked "(tooltip)".

const TAKEDOWN_WINDOW := 3.0


static func register(m: Dictionary) -> void:
	for id in [3077, 3074, 6698, 6631]:
		m[id] = func(): return Hydra.new()
	m[3748] = func(): return TitanicHydra.new()
	m[3044] = func(): return Phage.new()
	m[3071] = func(): return BlackCleaver.new()
	for id in [3057, 3078, 3508, 3100, 2510]:
		m[id] = func(): return Spellblade.new()
	m[3053] = func(): return Sterak.new()
	m[3156] = func(): return LifelineShield.new()
	m[3155] = func(): return LifelineShield.new()
	m[6333] = func(): return DeathsDance.new()
	m[6692] = func(): return Eclipse.new()
	m[3161] = func(): return Shojin.new()
	m[3142] = func(): return Youmuu.new()
	m[3814] = func(): return EdgeOfNight.new()
	m[6696] = func(): return AxiomArc.new()
	m[126697] = func(): return Hubris.new()
	m[2501] = func(): return Bloodmail.new()
	m[4003] = func(): return SoulAnchor.new()
	m[4004] = func(): return SoulAnchor.new()
	m[3146] = func(): return Gunblade.new()
	m[3179] = func(): return UmbralGlaive.new()
	m[2517] = func(): return EndlessHunger.new()
	m[2512] = func(): return Fiendhunter.new()
	m[3073] = func(): return Hexplate.new()
	m[3181] = func(): return Hullbreaker.new()
	m[6609] = func(): return ChempunkChainsword.new()
	m[6610] = func(): return SunderedSky.new()


# ===================================================================== helpers
static func dv(item_id: int, key: String, default: float = 0.0) -> float:
	return float(ItemDB.data(item_id, key, default))


static func is_structure(u) -> bool:
	return u.kind == G.Kind.TURRET or u.kind == G.Kind.INHIBITOR or u.kind == G.Kind.NEXUS


## True when `victim` was damaged by `who` within `window` seconds (takedown-window passives).
static func damaged_within(victim, who, window: float) -> bool:
	if victim == null or who == null or not is_instance_valid(victim) or not is_instance_valid(who):
		return false
	var t = victim.damage_log.get(who)
	return t != null and who.match_ref != null and who.match_ref.time - float(t) <= window


## Estimated health the unit would lose from `info` (post mitigation, after its shields) - used by "would reduce your
## Health below X%" passives, which must act BEFORE the damage lands (pre hooks).
static func predicted_loss(u, info) -> float:
	var src = info.source if info.source != null and is_instance_valid(info.source) else null
	var raw: float = (info.amount + info.flat_bonus) * info.mult
	if src != null:
		raw *= 1.0 + src.stats.dmg_amp
	raw *= 1.0 - u.stats.dmg_reduction
	if info.type == G.DmgType.PHYSICAL:
		raw *= Combat.resist_multiplier(u.stats.armor, src, true)
	elif info.type == G.DmgType.MAGIC:
		raw *= Combat.resist_multiplier(u.stats.mr, src, false)
	return maxf(0.0, raw - u.total_shield(info.type))


static func would_drop_below(u, info, frac: float) -> bool:
	if u.dead or info.cancelled or info.amount <= 0.0:
		return false
	return u.hp - predicted_loss(u, info) < u.stats.max_hp * frac


## Refresh a hidden-free flat/percent stat buff without allocating when it is already running.
static func timed_buff(u, id: String, dur: float, stats: Dictionary, nm: String = "") -> Buff:
	var b: Buff = u.find_buff(id)
	if b != null:
		b.remaining = maxf(b.remaining, dur)
		if b.stats != stats:
			b.stats = stats
			u.stats.mark_dirty()
		return b
	return K.buff(u, id, dur, stats, u, {"name": nm if nm != "" else id})


## Item damage that also benefits from life steal (League: Ravenous Hydra, Hullbreaker ...). Omnivamp is handled by Combat.
static func proc_lifesteal(it: Item, target, amount: float, type: int, tag: String, aoe: bool = false) -> DamageInfo:
	var o = it.owner
	var info := Combat.deal(o, target, amount, type, {"is_proc": true, "is_aoe": aoe, "tag": tag})
	if o.stats.lifesteal > 0.0 and info.mitigated > 0.0 and not info.cancelled and not is_structure(target) and not o.dead:
		Combat.heal(o, o, info.mitigated * o.stats.lifesteal, {"is_vamp": true, "show": false})
	return info


## "Rage / Quicken / Fervor": flat move speed after attacking / dealing damage. `ranged_mod` is League's RangedMod data value.
static func flat_ms(it: Item, id: String, dur_key: String, amt_key: String, default_amt: float, default_dur: float) -> void:
	var amt := dv(it.item_id, amt_key, default_amt)
	if not it.is_melee():
		amt *= dv(it.item_id, "RangedMod", 1.0)
	timed_buff(it.owner, id, dv(it.item_id, dur_key, default_dur), {"ms": amt}, "Rage" if id == "rage" else "Fervor")


# ===================================================================== Phage (Rage)
class Phage extends Item:
	func on_attack_hit(_t, info) -> void:
		if info != null and info.is_attack:
			ItemFxBruiser.flat_ms(self, "rage", "MoveSpeedDuration", "MoveSpeedBonus", 20.0, 2.0)


# ===================================================================== Black Cleaver
class BlackCleaver extends Item:
	var last_carve := {}

	func on_damage_dealt(info) -> void:
		if info.type != G.DmgType.PHYSICAL or info.target == null or info.final + info.absorbed <= 0.0:
			return
		var t = info.target
		# Fervor: dealing physical damage grants flat move speed
		ItemFxBruiser.flat_ms(self, "fervor", "MoveSpeedDuration", "MoveSpeedBonus", 20.0, 2.0)
		if t.kind != G.Kind.CHAMPION:
			return
		var now_t: float = owner.match_ref.time
		var iid: int = t.get_instance_id()
		if now_t - float(last_carve.get(iid, -10.0)) < ItemDB.data(item_id, "InternalCD", 0.01):
			return
		last_carve[iid] = now_t
		var max_stacks := int(ItemDB.data(item_id, "MaxStacks", 5.0))
		var dur: float = ItemDB.data(item_id, "DebuffDuration", 6.0)
		var b: Buff = t.find_buff("carve", owner)
		if b == null:
			b = Buff.new("carve", dur)
			b.display_name = "Carve"
			b.is_debuff = true
			b.max_stacks = max_stacks
			b.stack_mode = Buff.Stack.ADD_STACK
			b.stats_per_stack = {"armor%": -float(ItemDB.data(item_id, "ShredPerStack", 0.06))}
			t.add_buff(b, owner)
		else:
			b.stacks = mini(max_stacks, b.stacks + 1)
			b.remaining = dur
			t.stats.mark_dirty()


# ===================================================================== Hydras (Cleave + active)
class Hydra extends Item:
	## Tiamat 3077 / Ravenous 3074 / Profane 6698 / Stridebreaker 6631.
	func _cleave_radius() -> float:
		return ItemFxBruiser.dv(item_id, "PassiveRadius" if item_id == 6631 else "CleaveRadius", 350.0) * G.U

	func _active_radius() -> float:
		match item_id:
			6631: return ItemFxBruiser.dv(item_id, "CleaveRadius", 450.0) * G.U
			6698: return ItemFxBruiser.dv(item_id, "ActiveRadius", 450.0) * G.U
		return ItemFxBruiser.dv(item_id, "Radius", 450.0) * G.U

	func _active_ratio() -> float:
		match item_id:
			3077: return ItemFxBruiser.dv(item_id, "ActiveADRatio", 0.75)
			3074: return ItemFxBruiser.dv(item_id, "ActiveADRatio", 1.0)
			6631: return ItemFxBruiser.dv(item_id, "ADRatio", 1.0)
		return 0.8   # Profane Hydra "Heretical Cleave" 80% AD (tooltip)

	func on_attack_hit(t, info) -> void:
		if info == null or not info.is_attack or info.on_hit_mult < 1.0 or ItemFxBruiser.is_structure(t):
			return
		var o = owner
		var dmg: float = o.stats.ad * (0.4 if is_melee() else 0.2)   # Cleave: 40% AD melee / 20% AD ranged (tooltip)
		var cap := int(ItemFxBruiser.dv(item_id, "MaxProcPerAuto", 10.0))
		var n := 0
		var lifesteal := item_id == 3074
		for e in o.match_ref.enemies_in_radius(o.team, t.global_position, _cleave_radius()):
			if e == t:
				continue
			if n >= cap:
				break
			n += 1
			if lifesteal:
				ItemFxBruiser.proc_lifesteal(self, e, dmg, G.DmgType.PHYSICAL, "cleave", true)
			else:
				Combat.deal(o, e, dmg, G.DmgType.PHYSICAL, {"is_proc": true, "is_aoe": true, "tag": "cleave"})
		if n > 0:
			Vfx.ring(o.match_ref, t.global_position, Color(0.9, 0.7, 0.4), _cleave_radius(), 0.25, 0.25, 0.0)

	func use_active(_p: Vector3, _h) -> bool:
		var o = owner
		var r := _active_radius()
		var center: Vector3 = o.global_position + o.facing * 1.0   # centred 100 units in front of the caster
		var dmg: float = o.stats.ad * _active_ratio()
		var champs_hit := 0
		for e in o.match_ref.enemies_in_radius(o.team, center, r):
			if item_id == 3074:
				ItemFxBruiser.proc_lifesteal(self, e, dmg, G.DmgType.PHYSICAL, "hydra", true)
			else:
				Combat.deal(o, e, dmg, G.DmgType.PHYSICAL, {"is_proc": true, "is_aoe": true, "tag": "hydra"})
			if item_id == 6631:
				K.slow(e, absf(ItemFxBruiser.dv(item_id, "MSSlow", -0.35)), ItemFxBruiser.dv(item_id, "Duration", 3.0), o)
			if e.kind == G.Kind.CHAMPION:
				champs_hit += 1
		if item_id == 6631 and champs_hit > 0:
			# 45% decaying Move Speed per champion hit for 3 seconds
			K.haste(o, ItemFxBruiser.dv(item_id, "ActiveMS", 0.45) * champs_hit, ItemFxBruiser.dv(item_id, "Duration", 3.0), o, true, "stridebreaker_ms")
		Vfx.ring(o.match_ref, center, Color(1.0, 0.7, 0.35), r, 0.35, 0.2, 0.15)
		return true

	func ai_should_activate(ctx) -> bool:
		return ctx.count_enemies_near(owner.global_position + owner.facing * 1.0, _active_radius() - 0.3, false) >= 1


class TitanicHydra extends Item:
	var empowered := false

	func _mod() -> float:
		return 1.0 if is_melee() else ItemFxBruiser.dv(item_id, "RangedEffectiveness", 0.5)

	func on_attack_hit(t, info) -> void:
		if info == null or not info.is_attack or info.on_hit_mult < 1.0:
			return
		var o = owner
		var act := empowered
		empowered = false
		var prim: float = ItemFxBruiser.dv(item_id, "ActivePrimaryTargetHPRatio" if act else "PrimaryTargetHPRatio", 0.01)
		var splash: float = ItemFxBruiser.dv(item_id, "ActiveSplashHPRatio" if act else "SplashHPRatio", 0.03)
		var cap := int(ItemFxBruiser.dv(item_id, "MaxProcPerAuto", 10.0))
		proc(t, o.stats.max_hp * prim * _mod(), G.DmgType.PHYSICAL, "titanic")
		var n := 0
		for e in o.match_ref.units_in_cone(o.team, t.global_position, G.flat_dir(o.global_position, t.global_position), 4.5, 70.0):
			if e == t or n >= cap:
				continue
			n += 1
			Combat.deal(o, e, o.stats.max_hp * splash * _mod(), G.DmgType.PHYSICAL, {"is_proc": true, "is_aoe": true, "tag": "titanic"})

	func use_active(_p: Vector3, _h) -> bool:
		if empowered:
			return false
		empowered = true
		Vfx.rising(owner, Color(1.0, 0.75, 0.4), 0.6, 14)
		return true

	func ai_should_activate(ctx) -> bool:
		return not empowered and ctx.count_enemies_near(owner.global_position, owner.attack_range_m() + 1.0) >= 1


# ===================================================================== Spellblade family
class Spellblade extends Item:
	## Sheen 3057, Trinity Force 3078, Essence Reaver 3508, Lich Bane 3100, Dusk and Dawn 2510. Only the strongest
	## Spellblade item on a champion primes / procs. Other families can reuse this by defining spellblade_rank().
	var primed := false
	var left := 0.0
	var cd := 0.0

	func spellblade_rank() -> int:
		match item_id:
			3078: return 5
			3100: return 4
			3508: return 3
			2510: return 2
		return 1

	func _is_main() -> bool:
		var mine := spellblade_rank()
		for e in owner.items:
			if e != self and e.has_method("spellblade_rank"):
				var r: int = e.spellblade_rank()
				if r > mine or (r == mine and owner.items.find(e) < owner.items.find(self)):
					return false
		return true

	func _window() -> float:
		return ItemFxBruiser.dv(item_id, "SpellBladeDuration", 10.0)

	func _set_primed(v: bool) -> void:
		if primed != v:
			primed = v
			refresh_stats()   # Lich Bane: bonus attack speed while primed

	func get_stat_mods() -> Dictionary:
		var as_bonus := ItemFxBruiser.dv(item_id, "SheenASBuff", 0.0)
		if primed and as_bonus > 0.0:
			var d := stats.duplicate()
			d["as"] = d.get("as", 0.0) + as_bonus
			return d
		return stats

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		cd = maxf(0.0, cd - dt)
		if primed:
			left -= dt
			if left <= 0.0 or not _is_main():
				_set_primed(false)

	func on_ability_cast(ab, _t) -> void:
		if ab.is_summoner or cd > 0.0 or not _is_main():
			return
		left = _window()
		_set_primed(true)

	func on_attack_hit(t, info) -> void:
		if info == null or not info.is_attack:
			return
		if item_id == 3078:   # Quicken
			ItemFxBruiser.flat_ms(self, "rage", "MSDuration", "MoveSpeedBonus", 20.0, 2.0)
		if not primed or info.on_hit_mult < 1.0:
			return
		_set_primed(false)
		cd = ItemFxBruiser.dv(item_id, "SpellbladeCooldown", 1.5)
		var o = owner
		var base_ad: float = o.stats.base_ad
		var col := Color(0.6, 0.8, 1.0)
		match item_id:
			3078:
				proc(t, base_ad * ItemFxBruiser.dv(item_id, "SpellbladeMultiplier", 2.0), G.DmgType.PHYSICAL, "spellblade")
			3508:
				var amt: float = base_ad * ItemFxBruiser.dv(item_id, "BaseADRatio", 1.25) \
						+ ItemFxBruiser.dv(item_id, "CritChanceMultiplier", 50.0) * o.stats.crit_chance
				proc(t, amt, G.DmgType.PHYSICAL, "spellblade")
				if o.stats.uses_mana:
					o.mana = minf(o.stats.max_mana, o.mana + amt)
			3100:
				proc(t, ItemFxBruiser.dv(item_id, "SpellbladeADRatio", 0.75) * base_ad + ItemFxBruiser.dv(item_id, "LichBaneAPValue", 0.45) * o.stats.ap, G.DmgType.MAGIC, "spellblade")
				col = Color(0.7, 0.4, 1.0)
			2510:
				proc(t, 0.75 * base_ad + 0.10 * o.stats.ap, G.DmgType.MAGIC, "spellblade")
				Combat.heal(o, o, 0.10 * o.stats.ap + 0.03 * ItemFx.bonus_hp(o))
				col = Color(1.0, 0.75, 0.4)
				# then applies On-Hit effects an additional time (0.2 s later, tooltip / wiki)
				var self_ref := self
				o.match_ref.after(0.2, func():
					if is_instance_valid(o) and not o.dead and is_instance_valid(t) and not t.dead:
						o.trigger_on_hit(t, info, 1.0, self_ref))
			_:
				proc(t, base_ad, G.DmgType.PHYSICAL, "spellblade")   # Sheen: 100% base AD (tooltip)
		Vfx.hit_spark(o.match_ref, t.global_position + Vector3(0, 1.1, 0), col, 0.8)


# ===================================================================== Sterak's Gage
class Sterak extends Item:
	var cd := 0.0
	var shield: Dictionary = {}
	var age := 0.0

	func get_stat_mods() -> Dictionary:
		var d := stats.duplicate()
		if owner != null:
			d["ad"] = d.get("ad", 0.0) + ItemFxBruiser.dv(item_id, "ADtoAD", 0.5) * owner.stats.base_ad   # The Claws that Catch
		return d

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		cd = maxf(0.0, cd - dt)
		if not shield.is_empty():
			var alive := false
			for x in u.shields:
				if is_same(x, shield):
					alive = true
					break
			if not alive:
				shield = {}
				return
			age += dt
			var hold := ItemFxBruiser.dv(item_id, "TimeBeforeDecay", 0.75)
			var total := ItemFxBruiser.dv(item_id, "ShieldDuration", 4.5)
			if age > hold:
				shield.amount = minf(shield.amount, shield.max * clampf(1.0 - (age - hold) / maxf(0.01, total - hold), 0.0, 1.0))

	func on_pre_damage_taken(info) -> void:
		if cd > 0.0 or not ItemFxBruiser.would_drop_below(owner, info, ItemFxBruiser.dv(item_id, "LowHealthThreshold", 0.3)):
			return
		cd = ItemFxBruiser.dv(item_id, "Cooldown", 60.0)
		var amt := ItemFx.bonus_hp(owner) * ItemFxBruiser.dv(item_id, "BaseShieldRatio", 0.7)
		shield = Combat.shield(owner, owner, amt, ItemFxBruiser.dv(item_id, "ShieldDuration", 4.5), {"id": "steraks"})
		age = 0.0
		Vfx.shield_bubble(owner, Color(1.0, 0.7, 0.3), 1.5, 1.1)


# ===================================================================== Hexdrinker / Maw of Malmortius
class LifelineShield extends Item:
	## Hexdrinker "Lifeline" (magic shield) and Maw of Malmortius (+ omnivamp until end of combat).
	var cd := 0.0

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		cd = maxf(0.0, cd - dt)

	func on_pre_damage_taken(info) -> void:
		if cd > 0.0 or info.type != G.DmgType.MAGIC:
			return
		if not ItemFxBruiser.would_drop_below(owner, info, ItemFxBruiser.dv(item_id, "LowHealthThreshold", 0.3)):
			return
		cd = ItemFxBruiser.dv(item_id, "Cooldown", 60.0)
		var o = owner
		var amt: float
		if item_id == 3156:
			var base: float = ItemFxBruiser.dv(item_id, "ShieldSize", 200.0)
			if not is_melee():
				base *= ItemFxBruiser.dv(item_id, "RangedShieldMod", 0.75)
			amt = base + ItemFxBruiser.dv(item_id, "ShieldADScaling", 1.5) * o.stats.bonus_ad
			ItemFxBruiser.timed_buff(o, "maw_vamp", ItemFxBruiser.dv(item_id, "BuffDuration", 5.0), {"omnivamp": ItemFxBruiser.dv(item_id, "BuffVamp", 0.1)}, "Maw of Malmortius")
		else:
			amt = lvl_lerp(110.0, 280.0)   # 110 - 280 based on level (tooltip)
		Combat.shield(o, o, amt, ItemFxBruiser.dv(item_id, "ShieldDuration", 3.0 if item_id == 3156 else 2.5), {"type": G.DmgType.MAGIC, "id": "lifeline_%d" % item_id})
		Vfx.shield_bubble(o, Color(0.6, 0.5, 1.0), 2.5, 1.1)

	func _extend(other) -> void:
		if item_id != 3156 or other == null or other.kind != G.Kind.CHAMPION:
			return
		var b: Buff = owner.find_buff("maw_vamp")
		if b != null:
			b.remaining = maxf(b.remaining, ItemFxBruiser.dv(item_id, "BuffExtension", 3.0))

	func on_damage_dealt(info) -> void:
		_extend(info.target)

	func on_damage_taken(info) -> void:
		_extend(info.source)


# ===================================================================== Death's Dance
class DeathsDance extends Item:
	func on_damage_taken(info) -> void:
		if info.tag == "deathsdance" or info.no_hooks or owner.dead:
			return
		if info.type != G.DmgType.PHYSICAL and info.type != G.DmgType.MAGIC:
			return
		var pct := 0.3 if is_melee() else 0.1   # Ignore Pain: 30% melee / 10% ranged of post-mitigation damage (tooltip)
		var stored: float = minf(info.mitigated * pct, info.final)
		if stored <= 0.5:
			return
		owner.hp = minf(owner.stats.max_hp, owner.hp + stored)   # put the delayed part back; it bleeds as true damage
		var src = info.source
		var t = owner
		var per: float = stored / 3.0
		var b := Buff.new("deaths_dance", 3.05)
		b.stack_mode = Buff.Stack.INDEPENDENT
		b.hidden = true
		b.tick_interval = 1.0
		b.on_interval = func(_x):
			if is_instance_valid(t) and not t.dead:
				Combat.deal(src if src != null and is_instance_valid(src) else null, t, per, G.DmgType.TRUE, {"is_proc": true, "is_dot": true, "no_hooks": true, "tag": "deathsdance", "show_number": false})
		owner.add_buff(b, owner)

	func on_takedown(victim) -> void:
		if victim == null or not ItemFxBruiser.damaged_within(victim, owner, ItemDB.data(item_id, "TakedownWindow", 3.0)):
			return
		owner.remove_buffs_by_id("deaths_dance")   # cleanse Ignore Pain's remaining damage
		var total: float = ItemDB.data(item_id, "BonusADRatio", 1.0) * owner.stats.bonus_ad
		var t = owner
		var per := total / 8.0
		var b := Buff.new("deaths_dance_heal", 2.05)
		b.stack_mode = Buff.Stack.INDEPENDENT
		b.hidden = true
		b.tick_interval = 0.25
		b.on_interval = func(_x):
			if is_instance_valid(t) and not t.dead:
				Combat.heal(t, t, per, {"show": false})
		owner.add_buff(b, owner)


# ===================================================================== Eclipse
class Eclipse extends Item:
	var hits := {}
	var cd := 0.0

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		cd = maxf(0.0, cd - dt)

	func on_damage_dealt(info) -> void:
		var t = info.target
		if cd > 0.0 or t == null or t.kind != G.Kind.CHAMPION or info.is_dot or info.tag == "eclipse":
			return
		if info.is_proc and not info.is_spell and not info.is_pet:
			return
		var now_t: float = owner.match_ref.time
		var win: float = ItemDB.data(item_id, "WindowDuration", 2.0)
		var iid: int = t.get_instance_id()
		var last: float = hits.get(iid, -10.0)
		if now_t - last <= 0.1:
			return   # same cast instance
		if now_t - last < win:
			cd = ItemDB.data(item_id, "Cooldown", 6.0)
			hits.erase(iid)
			var o = owner
			var melee := is_melee()
			var pct: float = ItemDB.data(item_id, "MeleePercMaxHP", 0.08) * (1.0 if melee else ItemDB.data(item_id, "RangedPercMaxHPMult", 0.625))
			proc(t, t.stats.max_hp * pct, G.DmgType.PHYSICAL, "eclipse")
			var base: float = ItemDB.data(item_id, "MeleeBaseShield", 150.0)
			var ratio: float = ItemDB.data(item_id, "MeleeShieldADRatio", 0.5)
			if not melee:
				base *= ItemDB.data(item_id, "RangedShieldMult", 0.5)
				ratio *= 0.5
			Combat.shield(o, o, base + ratio * o.stats.bonus_ad, ItemDB.data(item_id, "ShieldDuration", 2.0))
			Vfx.burst(o.match_ref, t.global_position + Vector3(0, 1, 0), Color(0.95, 0.85, 0.6), 1.0, {"ring": false})
		else:
			hits[iid] = now_t


# ===================================================================== Spear of Shojin
class Shojin extends Item:
	var lock := {}

	func get_stat_mods() -> Dictionary:
		var d := stats.duplicate()
		d["basic_ah"] = d.get("basic_ah", 0.0) + ItemFxBruiser.dv(item_id, "AHBase", 25.0)   # Dragonforce
		return d

	func _per_stack() -> float:
		return ItemFxBruiser.dv(item_id, "SpellDamageIncrease", 0.03) * (1.0 if is_melee() else ItemFxBruiser.dv(item_id, "RangedMod", 0.5))

	func on_pre_damage_dealt(info) -> void:
		if info.is_spell:
			var b: Buff = owner.find_buff("shojin")
			if b != null:
				info.mult *= 1.0 + _per_stack() * b.stacks

	func on_damage_dealt(info) -> void:
		if not info.is_spell or info.target == null or info.is_dot or ItemFxBruiser.is_structure(info.target):
			return
		var now_t: float = owner.match_ref.time
		var key: int = info.ability.get_instance_id() if info.ability != null else 0
		if now_t - float(lock.get(key, -10.0)) < ItemFxBruiser.dv(item_id, "CastIDLockout", 1.0):
			return
		lock[key] = now_t
		var dur := ItemFxBruiser.dv(item_id, "StackDuration", 6.0)
		var mx := int(ItemFxBruiser.dv(item_id, "StackCount", 4.0))
		var b: Buff = owner.find_buff("shojin")
		if b == null:
			K.buff(owner, "shojin", dur, {}, owner, {"name": "Focused Will", "max_stacks": mx, "stack_mode": Buff.Stack.ADD_STACK})
		else:
			b.stacks = mini(mx, b.stacks + 1)
			b.remaining = dur


# ===================================================================== Youmuu's Ghostblade
class Youmuu extends Item:
	var ooc := false

	func get_stat_mods() -> Dictionary:
		if ooc:
			var d := stats.duplicate()
			d["ms"] = d.get("ms", 0.0) + ItemFxBruiser.dv(item_id, "BaseOOCMS", 30.0) * (1.0 if is_melee() else 0.5)   # Haunt (ranged half, wiki)
			return d
		return stats

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		var now_ooc := not ItemFx.in_combat(u)
		if now_ooc != ooc:
			ooc = now_ooc
			refresh_stats()

	func use_active(_p: Vector3, _h) -> bool:
		var pct: float = ItemFxBruiser.dv(item_id, "MeleeItemCalcValueB" if is_melee() else "RangedItemCalcValueB", 45.0 if is_melee() else 30.0) / 100.0
		K.buff(owner, "youmuu", ItemFxBruiser.dv(item_id, "DurationNDV", 6.0), {"ms%": pct}, owner, {"name": "Wraith Step", "cc": Buff.CC.GHOSTED})
		Vfx.rising(owner, Color(0.6, 0.3, 0.9), 1.0, 30)
		return true

	func ai_should_activate(ctx) -> bool:
		return (ctx.mode == "fight" and ctx.count_enemies_near(owner.global_position, 12.0) >= 1) or (ctx.mode == "retreat" and ctx.in_danger())


# ===================================================================== Edge of Night
class EdgeOfNight extends Item:
	## Annul: spell shield that blocks the next enemy Ability (damage part; see report: no CC pre-hook in core).
	var cd := 0.0

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		cd = maxf(0.0, cd - dt)

	func on_pre_damage_taken(info) -> void:
		if cd > 0.0 or not info.is_spell or info.is_dot or info.source == null or not is_instance_valid(info.source):
			return
		if info.source.team == owner.team or info.source.kind != G.Kind.CHAMPION:
			return
		cd = ItemDB.data(item_id, "Cooldown", 30.0)
		info.cancelled = true
		Vfx.shield_bubble(owner, Color(0.7, 0.5, 1.0), 0.5, 1.1)


# ===================================================================== Axiom Arc
class AxiomArc extends Item:
	func on_takedown(victim) -> void:
		if victim == null or victim.kind != G.Kind.CHAMPION or not ItemFxBruiser.damaged_within(victim, owner, ItemDB.data(item_id, "ResetWindow", 3.0)):
			return
		# Flux: refunds 10% (+0.25% per Lethality) of the Ultimate's total cooldown
		var pct: float = ItemDB.data(item_id, "UltimateRefundBase", 10.0) / 100.0 + 0.0025 * owner.stats.lethality
		for ab in owner.abilities:
			if ab != null and (ab.is_ult or ab.slot == 3) and ab.cd > 0.0:
				ab.reduce_cooldown(ab.cd_total * pct)


# ===================================================================== Hubris
class Hubris extends Item:
	var kills := 0

	func on_takedown(victim) -> void:
		if victim == null or victim.kind != G.Kind.CHAMPION or not ItemFxBruiser.damaged_within(victim, owner, ItemDB.data(item_id, "TakedownWindow", 3.0)):
			return
		kills += 1   # Eminence: permanent stack per champion takedown
		var melee := is_melee()
		var ad: float = ItemDB.data(item_id, "BaseADBonusMelee" if melee else "BaseADBonusRange", 15.0) + ItemDB.data(item_id, "ADPerStatueMelee" if melee else "ADPerStatueRange", 2.0) * kills
		var dur: float = ItemDB.data(item_id, "BuffDurationMelee" if melee else "BuffDurationRange", 90.0)
		var b: Buff = owner.find_buff("hubris")
		if b != null:
			b.stats = {"ad": ad}
			b.remaining = dur
			b.duration = dur
			owner.stats.mark_dirty()
		else:
			K.buff(owner, "hubris", dur, {"ad": ad}, owner, {"name": "Eminence"})


# ===================================================================== Overlord's Bloodmail
class Bloodmail extends Item:
	var given := 0.0

	func get_stat_mods() -> Dictionary:
		var d := stats.duplicate()
		if owner != null:
			var tyranny: float = ItemDB.data(item_id, "HPToADPercentage", 0.025) * ItemFx.bonus_hp(owner)
			var missing: float = 1.0 - owner.hp_ratio()
			var thr: float = ItemDB.data(item_id, "MissingHealthThreshold", 0.7)
			var other_ad: float = maxf(0.0, owner.stats.ad - given)
			var retr: float = ItemDB.data(item_id, "MissingHealthAD", 0.12) * clampf(missing / thr, 0.0, 1.0) * other_ad
			given = retr
			d["ad"] = d.get("ad", 0.0) + tyranny + retr
		return d


# ===================================================================== Lifeline / Spectral Cutlass (Soul Anchor)
class SoulAnchor extends Item:
	var mark := Vector3.ZERO
	var marked := false
	var left := 0.0

	func activate(pos: Vector3, hovered) -> void:
		if marked and not owner.dead:
			_return()   # recast: return to the marked location early
			return
		super.activate(pos, hovered)

	func use_active(_p: Vector3, _h) -> bool:
		mark = owner.global_position
		marked = true
		left = ItemDB.data(item_id, "Duration", 4.0)
		Vfx.ring(owner.match_ref, mark, Color(0.6, 0.8, 1.0), 1.0, left, 0.12, 0.1)
		return true

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		if marked:
			left -= dt
			if left <= 0.0:
				_return()

	func on_death(_k) -> void:
		marked = false

	func _return() -> void:
		if not marked:
			return
		marked = false
		if owner.dead:
			return
		Vfx.ring(owner.match_ref, owner.global_position, Color(0.6, 0.8, 1.0), 1.2, 0.3, 0.12, 0.1)
		owner.teleport(mark)
		Vfx.ring(owner.match_ref, mark, Color(0.6, 0.8, 1.0), 1.2, 0.3, 0.12, 0.1)

	func ai_should_activate(ctx) -> bool:
		# hit-and-run: mark the spot before engaging, the anchor pulls the bot back after the burst
		return not marked and ctx.mode == "fight" and owner.hp_ratio() > 0.5 and ctx.count_enemies_near(owner.global_position, 9.0) >= 1


# ===================================================================== Hextech Gunblade
class Gunblade extends Item:
	func _target(hovered):
		var o = owner
		var rng := 7.0
		if hovered != null and is_instance_valid(hovered) and not hovered.dead and hovered.kind == G.Kind.CHAMPION \
				and hovered.team != o.team and hovered.is_targetable_by(o.team) and o.edge_dist(hovered) <= rng:
			return hovered
		var best = null
		var bd := INF
		for e in o.match_ref.enemies_in_radius(o.team, o.global_position, rng + 1.5, true):
			var d: float = o.edge_dist(e)
			if d <= rng and d < bd:
				bd = d
				best = e
		return best

	func use_active(_p: Vector3, hovered) -> bool:
		var t = _target(hovered)
		if t == null:
			return false
		var o = owner
		Combat.deal(o, t, lvl_lerp(175.0, 253.0) + 0.3 * o.stats.ap, G.DmgType.MAGIC, {"is_spell": true, "is_proc": true, "tag": "gunblade"})
		K.slow(t, ItemDB.data(item_id, "SlowAmount", 0.25), ItemDB.data(item_id, "SlowDuration", 1.5), o)
		Vfx.beam(o.match_ref, o.global_position + Vector3(0, 1.4, 0), t.global_position + Vector3(0, 1.2, 0), Color(0.6, 0.8, 1.0), 0.1, 0.25)
		return true

	func ai_should_activate(ctx) -> bool:
		return ctx.mode == "fight" and _target(ctx.focus) != null


# ===================================================================== Umbral Glaive
class UmbralGlaive extends Item:
	var unseen := 0.0
	var ready := false
	var ready_left := 0.0
	var seen_before := true

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		var seen: bool = u.visible_to[G.enemy_team(u.team)]
		if seen:
			if not seen_before and ready:
				ready_left = ItemFxBruiser.dv(item_id, "AttackReadyDuration", 4.0)   # lasts 4 s after being spotted
			unseen = 0.0
			if ready:
				ready_left -= dt
				if ready_left <= 0.0:
					ready = false
		else:
			unseen += dt
			if unseen >= ItemFxBruiser.dv(item_id, "OutOfVisionDuration", 1.0):
				ready = true
		seen_before = seen

	func on_attack_hit(t, info) -> void:
		if not ready or info == null or not info.is_attack or t.kind != G.Kind.CHAMPION:
			return
		ready = false
		# Nightstalker: 50 (+150% stat) true damage - the stat is Lethality (wiki)
		proc(t, 50.0 + 1.5 * owner.stats.lethality, G.DmgType.TRUE, "nightstalker")


# ===================================================================== Endless Hunger
class EndlessHunger extends Item:
	func get_stat_mods() -> Dictionary:
		var d := stats.duplicate()
		if owner != null:
			# Famine: 5 (+13% melee / 10% ranged bonus AD) Ability Haste (tooltip calculation)
			d["ah"] = d.get("ah", 0.0) + 5.0 + (0.13 if is_melee() else 0.10) * owner.stats.bonus_ad
		return d

	func on_takedown(victim) -> void:
		if victim == null or victim.kind != G.Kind.CHAMPION or not ItemFxBruiser.damaged_within(victim, owner, ItemDB.data(item_id, "TakedownWindow", 3.0)):
			return
		ItemFxBruiser.timed_buff(owner, "feast", ItemDB.data(item_id, "OmnivampDuration", 8.0), {"omnivamp": ItemDB.data(item_id, "OmnivampOnTakedown", 0.15)}, "Feast")


# ===================================================================== Fiendhunter Bolts
class Fiendhunter extends Item:
	var left := 0.0       ## seconds of Opening Barrage remaining
	var attacks := 0
	var cd := 0.0
	var _mark = null
	var _true_dmg := 0.0

	func get_stat_mods() -> Dictionary:
		var d := stats.duplicate()
		d["ult_ah"] = d.get("ult_ah", 0.0) + ItemFxBruiser.dv(item_id, "UltimateHaste", 30.0)   # Night Vigil
		if left > 0.0:
			d["as"] = d.get("as", 0.0) + ItemFxBruiser.dv(item_id, "BonusAS", 0.5)
		return d

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		cd = maxf(0.0, cd - dt)
		if left > 0.0:
			left -= dt
			if left <= 0.0:
				_end()

	func _end() -> void:
		left = 0.0
		attacks = 0
		refresh_stats()

	func on_ability_cast(ab, _t) -> void:
		if ab.is_ult and cd <= 0.0:
			cd = ItemDB.data(item_id, "Cooldown", 45.0)
			left = ItemDB.data(item_id, "Duration", 8.0)
			attacks = int(ItemDB.data(item_id, "NumberOfAttacks", 3.0))
			refresh_stats()

	func on_pre_damage_dealt(info) -> void:
		if left <= 0.0 or not info.is_attack or info.is_proc:
			return
		attacks -= 1
		if info.is_crit and not info.has_meta("forced_crit"):
			# would already crit: normal crit damage + 15% of the attack's damage as true damage
			_mark = info
			_true_dmg = info.amount * ItemDB.data(item_id, "BonusTrueDamage", 0.15)
		elif not info.is_crit:
			info.is_crit = true
			info.set_meta("forced_crit", true)
			info.amount *= owner.stats.crit_damage * ItemDB.data(item_id, "CritModifier", 0.8)
		if attacks <= 0:
			_end()

	func on_damage_dealt(info) -> void:
		if _mark != null and info == _mark:
			_mark = null
			if info.target != null and is_instance_valid(info.target) and not info.target.dead:
				proc(info.target, _true_dmg, G.DmgType.TRUE, "fiendhunter")


# ===================================================================== Experimental Hexplate
class Hexplate extends Item:
	var left := 0.0
	var cd := 0.0

	func get_stat_mods() -> Dictionary:
		var d := stats.duplicate()
		d["ult_ah"] = d.get("ult_ah", 0.0) + ItemFxBruiser.dv(item_id, "UltimateHaste", 30.0)   # Hexcharged
		if left > 0.0:
			var melee := is_melee()
			d["as"] = d.get("as", 0.0) + ItemFxBruiser.dv(item_id, "BonusASMelee" if melee else "BonusASRanged", 50.0) / 100.0
			d["ms%"] = d.get("ms%", 0.0) + ItemFxBruiser.dv(item_id, "BonusMSMelee" if melee else "BonusMSRanged", 20.0) / 100.0
		return d

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		cd = maxf(0.0, cd - dt)
		if left > 0.0:
			left -= dt
			if left <= 0.0:
				refresh_stats()

	func on_ability_cast(ab, _t) -> void:
		if ab.is_ult and cd <= 0.0:
			cd = ItemDB.data(item_id, "Cooldown", 30.0)
			left = ItemDB.data(item_id, "HasteDuration", 8.0)   # Overdrive
			refresh_stats()


# ===================================================================== Hullbreaker
class Hullbreaker extends Item:
	var stacks := 0
	var left := 0.0
	var acc := 0.0

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		if stacks > 0:
			left -= dt
			if left <= 0.0:
				stacks = 0
		acc += dt
		if acc >= 0.5:
			acc = 0.0
			_boarding_party(u)

	func _boarding_party(u) -> void:
		if u.dead or u.match_ref == null:
			return
		# armor / magic resist for allied siege and super minions within 1050 units (melee 70-130, ranged 35-65 by level; wiki)
		var res := lvl_lerp(70.0, 130.0) if is_melee() else lvl_lerp(35.0, 65.0)
		for m in u.match_ref.units_in_radius(u.global_position, 11.0, u.team):
			if m.kind == G.Kind.MINION and not m.dead and (m.minion_type == Minion.Type.SIEGE or m.minion_type == Minion.Type.SUPER):
				ItemFxBruiser.timed_buff(m, "boarding_party", 1.0, {"armor": res, "mr": res}, "Boarding Party")

	func on_attack_hit(t, info) -> void:
		if info == null or not info.is_attack or info.on_hit_mult < 1.0:
			return
		var strike := ItemFxBruiser.is_structure(t)
		if stacks >= 4 and (t.kind == G.Kind.CHAMPION or strike):
			stacks = 0
			var melee := is_melee()
			var ad_key := "SkipperADRatioVSStructures" if strike else "SkipperADRatio"
			var hp_key := "MaxStackDamageVSStructuresHPRatio" if strike else "MaxStackDamageHPRatio"
			var ad_ratio: float = ItemFxBruiser.dv(item_id, ad_key if melee else "Ranged" + ad_key, 1.2)
			var hp_ratio: float = ItemFxBruiser.dv(item_id, hp_key, 0.05)
			if not melee:
				hp_ratio *= ad_ratio / maxf(0.01, ItemFxBruiser.dv(item_id, ad_key, 1.2))
			ItemFxBruiser.proc_lifesteal(self, t, ad_ratio * owner.stats.base_ad + hp_ratio * ItemFx.bonus_hp(owner), G.DmgType.PHYSICAL, "skipper")
			Vfx.hit_spark(owner.match_ref, t.global_position + Vector3(0, 1.1, 0), Color(0.9, 0.7, 0.3), 0.9)
		else:
			stacks = mini(4, stacks + 1)
			left = ItemFxBruiser.dv(item_id, "SkipperStackDuration", 10.0)


# ===================================================================== Chempunk Chainsword
class ChempunkChainsword extends Item:
	func on_damage_dealt(info) -> void:
		if info.type != G.DmgType.PHYSICAL or info.target == null or info.target.kind != G.Kind.CHAMPION or info.final + info.absorbed <= 0.0:
			return
		var t = info.target
		var dur: float = ItemDB.data(item_id, "GrievousDuration", 3.0)
		var amt: float = ItemDB.data(item_id, "GrievousAmount", 0.4)
		var b: Buff = t.find_buff("grievous", owner)
		if b != null and float(b.stats.get("_gw", 0.0)) >= amt:
			b.remaining = maxf(b.remaining, dur)
		else:
			K.grievous(t, dur, owner, amt)


# ===================================================================== Sundered Sky
class SunderedSky extends Item:
	var cds := {}
	var _mark = null

	func on_pre_damage_dealt(info) -> void:
		var t = info.target
		if not info.is_attack or info.is_proc or t == null or t.kind != G.Kind.CHAMPION:
			return
		var now_t: float = owner.match_ref.time
		var iid: int = t.get_instance_id()
		if now_t - float(cds.get(iid, -100.0)) < ItemDB.data(item_id, "Cooldown", 10.0):
			return
		cds[iid] = now_t
		_mark = info
		if not info.is_crit:
			info.is_crit = true
			info.set_meta("forced_crit", true)
			info.amount *= owner.stats.crit_damage * ItemDB.data(item_id, "CritModifier", 0.8)

	func on_damage_dealt(info) -> void:
		if _mark == null or info != _mark:
			return
		_mark = null
		var o = owner
		var heal: float = ItemDB.data(item_id, "HealBaseADRatio", 0.9) * o.stats.base_ad * (1.0 if is_melee() else ItemDB.data(item_id, "RangedHealMod", 0.5)) \
				+ ItemDB.data(item_id, "MissingHealthHeal", 0.04) * (o.stats.max_hp - o.hp)
		Combat.heal(o, o, heal)
