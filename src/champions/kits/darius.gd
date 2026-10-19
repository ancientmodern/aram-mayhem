extends ChampionKit
## Darius, the Hand of Noxus.

const RED := Color(1.0, 0.12, 0.06)
const Q_INNER := 205.0     ## handle radius (units)
const Q_OUTER := 425.0     ## blade radius (units)
const Q_WINDUP := 0.75


func build_kit() -> void:
	c.attack_missile_speed = 0.0
	c.attack_color = RED
	c.role = "fighter"
	c.level_order = "QWEQQRQEQEREEWWRWW"
	var hemo := Hemorrhage.new()
	hemo.dvals = spell("DariusHemoMarker").get("data_values", {})
	c.passive = hemo
	c.add_effect(hemo)
	c.abilities[0] = init_ability(Decimate.new(), "Q")
	c.abilities[1] = init_ability(CripplingStrike.new(), "W")
	c.abilities[2] = init_ability(Apprehend.new(), "E")
	c.abilities[3] = init_ability(NoxianGuillotine.new(), "R")
	# the json cast times describe the internal sub-casts; these abilities drive their own timing
	for i in [0, 1, 3]:
		c.abilities[i].cast_time = 0.0
		c.abilities[i].anim = ""
	c.add_effect(WAttackHook.new(c.abilities[1]))
	c.add_effect(ApprehendPen.new(c.abilities[2]))
	c.add_effect(BotLeveler.new())



func ai_tuning() -> Dictionary:
	return {"aggression": 0.8}


## Match time of the last empowered W hit: its basic attack impact becomes darius_Base_W_tar.
var w_hit_time := -1.0


