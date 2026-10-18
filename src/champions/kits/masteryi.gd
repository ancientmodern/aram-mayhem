extends ChampionKit
## Master Yi, the Wuju Bladesman.

const WUJU := Color(0.5, 1.0, 0.3)


func build_kit() -> void:
	c.attack_missile_speed = 0.0
	c.attack_color = WUJU
	c.role = "assassin"
	c.level_order = "QEWQQRQEQEREEWWRWW"
	var p := DoubleStrike.new()
	p.dvals = spell("MasterYiPassive").get("data_values", {})
	c.passive = p
	c.add_effect(p)
	c.abilities[0] = init_ability(AlphaStrike.new(), "Q")
	c.abilities[1] = init_ability(Meditate.new(), "W")
	c.abilities[2] = init_ability(WujuStyle.new(), "E")
	c.abilities[3] = init_ability(Highlander.new(), "R")
	c.abilities[1].anim = ""
	c.abilities[1].cast_time = 0.0
	c.add_effect(WujuHook.new(c.abilities[2]))
	c.add_effect(MeditateGuard.new(c.abilities[1]))
	c.add_effect(HighlanderPassive.new(c.abilities[3]))
	c.add_effect(BotLeveler.new())
	c.add_effect(YiFx.new())



func ai_tuning() -> Dictionary:
	return {"aggression": 0.8}


# ===================================================================== League VFX
## League particle systems (data/vfx/masteryi.json). Casts of W/R use the automatic "<K>_cas" hook.
func vfx_map() -> Dictionary:
	return {
		"BA_tar": "", "BA_crit_tar": "",            # YiFx: swing trail + matching impact
		"Q_cas": "", "Q_mis": "", "Q_tar": "MasterYi_Base_Q_Tar",   # Q_Cas / Q_Mis / Q_End spawned by Alpha Strike
		"W_cas": "MasterYi_Base_W_Cas", "W_tar": "",
		"E_cas": "", "E_tar": "",
		"R_cas": "MasterYi_Base_R_Cas", "R_tar": "",
	}


## Basic attack visuals: League's alternating swing trails (Wuju variants while Wuju Style is up) and impacts.
class YiFx extends Effect:
	var alt := false

	func _init() -> void:
		id = "yi_lol_fx"
		hidden = true

	func on_attack_hit(t, info) -> void:
		var o = owner
		if t == null or not is_instance_valid(t) or (info != null and info.cancelled):
			return
		if o.passive != null and o.passive.get("striking"):
			return    # Double Strike's extra hit has its own trail (DoubleStrike._second)
		var wuju: bool = o.has_buff("yi_wuju")
		var crit: bool = info != null and info.is_crit
		var dir := G.flat_dir(o.global_position, t.global_position)
		var trail := ""
		if crit:
			trail = "MasterYi_Base_Crit_Wuju_Trail" if wuju else "MasterYi_Base_Crit_Trail"
		else:
			alt = not alt
			trail = "MasterYi_Base_BA%d%s_Trail" % [1 if alt else 2, "_Wuju" if wuju else ""]
		LolVfx.attach(o, trail, {"dir": dir})
		var nm := "MasterYi_Base_Crit_tar" if crit else "MasterYi_Base_BA_Tar_%02d" % (1 if alt else 2)
		LolVfx.spawn(o.match_ref, nm, t.global_position + Vector3(0, t.height * 0.5, 0), {"dir": dir})


# ===================================================================== helpers
## Bots never spend points after spawning (core gap): level abilities on their behalf.
class BotLeveler extends Effect:
	func _init() -> void:
		id = "kit_bot_leveler"
		hidden = true

	func on_tick(u, _dt: float) -> void:
		if u.is_bot and u.ability_points > 0:
			u.auto_level_abilities()


