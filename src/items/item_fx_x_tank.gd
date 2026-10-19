extends RefCounted
## Item behaviour: tank family (see ItemFxExtra). Numbers come from League's item data (ItemDB.data / resolved tooltip text,
## ARAM overrides included). Items listed here win over the legacy ItemFx classes.
##
## Implemented: Bami's Cinder / Sunfire Aegis / Hollow Radiance (Immolate, Desolate), Thornmail / Bramble Vest (Thorns),
## Warmog's Armor, Spirit Visage, Frozen Heart, Jak'Sho, Dead Man's Plate, Force of Nature, Heartsteel, Iceborn Gauntlet,
## Unending Despair, Protoplasm Harness, Warden's Mail, Gluttonous Greaves, Winter's Approach.
## Verified legacy (item_fx.gd, faithful, not re-registered): Plated Steelcaps, Randuin's Omen, Atma's Reckoning.

const Tu = preload("res://src/items/item_fx_x_tank_util.gd")
const COMBAT_WINDOW := 5.0   ## seconds without champion damage before "champion combat" ends


static func register(m: Dictionary) -> void:
	m[6660] = func(): return TkImmolate.new()
	m[3068] = func(): return TkImmolate.new()
	m[6664] = func(): return TkImmolate.new()
	m[3075] = func(): return TkThorns.new()
	m[3076] = func(): return TkThorns.new()
	m[3083] = func(): return TkWarmogs.new()
	m[3065] = func(): return TkVisage.new()
	m[3110] = func(): return TkFrozenHeart.new()
	m[6665] = func(): return TkJakSho.new()
	m[3742] = func(): return TkDeadMans.new()
	m[4401] = func(): return TkForceOfNature.new()
	m[3084] = func(): return TkHeartsteel.new()
	m[6662] = func(): return TkIceborn.new()
	m[2502] = func(): return TkUnending.new()
	m[2525] = func(): return TkProtoplasm.new()
	m[3082] = func(): return TkWardensMail.new()
	m[3008] = func(): return TkGluttonous.new()
	m[3119] = func(): return TkWintersApproach.new()


# ------------------------------------------------------------------ base
class TankItem extends Item:
	var last_champ_combat := -100.0   ## last damage dealt to / taken from an enemy champion

	func now() -> float:
		return owner.match_ref.time if owner != null and owner.match_ref != null else 0.0

	func champ_combat() -> bool:
		return now() - last_champ_combat < COMBAT_WINDOW

	func _note_combat(other, info) -> void:
		if other != null and is_instance_valid(other) and other.kind == G.Kind.CHAMPION and other != owner:
			if info.tag != "immolate" and info.tag != "anguish" and info.tag != "thorns" and info.tag != "desolate":
				last_champ_combat = now()

	func on_damage_dealt(info) -> void:
		_note_combat(info.target, info)

	func on_damage_taken(info) -> void:
		_note_combat(info.source, info)

	func bonus_hp() -> float:
		return Tu.owner_bonus_hp(owner)

	func d(key: String, default = 0.0) -> float:
		return float(ItemDB.data(item_id, key, default))


