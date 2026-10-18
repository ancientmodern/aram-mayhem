extends ChampionKit
## Garen, the Might of Demacia.

const GOLD := Color(1.0, 0.82, 0.35)
const STEEL := Color(0.75, 0.85, 1.0)


func build_kit() -> void:
	c.attack_missile_speed = 0.0
	c.attack_color = GOLD
	c.role = "fighter"
	c.resource_name = "None"
	c.level_order = "QEWEERQEEQRQQWWRWW"
	c.passive = Perseverance.new()
	c.add_effect(c.passive)
	c.abilities[0] = init_ability(DecisiveStrike.new(), "Q")
	c.abilities[1] = init_ability(Courage.new(), "W")
	c.abilities[2] = init_ability(Judgment.new(), "E")
	c.abilities[3] = init_ability(DemacianJustice.new(), "R")
	c.add_effect(c.abilities[1].passive_resists)
	c.add_effect(QAttackHook.new(c.abilities[0]))
	c.add_effect(SwingTrails.new(c.abilities[0]))


func ai_tuning() -> Dictionary:
	return {"aggression": 0.75}


## Match time of the last empowered Q hit: its basic attack impact is replaced by Garen_Base_Q_Tar.
var q_hit_time := -1.0


## League VFX mapping (LolVfx.champ_fx). "" disables a key that the kit spawns itself.
func vfx_map() -> Dictionary:
	var q_hit: bool = c != null and c.match_ref != null and c.match_ref.time == q_hit_time
	return {
		"BA_tar": "" if q_hit else "Garen_Base_AA_Tar",
		"BA_crit_tar": "" if q_hit else "Garen_Base_Crit_Tar",
		"Q_cas": "Garen_Base_Q_Cas",
		"Q_tar": "",
		"W_cas": "Garen_Base_W_Cas",
		"E_cas": "Garen_Base_E_Cas",
		"E_tar": "Garen_Base_E_Tar",
		"R_cas": "Garen_Base_R_Cas",
		"R_tar": "",
	}


# ===================================================================== League VFX helpers
class LFx:
	static func stop(n) -> void:
		if n != null and is_instance_valid(n):
			n.stop()

	## Stop and remove shortly after (effects whose single particles outlive the gameplay state).
	static func kill(n, fade: float = 0.25) -> void:
		if n == null or not is_instance_valid(n):
			return
		n.stop()
		if G.match != null:
			G.match.after(fade, func():
				if is_instance_valid(n):
					n.queue_free())


## Weapon swing trails on basic attacks (empowered Q swing uses the Q sword trail).
class SwingTrails extends Effect:
	var q
	var n := 0

	func _init(p_q) -> void:
		q = p_q
		id = "garen_swing_fx"
		hidden = true

	func on_attack_launch(_target) -> void:
		var nm := "Garen_Base_AA_Atk_01" if n % 2 == 0 else "Garen_Base_AA_Atk_02"
		n += 1
		if q.is_empowered():
			nm = "Garen_Base_Q_Sword_Trail"
		elif owner._pending_crit:
			nm = "Garen_Base_AA_Crit"
		LolVfx.attach(owner, nm, {"dir": owner.facing})


# ===================================================================== passive
class Perseverance extends Effect:
	var since_damage := 99.0
	var heal_fx: LolVfx = null

	func _init() -> void:
		id = "garen_passive"
		display_name = "Perseverance"

	func on_damage_taken(info) -> void:
		if info.source != null and (info.source.kind == G.Kind.CHAMPION or info.source.kind == G.Kind.TURRET or info.is_spell):
			since_damage = 0.0

	func on_tick(u, dt: float) -> void:
		since_damage += dt
		var regen: bool = since_damage >= 8.0 and u.hp < u.stats.max_hp
		if regen:
			# 1.5% -> 10.1% max health every 5 seconds by level
			var pct: float = lerpf(0.015, 0.101, (u.level - 1) / 17.0)
			u.hp = minf(u.stats.max_hp, u.hp + u.stats.max_hp * pct / 5.0 * dt)
		# League regen glow while Perseverance heals
		var show: bool = regen and not u.dead
		if show and (heal_fx == null or not is_instance_valid(heal_fx)):
			heal_fx = LolVfx.attach(u, "Garen_Base_P_Heal", {"loop": true, "height": 1.0})
		elif not show and heal_fx != null:
			LFx.stop(heal_fx)
			heal_fx = null


