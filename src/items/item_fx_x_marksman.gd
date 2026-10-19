extends RefCounted
## Item behaviour: marksman family (see ItemFxExtra). Numbers come from ItemDB.data() (League's own item data with the
## ARAM/Kiwi overrides). Values that League keeps in tooltip calculations instead of data values (level breakpoints,
## flat damage in the resolved text) are read from the resolved tooltip text or come from the item bin calculations
## (tools/extracted/items/items_bin.json, "mItemCalculations") and are marked below.
##
## Implemented here: 1043 3144 3123 3094 3095 3046 3032 3302 3139 3140 6694 3036 3033 6699 6672 3085 3153 3124 3087
## 6676 6675 3072 6673 3091 6695.   Plain stat items (6670 3031 3086) need nothing.

const ENERGY_MAX := 100.0
const ENERGY_ATTACK := 6.0         ## Energized: stacks per basic attack (League wiki, Stormrazor)
const ENERGY_UNITS := 24.0         ## Energized: one stack per 24 units travelled


static func register(m: Dictionary) -> void:
	m[1043] = func(): return Recurve.new()
	m[3144] = func(): return Slingshot.new()
	m[3123] = func(): return GrievousItem.new()
	m[3033] = func(): return GrievousItem.new()
	m[3094] = func(): return RapidFirecannon.new()
	m[3095] = func(): return Stormrazor.new()
	m[3046] = func(): return PhantomDancer.new()
	m[3032] = func(): return YunTal.new()
	m[3302] = func(): return Terminus.new()
	m[3139] = func(): return Quicksilver.new()
	m[3140] = func(): return Quicksilver.new()
	m[6694] = func(): return Seryldas.new()
	m[3036] = func(): return Dominiks.new()
	m[6699] = func(): return Voltaic.new()
	m[6672] = func(): return KrakenSlayer.new()
	m[3085] = func(): return Hurricane.new()
	m[3153] = func(): return Botrk.new()
	m[3124] = func(): return Rageblade.new()
	m[3087] = func(): return Statikk.new()
	m[6676] = func(): return Collector.new()
	m[6675] = func(): return Navori.new()
	m[3072] = func(): return Bloodthirster.new()
	m[6673] = func(): return Shieldbow.new()
	m[3091] = func(): return WitsEnd.new()
	m[6695] = func(): return SerpentsFang.new()


# ===================================================================== base
class MkBase extends Item:
	var _cd := 0.0               ## passive cooldown (seconds left)

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		if _cd > 0.0:
			_cd = maxf(0.0, _cd - dt)

	## League data value (after ARAM / Kiwi overrides).
	func d(key: String, default: float = 0.0) -> float:
		return float(ItemDB.data(item_id, key, default))

	## First number captured by `rx` in the item's resolved tooltip text (for values that only exist in calculations).
	func txt_num(rx: String, default: float) -> float:
		var s := ""
		for p in ItemDB.meta(item_id).get("text", []):
			s += str(p)
		var r := RegEx.new()
		r.compile(rx)
		var mt := r.search(s)
		return float(mt.get_string(1)) if mt != null else default

	## On-hit effectiveness of the current on-hit application (1 = normal; 0.999 is the "applied again" marker).
	static func om(info) -> float:
		if info == null:
			return 1.0
		var x: float = info.on_hit_mult
		return 1.0 if x >= 0.999 else x

	## true for the first application of a real basic attack's on-hit effects.
	static func is_real_attack(info) -> bool:
		return info != null and info.is_attack and info.on_hit_mult >= 1.0

	static func is_structure(u) -> bool:
		return u.kind == G.Kind.TURRET or u.kind == G.Kind.INHIBITOR or u.kind == G.Kind.NEXUS

	## League "ByCharLevelBreakpoints": base + per_level for every level from `from_level` on (inclusive).
	func bp(base: float, per_level: float, from_level: int) -> float:
		return base + per_level * maxf(0.0, float(owner.level - from_level + 1))

	func now() -> float:
		return owner.match_ref.time if owner.match_ref != null else 0.0