# ------------------------------------------------------------------ Immolate / Desolate
class TkImmolate extends TankItem:
	const RANK := {3068: 3, 6664: 2, 6660: 1}   ## "Limited to 1 Immolate item": the strongest one burns
	var until := -1.0
	var tick_t := 0.0
	var base := 15.0
	var ratio := 0.0
	var minion_mod := 0.5
	var range_m := 3.0
	var aura_dur := 3.0
	var period := 1.0
	# Desolate (Hollow Radiance)
	var proc_base := 0.0
	var proc_ratio := 0.0
	var proc_aoe := 0.0
	var champ_proc_base := 0.0
	var champ_aoe := 0.0
	var takedown_window := 3.0

	func on_attach(_u) -> void:
		var s := Tu.health_scaling(item_id, 0, Vector2(15.0, 0.0))
		base = s.x
		ratio = s.y
		minion_mod = d("MinionMod", 0.5)
		range_m = d("Range", 300.0) * G.U
		aura_dur = d("AuraDuration", 3.0)
		period = 1.0 / maxf(d("TicksPerSecond", 1.0), 0.1)
		if d("ProcAoE", 0.0) > 0.0:
			var p := Tu.health_scaling(item_id, 1, Vector2(base * d("ProcDPSMultiplier", 2.0), ratio))
			proc_base = p.x
			proc_ratio = p.y
			proc_aoe = d("ProcAoE") * G.U
			champ_proc_base = base * d("ChampProcDPSMultiplier", 4.0)
			champ_aoe = d("ChampProcAoE", 500.0) * G.U
			takedown_window = d("TakedownWindow", 3.0)

	func _is_main() -> bool:
		var r: int = RANK.get(item_id, 0)
		for e in owner.items:
			if e != self and e is TkImmolate and RANK.get(e.item_id, 0) > r:
				return false
		return true

	func _activate() -> void:
		if until < now():
			tick_t = 0.0
		until = now() + aura_dur

	func on_damage_dealt(info) -> void:
		super.on_damage_dealt(info)
		if info.tag != "immolate" and info.tag != "desolate" and info.target != null and info.target != owner:
			_activate()

	func on_damage_taken(info) -> void:
		super.on_damage_taken(info)
		if info.final > 0.0 or info.absorbed > 0.0:
			_activate()

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		# ticks at activation, +1s, +2s ... while more than a quarter tick of the aura is left
		if u.dead or until - now() < period * 0.25:
			return
		tick_t -= dt
		if tick_t > 0.0:
			return
		tick_t += period
		if tick_t < 0.0:
			tick_t = period
		if _is_main():
			_burn()

	func _tick_damage() -> float:
		return base + ratio * bonus_hp()

	func _burn() -> void:
		var o = owner
		var dmg := _tick_damage()
		var r := range_m * maxf(1.0, o.stats.size)
		for e in Tu.enemies_near(o.match_ref, o.team, o.global_position, r):
			if e.kind == G.Kind.MINION:
				var md := dmg * (1.0 + minion_mod)
				# "executes minions that would be killed by one more tick of damage"
				if e.hp <= md * 2.0:
					Combat.deal(o, e, e.hp + e.stats.max_hp, G.DmgType.TRUE, {"is_proc": true, "is_dot": true, "tag": "immolate", "show_number": false})
				else:
					Combat.deal(o, e, md, G.DmgType.MAGIC, {"is_proc": true, "is_dot": true, "tag": "immolate", "show_number": false})
			else:
				Combat.deal(o, e, dmg, G.DmgType.MAGIC, {"is_proc": true, "is_dot": true, "tag": "immolate", "show_number": e.kind == G.Kind.CHAMPION})

	func _desolate(pos: Vector3, amount: float, radius: float) -> void:
		var o = owner
		Vfx.ring(o.match_ref, pos, Color(1.0, 0.55, 0.2), radius, 0.35, 0.12, 0.2)
		for e in Tu.enemies_near(o.match_ref, o.team, pos, radius):
			var a := amount * ((1.0 + minion_mod) if e.kind == G.Kind.MINION else 1.0)
			Combat.deal(o, e, a, G.DmgType.MAGIC, {"is_proc": true, "is_aoe": true, "tag": "desolate", "show_number": e.kind == G.Kind.CHAMPION})

	## Desolate: killing a non-champion enemy
	func on_kill(v) -> void:
		if proc_aoe <= 0.0 or v == null or not is_instance_valid(v) or v.kind == G.Kind.CHAMPION or Tu.is_structure(v):
			return
		_desolate(v.global_position, proc_base + proc_ratio * bonus_hp(), proc_aoe)

	## Desolate: champion takedown within the window of damaging them
	func on_takedown(v) -> void:
		if champ_aoe <= 0.0 or v == null or not is_instance_valid(v):
			return
		var last: float = v.damage_log.get(owner, -100.0)
		if now() - last > takedown_window:
			return
		_desolate(v.global_position, champ_proc_base + proc_ratio * bonus_hp(), champ_aoe)


