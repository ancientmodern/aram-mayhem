extends RefCounted
## Item behaviour: mage family (see ItemFxExtra). Numbers come from ItemDB.data() (League's own item data with the ARAM
## overrides); the few values League keeps in script calculations (not in the data values) are named constants with their
## source noted next to them.
##
## Registered here (legacy ItemFx classes were wrong / outdated): Tear 3070, Archangel 3003, Manamune 3004, Oblivion Orb
## 3916, Morellonomicon 3165, Fated Ashes 2508, Blackfire Torch 2503, Hextech Alternator 3145, Lost Chapter 3802, Catalyst
## 3803, Rod of Ages 6657, Haunting Guise 3147, Liandry's 6653, Riftmaker 4633, Luden's Echo 6655, Rocketbelt 3152,
## Seeker's Armguard 2420, Shadowflame 4645, Horizon Focus 4628, Stormsurge 4646, Malignance 3118, Actualizer 2522,
## Abyssal Mask 8020, Kaenic Rookern 2504, Bloodletter's 8010, Cryptbloom 3137, Cosmic Drive 4629, Rite of Ruin 123430,
## Dawncore 6621, Hexoptics C44 2523.
## Legacy ItemFx classes kept (faithful to the data): Zhonya 3157, Nashor 3115, Rylai 3116, Banshee 3102 (Rabadon 3089 is
## handled by ItemDB.PASSIVE_STATS).


static func register(m: Dictionary) -> void:
	for id in [3070, 3003, 3004]:
		m[id] = func(): return ManaFlow.new()
	for id in [3916, 3165]:
		m[id] = func(): return GrievousOnMagic.new()
	m[2508] = func(): return BurnOnSpell.new()
	m[2503] = func(): return BurnOnSpell.new()
	m[3145] = func(): return Revved.new()
	m[3802] = func(): return Enlighten.new()
	for id in [3803, 6657]:
		m[id] = func(): return Eternity.new()
	m[3147] = func(): return CombatAmp.new()
	m[4633] = func(): return CombatAmp.new()
	m[6653] = func(): return Torment.new()
	m[6655] = func(): return Echo.new()
	m[3152] = func(): return Supersonic.new()
	m[2420] = func(): return TimeStopSingle.new()
	m[4645] = func(): return Cinderbloom.new()
	m[4628] = func(): return Hypershot.new()
	m[4646] = func(): return Stormraider.new()
	m[3118] = func(): return Hatefog.new()
	m[2522] = func(): return ManaMadeReal.new()
	m[8020] = func(): return Unmake.new()
	m[2504] = func(): return Magebane.new()
	m[8010] = func(): return VileDecay.new()
	m[3137] = func(): return LifeFromDeath.new()
	m[4629] = func(): return Spelldance.new()
	m[123430] = func(): return RiteOfRuin.new()
	m[6621] = func(): return FirstLight.new()
	m[2523] = func(): return Magnification.new()


# ===================================================================== shared base
class Base extends Item:
	var icd := 0.0                ## internal cooldown (s)
	var _cast_seen := {}          ## Ability -> cast_count already counted (one proc per cast)

	func dv(key: String, default = 0.0) -> float:
		return float(ItemDB.data(item_id, key, default))

	func now() -> float:
		return owner.match_ref.time if owner != null and owner.match_ref != null else 0.0

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		if icd > 0.0:
			icd = maxf(0.0, icd - dt)
		tick_fx(u, dt)

	func tick_fx(_u, _dt: float) -> void:
		pass

	func dealt(info) -> float:
		return float(info.final) + float(info.absorbed)

	static func is_champ(u) -> bool:
		return u != null and is_instance_valid(u) and u.kind == G.Kind.CHAMPION

	static func is_structure(u) -> bool:
		return u.kind == G.Kind.TURRET or u.kind == G.Kind.INHIBITOR or u.kind == G.Kind.NEXUS

	## True once per ability cast (multi hit abilities count once).
	func first_of_cast(ab) -> bool:
		if ab == null:
			return true
		if _cast_seen.get(ab, -1) == ab.cast_count:
			return false
		_cast_seen[ab] = ab.cast_count
		return true

	## Magic damage over time buff on `t` (re-applying refreshes the duration). per_tick(t) -> damage of one tick.
	func apply_burn(t, bid: String, dur: float, tick: float, per_tick: Callable) -> void:
		var src = owner
		var b := Buff.new(bid, dur)
		b.display_name = display_name
		b.is_debuff = true
		b.tick_interval = tick
		b.on_interval = func(_x):
			if is_instance_valid(src) and is_instance_valid(t) and not t.dead:
				var amt: float = per_tick.call(t)
				Combat.deal(src, t, amt, G.DmgType.MAGIC, {"is_dot": true, "is_proc": true, "tag": "burn", "show_number": t.kind == G.Kind.CHAMPION})
		t.add_buff(b, src)

	## Stasis (Zhonya's / Seeker's): untargetable and invulnerable, cannot act.
	func stasis(dur: float) -> void:
		var o = owner
		K.buff(o, "zhonya", dur, {}, o, {"name": "Stasis", "cc": Buff.CC.STASIS})
		o.cancel_windup()
		Vfx.shield_bubble(o, Color(1.0, 0.85, 0.35), dur, 1.2)


