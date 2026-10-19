extends RefCounted
## Item behaviour: support family (see ItemFxExtra). Numbers come from League's own item data (ItemDB.data / meta.effect_amount,
## ARAM overrides already applied). Ids: Guardian's Horn / Orb, Shurelya's, Zeke's, Locket, Ardent Censer, Moonstone, Echoes of
## Helia, Whispering Circlet, Staff of Flowing Water, Bandlepipes, Redemption, Knight's Vow, Mikael's, Sword of Blossoming Dawn,
## Imperial Mandate, Verdant Barrier.

const SUPPORT_BUSY := "fx_support_busy"


static func register(m: Dictionary) -> void:
	m[2051] = func(): return GuardianHorn.new()
	m[3112] = func(): return GuardianOrb.new()
	m[2065] = func(): return Shurelya.new()
	m[3050] = func(): return Zekes.new()
	m[3190] = func(): return Locket.new()
	m[3504] = func(): return ArdentCenser.new()
	m[6617] = func(): return Moonstone.new()
	m[6620] = func(): return EchoesOfHelia.new()
	m[2526] = func(): return WhisperingCirclet.new()
	m[6616] = func(): return StaffOfFlowingWater.new()
	m[2524] = func(): return Bandlepipes.new()
	m[3107] = func(): return Redemption.new()
	m[3109] = func(): return KnightsVow.new()
	m[3222] = func(): return Mikaels.new()
	m[124011] = func(): return BlossomingDawn.new()
	m[4005] = func(): return ImperialMandate.new()
	m[4632] = func(): return VerdantBarrier.new()


## ====================================================================================================== bases
class Fx extends Item:
	var _ai_target = null

	func on_attach(_u) -> void:
		if active_cd <= 0.0 and bool(ItemDB.meta(item_id).get("clickable", false)):
			active_cd = ItemDB.cooldown_of(item_id)

	func dv(key: String, def: float = 0.0) -> float:
		return float(ItemDB.data(item_id, key, def))

	func amt(i: int, def: float = 0.0) -> float:
		var a: Array = ItemDB.meta(item_id).get("effect_amount", [])
		return float(a[i]) if i < a.size() else def

	func busy() -> bool:
		return owner != null and owner.has_meta(SUPPORT_BUSY)

	func set_busy(v: bool) -> void:
		if v:
			owner.set_meta(SUPPORT_BUSY, true)
		else:
			owner.remove_meta(SUPPORT_BUSY)

	func is_ally_champ(t) -> bool:
		return t != null and is_instance_valid(t) and t != owner and not t.dead and t.kind == G.Kind.CHAMPION and t.team == owner.team

	## Allied champions (including the owner) within r meters of center.
	func allies_near(center: Vector3, r: float, include_self: bool = true) -> Array:
		var out: Array = owner.match_ref.allies_in_radius(owner.team, center, r)
		if include_self and not owner.dead and not out.has(owner):
			out.append(owner)
		return out

	func now() -> float:
		return owner.match_ref.time if owner != null and owner.match_ref != null else 0.0


## Items reacting to "healing or shielding an ally". Chained / item-made heals set the busy flag so they do not re-trigger.
class HealTrigger extends Fx:
	var _last_amt := 0.0

	func modify_heal_shield_dealt(amount: float, _target, _is_shield: bool) -> float:
		_last_amt = amount
		return amount

	func on_heal_dealt(target, healed: float) -> void:
		if busy() or not is_ally_champ(target):
			return
		_on_support(target, _last_amt if _last_amt > 0.0 else healed, false)

	func on_shield_dealt(target, amount: float) -> void:
		if busy() or not is_ally_champ(target):
			return
		_on_support(target, amount, true)

	func _on_support(_t, _amount: float, _is_shield: bool) -> void:
		pass


