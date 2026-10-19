class_name ItemFxUpgrades
extends RefCounted
## [numbers] Item behaviour: the Manaflow upgrades (see ItemFxExtra). In League the Manaflow items transform for free once
## they hold 360 bonus Mana: Archangel's Staff -> Seraph's Embrace, Manamune -> Muramana, Winter's Approach -> Fimbulwinter,
## Whispering Circlet -> Diadem of Songs. The upgrades are not sold in the shop (data/items/items.json lists them with
## in_store = false, no recipe); the Manaflow items call ItemFxUpgrades.upgrade() when they reach the cap.
## Numbers come from ItemDB.data() (League data incl. the Kiwi overrides: Seraph's Lifeline cooldown 75 s) or from the item
## bin calculations (marked), tooltips and the wiki.

const TOOLTIP_RADIUS := 1200.0       ## Fimbulwinter: "more than one enemy is nearby" (wiki: 1200 units)


static func register(m: Dictionary) -> void:
	m[3040] = func(): return SeraphsEmbrace.new()
	m[3042] = func(): return Muramana.new()
	m[3121] = func(): return Fimbulwinter.new()
	m[2530] = func(): return DiademOfSongs.new()


## Replace `it` in its owner's inventory (same slot) with the upgrade `new_id`. Safe to call from inside a hook.
static func upgrade(it, new_id: int) -> void:
	var o = it.owner
	if o == null or o.match_ref == null or not ItemDB.has(new_id):
		return
	var me = it
	o.match_ref.after(0.0, func():
		if not is_instance_valid(o) or not (me in o.items):
			return
		var idx: int = o.items.find(me)
		o.remove_item(me)
		var ni := ItemDB.create(new_id)
		if ni == null:
			return
		o.add_item(ni)
		o.items.erase(ni)
		o.items.insert(clampi(idx, 0, o.items.size()), ni)
		o.items_changed.emit())


class Up extends Item:
	var icd := 0.0

	func dv(key: String, default = 0.0) -> float:
		return float(ItemDB.data(item_id, key, default))

	func now() -> float:
		return owner.match_ref.time if owner != null and owner.match_ref != null else 0.0

	func bonus_mana() -> float:
		return owner.stats.m("mana")          # every flat Mana modifier = bonus Mana

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		if icd > 0.0:
			icd = maxf(0.0, icd - dt)
		tick_fx(u, dt)

	func tick_fx(_u, _dt: float) -> void:
		pass

	static func is_champ(u) -> bool:
		return u != null and is_instance_valid(u) and u.kind == G.Kind.CHAMPION

	static func is_structure(u) -> bool:
		return u.kind == G.Kind.TURRET or u.kind == G.Kind.INHIBITOR or u.kind == G.Kind.NEXUS


## ---------------------------------------------------------------------------------------------- Seraph's Embrace
class SeraphsEmbrace extends Up:
	## Awe: Ability Power equal to 2% bonus Mana. Lifeline: damage that would take you below 30% Health first grants a Shield of
	## 18% max Mana for 3 s (bin calc ShieldValue; cooldown 75 s in ARAM / Mayhem).
	var awe := 0.0

	func get_stat_mods() -> Dictionary:
		if awe == 0.0:
			return stats
		var s := stats.duplicate()
		s["ap"] = s.get("ap", 0.0) + awe
		return s

	func tick_fx(u, _dt: float) -> void:
		var want: float = bonus_mana() * dv("APFromMana", 0.02)
		if absf(want - awe) > 0.05:
			awe = want
			refresh_stats()

	func on_pre_damage_taken(info) -> void:
		if icd > 0.0 or owner.dead:
			return
		if not ItemFxBruiser.would_drop_below(owner, info, dv("HealthThreshold", 0.3)):
			return
		icd = dv("LifelineCooldown", 75.0)
		var amt: float = 0.18 * owner.stats.max_mana
		Combat.shield(owner, owner, amt, dv("ShieldDuration", 3.0), {"id": "seraph"})
		Vfx.shield_bubble(owner, Color(0.9, 0.8, 1.0), dv("ShieldDuration", 3.0), 1.1)


## ---------------------------------------------------------------------------------------------- Muramana
class Muramana extends Up:
	## Awe: Attack Damage equal to 2% max Mana. Shock: attacks against champions deal 1.2% max Mana bonus physical damage
	## on-hit; damaging abilities against champions deal 4% (melee) / 3% (ranged) max Mana, once per cast per target
	## (item data: the ratios are tooltip-only values, the calculations are in the item bin).
	var awe := 0.0
	var _seen := {}

	func get_stat_mods() -> Dictionary:
		if awe == 0.0:
			return stats
		var s := stats.duplicate()
		s["ad"] = s.get("ad", 0.0) + awe
		return s

	func tick_fx(u, _dt: float) -> void:
		var want: float = u.stats.max_mana * dv("BonusADManaRatioTOOLTIPONLY", 0.02)
		if absf(want - awe) > 0.05:
			awe = want
			refresh_stats()
		if _seen.size() > 64:
			_seen.clear()

	func on_attack_hit(t, info) -> void:
		if info == null or not info.is_attack or not is_champ(t) or t.team == owner.team:
			return
		var mult: float = info.on_hit_mult if info.on_hit_mult < 0.999 else 1.0
		proc(t, owner.stats.max_mana * dv("OnHitManaRatioTOOLTIPONLY", 0.012) * mult, G.DmgType.PHYSICAL, "shock")

	func on_damage_dealt(info) -> void:
		if not info.is_spell or info.is_proc or info.is_dot or info.ability == null:
			return
		var t = info.target
		if not is_champ(t) or t.team == owner.team:
			return
		var key := "%d:%d:%d" % [info.ability.get_instance_id(), info.ability.cast_count, t.get_instance_id()]
		if _seen.has(key):
			return
		_seen[key] = true
		var r: float = dv("AbilityManaRatioMeleeTOOLTIPONLY", 0.04) if is_melee() else dv("AbilityManaRatioRangedTOOLTIPONLY", 0.03)
		proc(t, owner.stats.max_mana * r, G.DmgType.PHYSICAL, "shock")


