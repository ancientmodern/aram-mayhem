extends ChampionKit
## Miss Fortune, the Bounty Hunter.


func build_kit() -> void:
	c.attack_missile_speed = 2000.0
	c.attack_color = Color(1.0, 0.75, 0.4)
	c.role = "marksman"
	c.level_order = "QEWQQRQEQEREEWWRWW"
	c.passive = LoveTap.new()
	c.add_effect(c.passive)
	c.abilities[0] = init_ability(DoubleUp.new(), "Q")
	var w = init_ability(Strut.new(), "W")
	c.abilities[1] = w
	c.abilities[2] = init_ability(MakeItRain.new(), "E")
	var r = init_ability(BulletTime.new(), "R")
	r.cast_range = float(spell("R").get("castConeDistance", 1400.0))
	r.ind_length = r.cast_range
	c.abilities[3] = r
	c.add_effect(StrutPassive.new(w))
	# [anim-events] the pistol muzzle flashes are the Attack1 (right) / Attack2 (left) clip events; League alternates
	# her pistols every attack
	c.attack_alternate = true
	c.add_effect(BotLeveler.new())


func ai_tuning() -> Dictionary:
	return {"aggression": 0.6}


## League VFX mapping. An attack on a new target (Love Tap) fires League's passive missile.
## Q hits, Make It Rain and the Bullet Time muzzle flashes are spawned by the abilities.
func vfx_map() -> Dictionary:
	var mis := "MissFortune_Base_BA_mis"
	var t = c.attack_target
	var tap = c.passive   # LoveTap (untyped: last_target is not an Effect member)
	if tap != null and t != null and is_instance_valid(t) and t != tap.last_target and not FX.is_structure(t):
		mis = "MissFortune_Base_P_Mis"
	return {
		"BA_mis": mis, "BA_crit_mis": mis,
		"BA_tar": "MissFortune_Base_BA_Tar", "BA_crit_tar": "MissFortune_Base_BA_Crit_Tar",
		"Q_cas": "", "Q_mis": "MissFortune_Base_Q_Mis", "Q_tar": "",
		"W_cas": "", "W_mis": "", "W_tar": "",
		"E_cas": "", "E_mis": "", "E_tar": "",
		"R_cas": "", "R_mis": "MissFortune_Base_R_mis", "R_tar": "MissFortune_Base_R_Tar",
	}


# ===================================================================== shared
## Workaround: the core only levels bot abilities at spawn; spend new points as bots level up.
class BotLeveler extends Effect:
	func _init() -> void:
		id = "kit_bot_leveler"
		hidden = true

	func on_tick(u, _dt: float) -> void:
		if u.is_bot and u.ability_points > 0:
			u.auto_level_abilities()


## Abilities return {"skip": true} from ai_consider to hold (prevents the generic bot fallback).
class KitAbility extends Ability:
	func try_cast(t: Dictionary) -> bool:
		if t.get("skip", false):
			return false
		# a player casting something else cancels Bullet Time
		if not owner.is_bot and not owner.channel.is_empty() and owner.channel.ability != self:
			owner.interrupt_channel(true)
		return super(t)

	## Bots never break their own Bullet Time channel with another cast.
	func extra_block_reason() -> String:
		if owner.is_bot and not owner.channel.is_empty() and owner.channel.ability != self:
			return "channeling"
		return ""

	func skip() -> Dictionary:
		return {"skip": true}

	func ground(p: Vector3) -> Vector3:
		var m = owner.match_ref
		return Vector3(p.x, m.nav.height_at(p) if m.nav != null else 0.0, p.z)


class FX extends RefCounted:
	static func is_structure(u) -> bool:
		return u.kind == G.Kind.TURRET or u.kind == G.Kind.INHIBITOR or u.kind == G.Kind.NEXUS

	## True when `u` fights against the local player (League's red / enemy-colored variants).
	static func is_enemy_of_player(u) -> bool:
		return G.player != null and is_instance_valid(G.player) and G.player.team != u.team

	## Body-height point of a unit (where League hit effects play).
	static func body(u) -> Vector3:
		return u.global_position + Vector3(0, (u.height if u.kind == G.Kind.CHAMPION else 1.6) * 0.5, 0)


