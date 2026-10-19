class_name Summoners
extends RefCounted
## Summoner spells available on the Howling Abyss. [numbers] classic ARAM has Exhaust (Mayhem disables it).

const ALL := ["Flash", "Mark", "Ghost", "Heal", "Barrier", "Cleanse", "Ignite", "Clarity", "Exhaust"]


static func make(name: String, c) -> Ability:
	var a: Ability
	match name:
		"Flash": a = FlashSpell.new(c)
		"Mark": a = MarkSpell.new(c)
		"Ghost": a = GhostSpell.new(c)
		"Heal": a = HealSpell.new(c)
		"Barrier": a = BarrierSpell.new(c)
		"Cleanse": a = CleanseSpell.new(c)
		"Ignite": a = IgniteSpell.new(c)
		"Clarity": a = ClaritySpell.new(c)
		"Exhaust": a = ExhaustSpell.new(c)
		_: a = FlashSpell.new(c)
	a.is_summoner = true
	a.level = 1
	a.max_level = 1
	a.id = name
	a.icon = Assets.summoner_icon(name.to_lower())
	a.anim = ""
	return a


static func give_default(c, d: String = "Flash", f: String = "Mark") -> void:
	c.summoners[0] = make(d, c)
	c.summoners[0].slot = 5
	c.summoners[0].key = "D"
	c.summoners[1] = make(f, c)
	c.summoners[1].slot = 6
	c.summoners[1].key = "F"


static func set_spell(c, slot_index: int, name: String) -> void:
	var a := make(name, c)
	a.slot = 5 + slot_index
	a.key = "D" if slot_index == 0 else "F"
	c.summoners[slot_index] = a


## Summoner VFX are League systems: Flash / Barrier / Ignite from data/vfx/shared.json, Heal / Clarity / Cleanse / Ghost from
## data/vfx/summoners.json (tools/lol/extract_summoner_vfx.py); K.attach_fx / K.spawn_fx load the sets on demand.


class FlashSpell extends Ability:
	func _init(p_owner) -> void:
		super._init(p_owner)
		display_name = "Flash"
		description = "Teleports your champion a short distance toward your cursor's location."
		cooldowns = [300.0]
		cast_range = 400.0
		target_type = Target.POINT
		indicator = Ind.NONE
		cast_time = 0.0
		face_target = true

	func cancels_windup() -> bool:
		return true

	func execute(t: Dictionary) -> void:
		var o: Vector3 = owner.global_position
		var d := minf(G.flat_dist(o, t.pos), range_m())
		var dest: Vector3 = o + G.flat_dir(o, t.pos) * d
		var m = owner.match_ref
		dest = m.nav.clamp_walkable(o, dest)
		if not m.nav.is_walkable(dest):
			dest = m.nav.nearest_walkable(dest)
		var fdir := G.flat_dir(o, t.pos)
		# League: Global_SS_Flash stays at the departure point, Global_SS_Flash_02 plays on the champion on arrival
		K.spawn_fx(m, "Global_SS_Flash", o, {"dir": fdir})
		owner.teleport(dest)
		owner.cancel_windup()
		owner.face_toward(o + fdir * 10.0, 100.0)
		K.attach_fx(owner, {"lol": "Global_SS_Flash_02", "dir": fdir}, false)
		for e in owner.effects.duplicate():
			e.on_dash(o, dest)
			e.on_summoner_cast(self)
		notify_cast(t)

	func ai_consider(ctx) -> Dictionary:
		return ctx.flash_decision(self)