# ===================================================================== Tear / Archangel / Manamune
## Manaflow: landing abilities (Manamune also attacks) grants max Mana (doubled vs champions), 8s charges. Archangel's Awe
## turns bonus Mana into AP; Manamune's Awe into AD (its ratio is not in the item data: League script constant 2.5%).
## The Seraph's Embrace / Muramana upgrade is not in the ARAM item data (these items stay at the stacked state).
class ManaFlow extends Base:
	const AWE_AD_RATIO := 0.025
	var gained := 0.0
	var charges := 0
	var charge_t := 0.0
	var awe := 0.0

	func on_attach(_u) -> void:
		charges = int(dv("ManaChargeMaxAmmo", 4.0))

	func get_stat_mods() -> Dictionary:
		var s := stats.duplicate()
		s["mana"] = s.get("mana", 0.0) + gained
		if awe != 0.0:
			var k := "ap" if item_id == 3003 else "ad"
			s[k] = s.get(k, 0.0) + awe
		return s

	func tick_fx(u, dt: float) -> void:
		var max_c := int(dv("ManaChargeMaxAmmo", 4.0))
		if charges < max_c:
			charge_t -= dt
			if charge_t <= 0.0:
				charges += 1
				charge_t = dv("ManaChargeAmmoCD", 8.0) if charges < max_c else 0.0
		if item_id == 3003 or item_id == 3004:
			var ratio: float = dv("APFromMana", 0.01) if item_id == 3003 else AWE_AD_RATIO
			var want: float = u.stats.m("mana") * ratio     # bonus Mana = every flat Mana modifier
			if absf(want - awe) > 0.05:
				awe = want
				refresh_stats()

	func _land(champ: bool) -> void:
		var cap := dv("MaxMana", 360.0)
		if charges <= 0 or gained >= cap - 0.001:
			return
		charges -= 1
		if charge_t <= 0.0:
			charge_t = dv("ManaChargeAmmoCD", 8.0)
		gained = minf(cap, gained + dv("ManaPerCharge", 4.5) * (2.0 if champ else 1.0))
		refresh_stats()

	func on_damage_dealt(info) -> void:
		if not info.is_spell or info.is_attack or info.is_dot or info.is_proc:
			return
		var t = info.target
		if t == null or not is_instance_valid(t) or is_structure(t) or t.team == owner.team:
			return
		if first_of_cast(info.ability):
			_land(t.kind == G.Kind.CHAMPION)

	func on_attack_hit(t, info) -> void:
		if info == null or not info.is_attack or t == null or not is_instance_valid(t):
			return
		if item_id == 3004 and not is_structure(t):
			_land(t.kind == G.Kind.CHAMPION)
		elif item_id == 3070 and t.kind == G.Kind.MINION:     # Helping Hand
			proc(t, dv("BonusMinionDamage", 5.0) * info.on_hit_mult, G.DmgType.PHYSICAL, "tear")


# ===================================================================== Oblivion Orb / Morellonomicon
class GrievousOnMagic extends Base:
	func on_damage_dealt(info) -> void:
		if info.type != G.DmgType.MAGIC:
			return
		var t = info.target
		if not is_champ(t) or dealt(info) <= 0.0:
			return
		var dur := dv("GrievousDuration", 3.0)
		var b: Buff = t.find_buff("grievous")
		if b != null and b.remaining > dur - 0.25 and b.stats.get("_gw", 0.0) >= dv("GrievousAmount", 0.4) - 0.001:
			return
		K.grievous(t, dur, owner, dv("GrievousAmount", 0.4))


