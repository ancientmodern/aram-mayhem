extends ChampionKit
## Sona, Maven of the Strings.

const BLUE := Color(0.35, 0.62, 1.0)      ## Hymn of Valor
const GREEN := Color(0.4, 1.0, 0.55)      ## Aria of Perseverance
const VIOLET := Color(0.85, 0.45, 1.0)    ## Song of Celerity
const SONG_COLORS := [BLUE, GREEN, VIOLET]
const BASE_ATTACK_COLOR := Color(0.55, 0.78, 1.0)
const HOLD := {"hold": true}
## League Power Chord systems per active song (Hymn / Aria / Celerity)
const CHORD_MIS := ["Sona_Base_Q_PowerChord_Mis", "Sona_Base_W_Powerchord_Mis", "Sona_Base_E_Powerchord_Mis"]
const CHORD_TAR := ["Sona_Base_Q_PowerChord_Tar", "Sona_Base_W_Powerchord_Tar", "Sona_Base_E_Powerchord_Tar"]
const CHORD_READY := ["Sona_Base_Q_PCReady_CoreRings", "Sona_Base_W_PCReady_CoreRings", "Sona_Base_E_PCReady_CoreRings"]


func build_kit() -> void:
	c.attack_missile_speed = 1500.0
	c.attack_color = BASE_ATTACK_COLOR
	c.role = "support"
	c.level_order = "QWEQQRQWQWRWWEEREE"
	var pd: Dictionary = spell(str(c.data.get("passive", "SonaPassive"))).get("data_values", {}).duplicate()
	# ARAM (CommunityDragon sona.bin.json SonaPassive DataValuesModeOverride.ARAM; wiki ARAM page): Accelerando
	# caps at 30 basic ability haste (60 stacks x 0.5) and each stack past the cap refunds 1 s of Crescendo.
	pd["AccelerandoCap"] = 30.0
	pd["AccelerandoUltCDR"] = 1.0
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
	# ARAM song cooldowns (sona.bin.json cooldown overrides ARAM; wiki ARAM page): Hymn of Valor 10 s,
	# Aria of Perseverance 13 s (SonaW has no cooldown in the extracted SR data).
	K.aram_cooldowns(c.abilities[0], [10.0, 10.0, 10.0, 10.0, 10.0, 10.0, 10.0])
	K.aram_cooldowns(c.abilities[1], [13.0, 13.0, 13.0, 13.0, 13.0, 13.0, 13.0])
	# ARAM Aria values (SonaW DataValuesModeOverride.ARAM): shield 65-105 base, heal ratio 20% AP.
	K.aram_data(c.abilities[1], {"BaseShield": [55.0, 65.0, 75.0, 85.0, 95.0, 105.0, 115.0], "HealRatio": 0.2})
	c.abilities[2].cast_range = 400.0
	c.abilities[3].cast_time = 0.25


func ai_tuning() -> Dictionary:
	return {"aggression": 0.5}