class MarkSpell extends Ability:
	var marked = null
	var tag_fx = null
	var mark_time := 0.0

	func _init(p_owner) -> void:
		super._init(p_owner)
		display_name = "Mark"
		description = "Throw a snowball. On hit, deals true damage and you can recast to dash to the target."
		cooldowns = [80.0]
		cast_range = 1600.0
		target_type = Target.DIRECTION
		indicator = Ind.LINE
		ind_width = 100.0   # [numbers] SummonerSnowball mMissileWidth 50 (radius) -> 100 wide (was 120)
		cast_time = 0.0

	func is_dash() -> bool:
		return recast_window > 0.0

	func damage() -> float:
		var base: float = 10.0 + 5.0 * owner.level
		for e in owner.effects.duplicate():
			if e.has_method("snowball_damage_mult"):
				base *= e.snowball_damage_mult()
		return base

	## The mark ends early when the marked unit dies or becomes untargetable (no dash target left).
	func on_tick(_dt: float) -> void:
		if recast_window > 0.0 and (marked == null or not is_instance_valid(marked) or marked.dead or not marked.is_targetable_by(owner.team)):
			recast_window = 0.0
			on_recast_expired()

	func execute(t: Dictionary) -> void:
		var m = owner.match_ref
		if recast_window > 0.0 and (marked == null or not is_instance_valid(marked) or marked.dead):
			# recast but the target is gone: the mark is spent (it used to throw a free second snowball)
			recast_window = 0.0
			on_recast_expired()
			return
		if recast_window > 0.0 and marked != null and is_instance_valid(marked) and not marked.dead:
			recast_window = 0.0
			var tgt = marked
			marked = null
			if tag_fx != null and is_instance_valid(tag_fx):
				tag_fx.stop()
			var dash_fx := LolVfx.attach(owner, "Summoner_Snowball_Dash", {"loop": true, "dir": G.flat_dir(owner.global_position, tgt.global_position)})
			# the dash can be cut short (knockback / stun clears it without on_arrive): never leave the trail looping
			var dfx_ref := weakref(dash_fx) if dash_fx != null else null
			if dfx_ref != null:
				m.after(G.flat_dist(owner.global_position, tgt.global_position) / 25.0 + 0.3, func():
					K.kill_fx(dfx_ref.get_ref(), 0.3))
			LolVfx.spawn(m, "Summoner_Snowball_Dash_Cast", owner.global_position)
			# [numbers] wiki Mark: Dash speed 2500 (was 1800), it deals the same true damage on arrival and a successful
			# Dash cuts Mark's remaining cooldown by 25% (SummonerSnowball CDRefundPerc)
			owner.start_dash(tgt.global_position, {"speed": 25.0, "on_arrive": func(_u):
				if is_instance_valid(tgt) and not tgt.dead:
					hit(tgt, damage(), G.DmgType.TRUE, {"is_spell": false, "is_proc": true, "tag": "snowball"})
				cd *= 0.75
				for e in owner.effects.duplicate():
					if e.has_method("on_snowball_dash_arrive"):
						e.on_snowball_dash_arrive(tgt)
				if dash_fx != null and is_instance_valid(dash_fx):
					dash_fx.stop()
				LolVfx.spawn(m, "Summoner_Snowball_Dash_Arrival", owner.global_position)})
			start_cooldown()
			notify_cast(t)
			return
		var mi := Missile.new()
		var from: Vector3 = owner.global_position + Vector3(0, 1.0, 0)
		mi.setup_linear(owner, from, t.dir, 12.0, range_m(), 0.5)   # [numbers] SummonerSnowball missile speed 1200, width 50 (was 13 / 0.6)
		mi.hits_minions = true
		var ally_view: bool = G.player == null or owner.team == G.player.team
		var lv := LolVfx.make("Summoner_Snowball_Mis" if ally_view else "Summoner_Snowball_Mis_Enemy", {"loop": true})
		mi.visual = lv if lv != null else Node3D.new()
		mi.custom["keep_visual"] = true
		mi.on_hit = func(_m, u):
			hit(u, damage(), G.DmgType.TRUE, {"is_spell": false, "is_proc": true, "tag": "snowball"})
			marked = u
			recast_window = 3.0
			cd = 0.0
			LolVfx.spawn(m, "Summoner_Snowball_Explosion", u.global_position + Vector3(0, 1.0, 0))
			if tag_fx != null and is_instance_valid(tag_fx):
				tag_fx.stop()
			tag_fx = LolVfx.attach(u, "Summoner_Snowball_Tagged", {"loop": true})
			for e in owner.effects.duplicate():
				if e.has_method("on_snowball_hit"):
					e.on_snowball_hit(u)
		for e in owner.effects.duplicate():
			if e.has_method("modify_snowball"):
				e.modify_snowball(mi)
		m.add_missile(mi, from)
		for e in owner.effects.duplicate():
			e.on_summoner_cast(self)
		notify_cast(t)

	func auto_cooldown() -> bool:
		return true

	func on_recast_expired() -> void:
		marked = null
		if tag_fx != null and is_instance_valid(tag_fx):
			tag_fx.stop()
		tag_fx = null
		start_cooldown()

	func ai_consider(ctx) -> Dictionary:
		return ctx.mark_decision(self)


class GhostSpell extends Ability:
	func _init(p_owner) -> void:
		super._init(p_owner)
		display_name = "Ghost"
		description = "Gain Ghosted and 24-48% Movement Speed for 10 seconds."
		cooldowns = [240.0]
		target_type = Target.NONE
		indicator = Ind.NONE
		cast_range = 0.0
		cast_time = 0.0

	func execute(t: Dictionary) -> void:
		var b := K.FxBuff.new("ghost", 10.0)
		b.kill_fade = 0.3
		b.display_name = "Ghost"
		b.cc = Buff.CC.GHOSTED
		b.stats = {"ms%": 0.24 + 0.24 * (owner.level - 1) / 17.0}
		b.icon = icon
		owner.add_buff(b, owner)
		# Global_SS_Ghost is a faint swirl on its own; League layers it with the generic speed lines
		b.vfx = K.attach_fx(owner, "Global_Haste")
		b.extra_fx.append(K.attach_fx(owner, "Global_SS_Ghost"))
		notify_cast(t)

	func ai_consider(ctx) -> Dictionary:
		return {} if not ctx.wants_speed() else {"pos": owner.global_position}