## ====================================================================================================== guardian items
class GuardianHorn extends Fx:
	## Undaunted: blocks 15 damage (after resistances) from champion attacks and spells, 25% as effective vs damage over time.
	func on_pre_damage_taken(info) -> void:
		var src = info.source
		if src == null or not is_instance_valid(src) or src.kind != G.Kind.CHAMPION or src.team == owner.team:
			return
		if not (info.is_attack or info.is_spell):
			return
		var blk := amt(0, 15.0) * (amt(1, 0.25) if info.is_dot else 1.0)
		var raw: float = (info.amount + info.flat_bonus) * info.mult
		if raw <= 0.0 or info.mult <= 0.0:
			return
		var rm := 1.0
		if info.type == G.DmgType.PHYSICAL:
			rm = Combat.resist_multiplier(owner.stats.armor, src, true)
		elif info.type == G.DmgType.MAGIC:
			rm = Combat.resist_multiplier(owner.stats.mr, src, false)
		var post_k: float = rm * (1.0 + src.stats.dmg_amp) * (1.0 - owner.stats.dmg_reduction)
		if post_k <= 0.0:
			return
		var cut := minf(blk, raw * post_k)
		info.flat_bonus -= cut / (post_k * info.mult)


class GuardianOrb extends Fx:
	## Recovery: 10 mana per 5 s (stat); champions without mana restore 15 health per 5 s instead.
	func on_attach(u) -> void:
		super.on_attach(u)
		if not owner.stats.uses_mana:
			stats.erase("mana_regen")
			stats["hp_regen"] = float(stats.get("hp_regen", 0.0)) + amt(0, 3.0)
			refresh_stats()


## ====================================================================================================== actives
class Shurelya extends Fx:
	## Inspiring Speech: nearby allies gain Move Speed.
	func use_active(_p: Vector3, _h) -> bool:
		var o = owner
		for a in allies_near(o.global_position, dv("ItemRange", 1000.0) * G.U):
			K.haste(a, dv("ActiveMoveSpeed", 0.3), dv("BuffDuration", 4.0), o, false, "shurelya_ms")
		Vfx.ring(o.match_ref, o.global_position, Color(0.55, 0.85, 1.0), dv("ItemRange", 1000.0) * G.U, 0.5, 0.15, 0.08)
		return true

	func ai_should_activate(ctx) -> bool:
		if ctx.enemies.is_empty():
			return false
		if ctx.mode == "retreat":
			return ctx.in_danger() or not ctx.allies.is_empty()
		if ctx.mode == "fight" and ctx.focus != null and is_instance_valid(ctx.focus):
			# engage / chase: the target is not yet in reach, or an ally is being chased
			return G.flat_dist(owner.global_position, ctx.focus.global_position) > owner.attack_range_m() + 1.0
		return false


class Locket extends Fx:
	## Devotion: shield decaying over 2.5 s for nearby allies. Repeated shields within 20 s are diminished.
	func use_active(_p: Vector3, _h) -> bool:
		var o = owner
		var m = o.match_ref
		var base := K.level_breakpoints(o.level, 290.0, 0.0, [[9, 7.0]])
		var dur := dv("ShieldDuration", 2.5)
		var dim_t := dv("DiminishedTimer", 20.0)
		var dim_m := dv("DiminishedEffectMulitplier", 0.25)
		for a in allies_near(o.global_position, dv("ShieldRange", 850.0) * G.U):
			var amount := base
			var last: float = a.get_meta("fx_locket_t", -1000.0)
			if m.time - last < dim_t:
				amount *= dim_m
			a.set_meta("fx_locket_t", m.time)
			Combat.shield(o, a, amount, dur, {"decay": true, "id": "locket"})
			Vfx.shield_bubble(a, Color(1.0, 0.85, 0.45), dur, 1.1)
		return true

	func ai_should_activate(ctx) -> bool:
		var n: int = ctx.count_enemies_near(owner.global_position, 9.0)
		if n == 0 or ctx.mode == "lane":
			return false
		var hurt: bool = ctx.lowest_ally(8.0, 0.75) != null
		return n >= 2 or hurt or not ctx.allies.is_empty() and ctx.mode == "fight"