# ===================================================================== simple on-hit / on-damage items
class Recurve extends MkBase:
	## Sting: attacks deal bonus physical damage On-Hit.
	func on_attack_hit(t, info) -> void:
				proc(t, d("OnHitDamage", 15.0) * om(info), G.DmgType.PHYSICAL, "recurve")


class WitsEnd extends MkBase:
	## Fray: attacks deal bonus magic damage On-Hit (flat value lives in the tooltip calculation).
	var _dmg := -1.0

	func on_attack_hit(t, info) -> void:
		if _dmg < 0.0:
			_dmg = txt_num("<magicDamage>(\\d+(?:\\.\\d+)?)", 45.0)
		proc(t, _dmg * om(info), G.DmgType.MAGIC, "witsend")


class Slingshot extends MkBase:
	## Bullseye: damaging a champion deals bonus magic damage (40 s cooldown, every attack reduces it by 1 s).
	var _dmg := -1.0

	func on_attack_launch(_t) -> void:
		if _cd > 0.0:
			_cd = maxf(0.0, _cd - 1.0)

	func on_damage_dealt(info) -> void:
		var t = info.target
		if _cd > 0.0 or t == null or t.kind != G.Kind.CHAMPION or info.tag == "bullseye" or t.dead:
			return
		if _dmg < 0.0:
			_dmg = txt_num("<magicDamage>(\\d+(?:\\.\\d+)?)", 40.0)
		_cd = d("Cooldown", 40.0)
		proc(t, _dmg, G.DmgType.MAGIC, "bullseye")
		Vfx.hit_spark(owner.match_ref, t.global_position + Vector3(0, 1.2, 0), Color(1.0, 0.85, 0.4), 0.6)


class GrievousItem extends MkBase:
	## Executioner's Calling / Mortal Reminder: physical damage to champions applies Grievous Wounds.
	func on_damage_dealt(info) -> void:
		var t = info.target
		if info.type != G.DmgType.PHYSICAL or t == null or t.kind != G.Kind.CHAMPION or t.dead:
			return
		var dur := d("GrievousDuration", 3.0)
		var amt := d("GrievousAmount", 0.4)
		var b: Buff = t.find_buff("grievous")
		if b != null and float(b.stats.get("_gw", 0.4)) >= amt - 0.001:
			b.remaining = maxf(b.remaining, dur)
			b.duration = maxf(b.duration, dur)
			return
		K.grievous(t, dur, owner, amt)


class Seryldas extends MkBase:
	## Bitter Cold: damaging abilities slow enemies below 50% health.
	func on_damage_dealt(info) -> void:
		var t = info.target
		if not info.is_spell or info.is_proc or t == null or t.dead or is_structure(t):
			return
		if t.hp_ratio() >= d("SlowThreshold", 0.5):
			return
		var dur := d("SlowDuration", 1.0)
		var b: Buff = t.find_buff("seryldas_slow")
		if b != null:
			b.remaining = maxf(b.remaining, dur)
			return
		K.slow(t, d("SlowAmount", 0.3), dur, owner, false, "seryldas_slow")


class Dominiks extends MkBase:
	## Giant Slayer: up to MaxBonusDamagePercent more damage against champions, scaling with their bonus health.
	func on_pre_damage_dealt(info) -> void:
		var t = info.target
		if t == null or t.kind != G.Kind.CHAMPION:
			return
		var bonus: float = t.stats.max_hp - (t.stats.base.base_hp + Stats.growth(t.stats.base.hp_per_level, t.level))
		var k := clampf(bonus / maxf(1.0, d("MaxBonusHealth", 1500.0)), 0.0, 1.0)
		info.mult *= 1.0 + d("MaxBonusDamagePercent", 0.15) * k


class Collector extends MkBase:
	## Death: damage executes champions below 5% health. Taxes: champion kills grant gold.
	func on_damage_dealt(info) -> void:
		var t = info.target
		if t == null or t.kind != G.Kind.CHAMPION or t.dead or info.tag == "collector":
			return
		if t.hp_ratio() < d("ExecuteThreshold", 0.05):
			Combat.deal(owner, t, t.hp + t.total_shield() + 10.0, G.DmgType.TRUE, {"is_proc": true, "tag": "collector", "no_hooks": true})

	func on_kill(v) -> void:
		if v.kind == G.Kind.CHAMPION:
			owner.add_gold(d("GoldAmount", 25.0), v)