# ------------------------------------------------------------------ Thorns
class TkThorns extends TankItem:
	var base := 20.0
	var armor_ratio := 0.0
	var gw := 0.4
	var gw_dur := 3.0

	func on_attach(_u) -> void:
		base = d("BaseDamage", 10.0)
		armor_ratio = d("BonusArmorDamageRatio", 0.0)
		gw = d("GrievousAmount", 0.4)
		gw_dur = d("GrievousDuration", 3.0)

	func _best() -> bool:
		for e in owner.items:
			if e != self and e is TkThorns and e.base + e.armor_ratio * 100.0 > base + armor_ratio * 100.0:
				return false
		return true

	func on_damage_taken(info) -> void:
		super.on_damage_taken(info)
		var src = info.source
		if not info.is_attack or src == null or not is_instance_valid(src) or src.dead or Tu.is_structure(src) or info.tag == "thorns":
			return
		if src.kind == G.Kind.TURRET or not _best():
			return
		var champ: bool = src.kind == G.Kind.CHAMPION
		Combat.deal(owner, src, base + armor_ratio * owner.stats.bonus_armor, G.DmgType.MAGIC,
				{"is_proc": true, "is_reflect": true, "no_hooks": true, "tag": "thorns", "show_number": champ})
		if champ:
			K.grievous(src, gw_dur, owner, gw)


# ------------------------------------------------------------------ Warmog's Armor
class TkWarmogs extends TankItem:
	var last_champ_hit := -100.0
	var last_other_hit := -100.0
	var heal_t := 0.0
	var vit := 0.0
	var _vit_t := 0.0

	func get_stat_mods() -> Dictionary:
		var s := stats.duplicate()
		s["hp"] = s.get("hp", 0.0) + vit
		return s

	func on_damage_taken(info) -> void:
		super.on_damage_taken(info)
		if info.final <= 0.0 and info.absorbed <= 0.0:
			return
		if info.source != null and is_instance_valid(info.source) and info.source.kind == G.Kind.CHAMPION:
			last_champ_hit = now()
		else:
			last_other_hit = now()

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		_vit_t -= dt
		if _vit_t <= 0.0:
			_vit_t = 0.5
			# Warmog's Vitality: bonus Health equal to HPAmp of the Health granted by items
			var item_hp := 0.0
			for it in u.items:
				item_hp += float(it.stats.get("hp", 0.0))
			var want := d("HPAmp", 0.12) * item_hp
			if absf(want - vit) > 0.5:
				vit = want
				refresh_stats()
		if u.dead or u.hp >= u.stats.max_hp:
			heal_t = 0.0
			return
		var t := now()
		if t - last_champ_hit < d("OOCTimerChampion", 8.0) or t - last_other_hit < d("OOCTimer", 4.0):
			heal_t = 0.0
			return
		if bonus_hp() < d("HealthThreshold", 2000.0):
			return
		heal_t += dt
		var step := d("SecondsPerHeal", 0.5)
		if heal_t >= step:
			heal_t -= step
			# "restore 1.5% Health per second"
			Combat.heal(u, u, d("MaxHealthRatio", 0.015) * u.stats.max_hp * step, {"is_vamp": true, "show": false})


# ------------------------------------------------------------------ Spirit Visage
class TkVisage extends TankItem:
	func modify_heal_received(amount: float, _healer) -> float:
		return amount * (1.0 + d("HealingIncrease", 0.25))

	## Shields on you are increased too: top up the shield that was just added.
	func on_shield_received(amount: float) -> void:
		var extra := amount * d("ShieldIncrease", 0.25)
		var i: int = owner.shields.size() - 1
		while i >= 0:
			var s: Dictionary = owner.shields[i]
			if absf(float(s.max) - amount) < 0.01 or i == 0:
				s.amount += extra
				s.max += extra
				return
			i -= 1

	## health regeneration is healing as well
	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		if not u.dead and u.hp < u.stats.max_hp:
			u.hp = minf(u.stats.max_hp, u.hp + u.stats.hp_regen * d("HealingIncrease", 0.25) * dt)