class Mikaels extends Fx:
	## Purify: cleanse an ally champion and heal them.
	const RANGE := 6.5

	func _pick(pos: Vector3, hovered):
		var o = owner
		if _ai_target != null and is_instance_valid(_ai_target) and not _ai_target.dead:
			var t = _ai_target
			_ai_target = null
			return t
		if hovered != null and is_instance_valid(hovered) and hovered.kind == G.Kind.CHAMPION and hovered.team == o.team and not hovered.dead \
				and G.flat_dist(o.global_position, hovered.global_position) <= RANGE + hovered.radius:
			return hovered
		var best = null
		var bd := 2.0
		for a in allies_near(o.global_position, RANGE):
			var d: float = G.flat_dist(a.global_position, pos)
			if d < bd:
				bd = d
				best = a
		return best if best != null else o

	func use_active(pos: Vector3, hovered) -> bool:
		var t = _pick(pos, hovered)
		if t == null or t.dead:
			return false
		t.cleanse()
		Combat.heal(owner, t, lvl_lerp(dv("HealAmountMin", 100.0), dv("HealAmountMax", 250.0)))
		Vfx.rising(t, Color(1.0, 0.95, 0.7), 1.0, 24)
		return true

	func ai_should_activate(ctx) -> bool:
		var best = null
		var score := 0.0
		for a in ctx.allies + [owner]:
			if a.dead or G.flat_dist(owner.global_position, a.global_position) > RANGE:
				continue
			var s := 0.0
			if (a.cc & Buff.HARD_CC) != 0 and (a.cc & (Buff.CC.AIRBORNE | Buff.CC.SUPPRESS)) == 0 and not ctx.enemies.is_empty():
				s = 2.0 - a.hp_ratio()
			elif a.hp_ratio() < 0.35 and not ctx.enemies.is_empty():
				s = 1.0 - a.hp_ratio()
			if s > score:
				score = s
				best = a
		_ai_target = best
		return best != null


class Redemption extends Fx:
	## Intervention: after 2.5 s heal allied units and deal true damage to enemy champions in the target area.
	var _ai_pos := Vector3.INF

	func use_active(p: Vector3, _h) -> bool:
		var o = owner
		var m = o.match_ref
		var pos: Vector3 = p
		if _ai_pos != Vector3.INF:
			pos = _ai_pos
			_ai_pos = Vector3.INF
		if G.flat_dist(pos, o.global_position) > dv("CastRange", 5500.0) * G.U:
			pos = o.global_position
		var r := dv("AOESize", 550.0) * G.U
		var lvl: int = o.level
		Vfx.ground_circle(m, pos, r, Color(1.0, 0.95, 0.6, 0.8), 2.5, 0.2)
		var item := self
		m.after(2.5, func():
			if not is_instance_valid(o):
				return
			Vfx.beam(m, pos + Vector3(0, 14, 0), pos, Color(1.0, 0.95, 0.6), 3.0, 0.6)
			var base: float = item.lvl_lerp(item.dv("HealMin", 150.0), item.dv("HealMax", 350.0)) if is_instance_valid(item.owner) else 150.0
			var dim_t: float = item.dv("DiminishedTimer", 8.0)
			var dim_m: float = item.dv("DiminishedEffect", 0.5)
			for a in m.allies_in_radius(o.team, pos, r, false):
				var last: float = a.get_meta("fx_redemption_t", -1000.0)
				var amount := base * (dim_m if m.time - last < dim_t else 1.0)
				a.set_meta("fx_redemption_t", m.time)
				Combat.heal(o, a, amount)
			for e in m.enemies_in_radius(o.team, pos, r, true):
				Combat.deal(o, e, e.stats.max_hp * item.dv("DamageToChampions", 0.1), G.DmgType.TRUE, {"is_proc": true, "tag": "redemption"}))
		return true

	func ai_should_activate(ctx) -> bool:
		var o = owner
		var best := Vector3.INF
		var best_s := 0.0
		for a in ctx.allies + [o]:
			if a.dead or G.flat_dist(o.global_position, a.global_position) > 30.0:
				continue
			var hurt := 0.0
			var n := 0
			for b in ctx.allies + [o]:
				if not b.dead and G.flat_dist(a.global_position, b.global_position) < 5.0:
					hurt += 1.0 - b.hp_ratio()
					n += 1
			# only worth it when someone is clearly hurt and enemies are around
			if hurt > 0.55 and not ctx.enemies.is_empty() and hurt > best_s:
				best_s = hurt
				best = a.global_position
		if best == Vector3.INF:
			return false
		_ai_pos = best
		return true