class Navori extends MkBase:
	## Transcendence: attacks reduce basic ability cooldowns by a share of their remaining cooldown.
	func on_attack_hit(_t, info) -> void:
		if not is_real_attack(info):
			return
		var pct := d("CDRAmount", 0.15)
		for i in 3:
			var ab = owner.abilities[i]
			if ab != null and ab.cd > 0.0:
				ab.reduce_cooldown_pct(pct)


class PhantomDancer extends MkBase:
	## Spectral Waltz: permanently Ghosted.
	var _b: Buff = null

	func _grant() -> void:
		var b := Buff.new("phantom_dancer", 1.0)
		b.permanent = true
		b.hidden = true
		b.cleansable = false
		b.cc = Buff.CC.GHOSTED
		_b = owner.add_buff(b, owner)

	func on_attach(_u) -> void:
		_grant()

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		if (_b == null or _b.removed) and not u.dead:
			_grant()

	func on_respawn() -> void:
		owner._update_cc()   # respawn() clears the cc mask before the permanent buff is looked at again

	func on_detach(u) -> void:
		if _b != null:
			u.remove_buff(_b)
			_b = null


class Quicksilver extends MkBase:
	## Quicksilver (active): remove crowd control (not Airborne). Mercurial Scimitar also grants Move Speed.
	static func cleanse_cc(u) -> int:
		var n := 0
		for b in u.buffs.duplicate():
			if not b.is_debuff or not b.cleansable:
				continue
			if (b.cc & Buff.CC.AIRBORNE) != 0:
				continue
			if (b.cc & ~Buff.CC.AIRBORNE) != 0 or b.slow_amount > 0.0:
				u.remove_buff(b)
				n += 1
		return n

	func use_active(_p: Vector3, _h) -> bool:
		var o = owner
		cleanse_cc(o)
		if ItemDB.data(item_id, "MoveSpeed", 0.0) != 0.0:
			K.buff(o, "mercurial_ms", d("MSDuration", 2.0), {"ms%": d("MoveSpeed", 0.5)}, o, {"name": "Quicksilver"})
		Vfx.rising(o, Color(0.8, 0.9, 1.0), 0.8, 24)
		return true

	func ai_should_activate(ctx) -> bool:
		var o = owner
		var hard := Buff.HARD_CC & ~Buff.CC.AIRBORNE & ~Buff.CC.GROUNDED & ~Buff.CC.BLIND
		for b in o.buffs:
			if b.is_debuff and b.cleansable and (b.cc & Buff.CC.AIRBORNE) == 0 and (b.cc & hard) != 0 and b.remaining > 0.45:
				return ctx.mode != "lane" or ctx.in_danger()
		return false


# ===================================================================== on-hit chains
class KrakenSlayer extends MkBase:
	## Bring It Down: every third attack deals bonus physical damage, up to MaxAmpNumber x at 0 health.
	var count := 0
	var last := -100.0

	func on_attack_hit(t, info) -> void:
		if not is_real_attack(info):
			return
		if now() - last > d("BuffDuration", 4.0):
			count = 0
		last = now()
		count += 1
		if count < int(d("AttackCount", 3.0)):
			return
		count = 0
		# bin calc DamageAmount: 150 at level 1, +5 per level from level 9; ranged use RangedDamageMultiplier
		var base := bp(150.0, 5.0, 9)
		if not is_melee():
			base *= d("RangedDamageMultiplier", 1.0)
		var miss: float = 1.0 - t.hp_ratio()
		var dmg: float = base * (1.0 + (d("MaxAmpNumber", 1.75) - 1.0) * miss)
		proc(t, dmg, G.DmgType.PHYSICAL, "kraken")
		Vfx.burst(owner.match_ref, t.global_position + Vector3(0, 1.0, 0), Color(0.3, 0.8, 0.9), 0.9, {"ring": false, "sparks": 14, "light": false})