# ------------------------------------------------------------------ Frozen Heart
class FrozenSlow extends Buff:
	## -X% of the victim's total Attack Speed: the "as" stat is bonus AS (scaled by its ratio), so the amount is
	## derived from the AS the unit would have without this debuff.
	var amount := 0.2
	var _own := 0.0

	func _init() -> void:
		super._init("frozen_heart_as", 0.6)
		display_name = "Winter's Caress"
		is_debuff = true
		hidden = true

	func get_stat_mods() -> Dictionary:
		return {"as": _own}

	func on_tick(u, _dt: float) -> void:
		var st: Stats = u.stats
		var ratio := maxf(float(st.base.get("attack_speed_ratio", 0.65)), 0.01)
		var bonus := Stats.growth(float(st.base.get("attack_speed_per_level", 0.0)), u.level) / 100.0 + st.m("as") - _own
		var as_free := clampf(float(st.base.get("attack_speed", 0.65)) + ratio * bonus, 0.2, st.as_cap)
		var want := -amount * as_free / ratio
		if absf(want - _own) > 0.002:
			_own = want
			st.mark_dirty()


class TkFrozenHeart extends TankItem:
	var scan_t := 0.0

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		scan_t -= dt
		if scan_t > 0.0 or u.dead:
			return
		scan_t = 0.25
		var r := d("AuraRadius", 700.0) * G.U
		for e in Tu.enemies_near(u.match_ref, u.team, u.global_position, r, true):
			var b := FrozenSlow.new()
			b.amount = -d("ASPDSlow", -0.2)
			e.add_buff(b, u)


# ------------------------------------------------------------------ Jak'Sho, The Protean
class TkJakSho extends TankItem:
	var combat_t := 0.0
	var ex_armor := 0.0
	var ex_mr := 0.0
	var _t := 0.0

	func get_stat_mods() -> Dictionary:
		var s := stats.duplicate()
		s["armor"] = s.get("armor", 0.0) + ex_armor
		s["mr"] = s.get("mr", 0.0) + ex_mr
		return s

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		if champ_combat() and not u.dead:
			combat_t += dt
		else:
			combat_t = 0.0
		_t -= dt
		if _t > 0.0:
			return
		_t = 0.25
		var a := 0.0
		var r := 0.0
		if combat_t >= d("MaxStacks", 5.0):   # one stack per second of champion combat; full effect at the last
			var k := d("BonusResistPercentage", 0.3)
			a = k * maxf(0.0, u.stats.bonus_armor - ex_armor)
			r = k * maxf(0.0, u.stats.bonus_mr - ex_mr)
		if absf(a - ex_armor) > 0.25 or absf(r - ex_mr) > 0.25 or ((a == 0.0) != (ex_armor == 0.0)):
			ex_armor = a
			ex_mr = r
			refresh_stats()


# ------------------------------------------------------------------ Dead Man's Plate
class TkDeadMans extends TankItem:
	var stacks := 0.0
	var last_pos := Vector3.INF
	var _applied := 0.0

	func get_stat_mods() -> Dictionary:
		var s := stats.duplicate()
		s["ms"] = s.get("ms", 0.0) + _applied
		return s

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		var p: Vector3 = u.global_position
		var moved := last_pos != Vector3.INF and G.flat_dist(p, last_pos) > 0.5 * dt
		last_pos = p
		var maxs := d("MaxStacks", 100.0)
		var rate := maxs / maxf(d("DurationToMaxStack", 4.0), 0.1) * dt
		stacks = clampf(stacks + (rate if moved and not u.dead else -rate), 0.0, maxs)
		var want := floorf(d("MaxMovementSpeed", 20.0) * stacks / maxs)
		if want != _applied:
			_applied = want
			refresh_stats()

	func on_attack_hit(t, info) -> void:
		if info == null or not info.is_attack or info.on_hit_mult < 0.999 or stacks < 1.0 or t == null:
			return
		var maxs := d("MaxStacks", 100.0)
		var f := stacks / maxs
		stacks = 0.0
		var dmg: float = f * (d("BonusDamagePerStack", 0.4) * maxs + d("MaxStacksADRatio", 1.0) * owner.stats.base_ad)
		proc(t, dmg, G.DmgType.PHYSICAL, "shipwrecker")
		if _applied != 0.0:
			_applied = 0.0
			refresh_stats()