class YiAbility extends Ability:
	func try_cast(t: Dictionary) -> bool:
		if t.get("skip", false):
			return false
		return super.try_cast(t)

	func skip() -> Dictionary:
		return {"skip": true}

	func now() -> float:
		return owner.match_ref.time if owner.match_ref != null else 0.0

	func self_target() -> Dictionary:
		return {"pos": owner.global_position, "dir": owner.facing, "unit": null}

	func in_alpha() -> bool:
		var q = owner.abilities[0]
		return q != null and q.active


# ===================================================================== passive
class DoubleStrike extends Effect:
	var dvals := {}
	var count := 0
	var last_attack := -100.0
	var striking := false

	func _init() -> void:
		id = "yi_passive"
		display_name = "Double Strike"

	func val(n: String, d: float) -> float:
		return float(dvals.get(n, d))

	func now() -> float:
		return owner.match_ref.time if owner.match_ref != null else 0.0

	func hud_counter() -> String:
		return str(count) if count > 0 else ""

	func on_tick(_u, _dt: float) -> void:
		if count > 0 and now() - last_attack > val("StackDuration", 4.0):
			count = 0

	func on_attack_hit(target, info) -> void:
		if info == null or info.cancelled:
			return
		var o = owner
		var q = o.abilities[0]
		if q != null and q.level > 0:
			q.reduce_cooldown(q.dv("BasicAttackCDR", 1.0))
		if striking:
			return
		last_attack = now()
		count += 1
		if count >= int(val("AttackCount", 4.0)):
			count = 0
			var self_ref := self
			o.match_ref.after(0.14, func(): self_ref._second(target))

	func _second(target) -> void:
		var o = owner
		if o.dead or not o.attack_valid(target) or not o.can_attack():
			return
		striking = true
		var crit: bool = G.rng.randf() < o.stats.crit_chance
		var dir := G.flat_dir(o.global_position, target.global_position)
		var tp: Vector3 = target.global_position + Vector3(0, target.height * 0.5, 0)
		o.attack_hit(target, crit, 0.5)
		striking = false
		var wuju: bool = o.has_buff("yi_wuju")
		LolVfx.attach(o, "MasterYi_Base_P_%sTrail_%d" % ["Wuju_" if wuju else "", G.rng.randi_range(1, 2)], {"dir": dir})
		LolVfx.spawn(o.match_ref, "MasterYi_Base_P_tar", tp, {"dir": dir})
		o.play_anim("crit", 1.6, 0.03)
		o.anim_lock = 0.3