# ===================================================================== passive
class LoveTap extends Effect:
	var last_target = null

	func _init() -> void:
		id = "mf_passive"
		display_name = "Love Tap"

	## 50% -> 100% AD by level (levels 1/4/7/9/11/13).
	func ratio() -> float:
		var lv: int = owner.level
		if lv >= 13:
			return 1.0
		if lv >= 11:
			return 0.9
		if lv >= 9:
			return 0.8
		if lv >= 7:
			return 0.7
		if lv >= 4:
			return 0.6
		return 0.5

	func bonus_vs(u) -> float:
		var b: float = ratio() * owner.stats.ad
		if u.kind != G.Kind.CHAMPION:
			b *= 0.5
		return b

	## Returns the Love Tap bonus if `u` is a new target (and consumes it), else 0.
	func try_tap(u) -> float:
		if u == null or not is_instance_valid(u) or u == last_target:
			return 0.0
		last_target = u
		if u.kind == G.Kind.TURRET or u.kind == G.Kind.INHIBITOR or u.kind == G.Kind.NEXUS:
			return 0.0
		LolVfx.spawn(owner.match_ref, "MissFortune_Base_P_Tar", FX.body(u), {"dir": G.flat_dir(owner.global_position, u.global_position)})
		if u.kind == G.Kind.CHAMPION:
			var w = owner.abilities[1]
			if w != null and w.level > 0:
				# [numbers] League LoveTapRefund = LoveTapBaseRefund (2 s) x CooldownMultiplierCalculationPart, i.e. 2 s of *base*
				# cooldown: ability haste shrinks the refund (missfortune.bin MissFortuneViciousStrikes).
				w.reduce_cooldown(owner.stats.cooldown(w.dv("LoveTapBaseRefund", 2.0)))
		return bonus_vs(u)

	func on_pre_damage_dealt(info) -> void:
		if info.is_attack and info.target != null:
			var b := try_tap(info.target)
			if b > 0.0:
				if info.is_crit:
					b *= owner.stats.crit_damage
				info.flat_bonus += b


