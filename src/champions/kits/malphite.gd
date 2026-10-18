extends ChampionKit
## Malphite, Shard of the Monolith.

const AMBER := Color(1.0, 0.62, 0.22)


func build_kit() -> void:
	c.attack_missile_speed = 0.0
	c.attack_color = AMBER
	c.role = "tank"
	c.level_order = "QEWQQRQEQEREEWWRWW"
	var p := GraniteShield.new()
	c.passive = p
	c.add_effect(p)
	c.abilities[0] = init_ability(SeismicShard.new(), "Q")
	c.abilities[1] = init_ability(Thunderclap.new(), "W")
	c.abilities[2] = init_ability(GroundSlam.new(), "E")
	c.abilities[3] = init_ability(UnstoppableForce.new(), "R")
	c.abilities[3].anim = ""
	c.abilities[3].cast_time = 0.0
	c.add_effect(ThunderclapHook.new(c.abilities[1]))
	c.add_effect(BotLeveler.new())
	# [anim-events] the fist sweeps (BA_Sweep_01/02) are the Attack1/2 clips' particle events (layout bone, frame 5)



func ai_tuning() -> Dictionary:
	return {"aggression": 0.75}


## Match time of the last empowered Thunderclap hit: its basic attack impact becomes Malphite_Base_W_tar_1.
var w_hit_time := -1.0