# ===================================================================== Q
class AlphaStrike extends YiAbility:
	var active := false

	func _init() -> void:
		target_type = Target.UNIT
		target_side = Side.ENEMY
		indicator = Ind.NONE
		cast_range = 600.0
		cast_time = 0.0
		anim = ""
		anim_lock = 0.0
		uninterruptible = true

	func damage_vs(first: bool) -> float:
		var d := dv("BaseDamage") + dv("AttackDamageRatio", 0.7) * ad()
		if not first:
			d *= dv("SubsequentHitMultiplier", 0.25)
		return d * (1.0 + owner.stats.crit_chance * dv("BonusCritDamageRatio", 1.0))

	func extra_block_reason() -> String:
		return "casting" if active else ""

	func execute(t: Dictionary) -> void:
		var o = owner
		var u = t.unit
		if u == null or not is_instance_valid(u) or u.dead:
			return
		var m = o.match_ref
		active = true
		o.cancel_windup()
		o.stop_moving()
		o.untargetable_count += 1
		o.invulnerable_count += 1
		if o.model != null:
			o.model.visible = false
		var strikes := int(dv("AlphaStrikeBounces", 4.0))
		var interval := 0.19
		var total := strikes * interval + 0.08
		start_channel(total, {})
		o.channel_disarm = true
		LolVfx.spawn(m, "MasterYi_Base_Q_Cas", o.global_position + Vector3(0, 1.0, 0), {"dir": G.flat_dir(o.global_position, u.global_position)})
		var st := {"last": null, "pos": o.global_position, "hit": {}}
		var self_ref := self
		for i in strikes:
			m.after(0.04 + i * interval, func(): self_ref._strike(i, u, st))
		m.after(total, func(): self_ref._finish(u, st))
		notify_cast(t)

	func _pick(i: int, primary, st: Dictionary):
		var o = owner
		var hset: Dictionary = st.hit
		if i == 0 and is_instance_valid(primary) and not primary.dead:
			return primary
		var center: Vector3 = primary.global_position if is_instance_valid(primary) and not primary.dead else st.pos
		var best = null
		var best_s := INF
		for e in o.match_ref.enemies_in_radius(o.team, center, cast_range * G.U):
			if hset.has(e):
				continue
			var s := G.flat_dist(center, e.global_position) + (0.0 if e.kind == G.Kind.CHAMPION else 6.0)
			if s < best_s:
				best_s = s
				best = e
		if best != null:
			return best
		if is_instance_valid(primary) and not primary.dead:
			return primary
		for e in hset:
			if is_instance_valid(e) and not e.dead:
				return e
		return null

	func _strike(i: int, primary, st: Dictionary) -> void:
		var o = owner
		if o.dead:
			return
		var m = o.match_ref
		var tgt = _pick(i, primary, st)
		if tgt == null:
			return
		var first: bool = not st.hit.has(tgt)
		st.hit[tgt] = true
		hit(tgt, damage_vs(first), G.DmgType.PHYSICAL, {"tag": "yi_q"})
		var e_ab = o.abilities[2]
		if e_ab != null and e_ab.is_active() and is_instance_valid(tgt) and not tgt.dead:
			hit(tgt, e_ab.on_hit_damage() * dv("BaseOnHitMultiplier", 0.75), G.DmgType.TRUE, {"tag": "yi_wuju"})
		var from: Vector3 = st.pos
		var tp: Vector3 = tgt.global_position
		var a := G.rng.randf() * TAU
		var land: Vector3 = tp + Vector3(cos(a), 0, sin(a)) * (tgt.radius + 0.7)
		if m.nav != null and not m.nav.is_walkable(land):
			land = tp
		o.teleport(land)
		o.face_toward(tp, 100.0)
		st.pos = land
		st.last = tgt
		_streak(m, from, land)   # impact on the target: vfx_map "Q_tar" (MasterYi_Base_Q_Tar)

	## League's Alpha Strike missile (Yi's speed shadow) flown from one strike position to the next.
	func _streak(m, from: Vector3, to: Vector3) -> void:
		if G.flat_dist(from, to) < 0.05:
			return
		var fx := LolVfx.spawn(m, "MasterYi_Base_Q_Mis", from, {"dir": G.flat_dir(from, to), "loop": true})
		if fx == null:
			return
		var tw := fx.create_tween()
		tw.tween_property(fx, "global_position", to, 0.1)
		tw.tween_callback(fx.stop)

	func _finish(primary, st: Dictionary) -> void:
		var o = owner
		if not active:
			return
		active = false
		o.untargetable_count = maxi(0, o.untargetable_count - 1)
		o.invulnerable_count = maxi(0, o.invulnerable_count - 1)
		if o.model != null:
			o.model.visible = true
		if not o.channel.is_empty() and o.channel.ability == self:
			o.channel = {}
		o.channel_disarm = false
		var m = o.match_ref
		var tgt = primary if is_instance_valid(primary) and not primary.dead else st.last
		if tgt != null and is_instance_valid(tgt) and not tgt.dead:
			var tp: Vector3 = tgt.global_position
			var back: Vector3 = tp + G.flat_dir(tp, st.pos) * (tgt.radius + o.radius + 0.3)
			if m.nav != null and m.nav.is_walkable(back):
				o.teleport(back)
			o.face_toward(tp, 100.0)
		o.reset_attack()
		if o.is_bot and tgt != null and is_instance_valid(tgt) and not tgt.dead and tgt.kind == G.Kind.CHAMPION:
			o.issue_attack(tgt)
		LolVfx.spawn(m, "MasterYi_Base_Q_End", o.global_position + Vector3(0, 1.0, 0), {"dir": o.facing})

	func channel_end(_ch: Dictionary, _interrupted: bool) -> void:
		owner.channel_disarm = false

	## True when a dangerous targeted projectile / ability is about to hit Yi.
	func threatened() -> bool:
		var o = owner
		for mi in o.match_ref.missiles:
			if not is_instance_valid(mi) or not mi.alive or mi.team == o.team:
				continue
			if mi.is_attack:
				continue
			var d := G.flat_dist(mi.global_position, o.global_position)
			if d > 5.0:
				continue
			if (mi.mode == Missile.Mode.HOMING or mi.mode == Missile.Mode.FOLLOW) and mi.target == o:
				return true
			if mi.mode == Missile.Mode.LINEAR and mi.dir.dot(G.flat_dir(mi.global_position, o.global_position)) > 0.9 and d < 3.5:
				return true
		return false

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var p: Vector3 = o.global_position
		var f = ctx.focus
		var in_rng := func(u) -> bool:
			return valid_unit_target(u) and G.flat_dist(p, u.global_position) <= range_m() + o.radius + u.radius
		if threatened() or (ctx.in_danger() and o.hp_ratio() < 0.25):
			var any = null
			for e in ctx.enemies:
				if in_rng.call(e):
					any = e
					break
			if any == null:
				for mn in ctx.enemy_minions:
					if in_rng.call(mn):
						any = mn
						break
			if any != null:
				return {"unit": any, "pos": any.global_position}
		if ctx.mode == "fight" and f != null and is_instance_valid(f) and in_rng.call(f):
			var d := G.flat_dist(p, f.global_position)
			var melee: float = o.attack_range_m() + o.radius + f.radius
			if d > melee + 1.0 or f.hp_ratio() < 0.35 or ctx.count_enemies_near(f.global_position, 4.0) >= 2:
				return {"unit": f, "pos": f.global_position}
		if ctx.enemies.is_empty() and o.mana > o.stats.max_mana * 0.6:
			for mn in ctx.enemy_minions:
				if in_rng.call(mn) and ctx.count_enemies_near(mn.global_position, 4.0, false) >= 4:
					return {"unit": mn, "pos": mn.global_position}
		return skip()