class KnightsVow extends Fx:
	## Pledge designates a Worthy ally; while within tether range you take part of their damage and heal from their damage.
	var worthy = null
	var mark: WorthyMark = null

	func on_detach(_u) -> void:
		_clear()

	func on_death(_k) -> void:
		pass

	func _clear() -> void:
		if mark != null and worthy != null and is_instance_valid(worthy):
			worthy.remove_effect(mark)
		mark = null
		worthy = null

	func _pick(pos: Vector3, hovered):
		var o = owner
		if _ai_target != null and is_instance_valid(_ai_target) and not _ai_target.dead:
			var t = _ai_target
			_ai_target = null
			return t
		var rng := dv("TetherRange", 1250.0) * G.U
		if hovered != null and is_instance_valid(hovered) and hovered != o and hovered.kind == G.Kind.CHAMPION and hovered.team == o.team and not hovered.dead \
				and G.flat_dist(o.global_position, hovered.global_position) <= rng:
			return hovered
		var best = null
		var bd := 3.0
		for a in allies_near(o.global_position, rng, false):
			var d: float = G.flat_dist(a.global_position, pos)
			if d < bd:
				bd = d
				best = a
		return best

	func use_active(pos: Vector3, hovered) -> bool:
		var t = _pick(pos, hovered)
		if t == null or t == owner or t.dead:
			return false
		_clear()
		worthy = t
		mark = WorthyMark.new(self)
		t.add_effect(mark)
		Vfx.rising(t, Color(0.9, 0.8, 0.4), 1.0, 20)
		return true

	func ai_should_activate(ctx) -> bool:
		if worthy != null and is_instance_valid(worthy) and not worthy.dead:
			return false
		var best = null
		var bp := -1.0
		for a in ctx.allies:
			if a.dead or G.flat_dist(owner.global_position, a.global_position) > dv("TetherRange", 1250.0) * G.U:
				continue
			var p: float = BotBrain.power_of(a)
			if p > bp:
				bp = p
				best = a
		_ai_target = best
		return best != null


## Effect on the Worthy ally.
class WorthyMark extends Effect:
	var vow = null
	var _cd := 0.0

	func _init(p_vow = null) -> void:
		id = "knights_vow_worthy"
		hidden = true
		vow = p_vow

	func _active() -> bool:
		if vow == null or vow.removed or vow.owner == null or not is_instance_valid(vow.owner) or vow.owner.dead:
			return false
		return G.flat_dist(vow.owner.global_position, owner.global_position) <= vow.dv("TetherRange", 1250.0) * G.U

	func on_tick(_u, dt: float) -> void:
		# the item left the owner's inventory (sold) or the vow's holder died for good: forget the mark
		if vow == null or vow.removed or vow.owner == null or not is_instance_valid(vow.owner):
			owner.remove_effect(self)

	func on_pre_damage_taken(info) -> void:
		if info.amount <= 0.0 or info.is_proc and info.tag == "knights_vow" or not _active():
			return
		var k = vow.owner
		if k.hp_ratio() < vow.dv("DamageRedirectionThreshold", 0.3):
			return
		var frac: float = vow.dv("DamageRedirection", 0.14)
		var raw: float = (info.amount + info.flat_bonus) * info.mult
		var rm := 1.0
		if info.type == G.DmgType.PHYSICAL:
			rm = Combat.resist_multiplier(owner.stats.armor, info.source, true)
		elif info.type == G.DmgType.MAGIC:
			rm = Combat.resist_multiplier(owner.stats.mr, info.source, false)
		info.mult *= 1.0 - frac
		# the redirected share is what the ally would have taken (already mitigated), dealt to the holder as true damage
		var share: float = raw * rm * frac
		if share > 0.0:
			Combat.deal(info.source, k, share, G.DmgType.TRUE, {"is_proc": true, "no_hooks": true, "no_vamp": true, "tag": "knights_vow", "show_number": false})

	func on_damage_dealt(info) -> void:
		var t = info.target
		if t == null or not is_instance_valid(t) or t.kind != G.Kind.CHAMPION or t.team == owner.team or not _active():
			return
		var k = vow.owner
		Combat.heal(k, k, (info.final + info.absorbed) * vow.dv("AllyHealingConversion", 0.12), {"is_vamp": true, "show": false})