class Botrk extends MkBase:
	## Mist's Edge: current-health on-hit damage. Clawing Shadows: third attack on a champion slows (15 s cooldown).
	var hits := {}               ## champion -> [count, last attack time]

	func on_attack_hit(t, info) -> void:
		if is_structure(t):
			return
		var melee := is_melee()
		var pct := d("MeleeValue", 0.09) if melee else d("RangedValue", 0.06)
		var dmg: float = t.hp * pct * om(info)
		if t.kind != G.Kind.CHAMPION:
			dmg = minf(dmg, d("MonsterDamageCap", 100.0))
		proc(t, dmg, G.DmgType.PHYSICAL, "botrk")
		if not is_real_attack(info) or t.kind != G.Kind.CHAMPION or _cd > 0.0:
			return
		var e: Array = hits.get(t, [0, -100.0])
		if now() - e[1] > d("AttackCounterDuration", 6.0):
			e[0] = 0
		e[0] += 1
		e[1] = now()
		hits[t] = e
		if hits.size() > 10:
			for k in hits.keys():
				if not is_instance_valid(k) or now() - hits[k][1] > 10.0:
					hits.erase(k)
		if e[0] >= 3:
			hits.erase(t)
			_cd = d("Cooldown", 15.0)
			var amt := absf(d("MoveSpeedMod", -0.3)) if melee else absf(d("RangedMoveSpeedMod", -0.15))
			K.slow(t, amt, d("MoveSpeedDuration", 1.0), owner, false, "botrk_slow")


class Rageblade extends MkBase:
	## Wrath: bonus magic damage On-Hit. Seething Strike: attack speed stacks; while fully stacked every third attack
	## applies On-Hit effects twice.
	var count := 0

	func on_attack_hit(t, info) -> void:
		proc(t, d("OnHitDamage", 30.0) * om(info), G.DmgType.MAGIC, "guinsoo")
		if not is_real_attack(info):
			return
		var max_st := int(d("MaxStacks", 4.0))
		var dur := d("BuffDuration", 4.0)
		var b: Buff = owner.find_buff("guinsoo")
		var was_full := b != null and b.stacks >= max_st
		if b == null:
			K.buff(owner, "guinsoo", dur, {}, owner, {"name": "Seething Strike", "max_stacks": max_st, "stack_mode": Buff.Stack.ADD_STACK, "per_stack": {"as": d("AttackSpeedPerStack", 0.08)}})
			count = 0
		else:
			b.stacks = mini(max_st, b.stacks + 1)
			b.remaining = dur
			b.duration = dur
			owner.stats.mark_dirty()
		if was_full:
			count += 1
			if count >= 3:
				count = 0
				owner.trigger_on_hit(t, info, 0.999)


class Hurricane extends MkBase:
	## Wind's Fury: attacks fire bolts at additional enemies near the target; bolts apply On-Hit effects.
	func on_attack_hit(t, info) -> void:
		if not is_real_attack(info) or info.tag == "runaans":
			return
		var o = owner
		# bin calc ChampRange: 1 additional target for melee champions, 2 for ranged
		var max_n := 1 if is_melee() else 2
		# [numbers] bin calc BoltDamage = 60% AD (wiki V26.20: 65% -> 60% AD; bolts crit only when the main attack does);
		# the data values BoltMin/MaxPercent (40) are stale and not used by the tooltip
		var pct := 0.6
		var rng: float = o.attack_range_m() + d("ExtraRangeOnBoltCheck", 65.0) * G.U + o.radius
		var cand: Array = []
		for e in o.match_ref.enemies_in_radius(o.team, o.global_position, rng + 0.5):
			if e == t or is_structure(e):
				continue
			if G.flat_dist(o.global_position, e.global_position) > rng + e.radius:
				continue
			cand.append(e)
		cand.sort_custom(func(a, b):
			var ka := 0 if a.kind == G.Kind.CHAMPION else 1
			var kb := 0 if b.kind == G.Kind.CHAMPION else 1
			if ka != kb:
				return ka < kb
			return G.flat_dist(a.global_position, t.global_position) < G.flat_dist(b.global_position, t.global_position))
		var crit: bool = info.is_crit
		var self_ref := self
		for i in mini(max_n, cand.size()):
			var from: Vector3 = o.global_position + Vector3(0, 1.2, 0)
			var mi := Missile.new()
			mi.setup_homing(o, from, cand[i], 20.0)
			mi.visual = Vfx.orb(Color(0.8, 0.95, 0.8), 0.25, false)
			mi.on_hit = func(_m, u):
				var dmg: float = o.stats.ad * pct * (o.stats.crit_damage if crit else 1.0)
				var inf := Combat.deal(o, u, dmg, G.DmgType.PHYSICAL, {"is_proc": true, "tag": "runaans", "is_crit": crit})
				if inf != null and not inf.cancelled:
					o.trigger_on_hit(u, inf, 1.0, self_ref)
			o.match_ref.add_missile(mi, from)