# ===================================================================== Fated Ashes / Blackfire Torch
## Inflame / Baleful Blaze: damaging abilities burn the target. Blackfire: +AP% per champion currently burning.
class BurnOnSpell extends Base:
	var burning := 0
	var _scan := 0.0
	var bonus_ap := 0.0

	func get_stat_mods() -> Dictionary:
		if bonus_ap == 0.0:
			return stats
		var s := stats.duplicate()
		s["ap%"] = s.get("ap%", 0.0) + bonus_ap
		return s

	func _bid() -> String:
		return "burn_%d_%d" % [item_id, owner.get_instance_id()]

	func on_damage_dealt(info) -> void:
		if not info.is_spell or info.is_dot or info.is_proc:
			return
		var t = info.target
		if t == null or not is_instance_valid(t) or t.dead or is_structure(t) or t.team == owner.team:
			return
		var tick := dv("TickFrequency", 0.5)
		var self_ref := self
		apply_burn(t, _bid(), dv("BurnDuration", 3.0), tick, func(_t):
			var dps: float = self_ref.dv("BurnFlatDamagePerSecond", 0.0) + self_ref.dv("APRatio", 0.0) * self_ref.owner.stats.ap
			return dps * tick)

	func tick_fx(u, dt: float) -> void:
		if item_id != 2503:
			return
		_scan -= dt
		if _scan > 0.0:
			return
		_scan = 0.2
		var n := 0
		var bid := _bid()
		for c in u.match_ref.champions:
			if c.team != u.team and not c.dead and c.has_buff(bid):
				n += 1
		var want := n * dv("APPerStack", 0.04)
		if absf(want - bonus_ap) > 0.0001:
			bonus_ap = want
			refresh_stats()


# ===================================================================== Hextech Alternator
class Revved extends Base:
	const DAMAGE := 65.0      ## item calculation DamageAmount (a plain number in League's item script, not a data value)

	func on_damage_dealt(info) -> void:
		if icd > 0.0 or info.is_proc:
			return
		var t = info.target
		if not is_champ(t) or dealt(info) <= 0.0:
			return
		icd = dv("Cooldown", 40.0)
		proc(t, DAMAGE, G.DmgType.MAGIC, "alternator")


# ===================================================================== Lost Chapter
class Enlighten extends Base:
	func on_level_up(_lvl: int) -> void:
		var o = owner
		if o == null or not o.stats.uses_mana:
			return
		var dur := dv("RestorationDuration", 3.0)
		var ticks := maxi(1, int(round(dur / 0.5)))
		var per: float = dv("ManaRestorePercent", 0.2) * o.stats.max_mana / float(ticks)
		var b := Buff.new("enlighten", dur)
		b.hidden = true
		b.stack_mode = Buff.Stack.INDEPENDENT
		b.tick_interval = 0.5
		b.on_interval = func(_x): o.mana = minf(o.stats.max_mana, o.mana + per)
		o.add_buff(b, o)


# ===================================================================== Catalyst of Aeons / Rod of Ages
## Eternity (both) and Timeless (Rod of Ages: stats every 40s, a free level at max stacks).
class Eternity extends Base:
	var stacks := 0
	var timer := 0.0

	func get_stat_mods() -> Dictionary:
		if stacks == 0:
			return stats
		var s := stats.duplicate()
		s["hp"] = s.get("hp", 0.0) + dv("HealthPerStack", 10.0) * stacks
		s["mana"] = s.get("mana", 0.0) + dv("ManaPerStack", 30.0) * stacks
		s["ap"] = s.get("ap", 0.0) + dv("APPerStack", 3.0) * stacks
		return s

	func tick_fx(u, dt: float) -> void:
		if item_id != 6657:
			return
		var max_s := int(dv("MaxStacks", 10.0))
		if stacks >= max_s:
			return
		timer += dt
		if timer >= dv("SecondsPerStack", 40.0):
			timer = 0.0
			stacks += 1
			refresh_stats()
			if stacks >= max_s and u.level < Rules.MAX_LEVEL:
				u.level_up()

	func on_damage_taken(info) -> void:
		var src = info.source
		if not is_champ(src) or not owner.stats.uses_mana or info.mitigated <= 0.0:
			return
		owner.mana = minf(owner.stats.max_mana, owner.mana + dv("EternityManaRestore", 0.1) * info.mitigated)

	func on_ability_cast(ab, _t) -> void:
		if icd > 0.0 or ab == null or ab.is_summoner or not owner.stats.uses_mana:
			return
		var spent: float = ab.cost()
		if spent <= 0.0:
			return
		icd = dv("EternityCDPerCast", 1.0)
		Combat.heal(owner, owner, minf(dv("EternityMaxHealPerCast", 20.0), dv("EternityHealthRestore", 0.25) * spent))