## ====================================================================================================== zeke's
class Zekes extends Fx:
	## Cryocombustion (ultimate haste) and Frostfire Tempest: casting the ultimate readies a storm that triggers near an enemy champion.
	var ready_left := 0.0
	var cd := 0.0
	var _scan := 0.0

	func on_attach(u) -> void:
		super.on_attach(u)
		stats["ult_ah"] = dv("UltimateHaste", 15.0)
		refresh_stats()

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		cd = maxf(0.0, cd - dt)
		if ready_left <= 0.0:
			return
		ready_left -= dt
		_scan -= dt
		if _scan > 0.0 or u.dead:
			return
		_scan = 0.1
		if cd > 0.0:
			return
		if not u.match_ref.enemies_in_radius(u.team, u.global_position, dv("StormRadius", 350.0) * G.U, true).is_empty():
			_summon()

	func on_ability_cast(ab, _t) -> void:
		if ab.is_ult and not ab.is_summoner and cd <= 0.0:
			ready_left = dv("ReadyDuration", 5.0)

	func _summon() -> void:
		var o = owner
		ready_left = 0.0
		cd = dv("Cooldown", 45.0)
		var dur := dv("Duration", 5.0)
		var per := dv("DamagePerSecond", 30.0) * 0.5
		var slow := dv("SlowAmount", 0.3)
		var r := dv("StormRadius", 350.0) * G.U
		var item := self
		var b := Buff.new("zeke_storm", dur)
		b.display_name = "Frostfire Tempest"
		b.tick_interval = 0.5
		b.on_interval = func(_bb):
			if not is_instance_valid(o) or o.dead:
				return
			for e in o.match_ref.enemies_in_radius(o.team, o.global_position, r):
				Combat.deal(o, e, per, G.DmgType.MAGIC, {"is_proc": true, "is_dot": true, "is_aoe": true, "tag": "zeke", "show_number": e.kind == G.Kind.CHAMPION})
				K.slow(e, slow, 0.75, o, false, "zeke_slow")
		o.add_buff(b, o)
		Vfx.ring(o.match_ref, o.global_position, Color(0.6, 0.85, 1.0), r, 0.6, 0.2, 0.1)


## ====================================================================================================== enchanter passives
class ArdentCenser extends HealTrigger:
	## Sanctify: healing or shielding an ally gives both of you attack speed and magic on-hit damage.
	func _on_support(t, _a, _s) -> void:
		_apply(owner)
		_apply(t)

	func _apply(u) -> void:
		var b := SanctifyBuff.new("ardent_sanctify", dv("Duration", 6.0))
		b.display_name = "Sanctify"
		b.stats = {"as": dv("AttackSpeedMin", 0.25)}
		b.dmg = dv("OnHitMin", 20.0)
		u.add_buff(b, owner)


class SanctifyBuff extends Buff:
	var dmg := 20.0

	func on_attack_hit(t, info) -> void:
		var mult: float = info.on_hit_mult if info != null else 1.0
		if t == null or not is_instance_valid(t) or t.dead:
			return
		Combat.deal(owner, t, dmg * mult, G.DmgType.MAGIC, {"is_proc": true, "tag": "ardent"})


class StaffOfFlowingWater extends HealTrigger:
	## Rapids: healing or shielding an ally gives both of you Ability Power and Ability Haste.
	func _on_support(t, _a, _s) -> void:
		for u in [owner, t]:
			K.buff(u, "flowing_rapids", dv("BuffDuration", 6.0), {"ap": dv("APMod", 40.0), "ah": dv("AHMod", 15.0)}, owner, {"name": "Rapids"})