# ===================================================================== Yun Tal / Terminus
class YunTal extends MkBase:
	## Practice Makes Lethal: attacks permanently grant crit chance (up to CritMax). Flurry: attack speed burst when
	## attacking a champion; attacks (crits more) reduce its cooldown.
	var crit_bonus := 0.0

	func get_stat_mods() -> Dictionary:
		var s := stats.duplicate()
		if crit_bonus > 0.0:
			s["crit"] = s.get("crit", 0.0) + crit_bonus
		return s

	func on_attack_launch(t) -> void:
		var cap := d("CritMax", 25.0) / 100.0
		if crit_bonus < cap:
			var per := d("CritPerStackMelee", 1.0) / 100.0
			if not is_melee():
				per *= d("StackRangedMultiplier", 0.5)
			crit_bonus = minf(cap, crit_bonus + per)
			refresh_stats()
		if _cd > 0.0:
			_cd = maxf(0.0, _cd - (d("CritCDR", 2.0) if owner._pending_crit else d("AACDR", 1.0)))
		if _cd <= 0.0 and t != null and t.kind == G.Kind.CHAMPION:
			_cd = d("Cooldown", 30.0)
			K.buff(owner, "yuntal_flurry", d("ASDuration", 6.0), {"as": d("ASMod", 0.3)}, owner, {"name": "Flurry"})


class Terminus extends MkBase:
	## Shadow: on-hit magic damage. Juxtaposition: attacks on champions alternate Light (armor / MR) and Dark
	## (armor / magic penetration) and stack up to three times.
	var dark := false
	var _base := -1.0
	var _c_ad := 0.1
	var _c_ap := 0.1

	func on_attack_hit(t, info) -> void:
		if _base < 0.0:
			_base = txt_num("<magicDamage>(\\d+(?:\\.\\d+)?)", 30.0)
			_c_ad = txt_num("\\+ (\\d+(?:\\.\\d+)?)% bonus AD", 10.0) / 100.0
			_c_ap = txt_num("(\\d+(?:\\.\\d+)?)% AP", 10.0) / 100.0
		var o = owner
		proc(t, (_base + _c_ad * o.stats.bonus_ad + _c_ap * o.stats.ap) * om(info), G.DmgType.MAGIC, "terminus")
		if not is_real_attack(info) or t.kind != G.Kind.CHAMPION:
			return
		if not dark:
			# bin calc ARMRPerHitScaling: 6, +1 at level 11, +1 at level 14; ARMRMaxScaling = 3x that
			var per := 6.0 + (1.0 if o.level >= 11 else 0.0) + (1.0 if o.level >= 14 else 0.0)
			K.buff(o, "terminus_light", d("BuffDuration", 5.0), {}, o, {"name": "Juxtaposition (Light)", "max_stacks": 3, "stack_mode": Buff.Stack.ADD_STACK, "per_stack": {"armor": per, "mr": per}})
		else:
			var p := d("PenPerHit", 0.1)
			var n := maxi(1, int(round(d("PenMax", 0.3) / maxf(p, 0.001))))
			K.buff(o, "terminus_dark", d("DebuffDuration", 5.0), {}, o, {"name": "Juxtaposition (Dark)", "max_stacks": n, "stack_mode": Buff.Stack.ADD_STACK, "per_stack": {"armor_pen%": p, "magic_pen%": p}})
		dark = not dark