# ===================================================================== Haunting Guise / Riftmaker / Liandry's amplification
## Madness / Void Corruption / Suffering: +x% damage to champions per second in combat with enemy champions.
## Riftmaker also: Void Infusion (AP from bonus Health) and Omnivamp at maximum strength.
class CombatAmp extends Base:
	var last_combat := -100.0
	var secs := 0.0
	var amp := 0.0
	var maxed := false
	var infusion := 0.0

	func _per() -> float:
		return dv("DamageIncreasePerSecond", dv("EternityDamageIncreasePerSecond", 0.02))

	func _max() -> float:
		return dv("DamageIncreaseMax", dv("EternityDamageIncreaseMax", 0.06))

	func get_stat_mods() -> Dictionary:
		if item_id != 4633 or (infusion == 0.0 and not maxed):
			return stats
		var s := stats.duplicate()
		s["ap"] = s.get("ap", 0.0) + infusion
		if maxed:
			s["omnivamp"] = s.get("omnivamp", 0.0) + (dv("VampAmountMelee", 0.1) if is_melee() else dv("VampAmountRanged", 0.06))
		return s

	func on_damage_dealt(info) -> void:
		if is_champ(info.target) and info.target.team != owner.team and dealt(info) > 0.0:
			last_combat = now()

	func on_damage_taken(info) -> void:
		if is_champ(info.source) and info.source.team != owner.team and dealt(info) > 0.0:
			last_combat = now()

	func on_pre_damage_dealt(info) -> void:
		if amp > 0.0 and is_champ(info.target):
			info.mult *= 1.0 + amp

	func tick_fx(u, dt: float) -> void:
		if now() - last_combat <= dv("BuffCounterDuration", 3.0):
			secs += dt
		else:
			secs = 0.0
		var cap := _max()
		amp = minf(cap, floorf(secs) * _per())
		if item_id == 4633:
			var m := amp >= cap - 0.0001
			var inf: float = dv("HealthToAPConversionPercent", 0.02) * ItemFx.bonus_hp(u)
			if m != maxed or absf(inf - infusion) > 0.5:
				maxed = m
				infusion = inf
				refresh_stats()


# ===================================================================== Liandry's Torment
## Torment: damaging abilities burn for % max Health; Suffering (the combat amplification) is inherited.
class Torment extends CombatAmp:
	func on_damage_dealt(info) -> void:
		super.on_damage_dealt(info)
		if not info.is_spell or info.is_dot or info.is_proc:
			return
		var t = info.target
		if t == null or not is_instance_valid(t) or t.dead or is_structure(t) or t.team == owner.team:
			return
		var tick := dv("TickFrequency", 0.5)
		var self_ref := self
		apply_burn(t, "burn_%d_%d" % [item_id, owner.get_instance_id()], dv("BurnDuration", 3.0), tick, func(tt):
			var dps: float = self_ref.dv("BurnPercentHealthDamage", 0.018) * tt.stats.max_hp
			if tt.kind != G.Kind.CHAMPION:
				dps = minf(dps, self_ref.dv("MonsterDamageCap", 40.0))
			return dps * tick)


# ===================================================================== Luden's Echo
class Echo extends Base:
	func on_damage_dealt(info) -> void:
		if icd > 0.0 or not info.is_spell or info.is_dot or info.is_proc:
			return
		var t = info.target
		if t == null or not is_instance_valid(t) or is_structure(t) or t.team == owner.team:
			return
		icd = dv("Cooldown", 12.0)
		var o = owner
		var m = o.match_ref
		var origin: Vector3 = t.global_position
		var targets: Array = m.enemies_in_radius(o.team, origin, dv("MissileRange", 650.0) * G.U)
		targets.erase(t)
		targets.sort_custom(func(a, b):
			var ca := 0 if a.kind == G.Kind.CHAMPION else 1
			var cb := 0 if b.kind == G.Kind.CHAMPION else 1
			if ca != cb:
				return ca < cb
			return G.flat_dist(a.global_position, origin) < G.flat_dist(b.global_position, origin))
		if not t.dead:
			targets.push_front(t)
		if targets.is_empty():
			return
		var base: float = dv("BaseDamage", 75.0) + dv("APRatio", 0.05) * o.stats.ap
		var repeat := dv("RepeatDamageReduction", 0.2)
		var self_ref := self
		var from: Vector3 = o.global_position + Vector3(0, 1.5, 0)
		for i in int(dv("MaxCharges", 6.0)):
			var tgt = targets[i] if i < targets.size() else targets[0]
			var amount: float = base if i < targets.size() else base * repeat
			var mi := Missile.new()
			mi.setup_homing(o, from, tgt, 14.0 + i)
			mi.visual = Vfx.orb(Color(0.45, 0.6, 1.0), 0.28, false)
			mi.on_hit = func(_m, u): self_ref.proc(u, amount, G.DmgType.MAGIC, "luden")
			m.add_missile(mi, from)


