extends ChampionKit
## Sona, Maven of the Strings.

const BLUE := Color(0.35, 0.62, 1.0)      ## Hymn of Valor
const GREEN := Color(0.4, 1.0, 0.55)      ## Aria of Perseverance
const VIOLET := Color(0.85, 0.45, 1.0)    ## Song of Celerity
const GOLD := Color(1.0, 0.86, 0.45)      ## Crescendo
const TEAL := Color(0.45, 0.95, 0.95)
const SONG_COLORS := [BLUE, GREEN, VIOLET]
const BASE_ATTACK_COLOR := Color(0.55, 0.78, 1.0)
const HOLD := {"hold": true}


func build_kit() -> void:
	c.attack_missile_speed = 1500.0
	c.attack_color = BASE_ATTACK_COLOR
	c.role = "support"
	c.level_order = "QWEQQRQWQWRWWEEREE"
	var pd: Dictionary = spell(str(c.data.get("passive", "SonaPassive"))).get("data_values", {})
	c.passive = PowerChord.new(pd)
	c.add_effect(c.passive)
	c.abilities[0] = init_ability(HymnOfValor.new(), "Q")
	c.abilities[1] = init_ability(AriaOfPerseverance.new(), "W")
	c.abilities[2] = init_ability(SongOfCelerity.new(), "E")
	c.abilities[3] = init_ability(Crescendo.new(), "R")
	# the game data animates every song with Spell1; use the distinct clips
	c.abilities[0].anim = "spell1"
	c.abilities[1].anim = "spell2"
	c.abilities[2].anim = "spell3"
	c.abilities[3].anim = "spell4"
	# SonaW has no cooldown in the extracted data (live: 10s)
	c.abilities[1].cooldowns = [10.0]
	c.abilities[2].cast_range = 400.0
	c.abilities[3].cast_time = 0.25


func ai_tuning() -> Dictionary:
	return {"aggression": 0.5}


## Bot AI returns HOLD to deliberately skip a cast ({} would fall back to BotBrain.default_consider).
class KAbility extends Ability:
	func try_cast(t: Dictionary) -> bool:
		if t.get("hold", false):
			return false
		return super.try_cast(t)