class HealSpell extends Ability:
	func _init(p_owner) -> void:
		super._init(p_owner)
		display_name = "Heal"
		description = "Restore 80-318 Health and grant 30% Movement Speed to you and an ally."
		cooldowns = [240.0]
		target_type = Target.NONE
		indicator = Ind.NONE
		cast_range = 900.0   # [numbers] SummonerHeal AllyRange 900 (was 850)
		cast_time = 0.0

	func execute(t: Dictionary) -> void:
		# [numbers] SummonerHeal TotalHeal: 80 -> 318 interpolated by champion level 1 -> 18 (was 90 + 15 per level = 345)
		var amt: float = lerpf(80.0, 318.0, clampf((owner.level - 1) / 17.0, 0.0, 1.0))
		var targets := [owner]
		var best = null
		var best_r := 2.0
		for a in owner.match_ref.allies_in_radius(owner.team, owner.global_position, range_m()):
			if a != owner and a.hp_ratio() < best_r:
				best_r = a.hp_ratio()
				best = a
		if best != null:
			targets.append(best)
		for u in targets:
			# [numbers] SummonerHeal StackingHealDebuff 0.5 for 30 s: a unit healed by Heal in the last 30 s is healed 50% less
			var now: float = owner.match_ref.time
			var cut: float = 0.5 if u.get_meta("summoner_heal_until", -1.0) > now else 1.0
			u.set_meta("summoner_heal_until", now + 30.0)
			Combat.heal(owner, u, amt * cut)
			# League Heal: 30% move speed for 1 s (SummonerHeal MoveSpeedDuration 1.0; was 2 s)
			var b := Buff.new("heal_ms", 1.0)
			b.stats = {"ms%": 0.3}
			b.display_name = "Heal"
			u.add_buff(b, owner)
			K.attach_fx(u, "Global_SS_Heal" if u == owner else "Global_SS_Heal_02", false)
		notify_cast(t)

	func ai_consider(ctx) -> Dictionary:
		return {"pos": owner.global_position} if owner.hp_ratio() < 0.25 and ctx.in_danger() else {}


class BarrierSpell extends Ability:
	func _init(p_owner) -> void:
		super._init(p_owner)
		display_name = "Barrier"
		description = "Gain a 100-460 Shield for 2.5 seconds."
		cooldowns = [180.0]
		target_type = Target.NONE
		indicator = Ind.NONE
		cast_range = 0.0
		cast_time = 0.0

	func execute(t: Dictionary) -> void:
		# [numbers] SummonerBarrier ShieldStrength: 100 -> 460 interpolated by champion level 1 -> 18 (was 105 + 18 per level = 411)
		var amt: float = lerpf(100.0, 460.0, clampf((owner.level - 1) / 17.0, 0.0, 1.0))
		var sh: Dictionary = Combat.shield(owner, owner, amt, 2.5)
		# the bubble disappears when the barrier breaks (it used to stay the full 2.5 s)
		K.track_shield_fx(owner, sh, K.attach_fx(owner, "Global_SS_Barrier"))
		notify_cast(t)

	func ai_consider(ctx) -> Dictionary:
		return {"pos": owner.global_position} if owner.hp_ratio() < 0.25 and ctx.in_danger() else {}


class CleanseSpell extends Ability:
	func _init(p_owner) -> void:
		super._init(p_owner)
		display_name = "Cleanse"
		description = "Remove all disables and summoner debuffs and gain 75% Tenacity for 3 seconds."
		cooldowns = [240.0]
		target_type = Target.NONE
		indicator = Ind.NONE
		cast_range = 0.0
		cast_time = 0.0

	func execute(t: Dictionary) -> void:
		owner.cleanse()
		# League Cleanse also removes summoner spell debuffs (Ignite and its Grievous Wounds)
		owner.remove_buffs_by_id("ignite")
		for gb in owner.buffs.duplicate():
			if gb.id == "grievous" and gb.has_meta("ignite"):
				owner.remove_buff(gb)
		var b := Buff.new("cleanse", 3.0)
		b.stats = {"tenacity_b": 0.75}   # [numbers] SummonerBoost TenacityValue 0.75 (was 0.65); tenacity group B (wiki Tenacity)
		owner.add_buff(b, owner)
		K.attach_fx(owner, "Jade_Summoner_Cleanse", false)
		notify_cast(t)

	func ai_consider(_ctx) -> Dictionary:
		return {"pos": owner.global_position} if (owner.cc & (Buff.CC.STUN | Buff.CC.ROOT | Buff.CC.CHARM | Buff.CC.FEAR | Buff.CC.TAUNT | Buff.CC.SLEEP)) != 0 else {}