# ===================================================================== W
class Meditate extends YiAbility:
	var channeling := false
	var dr_until := -1.0
	var extra_until := -1.0
	var fx: LolVfx = null

	func _init() -> void:
		target_type = Target.NONE
		indicator = Ind.NONE
		cast_range = 0.0
		cast_time = 0.0
		anim = ""
		anim_lock = 0.0

	func make_target(_world_pos: Vector3, _hovered = null) -> Dictionary:
		return self_target()

	func extra_block_reason() -> String:
		return "casting" if in_alpha() or channeling else ""

	func execute(t: Dictionary) -> void:
		var o = owner
		var dur := dv("HealDuration", 4.0)
		channeling = true
		extra_until = now() + dv("InitialExtraDRDuration", 0.5)
		dr_until = now() + dur + dv("DRLinger", 0.5)
		o.cancel_windup()
		o.stop_moving()
		o.play_anim("spell2", 1.0, 0.1)
		o.anim_lock = 0.7
		start_channel(dur, {"acc": 0.0, "elapsed": 0.0})
		o.channel_disarm = true
		# League meditate aura for the channel (W_Cas burst comes from the automatic cast hook)
		if fx != null and is_instance_valid(fx):
			fx.stop()
		fx = LolVfx.attach(o, "MasterYi_Base_W_Buf", {"loop": true, "dir": o.facing})
		notify_cast(t)

	func channel_tick(dt: float, ch: Dictionary) -> void:
		var o = owner
		ch.elapsed += dt
		ch.acc += dt
		# Meditate pauses Wuju Style and Highlander
		for bid in ["yi_wuju", "yi_highlander"]:
			var b = o.find_buff(bid)
			if b != null:
				b.remaining += dt
		var interval := dv("TickFrequency", 0.5)
		var ticks := dv("HealDuration", 4.0) / interval
		while ch.acc >= interval:
			ch.acc -= interval
			var total := dv("BaseHeal") + ap()
			var amt: float = total / ticks * (1.0 + (1.0 - o.hp_ratio()) * dv("MaxMissingHealthPercent", 1.0))
			Combat.heal(o, o, amt)
		if o.is_bot and ch.elapsed > 1.0 and o.hp_ratio() > 0.9:
			ch.t = 0.0

	func channel_end(_ch: Dictionary, _interrupted: bool) -> void:
		var o = owner
		channeling = false
		o.channel_disarm = false
		o.anim_lock = 0.0
		dr_until = minf(dr_until, now() + dv("DRLinger", 0.5))
		if fx != null and is_instance_valid(fx):
			fx.stop()
		fx = null

	func current_dr(src) -> float:
		if now() > dr_until:
			return 0.0
		var dr := dv("DamageReduction", 0.45)
		if now() < extra_until:
			dr += dv("InitialExtraDR", 0.25)
		if src != null and is_instance_valid(src) and src.kind == G.Kind.TURRET:
			dr *= dv("DamageReductionTowerMod", 0.5)
		return dr

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var f = ctx.focus
		var hp: float = o.hp_ratio()
		if ctx.mode == "fight" and f != null and is_instance_valid(f) and f.hp_ratio() < 0.15 and o.in_attack_range(f, 0.5) and hp > 0.15:
			return skip()
		# never meditate in turret range (the damage reduction is halved against turrets)
		if ctx._under_enemy_turret(o.global_position):
			return skip()
		if not ctx.enemies.is_empty() and hp < 0.3:
			return self_target()
		elif hp < 0.55 and ctx.enemy_minions.size() < 3:
			return self_target()
		return skip()