# ------------------------------------------------------------------ Force of Nature
class TkForceOfNature extends TankItem:
	var stacks := 0
	var stack_cd := 0.0
	var stack_t := 0.0

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		stack_cd = maxf(0.0, stack_cd - dt)
		if stacks > 0:
			stack_t -= dt
			if stack_t <= 0.0:
				stacks = 0

	func on_damage_taken(info) -> void:
		super.on_damage_taken(info)
		var src = info.source
		if info.type != G.DmgType.MAGIC or src == null or not is_instance_valid(src) or src.kind != G.Kind.CHAMPION:
			return
		if (info.final <= 0.0 and info.absorbed <= 0.0) or stack_cd > 0.0:
			return
		stack_cd = d("StackRefreshTimer", 1.0)
		stack_t = d("BuffDuration", 7.0)
		stacks += int(d("ImmobilizeStacks", 2.0)) if (owner.cc & Buff.IMMOBILIZE) != 0 else 1
		if stacks >= int(d("MaxStacks", 8.0)):
			stacks = 0
			K.buff(owner, "steadfast", d("BuffDuration", 7.0), {"mr": d("BonusMagicResist", 70.0), "ms%": d("MoveSpeed", 0.06)},
					owner, {"name": "Steadfast"})


# ------------------------------------------------------------------ Heartsteel
class TkHeartsteel extends TankItem:
	var cds := {}        ## target instance id -> time of the last proc
	var near := {}       ## enemy champion instance id -> seconds nearby
	var gained := 0.0
	var scan_t := 0.0
	var _size := 0.0

	func get_stat_mods() -> Dictionary:
		var s := stats.duplicate()
		s["hp"] = s.get("hp", 0.0) + gained
		# Goliath: +3% size per 1000 max Health, up to 30%
		s["size"] = _size
		return s

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		scan_t += dt
		if scan_t < 0.25:
			return
		var el := scan_t
		scan_t = 0.0
		if u.dead:
			near.clear()
			return
		var seen := {}
		var r := d("DistanceToChampion", 700.0) * G.U
		for e in Tu.enemies_near(u.match_ref, u.team, u.global_position, r, true):
			var k: int = e.get_instance_id()
			seen[k] = true
			near[k] = near.get(k, 0.0) + el
		for k in near.keys():
			if not seen.has(k):
				near.erase(k)
		var want := minf(d("SizeCap", 0.3), d("SizeAmount", 0.03) * u.stats.max_hp / d("HealthSizeThreshold", 1000.0))
		if absf(want - _size) > 0.004:
			_size = want
			refresh_stats()

	func on_attack_hit(t, info) -> void:
		if t == null or t.kind != G.Kind.CHAMPION or info == null or not info.is_attack or info.on_hit_mult < 0.999:
			return
		var k: int = t.get_instance_id()
		var tm := now()
		if near.get(k, 0.0) < 0.5 or tm - cds.get(k, -100.0) < d("PerTargetCooldown", 30.0):
			return
		cds[k] = tm
		var dmg: float = d("BaseDamage", 70.0) + d("HPRatio", 0.06) * owner.stats.max_hp
		proc(t, dmg, G.DmgType.PHYSICAL, "heartsteel")
		var mult := 1.0
		for e in owner.effects.duplicate():
			if e.has_method("heartsteel_mult"):
				mult *= e.heartsteel_mult()
		gained += dmg * d("DamageToMaxHealthRatio", 0.05) * mult
		refresh_stats()
		Vfx.burst(owner.match_ref, t.global_position + Vector3(0, 1, 0), Color(0.9, 0.2, 0.3), 1.4, {"sparks": 20})


