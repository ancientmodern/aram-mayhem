extends ChampionKit
## Leona, the Radiant Dawn.

const SUN := Color(1.0, 0.8, 0.3)
const HOLD := {"hold": true}


func build_kit() -> void:
	c.attack_missile_speed = 0.0
	c.attack_color = SUN
	c.role = "tank"
	c.level_order = "EQWWWRWEWEREEQQRQQ"
	var pd: Dictionary = spell(str(c.data.get("passive", "LeonaSunlightPassive"))).get("data_values", {})
	c.passive = Sunlight.new(pd)
	c.add_effect(c.passive)
	c.abilities[0] = init_ability(ShieldOfDawn.new(), "Q")
	c.abilities[1] = init_ability(Eclipse.new(), "W")
	c.abilities[2] = init_ability(ZenithBlade.new(), "E")
	c.abilities[3] = init_ability(SolarFlare.new(), "R")
	# Q is an instant self-buff (attack reset) in live
	c.abilities[0].cast_time = 0.0
	c.abilities[0].anim = ""
	c.abilities[2].cast_range = 875.0
	c.abilities[3].cast_time = 0.25
	c.add_effect(QAttackHook.new(c.abilities[0]))
	# [anim-events] the sword and shield flames are her skin's idleParticlesEffects (attached by Unit.anim_ev)


func ai_tuning() -> Dictionary:
	return {"aggression": 0.8}


## Match time of the last Shield of Dawn hit: its basic attack impact is replaced by Leona_Base_Q_tar.
var q_hit_time := -1.0