class Moonstone extends HealTrigger:
	## Starlit Grace: healing / shielding an ally chains a fraction to another ally (not you).
	func _on_support(t, amount: float, is_shield: bool) -> void:
		var best = null
		var br := 2.0
		for a in owner.match_ref.allies_in_radius(owner.team, t.global_position, dv("EffectRange", 800.0) * G.U):
			if a == owner or a == t or a.dead or a.kind != G.Kind.CHAMPION:
				continue
			var r: float = a.hp_ratio()
			if r < br:
				br = r
				best = a
		if best == null:
			return
		var dur := 3.0
		var decay := false
		if is_shield:
			for s in t.shields:
				if s.get("source") == owner:
					dur = maxf(float(s.get("remaining", dur)), 0.5)
					decay = bool(s.get("decay", false))
		# Combat applies heal and shield power again: pass the "original amount" fraction without it
		var out: float = amount * (dv("ChainShield", 0.35) if is_shield else dv("ChainHeal", 0.3)) / (1.0 + owner.stats.heal_power)
		set_busy(true)
		if is_shield:
			Combat.shield(owner, best, out, dur, {"decay": decay, "id": "moonstone"})
		else:
			Combat.heal(owner, best, out)
		set_busy(false)


class EchoesOfHelia extends HealTrigger:
	## Soul Siphon: store a share of damage dealt to champions, release it as healing when you heal or shield an ally.
	var charges := 0.0

	func max_charges() -> float:
		return K.level_breakpoints(owner.level, 80.0, 10.0)

	func on_damage_dealt(info) -> void:
		var t = info.target
		if t == null or not is_instance_valid(t) or t.kind != G.Kind.CHAMPION or t.team == owner.team:
			return
		var pre: float = (info.amount + info.flat_bonus) * info.mult
		if pre > 0.0:
			charges = minf(max_charges(), charges + pre * dv("DamageStorageRate", 0.3))

	func _on_support(t, amount: float, _s) -> void:
		if amount < dv("MinimumHealToTrigger", 10.0) or charges < 1.0:
			return
		var h := charges * dv("ChargeToHealConversion", 1.0)
		charges = 0.0
		set_busy(true)
		Combat.heal(owner, t, h, {"is_vamp": true})
		set_busy(false)


class WhisperingCirclet extends HealTrigger:
	## Harmony: heal and shield power from bonus mana. Manaflow: charges (1 per 8 s, max 5) grant max mana on landing abilities / on-hit.
	var ammo := 5.0
	var gained := 0.0
	var base_mana := 300.0
	var _last_mp := -1.0
	var _cast_key := ""
	var _cast_t := -100.0
	var _used_key := ""

	func on_attach(u) -> void:
		super.on_attach(u)
		base_mana = float(stats.get("mana", 300.0))
		ammo = dv("ManaChargeMaxAmmo", 5.0)

	func _bonus_mana() -> float:
		var b = owner.stats.base
		return maxf(0.0, owner.stats.max_mana - (float(b.mana_base) + Stats.growth(float(b.mana_per_level), owner.level)))

	func get_stat_mods() -> Dictionary:
		var d := stats.duplicate()
		d["mana"] = base_mana + gained
		if owner != null:
			d["heal_power"] = float(d.get("heal_power", 0.0)) + 0.00005 * _bonus_mana()
		return d

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		var mx := dv("ManaChargeMaxAmmo", 5.0)
		if ammo < mx:
			ammo = minf(mx, ammo + dt / dv("ManaChargeAmmoCD", 8.0))
		if absf(u.stats.max_mana - _last_mp) > 0.5:
			_last_mp = u.stats.max_mana
			refresh_stats()

	func _grant(champ: bool) -> void:
		var cap := dv("MaxMana", 360.0)       # [numbers] 360 BONUS mana from Manaflow (wiki), not 360 max mana in total
		if ammo < 1.0 or gained >= cap:
			return
		ammo -= 1.0
		var g := minf(dv("ManaPerCharge", 4.0) * (2.0 if champ else 1.0), cap - gained)
		gained += g
		owner.mana += g
		refresh_stats()
		if gained >= cap - 0.001:             # "Transforms into Diadem of Songs at 360 max Mana"
			ItemFxUpgrades.upgrade(self, 2530)

	func on_ability_cast(ab, _t) -> void:
		if ab.is_summoner:
			return
		_cast_key = "%d:%d" % [ab.slot, ab.cast_count]
		_cast_t = now()

	func _cast_free() -> bool:
		if _cast_key == "" or now() - _cast_t > 3.0 or _cast_key == _used_key:
			return false
		_used_key = _cast_key
		return true

	func on_damage_dealt(info) -> void:
		var t = info.target
		if t == null or not is_instance_valid(t) or t.team == owner.team or t.kind in [G.Kind.TURRET, G.Kind.INHIBITOR, G.Kind.NEXUS]:
			return
		if info.is_spell and info.ability != null and not info.is_dot and not info.ability.is_summoner:
			if info.ability.slot <= 3 and ("%d:%d" % [info.ability.slot, info.ability.cast_count]) != _used_key:
				_used_key = "%d:%d" % [info.ability.slot, info.ability.cast_count]
				_grant(t.kind == G.Kind.CHAMPION)

	func on_attack_hit(t, info) -> void:
		if info != null and info.is_attack and t != null and is_instance_valid(t) and t.team != owner.team and not t.kind in [G.Kind.TURRET, G.Kind.INHIBITOR, G.Kind.NEXUS]:
			_grant(t.kind == G.Kind.CHAMPION)

	## Abilities that heal / shield allies also count (once per cast).
	func _on_support(_t, _a, _s) -> void:
		if _cast_free():
			_grant(false)