# ===================================================================== Hextech Rocketbelt
class Supersonic extends Base:
	const DASH_M := 2.75                                    ## dash 275 units (3152Active castRange)
	const BOLT_ANGLES := [0.0, 0.12, -0.12, 0.24, -0.24, 0.36, -0.36]    ## 7 bolts, 60 degree fan (targeters of 3152Active)
	const BOLT_SPEED := 16.0
	const BOLT_RANGE_M := 8.0

	func use_active(p: Vector3, _h) -> bool:
		var o = owner
		var dir := G.flat_dir(o.global_position, p)
		var dmg: float = dv("BaseDamage", 135.0) + dv("APRatio", 0.15) * o.stats.ap
		var self_ref := self
		var fire := func(_u):
			if not is_instance_valid(o) or o.dead:
				return
			var from: Vector3 = o.global_position + Vector3(0, 1.0, 0) + dir * 2.5
			var hit := {}
			for a in BOLT_ANGLES:
				var mi := Missile.new()
				mi.setup_linear(o, from, dir.rotated(Vector3.UP, a), BOLT_SPEED, BOLT_RANGE_M, 0.3)
				mi.pierce = true
				mi.visual = Vfx.orb(Color(0.4, 0.7, 1.0), 0.3, false)
				mi.on_hit = func(_m, u):
					if not hit.has(u):
						hit[u] = true
						self_ref.proc(u, dmg, G.DmgType.MAGIC, "rocketbelt")
				o.match_ref.add_missile(mi, from)
		o.start_dash(o.global_position + dir * DASH_M, {"speed": 18.0, "on_arrive": fire})
		return true

	func ai_should_activate(ctx) -> bool:
		return ctx.mode == "fight" and ctx.focus != null and is_instance_valid(ctx.focus) \
				and G.flat_dist(owner.global_position, ctx.focus.global_position) < 6.0


# ===================================================================== Seeker's Armguard
## Single use: stasis, then the item breaks into Shattered Armguard.
class TimeStopSingle extends Base:
	func use_active(_p: Vector3, _h) -> bool:
		stasis(dv("Duration", 2.5))
		var o = owner
		var idx: int = o.items.find(self)
		var me := self
		o.match_ref.after(0.0, func():
			if not is_instance_valid(o) or not (me in o.items) or not ItemDB.has(2421):
				return
			o.remove_item(me)
			var sh := ItemDB.create(2421)
			if sh != null:
				o.add_item(sh)
				o.items.erase(sh)
				o.items.insert(clampi(idx, 0, o.items.size()), sh)
				o.items_changed.emit())
		return true

	func ai_should_activate(ctx) -> bool:
		return owner.hp_ratio() < 0.2 and ctx.in_danger()


# ===================================================================== Shadowflame
## Cinderbloom: magic and true damage (damage over time too) deals +20% to enemies below 40% Health.
class Cinderbloom extends Base:
	func on_pre_damage_dealt(info) -> void:
		var t = info.target
		if t == null or not is_instance_valid(t) or info.type == G.DmgType.PHYSICAL or is_structure(t):
			return
		if t.hp_ratio() < dv("HealthThreshold", 0.4):
			info.mult *= 1.0 + (dv("DamageOverTimeAmp", 0.2) if info.is_dot else dv("SpellItemDamageAmp", 0.2))


# ===================================================================== Horizon Focus
## Hypershot: ability damage to champions from far away marks them (+10% damage from you); Focus marks the others nearby.
## (Revealing them through fog of war needs a vision hook on Unit: not available, the damage bonus is applied.)
class Hypershot extends Base:
	func _bid() -> String:
		return "hypershot_%d" % owner.get_instance_id()

	func _mark(t, dur: float) -> void:
		var b := Buff.new(_bid(), dur)
		b.display_name = "Hypershot"
		b.is_debuff = true
		t.add_buff(b, owner)

	func on_pre_damage_dealt(info) -> void:
		var t = info.target
		if is_champ(t) and t.has_buff(_bid()):
			info.mult *= 1.0 + dv("DamageAmp", 0.1)

	func on_damage_dealt(info) -> void:
		if not info.is_spell or info.is_proc:
			return
		var t = info.target
		if not is_champ(t) or t.team == owner.team:
			return
		if G.flat_dist(owner.global_position, t.global_position) / G.U < dv("SnipeRange", 600.0):
			return
		_mark(t, dv("BuffDuration", 6.0))
		if icd <= 0.0:
			icd = dv("Cooldown", 30.0)
			for c in owner.match_ref.champions:
				if c.team != owner.team and c != t and not c.dead \
						and G.flat_dist(c.global_position, t.global_position) <= dv("VisionRadius", 1400.0) * G.U:
					_mark(c, dv("SecondaryBuffDuration", 3.0))