## ---------------------------------------------------------------------------------------------- Fimbulwinter
class Fimbulwinter extends Up:
	## Awe: bonus Health equal to 15% bonus Mana (bin calc BonusHPFromMana). Everlasting: Immobilizing (or, for melee
	## champions, Slowing) an enemy champion grants a Shield of 100 + 4.5% current Mana for 3 s, +80% when more than one enemy
	## champion is nearby; 8 s cooldown.
	var awe := 0.0

	func get_stat_mods() -> Dictionary:
		if awe == 0.0:
			return stats
		var s := stats.duplicate()
		s["hp"] = s.get("hp", 0.0) + awe
		return s

	func tick_fx(_u, _dt: float) -> void:
		var want: float = 0.15 * bonus_mana()
		if absf(want - awe) > 0.5:
			awe = want
			refresh_stats()

	func on_cc_applied(target, buff) -> void:
		if icd > 0.0 or owner.dead or not is_champ(target) or target.team == owner.team:
			return
		var immob: bool = (buff.cc & Buff.IMMOBILIZE) != 0
		if not immob and not (buff.slow_amount > 0.0 and is_melee()):
			return
		icd = dv("Cooldown", 8.0)
		var amt: float = 100.0 + dv("CurrentManaShieldRatio", 0.045) * owner.mana     # bin calc ShieldBase = 100
		var n := 0
		for e in owner.match_ref.enemies_in_radius(owner.team, owner.global_position, TOOLTIP_RADIUS * G.U, true):
			n += 1
		if n > 1:
			amt *= 1.0 + dv("Multiplier", 0.8)
		Combat.shield(owner, owner, amt, dv("ShieldDuration", 3.0), {"id": "fimbulwinter"})
		Vfx.shield_bubble(owner, Color(0.7, 0.9, 1.0), dv("ShieldDuration", 3.0), 1.1)


## ---------------------------------------------------------------------------------------------- Diadem of Songs
class DiademOfSongs extends Up:
	## Harmony: Heal and Shield Power equal to 0.5% bonus Mana. Consonance: while you, or an ally you healed or shielded in
	## the last 3 s, is in combat, every second heal the lowest-health ally champion nearby for 0.8% max Mana.
	var hsp := 0.0
	var supported := {}          ## ally instance id -> time you last healed / shielded it
	var _tick := 0.0

	func get_stat_mods() -> Dictionary:
		if hsp == 0.0:
			return stats
		var s := stats.duplicate()
		s["heal_power"] = float(s.get("heal_power", 0.0)) + hsp
		return s

	func on_heal_dealt(target, _amount: float) -> void:
		if target != null and is_instance_valid(target) and target != owner:
			supported[target.get_instance_id()] = now()

	func on_shield_dealt(target, _amount: float) -> void:
		if target != null and is_instance_valid(target) and target != owner:
			supported[target.get_instance_id()] = now()

	func _engaged() -> bool:
		if ItemFx.in_combat(owner):
			return true
		var window := dv("AllyCombatDuration", 3.0)
		for k in supported.keys():
			if now() - float(supported[k]) > window:
				supported.erase(k)
				continue
			var a = instance_from_id(k)
			if a != null and is_instance_valid(a) and not a.dead and ItemFx.in_combat(a):
				return true
		return false

	func tick_fx(u, dt: float) -> void:
		var want: float = 0.00005 * bonus_mana()      # bin calc BonusHSPCalc: 0.005 per bonus Mana, in percent
		if absf(want - hsp) > 0.0002:
			hsp = want
			refresh_stats()
		_tick -= dt
		if _tick > 0.0 or u.dead or not u.stats.uses_mana:
			return
		_tick = 1.0
		if not _engaged():
			return
		var best = null
		var br := 2.0
		for a in u.match_ref.allies_in_radius(u.team, u.global_position, dv("AllyRangeCheck", 900.0) * G.U):
			if a == u or a.dead or a.kind != G.Kind.CHAMPION:
				continue
			var r: float = a.hp_ratio()
			if r < br:
				br = r
				best = a
		if best != null and br < 1.0:
			Combat.heal(u, best, 0.008 * u.stats.max_mana)    # bin calc ManaToHeal: 0.8% of max Mana