# ===================================================================== Energized family
class EnergyState extends RefCounted:
	var energy := 0.0
	var pending := false         ## the attack in flight is Energized
	var pending_t := -100.0
	var last_pos := Vector3.INF
	var charged := false


## Shared Energized logic (Stormrazor, Statikk Shiv, Rapid Firecannon, Voltaic Cyclosword all use one charge). The first
## Energized item in the inventory drives the charge; every Energized item reacts through energized_fire().
class MkEnergized extends MkBase:
	func extra_stacks() -> float:
		return 0.0

	func energy_charged(_on: bool) -> void:
		pass

	func energized_fire(_t, _info) -> void:
		pass

	func _st() -> EnergyState:
		if owner.has_meta("mk_energy"):
			return owner.get_meta("mk_energy")
		var s := EnergyState.new()
		owner.set_meta("mk_energy", s)
		return s

	func _is_driver() -> bool:
		for e in owner.items:
			if e is MkEnergized:
				return e == self
		return false

	func _sync(s: EnergyState) -> void:
		var c := s.energy >= ENERGY_MAX
		if c != s.charged:
			s.charged = c
			for e in owner.items:
				if e is MkEnergized:
					e.energy_charged(c)

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		if not _is_driver():
			return
		var s := _st()
		var p: Vector3 = u.global_position
		if s.last_pos != Vector3.INF and not u.dead:
			var du: float = G.flat_dist(p, s.last_pos) / G.U
			if du > 0.0 and du < 1500.0:
				s.energy = minf(ENERGY_MAX, s.energy + du / ENERGY_UNITS)
		s.last_pos = p
		if s.pending and now() - s.pending_t > 2.0:
			s.pending = false
		_sync(s)

	func on_death(_k) -> void:
		var s := _st()
		s.pending = false

	func _total_extra() -> float:
		var x := 0.0
		for e in owner.items:
			if e is MkEnergized:
				x += e.extra_stacks()
		return x

	func on_attack_launch(_t) -> void:
		if not _is_driver():
			return
		var s := _st()
		if s.energy >= ENERGY_MAX:
			s.pending = true
			s.pending_t = now()
			s.energy = 0.0
		else:
			s.energy = minf(ENERGY_MAX, s.energy + ENERGY_ATTACK + _total_extra())
		_sync(s)

	func on_attack_hit(t, info) -> void:
		if not _is_driver() or info == null or info.on_hit_mult < 1.0:
			return
		var s := _st()
		if info.is_attack:
			if not s.pending:
				return
			s.pending = false
			for e in owner.items.duplicate():
				if e is MkEnergized:
					e.energized_fire(t, info)
		elif info.is_spell and not info.is_proc:
			# abilities that apply On-Hit effects build stacks as well
			s.energy = minf(ENERGY_MAX, s.energy + ENERGY_ATTACK + _total_extra())
			_sync(s)

	## Fire every Energized effect right now (used by Voltaic's Galvanize).
	func fire_all(t, info) -> void:
		var s := _st()
		s.energy = 0.0
		s.pending = false
		_sync(s)
		for e in owner.items.duplicate():
			if e is MkEnergized:
				e.energized_fire(t, info)


class Stormrazor extends MkEnergized:
	## Bolt: the Energized attack deals bonus magic damage and grants Move Speed.
	var _dmg := -1.0

	func energized_fire(t, _info) -> void:
		if _dmg < 0.0:
			_dmg = txt_num("<magicDamage>(\\d+(?:\\.\\d+)?)", 100.0)
		proc(t, _dmg, G.DmgType.MAGIC, "stormrazor")
		K.buff(owner, "stormrazor_ms", d("BuffDuration", 1.5), {"ms%": d("BuffStrength", 0.45)}, owner, {"name": "Bolt"})
		Vfx.hit_spark(owner.match_ref, t.global_position + Vector3(0, 1.1, 0), Color(1.0, 0.8, 0.45), 0.9)