# ===================================================================== helpers
class SonaUtil:
	static func chord(o):
		var p = o.passive
		if p != null and p.has_method("add_accel"):
			return p
		return null

	static func add_accel(o, n: float) -> void:
		var p = chord(o)
		if p != null:
			p.add_accel(n)

	## Start a Melody: a brief aura ring around Sona; allied champions touching it get `on_touch(ally)` once.
	static func melody(ab: Ability, color: Color, on_touch: Callable) -> void:
		var o = ab.owner
		var m = o.match_ref
		var r: float = ab.dv("AuraRange", 400.0) * G.U
		var dur: float = ab.dv("AuraDuration", 3.0)
		var token: int = int(o.get_meta("sona_melody", 0)) + 1
		o.set_meta("sona_melody", token)
		var old = o.get_meta("sona_melody_fx") if o.has_meta("sona_melody_fx") else null
		if old != null and is_instance_valid(old):
			old.detach_and_fade()
		var fx := Vfx.aura(o, color, r, dur, 0.07)
		var mat: ShaderMaterial = (fx.get_child(0) as MeshInstance3D).material_override
		mat.set_shader_parameter("thickness", 0.05)
		mat.set_shader_parameter("fill", 0.08)
		mat.set_shader_parameter("segments", 14.0)
		mat.set_shader_parameter("rotate_speed", 0.8)
		var tw := fx.create_tween()
		tw.tween_interval(maxf(0.0, dur - 0.4))
		tw.tween_method(func(v): mat.set_shader_parameter("fade", v), 1.0, 0.0, 0.4)
		var notes := Vfx.emitter(color, 18, 1.0, 0.3, {"local": true, "radius": r * 0.85, "dir": Vector3.UP, "spread": 8.0,
				"vmin": 0.6, "vmax": 1.3, "tex": Vfx.spark_texture()})
		fx.add_child(notes)
		fx.trails.append(notes)
		o.set_meta("sona_melody_fx", fx)
		Vfx.ring(m, o.global_position, color, r, 0.45, 0.06, 0.12)
		var touched := {}
		m.add_ticker(dur, func(_dt):
			if not is_instance_valid(o) or o.dead or int(o.get_meta("sona_melody", 0)) != token:
				return false
			for a in m.allies_in_radius(o.team, o.global_position, r, true):
				if touched.has(a) or a.dead:
					continue
				touched[a] = true
				on_touch.call(a)
				if a != o:
					Vfx.beam(m, o.global_position + Vector3(0, 1.3, 0), a.global_position + Vector3(0, 1.1, 0), color, 0.1, 0.22)
				note_pop(m, a, color)
			return true)

	static func note_pop(m, u, color: Color) -> void:
		var n := VfxNode.new()
		n.lifetime = 1.0
		u.add_child(n)
		n.position = Vector3(0, u.height * 0.9, 0)
		var s := Vfx.sprite(color, 0.55, 3.0, Vfx.spark_texture())
		n.add_child(s)
		var tw := n.create_tween()
		tw.tween_property(n, "position:y", u.height * 0.9 + 0.9, 0.8).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_method(func(v): s.material_override.set_shader_parameter("energy", v), 3.0, 0.0, 0.8)
		Vfx.ring(m, u.global_position, color, 1.0, 0.35, 0.12, 0.15)

	static func bolt(color: Color, size: float) -> VfxNode:
		var n := VfxNode.new()
		n.add_child(Vfx.sprite(color.lerp(Color.WHITE, 0.55), size * 0.5, 3.2, Vfx.spark_texture()))
		n.add_child(Vfx.sprite(color, size * 1.4, 1.8))
		var e := Vfx.emitter(color, 40, 0.4, size * 0.7, {"vmin": 0.0, "vmax": 0.4, "radius": size * 0.25})
		n.add_child(e)
		n.trails.append(e)
		var e2 := Vfx.emitter(color.lerp(Color.WHITE, 0.3), 16, 0.6, size * 0.3, {"vmin": 0.3, "vmax": 1.0, "tex": Vfx.spark_texture()})
		n.add_child(e2)
		n.trails.append(e2)
		return n

	static func est(o, target, dmg: float) -> float:
		var mr: float = target.stats.mr
		if mr > 0.0:
			mr = maxf(0.0, mr * (1.0 - o.stats.magic_pen_pct) - o.stats.magic_pen)
		return dmg * 100.0 / (100.0 + mr)