## ====================================================================================================== sword of blossoming dawn
class BlossomingDawn extends Fx:
	## Effervescence: attack speed from heal and shield power. Peppermint: on-hit heal for the lowest health ally champion nearby.
	var _last_hp := -1.0

	func get_stat_mods() -> Dictionary:
		var d := stats.duplicate()
		if owner != null:
			d["as"] = float(d.get("as", 0.0)) + maxf(0.0, _last_hp) * dv("ASPerHS", 1.2)
		return d

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		if absf(u.stats.heal_power - _last_hp) > 0.0005:
			_last_hp = u.stats.heal_power
			refresh_stats()

	func on_attack_hit(_t, info) -> void:
		if info == null or not info.is_attack:
			return
		var o = owner
		var best = o
		for a in o.match_ref.allies_in_radius(o.team, o.global_position, 8.0):
			if not a.dead and a.hp_ratio() < best.hp_ratio():
				best = a
		var amount: float = lvl_lerp(dv("BaseHealAmountTOOLTIPMIN", 15.0), dv("BaseHealAmountTOOLTIPMAX", 45.0)) \
				+ dv("HealbADRatio", 0.1) * o.stats.bonus_ad + dv("HealAPRatio", 0.07) * o.stats.ap
		Combat.heal(o, best, amount * info.on_hit_mult)


## ====================================================================================================== crowd control items
class Bandlepipes extends Fx:
	## Fanfare: slowing / immobilizing an enemy champion gives you Move Speed and nearby allies Attack Speed.
	var left := 0.0
	var _acc := 0.0
	var _ms_on := false

	func on_cc_applied(target, buff) -> void:
		if target == null or not is_instance_valid(target) or target.kind != G.Kind.CHAMPION or target.team == owner.team:
			return
		if buff.slow_amount > 0.0 or (buff.cc & Buff.IMMOBILIZE) != 0:
			left = dv("Duration", 8.0) * (1.0 if is_melee() else 0.5)
			_acc = 0.0

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		if left <= 0.0:
			if _ms_on:
				_ms_on = false
				stats.erase("ms")
				refresh_stats()
			return
		left -= dt
		if u.dead:
			left = 0.0
			return
		if not _ms_on:
			_ms_on = true
			stats["ms"] = dv("MoveSpeed", 20.0)
			refresh_stats()
		_acc -= dt
		if _acc > 0.0:
			return
		_acc = 0.5
		var dur := dv("ASDuration", 1.0)
		for a in allies_near(u.global_position, dv("AuraRange", 900.0) * G.U):
			var v := dv("MeleeAuraAttackSpeed", 0.3)
			if float(a.stats.base.get("attack_range", 550.0)) >= 300.0:
				v *= dv("RangedAttackSpeedMultiplier", 0.667)
			K.buff(a, "bandle_fanfare", dur, {"as": v}, u, {"name": "Fanfare"})