# ===================================================================== Q
class DoubleUp extends KitAbility:
	const BOUNCE_R := 500.0

	func _init() -> void:
		target_type = Target.UNIT
		target_side = Side.ENEMY
		indicator = Ind.NONE
		cast_time = 0.25
		anim = "spell1"
		anim_lock = 0.35
		resets_attack = true

	func damage() -> float:
		return dv("BaseDamage") + dv("ADRatio", 1.0) * ad() + dv("APRatio", 0.35) * ap()

	func crit_mult() -> float:
		return 1.0 + dv("BounceCriticalMod", 0.5) * (owner.stats.crit_damage - 1.0)

	func execute(t: Dictionary) -> void:
		var o = owner
		var u: Unit = t.get("unit")
		if u == null or not is_instance_valid(u) or u.dead:
			return
		var m = o.match_ref
		var from: Vector3 = K.cast_pos(o, 1.2)
		var dir := G.flat_dir(o.global_position, u.global_position)
		var self_ref := self
		# [anim-events] MissFortune_Base_Q_Cas is the Spell1 clip's particle event (right pistol, frame 5)
		K.homing_missile(self, from, u, 1400.0, func(_mi, tu): self_ref._first_hit(tu, dir), {"lol": "MissFortune_Base_Q_Mis", "height": 1.2})
		notify_cast(t)

	func _apply(u: Unit, amount: float, crit: bool, tag: String) -> DamageInfo:
		var o = owner
		var bonus: float = o.passive.try_tap(u) if o.passive != null else 0.0
		if crit:
			bonus *= o.stats.crit_damage
		var info := hit(u, amount + bonus, G.DmgType.PHYSICAL, {"tag": tag, "is_crit": crit})
		if info != null and not info.cancelled and is_instance_valid(u):
			for e in o.effects.duplicate():
				e.on_attack_hit(u, info)
		return info

	func _first_hit(u: Unit, dir: Vector3) -> void:
		var o = owner
		if not is_instance_valid(o) or not is_instance_valid(u):
			return
		var m = o.match_ref
		var pos: Vector3 = u.global_position
		var info := _apply(u, damage(), false, "q")
		var killed: bool = info != null and info.killed
		if is_instance_valid(u):
			LolVfx.spawn(m, "MissFortune_Base_Q_Tar", FX.body(u), {"dir": dir})
			if killed:
				LolVfx.spawn(m, "MissFortune_Base_Q_Tar_killed", FX.body(u), {"dir": dir})
		var nxt := bounce_target(u, pos, dir)
		var self_ref := self
		if nxt == null:
			# dud ricochet: League dud bullet, dust puff where it drops
			var mi := K.line_missile(self, pos + Vector3(0, 1.2, 0), dir, 400.0, 176.0, {"width": 10.0, "lol": "MissFortune_Base_Q_Mis_Dud",
				"on_end": func(_mi, ep): LolVfx.spawn(m, "MissFortune_Base_Q_Mis_Dud_Dust", ground(ep), {"dir": dir, "height": 0.1})})
			mi.collides = false
			return
		var crit: bool = killed or G.rng.randf() < o.stats.crit_chance
		K.homing_missile(self, pos + Vector3(0, 1.2, 0), nxt, 1400.0, func(_mi, tu): self_ref._second_hit(tu, crit),
			{"lol": "MissFortune_Base_Q_Mis", "height": 1.2})

	func _second_hit(tu: Unit, crit: bool) -> void:
		if not is_instance_valid(owner) or not is_instance_valid(tu):
			return
		var m = owner.match_ref
		var dmg: float = damage() * (crit_mult() if crit else 1.0)
		var p2: Vector3 = FX.body(tu)
		var d2 := G.flat_dir(owner.global_position, tu.global_position)
		_apply(tu, dmg, crit, "q2")
		LolVfx.spawn(m, "MissFortune_Base_Q_second_tar", p2, {"dir": d2})
		if crit:
			LolVfx.spawn(m, "MissFortune_Base_Q_second_02_tar", p2, {"dir": d2})

	## Unit behind `first` (relative to the shot direction). League priority: 500 units within a 20° cone,
	## then 40°, then 110°, then 150 units within 160° (full angles); champions first inside a tier.
	func bounce_target(first, pos: Vector3, dir: Vector3) -> Unit:
		var o = owner
		var best: Unit = null
		var best_s := INF
		for u in o.match_ref.enemies_in_radius(o.team, pos, BOUNCE_R * G.U):
			if u == first:
				continue
			var to := G.flat(u.global_position - pos)
			var d := to.length()
			if d < 0.05:
				continue
			var ang := rad_to_deg(dir.angle_to(to / d))
			var tier := -1
			if ang <= 10.0:
				tier = 0
			elif ang <= 20.0:
				tier = 1
			elif ang <= 55.0:
				tier = 2
			elif ang <= 80.0 and d <= 150.0 * G.U + u.radius:
				tier = 3
			if tier < 0:
				continue
			var s := tier * 100.0 + (0.0 if u.kind == G.Kind.CHAMPION else 50.0) + d
			if s < best_s:
				best_s = s
				best = u
		return best

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var p: Vector3 = o.global_position
		var rng := range_m()
		var dmg := damage()
		var mana_r: float = o.mana / maxf(o.stats.max_mana, 1.0)
		# bounce setups: a target in front with an enemy champion behind it
		var best: Unit = null
		var best_s := -INF
		for u in ctx.enemy_minions + ctx.enemies:
			if G.flat_dist(p, u.global_position) > rng + u.radius + o.radius:
				continue
			var nxt := bounce_target(u, u.global_position, G.flat_dir(p, u.global_position))
			if nxt == null or nxt.kind != G.Kind.CHAMPION:
				continue
			var kills: bool = u.hp <= dmg * Combat.resist_multiplier(u.stats.armor, o, true)
			var s := 5.0 + (8.0 if kills else 0.0) + (1.0 - nxt.hp_ratio()) * 3.0 + (2.0 if u.kind == G.Kind.CHAMPION else 0.0)
			if s > best_s:
				best_s = s
				best = u
		if best != null and (ctx.mode != "lane" or mana_r > 0.3 or best_s > 12.0):
			return {"unit": best, "pos": best.global_position, "dir": G.flat_dir(p, best.global_position)}
		var t: Unit = ctx.best_enemy_in_range(rng)
		if t != null and (ctx.mode == "fight" or mana_r > 0.45 or t.hp_ratio() < 0.35):
			return {"unit": t, "pos": t.global_position, "dir": G.flat_dir(p, t.global_position)}
		# farm: last hit with Q when it won't be wasted
		if ctx.enemies.is_empty() and mana_r > 0.6:
			for mn in ctx.enemy_minions:
				if G.flat_dist(p, mn.global_position) <= rng and mn.hp <= dmg * Combat.resist_multiplier(mn.stats.armor, o, true):
					return {"unit": mn, "pos": mn.global_position, "dir": G.flat_dir(p, mn.global_position)}
		return skip()