# ===================================================================== Q
class DecisiveStrike extends Ability:
	var empowered_until := -1.0

	func _init() -> void:
		target_type = Target.NONE
		indicator = Ind.NONE
		cast_time = 0.0
		cast_range = 0.0
		anim = ""
		resets_attack = true

	func execute(t: Dictionary) -> void:
		var o = owner
		for b in o.buffs.duplicate():
			if b.slow_amount > 0.0:
				o.remove_buff(b)
		K.haste(o, dv("MovementSpeedAmount", 0.35), dv("MovementSpeedDuration", 1.4), o, false, "garen_q_ms")
		empowered_until = o.match_ref.time + dv("AttackWindow", 4.5)
		# League: glowing sword for the empowered window, speed trail for the haste (Q_Cas flash via on_cast)
		end_fx()
		sword_fx = LolVfx.attach(o, "Garen_Base_Q_Cas_Sword", {"loop": true, "dir": o.facing})
		LFx.stop(boost_fx)
		boost_fx = LolVfx.attach(o, "Garen_Base_P_Boost", {"loop": true, "height": 0.6})
		var bf := boost_fx
		o.match_ref.after(dv("MovementSpeedDuration", 1.4), func(): LFx.stop(bf))
		notify_cast(t)

	var sword_fx: LolVfx = null
	var boost_fx: LolVfx = null

	func end_fx() -> void:
		LFx.stop(sword_fx)
		sword_fx = null

	func is_empowered() -> bool:
		return owner.match_ref != null and owner.match_ref.time < empowered_until

	func consume(target: Unit) -> void:
		empowered_until = -1.0
		end_fx()
		var sb: Buff = K.silence(target, dv("SilenceDuration", 1.5), owner)
		var m = owner.match_ref
		owner.kit.q_hit_time = m.time
		LolVfx.spawn(m, "Garen_Base_Q_Tar", target.global_position + Vector3(0, target.height * 0.5, 0), {"dir": G.flat_dir(owner.global_position, target.global_position)})
		LolVfx.spawn(m, "Garen_Base_Q_Land", target.global_position, {"dir": G.flat_dir(owner.global_position, target.global_position)})
		# League silence mark replaces the generic LOC_Silence; it is the silence buff's vfx so it ends with
		# the silence (expiry, cleanse, death) instead of a fixed timer
		if sb != null:
			var sil := LolVfx.attach(target, "Garen_Base_Q_Silence", {"loop": true, "height": target.height + 0.4})
			if sil != null:
				K.kill_fx(sb.vfx, 0.0)
				sb.vfx = sil
		if m.camera_rig != null and owner == G.player:
			m.camera_rig.shake(0.25)

	func ai_consider(ctx) -> Dictionary:
		if ctx.mode == "fight" and ctx.focus != null and G.flat_dist(owner.global_position, ctx.focus.global_position) < 7.0:
			return {"pos": owner.global_position}
		if ctx.mode == "retreat" and owner.stats.slow > 0.0:
			return {"pos": owner.global_position}
		return {}


## Empowered attack handling lives on an Effect so it can modify the basic attack.
class QAttackHook extends Effect:
	var q: DecisiveStrike

	func _init(p_q) -> void:
		q = p_q
		id = "garen_q_hook"
		hidden = true

	func on_tick(_u, _dt: float) -> void:
		if q.sword_fx != null and not q.is_empowered():
			q.end_fx()

	## Effects don't tick while dead: drop the empowered sword (and its looping glow) on death.
	func on_death(_killer) -> void:
		q.empowered_until = -1.0
		q.end_fx()
		LFx.stop(q.boost_fx)

	func on_pre_damage_dealt(info) -> void:
		if info.is_attack and q.is_empowered() and info.target != null:
			info.amount = q.dv("BaseDamage") + q.dv("tADRatio", 1.5) * owner.stats.ad
			info.tag = "garen_q"
			q.consume(info.target)