## Meditate's damage reduction (halved against turrets).
class MeditateGuard extends Effect:
	var w

	func _init(p_w) -> void:
		w = p_w
		id = "yi_w_dr"
		hidden = true

	var fx_t := -10.0

	func on_pre_damage_taken(info) -> void:
		var dr: float = w.current_dr(info.source)
		if dr > 0.0:
			info.mult *= 1.0 - dr
			# League "damage absorbed while meditating" flash, rate limited
			var o = owner
			var tnow: float = o.match_ref.time if o.match_ref != null else 0.0
			if w.channeling and tnow - fx_t > 0.4:
				fx_t = tnow
				LolVfx.spawn(o.match_ref, "MasterYi_Base_W_Dmg", o.global_position + Vector3(0, 1.0, 0), {})


# ===================================================================== E
class WujuStyle extends YiAbility:
	func _init() -> void:
		target_type = Target.NONE
		indicator = Ind.NONE
		cast_range = 0.0
		cast_time = 0.0
		anim = "spell3"
		anim_lock = 0.25

	func make_target(_world_pos: Vector3, _hovered = null) -> Dictionary:
		return self_target()

	func is_active() -> bool:
		return owner.has_buff("yi_wuju")

	func on_hit_damage() -> float:
		return dv("BaseDamage") + dv("ADRatio", 0.35) * bonus_ad()

	func execute(t: Dictionary) -> void:
		var o = owner
		var dur := dv("Duration", 5.0)
		var b := K.buff(o, "yi_wuju", dur, {}, o, {"name": "Wuju Style", "icon": icon})
		# League Wuju blade glow for the buff (stopped by the buff on expiry)
		if b != null and (b.vfx == null or not is_instance_valid(b.vfx)):
			b.vfx = LolVfx.attach(o, "MasterYi_Base_E_buff", {"loop": true, "dir": o.facing, "height": 1.0})
		notify_cast(t)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		if is_active():
			return skip()
		var f = ctx.focus
		if ctx.mode == "fight" and f != null and is_instance_valid(f) and o.in_attack_range(f, 1.2):
			return self_target()
		var at = o.attack_target
		if ctx.enemies.is_empty() and at != null and is_instance_valid(at) and at.kind == G.Kind.TURRET and o.in_attack_range(at, 0.3):
			return self_target()
		return skip()