# ===================================================================== passive
class PowerChord extends Effect:
	var data := {}
	var count := 0
	var ready := false
	var song := 0               ## 0 = Hymn (Staccato), 1 = Aria (Diminuendo), 2 = Celerity (Tempo)
	var accel := 0.0            ## Accelerando stacks
	var ready_fx: Node3D = null

	func _init(pd: Dictionary = {}) -> void:
		data = pd
		id = "sona_passive"
		display_name = "Power Chord"

	func hud_counter() -> String:
		return str(count) if count > 0 else ""

	func max_count() -> int:
		return int(data.get("PowerChordPassiveCountMax", 3.0))

	func accel_cap_stacks() -> float:
		return float(data.get("AccelerandoCap", 60.0)) / maxf(float(data.get("AccelerandoAHPerStack", 0.5)), 0.01)

	func get_stat_mods() -> Dictionary:
		return {"basic_ah": minf(accel, accel_cap_stacks()) * float(data.get("AccelerandoAHPerStack", 0.5))}

	func add_accel(n: float) -> void:
		var g: float = n * owner.permanent_stack_mult()
		var cap := accel_cap_stacks()
		if accel >= cap:
			var r = owner.abilities[3]
			if r != null:
				r.reduce_cooldown(float(data.get("AccelerandoUltCDR", 1.5)) * g)
		else:
			accel = minf(cap, accel + g)
		refresh_stats()

	func chord_damage() -> float:
		var lvl: float = owner.level
		return lerpf(20.0, 240.0, (lvl - 1.0) / 17.0) + 0.2 * owner.stats.ap

	func staccato_damage() -> float:
		var lvl: float = owner.level
		return lerpf(30.0, 360.0, (lvl - 1.0) / 17.0) + 0.3 * owner.stats.ap

	func on_tick(u, _dt: float) -> void:
		if u.is_bot and u.ability_points > 0:
			u.auto_level_abilities()
		if ready and not u.dead and (ready_fx == null or not is_instance_valid(ready_fx)):
			_show_ready()

	func on_ability_cast(ab, _t) -> void:
		if ab == null or ab.is_summoner or ab.slot > 2:
			return
		song = ab.slot
		# songs share a short global cooldown
		for i in 3:
			var other = owner.abilities[i]
			if other != null and i != ab.slot and other.level > 0 and other.cd < 0.5:
				other.cd = ab.dv("BaseGlobalCD", 0.5)
				other.cd_total = maxf(other.cd_total, other.cd) if other.cd_total > 0.0 else other.cd
		if not ready:
			count += 1
			if count >= max_count():
				ready = true
		if ready:
			_show_ready()

	func on_attack_hit(target, _info) -> void:
		if not ready or target == null or not is_instance_valid(target) or target.dead:
			return
		if target.team == owner.team or target.kind in [G.Kind.TURRET, G.Kind.INHIBITOR, G.Kind.NEXUS]:
			return
		ready = false
		count = 0
		_hide_ready()
		var o = owner
		var m = o.match_ref
		var col: Color = SONG_COLORS[song]
		var dmg := staccato_damage() if song == 0 else chord_damage()
		Combat.deal(o, target, dmg, G.DmgType.MAGIC, {"is_proc": true, "is_spell": true, "tag": "power_chord"})
		match song:
			1:
				var weak: float = 0.25 + 0.0004 * o.stats.ap
				K.buff(target, "sona_diminuendo", o.abilities[1].dv("DiminuendoDuration", 3.0), {"dmg_amp": -weak}, o,
						{"name": "Diminuendo", "debuff": true})
			2:
				K.slow(target, 0.5 + 0.0004 * o.stats.ap, o.abilities[2].dv("TempoDuration", 2.0), o, false, "sona_tempo")
		var p: Vector3 = target.global_position
		Vfx.burst(m, p + Vector3(0, 1.0, 0), col, 1.1, {"sparks": 24, "ring": false})
		Vfx.ring(m, p, col, 1.8, 0.4, 0.1, 0.15)
		Vfx.ring(m, p, GOLD, 1.1, 0.3, 0.08, 0.0)
		SonaUtil.note_pop(m, target, col)

	func _show_ready() -> void:
		_hide_ready()
		var o = owner
		var col: Color = SONG_COLORS[song]
		o.attack_color = col.lerp(Color.WHITE, 0.25)
		var n := VfxNode.new()
		o.add_child(n)
		n.position = Vector3(0, 0.08, 0)
		var ring := Vfx.aura(o, col, 1.0, 1.0e6, 0.08)
		ring.reparent(n)
		var e := Vfx.emitter(col, 16, 0.8, 0.22, {"local": true, "radius": 0.6, "dir": Vector3.UP, "spread": 10.0, "vmin": 0.8,
				"vmax": 1.6, "tex": Vfx.spark_texture()})
		n.add_child(e)
		n.trails.append(e)
		ready_fx = n

	func _hide_ready() -> void:
		if ready_fx != null and is_instance_valid(ready_fx):
			ready_fx.detach_and_fade()
		ready_fx = null
		if owner != null:
			owner.attack_color = BASE_ATTACK_COLOR

	func on_death(_k) -> void:
		_hide_ready()