# ===================================================================== W
class Courage extends Ability:
	var passive_resists := CourageResists.new()

	func _init() -> void:
		target_type = Target.NONE
		indicator = Ind.NONE
		cast_time = 0.0
		cast_range = 0.0
		anim = "spell2"
		anim_lock = 0.2

	func execute(t: Dictionary) -> void:
		var o = owner
		var bonus_hp: float = o.stats.max_hp - (o.stats.base.base_hp + Stats.growth(o.stats.base.hp_per_level, o.level))
		var shield := dv("BaseShield") + dv("ShieldHealthRatio", 0.18) * maxf(0.0, bonus_hp)
		# same as K.shield without the procedural bubble (League W_Cas / W_Buff cover it)
		Combat.shield(o, o, shield, dv("UpfrontDuration", 0.75), {"id": ""})
		K.buff(o, "garen_w_ten", dv("UpfrontDuration", 0.75), {"tenacity": dv("UpfrontTenacity", 0.6)}, o, {"name": "Courage"})
		var b := K.buff(o, "garen_w_dr", dv("DRDuration", 4.0), {"dmg_reduction": dv("DRPercent", 0.3)}, o, {"name": "Courage", "icon": icon})
		LFx.stop(buff_fx)
		buff_fx = LolVfx.attach(o, "Garen_Base_W_Buff", {"loop": true})
		if b != null:
			var fx := buff_fx
			b.on_expire = func(_b): LFx.kill(fx, 0.3)
		notify_cast(t)

	var buff_fx: LolVfx = null

	func ai_consider(ctx) -> Dictionary:
		if ctx.in_danger() or (ctx.mode == "fight" and ctx.count_enemies_near(owner.global_position, 4.0) >= 1 and owner.hp_ratio() < 0.75):
			return {"pos": owner.global_position}
		return {}


class CourageResists extends Effect:
	var stacks := 0.0

	func _init() -> void:
		id = "garen_courage"
		hidden = true

	func get_stat_mods() -> Dictionary:
		return {"armor": stacks, "mr": stacks}

	func on_kill(_v) -> void:
		var w = owner.abilities[1]
		if w != null and w.level > 0:
			stacks = minf(30.0, stacks + 0.2 if _v.kind == G.Kind.MINION else stacks + 1.0)
			refresh_stats()


# ===================================================================== E
class Judgment extends Ability:
	var spinning := false
	var hits_on := {}

	func _init() -> void:
		target_type = Target.NONE
		indicator = Ind.CIRCLE
		ind_radius = 325.0
		cast_range = 0.0
		cast_time = 0.0
		anim = "spell3"
		can_move_while_channeling = true
		uninterruptible = true

	func make_target(world_pos: Vector3, hovered = null) -> Dictionary:
		return {"pos": owner.global_position, "dir": owner.facing, "unit": null}

	## League: the cooldown starts when the spin ends; recasting during the spin ends it early.
	func auto_cooldown() -> bool:
		return false

	func on_recast_expired() -> void:
		pass

	func execute(t: Dictionary) -> void:
		var o = owner
		if spinning:
			# recast (GarenECancel): stop spinning now
			recast_window = 0.0
			if not o.channel.is_empty() and o.channel.ability == self:
				o.interrupt_channel(true)
			return
		spinning = true
		hits_on.clear()
		var dur := dv("Duration", 3.0)
		var ticks := int(dv("NumTicks", 7.0)) + int(floor(maxf(0.0, o.stats.bonus_as) / dv("ASPerTick", 0.25)))
		var interval := dur / float(ticks)
		LFx.stop(spin_fx)
		spin_fx = LolVfx.attach(o, "Garen_Base_E_Spin", {"loop": true})
		o.play_anim("spell3", 1.0, 0.05)
		o.anim_lock = dur
		start_channel(dur, {"interval": interval, "acc": 0.0})
		o.channel_disarm = true
		recast_window = dur + 0.1
		notify_cast(t)

	func channel_tick(dt: float, ch: Dictionary) -> void:
		ch.acc += dt
		while ch.acc >= ch.interval:
			ch.acc -= ch.interval
			_tick()

	func _tick() -> void:
		var o = owner
		var targets: Array = K.enemies_circle(self, o.global_position, 325.0)
		if targets.is_empty():
			_mark_nearest(null)
			return
		var nearest: Unit = null
		var nd := INF
		for u in targets:
			var d := G.flat_dist(o.global_position, u.global_position)
			if d < nd:
				nd = d
				nearest = u
		_mark_nearest(nearest)
		var base := dv("BaseDamagePerTick") + dv("ADRatioPerTick", 0.4) * ad()
		base *= 1.0 + o.stats.crit_chance * dv("CritMod", 0.3)
		for u in targets:
			var dmg := base
			if u == nearest:
				dmg *= 1.0 + dv("NearestEnemyBonus", 0.25)
			if u.kind == G.Kind.MINION:
				dmg *= 0.75
			hit(u, dmg, G.DmgType.PHYSICAL, {"is_aoe": true, "tag": "e"})
			if u.kind == G.Kind.CHAMPION:
				var n: int = hits_on.get(u, 0) + 1
				hits_on[u] = n
				if n == int(dv("StacksToShred", 6.0)):
					var sb := K.buff(u, "garen_shred", dv("ShredDuration", 6.0), {"armor%": -dv("ShredAmount", 0.25)}, o, {"name": "Judgment", "debuff": true, "kill_fx": true})
					if sb != null:
						LolVfx.spawn(o.match_ref, "Garen_Base_E_ArmorShred_Cleaver", u.global_position + Vector3(0, u.height * 0.5, 0), {"dir": G.flat_dir(o.global_position, u.global_position)})
						# buff vfx (re-applying the shred refreshes the buff and keeps one effect; it used to stack
						# a new looping effect per application and leak the old one forever)
						if sb.vfx == null or not is_instance_valid(sb.vfx):
							sb.vfx = LolVfx.attach(u, "Garen_Base_E_ArmorShred", {"loop": true, "height": u.height * 0.5})

	var spin_fx: LolVfx = null
	var nearest_fx: LolVfx = null
	var nearest_unit = null

	## League marker on the enemy taking the nearest-target bonus.
	func _mark_nearest(u) -> void:
		if u == nearest_unit and (u == null or (nearest_fx != null and is_instance_valid(nearest_fx))):
			return
		LFx.kill(nearest_fx, 0.15)
		nearest_fx = null
		nearest_unit = u
		if u != null and is_instance_valid(u) and u.kind == G.Kind.CHAMPION:
			nearest_fx = LolVfx.attach(u, "Garen_Base_E_Nearest_Buf", {"loop": true, "height": u.height + 0.3})

	func channel_end(_ch: Dictionary, interrupted: bool) -> void:
		spinning = false
		recast_window = 0.0
		start_cooldown()
		owner.channel_disarm = false
		owner.anim_lock = 0.0
		LFx.stop(spin_fx)
		spin_fx = null
		_mark_nearest(null)
		if interrupted:
			LolVfx.attach(owner, "Garen_Base_E_Cancel", {"dir": owner.facing})

	func ai_consider(ctx) -> Dictionary:
		if ctx.count_enemies_near(owner.global_position, 3.2) >= 1 or ctx.count_enemies_near(owner.global_position, 3.2, false) >= 3:
			return {"pos": owner.global_position}
		return {}