# ===================================================================== Stormsurge
class Stormraider extends Base:
	const SQUALL_RADIUS := 450.0    ## units: nova of the Squall when the target died first (4646_AoE_Warning)
	var hist := {}                   ## champion -> [[time, damage], ...]
	var _prune := 0.0

	func tick_fx(_u, dt: float) -> void:
		_prune -= dt
		if _prune > 0.0 or hist.is_empty():
			return
		_prune = 3.0
		var fresh := {}
		for t in hist.keys():
			if is_instance_valid(t) and not t.dead:
				fresh[t] = hist[t]
		hist = fresh

	func on_damage_dealt(info) -> void:
		var t = info.target
		if icd > 0.0 or not is_champ(t) or t.team == owner.team:
			return
		var amt := dealt(info)
		if amt <= 0.0:
			return
		var n := now()
		var window := dv("WindowDuration", 2.5)
		var log: Array = hist.get(t, [])
		log.append([n, amt])
		var keep := []
		var total := 0.0
		for e in log:
			if n - e[0] <= window:
				keep.append(e)
				total += e[1]
		hist[t] = keep
		if total >= dv("DamageThreshold", 0.25) * t.stats.max_hp:
			hist.erase(t)
			_squall(t)

	func _squall(t) -> void:
		icd = dv("Cooldown", 30.0)
		var o = owner
		var m = o.match_ref
		var self_ref := self
		m.after(dv("DelayDuration", 2.0), func():
			if not is_instance_valid(o) or not is_instance_valid(t):
				return
			var dmg: float = self_ref.dv("BaseDamage", 125.0) + self_ref.dv("APRatio", 0.1) * o.stats.ap
			if not t.dead:
				self_ref.proc(t, dmg, G.DmgType.MAGIC, "stormsurge")
				Vfx.hit_spark(m, t.global_position + Vector3(0, 1.1, 0), Color(0.6, 0.7, 1.0), 1.0)
			else:
				for e in m.enemies_in_radius(o.team, t.global_position, SQUALL_RADIUS * G.U):
					self_ref.proc(e, dmg, G.DmgType.MAGIC, "stormsurge"))


# ===================================================================== Malignance
## Scorn (ultimate haste) and Hatefog: ultimate damage to a champion burns the ground under them.
class Hatefog extends Base:
	const TICK := 0.25            ## 8e8f7a34: the per tick calculation is 25% of the per second value
	const SHRED := 10.0           ## MagicResistanceShred (script calculation)
	var _last_ab = null
	var _last_n := -1

	func on_attach(_u) -> void:
		stats["ult_ah"] = dv("UltimateHaste", 20.0)
		refresh_stats()

	func on_damage_dealt(info) -> void:
		var ab = info.ability
		if ab == null or not ab.is_ult or info.is_proc or info.is_attack:
			return
		var t = info.target
		if not is_champ(t) or t.team == owner.team:
			return
		if ab == _last_ab and ab.cast_count == _last_n:
			return
		_last_ab = ab
		_last_n = ab.cast_count
		_zone(t.global_position)

	func _zone(pos: Vector3) -> void:
		var o = owner
		var m = o.match_ref
		var dur := dv("GroundDuration", 3.0)
		var rad := dv("AOESize", 250.0) * G.U
		var self_ref := self
		var acc := [0.0]
		Vfx.ground_circle(m, pos, rad, Color(0.75, 0.3, 0.95, 0.7), dur, 0.2)
		m.add_ticker(dur, func(dt: float) -> bool:
			if not is_instance_valid(o):
				return false
			acc[0] += dt
			while acc[0] >= TICK:
				acc[0] -= TICK
				var dmg: float = (self_ref.dv("BaseDamage", 40.0) + self_ref.dv("APRatio", 0.028) * o.stats.ap) * TICK
				for e in m.enemies_in_radius(o.team, pos, rad):
					Combat.deal(o, e, dmg, G.DmgType.MAGIC, {"is_dot": true, "is_proc": true, "tag": "malignance", "show_number": e.kind == G.Kind.CHAMPION})
					K.buff(e, "hatefog_shred", 0.5, {"mr": -SHRED}, o, {"name": "Hatefog", "debuff": true, "hidden": true})
			return true)