# ===================================================================== Q
class HymnOfValor extends KAbility:
	func _init() -> void:
		target_type = Target.NONE
		indicator = Ind.RANGE
		cast_range = 825.0
		cast_time = 0.0
		anim = "spell1"
		anim_lock = 0.4

	func make_target(_world_pos: Vector3, _hovered = null) -> Dictionary:
		return {"pos": owner.global_position, "dir": owner.facing, "unit": null}

	func damage() -> float:
		return dv("BaseDamage") + 0.4 * ap()

	## Nearest two enemies in range, champions first.
	func pick_targets() -> Array:
		var o = owner
		var cands: Array = o.match_ref.enemies_in_radius(o.team, o.global_position, cast_range * G.U)
		cands.sort_custom(func(a, b):
			var sa: float = (0.0 if a.kind == G.Kind.CHAMPION else 100.0) + G.flat_dist(o.global_position, a.global_position)
			var sb: float = (0.0 if b.kind == G.Kind.CHAMPION else 100.0) + G.flat_dist(o.global_position, b.global_position)
			return sa < sb)
		return cands.slice(0, int(dv("EnemiesToHit", 2.0)))

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var dmg := damage()
		var self_ref := self
		var targets := pick_targets()
		for i in targets.size():
			var tgt: Unit = targets[i]
			var from: Vector3 = o.global_position + Vector3(0, 1.4, 0) + o.facing.rotated(Vector3.UP, 0.7 if i == 0 else -0.7) * 0.6
			K.homing_missile(self, from, tgt, 1300.0, func(_mm, u):
				self_ref.hit(u, dmg, G.DmgType.MAGIC, {"tag": "q"})
				if u.kind == G.Kind.CHAMPION:
					SonaUtil.add_accel(o, 1.0)
				Vfx.hit_spark(m, u.global_position + Vector3(0, 1.1, 0), BLUE, 0.9)
				Vfx.ring(m, u.global_position, BLUE, 0.9, 0.3, 0.12, 0.1),
				{"visual": SonaUtil.bolt(BLUE, 0.55)})
		Vfx.burst(m, o.global_position + Vector3(0, 1.3, 0), BLUE, 0.7, {"sparks": 14, "ring": false})
		var on_hit_dmg := dv("BaseOnHitDamage") + dv("OnHitRatio", 0.1) * ap()
		var dur := dv("OnHitDuration", 5.0)
		var q_icon := icon
		SonaUtil.melody(self, BLUE, func(a):
			a.remove_buffs_by_id("sona_q_onhit")
			var b := HymnBuff.new()
			b.duration = dur
			b.remaining = dur
			b.dmg = on_hit_dmg
			b.icon = q_icon
			b.vfx = Vfx.aura(a, BLUE, maxf(0.8, a.radius * 1.4), dur, 0.1)
			a.add_buff(b, o))
		notify_cast(t)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var rng := cast_range * G.U
		for e in ctx.enemies:
			if G.flat_dist(o.global_position, e.global_position) <= rng + e.radius:
				return make_target(o.global_position)
		# empower an ally that is about to fight / farm with a big wave
		if ctx.enemies.is_empty() and o.mana > o.stats.max_mana * 0.75:
			var n := 0
			for mn in ctx.enemy_minions:
				if G.flat_dist(o.global_position, mn.global_position) <= rng:
					n += 1
			if n >= 3:
				return make_target(o.global_position)
		return HOLD


class HymnBuff extends Buff:
	var dmg := 0.0

	func _init() -> void:
		id = "sona_q_onhit"
		display_name = "Hymn of Valor"

	func on_attack_hit(target, _info) -> void:
		if removed or target == null or not is_instance_valid(target) or target.dead or target.team == owner.team:
			return
		removed = true
		Combat.deal(owner, target, dmg, G.DmgType.MAGIC, {"is_proc": true, "tag": "sona_q"})
		if owner.match_ref != null:
			Vfx.hit_spark(owner.match_ref, target.global_position + Vector3(0, 1.1, 0), BLUE, 0.8)