class IgniteSpell extends Ability:
	func _init(p_owner) -> void:
		super._init(p_owner)
		display_name = "Ignite"
		description = "Ignites target enemy champion, dealing 70-475 true damage over 5 seconds and applying Grievous Wounds."
		cooldowns = [180.0]
		target_type = Target.UNIT
		target_side = Side.ENEMY
		target_champions_only = true
		indicator = Ind.NONE
		cast_range = 600.0
		cast_time = 0.0

	func execute(t: Dictionary) -> void:
		var u = t.unit
		# [numbers] SummonerDot TooltipTrueDamageCalculation: 70 at level 1, +20 per level up to level 5, +25 per level from
		# level 6 (175 at 6 ... 475 at 18; was 70 + 20 per level = 410)
		var lv: int = owner.level
		var total: float = 70.0 + 20.0 * (mini(lv, 5) - 1) + 25.0 * maxi(lv - 5, 0)
		if u == null or not is_instance_valid(u) or u.dead:
			return
		var src = owner
		var b := K.FxBuff.new("ignite", 5.0)
		b.is_debuff = true
		b.display_name = "Ignite"
		b.tick_interval = 1.0
		b.on_interval = func(bb):
			if is_instance_valid(src) and is_instance_valid(bb.owner) and not bb.owner.dead:
				Combat.deal(src, bb.owner, total / 5.0, G.DmgType.TRUE, {"is_dot": true, "is_proc": true, "tag": "burn"})
		# a second Ignite refreshes the first one: only the live buff may own the burning effect (the effect used
		# to be attached to the discarded new buff and burned forever)
		var got: Buff = u.add_buff(b, owner)
		var gw := Buff.new("grievous", 5.0)   # the core reads Grievous Wounds by this id
		gw.set_meta("ignite", true)
		gw.stats = {"_gw": 0.4}
		gw.is_debuff = true
		gw.display_name = "Grievous Wounds"
		u.add_buff(gw, owner)
		if got != null and (got.vfx == null or not is_instance_valid(got.vfx)):
			got.vfx = K.attach_fx(u, "Global_SS_Ignite")
		notify_cast(t)

	func ai_consider(ctx) -> Dictionary:
		return ctx.ignite_decision(self)


## [numbers] SummonerExhaust: range 650, 3 s, 40% slow and the target deals 35% less damage (not true damage); 290 s on the
## Howling Abyss (wiki Exhaust; the data cooldown is the Summoner's Rift 240). Cleanse removes it.
class ExhaustDebuff extends Buff:
	func _init() -> void:
		super._init("exhaust", 3.0)
		display_name = "Exhaust"
		is_debuff = true
		slow_amount = 0.4

	func on_pre_damage_dealt(info) -> void:
		if info.type != G.DmgType.TRUE:
			info.mult *= 0.65


class ExhaustSpell extends Ability:
	func _init(p_owner) -> void:
		super._init(p_owner)
		display_name = "Exhaust"
		description = "Exhausts target enemy champion, slowing them by 40% and reducing the damage they deal by 35% for 3 seconds."
		cooldowns = [290.0]
		target_type = Target.UNIT
		target_side = Side.ENEMY
		target_champions_only = true
		indicator = Ind.NONE
		cast_range = 650.0
		cast_time = 0.0

	func execute(t: Dictionary) -> void:
		var u = t.unit
		if u == null or not is_instance_valid(u) or u.dead:
			return
		u.add_buff(ExhaustDebuff.new(), owner)
		notify_cast(t)

	func ai_consider(_ctx) -> Dictionary:
		return {}


class ClaritySpell extends Ability:
	func _init(p_owner) -> void:
		super._init(p_owner)
		display_name = "Clarity"
		description = "Restores 50% of your champion's maximum Mana. Also restores allies for 25% of their maximum Mana."
		cooldowns = [240.0]
		target_type = Target.NONE
		indicator = Ind.NONE
		cast_range = 600.0
		cast_time = 0.0

	func execute(t: Dictionary) -> void:
		owner.mana = minf(owner.stats.max_mana, owner.mana + owner.stats.max_mana * 0.5)
		K.attach_fx(owner, "Global_SS_Clarity", false)
		for a in owner.match_ref.allies_in_radius(owner.team, owner.global_position, range_m()):
			if a != owner:
				a.mana = minf(a.stats.max_mana, a.mana + a.stats.max_mana * 0.25)
				K.attach_fx(a, "Global_SS_Clarity", false)
		notify_cast(t)

	func ai_consider(_ctx) -> Dictionary:
		return {"pos": owner.global_position} if owner.stats.max_mana > 0.0 and owner.mana < owner.stats.max_mana * 0.25 else {}
