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


func ai_tuning() -> Dictionary:
	return {"aggression": 0.75}


# ===================================================================== passive
class Perseverance extends Effect:
	var since_damage := 99.0

	func _init() -> void:
		id = "garen_passive"
		display_name = "Perseverance"

	func on_damage_taken(info) -> void:
		if info.source != null and (info.source.kind == G.Kind.CHAMPION or info.source.kind == G.Kind.TURRET or info.is_spell):
			since_damage = 0.0

	func on_tick(u, dt: float) -> void:
		since_damage += dt
		if since_damage >= 8.0 and u.hp < u.stats.max_hp:
			# 1.5% -> 10.1% max health every 5 seconds by level
			var pct: float = lerpf(0.015, 0.101, (u.level - 1) / 17.0)
			u.hp = minf(u.stats.max_hp, u.hp + u.stats.max_hp * pct / 5.0 * dt)


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
		var fx := Vfx.aura(o, GOLD, 1.0, dv("AttackWindow", 4.5), 0.1)
		o.set_meta("garen_q_fx", fx)
		Vfx.rising(o, GOLD, 0.4, 20)
		notify_cast(t)

	func is_empowered() -> bool:
		return owner.match_ref != null and owner.match_ref.time < empowered_until

	func consume(target: Unit) -> void:
		empowered_until = -1.0
		var fx = owner.get_meta("garen_q_fx", null)
		if fx != null and is_instance_valid(fx):
			fx.detach_and_fade()
		K.silence(target, dv("SilenceDuration", 1.5), owner)
		Vfx.burst(owner.match_ref, target.global_position + Vector3(0, 1.0, 0), GOLD, 1.3, {"sparks": 30})
		if owner.match_ref.camera_rig != null and owner == G.player:
			owner.match_ref.camera_rig.shake(0.25)

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
		K.shield(o, o, shield, dv("UpfrontDuration", 0.75), Color(1.0, 0.9, 0.5))
		K.buff(o, "garen_w_ten", dv("UpfrontDuration", 0.75), {"tenacity": dv("UpfrontTenacity", 0.6)}, o, {"name": "Courage"})
		K.buff(o, "garen_w_dr", dv("DRDuration", 4.0), {"dmg_reduction": dv("DRPercent", 0.3)}, o, {"name": "Courage", "icon": icon})
		Vfx.aura(o, Color(1.0, 0.85, 0.4), 1.1, dv("DRDuration", 4.0), 0.12)
		notify_cast(t)

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

	func execute(t: Dictionary) -> void:
		var o = owner
		if spinning:
			return
		spinning = true
		hits_on.clear()
		var dur := dv("Duration", 3.0)
		var ticks := int(dv("NumTicks", 7.0)) + int(floor(maxf(0.0, o.stats.bonus_as) / dv("ASPerTick", 0.25)))
		var interval := dur / float(ticks)
		var fx := VfxNode.new()
		fx.lifetime = dur
		o.add_child(fx)
		fx.position.y = 0.9
		var blade := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 2.6
		tm.outer_radius = 3.25
		tm.rings = 24
		blade.mesh = tm
		var mat := Vfx.add_material(STEEL, 1.3, false)
		mat.set_shader_parameter("use_mask", false)
		blade.material_override = mat
		blade.scale = Vector3(1, 0.05, 1)
		fx.add_child(blade)
		var spin := fx.create_tween().set_loops()
		spin.tween_property(fx, "rotation:y", -TAU, 0.3).from(0.0)
		o.play_anim("spell3", 1.0, 0.05)
		o.anim_lock = dur
		start_channel(dur, {"interval": interval, "acc": 0.0})
		o.channel_disarm = true
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
			return
		var nearest: Unit = null
		var nd := INF
		for u in targets:
			var d := G.flat_dist(o.global_position, u.global_position)
			if d < nd:
				nd = d
				nearest = u
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
					K.buff(u, "garen_shred", dv("ShredDuration", 6.0), {"armor%": -dv("ShredAmount", 0.25)}, o, {"name": "Judgment", "debuff": true})
			Vfx.hit_spark(o.match_ref, u.global_position + Vector3(0, 1.0, 0), STEEL, 0.5)

	func channel_end(_ch: Dictionary, _interrupted: bool) -> void:
		spinning = false
		owner.channel_disarm = false
		owner.anim_lock = 0.0

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
		var top := u.global_position + Vector3(0, 9.0, 0)
		var sword := VfxNode.new()
		sword.lifetime = 0.9
		m.add_fx(sword, top)
		var blade := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, 6.0, 0.12)
		blade.mesh = bm
		var mat := Vfx.add_material(GOLD, 3.0, false)
		mat.set_shader_parameter("use_mask", false)
		blade.material_override = mat
		sword.add_child(blade)
		sword.add_child(Vfx.light(GOLD, 6.0, 8.0))
		var tw := sword.create_tween()
		var self_ref := self
		tw.tween_property(sword, "global_position", u.global_position + Vector3(0, 3.0, 0), 0.18).set_ease(Tween.EASE_IN)
		tw.tween_callback(func():
			if is_instance_valid(u) and not u.dead:
				self_ref.hit(u, self_ref.damage_vs(u), G.DmgType.TRUE, {"tag": "r"})
				Vfx.burst(m, u.global_position + Vector3(0, 0.5, 0), GOLD, 2.4, {"sparks": 50})
				if m.camera_rig != null:
					m.camera_rig.shake(0.45 if o == G.player or u == G.player else 0.15))
		notify_cast(t)

	func ai_consider(ctx) -> Dictionary:
		for e in ctx.enemies:
			if G.flat_dist(owner.global_position, e.global_position) <= range_m() + e.radius + 0.5:
				if damage_vs(e) >= e.hp + e.total_shield():
					return {"unit": e, "pos": e.global_position}
		return {}