## League VFX mapping (LolVfx.champ_fx). "" disables a key that the kit spawns itself.
func vfx_map() -> Dictionary:
	var q_hit: bool = c != null and c.match_ref != null and c.match_ref.time == q_hit_time
	return {
		"BA_tar": "" if q_hit else "Leona_Base_BA_hit",
		"BA_crit_tar": "" if q_hit else "Leona_Base_BA_hit",
		"Q_cas": "",
		"Q_tar": "",
		"W_cas": "",
		"W_tar": "Leona_Base_W_tar",
		"E_cas": "",
		"E_mis": "Leona_Base_E_mis_weapon",
		"E_tar": "Leona_Base_E_tar",
		"R_cas": "Leona_Base_R_cas",
		"R_tar": "Leona_Base_R_tar",
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

	## Enemy-team (red) variant when `u` is not on the local player's team.
	static func hostile(u) -> bool:
		return G.player != null and is_instance_valid(G.player) and u != null and u.team != G.player.team


## Bot AI returns HOLD to deliberately skip a cast ({} would fall back to BotBrain.default_consider).
class KAbility extends Ability:
	func try_cast(t: Dictionary) -> bool:
		if t.get("hold", false):
			return false
		return super.try_cast(t)


# ===================================================================== helpers
class LUtil:
	static func mark(leona, target) -> void:
		var p = leona.passive
		if p != null and p.has_method("apply_mark"):
			p.apply_mark(target)

	static func shake(o, pos: Vector3, amount: float) -> void:
		var m = o.match_ref
		if m != null and m.camera_rig != null and G.player != null and G.flat_dist(G.player.global_position, pos) < 14.0:
			m.camera_rig.shake(amount)

	static func immobile(u) -> bool:
		return (u.cc & Buff.IMMOBILIZE) != 0

	## Exported clip name for a logical clip like "spell2_run" ("" if missing).
	static func find_clip(o, logical: String) -> String:
		if o.anim_player == null:
			return ""
		for an in o.anim_player.get_animation_list():
			if Assets._strip_prefix(String(an).to_lower()) == logical:
				return String(an)
		return ""


# ===================================================================== passive
class Sunlight extends Effect:
	var data := {}

	func _init(pd: Dictionary = {}) -> void:
		data = pd
		id = "leona_passive"
		display_name = "Sunlight"

	func damage() -> float:
		return 24.0 + 8.0 * owner.level

	func apply_mark(target) -> void:
		if target == null or not is_instance_valid(target) or target.dead or target.team == owner.team:
			return
		if target.kind in [G.Kind.TURRET, G.Kind.INHIBITOR, G.Kind.NEXUS]:
			return
		var dur: float = float(data.get("MarkDuration", 1.5))
		var ex = target.find_buff("leona_sunlight")
		if ex != null:
			ex.remaining = dur
			ex.duration = dur
			ex.leona = owner
			# restart the League sun tag (its single particle is shorter than a chain of refreshes)
			if ex.vfx != null and is_instance_valid(ex.vfx):
				ex.vfx.queue_free()
			ex.vfx = _mark_fx(target)
			return
		var b := SunlightMark.new()
		b.duration = dur
		b.remaining = dur
		b.leona = owner
		b.icon = icon
		b.vfx = _mark_fx(target)
		target.add_buff(b, owner)

	func _mark_fx(target) -> Node3D:
		var nm := "Leona_Base_P_tar_buf_champ" if target.kind == G.Kind.CHAMPION else "Leona_Base_P_tar_buf"
		return LolVfx.attach(target, nm, {"loop": true, "height": target.height * 0.5})

	func on_tick(u, _dt: float) -> void:
		if u.is_bot and u.ability_points > 0:
			u.auto_level_abilities()


## Sunlight debuff: the next damage from another allied champion detonates it.
## FxBuff: the sun tag vanishes the moment the mark is consumed / expires.
class SunlightMark extends K.FxBuff:
	var leona = null

	func _init() -> void:
		id = "leona_sunlight"
		display_name = "Sunlight"
		is_debuff = true

	func on_damage_taken(info) -> void:
		if removed or leona == null or not is_instance_valid(leona):
			return
		var src = info.source
		if src == null or not is_instance_valid(src) or src == leona or info.tag == "sunlight":
			return
		if src.kind != G.Kind.CHAMPION or src.team != leona.team:
			return
		removed = true
		var dmg: float = leona.passive.damage() if leona.passive != null and leona.passive.has_method("damage") else 24.0 + 8.0 * leona.level
		Combat.deal(leona, owner, dmg, G.DmgType.MAGIC, {"is_proc": true, "tag": "sunlight"})
		var m = owner.match_ref
		if m != null:
			LolVfx.spawn(m, "Leona_Base_P_tar_hit", owner.global_position + Vector3(0, owner.height * 0.5, 0))


# ===================================================================== Q
class ShieldOfDawn extends KAbility:
	var empowered_until := -1.0
	var fx: Node3D = null

	func _init() -> void:
		target_type = Target.NONE
		indicator = Ind.NONE
		cast_range = 0.0
		cast_time = 0.0
		anim = ""
		resets_attack = true

	func make_target(_world_pos: Vector3, _hovered = null) -> Dictionary:
		return {"pos": owner.global_position + owner.facing, "dir": owner.facing, "unit": null}

	func window() -> float:
		return 6.0

	func execute(t: Dictionary) -> void:
		var o = owner
		empowered_until = o.match_ref.time + window()
		_clear_fx()
		# League: the radiant shield glow for the empowered window
		fx = K.attach_fx(o, {"lol": "Leona_Base_Q_cas", "bone": "BUFFBONE_CSTM_SHIELD_MID"})
		notify_cast(t)

	func is_empowered() -> bool:
		return owner.match_ref != null and owner.match_ref.time < empowered_until

	func _clear_fx() -> void:
		LFx.kill(fx, 0.2)
		fx = null

	func consume(target) -> void:
		var o = owner
		empowered_until = -1.0
		_clear_fx()
		hit(target, dv("BaseDamage") + 0.3 * ap(), G.DmgType.MAGIC, {"tag": "q"})
		K.stun(target, dv("StunDuration", 1.0), o)
		LUtil.mark(o, target)
		var m = o.match_ref
		var gp: Vector3 = target.global_position
		# League Q_tar carries ground sigils: spawn it at the target's feet
		LolVfx.spawn(m, "Leona_Base_Q_tar", gp, {"dir": G.flat_dir(o.global_position, gp)})
		LUtil.shake(o, gp, 0.2)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		if is_empowered() or not o.dash.is_empty():
			return HOLD
		var t: Unit = ctx.focus
		if t == null or not is_instance_valid(t) or t.dead:
			t = ctx.best_enemy_in_range(o.attack_range_m() + 1.5)
		if t == null or t.has_cc_immunity():
			return HOLD
		if o.edge_dist(t) <= o.attack_range_m() + 1.2:
			return make_target(t.global_position)
		return HOLD


## Empowered Shield of Dawn attack (and the shield-bash animation during its windup).
class QAttackHook extends Effect:
	var q = null
	var played := false

	func _init(p_q) -> void:
		q = p_q
		id = "leona_q_hook"
		hidden = true

	## Effects don't tick while dead: drop the empowered shield (and its looping glow) on death.
	func on_death(_killer) -> void:
		q.empowered_until = -1.0
		q._clear_fx()

	func on_tick(u, _dt: float) -> void:
		if q.fx != null and not q.is_empowered():
			q._clear_fx()
		if u.windup_timer < 0.0:
			played = false
			return
		if not played and q.is_empowered() and u.has_anim("spell1"):
			played = true
			u.play_anim("spell1", 1.0, 0.05, u.windup_timer + 0.35)
			u.anim_lock = u.windup_timer + 0.35

	## The empowered hit's generic basic attack impact is replaced by Leona_Base_Q_tar (see vfx_map).
	func on_pre_damage_dealt(info) -> void:
		var t = info.target
		if info.is_attack and q != null and q.is_empowered() and t != null and is_instance_valid(t) \
				and not (t.kind in [G.Kind.TURRET, G.Kind.INHIBITOR, G.Kind.NEXUS]) and owner.match_ref != null:
			owner.kit.q_hit_time = owner.match_ref.time

	func on_attack_hit(target, _info) -> void:
		if q == null or not q.is_empowered() or target == null or not is_instance_valid(target) or target.dead:
			return
		if target.kind in [G.Kind.TURRET, G.Kind.INHIBITOR, G.Kind.NEXUS]:
			return
		q.consume(target)


# ===================================================================== W
class Eclipse extends KAbility:
	func _init() -> void:
		target_type = Target.NONE
		indicator = Ind.CIRCLE
		ind_radius = 450.0
		cast_range = 0.0
		cast_time = 0.0
		anim = "spell2"
		anim_lock = 0.45

	func make_target(_world_pos: Vector3, _hovered = null) -> Dictionary:
		return {"pos": owner.global_position, "dir": owner.facing, "unit": null}

	func resist_stats() -> Dictionary:
		var o = owner
		var base := dv("ArmorBaseBonus", 20.0)
		return {"armor": base + 0.2 * o.stats.bonus_armor, "mr": dv("MRBaseBonus", 20.0) + 0.2 * o.stats.bonus_mr}

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var dur := dv("ArmorMRDuration", 3.0)
		var b := EclipseBuff.new()
		b.duration = dur
		b.remaining = dur
		b.stats = resist_stats()
		b.flat = dv("FlatDamageReduction", 8.0)
		b.cap = dv("FlatDamageReductionMax", 0.5)
		b.icon = icon
		# League: the eclipse (sun disc, corona, rays) around Leona while the stance lasts
		b.vfx = K.attach_fx(o, {"lol": "Leona_Base_W_buf_1", "height": 1.1})
		o.remove_buffs_by_id("leona_w")
		o.add_buff(b, o)
		_set_stance(true)
		var self_ref := self
		m.after(dur, func():
			if is_instance_valid(o):
				self_ref._detonate())
		notify_cast(t)

	func _set_stance(on: bool) -> void:
		var o = owner
		if not o.has_meta("leona_anim_backup"):
			o.set_meta("leona_anim_backup", {"idle": o.anim_map.get("idle", []), "run": o.anim_map.get("run", [])})
		var bk: Dictionary = o.get_meta("leona_anim_backup")
		if on:
			var idle_clip: String = LUtil.find_clip(o, "spell2_idle")
			var run_clip: String = LUtil.find_clip(o, "spell2_run")
			if idle_clip != "":
				o.anim_map["idle"] = [idle_clip]
			if run_clip != "":
				o.anim_map["run"] = [run_clip]
		else:
			o.anim_map["idle"] = bk.idle
			o.anim_map["run"] = bk.run
		o.cur_anim = ""

	func _detonate() -> void:
		var o = owner
		_set_stance(false)
		if o.dead:
			return
		var m = o.match_ref
		var dmg := dv("ExplosionBaseDamage") + dv("APRatio", 0.4) * ap()
		var hits := K.enemies_circle(self, o.global_position, ind_radius)
		for u in hits:
			hit(u, dmg, G.DmgType.MAGIC, {"is_aoe": true, "tag": "w"})
			LUtil.mark(o, u)
		var gp: Vector3 = o.global_position
		# League: solar detonation (the "fail" variant when nobody was hit); W_tar on each target via mapping
		LolVfx.spawn(m, "Leona_Base_W_cas_fail" if hits.is_empty() else "Leona_Base_W_cas_hit", gp, {"dir": o.facing})
		LUtil.shake(o, gp, 0.15)
		if not hits.is_empty():
			var dur := dv("ArmorMRDuration", 3.0)
			var kb := K.buff(o, "leona_w_keep", dur, resist_stats(), o, {"name": "Eclipse", "icon": icon})
			if kb != null and (kb.vfx == null or not is_instance_valid(kb.vfx)):
				kb.vfx = K.attach_fx(o, {"lol": "Leona_Base_W_buf_2", "height": 1.1})

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var r := ind_radius * G.U
		if ctx.count_enemies_near(o.global_position, r * 0.9) >= 1 and (ctx.mode == "fight" or ctx.in_danger()):
			return make_target(o.global_position)
		# soak while diving in with E / walking into a fight
		if ctx.mode == "fight" and ctx.focus != null and G.flat_dist(o.global_position, ctx.focus.global_position) < 8.0 and o.hp_ratio() < 0.9:
			return make_target(o.global_position)
		if ctx.in_danger():
			return make_target(o.global_position)
		return HOLD


class EclipseBuff extends K.FxBuff:
	var flat := 8.0
	var cap := 0.5

	func _init() -> void:
		id = "leona_w"
		display_name = "Eclipse"

	func on_pre_damage_taken(info) -> void:
		if info.amount <= 0.0 or info.type == G.DmgType.TRUE:
			return
		var resist: float = owner.stats.armor if info.type == G.DmgType.PHYSICAL else owner.stats.mr
		var k := Combat.resist_multiplier(resist, info.source, info.type == G.DmgType.PHYSICAL)
		# flat reduction applies after mitigation: convert to a pre-mitigation amount
		info.amount -= minf(flat / maxf(k, 0.05), info.amount * cap)


# ===================================================================== E
class ZenithBlade extends KAbility:
	const TRAVEL := 900.0

	func _init() -> void:
		target_type = Target.DIRECTION
		indicator = Ind.LINE
		ind_width = 140.0
		cast_range = 875.0
		cast_time = 0.25
		anim = "spell3"
		anim_lock = 0.45

	func is_dash() -> bool:
		return true

	func execute(t: Dictionary) -> void:
		var o = owner
		var dir: Vector3 = t.dir
		var dmg := dv("BaseDamage") + 0.4 * ap()
		var root := dv("RootDuration", 0.5)
		var state := {"last": null}
		var self_ref := self
		var on_hit := func(_mm, u):
			self_ref.hit(u, dmg, G.DmgType.MAGIC, {"tag": "e"})
			LUtil.mark(o, u)
			if u.kind == G.Kind.CHAMPION:
				state.last = u
		var on_end := func(_mm, _pos):
			var tgt = state.last
			if tgt == null or not is_instance_valid(tgt) or tgt.dead or not is_instance_valid(o) or o.dead:
				return
			self_ref._dash_to(tgt, root)
		K.line_missile(self, K.cast_pos(o, 1.0), dir, 2000.0, TRAVEL, {
			"width": 70.0, "pierce": true, "lol": "Leona_Base_E_mis_weapon", "on_hit": on_hit, "on_end": on_end,
		})
		notify_cast(t)

	func _dash_to(tgt, root: float) -> void:
		var o = owner
		var m = o.match_ref
		var d := G.flat_dist(o.global_position, tgt.global_position)
		var spd := maxf(22.0, d / 0.3)
		var travel := maxf(0.0, d - o.radius - tgt.radius) / spd
		K.root(tgt, root + travel, o, SUN)
		if (o.cc & (Buff.BLOCK_MOVE | Buff.CC.GROUNDED)) != 0:
			return
		var dest: Vector3 = tgt.global_position - G.flat_dir(o.global_position, tgt.global_position) * (o.radius + tgt.radius * 0.8)
		# League: Zenith dash streak, solar flare on arrival
		var trail := LolVfx.attach(o, "Leona_Base_E_mis_dash", {"loop": true, "dir": G.flat_dir(o.global_position, dest)})
		K.stop_later(m, travel + 0.05, trail)
		o.start_dash(dest, {"speed": spd, "anim": "spell3", "on_arrive": func(_u):
			LFx.stop(trail)
			LolVfx.attach(o, "Leona_Base_E_cas_arrive", {"height": 1.0})})

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		if ctx.mode == "retreat" or not o.dash.is_empty():
			return HOLD
		var rng := TRAVEL * G.U * 0.93
		var t: Unit = null
		var best_s := -INF
		for e in ctx.enemies:
			var d := G.flat_dist(o.global_position, e.global_position)
			if d > rng or d < o.attack_range_m() + 1.0 or e.has_cc_immunity():
				continue
			if ctx._under_enemy_turret(e.global_position) and e.hp_ratio() > 0.25:
				continue
			var s: float = (1.0 - e.hp_ratio()) * 2.0 - d * 0.1 + (1.0 if e == ctx.focus else 0.0) + (0.8 if e.stats.attack_range > 300.0 else 0.0)
			if s > best_s:
				best_s = s
				t = e
		if t == null:
			return HOLD
		var support := 0
		for a in ctx.allies:
			if G.flat_dist(a.global_position, t.global_position) < 11.0:
				support += 1
		var enemies_there: int = ctx.count_enemies_near(t.global_position, 7.0)
		if not (ctx.mode == "fight" or support >= 1):
			return HOLD
		if o.hp_ratio() < 0.35 and t.hp_ratio() > 0.2:
			return HOLD
		if enemies_there > support + 2 and t.hp_ratio() > 0.3:
			return HOLD
		var aim: Vector3 = ctx.predict(t, cast_time + G.flat_dist(o.global_position, t.global_position) / 20.0)
		return ctx.aim_at(aim, self)


# ===================================================================== R
class SolarFlare extends KAbility:
	## League (wiki Solar Flare): hitbox 325 outer / 175 epicenter; the cast indicator draws 300 / 120 (castRadius
	## 120, castRadiusSecondary 300 in the data) but "the actual hitbox radii are larger than those values".
	const INNER := 175.0

	func _init() -> void:
		target_type = Target.POINT
		indicator = Ind.CIRCLE
		ind_radius = 325.0
		cast_range = 1200.0
		cast_time = 0.25
		anim = "spell4"
		anim_lock = 0.7

	func delay() -> float:
		return 0.625

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var pos: Vector3 = t.pos
		var R := ind_radius * G.U
		var dl := delay()
		var dmg := dv("ExplosionBaseDamage") + dv("ExplosionAPRatio", 0.8) * ap()
		var cc := dv("CCDuration", 1.75)
		var slow := dv("SlowPercent", 80.0) / 100.0
		var self_ref := self
		# League: the sword glows (R_buf) through the cast animation
		var glow := K.attach_fx(o, {"lol": "Leona_Base_R_buf", "bone": "BUFFBONE_GLB_WEAPON_1"})
		K.stop_later(m, 0.9, glow, true)
		# League telegraph: focused sun + outer slow ring / inner stun ring (red for the enemy team)
		LolVfx.spawn(m, "Leona_Base_R_hit_aoe_red" if LFx.hostile(o) else "Leona_Base_R_hit_aoe_green", pos, {"dir": G.flat_dir(o.global_position, pos), "height": 0.05})
		m.after(dl, func():
			if not is_instance_valid(o):
				return
			self_ref._strike(pos, R, dmg, cc, slow))
		notify_cast(t)

	func _strike(pos: Vector3, _r: float, dmg: float, cc: float, slow: float) -> void:
		var o = owner
		var m = o.match_ref
		for u in K.enemies_circle(self, pos, ind_radius):
			hit(u, dmg, G.DmgType.MAGIC, {"is_aoe": true, "tag": "r"})
			LUtil.mark(o, u)
			if G.flat_dist(pos, u.global_position) <= INNER * G.U + u.radius:
				K.stun(u, cc, o)
			else:
				K.slow(u, slow, cc, o, false, "leona_r_slow")
		# League: the solar flare impact (R_tar on each target via mapping)
		LolVfx.spawn(m, "Leona_Base_R_hit_impact", pos, {"dir": G.flat_dir(o.global_position, pos)})
		LUtil.shake(o, pos, 0.45)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var p: Vector3 = o.global_position
		var rng := range_m()
		var R := ind_radius * G.U
		var lead := cast_time + delay()
		# 1) multi-champion flare (center on the group)
		var best_n := 0
		var best := Vector3.INF
		for e in ctx.enemies:
			if G.flat_dist(p, e.global_position) > rng + R * 0.5:
				continue
			var c: Vector3 = ctx.predict(e, lead)
			var n := 0
			for e2 in ctx.enemies:
				if G.flat_dist(c, ctx.predict(e2, lead)) <= R * 0.85 + e2.radius:
					n += 1
			if n > best_n:
				best_n = n
				best = c
		if best_n >= 2 and G.flat_dist(p, best) <= rng + R * 0.3:
			return make_target(best, null)
		if ctx.mode != "fight" or ctx.focus == null:
			return HOLD
		var f: Unit = ctx.focus
		if f.has_cc_immunity() or G.flat_dist(p, f.global_position) > rng:
			return HOLD
		# 2) chain CC after E/Q, or open on a target the team can follow up on
		var e_ab = o.abilities[2]
		var q_ab = o.abilities[0]
		var e_down: bool = e_ab == null or e_ab.cast_block_reason() != ""
		var chain: bool = LUtil.immobile(f) and f.hp_ratio() > 0.2 and (o.abilities[0].is_empowered() == false)
		var allies_near := 0
		for a in ctx.allies:
			if G.flat_dist(a.global_position, f.global_position) < 9.0:
				allies_near += 1
		if chain and allies_near >= 1:
			return make_target(f.global_position, null)
		if e_down and not LUtil.immobile(f) and allies_near >= 1 and f.hp_ratio() > 0.25 and q_ab != null and not q_ab.is_empowered():
			return make_target(ctx.predict(f, lead), null)
		# 3) peel for a diven ally
		for a in ctx.allies:
			if a.hp_ratio() < 0.4:
				var threat: int = ctx.count_enemies_near(a.global_position, 3.5)
				if threat >= 1 and G.flat_dist(p, a.global_position) < rng:
					return make_target(a.global_position, null)
		return HOLD