# ------------------------------------------------------------------ Iceborn Gauntlet
class TkIceborn extends TankItem:
	var ready := false
	var ready_until := -1.0
	var cd_until := -1.0

	func _other_spellblade() -> bool:
		for e in owner.items:
			if e != self and e is ItemFx.Spellblade and e.item_id != 3057:
				return true
		return false

	func on_ability_cast(ab, _t) -> void:
		if ab != null and ab.is_summoner:
			return
		if now() >= cd_until and not _other_spellblade():
			ready = true
			ready_until = now() + 10.0

	func on_attack_hit(t, info) -> void:
		if not ready or info == null or not info.is_attack or info.on_hit_mult < 0.999 or t == null:
			return
		if now() > ready_until:
			ready = false
			return
		ready = false
		cd_until = now() + d("SpellbladeCooldown", 1.5)
		var o = owner
		proc(t, o.stats.base_ad * d("SpellbladeMultiplier", 1.5), G.DmgType.PHYSICAL, "spellblade")
		_field(t.global_position)

	func _field(pos: Vector3) -> void:
		var o = owner
		var m = o.match_ref
		var r := d("AoERadius", 300.0) * G.U
		var amt := d("SlowAmount", 0.25) if is_melee() else d("RangedSlowAmount", 0.125)
		var dur := d("SlowFieldDuration", 2.0)
		Vfx.ground_circle(m, pos, r, Color(0.6, 0.85, 1.0, 0.7), dur, 0.2)
		var acc := [0.0]
		var team: int = o.team
		m.add_ticker(dur, func(dt: float) -> bool:
			acc[0] -= dt
			if acc[0] > 0.0:
				return true
			acc[0] = 0.25
			if not is_instance_valid(o):
				return false
			for e in Tu.enemies_near(m, team, pos, r):
				K.slow(e, amt, 0.5, o, false, "iceborn_field")
			return true)


# ------------------------------------------------------------------ Unending Despair
class TkUnending extends TankItem:
	var cd := 0.0

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		cd = maxf(0.0, cd - dt)
		if cd > 0.0 or u.dead or not champ_combat():
			return
		var targets := Tu.enemies_near(u.match_ref, u.team, u.global_position, d("DrainRange", 650.0) * G.U, true)
		if targets.is_empty():
			return
		cd = d("Cooldown", 4.0)
		var dmg := d("BonusHealthDrainPercentage", 0.03) * bonus_hp()
		var total := 0.0
		for e in targets:
			var info := Combat.deal(u, e, dmg, G.DmgType.MAGIC, {"is_proc": true, "tag": "anguish", "show_number": true})
			if not info.cancelled:
				total += info.mitigated
		if total > 0.0:
			Combat.heal(u, u, total * d("HealMultiplier", 2.5))
			Vfx.rising(u, Color(0.6, 0.15, 0.35), 0.8, 18)


# ------------------------------------------------------------------ Protoplasm Harness
class TkProtoplasm extends TankItem:
	var cd := 0.0

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		cd = maxf(0.0, cd - dt)

	func on_damage_taken(info) -> void:
		super.on_damage_taken(info)
		var o = owner
		if cd > 0.0 or o.dead or o.hp > o.stats.max_hp * d("LowHealthThreshold", 0.3):
			return
		cd = d("Cooldown", 60.0)
		var dur := d("Duration", 5.0)
		var gain := lvl_lerp(100.0, 300.0)
		var bonus_ms := maxf(0.0, o.stats.move_speed - float(o.stats.base.get("base_ms", 330.0)))
		var total: float = lvl_lerp(100.0, 400.0) + 1.75 * o.stats.bonus_armor + 1.75 * bonus_ms
		var b := K.buff(o, "lifeline", dur, {"hp": gain, "size": d("SizeIncrease", 0.15), "ms%": d("MSAmount", 0.1),
				"tenacity": d("TenacityAmount", 0.25)}, o, {"name": "Lifeline"})
		if b != null:
			b.tick_interval = 0.5
			var per: float = total / (dur / 0.5)
			b.on_interval = func(_b): Combat.heal(o, o, per, {"is_vamp": true, "show": false})
		# the extra max Health is granted before the hit lands (so it can save the unit)
		o.recompute_stats()
		Vfx.rising(o, Color(0.5, 0.9, 0.4), 1.0, 24)