# ===================================================================== R
class DemacianJustice extends Ability:
	func _init() -> void:
		target_type = Target.UNIT
		target_side = Side.ENEMY
		target_champions_only = true
		indicator = Ind.NONE
		cast_range = 400.0
		cast_time = 0.435
		anim = "spell4"
		anim_lock = 0.8

	func damage_vs(u: Unit) -> float:
		return dv("BaseDamage") + dv("ExecuteDamage", 0.25) * (u.stats.max_hp - u.hp)

	func execute(t: Dictionary) -> void:
		var o = owner
		var u: Unit = t.unit
		if u == null or not is_instance_valid(u) or u.dead:
			return
		var m = o.match_ref
		# League: the target is marked and the giant sword of Demacia drops onto it
		var dir := G.flat_dir(o.global_position, u.global_position)
		LolVfx.attach(u, "Garen_Base_R_Buf_Enemy_Activate", {"height": u.height + 0.3, "max_life": 2.0})
		LolVfx.spawn(m, "Garen_Base_R_Sword_Tar", u.global_position, {"dir": dir})
		var self_ref := self
		m.after(0.18, func():
			if is_instance_valid(u) and not u.dead:
				var info: DamageInfo = self_ref.hit(u, self_ref.damage_vs(u), G.DmgType.TRUE, {"tag": "r"})
				LolVfx.spawn(m, "Garen_Base_R_Tar_Impact", u.global_position, {"dir": dir})
				if info != null and info.killed:
					LolVfx.spawn(m, "Garen_Base_R_Champ_Kill", u.global_position, {"dir": dir})
				if m.camera_rig != null:
					m.camera_rig.shake(0.45 if o == G.player or u == G.player else 0.15))
		notify_cast(t)

	func ai_consider(ctx) -> Dictionary:
		for e in ctx.enemies:
			if G.flat_dist(owner.global_position, e.global_position) <= range_m() + e.radius + 0.5:
				if damage_vs(e) >= e.hp + e.total_shield():
					return {"unit": e, "pos": e.global_position}
		return {}