## League particle systems (data/vfx/sona.json). Automatic hooks cover BA_Mis / BA_Tar, Q_Mis / Q_Tar,
## R_Cas / R_Missile / R_Tar; the auras, buffs, heals and Power Chord are spawned by the kit.
func vfx_map() -> Dictionary:
	var mis := "Sona_Base_BA_Mis"
	var crit_mis := "Sona_Base_CritAttack_Cas"
	var pc = c.passive
	if pc != null and pc.get("ready"):
		mis = CHORD_MIS[clampi(int(pc.song), 0, 2)]
		crit_mis = mis
	return {
		"BA_mis": mis, "BA_crit_mis": crit_mis, "BA_tar": "Sona_Base_BA_Tar", "BA_crit_tar": "Sona_Base_BA_Tar",
		"Q_cas": "", "Q_mis": "Sona_Base_Q_Mis", "Q_tar": "Sona_Base_Q_Tar",
		"W_cas": "", "W_mis": "", "W_tar": "",
		"E_cas": "", "E_tar": "",
		"R_cas": "Sona_Base_R_Cas", "R_mis": "Sona_Base_R_Missile", "R_tar": "Sona_Base_R_Tar",
	}


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

	## League effect attached to a unit's centre (League attaches these to the body bone).
	static func fx_on(u, fx_name: String, opts: Dictionary = {}) -> LolVfx:
		if u == null or not is_instance_valid(u):
			return null
		var o2 := {"height": u.height * 0.5}
		o2.merge(opts, true)
		return LolVfx.attach(u, fx_name, o2)

	## Start a Melody: League's song aura around Sona ("<key>_Zone"); allied champions touching it get
	## `on_touch(ally)` once and the song's touch flash ("<key>_Tar_Buf").
	static func melody(ab: Ability, key: String, on_touch: Callable) -> void:
		var o = ab.owner
		var m = o.match_ref
		var r: float = ab.dv("AuraRange", 400.0) * G.U
		var dur: float = ab.dv("AuraDuration", 3.0)
		var token: int = int(o.get_meta("sona_melody", 0)) + 1
		o.set_meta("sona_melody", token)
		var old = o.get_meta("sona_melody_fx") if o.has_meta("sona_melody_fx") else null
		if old != null and is_instance_valid(old):
			old.stop()
		var zone := LolVfx.attach(o, "Sona_Base_%s_Zone%s" % [key, "_Self" if o == G.player else ""], {"loop": true, "dir": o.facing})
		o.set_meta("sona_melody_fx", zone)
		if zone != null:
			K.stop_later(m, dur, zone)   # weakref-safe: the zone node may be freed before the timer fires
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
					fx_on(a, "Sona_Base_%s_Tar_Buf" % key)
			return true)

	## Fly a League missile system from `from` to unit `u` (visual only), then call `on_arrive`.
	static func fly(m, fx_name: String, from: Vector3, u, time: float, on_arrive: Callable = Callable()) -> void:
		if u == null or not is_instance_valid(u):
			return
		var to: Vector3 = u.global_position + Vector3(0, u.height * 0.5, 0)
		var fx := LolVfx.spawn(m, fx_name, from, {"dir": G.flat_dir(from, to), "loop": true})
		if fx == null:
			if on_arrive.is_valid():
				on_arrive.call()
			return
		var tw := fx.create_tween()
		tw.tween_property(fx, "global_position", to, time)
		tw.tween_callback(func():
			fx.stop()
			if on_arrive.is_valid():
				on_arrive.call())

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
			SonaUtil.fx_on(owner, "Sona_Base_P_Accelerando_Tar")
		else:
			accel = minf(cap, accel + g)
			SonaUtil.fx_on(owner, "Sona_Base_P_Accelerando_Tar")
			if accel >= cap:
				SonaUtil.fx_on(owner, "Sona_Base_P_Accelerando_Completed")
		refresh_stats()

	## League SonaPassive "PowerChordDamage" (CommunityDragon sona.bin.json): 20, +10 per level, +15 per level
	## from 9 -> 20 .. 240 (+20% AP).
	func chord_damage() -> float:
		return K.level_breakpoints(owner.level, 20.0, 10.0, [[9, 15.0]]) + 0.2 * owner.stats.ap

	## League SonaQ "TotalStaccatoDamage": 30, +15 per level, +22.5 per level from 9 -> 30 .. 360 (+30% AP).
	func staccato_damage() -> float:
		return K.level_breakpoints(owner.level, 30.0, 15.0, [[9, 22.5]]) + 0.3 * owner.stats.ap

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
		var dmg := staccato_damage() if song == 0 else chord_damage()
		Combat.deal(o, target, dmg, G.DmgType.MAGIC, {"is_proc": true, "is_spell": true, "tag": "power_chord"})
		match song:
			1:
				var weak: float = 0.25 + 0.0004 * o.stats.ap
				K.buff(target, "sona_diminuendo", o.abilities[1].dv("DiminuendoDuration", 3.0), {"dmg_amp": -weak}, o,
						{"name": "Diminuendo", "debuff": true})
			2:
				K.slow(target, 0.5 + 0.0004 * o.stats.ap, o.abilities[2].dv("TempoDuration", 2.0), o, false, "sona_tempo")
		SonaUtil.fx_on(target, CHORD_TAR[clampi(song, 0, 2)])

	func _show_ready() -> void:
		_hide_ready()
		var o = owner
		var col: Color = SONG_COLORS[song]
		o.attack_color = col.lerp(Color.WHITE, 0.25)
		# League "Power Chord ready" rings of the active song (the next attack uses the song's chord missile, see vfx_map)
		ready_fx = LolVfx.attach(o, CHORD_READY[clampi(song, 0, 2)], {"loop": true, "dir": o.facing})

	func _hide_ready() -> void:
		if ready_fx != null and is_instance_valid(ready_fx):
			ready_fx.stop()
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
		var dmg := damage()
		var self_ref := self
		var targets := pick_targets()
		for i in targets.size():
			var tgt: Unit = targets[i]
			var from: Vector3 = o.global_position + Vector3(0, 1.4, 0) + o.facing.rotated(Vector3.UP, 0.7 if i == 0 else -0.7) * 0.6
			# bolt: vfx_map "Q_mis" (Sona_Base_Q_Mis); impact: "Q_tar" (Sona_Base_Q_Tar)
			K.homing_missile(self, from, tgt, 1300.0, func(_mm, u):
				self_ref.hit(u, dmg, G.DmgType.MAGIC, {"tag": "q"})
				if u.kind == G.Kind.CHAMPION:
					SonaUtil.add_accel(o, 1.0),
				{"lol": "Sona_Base_Q_Mis"})
		var on_hit_dmg := dv("BaseOnHitDamage") + dv("OnHitRatio", 0.1) * ap()
		var dur := dv("OnHitDuration", 5.0)
		var q_icon := icon
		SonaUtil.melody(self, "Q", func(a):
			a.remove_buffs_by_id("sona_q_onhit")
			var b := HymnBuff.new()
			b.duration = dur
			b.remaining = dur
			b.dmg = on_hit_dmg
			b.icon = q_icon
			b.vfx = SonaUtil.fx_on(a, "Sona_Base_Q_Buff", {"loop": true})
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
			LolVfx.spawn(owner.match_ref, "Sona_Base_Q_Target_Hit", target.global_position + Vector3(0, target.height * 0.5, 0),
					{"dir": G.flat_dir(owner.global_position, target.global_position)})


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
		SonaUtil.fx_on(o, "Sona_Base_W_tar")
		var a := best_ally()
		if a != null:
			var injured: bool = a.hp < a.stats.max_hp - 1.0
			Combat.heal(o, a, heal)
			if injured:
				SonaUtil.add_accel(o, 1.0)
			# League heal note flying to the ally (visual only, the heal is instant)
			var aw := weakref(a)   # (a captured Unit freed before the callback runs would log an error)
			SonaUtil.fly(m, "Sona_Base_W_Mis", o.global_position + Vector3(0, 1.3, 0), a, 0.25, func(): SonaUtil.fx_on(aw.get_ref(), "Sona_Base_W_tar"))
		var shield := dv("BaseShield") + dv("ShieldRatio", 0.25) * ap()
		var sdur := dv("ShieldDuration", 1.5)
		var bp := dv("AccelerandoShieldBreakpoint", 25.0)
		SonaUtil.melody(self, "W", func(u):
			var sh: Dictionary = Combat.shield(o, u, shield, sdur, {"id": "sona_w"})
			var sfx := SonaUtil.fx_on(u, "Sona_Base_W_Shield", {"loop": true})
			if sfx != null:
				# the shield bubble ends with the shield (broken early, expired or the unit died)
				K.track_shield_fx(u, sh, sfx)
				K.stop_later(m, sdur + 0.05, sfx, true, 0.1)
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
		o.remove_buffs_by_id("sona_e_self")
		b.vfx = SonaUtil.fx_on(o, "Sona_Base_E_Buff", {"loop": true, "dir": o.facing})
		o.add_buff(b, o)
		var ms := dv("AllyBaseMovementSpeed", 0.1) + 0.0002 * ap()
		var mdur := dv("AllyMovementSpeedDuration", 3.0)
		SonaUtil.melody(self, "E", func(u):
			if u == o:
				return
			K.haste(u, ms, mdur, o, false, "sona_e_ally"))
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
		# cast: vfx_map "R_cas" (Sona_Base_R_Cas); impact: "R_tar" (Sona_Base_R_Tar)
		var on_hit := func(_mm, u):
			self_ref.hit(u, dmg, G.DmgType.MAGIC, {"is_aoe": true, "tag": "r"})
			var sb := K.stun(u, stun, o)
			# League Crescendo stun visual replaces the generic stun stars
			if sb != null:
				if sb.vfx != null and is_instance_valid(sb.vfx):
					sb.vfx.queue_free()
				sb.vfx = SonaUtil.fx_on(u, "Sona_Base_R_buf", {"loop": true})
		var mi := K.line_missile(self, o.global_position + Vector3(0, 0.0, 0) + dir * 0.4, dir, 2400.0, TRAVEL, {
			"width": half_width(), "pierce": true, "lol": "Sona_Base_R_Missile", "height": 1.0, "on_hit": on_hit,
		})
		mi.blockable = true
		var gp: Vector3 = o.global_position
		if m.camera_rig != null and G.player != null and G.flat_dist(G.player.global_position, gp) < 14.0:
			m.camera_rig.shake(0.2)
		notify_cast(t)

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