class ImperialMandate extends Fx:
	## Control: bonus Ability Haste on abilities that immobilize (learned the first time an ability immobilizes a champion).
	## Command: immobilizing an enemy champion marks it Vulnerable to damage from your team.
	var _immob := {}
	var _last_slot := -1
	var _last_t := -100.0

	func on_ability_cast(ab, _t) -> void:
		if not ab.is_summoner and ab.slot <= 3:
			_last_slot = ab.slot
			_last_t = now()

	func _factor(ab) -> float:
		var ah: float = owner.stats.ability_haste + (owner.stats.ult_haste if ab.is_ult else owner.stats.basic_haste)
		return (100.0 + ah) / (100.0 + ah + dv("ImmobilizingAbilityAH", 20.0))

	func modify_cooldown(ab, cd: float) -> float:
		if not ab.is_summoner and _immob.has(ab.slot):
			return cd * _factor(ab)
		return cd

	func on_cc_applied(target, buff) -> void:
		if target == null or not is_instance_valid(target) or target.kind != G.Kind.CHAMPION or target.team == owner.team:
			return
		if (buff.cc & Buff.IMMOBILIZE) == 0:
			return
		# learn which ability immobilized (first time: shorten the cooldown that already started)
		if _last_slot >= 0 and now() - _last_t < 2.5 and not _immob.has(_last_slot):
			_immob[_last_slot] = true
			var ab = owner.abilities[_last_slot] if _last_slot < owner.abilities.size() else null
			if ab != null:
				var f := _factor(ab)
				ab.cd *= f
				ab.cd_total *= f
		var b := VulnerableBuff.new("imperial_vulnerable_%d" % owner.team, dv("DamageAmpDuration", 4.0))
		b.display_name = "Vulnerable"
		b.is_debuff = true
		b.cleansable = false
		b.team = owner.team
		b.amp = dv("DamageAmp", 0.07)
		target.add_buff(b, owner)


class VulnerableBuff extends Buff:
	var team := 0
	var amp := 0.07

	func on_pre_damage_taken(info) -> void:
		var s = info.source
		if s != null and is_instance_valid(s) and s.team == team and s != owner:
			info.mult *= 1.0 + amp


class VerdantBarrier extends Fx:
	## Annul: a spell shield that blocks the next enemy ability (its damage and crowd control), then recharges.
	var cd := 0.0
	var _blk_src = null
	var _blk_t := -100.0
	var _scan := 0.0

	func _blockable(src) -> bool:
		return src != null and is_instance_valid(src) and src.kind == G.Kind.CHAMPION and src.team != owner.team

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		var t := now()
		_scan -= dt
		if _scan > 0.0:
			return
		_scan = 0.05
		if cd > 0.0:
			cd = maxf(0.0, cd - 0.05 * (1.0 + u.stats.m("item_haste") / 100.0))
		# crowd control that arrived with / without damage: strip it while the shield is up or just blocked a cast
		var recent := _blk_src != null and t - _blk_t < 0.4
		if cd > 0.0 and not recent:
			return
		for b in u.buffs.duplicate():
			if not b.is_debuff or b.source == null or not _blockable(b.source):
				continue
			if b.cc == 0 and b.slow_amount <= 0.0:
				continue
			if b.duration - b.remaining > 0.2:
				continue
			if recent:
				if b.source == _blk_src:
					u.remove_buff(b)
			else:
				u.remove_buff(b)
				_trigger(b.source)
				recent = true

	func on_pre_damage_taken(info) -> void:
		if cd > 0.0 or not info.is_spell or not _blockable(info.source):
			return
		info.cancelled = true
		_trigger(info.source)

	func _trigger(src) -> void:
		cd = dv("SpellShieldCooldown", 60.0)
		_blk_src = src
		_blk_t = now()
		Vfx.shield_bubble(owner, Color(0.85, 0.5, 1.0), 0.5, 1.1)
		owner.match_ref.fx_text(owner, "Blocked", Color(0.85, 0.6, 1.0))