# ===================================================================== W
class AriaOfPerseverance extends KAbility:
	func _init() -> void:
		target_type = Target.NONE
		indicator = Ind.RANGE
		cast_range = 1000.0
		cast_time = 0.0
		anim = "spell2"
		anim_lock = 0.4

	func make_target(_world_pos: Vector3, _hovered = null) -> Dictionary:
		return {"pos": owner.global_position, "dir": owner.facing, "unit": null}

	func heal_amount() -> float:
		return dv("BaseHeal") + dv("HealRatio", 0.3) * ap()

	func best_ally() -> Unit:
		var o = owner
		var best: Unit = null
		var br := 1.01
		for a in o.match_ref.allies_in_radius(o.team, o.global_position, dv("HealRange", 1000.0) * G.U, true):
			if a == o or a.dead:
				continue
			if a.hp_ratio() < br:
				br = a.hp_ratio()
				best = a
		return best

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var heal := heal_amount()
		Combat.heal(o, o, heal)
		Vfx.rising(o, GREEN, 0.5, 24, 0.5)
		var a := best_ally()
		if a != null:
			var injured: bool = a.hp < a.stats.max_hp - 1.0
			Combat.heal(o, a, heal)
			if injured:
				SonaUtil.add_accel(o, 1.0)
			Vfx.beam(m, o.global_position + Vector3(0, 1.3, 0), a.global_position + Vector3(0, 1.1, 0), GREEN, 0.16, 0.3)
			Vfx.rising(a, GREEN, 0.5, 24, 0.5)
		var shield := dv("BaseShield") + dv("ShieldRatio", 0.25) * ap()
		var sdur := dv("ShieldDuration", 1.5)
		var bp := dv("AccelerandoShieldBreakpoint", 25.0)
		SonaUtil.melody(self, GREEN, func(u):
			K.shield(o, u, shield, sdur, GREEN, "sona_w")
			if u != o:
				u.remove_buffs_by_id("sona_w_watch")
				var wb := AriaWatch.new()
				wb.duration = sdur
				wb.remaining = sdur
				wb.sona = o
				wb.threshold = bp
				wb.hidden = true
				u.add_buff(wb, o))
		notify_cast(t)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var heal := heal_amount()
		var missing_self: float = o.stats.max_hp - o.hp
		var a := best_ally()
		var ally_need: bool = a != null and a.hp_ratio() < 0.7 and a.stats.max_hp - a.hp > heal * 0.8
		if missing_self > heal * 1.2 and (ally_need or o.hp_ratio() < 0.6):
			return make_target(o.global_position)
		if ally_need and (a.hp_ratio() < 0.45 or missing_self > heal * 0.5):
			return make_target(o.global_position)
		if o.hp_ratio() < 0.35:
			return make_target(o.global_position)
		# shield aura for a fight where allies are close and taking hits
		if ctx.mode == "fight" and o.mana > o.stats.max_mana * 0.45:
			var now: float = o.match_ref.time
			var hit_allies := 0
			for al in ctx.allies + [o]:
				if G.flat_dist(o.global_position, al.global_position) < 4.0 and now - al.last_hit_by_champion_time < 0.8:
					hit_allies += 1
			if hit_allies >= 2:
				return make_target(o.global_position)
		return HOLD


## Watches Aria's shield on an ally; grants Accelerando when it blocks enough damage.
class AriaWatch extends Buff:
	var sona = null
	var threshold := 25.0
	var blocked := 0.0

	func _init() -> void:
		id = "sona_w_watch"
		display_name = "Aria"

	func on_damage_taken(info) -> void:
		if removed:
			return
		blocked += info.absorbed
		if blocked >= threshold and sona != null and is_instance_valid(sona):
			SonaUtil.add_accel(sona, 1.0)
			removed = true