# ===================================================================== Actualizer
## Mana Made Real: 8s Empowered (ability costs +100%, +x% ability damage / shields / heals, basic ability cooldowns tick faster).
class ManaMadeReal extends Base:
	var left := 0.0

	func _amp() -> float:
		# 15% + 0.5% of max Mana per 100... (ManaCalc: (15 + 0.005 * max Mana) / 100)
		return 0.01 * (15.0 + 0.005 * owner.stats.max_mana)

	func use_active(_p: Vector3, _h) -> bool:
		left = dv("Duration", 8.0)
		Vfx.rising(owner, Color(0.45, 0.6, 1.0), 1.0, 30)
		return true

	func tick_fx(u, dt: float) -> void:
		if left <= 0.0:
			return
		left = maxf(0.0, left - dt)
		var k := dv("CooldownTick", 0.3) * dt
		for i in 3:
			var ab = u.abilities[i]
			if ab != null and ab.cd > 0.0:
				ab.cd = maxf(0.0, ab.cd - k)

	func on_pre_damage_dealt(info) -> void:
		if left > 0.0 and info.is_spell:
			info.mult *= 1.0 + _amp()

	func modify_heal_shield_dealt(amount: float, _t, _is_shield: bool) -> float:
		return amount * (1.0 + _amp()) if left > 0.0 else amount

	func on_ability_cast(ab, _t) -> void:
		if left > 0.0 and ab != null and not ab.is_summoner and owner.stats.uses_mana:
			owner.mana = maxf(0.0, owner.mana - ab.cost() * dv("ManaCostIncrease", 1.0))

	func ai_should_activate(ctx) -> bool:
		return ctx.mode == "fight" and ctx.focus != null and is_instance_valid(ctx.focus) \
				and G.flat_dist(owner.global_position, ctx.focus.global_position) < 9.0 and owner.mana > owner.stats.max_mana * 0.4


# ===================================================================== Abyssal Mask
## Unmake: enemy champions within range take more magic damage from every source.
class Unmake extends Base:
	var _scan := 0.0

	class Debuff extends Buff:
		var amp := 0.12

		func on_pre_damage_taken(info) -> void:
			if info.type == G.DmgType.MAGIC:
				info.mult *= 1.0 + amp

	func tick_fx(u, dt: float) -> void:
		_scan -= dt
		if _scan > 0.0:
			return
		_scan = 0.25
		for e in u.match_ref.enemies_in_radius(u.team, u.global_position, dv("Radius", 700.0) * G.U, true):
			var b := Debuff.new("unmake", 0.5)
			b.amp = dv("DamageAmp", 0.12)
			b.display_name = "Unmake"
			b.is_debuff = true
			b.hidden = true
			e.add_buff(b, u)


# ===================================================================== Kaenic Rookern
class Magebane extends Base:
	var quiet := 0.0

	func _shield_up() -> bool:
		for s in owner.shields:
			if s.id == "magebane":
				return true
		return false

	func _drop() -> void:
		owner.shields = owner.shields.filter(func(s): return s.id != "magebane")

	func on_damage_taken(info) -> void:
		if info.type == G.DmgType.MAGIC and (info.final > 0.0 or info.absorbed > 0.0):
			quiet = 0.0

	func tick_fx(u, dt: float) -> void:
		quiet += dt
		if quiet >= dv("OutOfCombatDuration", 15.0) and not _shield_up():
			u.add_shield(dv("ShieldAmount", 0.15) * u.stats.max_hp, 99999.0, u, G.DmgType.MAGIC, false, "magebane")

	func on_death(_k) -> void:
		quiet = 0.0
		_drop()

	func on_respawn() -> void:
		quiet = 0.0

	func on_detach(_u) -> void:
		_drop()


# ===================================================================== Bloodletter's Curse
class VileDecay extends Base:
	func on_damage_dealt(info) -> void:
		if icd > 0.0 or info.type != G.DmgType.MAGIC or info.is_attack or info.is_proc:
			return
		var t = info.target
		if not is_champ(t) or t.team == owner.team or dealt(info) <= 0.0:
			return
		icd = dv("InternalCD", 0.3)
		K.buff(t, "vile_decay_%d" % owner.get_instance_id(), dv("DebuffDuration", 6.0), {}, owner, {"name": "Vile Decay",
				"debuff": true, "max_stacks": int(dv("MaxStacks", 4.0)), "stack_mode": Buff.Stack.ADD_STACK,
				"per_stack": {"mr%": -dv("ShredPerStack", 0.075)}})