## League VFX mapping (LolVfx.champ_fx). "" disables a key that the kit spawns itself.
func vfx_map() -> Dictionary:
	var w_hit: bool = c != null and c.match_ref != null and c.match_ref.time == w_hit_time
	return {
		"BA_tar": "Malphite_Base_W_tar_1" if w_hit else "Malphite_Base_BA_tar",
		"BA_crit_tar": "Malphite_Base_W_tar_1" if w_hit else "Malphite_Base_BA_tar_crit_01",
		"Q_cas": "",
		"Q_mis": "Malphite_Base_Q_mis",
		"Q_tar": "Malphite_Base_Q_tar",
		"W_cas": "",
		"W_tar": "Malphite_Base_W_tar_2",
		"E_cas": "",
		"E_tar": "Malphite_Base_E_tar_01",
		"R_cas": "",
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


# ===================================================================== helpers
## Bots never spend points after spawning (core gap): level abilities on their behalf.
class BotLeveler extends Effect:
	func _init() -> void:
		id = "kit_bot_leveler"
		hidden = true

	func on_tick(u, _dt: float) -> void:
		if u.is_bot and u.ability_points > 0:
			u.auto_level_abilities()


class MAbility extends Ability:
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


# ===================================================================== passive
class GraniteShield extends Effect:
	const SID := "malphite_granite"
	var last_hit := -100.0
	var was_active := false

	func _init() -> void:
		id = "malphite_passive"
		display_name = "Granite Shield"

	func now() -> float:
		return owner.match_ref.time if owner.match_ref != null else 0.0

	func recharge_time() -> float:
		var lv: int = owner.level
		return 8.0 if lv < 7 else (7.0 if lv < 13 else 6.0)

	func is_active() -> bool:
		for s in owner.shields:
			if s.id == SID:
				return true
		return false

	func hud_counter() -> String:
		if is_active():
			return ""
		var left := recharge_time() - (now() - last_hit)
		return str(int(ceil(left))) if left > 0.0 else ""

	## League: damage absorbed by Granite Shield itself does not restart the recharge timer.
	func on_damage_taken(info) -> void:
		if info.final > 0.0:
			last_hit = now()

	func on_respawn() -> void:
		last_hit = -100.0

	## The pending break effect must not stay on the corpse (shields are cleared on death).
	func on_death(_killer) -> void:
		was_active = false

	func on_tick(u, _dt: float) -> void:
		if u.dead:
			return
		var on := is_active()
		if not on and now() - last_hit >= recharge_time():
			Combat.shield(u, u, 0.1 * u.stats.max_hp, 1.0e6, {"id": SID})
			on = true
			if u.match_ref != null and u.model != null:
				LolVfx.attach(u, "Malphite_Base_P_ShieldRegen")
		if was_active and not on and u.match_ref != null:
			# shell shatters (P_shield_break carries a 100 s overlay emitter: cut it after the burst)
			var brk := LolVfx.attach(u, "Malphite_Base_P_shield_break", {"height": 1.0})
			u.match_ref.after(1.2, func(): LFx.kill(brk, 0.3))
		was_active = on


# ===================================================================== Q
class SeismicShard extends MAbility:
	func _init() -> void:
		target_type = Target.UNIT
		target_side = Side.ENEMY
		indicator = Ind.NONE
		cast_range = 625.0
		cast_time = 0.25
		anim = "spell2"
		anim_lock = 0.5

	func damage() -> float:
		return dv("BaseDamage") + 0.6 * ap()

	func execute(t: Dictionary) -> void:
		var o = owner
		var u = t.unit
		if u == null or not is_instance_valid(u) or u.dead:
			notify_cast(t)
			return
		var self_ref := self
		var dmg := damage()
		# League Malphite_Base_Q_mis (furrow + seismic shard) replaces the visual via the Q_mis mapping
		var mi := K.homing_missile(self, K.cast_pos(o, 1.2), u, 1200.0, func(_mm, tgt):
			self_ref._land(tgt, dmg), {"lol": "Malphite_Base_Q_mis", "height": 0.6})
		mi.on_move = func(mm, _dt):
			mm.height = 0.45 + absf(sin(mm.traveled * 1.15)) * 1.1
		notify_cast(t)

	func _land(tgt, dmg: float) -> void:
		var o = owner
		var m = o.match_ref
		if tgt == null or not is_instance_valid(tgt) or tgt.dead:
			return
		hit(tgt, dmg, G.DmgType.MAGIC, {"tag": "malph_q"})
		var pct := dv("SpeedSteal", 20.0) / 100.0
		var dur := dv("SlowDuration", 3.0)
		K.slow(tgt, pct, dur, o, false, "malph_q_slow")
		if not o.dead:
			K.haste(o, pct, dur, o, false, "malph_q_ms")
			# League: stolen speed flies back to Malphite, then his speed buff swirl (Q_tar via mapping)
			_return_shard(tgt.global_position + Vector3(0, tgt.height * 0.5, 0))
			var sb := LolVfx.attach(o, "Malphite_Base_Q_Speed_Buff", {"loop": true})
			m.after(dur, func(): LFx.stop(sb))

	## Visual-only Malphite_Base_Q_return_mis flying from the target back to Malphite.
	func _return_shard(from: Vector3) -> void:
		var m = owner.match_ref
		var lv := LolVfx.make("Malphite_Base_Q_return_mis", {"loop": true})
		if lv == null:
			return
		m.fx_root.add_child(lv)
		lv.global_position = from
		var o = owner
		var st := {"t": 0.0}
		var dur := 0.4
		m.add_ticker(dur + 0.05, func(dt):
			if not is_instance_valid(lv):
				return false
			st.t += dt
			var k: float = clampf(st.t / dur, 0.0, 1.0)
			var to: Vector3 = from
			if is_instance_valid(o):
				to = o.global_position + Vector3(0, 1.0, 0)
			var pos: Vector3 = from.lerp(to, k)
			var fd := Vector3(pos.x - lv.global_position.x, 0.0, pos.z - lv.global_position.z)
			lv.global_position = pos
			if fd.length_squared() > 0.0001:
				lv.look_at(pos + fd, Vector3.UP)
			if k >= 1.0:
				lv.detach_and_fade()
				return false
			return true)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var p: Vector3 = o.global_position
		var in_rng := func(u) -> bool:
			return valid_unit_target(u) and G.flat_dist(p, u.global_position) <= range_m() + o.radius + u.radius - 0.1
		if ctx.mode == "retreat":
			var chaser = null
			var cd := INF
			for e in ctx.enemies:
				var d := G.flat_dist(p, e.global_position)
				if in_rng.call(e) and d < cd:
					cd = d
					chaser = e
			if chaser != null:
				return {"unit": chaser, "pos": chaser.global_position}
			return skip()
		var t: Unit = ctx.best_enemy_in_range(range_m() + o.radius)
		if t != null and in_rng.call(t):
			if ctx.mode == "fight" or not o.stats.uses_mana or o.mana > o.stats.max_mana * 0.35:
				return {"unit": t, "pos": t.global_position}
		if ctx.enemies.is_empty() and o.mana > o.stats.max_mana * 0.75:
			var est: float = damage()
			for mn in ctx.enemy_minions:
				if in_rng.call(mn) and mn.hp < est * Combat.resist_multiplier(mn.stats.mr, o, false) and G.flat_dist(p, mn.global_position) > 2.5:
					return {"unit": mn, "pos": mn.global_position}
		return skip()


# ===================================================================== W
## League (wiki Thunderclap): the next basic attack within 6 s is empowered (+50 range, bonus damage, cone);
## basic attacks for the next 5 s (ThunderclapBuffDuration) after that hit also trigger the cone.
class Thunderclap extends MAbility:
	const EMPOWER_WINDOW := 6.0
	var empowered := false
	var empowered_until := -1.0
	var window_until := -1.0     ## aftershock (cone) window, starts when the empowered attack lands
	var fx: LolVfx = null
	var next_hit_fx := false

	func _init() -> void:
		target_type = Target.NONE
		indicator = Ind.NONE
		cast_range = 0.0
		cast_time = 0.0
		anim = "spell1"
		anim_lock = 0.3
		resets_attack = true

	func make_target(_world_pos: Vector3, _hovered = null) -> Dictionary:
		return self_target()

	func armor_bonus_pct() -> float:
		if level <= 0:
			return 0.0
		var pct := dv("BonusArmorPassive", 0.1)
		if owner.passive != null and owner.passive.is_active():
			pct *= dv("BonusArmorPassiveMultiplier", 3.0)
		return pct

	func bonus_damage() -> float:
		return dv("ThunderclapBaseDamage") + dv("ThunderclapBaseDamageAPRatio", 0.2) * ap() + dv("ThunderclapBaseDamageArmorRatio", 0.15) * owner.stats.armor

	func splash_damage() -> float:
		return dv("ThunderclapSplashDamage") + dv("ThunderclapSplashAP", 0.3) * ap() + dv("ThunderclapSplashArmor", 0.15) * owner.stats.armor

	func in_window() -> bool:
		return now() < window_until

	func is_empowered() -> bool:
		return empowered and now() < empowered_until

	## The empowered attack landed: open the aftershock window.
	func consume_empower() -> void:
		empowered = false
		window_until = now() + dv("ThunderclapBuffDuration", 5.0)
		owner.stats.mark_dirty()

	func execute(t: Dictionary) -> void:
		var o = owner
		empowered = true
		empowered_until = now() + EMPOWER_WINDOW
		window_until = -1.0
		o.stats.mark_dirty()
		# League: burning fists (the "next hit" variant until the empowered attack lands)
		LFx.kill(fx, 0.1)
		fx = LolVfx.attach(o, "Malphite_Base_W_buf_hands_NextHit", {"loop": true, "height": 1.5, "dir": o.facing})
		next_hit_fx = true
		notify_cast(t)

	func end_fx() -> void:
		LFx.kill(fx, 0.3)
		fx = null
		next_hit_fx = false

	## Empowered hit consumed: keep the plain burning-fists glow for the rest of the window.
	func on_empowered_hit() -> void:
		if not next_hit_fx or not in_window():
			return
		LFx.kill(fx, 0.1)
		fx = LolVfx.attach(owner, "Malphite_Base_W_buf_hands", {"loop": true, "height": 1.5, "dir": owner.facing})
		next_hit_fx = false

	func on_tick(_dt: float) -> void:
		if owner.dead and (empowered or window_until > now()):
			window_until = -1.0
			empowered_until = -1.0
		if empowered and not is_empowered():
			empowered = false
			owner.stats.mark_dirty()
		if fx != null and not empowered and not in_window():
			end_fx()

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		if is_empowered() or in_window():
			return skip()
		var f = ctx.focus
		if ctx.mode == "fight" and f != null and is_instance_valid(f) and o.in_attack_range(f, 0.4):
			if o.windup_timer < 0.0 and o.attack_timer > 0.12:
				return self_target()
		var at = o.attack_target
		if ctx.enemies.is_empty() and at != null and is_instance_valid(at) and at.kind == G.Kind.MINION and o.in_attack_range(at, 0.2) \
				and o.mana > o.stats.max_mana * 0.6 and ctx.count_enemies_near(at.global_position, 3.5, false) >= 3:
			return self_target()
		return skip()


class ThunderclapHook extends Effect:
	var w

	func _init(p_w) -> void:
		w = p_w
		id = "malph_w_hook"
		hidden = true

	func get_stat_mods() -> Dictionary:
		var d := {}
		var pct: float = w.armor_bonus_pct()
		if pct > 0.0:
			d["armor%"] = pct
		# League: the empowered Thunderclap attack has +50 range
		if w.is_empowered():
			d["range"] = 50.0
		return d

	func on_pre_damage_dealt(info) -> void:
		if info.is_attack and w.is_empowered() and info.target != null and info.tag == "":
			info.flat_bonus += w.bonus_damage()
			info.tag = "malph_w"
			# the generic basic attack impact shows Malphite_Base_W_tar_1 for this hit (see vfx_map)
			if owner.match_ref != null:
				owner.kit.w_hit_time = owner.match_ref.time
			w.consume_empower()

	func on_attack_hit(target, info) -> void:
		if info == null or target == null or not is_instance_valid(target):
			return
		var big: bool = info.tag == "malph_w"
		if not big and not w.in_window():
			return
		var o = owner
		var m = o.match_ref
		var origin: Vector3 = o.global_position
		var dir := G.flat_dir(origin, target.global_position)
		var reach: float = w.dv("ThunderClapSplashRange", 400.0)
		var len: float = G.flat_dist(origin, target.global_position) / G.U + reach
		var dmg: float = w.splash_damage()
		for u in K.enemies_cone(w, origin, dir, len, 70.0):
			if u == target:
				continue
			# splashed units get Malphite_Base_W_tar_2 through the W_tar mapping
			Combat.deal(o, u, dmg, G.DmgType.PHYSICAL, {"is_aoe": true, "is_proc": true, "tag": "malph_w_splash", "ability": w})
		# League: cleave shockwave along the cone; the empowered hit adds the Thunderclap crit sweeps
		LolVfx.spawn(m, "Malphite_Base_W_Cleave_Arc", origin, {"dir": dir, "height": 0.9})
		if big:
			LolVfx.spawn(m, "Malphite_Base_W_Crit_Sweeps", origin, {"dir": dir, "height": 0.9})
			LolVfx.spawn(m, "Malphite_Base_W_Cleave", target.global_position + Vector3(0, target.height * 0.5, 0), {"dir": dir})
			w.on_empowered_hit()
			if m.camera_rig != null and (o == G.player or target == G.player):
				m.camera_rig.shake(0.12)


# ===================================================================== E
class GroundSlam extends MAbility:
	func _init() -> void:
		target_type = Target.NONE
		indicator = Ind.CIRCLE
		ind_radius = 400.0
		cast_range = 0.0
		cast_time = 0.24
		anim = "spell3"
		anim_lock = 0.45

	func make_target(_world_pos: Vector3, _hovered = null) -> Dictionary:
		return self_target()

	func damage() -> float:
		return dv("BaseDamage") + 0.4 * owner.stats.armor + 0.6 * ap()

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var p: Vector3 = o.global_position
		var pct := dv("ASReduction", 30.0) / 100.0
		var dur := dv("Duration", 3.0)
		var dmg := damage()
		for u in K.enemies_circle(self, p, ind_radius):
			hit(u, dmg, G.DmgType.MAGIC, {"is_aoe": true, "tag": "malph_e"})
			if not u.dead:
				var ratio: float = maxf(0.1, float(u.stats.base.get("attack_speed_ratio", 0.625)))
				var delta: float = u.stats.attack_speed * pct / ratio
				var ab := K.buff(u, "malph_e_as", dur, {"as": -delta}, o, {"name": "Ground Slam", "debuff": true})
				# League: molten hands on the attack-speed-reduced target (E_tar_01 via mapping)
				if ab != null and (ab.vfx == null or not is_instance_valid(ab.vfx)):
					ab.vfx = LolVfx.attach(u, "Malphite_Base_E_tar_buf_hands", {"loop": true, "height": u.height * 0.5})
		# League: the slam (rock crater / pillar) and the ground shockwave
		# [anim-events] Malphite_Base_E_cas is the Spell3 clip's detached particle event (R hand, frame 8)
		LolVfx.spawn(m, "Malphite_Base_E_hit_aoe", p, {"dir": o.facing})
		if m.camera_rig != null and o == G.player:
			m.camera_rig.shake(0.15)
		notify_cast(t)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var p: Vector3 = o.global_position
		var r := ind_radius * G.U
		var champs := 0
		for e in ctx.enemies:
			if G.flat_dist(p, ctx.predict(e, cast_time)) <= r + e.radius * 0.5:
				champs += 1
		if champs >= 1:
			return self_target()
		if ctx.enemies.is_empty() and o.mana > o.stats.max_mana * 0.55 and ctx.count_enemies_near(p, r, false) >= 4:
			return self_target()
		return skip()


# ===================================================================== R
class UnstoppableForce extends MAbility:
	func _init() -> void:
		target_type = Target.POINT
		indicator = Ind.CIRCLE
		ind_radius = 325.0   # League effect radius (data castRadius 270 is the targeting reticle)
		cast_range = 1000.0
		cast_time = 0.0
		anim = ""
		anim_lock = 0.0

	func is_dash() -> bool:
		return true

	func damage() -> float:
		return dv("BaseDamage") + 0.9 * ap()

	func radius_m() -> float:
		return ind_radius * G.U

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var from: Vector3 = o.global_position
		var dest: Vector3 = t.pos
		if G.flat_dist(from, dest) > range_m():
			dest = from + G.flat_dir(from, dest) * range_m()
		var speed_u: float = 1500.0 + o.stats.move_speed   # League: 1500 + 100% move speed
		var dur: float = maxf(0.12, G.flat_dist(from, dest) / (speed_u * G.U))
		K.buff(o, "malph_r_unstoppable", dur + 0.15, {}, o, {"name": "Unstoppable Force", "cc": Buff.CC.UNSTOPPABLE, "hidden": true})
		var self_ref := self
		o.start_dash(dest, {"speed": speed_u * G.U, "height": 0.7, "on_arrive": func(_u): self_ref._impact()})
		o.play_anim("spell4", 1.0, 0.03, dur + 0.3)
		o.anim_lock = dur + 0.3
		# League: take-off dust and the unstoppable meteor trail for the charge
		var trail := LolVfx.attach(o, "Malphite_Base_R_cas_trail", {"loop": true, "dir": G.flat_dir(from, dest)})
		m.after(dur, func(): LFx.stop(trail))
		notify_cast(t)

	func _impact() -> void:
		var o = owner
		var m = o.match_ref
		var p: Vector3 = o.global_position
		var dmg := damage()
		var hits := K.enemies_circle(self, p, ind_radius)
		for u in hits:
			hit(u, dmg, G.DmgType.MAGIC, {"is_aoe": true, "tag": "malph_r"})
			if not u.dead:
				K.knockup(u, dv("KnockupDuration", 1.5), o)
			# League R_tar has a ground-flagged ball: spawn it at the unit's feet
			LolVfx.spawn(m, "Malphite_Base_R_tar", u.global_position, {"dir": G.flat_dir(p, u.global_position)})
		LolVfx.spawn(m, "Malphite_Base_R_hit_aoe", p, {"dir": o.facing})
		if m.camera_rig != null:
			var involved: bool = o == G.player or hits.has(G.player)
			m.camera_rig.shake(0.6 if involved else 0.25)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var p: Vector3 = o.global_position
		if ctx.enemies.is_empty():
			return skip()
		var r := radius_m()
		var preds := []
		for e in ctx.enemies:
			if G.flat_dist(p, e.global_position) <= range_m() + r + 2.0 and not e.has_cc_immunity():
				preds.append([e, ctx.predict(e, 0.35)])
		if preds.is_empty():
			return skip()
		var centers := []
		for i in preds.size():
			centers.append(preds[i][1])
			for j in range(i + 1, preds.size()):
				var a: Vector3 = preds[i][1]
				var b: Vector3 = preds[j][1]
				if a.distance_to(b) <= r * 2.0 + 1.0:
					centers.append((a + b) * 0.5)
		var best := Vector3.INF
		var best_s := -INF
		var dmg := damage()
		for cpos in centers:
			if G.flat_dist(p, cpos) > range_m():
				continue
			var n := 0
			var kill := false
			var hp_sum := 0.0
			for pr in preds:
				var e = pr[0]
				if G.flat_dist(cpos, pr[1]) <= r + e.radius * 0.8:
					n += 1
					hp_sum += e.hp_ratio()
					if dmg * Combat.resist_multiplier(e.stats.mr, o, false) >= e.hp + e.total_shield():
						kill = true
			if n == 0:
				continue
			if ctx._under_enemy_turret(cpos) and n < 3 and not kill:
				continue
			var ok: bool = n >= 2 or (kill and ctx.mode != "retreat")
			if not ok:
				continue
			var s := n * 10.0 + (5.0 if kill else 0.0) - hp_sum
			if s > best_s:
				best_s = s
				best = cpos
		if best == Vector3.INF:
			return skip()
		return make_target(best, null)