# ===================================================================== W
class Strut extends KitAbility:
	var since_hit := 99.0

	func _init() -> void:
		target_type = Target.NONE
		indicator = Ind.NONE
		cast_range = 0.0
		cast_time = 0.0
		anim = ""
		anim_lock = 0.0

	func cancels_windup() -> bool:
		return true

	func make_target(_world_pos: Vector3, _hovered = null) -> Dictionary:
		return {"pos": owner.global_position, "dir": owner.facing, "unit": null}

	func passive_ms() -> float:
		if level <= 0:
			return 0.0
		var ooc := dv("PassiveBaseMSOOC", 4.0)
		if owner.has_buff("mf_w_active") or since_hit >= ooc + dv("PassiveMaxMSExtraOOC", 3.0):
			return dv("PassiveMaxMS", 60.0)
		if since_hit >= ooc:
			return dv("PassiveBaseMS", 25.0)
		return 0.0

	func execute(t: Dictionary) -> void:
		var o = owner
		var dur := dv("ActiveDuration", 4.0)
		var b: Buff = K.buff(o, "mf_w_active", dur, {"as": dv("ActiveAS", 0.4)}, o, {"name": "Strut", "icon": icon, "kill_fx": true})
		# League Strut active: the muzzle glow loops on each gun (W_Buf_RWeapon / LWeapon, bones R_WEAPON / L_WEAPON)
		# for the duration and ends with the W_Buf_End_* flashes; W_buf is the one-shot hand flash at the cast
		# (its 6 s starburst "glow" emitter must not be looped at the feet).
		if b != null and (b.vfx == null or not is_instance_valid(b.vfx)):
			b.vfx = LolVfx.attach(o, "MissFortune_Base_W_Buf_RWeapon", {"loop": true, "bone": "R_WEAPON"})
			var fb := b as K.FxBuff
			if fb != null:
				fb.extra_fx.append(LolVfx.attach(o, "MissFortune_Base_W_Buf_LWeapon", {"loop": true, "bone": "L_WEAPON"}))
			var wr := weakref(o)
			b.on_expire = func(_bb):
				var u = wr.get_ref()
				if u != null:
					LolVfx.attach(u, "MissFortune_Base_W_Buf_End_RWeapon", {"bone": "R_WEAPON"})
					LolVfx.attach(u, "MissFortune_Base_W_Buf_End_LWeapon", {"bone": "L_WEAPON"})
		LolVfx.attach(o, "MissFortune_Base_W_buf", {"bone": "R_Hand", "max_life": 1.2})
		o.stats.mark_dirty()
		notify_cast(t)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var f: Unit = ctx.focus
		if ctx.mode == "fight" and f != null and is_instance_valid(f) and o.edge_dist(f) < o.attack_range_m() + 1.5:
			return make_target(o.global_position)
		if ctx.mode == "retreat" and ctx.in_danger():
			return make_target(o.global_position)
		if ctx.wants_speed():
			return make_target(o.global_position)
		return skip()