# ===================================================================== Cryptbloom
## Life from Death: a champion you damaged within 3s dies -> healing nova.
class LifeFromDeath extends Base:
	const NOVA_RADIUS := 1175.0    ## 3137_Heal_Missile castRangeDisplayOverride (the nova range League displays)

	func on_takedown(victim) -> void:
		if icd > 0.0 or not is_champ(victim) or victim.team == owner.team:
			return
		var last: float = victim.damage_log.get(owner, -100.0)
		if now() - last > dv("TakedownWindow", 3.0):
			return
		icd = dv("Cooldown", 60.0)
		var amt: float = dv("BaseHeal", 100.0) + dv("HealAPRatio", 0.2) * owner.stats.ap
		Vfx.ring(owner.match_ref, victim.global_position, Color(0.5, 0.95, 0.6), NOVA_RADIUS * G.U * 0.5, 0.6)
		for a in owner.match_ref.allies_in_radius(owner.team, victim.global_position, NOVA_RADIUS * G.U):
			Combat.heal(owner, a, amt)


# ===================================================================== Cosmic Drive
## Spelldance: magic / true damage to champions stacks Move Speed for 4s.
class Spelldance extends Base:
	const MOVE_SPEED := 20.0      ## MoveSpeedAmount (script calculation; 3 stacks = 60 = the 15% the tooltip states)

	func on_damage_dealt(info) -> void:
		if info.type == G.DmgType.PHYSICAL or info.is_proc:
			return
		var t = info.target
		if not is_champ(t) or t.team == owner.team or dealt(info) <= 0.0:
			return
		if info.ability != null:
			if not first_of_cast(info.ability):
				return
		elif icd > 0.0:
			return
		else:
			icd = 0.5
		K.buff(owner, "spelldance", dv("StackDuration", 4.0), {}, owner, {"name": "Spelldance", "max_stacks": int(dv("MaxStacks", 3.0)),
				"stack_mode": Buff.Stack.ADD_STACK, "per_stack": {"ms": MOVE_SPEED}})


# ===================================================================== Rite of Ruin
class RiteOfRuin extends Base:
	var last_cast := {}

	func on_ability_cast(ab, t) -> void:
		if ab == null or ab.is_summoner:
			return
		var n := now()
		var fresh: bool = n - last_cast.get(ab.slot, -100.0) >= dv("StaleCastTime", 5.0)
		last_cast[ab.slot] = n
		if fresh:
			var per := dv("CritPerCast", 0.025)
			K.buff(owner, "rite_of_ruin", dv("Duration", 6.0), {}, owner, {"name": "Wrath and Ruin",
					"max_stacks": int(round(dv("BonusCritCap", 0.2) / per)), "stack_mode": Buff.Stack.ADD_STACK, "per_stack": {"crit": per}})
		if G.rng.randf() < owner.stats.crit_chance:
			var tgt = t.get("unit") if t is Dictionary else null
			if tgt == null or not is_instance_valid(tgt) or tgt.team != owner.team or tgt.kind != G.Kind.CHAMPION:
				tgt = owner
			Combat.shield(owner, tgt, lvl_lerp(70.0, 210.0) + 0.15 * owner.stats.ap + 0.25 * owner.stats.bonus_ad, dv("ShieldDuration", 3.0))


# ===================================================================== Dawncore
## First Light: +AP and heal/shield power per 100% base Mana regeneration.
class FirstLight extends Base:
	var ap := 0.0
	var hsp := 0.0

	func get_stat_mods() -> Dictionary:
		if ap == 0.0:
			return stats
		var s := stats.duplicate()
		s["ap"] = s.get("ap", 0.0) + ap
		s["heal_power"] = s.get("heal_power", 0.0) + hsp
		return s

	func tick_fx(u, _dt: float) -> void:
		var r: float = u.stats.m("mana_regen%")
		var want_ap := dv("APPerManaRegen", 10.0) * r
		if absf(want_ap - ap) > 0.05:
			ap = want_ap
			hsp = dv("HSPowerPerManaRegen", 0.02) * r
			refresh_stats()


# ===================================================================== Hexoptics C44
class Magnification extends Base:
	func on_pre_damage_dealt(info) -> void:
		if not info.is_attack or info.target == null or not is_instance_valid(info.target):
			return
		var d: float = G.flat_dist(owner.global_position, info.target.global_position) / G.U
		info.mult *= 1.0 + dv("MaxDamageAmp", 0.1) * clampf(d / dv("MaxRange", 500.0), 0.0, 1.0)

	func on_takedown(victim) -> void:
		if not is_champ(victim):
			return
		var last: float = victim.damage_log.get(owner, -100.0)
		if now() - last <= dv("TakedownWindow", 3.0):
			K.buff(owner, "arcane_aim", dv("Duration", 8.0), {"range": dv("ExtraRange", 100.0)}, owner, {"name": "Arcane Aim"})