# ===================================================================== E
class SongOfCelerity extends KAbility:
	func _init() -> void:
		target_type = Target.NONE
		indicator = Ind.RANGE
		cast_range = 400.0
		cast_time = 0.0
		anim = "spell3"
		anim_lock = 0.4

	func make_target(_world_pos: Vector3, _hovered = null) -> Dictionary:
		return {"pos": owner.global_position, "dir": owner.facing, "unit": null}

	func execute(t: Dictionary) -> void:
		var o = owner
		var b := CelerityBuff.new()
		b.min_time = dv("SelfMovementSpeedDurationMin", 3.0)
		b.duration = dv("SelfMovementSpeedDurationMax", 7.0)
		b.remaining = b.duration
		b.stats = {"ms%": dv("SelfBaseMovementSpeed", 0.2) + 0.0002 * ap()}
		b.icon = icon
		var fx := VfxNode.new()
		o.add_child(fx)
		fx.position.y = 0.15
		var e := Vfx.emitter(VIOLET, 30, 0.6, 0.35, {"radius": 0.4, "dir": Vector3.UP, "spread": 25.0, "vmin": 0.2, "vmax": 0.8})
		fx.add_child(e)
		fx.trails.append(e)
		var e2 := Vfx.emitter(VIOLET.lerp(Color.WHITE, 0.3), 10, 0.9, 0.22, {"radius": 0.5, "dir": Vector3.UP, "spread": 10.0,
				"vmin": 0.6, "vmax": 1.2, "tex": Vfx.spark_texture()})
		fx.add_child(e2)
		fx.trails.append(e2)
		b.vfx = fx
		o.remove_buffs_by_id("sona_e_self")
		o.add_buff(b, o)
		var ms := dv("AllyBaseMovementSpeed", 0.1) + 0.0002 * ap()
		var mdur := dv("AllyMovementSpeedDuration", 3.0)
		SonaUtil.melody(self, VIOLET, func(u):
			if u == o:
				return
			K.haste(u, ms, mdur, o, false, "sona_e_ally")
			Vfx.rising(u, VIOLET, mdur * 0.6, 16, 0.4))
		notify_cast(t)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		if ctx.mode == "retreat" and (ctx.in_danger() or not ctx.enemies.is_empty()):
			return make_target(o.global_position)
		if ctx.wants_speed():
			return make_target(o.global_position)
		# speed the team into a fight
		if ctx.mode == "fight" and ctx.focus != null:
			var d := G.flat_dist(o.global_position, ctx.focus.global_position)
			var near_allies := 0
			for a in ctx.allies:
				if G.flat_dist(o.global_position, a.global_position) < 4.0:
					near_allies += 1
			if near_allies >= 1 and d > 8.0 and d < 14.0:
				return make_target(o.global_position)
		return HOLD


class CelerityBuff extends Buff:
	var min_time := 3.0
	var age := 0.0
	var damaged := false

	func _init() -> void:
		id = "sona_e_self"
		display_name = "Song of Celerity"

	func on_tick(_u, dt: float) -> void:
		age += dt
		if damaged and age >= min_time:
			removed = true

	func on_damage_taken(info) -> void:
		if info.final + info.absorbed > 0.0 and info.source != null and is_instance_valid(info.source) and info.source.team != owner.team:
			damaged = true