class WujuHook extends Effect:
	var e_ab

	func _init(p_e) -> void:
		e_ab = p_e
		id = "yi_wuju_hook"
		hidden = true

	func on_attack_hit(target, info) -> void:
		if info == null or info.cancelled or not e_ab.is_active():
			return
		if target == null or not is_instance_valid(target) or target.dead:
			return
		Combat.deal(owner, target, e_ab.on_hit_damage(), G.DmgType.TRUE, {"is_proc": true, "tag": "yi_wuju", "ability": e_ab})


# ===================================================================== R
class Highlander extends YiAbility:
	var saved_run: Array = []

	func _init() -> void:
		target_type = Target.NONE
		indicator = Ind.NONE
		cast_range = 0.0
		cast_time = 0.0
		anim = ""
		anim_lock = 0.0

	func make_target(_world_pos: Vector3, _hovered = null) -> Dictionary:
		return self_target()

	func execute(t: Dictionary) -> void:
		var o = owner
		var dur := dv("RDuration", 7.0)
		for b0 in o.buffs.duplicate():
			if b0.slow_amount > 0.0:
				o.remove_buff(b0)
		var b := K.buff(o, "yi_highlander", dur, {"as": dv("RASBonus") / 100.0, "ms%": dv("RMSBonus") / 100.0, "slow_resist": 1.0}, o,
				{"name": "Highlander", "icon": icon})
		if b != null and (b.vfx == null or not is_instance_valid(b.vfx)):
			# League Highlander aura by rank (stopped by the buff on expiry); R_Cas comes from the cast hook
			var buf_fx: String = ["MasterYi_Base_R_Buf", "MasterYi_Base_R_Buf_Lvl2", "MasterYi_Base_R_Buf_Lvl3"][clampi(level, 1, 3) - 1]
			b.vfx = LolVfx.attach(o, buf_fx, {"loop": true, "dir": o.facing})
			var clip: String = o._raw_clip("run_haste")
			if clip != "":
				saved_run = o.anim_map.get("run", []).duplicate()
				o.anim_map["run"] = [clip]
				o.cur_anim = ""
			var self_ref := self
			b.on_expire = func(_bb): self_ref._restore_run()
		notify_cast(t)

	func _restore_run() -> void:
		var o = owner
		if not saved_run.is_empty():
			o.anim_map["run"] = saved_run
			saved_run = []
			o.cur_anim = ""

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		if o.has_buff("yi_highlander"):
			return skip()
		var f = ctx.focus
		if ctx.mode == "fight" and f != null and is_instance_valid(f):
			var d := G.flat_dist(o.global_position, f.global_position)
			if d < 9.0 and (f.hp_ratio() < 0.6 or ctx.enemies.size() >= 2 or o.stats.slow > 0.1):
				return self_target()
		if ctx.mode == "retreat" and ctx.in_danger() and o.stats.slow > 0.2:
			return self_target()
		return skip()


## Highlander passive: takedowns slash basic cooldowns by 70% and extend an active Highlander.
class HighlanderPassive extends Effect:
	var r

	func _init(p_r) -> void:
		r = p_r
		id = "yi_r_passive"
		hidden = true

	func on_takedown(victim) -> void:
		if victim == null or victim.kind != G.Kind.CHAMPION or r.level <= 0:
			return
		var o = owner
		for i in 3:
			var a = o.abilities[i]
			if a != null and a.cd > 0.0:
				a.reduce_cooldown_pct(r.dv("RCooldownRefund", 0.7))
		var b = o.find_buff("yi_highlander")
		if b != null:
			b.remaining += r.dv("RKillAssistExtension", 7.0)
			b.duration = maxf(b.duration, b.remaining)
		LolVfx.attach(o, "MasterYi_Base_R_OnBuffKill", {"dir": o.facing})