class RapidFirecannon extends MkEnergized:
	## Sharpshooter: the Energized attack deals bonus magic damage and has bonus attack range.
	func energy_charged(on: bool) -> void:
		if on:
			var base: float = owner.stats.base.attack_range
			stats["range"] = minf(d("RangePercentIncrease", 0.35) * base, d("MaxRangeIncrease", 150.0))
		else:
			stats.erase("range")
		refresh_stats()

	func on_detach(_u) -> void:
		stats.erase("range")

	func energized_fire(t, _info) -> void:
		proc(t, d("BonusDamage", 40.0), G.DmgType.MAGIC, "firecannon")
		Vfx.hit_spark(owner.match_ref, t.global_position + Vector3(0, 1.1, 0), Color(1.0, 0.6, 0.3), 0.8)


class Statikk extends MkEnergized:
	## Electrospark: the Energized attack chains lightning (target count grows with level); secondary targets also get
	## On-Hit effects. Electroshock: attacks grant extra Energized stacks.
	func extra_stacks() -> float:
		return d("BonusEnergizedStacks", 9.0)

	func energized_fire(t, _info) -> void:
		var o = owner
		var m = o.match_ref
		# bin calc BounceCount: 4, +1 at levels 6 / 10 / 14 / 20
		var count := 4 + (1 if o.level >= 6 else 0) + (1 if o.level >= 10 else 0) + (1 if o.level >= 14 else 0) + (1 if o.level >= 20 else 0)
		var rng := d("BounceRange", 500.0) * G.U
		var hit := {}
		var cur = t
		var prev: Vector3 = o.global_position + Vector3(0, 1.2, 0)
		for i in count:
			if cur == null or not is_instance_valid(cur) or cur.dead:
				break
			hit[cur] = true
			Vfx.beam(m, prev, cur.global_position + Vector3(0, 1.0, 0), Color(0.6, 0.85, 1.0), 0.07, 0.2)
			var dmg := d("ChainDamage", 70.0) if cur.kind == G.Kind.CHAMPION else d("NonChampChainDamage", 90.0)
			var inf := proc(cur, dmg, G.DmgType.MAGIC, "statikk")
			if i > 0 and inf != null and not inf.cancelled:
				o.trigger_on_hit(cur, inf, 0.999, self)
			prev = cur.global_position + Vector3(0, 1.0, 0)
			var nxt = null
			var bd := rng
			for e in m.enemies_in_radius(o.team, cur.global_position, rng):
				if not hit.has(e):
					var dd: float = G.flat_dist(e.global_position, cur.global_position)
					if dd < bd:
						bd = dd
						nxt = e
			cur = nxt


class Voltaic extends MkEnergized:
	## Galvanize: ability damage to champions triggers Energized. Firmament: the Energized attack deals current-health
	## physical damage and grants Lethality.
	func on_damage_dealt(info) -> void:
		if not info.is_spell or info.is_proc or info.is_dot:
			return
		var t = info.target
		if t == null or t.kind != G.Kind.CHAMPION or t.dead:
			return
		if _st().energy >= ENERGY_MAX:
			fire_all(t, info)

	func energized_fire(t, _info) -> void:
		var melee := is_melee()
		var pct := (d("PercentCurrentHPMelee", 9.0) if melee else d("PercentCurrentHPRanged", 7.0)) / 100.0
		var dmg: float = t.hp * pct
		if t.kind != G.Kind.CHAMPION:
			dmg = minf(dmg, d("NonChampCap", 200.0))
		proc(t, dmg, G.DmgType.PHYSICAL, "voltaic")
		var leth := d("LethalityBonusModMelee", 15.0) if melee else d("LethalityBonusModRanged", 12.0)
		K.buff(owner, "voltaic_lethality", d("LethalityBonusDuration", 4.0), {"lethality": leth}, owner, {"name": "Firmament"})
		Vfx.hit_spark(owner.match_ref, t.global_position + Vector3(0, 1.1, 0), Color(0.5, 0.9, 1.0), 0.9)