# ===================================================================== R
class Crescendo extends KAbility:
	const TRAVEL := 1000.0

	func _init() -> void:
		target_type = Target.DIRECTION
		indicator = Ind.LINE
		ind_width = 280.0
		ind_length = TRAVEL
		cast_range = 900.0
		cast_time = 0.25
		anim = "spell4"
		anim_lock = 0.6

	func damage() -> float:
		return dv("BaseDamage") + 0.5 * ap()

	func half_width() -> float:
		return 140.0

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var dir: Vector3 = t.dir
		var dmg := damage()
		var stun := dv("StunDuration", 1.5)
		var self_ref := self
		Vfx.burst(m, o.global_position + Vector3(0, 1.2, 0), GOLD, 1.4, {"sparks": 30})
		Vfx.ring(m, o.global_position, TEAL, 2.4, 0.5, 0.08, 0.1)
		var on_hit := func(_mm, u):
			self_ref.hit(u, dmg, G.DmgType.MAGIC, {"is_aoe": true, "tag": "r"})
			K.stun(u, stun, o)
			Vfx.burst(m, u.global_position + Vector3(0, 1.1, 0), GOLD, 1.0, {"sparks": 18, "ring": false})
			SonaUtil.note_pop(m, u, TEAL)
		var mi := K.line_missile(self, o.global_position + Vector3(0, 0.0, 0) + dir * 0.4, dir, 2400.0, TRAVEL, {
			"width": half_width(), "pierce": true, "visual": _wave_visual(), "height": 1.0, "on_hit": on_hit,
		})
		mi.blockable = true
		var gp: Vector3 = o.global_position
		if m.camera_rig != null and G.player != null and G.flat_dist(G.player.global_position, gp) < 14.0:
			m.camera_rig.shake(0.2)
		notify_cast(t)

	func _wave_visual() -> VfxNode:
		var n := VfxNode.new()
		var hw := half_width() * G.U
		# three bright arcs bulging forward (local -Z is the travel direction)
		for i in 3:
			var arc := MeshInstance3D.new()
			arc.mesh = _arc_mesh(hw * (1.25 + i * 0.22), 0.12 + 0.03 * i, 100.0)
			var mat := Vfx.add_material(GOLD if i == 0 else TEAL, 2.6 - i * 0.5, false)
			mat.set_shader_parameter("use_mask", false)
			arc.material_override = mat
			arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			arc.position = Vector3(0, -0.4 + i * 0.35, hw * 1.0 + i * 0.35)
			n.add_child(arc)
		for k in 7:
			var x := lerpf(-hw, hw, k / 6.0)
			var s := Vfx.sprite(TEAL if k % 2 == 0 else GOLD, 0.7, 2.2, Vfx.spark_texture())
			s.position = Vector3(x, 0.1, -absf(x) * -0.25)
			n.add_child(s)
		var e := Vfx.emitter(TEAL, 90, 0.5, 0.35, {"vmin": 0.0, "vmax": 0.6, "tex": Vfx.spark_texture(), "energy": 1.8})
		var pm: ParticleProcessMaterial = e.process_material
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(hw, 0.4, 0.2)
		n.add_child(e)
		n.trails.append(e)
		var e2 := Vfx.emitter(GOLD, 50, 0.7, 0.6, {"vmin": 0.0, "vmax": 0.3, "energy": 1.3})
		var pm2: ParticleProcessMaterial = e2.process_material
		pm2.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm2.emission_box_extents = Vector3(hw * 0.9, 0.3, 0.1)
		n.add_child(e2)
		n.trails.append(e2)
		n.add_child(Vfx.light(GOLD, 3.0, 6.0))
		return n

	## Flat arc strip (XZ plane) centred on +Z, spanning +-span/2 degrees around -Z.
	func _arc_mesh(radius: float, thickness: float, span_deg: float) -> ArrayMesh:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var segs := 16
		var half := deg_to_rad(span_deg * 0.5)
		for i in segs:
			var a0 := lerpf(-half, half, float(i) / segs)
			var a1 := lerpf(-half, half, float(i + 1) / segs)
			var d0 := Vector3(sin(a0), 0, -cos(a0))
			var d1 := Vector3(sin(a1), 0, -cos(a1))
			var i0 := d0 * (radius - thickness)
			var o0 := d0 * (radius + thickness)
			var i1 := d1 * (radius - thickness)
			var o1 := d1 * (radius + thickness)
			for v in [i0, o0, o1, i0, o1, i1]:
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
		return st.commit()

	## Champions hit by a cast toward `aim` (predicted positions).
	func count_line(ctx, aim: Vector3) -> int:
		var o = owner
		var from: Vector3 = o.global_position
		var dir := G.flat_dir(from, aim)
		var to: Vector3 = from + dir * TRAVEL * G.U
		var n := 0
		for e in ctx.enemies:
			if e.has_cc_immunity():
				continue
			var p: Vector3 = ctx.predict(e, cast_time + G.flat_dist(from, e.global_position) / 24.0)
			if NavGrid._dist_to_segment(p, from, to) <= half_width() * G.U + e.radius * 0.8:
				n += 1
		return n

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var best_n := 0
		var best_aim := Vector3.INF
		for e in ctx.enemies:
			if G.flat_dist(o.global_position, e.global_position) > TRAVEL * G.U * 0.95:
				continue
			var aim: Vector3 = ctx.predict(e, cast_time + G.flat_dist(o.global_position, e.global_position) / 24.0)
			var n := count_line(ctx, aim)
			if n > best_n:
				best_n = n
				best_aim = aim
		if best_n >= 2:
			return make_target(best_aim, null)
		if best_n == 1:
			# self-peel or a lone kill
			var t: Unit = ctx.best_enemy_in_range(TRAVEL * G.U * 0.9)
			if ctx.in_danger() and o.hp_ratio() < 0.4:
				for e in ctx.enemies:
					if G.flat_dist(o.global_position, e.global_position) < 4.5 and not e.has_cc_immunity():
						return make_target(e.global_position, null)
			if t != null and ctx.enemies.size() == 1 and SonaUtil.est(o, t, damage()) >= t.hp + t.total_shield():
				return make_target(ctx.predict(t, cast_time), null)
		return HOLD