## Strut's passive move speed (and its out-of-combat timer).
class StrutPassive extends Effect:
	var w

	func _init(p_w) -> void:
		w = p_w
		id = "mf_strut"
		hidden = true

	var _tier := 0             ## 0 none, 1 base Strut speed, 2 full Strut speed
	var _fx: LolVfx = null

	func on_tick(u, dt: float) -> void:
		w.since_hit += dt
		# League Strut visuals: P_Buff while the base speed is up, W_Max (+ W_MaxStart) at full speed
		var ms: float = w.passive_ms()
		var tier := 0
		if ms > 0.0 and not u.dead:
			tier = 2 if ms >= w.dv("PassiveMaxMS", 60.0) - 0.01 else 1
		if tier != _tier:
			_set_tier(u, tier)

	func on_death(_killer) -> void:
		_set_tier(owner, 0)

	func _set_tier(u, tier: int) -> void:
		_tier = tier
		if _fx != null and is_instance_valid(_fx):
			_fx.stop()
		_fx = null
		if tier == 1:
			_fx = LolVfx.attach(u, "MissFortune_Base_P_Buff", {"loop": true, "dir": u.facing})
		elif tier == 2:
			_fx = LolVfx.attach(u, "MissFortune_Base_W_Max", {"loop": true, "dir": u.facing})
			LolVfx.attach(u, "MissFortune_Base_W_MaxStart", {"height": 0.2})

	func on_damage_taken(info) -> void:
		var s = info.source
		if s != null and (s.kind == G.Kind.CHAMPION or s.kind == G.Kind.TURRET or info.is_spell):
			w.since_hit = 0.0

	func get_stat_mods() -> Dictionary:
		var ms: float = w.passive_ms()
		return {"ms": ms} if ms > 0.0 else {}