# ------------------------------------------------------------------ Warden's Mail
class TkWardensMail extends TankItem:
	func on_pre_damage_taken(info) -> void:
		var src = info.source
		if not info.is_attack or src == null or not is_instance_valid(src) or src.kind != G.Kind.CHAMPION:
			return
		var phys: bool = info.type == G.DmgType.PHYSICAL
		var rm := Combat.resist_multiplier(owner.stats.armor if phys else owner.stats.mr, src, phys)
		if rm <= 0.0:
			return
		# "Rock Solid": -BlockBase post-mitigation damage, at most WardenDamageMax of the hit
		var post: float = (info.amount + info.flat_bonus) * info.mult * rm
		var cut := minf(d("BlockBase", 15.0), d("WardenDamageMax", 0.2) * post)
		info.flat_bonus -= cut / rm


# ------------------------------------------------------------------ Gluttonous Greaves
class TkGluttonous extends TankItem:
	var stacks := 0

	func get_stat_mods() -> Dictionary:
		var s := stats.duplicate()
		s["omnivamp"] = s.get("omnivamp", 0.0) + stacks * d("OmnivampOnTakedown", 0.006)
		return s

	func on_takedown(v) -> void:
		if v != null and is_instance_valid(v) and v.kind == G.Kind.CHAMPION and stacks < int(d("MaxStacks", 10.0)):
			stacks += 1
			refresh_stats()


# ------------------------------------------------------------------ Winter's Approach (Awe + Manaflow)
class TkWintersApproach extends TankItem:
	const AWE_RATIO := 0.15    ## Health per bonus Mana (not part of the item data; League wiki, patch 14.10+)
	var charges := 0
	var charge_t := 0.0
	var gained := 0.0
	var bonus_mana := 0.0
	var _t := 0.0
	var guard := {}            ## ability instance id -> time of its last charge use

	func get_stat_mods() -> Dictionary:
		var s := stats.duplicate()
		s["mana"] = s.get("mana", 0.0) + gained
		s["hp"] = s.get("hp", 0.0) + AWE_RATIO * bonus_mana
		return s

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		if charges < int(d("ManaChargeMaxAmmo", 4.0)):
			charge_t += dt
			if charge_t >= d("ManaChargeAmmoCD", 8.0):
				charge_t = 0.0
				charges += 1
		_t -= dt
		if _t <= 0.0:
			_t = 0.25
			var bm: float = u.stats.m("mana")
			if absf(bm - bonus_mana) > 0.5 and bm > 0.0:
				bonus_mana = bm
				refresh_stats()

	func _consume(t) -> void:
		if charges <= 0 or t == null or not owner.stats.uses_mana:
			return
		if gained >= d("MaxMana", 360.0):
			return
		charges -= 1
		var per := d("ManaPerCharge", 4.5) * (2.0 if t.kind == G.Kind.CHAMPION else 1.0)
		gained = minf(d("MaxMana", 360.0), gained + per)
		refresh_stats()
		if gained >= d("MaxMana", 360.0) - 0.001:       # [numbers] "Transforms into Fimbulwinter at 360 max Mana"
			ItemFxUpgrades.upgrade(self, 3121)

	func on_attack_hit(t, info) -> void:
		if info != null and info.is_attack and info.on_hit_mult >= 0.999:
			_consume(t)

	func on_damage_dealt(info) -> void:
		super.on_damage_dealt(info)
		if not info.is_spell or info.is_dot or info.ability == null or info.target == null or info.target == owner:
			return
		var k: int = info.ability.get_instance_id()
		if now() - guard.get(k, -100.0) < 1.0:
			return
		guard[k] = now()
		_consume(info.target)