## League VFX mapping (LolVfx.champ_fx). "" disables a key that the kit spawns itself.
func vfx_map() -> Dictionary:
	var w_hit: bool = c != null and c.match_ref != null and c.match_ref.time == w_hit_time
	var ba := "Darius_Base_BA" if c == null or c.attack_count % 2 == 1 else "Darius_Base_BA2"
	return {
		"BA_tar": "darius_Base_W_tar" if w_hit else ba,
		"BA_crit_tar": "darius_Base_W_tar" if w_hit else "Darius_Base_BA_Crit",
		"Q_cas": "",
		"Q_tar": "",
		"W_cas": "",
		"W_tar": "",
		"E_cas": "darius_Base_E_weapon_trigger",
		"E_tar": "",
		"R_cas": "darius_Base_R_cast_axe",
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


## Base ability: `{"skip": true}` from ai_consider suppresses the generic bot fallback;
## nothing else can be cast during Decimate's wind-up.
class DAbility extends Ability:
	func try_cast(t: Dictionary) -> bool:
		if t.get("skip", false):
			return false
		return super.try_cast(t)

	func extra_block_reason() -> String:
		var ch: Dictionary = owner.channel
		if not ch.is_empty() and ch.ability != self and ch.ability is Decimate:
			return "casting"
		return ""

	func skip() -> Dictionary:
		return {"skip": true}

	func now() -> float:
		return owner.match_ref.time if owner.match_ref != null else 0.0


# ===================================================================== passive
class Hemorrhage extends Effect:
	var dvals := {}

	func _init() -> void:
		id = "darius_passive"
		display_name = "Hemorrhage"

	func val(n: String, d: float) -> float:
		return float(dvals.get(n, d))

	## Total bleed damage of one stack over its full duration.
	func per_stack_damage() -> float:
		var lv: float = owner.level
		return lerpf(13.0, 30.0, (lv - 1.0) / 17.0) + 0.3 * owner.stats.bonus_ad

	## League DariusHemoMarker "NoxianMightBonusAD" (CommunityDragon darius.bin.json): 30 at level 1, +5 per level,
	## +10 per level from 11, +25 per level from 14 -> 30/35/.../75 (L10), 85, 95, 105, 130, 155, 180, 205, 230.
	func might_ad() -> float:
		var lv: int = owner.level
		return K.level_breakpoints(lv, 30.0, 5.0, [[11, 10.0], [14, 25.0]])

	func in_might() -> bool:
		return owner.has_buff("darius_might")

	func hud_counter() -> String:
		var b = owner.find_buff("darius_might")
		return str(int(ceil(b.remaining))) if b != null else ""

	func stacks_on(u) -> int:
		if u == null or not is_instance_valid(u):
			return 0
		var b = u.find_buff("darius_hemo", owner)
		return b.stacks if b != null else 0

	## Remaining bleed damage that will still tick on u.
	func pending_bleed(u) -> float:
		var b = u.find_buff("darius_hemo", owner)
		if b == null:
			return 0.0
		return per_stack_damage() * b.stacks * clampf(b.remaining / b.duration, 0.0, 1.0)

	func apply(u, n: int = 1) -> void:
		if u == null or not is_instance_valid(u) or u.dead:
			return
		if not (u.kind == G.Kind.CHAMPION or u.kind == G.Kind.MINION or u.kind == G.Kind.SUMMON):
			return
		if in_might():
			n = int(val("MaxStacks", 5.0))
		var b = u.find_buff("darius_hemo", owner)
		if b == null:
			var nb := HemoBuff.new("darius_hemo", val("BleedDuration", 5.0) + 0.02)
			nb.display_name = "Hemorrhage"
			nb.is_debuff = true
			nb.max_stacks = int(val("MaxStacks", 5.0))
			nb.tick_interval = 1.25
			nb.passive = self
			nb.stacks = 0
			b = u.add_buff(nb, owner)
			if b == null:
				return
		b.stacks = mini(b.max_stacks, b.stacks + n)
		b.remaining = b.duration
		b.update_fx()
		if b.stacks >= b.max_stacks and u.kind == G.Kind.CHAMPION:
			trigger_might()

	func trigger_might() -> void:
		var fresh := not in_might()
		K.buff(owner, "darius_might", val("BleedDuration", 5.0), {"ad": might_ad(), "size": 0.08}, owner,
				{"name": "Noxian Might", "icon": icon, "kill_fx": true})   # [vfx-leak] FxBuff: its effects die with the buff
		var mb = owner.find_buff("darius_might")
		if not fresh or mb == null:
			return
		var m = owner.match_ref
		# League: enrage nova, then the Noxian Might aura and glowing axe for the buff's duration
		LolVfx.spawn(m, "Darius_Base_P_nova", owner.global_position, {"dir": owner.facing})
		var aura := K.attach_fx(owner, {"lol": "Darius_Base_P_enraged", "height": 1.0})
		var axe := K.attach_fx(owner, {"lol": "Darius_Base_P_axe_tip", "bone": "BuffBone_Glb_Weapon_1"})
		var shl := K.attach_fx(owner, {"lol": "Darius_Base_P_enraged_shoulder_L", "bone": "L_Shoulder"})
		var shr := K.attach_fx(owner, {"lol": "Darius_Base_P_enraged_shoulder_R", "bone": "R_Shoulder"})
		if "extra_fx" in mb:
			for n in [aura, axe, shl, shr]:
				if n != null:
					mb.extra_fx.append(n)
		if m.camera_rig != null and owner == G.player:
			m.camera_rig.shake(0.2)

	func on_attack_hit(target, info) -> void:
		if info == null or info.cancelled:
			return
		apply(target, 1)


## FxBuff: the blood-drop counter disappears with the bleed (not seconds later).
class HemoBuff extends K.FxBuff:
	var passive = null
	var shown := 0

	func on_interval_tick(unit) -> void:
		var src = source
		if passive == null or src == null or not is_instance_valid(src) or unit.dead:
			return
		var dmg: float = passive.per_stack_damage() * stacks / 4.0
		Combat.deal(src, unit, dmg, G.DmgType.PHYSICAL, {"is_dot": true, "is_proc": true, "tag": "bleed"})
		if unit.match_ref != null and not unit.dead:
			LolVfx.spawn(unit.match_ref, "BloodSlash", unit.global_position + Vector3(0, unit.height * 0.5, 0))

	## League bleed counter (1-5 blood drops) over the target; minions use the smaller variant.
	func update_fx() -> void:
		var u = owner
		if u == null or not is_instance_valid(u):
			return
		var n: int = clampi(stacks, 1, 5)
		if n == shown and vfx != null and is_instance_valid(vfx):
			return
		if vfx != null and is_instance_valid(vfx):
			vfx.queue_free()
		shown = n
		var nm := "darius_Base_hemo_counter_0%d%s" % [n, "" if u.kind == G.Kind.CHAMPION else "Minion"]
		vfx = LolVfx.attach(u, nm, {"loop": true, "height": u.height + 0.45})
		# five stacks on a champion: the overhead max-stack icon (the Noxian Might trigger) joins the drops
		if n >= 5 and u.kind == G.Kind.CHAMPION and extra_fx.is_empty():
			var ic := K.attach_fx(u, {"lol": "darius_Base_passive_overhead_max_stack", "bone": "C_BuffBone_Glb_Overhead_Loc"})
			if ic != null:
				extra_fx.append(ic)


# ===================================================================== Q
class Decimate extends DAbility:
	var windup_fx: LolVfx = null
	var ring_fx: LolVfx = null

	func _init() -> void:
		target_type = Target.NONE
		indicator = Ind.CIRCLE
		ind_radius = Q_OUTER
		cast_range = 0.0
		cast_time = 0.0
		anim = ""
		anim_lock = 0.0

	func make_target(_world_pos: Vector3, _hovered = null) -> Dictionary:
		return {"pos": owner.global_position, "dir": owner.facing, "unit": null}

	func blade_damage() -> float:
		return dv("BaseDamage") + dv("TotalADRatio", 100.0) / 100.0 * ad()

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		o.stop_moving()
		o.cancel_windup()
		o.play_anim("spell1_in", 1.0, 0.05, Q_WINDUP)
		o.anim_lock = Q_WINDUP + 0.05
		start_channel(Q_WINDUP, {})
		o.channel_disarm = true
		# League telegraph: Q_Ring_Windup lasts exactly the wind-up; Q_Ring (built-in 0.75 s delay) is the swing.
		var p: Vector3 = o.global_position
		windup_fx = LolVfx.spawn(m, "Darius_Base_Q_Ring_Windup", p, {"dir": o.facing, "height": 0.08})
		ring_fx = LolVfx.spawn(m, "Darius_Base_Q_Ring", p, {"dir": o.facing, "height": 0.1})
		notify_cast(t)

	func channel_end(_ch: Dictionary, interrupted: bool) -> void:
		var o = owner
		o.channel_disarm = false
		if interrupted or o.dead:
			# cancel the pending swing ring (its emitters only start after the 0.75 s delay)
			LFx.kill(windup_fx, 0.05)
			LFx.kill(ring_fx, 0.05)
			windup_fx = null
			ring_fx = null
			o.anim_lock = 0.0
			return
		windup_fx = null
		ring_fx = null
		_swing()

	func _swing() -> void:
		var o = owner
		var m = o.match_ref
		var p: Vector3 = o.global_position
		o.play_anim("spell1", 1.0, 0.03)
		o.anim_lock = 0.5
		var blade := blade_damage()
		var handle := blade * dv("InnerCircleDamagePercent", 35.0) / 100.0
		var hemo = o.passive
		var champs := 0
		for u in K.enemies_circle(self, p, Q_OUTER):
			var d := G.flat_dist(p, u.global_position)
			var tp: Vector3 = u.global_position + Vector3(0, 1.0, 0)
			if d > Q_INNER * G.U:
				# full blade damage to minions too: League has no minion modifier on Decimate (wiki Decimate /
				# patch history; DariusCleave data has only BaseDamage/TotalADRatio/InnerCircleDamagePercent)
				var info := hit(u, blade, G.DmgType.PHYSICAL, {"is_aoe": true, "tag": "q_blade"})
				if not info.killed:
					hemo.apply(u, 1)
				if u.kind == G.Kind.CHAMPION:
					champs += 1
				LolVfx.spawn(m, "darius_Base_Q_tar", tp, {"dir": G.flat_dir(p, u.global_position)})
			else:
				hit(u, handle, G.DmgType.PHYSICAL, {"is_aoe": true, "tag": "q_handle"})
				LolVfx.spawn(m, "darius_Base_Q_tar_inner", tp, {"dir": G.flat_dir(p, u.global_position)})
		if champs > 0:
			var pct := minf(dv("MissingHealPercent", 51.0), dv("MissingHealthHeal", 17.0) * champs) / 100.0
			Combat.heal(o, o, (o.stats.max_hp - o.hp) * pct)
			LolVfx.attach(o, "Darius_Base_Q_Heal")
		# the swing itself is Darius_Base_Q_Ring, spawned at wind-up start with its built-in delay
		if m.camera_rig != null and o == G.player:
			m.camera_rig.shake(0.12)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var p: Vector3 = o.global_position
		var blade_n := 0
		var inside := 0
		for e in ctx.enemies:
			var pp: Vector3 = ctx.predict(e, Q_WINDUP * 0.5)
			var d := G.flat_dist(p, pp)
			if d <= Q_OUTER * G.U + e.radius * 0.3:
				inside += 1
				if d > Q_INNER * G.U + 0.15:
					blade_n += 1
		if blade_n >= 1 or inside >= 2:
			return {"pos": p}
		if inside >= 1 and (o.hp_ratio() < 0.5 or ctx.mode == "fight" and o.stats.uses_mana and o.mana > o.stats.max_mana * 0.7):
			return {"pos": p}
		if ctx.enemies.is_empty() and o.mana > o.stats.max_mana * 0.55:
			var n := 0
			for mn in ctx.enemy_minions:
				var d2 := G.flat_dist(p, mn.global_position)
				if d2 <= Q_OUTER * G.U and d2 > Q_INNER * G.U * 0.7:
					n += 1
			if n >= 3:
				return {"pos": p}
		return skip()


# ===================================================================== W
class CripplingStrike extends DAbility:
	var empowered_until := -1.0
	var saved_attack: Array = []
	var saved_crit: Array = []
	var fx: LolVfx = null

	func _init() -> void:
		target_type = Target.NONE
		indicator = Ind.NONE
		cast_time = 0.0
		cast_range = 0.0
		anim = ""
		anim_lock = 0.0
		resets_attack = true

	func make_target(_world_pos: Vector3, _hovered = null) -> Dictionary:
		return {"pos": owner.global_position, "dir": owner.facing, "unit": null}

	func execute(t: Dictionary) -> void:
		var o = owner
		if not is_empowered():
			var clip: String = o._raw_clip("spell2")
			if clip != "":
				saved_attack = o.anim_map.get("attack", []).duplicate()
				saved_crit = o.anim_map.get("crit", []).duplicate()
				o.anim_map["attack"] = [clip]
				o.anim_map["crit"] = [clip]
		empowered_until = now() + 4.0
		# League: charged axe glow until the empowered attack lands or the window ends
		LFx.kill(fx, 0.1)
		fx = K.attach_fx(o, {"lol": "darius_Base_W_weapon_01", "bone": "BuffBone_Glb_Weapon_1"})
		notify_cast(t)

	func is_empowered() -> bool:
		return empowered_until > 0.0 and now() < empowered_until

	func consume() -> void:
		var o = owner
		empowered_until = -1.0
		if not saved_attack.is_empty():
			o.anim_map["attack"] = saved_attack
			o.anim_map["crit"] = saved_crit if not saved_crit.is_empty() else saved_attack
			saved_attack = []
			saved_crit = []
		# W_weapon_01 has a 10000 s emitter: remove it explicitly
		LFx.kill(fx, 0.3)
		fx = null

	func on_tick(_dt: float) -> void:
		if empowered_until > 0.0 and now() >= empowered_until:
			consume()

	func damage_estimate() -> float:
		return dv("ADRatio", 1.4) * ad()

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		if is_empowered():
			return skip()
		var f = ctx.focus
		if ctx.mode == "fight" and f != null and is_instance_valid(f) and o.in_attack_range(f, 0.4):
			if o.windup_timer < 0.0 and o.attack_timer > 0.12:
				return {"pos": o.global_position}
			if f.hp_ratio() < 0.2:
				return {"pos": o.global_position}
		if ctx.mode == "retreat":
			return skip()
		if ctx.enemies.is_empty() and o.mana > o.stats.max_mana * 0.4 and o.attack_target != null and is_instance_valid(o.attack_target):
			var mn = o.attack_target
			if mn.kind == G.Kind.MINION and o.in_attack_range(mn, 0.2):
				var est: float = damage_estimate() * Combat.resist_multiplier(mn.stats.armor, o, true)
				if mn.hp < est and mn.hp > o.stats.ad * Combat.resist_multiplier(mn.stats.armor, o, true):
					return {"pos": o.global_position}
		return skip()


class WAttackHook extends Effect:
	var w
	var _was_emp := false

	func _init(p_w) -> void:
		w = p_w
		id = "darius_w_hook"
		hidden = true

	## [numbers] League (wiki Crippling Strike): the empowered attack has 25 bonus attack range.
	func get_stat_mods() -> Dictionary:
		if w != null and w.is_empowered():
			return {"range": 25.0}
		return {}

	func on_tick(u, _dt: float) -> void:
		var emp: bool = w.is_empowered()
		if emp != _was_emp:
			_was_emp = emp
			u.stats.mark_dirty()   # [numbers] re-evaluate the +25 range when the empowered window opens / closes

	func on_pre_damage_dealt(info) -> void:
		if info.is_attack and info.target != null and w.is_empowered() and info.tag != "darius_w":
			info.amount = owner.stats.ad * w.dv("ADRatio", 1.4) * (owner.stats.crit_damage if info.is_crit else 1.0)
			info.tag = "darius_w"
			# the generic basic attack impact shows darius_Base_W_tar for this hit (see vfx_map)
			if owner.match_ref != null:
				owner.kit.w_hit_time = owner.match_ref.time

	func on_attack_hit(target, info) -> void:
		if info == null or info.tag != "darius_w":
			return
		var o = owner
		w.consume()
		if is_instance_valid(target) and not target.dead:
			K.slow(target, w.dv("SlowPercent", 90.0) / 100.0, w.dv("SlowDuration", 1.0), o, false, "darius_w_slow")
		if info.killed:
			if o.stats.uses_mana:
				o.mana = minf(o.stats.max_mana, o.mana + w.cost())
			w.reduce_cooldown_pct(w.dv("PercentCDRefund", 50.0) / 100.0)


# ===================================================================== E
class Apprehend extends DAbility:
	func _init() -> void:
		target_type = Target.DIRECTION
		indicator = Ind.CONE
		ind_angle = 50.0
		cast_time = 0.25
		anim = "spell3"
		anim_lock = 0.55

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var origin: Vector3 = o.global_position
		var dir: Vector3 = t.dir
		var length := cast_range
		var hits := K.enemies_cone(self, origin, dir, length, ind_angle)
		# League: axe-grab impact on each target and a drag trail while it is pulled (E_weapon_trigger via E_cas)
		for u in hits:
			var up: Vector3 = u.global_position
			var dist := G.flat_dist(origin, up)
			var keep: float = o.radius + u.radius + 0.25
			var to_me := G.flat_dir(up, origin)
			LolVfx.spawn(m, "Darius_Base_E_Axegrab_Collision", up + Vector3(0, u.height * 0.5, 0), {"dir": to_me})
			LolVfx.spawn(m, "darius_Base_E_tar", up, {"dir": to_me})
			if u.has_cc_immunity():
				continue
			if dist > keep:
				u.pull_to(origin + G.flat_dir(origin, up) * keep, 0.28, o)
				var trail := LolVfx.attach(u, "darius_Base_E_tar_unit_trail", {"loop": true, "height": u.height * 0.5, "dir": to_me})
				K.stop_later(m, 0.28, trail)
			K.slow(u, dv("SlowPercent", 40.0) / 100.0, dv("SlowDuration", 1.0) + 0.28, o, false, "darius_e_slow")
		notify_cast(t)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var p: Vector3 = o.global_position
		if ctx.mode == "retreat" and o.hp_ratio() < 0.3:
			return skip()
		var best: Unit = null
		var best_s := -INF
		for e in ctx.enemies:
			if e.has_cc_immunity():
				continue
			var d := G.flat_dist(p, e.global_position)
			if d > range_m() + e.radius * 0.4 - 0.2:
				continue
			if d < o.attack_range_m() + o.radius + e.radius + 0.9:
				continue
			var away: float = e.velocity.dot(G.flat_dir(p, e.global_position))
			var s: float = (1.0 - e.hp_ratio()) * 3.0 + (2.0 if e == ctx.focus else 0.0) + (1.5 if away > 1.0 else 0.0) + (0.8 if e.stats.attack_range > 300.0 else 0.0)
			if ctx.mode != "fight" and e.hp_ratio() > 0.6 and o.hp_ratio() < 0.5:
				continue
			if s > best_s:
				best_s = s
				best = e
		if best != null and (ctx.mode == "fight" or best.hp_ratio() < 0.5 or o.hp_ratio() > 0.6):
			return ctx.aim_at(ctx.predict(best, cast_time), self)
		return skip()


class ApprehendPen extends Effect:
	var e_ab

	func _init(p_e) -> void:
		e_ab = p_e
		id = "darius_e_pen"
		hidden = true

	func get_stat_mods() -> Dictionary:
		if e_ab == null or e_ab.level <= 0:
			return {}
		return {"armor_pen%": e_ab.dv("PassivePercentArmorPen", 20.0) / 100.0}


# ===================================================================== R
class NoxianGuillotine extends DAbility:
	var free_until := -1.0
	var saved_cd := 0.0

	func _init() -> void:
		target_type = Target.UNIT
		target_side = Side.ENEMY
		target_champions_only = true
		indicator = Ind.NONE
		cast_range = 460.0
		cast_time = 0.0
		anim = ""
		anim_lock = 0.0

	func is_dash() -> bool:
		return true

	func is_free() -> bool:
		return free_until > 0.0 and now() < free_until

	func cost() -> float:
		return 0.0 if is_free() else super.cost()

	func damage_vs(u) -> float:
		var st: int = owner.passive.stacks_on(u)
		var base := dv("RBaseDamage") + 0.75 * bonus_ad()
		return base * (1.0 + minf(5.0, float(st)) * dv("RDamagePercentPerHemoStack", 0.2))

	var ready_fx: LolVfx = null

	func on_tick(_dt: float) -> void:
		if free_until > 0.0 and now() >= free_until:
			free_until = -1.0
			cd = maxf(0.0, saved_cd - dv("RRecastDuration", 20.0))
			cd_total = maxf(cd, 0.01)
			LFx.stop(ready_fx)
			ready_fx = null

	func execute(t: Dictionary) -> void:
		var o = owner
		var u = t.unit
		if u == null or not is_instance_valid(u) or u.dead:
			return
		free_until = -1.0
		LFx.stop(ready_fx)
		ready_fx = null
		var m = o.match_ref
		var self_ref := self
		var from: Vector3 = o.global_position
		# leap time = DariusExecute mCastTime (0.367 s): the axe lands when the cast completes
		var leap := 0.367
		var off: float = u.radius + o.radius * 0.4
		var dest: Vector3 = u.global_position - G.flat_dir(from, u.global_position) * off
		o.play_anim("spell4", 1.0, 0.03, 0.95)
		o.anim_lock = 0.95
		o.start_dash(dest, {"duration": leap, "height": 2.4,
			"on_tick": func(unit, _k):
				if is_instance_valid(u) and not u.dead and not unit.dash.is_empty():
					unit.dash.to = u.global_position - G.flat_dir(from, u.global_position) * off
					unit.face_toward(u.global_position, 100.0),
			"on_arrive": func(_unit): self_ref._impact(u)})
		# League: blazing axe trail during the leap (R cast flash via R_cas)
		var trail := K.attach_fx(o, {"lol": "Darius_Base_P_axe_tip", "bone": "BuffBone_Glb_Weapon_1"})
		K.stop_later(m, leap, trail)
		notify_cast(t)

	func _impact(u) -> void:
		var o = owner
		var m = o.match_ref
		var p: Vector3 = o.global_position
		var tp: Vector3 = p
		var info: DamageInfo = null
		var mid := 1.0
		if u != null and is_instance_valid(u) and not u.dead:
			tp = u.global_position
			mid = u.height * 0.5
			info = hit(u, damage_vs(u), G.DmgType.TRUE, {"tag": "r"})
			if info != null and not info.killed and not info.cancelled:
				o.passive.apply(u, 1)
		var big: bool = o == G.player or (u != null and is_instance_valid(u) and u == G.player)
		var dir: Vector3 = G.flat_dir(p, tp) if G.flat_dist(p, tp) > 0.05 else o.facing
		LolVfx.spawn(m, "darius_Base_R_tar", tp + Vector3(0, mid, 0), {"dir": dir})
		LolVfx.spawn(m, "darius_Base_R_tar_02", tp + Vector3(0, mid, 0), {"dir": dir})
		LolVfx.spawn(m, "darius_Base_R_tar_04", tp + Vector3(0, mid, 0), {"dir": dir})
		LolVfx.spawn(m, "darius_Base_R_tar_03", tp, {"dir": dir})
		if m.camera_rig != null:
			m.camera_rig.shake(0.5 if big else 0.18)
		if info != null and info.killed:
			_on_execute_kill(tp)

	func _on_execute_kill(_tp: Vector3) -> void:
		var o = owner
		var m = o.match_ref
		o.passive.trigger_might()
		if level >= 3:
			cd = 0.0
		else:
			saved_cd = cd
			cd = 0.0
			free_until = now() + dv("RRecastDuration", 20.0)
		# League: ult refresh flash, and the "R ready" glow while the free recast window lasts
		LolVfx.attach(o, "darius_Base_r_refresh_01")
		if free_until > 0.0:
			LFx.stop(ready_fx)
			ready_fx = LolVfx.attach(o, "Darius_Base_R_Ready", {"loop": true, "height": o.height + 0.3})
		m.fx_text(o, "Guillotine reset!", RED)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var p: Vector3 = o.global_position
		var best = null
		var best_hp := INF
		for e in ctx.enemies:
			if not valid_unit_target(e):
				continue
			var d := G.flat_dist(p, e.global_position)
			if d > range_m() + o.radius + e.radius + 0.4:
				continue
			var dmg := damage_vs(e)
			var eff: float = e.hp + e.total_shield()
			var ok := dmg >= eff
			if not ok and dmg + o.passive.pending_bleed(e) * 0.6 >= eff and o.passive.stacks_on(e) >= 3:
				ok = true
			if ok and e.hp < best_hp:
				best_hp = e.hp
				best = e
		if best != null:
			return {"unit": best, "pos": best.global_position, "dir": G.flat_dir(p, best.global_position)}
		return skip()