# ===================================================================== E
class MakeItRain extends KitAbility:
	func _init() -> void:
		target_type = Target.POINT
		indicator = Ind.CIRCLE
		ind_radius = 350.0
		cast_time = 0.25
		anim = "spell3"
		anim_lock = 0.4

	func dps() -> float:
		return dv("BaseDamagePerSecond") + dv("APRatioPerSecond", 0.6) * ap()

	func slow_amount() -> float:
		return dv("BaseSlowAmount", 0.4) + dv("SlowPer100AP", 0.0006) * ap()

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var pos := ground(t.pos)
		var r_m := ind_radius * G.U
		var delay := dv("CastDelay", 0.25)
		var dur := dv("BaseDuration", 2.0)
		var interval := 1.0 / maxf(1.0, dv("TicksPerSecond", 4.0))
		var per_tick := dps() * interval
		var slow := slow_amount()
		_visual(m, pos, r_m, delay, dur)
		var st := {"age": 0.0, "acc": 0.0}
		var self_ref := self
		m.add_ticker(delay + dur, func(dt: float) -> bool:
			st.age += dt
			if not is_instance_valid(o) or st.age < delay:
				return true
			st.acc += dt
			while st.acc >= interval:
				st.acc -= interval
				for u in m.enemies_in_radius(o.team, pos, r_m):
					self_ref.hit(u, per_tick, G.DmgType.MAGIC, {"tag": "e", "is_aoe": true, "is_dot": true})
					K.slow(u, slow, interval + 0.1, o, false, "mf_e_slow")
					if G.rng.randf() < 0.5 and is_instance_valid(u):
						LolVfx.spawn(m, "MissFortune_Base_E_Unit_Tar", FX.body(u) + Vector3(G.rng.randf_range(-0.3, 0.3), 0, G.rng.randf_range(-0.3, 0.3)))
			return true)
		notify_cast(t)

	func _visual(m, pos: Vector3, r_m: float, delay: float, dur: float) -> void:
		var life := delay + dur
		# League zone: team-colored ring decal (the slow-zone telegraph) + shockwave ring / dome
		var zone := LolVfx.spawn(m, "MissFortune_Base_E_Unit_Tar_red" if FX.is_enemy_of_player(owner) else "MissFortune_Base_E_Unit_Tar_green", pos, {"loop": true, "height": 0.05})
		if zone != null:
			var wz := weakref(zone)
			m.after(life, func():
				var z = wz.get_ref()
				if z != null:
					z.stop())
		# League bullet rain: falling E_Bullet_Child rounds + E_Hit_Dirt impacts (their 0.45s delay matches the fall)
		var st := {"t": 0.0, "acc": 0.0}
		var rate := 12.0
		m.add_ticker(life, func(dt: float) -> bool:
			st.t += dt
			if st.t < delay * 0.5:
				return true
			st.acc += dt * rate
			while st.acc >= 1.0:
				st.acc -= 1.0
				var a := G.rng.randf() * TAU
				var rr := sqrt(G.rng.randf()) * r_m * 0.9
				var p := ground(pos + Vector3(cos(a) * rr, 0, sin(a) * rr))
				_rain_bullet(m, p)
			return true)

	## One falling round: League's child bullet carried down onto `p`, dirt impact on landing.
	func _rain_bullet(m, p: Vector3) -> void:
		var fall := 0.45
		var carrier := Node3D.new()
		m.fx_root.add_child(carrier)
		carrier.global_position = p + Vector3(0, 6.0, 0)
		var fx := LolVfx.attach(carrier, "MissFortune_Base_E_Bullet_Child", {"loop": true})
		var dirt := LolVfx.spawn(m, "MissFortune_Base_E_Hit_Dirt", p, {"height": 0.05})
		if dirt != null:
			var wd := weakref(dirt)   # cut the long League tail (dur 12.5s) once the impact has played
			m.after(1.6, func():
				var d = wd.get_ref()
				if d != null:
					d.stop())
		var tw := carrier.create_tween()
		tw.tween_property(carrier, "global_position", p + Vector3(0, 0.3, 0), fall).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_callback(func():
			if is_instance_valid(fx):
				fx.detach_and_fade()
			carrier.queue_free())

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var rng := range_m()
		var r_m := ind_radius * G.U
		var mana_r: float = o.mana / maxf(o.stats.max_mana, 1.0)
		var cp: Vector3 = ctx.best_cluster_point(rng, r_m * 0.9, 2)
		if cp != Vector3.INF:
			return ctx.aim_at(cp, self)
		if ctx.mode == "fight" and ctx.focus != null:
			var f: Unit = ctx.focus
			if G.flat_dist(o.global_position, f.global_position) <= rng + r_m * 0.5 and (f.hp_ratio() < 0.6 or mana_r > 0.5):
				return ctx.aim_at(ctx.predict(f, 0.6), self)
		if ctx.mode == "retreat" and not ctx.enemies.is_empty():
			var e0: Unit = ctx.enemies[0]
			if G.flat_dist(o.global_position, e0.global_position) < 7.0:
				return ctx.aim_at(ctx.predict(e0, 0.4), self)
		# wave clear when rich in mana
		if ctx.enemies.is_empty() and mana_r > 0.75:
			for mn in ctx.enemy_minions:
				if G.flat_dist(o.global_position, mn.global_position) > rng:
					continue
				var n := 0
				for mn2 in ctx.enemy_minions:
					if G.flat_dist(mn.global_position, mn2.global_position) <= r_m:
						n += 1
				if n >= 4:
					return make_target(mn.global_position, null)
		return skip()