# ===================================================================== shields
class Bloodthirster extends MkBase:
	## Ichorshield: excess Life Steal healing becomes a shield (cap by level, lasts until destroyed).
	var _hp_before := -1.0

	func on_pre_damage_dealt(info) -> void:
		if info.is_attack:
			_hp_before = owner.hp

	func on_damage_dealt(info) -> void:
		if not info.is_attack or _hp_before < 0.0:
			return
		var before := _hp_before
		_hp_before = -1.0
		var o = owner
		var ls: float = o.stats.lifesteal
		if ls <= 0.0 or o.dead:
			return
		var vamp: float = ls + o.stats.omnivamp
		var potential: float = info.mitigated * vamp * (1.0 - o.grievous_wounds())
		var healed := maxf(0.0, o.hp - before)
		var excess := maxf(0.0, potential - healed) * ls / vamp
		if excess < 0.5:
			return
		# bin calc OvershieldCalc: 165 at level 1, +15 per level from level 9
		var cap := bp(165.0, 15.0, 9)
		var cur := 0.0
		for s in o.shields:
			if s.id == "ichor":
				cur = s.amount
		var amt := minf(cap, cur + excess)
		if amt > 1.0:
			o.add_shield(amt, 3600.0, o, -1, false, "ichor")


class Shieldbow extends MkBase:
	## Lifeline: damage that would bring you below the health threshold first grants a shield.
	func on_pre_damage_taken(info) -> void:
		var o = owner
		if _cd > 0.0 or o.dead or info.cancelled:
			return
		var pre: float = (info.amount + info.flat_bonus) * info.mult
		if pre <= 0.0:
			return
		var src = info.source
		if src != null and is_instance_valid(src):
			pre *= 1.0 + src.stats.dmg_amp
		pre *= 1.0 - o.stats.dmg_reduction
		if info.type == G.DmgType.PHYSICAL:
			pre *= Combat.resist_multiplier(o.stats.armor, src if src != null and is_instance_valid(src) else null, true)
		elif info.type == G.DmgType.MAGIC:
			pre *= Combat.resist_multiplier(o.stats.mr, src if src != null and is_instance_valid(src) else null, false)
		if pre <= 0.0 or o.hp - pre > d("HealthThreshold", 0.3) * o.stats.max_hp:
			return
		_cd = d("Cooldown", 60.0)
		# bin calc ShieldAmount: 400 at level 1, +30 per level from level 9, x0.8 for ranged champions
		var amt := bp(400.0, 30.0, 9)
		if not is_melee():
			amt *= 0.8
		Combat.shield(o, o, amt, d("ShieldDuration", 3.0))
		Vfx.shield_bubble(o, Color(1.0, 0.8, 0.4), d("ShieldDuration", 3.0), 1.1)


class ShieldReaver extends Buff:
	## Debuff: shields gained by the holder are reduced.
	var frac := 0.5

	func on_shield_received(amount: float) -> void:
		var u = owner
		if u == null or u.shields.is_empty():
			return
		var best: Dictionary = u.shields[u.shields.size() - 1]
		for s in u.shields:
			if s.remaining >= best.remaining:
				best = s
		var cut := minf(amount * frac, best.amount)
		best.amount -= cut
		best.max = maxf(best.amount, best.max - cut)


class SerpentsFang extends MkBase:
	## Shield Reaver: damaging an enemy champion reduces the shields they gain (and shreds current shields once).
	func on_damage_dealt(info) -> void:
		var t = info.target
		if t == null or t.kind != G.Kind.CHAMPION or t.dead or t.team == owner.team:
			return
		var melee := is_melee()
		var wound := (d("ShieldWounds", 50.0) if melee else d("ShieldWoundsRange", 35.0)) / 100.0
		var shred := (d("ShieldShred", 50.0) if melee else d("ShieldShredRange", 35.0)) / 100.0
		var dur := d("DebuffDuration", 3.0)
		var b: Buff = t.find_buff("shield_reaver")
		if b != null:
			b.remaining = maxf(b.remaining, dur)
			b.duration = maxf(b.duration, dur)
			if b is ShieldReaver:
				b.frac = maxf(b.frac, wound)
			return
		for s in t.shields:
			s.amount *= 1.0 - shred
		var nb := ShieldReaver.new("shield_reaver", dur)
		nb.display_name = "Shield Reaver"
		nb.is_debuff = true
		nb.frac = wound
		t.add_buff(nb, owner)