# ===================================================================== R
class BulletTime extends KitAbility:
	## Full cone angle: twice the data's castConeAngle (17, a half-angle) over castConeDistance 1400.
	const ANGLE := 34.0
	const MAX_WAVES_PER_TICK := 3   ## a long frame never fires more than a few waves at once
	var _cone: LolVfx = null
	var _token := 0                 ## bumps on every cast / end: stale delayed hits are dropped

	func _init() -> void:
		target_type = Target.DIRECTION
		indicator = Ind.CONE
		ind_angle = ANGLE
		cast_time = 0.0
		anim = ""
		anim_lock = 0.0

	func wave_damage() -> float:
		return dv("BaseDamage") + dv("tADRatio", 0.6) * ad() + dv("APRatio", 0.25) * ap()

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var dir: Vector3 = t.dir
		var waves := int(dv("BaseWaves", 14.0))
		var dur := dv("BaseChannelDuration", 3.0)
		var interval := maxf(0.05, dur / float(maxi(waves, 1)))
		# a previous Bullet Time still marked active (its channel was replaced without channel_end): clean it first
		_cleanup()
		_token += 1
		o.stop_moving()
		o.cancel_windup()
		o.face_toward(o.global_position + dir, 1000.0)
		start_channel(dur, {"dir": dir, "interval": interval, "acc": interval, "left": clampi(waves, 0, 64), "n": 0, "token": _token})
		o.channel_disarm = true
		o.play_anim("spell4", 1.0, 0.1)
		o.anim_lock = dur
		_cone = _cone_visual(m, o.global_position, dir, dur)
		LolVfx.spawn(m, "MissFortune_Base_R_cas_smoke", o.global_position + Vector3(0, 1.15, 0) + dir * 0.7, {"dir": dir})
		notify_cast(t)

	## League cone decal (enemy-colored variant when Miss Fortune is hostile to the local player); stopped in channel_end.
	func _cone_visual(m, pos: Vector3, dir: Vector3, _dur: float) -> LolVfx:
		var nm := "MissFortune_Base_R_Indicator_Enemy" if FX.is_enemy_of_player(owner) else "MissFortune_Base_R_Indicator"
		return LolVfx.spawn(m, nm, pos, {"dir": dir, "loop": true, "height": 0.05})

	func channel_tick(dt: float, ch: Dictionary) -> void:
		var o = owner
		if o.dead or int(ch.get("token", -1)) != _token:
			o.interrupt_channel(true)
			return
		# a player's move order cancels the channel (League behaviour)
		if not o.is_bot and o.moving and o.cmd == Unit.Cmd.MOVE:
			o.interrupt_channel(true)
			return
		o.face_toward(o.global_position + ch.dir, dt)
		# League (V13.3): the cone follows Miss Fortune if she is displaced
		if _cone != null and is_instance_valid(_cone):
			_cone.global_position = o.global_position + Vector3(0, 0.05, 0)
		ch.acc = minf(ch.acc + dt, ch.interval * MAX_WAVES_PER_TICK)
		var fired := 0
		while ch.acc >= ch.interval and ch.left > 0 and fired < MAX_WAVES_PER_TICK:
			ch.acc -= ch.interval
			ch.left -= 1
			ch.n += 1
			fired += 1
			_wave(ch)
			# a wave can kill / interrupt (on-kill effects, Collector): stop if the channel is gone
			if o.dead or not is_same(o.channel, ch):
				return

	## Safety net: the channel was replaced or dropped without channel_end (cone decal, disarm left behind).
	func on_tick(_dt: float) -> void:
		var o = owner
		if _cone == null and not o.channel_disarm:
			return
		var ch: Dictionary = o.channel
		if ch.is_empty() or ch.get("ability") != self:
			if _cone != null or o.channel_disarm:
				_cleanup()

	func _wave(ch: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var dir: Vector3 = ch.dir
		var origin: Vector3 = o.global_position
		var len_u := cast_range
		var dmg := wave_damage()
		var crit: bool = G.rng.randf() < o.stats.crit_chance
		if crit:
			dmg *= 1.0 + dv("CritDamageMultiplier", 0.3) * (o.stats.crit_damage - 1.0)
		var self_ref := self
		var targets: Array = K.enemies_cone(self, origin, dir, len_u, ANGLE)
		# each target is hit once per wave when the bullets (2000 u/s) reach it; bullets already fired still land
		# after the channel ends. Bounded: one timer per target per wave, no re-scheduling.
		var wr := weakref(o)
		for u in targets:
			var delay: float = clampf(G.flat_dist(origin, u.global_position) / 20.0, 0.0, 1.0)
			var ur := weakref(u)   # a Unit captured directly would make the timer lambda error out once it is freed
			m.after(delay, func():
				var tu = ur.get_ref()
				if wr.get_ref() != null and tu != null and not tu.dead:
					self_ref.hit(tu, dmg, G.DmgType.PHYSICAL, {"tag": "r", "is_aoe": true, "is_crit": crit}))
		# visuals: alternate guns, a fan of tracer rounds
		var side := Vector3(-dir.z, 0, dir.x)
		var gun := side * (0.35 if ch.n % 2 == 0 else -0.35)
		var muzzle: Vector3 = origin + Vector3(0, 1.15, 0) + dir * 0.7 + gun
		LolVfx.spawn(m, "MissFortune_Base_R_MuzzleFlash_Cas", muzzle, {"dir": dir})
		var half := deg_to_rad(ANGLE * 0.5)
		var count := 6
		for j in count:
			var a := lerpf(-half, half, (float(j) + G.rng.randf()) / float(count))
			var bd := dir.rotated(Vector3.UP, a)
			# League bullet wave: a third of the rounds use the full tracer (trail / glow), the rest the light round
			var mi := K.line_missile(self, muzzle, bd, 2000.0 + G.rng.randf_range(-150.0, 150.0), len_u, {
				"width": 10.0, "lol": "MissFortune_Base_R_mis_child_01" if j % 3 == 0 else "MissFortune_Base_R_mis", "height": 1.15})
			mi.collides = false
		if m.camera_rig != null and o == G.player:
			m.camera_rig.shake(0.06)

	func channel_end(_ch: Dictionary, _interrupted: bool) -> void:
		_token += 1
		_cleanup()

	func _cleanup() -> void:
		var o = owner
		o.channel_disarm = false
		if o.anim_lock > 0.0 and o.channel.is_empty():
			o.anim_lock = 0.0
		if _cone != null and is_instance_valid(_cone):
			_cone.stop()
		_cone = null

	## Enemy champions inside the cone toward `dir`.
	func count_in_cone(ctx, dir: Vector3, lead: float) -> Array:
		var o = owner
		var out := []
		var half := deg_to_rad(ANGLE * 0.5)
		var rng := cast_range * G.U - 1.0
		for e in ctx.enemies:
			var p: Vector3 = ctx.predict(e, lead)
			var to := G.flat(p - o.global_position)
			var d := to.length()
			if d > rng or d < 0.1:
				continue
			if dir.angle_to(to / d) <= half + atan2(e.radius, d) * 0.5:
				out.append(e)
		return out

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		if ctx.enemies.is_empty():
			return skip()
		var best_dir := Vector3.ZERO
		var best: Array = []
		var best_s := -INF
		var dirs: Array = []
		for e in ctx.enemies:
			if G.flat_dist(o.global_position, e.global_position) < cast_range * G.U:
				dirs.append(G.flat_dir(o.global_position, ctx.predict(e, 0.6)))
		for i in dirs.size():
			for j in range(i + 1, dirs.size()):
				var avg: Vector3 = (dirs[i] + dirs[j])
				if avg.length() > 0.5:
					dirs.append(avg.normalized())
		for d in dirs:
			var inside := count_in_cone(ctx, d, 0.6)
			var s := inside.size() * 10.0
			for e in inside:
				s += (1.0 - e.hp_ratio()) * 3.0
			if s > best_s:
				best_s = s
				best = inside
				best_dir = d
		if best.is_empty():
			return skip()
		var total := 0.0
		var waves := dv("BaseWaves", 14.0)
		var lone: Unit = best[0]
		total = wave_damage() * waves * 0.6 * Combat.resist_multiplier(lone.stats.armor, o, true)
		# divers on top of us: don't plant ourselves unless it's a big hit
		var divers := 0
		for e in ctx.enemies:
			if o.edge_dist(e) < 2.0 and e.stats.attack_range < 300.0:
				divers += 1
		if best.size() >= 3 or (best.size() >= 2 and divers == 0) or (best.size() >= 2 and o.hp_ratio() > 0.5):
			return {"pos": o.global_position + best_dir * 5.0, "dir": best_dir, "unit": null}
		if best.size() == 1 and ctx.mode == "fight" and divers == 0 and total >= lone.hp + lone.total_shield() \
				and ((lone.cc & Buff.IMMOBILIZE) != 0 or lone.stats.slow > 0.2 or G.flat_dist(o.global_position, lone.global_position) < 8.0):
			return {"pos": o.global_position + best_dir * 5.0, "dir": best_dir, "unit": null}
		return skip()
