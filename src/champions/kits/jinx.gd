extends ChampionKit
## Jinx, the Loose Cannon.

const PINK := Color(1.0, 0.35, 0.8)
const CYAN := Color(0.3, 0.85, 1.0)
const ORANGE := Color(1.0, 0.5, 0.15)

var _hook = null   ## SwitcherooHook (weapon state for the League VFX mapping)


func build_kit() -> void:
	c.attack_missile_speed = 2750.0
	c.attack_color = CYAN
	c.role = "marksman"
	c.level_order = "QWEQQRQWQWRWWEEREE"
	var pd: Dictionary = spell("JinxPassiveMarker").get("data_values", {})
	c.passive = GetExcited.new(pd)
	c.add_effect(c.passive)
	var q = init_ability(Switcheroo.new(), "Q")
	# JinxQ's mCastTime (0.25) would root Jinx on every swap: Switcheroo is instant in League (it even
	# cancels into the next attack), so drop the windup
	q.cast_time = 0.0
	q.rocket_mana = q.rv(q.costs)
	q.costs = [0.0]
	c.abilities[0] = q
	c.abilities[1] = init_ability(Zap.new(), "W")
	c.abilities[2] = init_ability(FlameChompers.new(), "E")
	var r = init_ability(DeathRocket.new(), "R")
	r.cast_range = 25000.0
	r.ind_length = 2500.0
	c.abilities[3] = r
	_hook = SwitcherooHook.new(q)
	c.add_effect(_hook)
	c.add_effect(BotLeveler.new())


func ai_tuning() -> Dictionary:
	return {"aggression": 0.55}


## League VFX: basic attacks follow the active weapon (read while the attack missile spawns / lands).
## Cast flashes, chompers and the Super Mega Death Rocket explosion are spawned by the abilities.
func vfx_map() -> Dictionary:
	var rocket_shot: bool = _hook != null and _hook._pending == 2
	var rocket_hit: bool = _hook != null and _hook._rocket_hit
	var mis := "Jinx_Base_Q_Rocket_mis" if rocket_shot else "Jinx_Base_Q_Minigun_Mis"
	var tar := "Jinx_Base_Q_Rocket_Tar_Unit" if rocket_hit else "Jinx_Base_Q_Minigun_Tar"
	return {
		"BA_mis": mis, "BA_crit_mis": "Jinx_Base_Q_Rocket_Crit_Mis" if rocket_shot else mis,
		"BA_tar": tar, "BA_crit_tar": tar,
		"Q_cas": "", "Q_mis": "", "Q_tar": "",
		"W_cas": "", "W_mis": "Jinx_Base_W_Mis", "W_tar": "Jinx_Base_W_Tar",
		"E_cas": "", "E_mis": "Jinx_Base_E_Mis", "E_tar": "",
		"R_cas": "", "R_mis": "Jinx_Base_R_Mis", "R_tar": "",
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
		return super(t)

	func skip() -> Dictionary:
		return {"skip": true}

	func ground(p: Vector3) -> Vector3:
		var m = owner.match_ref
		return Vector3(p.x, m.nav.height_at(p) if m.nav != null else 0.0, p.z)

	## Enemy minions standing on the segment owner->to (before `to`).
	func minions_blocking(ctx, to: Vector3, hw_m: float) -> int:
		var a: Vector3 = owner.global_position
		var dmax := G.flat_dist(a, to)
		var n := 0
		for mn in ctx.enemy_minions:
			if G.flat_dist(a, mn.global_position) > dmax:
				continue
			if NavGrid._dist_to_segment(mn.global_position, a, to) <= hw_m + mn.radius:
				n += 1
		return n


class FX extends RefCounted:
	static func solid(mesh: Mesh, color: Color, energy: float = 2.0) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var mat := Vfx.add_material(color, energy, false)
		mat.set_shader_parameter("use_mask", false)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return mi

	## True when `u` fights against the local player (League's red / enemy-colored variants).
	static func is_enemy_of_player(u) -> bool:
		return G.player != null and is_instance_valid(G.player) and G.player.team != u.team

	## League flash attached at the weapon (League effects are bone-relative; we use a hand height + forward offset).
	static func hand_fx(u: Unit, name: String, dir: Vector3, h: float = 1.1, fwd: float = 0.6) -> LolVfx:
		var d := Vector3(dir.x, 0.0, dir.z)
		if d.length_squared() < 0.001:
			d = u.facing
		d = d.normalized()
		var fx := LolVfx.attach(u, name, {"dir": d, "height": h})
		if fx != null:
			fx.position += d * fwd
		return fx


# ===================================================================== passive
class GetExcited extends Effect:
	var dmg_times := {}
	var ms_buff := 1.75
	var as_buff := 0.25
	var duration := 6.0
	var window := 3.0
	var _connected := false

	func _init(pd: Dictionary) -> void:
		id = "jinx_passive"
		display_name = "Get Excited!"
		ms_buff = float(pd.get("MSBuff", 175.0)) / 100.0
		as_buff = float(pd.get("ASBuff", 25.0)) / 100.0
		duration = float(pd.get("BuffDuration", 6.0))
		window = float(pd.get("AssistMarkerDuration", 3.0))

	func hud_counter() -> String:
		if owner == null:
			return ""
		var b: Buff = owner.find_buff("jinx_excited_as")
		return str(b.stacks) if b != null else ""

	func on_damage_dealt(info) -> void:
		var t = info.target
		if t == null or owner.match_ref == null:
			return
		if t.kind == G.Kind.CHAMPION or t.kind == G.Kind.TURRET or t.kind == G.Kind.INHIBITOR or t.kind == G.Kind.NEXUS:
			dmg_times[t] = owner.match_ref.time
			if not _connected and t.kind != G.Kind.CHAMPION:
				_connected = true
				G.structure_destroyed.connect(_on_structure)

	func _recent(u) -> bool:
		return dmg_times.has(u) and owner.match_ref != null and owner.match_ref.time - float(dmg_times[u]) <= window

	func on_takedown(victim) -> void:
		if victim.kind == G.Kind.CHAMPION and _recent(victim):
			excite(true)

	func _on_structure(s, _k) -> void:
		if owner != null and is_instance_valid(owner) and not owner.dead and _recent(s):
			excite(false)

	func excite(champ: bool) -> void:
		var o = owner
		var hb: Buff = K.haste(o, ms_buff, duration, o, true, "jinx_excited_ms")
		# League: speed lines while excited (stopped with the haste buff) + a burst on trigger
		if hb != null and (hb.vfx == null or not is_instance_valid(hb.vfx)):
			hb.vfx = LolVfx.attach(o, "Jinx_Base_Passive_Buff", {"loop": true, "dir": o.facing})
		LolVfx.attach(o, "Jinx_Base_Passive_Buff_OnKill", {"height": 1.0})
		var b: Buff = o.find_buff("jinx_excited_as")
		if b == null:
			K.buff(o, "jinx_excited_as", duration, {}, o, {"name": "Get Excited!", "icon": icon,
				"per_stack": {"as": as_buff}, "max_stacks": 5, "stack_mode": Buff.Stack.ADD_STACK})
		else:
			if champ:
				b.stacks = mini(5, b.stacks + 1)
			b.remaining = duration
			b.duration = duration
		o.stats.mark_dirty()
		var m = o.match_ref
		m.fx_text(o, "Get Excited!", PINK)
		var q = o.abilities[0]
		if q != null:
			q.refresh_anims()
			m.after(duration + 0.05, func():
				if is_instance_valid(o):
					q.refresh_anims())


# ===================================================================== Q
class Switcheroo extends KitAbility:
	var rockets := false
	var rocket_mana := 20.0
	var _base_anims := {}
	var _last_toggle := -10.0

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

	func bonus_range() -> float:
		return dv("RocketBonusRange", 100.0)

	func execute(t: Dictionary) -> void:
		set_form(not rockets)
		if owner.windup_timer < 0.0:
			owner.play_spell_anim("spell1", 0.3)
		notify_cast(t)

	func set_form(r: bool) -> void:
		var o = owner
		rockets = r
		toggled = r
		_last_toggle = o.match_ref.time if o.match_ref != null else 0.0
		o.stats.mark_dirty()
		refresh_anims()
		# no League swap effect (the weapon change is animation-only); the next shot shows the new weapon's VFX

	func _clips(names: Array) -> Array:
		var out := []
		for n in names:
			var raw: String = owner._raw_clip(n)
			if raw != "":
				out.append(raw)
		return out

	func refresh_anims() -> void:
		var o = owner
		if _base_anims.is_empty():
			for k in ["attack", "crit", "run"]:
				_base_anims[k] = o.anim_map.get(k, []).duplicate()
		for k in _base_anims:
			o.anim_map[k] = _base_anims[k].duplicate()
		if rockets:
			var atk := _clips(["r_attack1", "r_attack2"])
			if not atk.is_empty():
				o.anim_map["attack"] = atk
				o.anim_map["crit"] = atk
			var run := _clips(["r_run_base"])
			if not run.is_empty():
				o.anim_map["run"] = run
		elif o.has_buff("jinx_excited_ms"):
			var fast := _clips(["run_haste", "run_fast"])
			if not fast.is_empty():
				o.anim_map["run"] = [fast[0]]
		if o.cur_anim == "run" or o.cur_anim == "idle":
			o.cur_anim = ""

	func add_rev() -> void:
		var o = owner
		var per := dv("MinigunAttackSpeedMax", 30.0) / 100.0 / maxf(1.0, dv("MinigunAttackSpeedStacks", 3.0))
		var b = o.find_buff("jinx_revd")
		if b == null:
			var nb := RevdUp.new()
			nb.per = per
			nb.duration = dv("MinigunAttackSpeedDuration", 2.5)
			nb.remaining = nb.duration
			nb.icon = icon
			o.add_buff(nb, o)
		else:
			b.per = per
			b.stacks = mini(b.max_stacks, b.stacks + 1)
			b.remaining = b.duration
		o.stats.mark_dirty()

	func rocket_splash(target: Unit, info) -> void:
		var o = owner
		var m = o.match_ref
		var pos: Vector3 = target.global_position
		var r_units := dv("RocketAoERadius", 250.0)
		var dmg: float = o.stats.ad * dv("RocketTAD", 1.1)
		if info != null and info.is_crit:
			dmg *= o.stats.crit_damage
		var dir := G.flat_dir(o.global_position, pos)
		for u in m.enemies_in_radius(o.team, pos, r_units * G.U):
			if u == target:
				continue
			Combat.deal(o, u, dmg, G.DmgType.PHYSICAL, {"is_aoe": true, "tag": "jinx_rocket_splash"})
			if is_instance_valid(u):
				LolVfx.spawn(m, "Jinx_Base_Q_Rocket_Tar_Unit", u.global_position + Vector3(0, u.height * 0.5, 0), {"dir": dir})
		# League rocket explosion (blast + splash dome) at the target's feet
		LolVfx.spawn(m, "Jinx_Base_Q_Rocket_tar", ground(pos), {"dir": dir, "height": 0.1})

	# --------------------------------------------------------------- AI
	func ai_consider(ctx) -> Dictionary:
		var o = owner
		if o.match_ref.time - _last_toggle < 1.5:
			return skip()
		if _want_rockets(ctx) != rockets:
			return {"pos": o.global_position, "dir": o.facing, "unit": null}
		return skip()

	func _want_rockets(ctx) -> bool:
		var o = owner
		var mana_r: float = o.mana / maxf(o.stats.max_mana, 1.0)
		if mana_r < 0.12:
			return false
		var bonus_m := bonus_range() * G.U
		var mini_m: float = o.attack_range_m() - (bonus_m if rockets else 0.0)
		var rock_m := mini_m + bonus_m
		var e: Unit = ctx.focus
		if e != null and is_instance_valid(e) and not e.dead:
			var d: float = o.edge_dist(e)
			# poke / finish from max range
			if d > mini_m and d <= rock_m + 1.5 and mana_r > 0.2:
				return true
			# teamfight splash: three or more units bunched up around the target
			if ctx.count_enemies_near(e.global_position, 2.5, false) >= 3 and mana_r > 0.3:
				return true
			if ctx.count_enemies_near(e.global_position, 2.5) >= 2 and mana_r > 0.25:
				return true
			return false
		for ec in ctx.enemies:
			var d2: float = o.edge_dist(ec)
			if d2 > mini_m and d2 <= rock_m and mana_r > 0.4:
				return true
		var t = o.attack_target
		if t != null and is_instance_valid(t) and not t.dead and t.kind == G.Kind.MINION and mana_r > 0.55:
			var n := 0
			for mn in ctx.enemy_minions:
				if G.flat_dist(mn.global_position, t.global_position) <= 2.5:
					n += 1
			return n >= 3
		return false


class RevdUp extends Buff:
	var per := 0.1

	func _init() -> void:
		super("jinx_revd", 2.5)
		display_name = "Rev'd up!"
		max_stacks = 3
		stack_mode = Stack.ADD_STACK

	func get_stat_mods() -> Dictionary:
		return {"as": per * stacks}

	## Stacks fall off one at a time.
	func tick(unit, dt: float) -> bool:
		if removed:
			return false
		remaining -= dt
		if remaining <= 0.0:
			stacks -= 1
			if stacks <= 0:
				return false
			remaining = 0.6
			unit.stats.mark_dirty()
		return true


## Modifies Jinx's basic attacks according to the active weapon.
class SwitcherooHook extends Effect:
	var q
	var _pending := 0          ## 1 = minigun shot, 2 = rocket about to spawn
	var _rocket_hit := false
	var _listening := false
	var _as_pen := 0.0

	func _init(p_q) -> void:
		q = p_q
		id = "jinx_q_hook"
		hidden = true

	func get_stat_mods() -> Dictionary:
		if q.level <= 0 or not q.rockets:
			_as_pen = 0.0
			return {}
		# rockets scale less with bonus attack speed
		var raw: float = owner.stats.bonus_as - _as_pen
		_as_pen = -q.dv("RocketASPDPenalty", 0.1) * maxf(raw, 0.0)
		return {"range": q.bonus_range(), "as": _as_pen}

	func on_attack_launch(target) -> void:
		var m = owner.match_ref
		if m == null:
			return
		if q.level > 0:
			if not _listening:
				_listening = true
				m.missiles_root.child_entered_tree.connect(_on_missile)
			if q.rockets:
				if owner.mana >= q.rocket_mana:
					owner.mana -= q.rocket_mana
					_pending = 2
				else:
					_pending = 1
					q.set_form(false)
					q.add_rev()
			else:
				_pending = 1
				q.add_rev()
		# League muzzle flash of the active weapon (the missile visual itself comes from the kit's vfx_map)
		var dir: Vector3 = owner.facing
		if target != null and is_instance_valid(target):
			dir = G.flat_dir(owner.global_position, target.global_position)
		FX.hand_fx(owner, "Jinx_Base_Q_Rocket_Cas" if _pending == 2 else "Jinx_Base_Q_Minigun_Cas_Medium", dir, owner.height * 0.55, owner.radius)

	func _on_missile(node) -> void:
		if _pending == 0 or not (node is Missile):
			return
		var mi: Missile = node
		if not mi.is_attack or mi.source != owner:
			return
		var rocket := _pending == 2
		_pending = 0
		if rocket:
			var orig: Callable = mi.on_hit
			var self_ref := self
			mi.on_hit = func(m2, u):
				self_ref._rocket_hit = true
				orig.call(m2, u)
				self_ref._rocket_hit = false

	func on_pre_damage_dealt(info) -> void:
		if _rocket_hit and info.is_attack:
			info.amount *= q.dv("RocketTAD", 1.1)
			info.tag = "jinx_rocket"

	func on_attack_hit(target, info) -> void:
		if _rocket_hit:
			_rocket_hit = false
			q.rocket_splash(target, info)
			_rocket_hit = true


# ===================================================================== W
class Zap extends KitAbility:
	func _init() -> void:
		target_type = Target.DIRECTION
		indicator = Ind.LINE
		ind_width = 120.0
		cast_time = 0.6
		anim = "spell2"
		anim_lock = 0.6

	func windup() -> float:
		return maxf(dv("JinxLowEndWCastTime", 0.4), 0.6 - 0.08 * maxf(0.0, owner.stats.bonus_as))

	func begin_cast(t: Dictionary) -> void:
		cast_time = windup()
		anim_lock = cast_time + 0.15
		super(t)
		# League Zapper charge flash at the gun (replaces the procedural charge orb)
		FX.hand_fx(owner, "Jinx_Base_W_Cas", t.get("dir", owner.facing), 1.25, 0.8)

	func damage() -> float:
		return dv("Damage") + dv("ADRatio", 1.4) * ad()

	func execute(t: Dictionary) -> void:
		var o = owner
		var from: Vector3 = K.cast_pos(o, 1.25)
		var dir: Vector3 = t.dir
		var dmg := damage()
		var slow := dv("SlowPercent", 40.0) / 100.0
		var slow_t := dv("SlowDuration", 2.0)
		var range_u := cast_range
		var self_ref := self
		# League visuals: W_Mis (missile), W_Tar (auto, on damage), W_Slow (on the slowed unit while slowed)
		K.line_missile(self, from, dir, 3300.0, range_u, {
			"width": 60.0, "lol": "Jinx_Base_W_Mis",
			"on_hit": func(_mi, u):
				self_ref.hit(u, dmg, G.DmgType.PHYSICAL, {"tag": "w"})
				var sb: Buff = K.slow(u, slow, slow_t, o, false, "jinx_w_slow")
				# League W slow effect replaces the generic slow trail (K.slow attaches Global_Slow on champions)
				if sb != null and not sb.has_meta("jinx_fx"):
					sb.set_meta("jinx_fx", true)
					K.kill_fx(sb.vfx, 0.0)
					sb.vfx = LolVfx.attach(u, "Jinx_Base_W_Slow", {"loop": true}),
		})
		notify_cast(t)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var rng := range_m() * 0.95
		var best: Unit = null
		var best_s := -INF
		var best_aim := Vector3.ZERO
		for e in ctx.enemies:
			var d := G.flat_dist(o.global_position, e.global_position)
			if d > rng:
				continue
			var aim: Vector3 = ctx.predict(e, windup() + d / 33.0)
			if G.flat_dist(o.global_position, aim) > rng + 0.5:
				continue
			if minions_blocking(ctx, aim, 0.6) > 0:
				continue
			var s: float = (1.0 - e.hp_ratio()) * 3.0 - d * 0.08
			if (e.cc & Buff.IMMOBILIZE) != 0:
				s += 2.5
			if e == ctx.focus:
				s += 1.0
			if s > best_s:
				best_s = s
				best = e
				best_aim = aim
		if best == null:
			return skip()
		var mana_r: float = o.mana / maxf(o.stats.max_mana, 1.0)
		# don't stand still for the windup while a melee is on top of us unless it's to peel
		var melee_close := false
		for e in ctx.enemies:
			if e.stats.attack_range < 300.0 and o.edge_dist(e) < 1.5:
				melee_close = true
		if melee_close and best.edge_dist(o) > 2.5:
			return skip()
		if ctx.mode == "fight" or ctx.mode == "retreat" or mana_r > 0.4 or best.hp_ratio() < 0.35:
			return ctx.aim_at(best_aim, self)
		return skip()


# ===================================================================== E
## League (wiki Flame Chompers!): three chompers centred on the target point in a row perpendicular to the throw,
## collision (trigger) radius 115, explosion radius 225, land after 0.4 s, arm 0.5 s, last 5 s. The row spans
## the spell's castRadius (315) on each side: outer chompers sit 315 - 115 = 200 units from the centre.
## The targeter is that row of three circles (custom: the core indicator set has no multi-circle shape).
class FlameChompers extends KitAbility:
	const TRIGGER_R := 115.0
	const BLAST_R := 225.0
	const SPACING := 200.0
	const LAND_TIME := 0.4
	var _ind: Node3D = null

	func _init() -> void:
		target_type = Target.POINT
		indicator = Ind.NONE     # drawn by _update_indicator (range ring still comes from the controller)
		ind_radius = TRIGGER_R
		cast_time = 0.25
		anim = "spell3"
		anim_lock = 0.45

	## Chomper positions for a throw at `center` (row perpendicular to the cast direction).
	func layout(center: Vector3) -> Array:
		var fwd := G.flat_dir(owner.global_position, center)
		if fwd.length_squared() < 0.01:
			fwd = owner.facing
		var side := Vector3(-fwd.z, 0, fwd.x)
		return [center - side * SPACING * G.U, center, center + side * SPACING * G.U]

	func on_tick(_dt: float) -> void:
		_update_indicator()

	## Local player aiming E: three League "aoe" circles at the chomper spots (no allocation per frame).
	func _update_indicator() -> void:
		var o = owner
		var pc = o.controller if o == G.player else null
		var show: bool = pc != null and is_instance_valid(pc) and pc is PlayerController and pc.aiming == slot and not o.dead
		if not show:
			if _ind != null and is_instance_valid(_ind):
				_ind.visible = false
			return
		var m = o.match_ref
		if _ind == null or not is_instance_valid(_ind):
			_ind = Node3D.new()
			_ind.name = "JinxEIndicator"
			m.add_child(_ind)
			for i in 3:
				var mi := Vfx.indicator_mesh(0, Color(1, 1, 1, 0.95))
				mi.scale = Vector3(TRIGGER_R * 2.0 * G.U, 1, TRIGGER_R * 2.0 * G.U)
				_ind.add_child(mi)
		_ind.visible = true
		var col := Color(1, 1, 1, 0.95) if is_ready() and can_afford() else Color(0.5, 0.5, 0.55, 0.55)
		var spots := layout(make_target(pc.mouse_ground, null).pos)
		for i in 3:
			var mi: MeshInstance3D = _ind.get_child(i)
			var p: Vector3 = spots[i]
			mi.global_position = Vector3(p.x, (m.nav.height_at(p) if m.nav != null else p.y) + 0.12, p.z)
			mi.material_override.set_shader_parameter("color", col)

	func damage() -> float:
		return dv("Damage") + 1.0 * ap()

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var center: Vector3 = t.pos
		var self_ref := self
		var cast_hits := {}
		for spot in layout(center):
			var p: Vector3 = spot
			if m.nav != null and not m.nav.is_walkable(p):
				p = m.nav.nearest_walkable(p)
			K.arc_missile(self, o.global_position + Vector3(0, 1.3, 0), p, LAND_TIME, func(_mi, _pos): self_ref._place(p, cast_hits), {"lol": "Jinx_Base_E_Mis", "arc": 2.2})
		notify_cast(t)

	static func _body_mesh() -> Mesh:
		var sm := SphereMesh.new()
		sm.radius = 0.24
		sm.height = 0.36
		return sm

	## Chomper body: League's chomper is an animated mesh (not supported by LolVfx), so the small
	## procedural body stays; the trigger ring / set / explosion effects are League's.
	func _chomper_visual(m, pos: Vector3, life: float) -> VfxNode:
		var n := VfxNode.new()
		n.lifetime = life
		m.add_fx(n, pos)
		var body := FX.solid(_body_mesh(), Color(0.75, 0.2, 0.5), 1.3)
		body.position.y = 0.2
		n.add_child(body)
		var jaw := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.2
		tm.outer_radius = 0.27
		jaw.mesh = tm
		var jm := Vfx.add_material(Color(1.0, 0.95, 0.9), 2.0, false)
		jm.set_shader_parameter("use_mask", false)
		jaw.material_override = jm
		jaw.position.y = 0.2
		jaw.scale = Vector3(1, 0.35, 1)
		n.add_child(jaw)
		for sx in [-1.0, 1.0]:
			var eye := Vfx.sprite(Color(1.0, 0.9, 0.2), 0.14, 3.0)
			eye.position = Vector3(sx * 0.1, 0.38, 0.0)
			n.add_child(eye)
		# League trigger-area ring, team colored (red = hostile to the local player)
		var ring := LolVfx.spawn(m, "Jinx_Base_E_Mine_Ready_Red" if FX.is_enemy_of_player(owner) else "Jinx_Base_E_Mine_Ready_Green", pos, {"loop": true, "height": 0.05})
		n.set_meta("ring", ring)
		if ring != null:
			var wr := weakref(ring)   # the ring may already have faded out (exploded chomper)
			m.after(life, func():
				var r = wr.get_ref()
				if r != null:
					r.stop())
		var tw := n.create_tween().set_loops()
		tw.tween_property(body, "scale", Vector3(1.1, 0.8, 1.1), 0.18)
		tw.tween_property(body, "scale", Vector3.ONE, 0.18)
		return n

	func _place(p: Vector3, cast_hits: Dictionary) -> void:
		var o = owner
		if not is_instance_valid(o):
			return
		var m = o.match_ref
		var pos := ground(p)
		var arm := dv("GrenadeArmTime", 0.5)
		var dur := dv("GrenadeDuration", 5.0)
		var node := _chomper_visual(m, pos, arm + dur)
		LolVfx.spawn(m, "Jinx_Base_E_Mine_Set", pos, {"height": 0.1})
		var st := {"age": 0.0, "armed": false, "acc": 0.0}
		var self_ref := self
		m.add_ticker(arm + dur, func(dt: float) -> bool:
			st.age += dt
			if not is_instance_valid(o):
				return false
			if st.age < arm:
				return true
			if not st.armed:
				st.armed = true
				LolVfx.spawn(m, "Jinx_Base_E_Mine_Ready", pos, {"height": 0.3})
			# trigger check at League's server tick (30 Hz) instead of every rendered frame
			st.acc += dt
			if st.acc < 1.0 / 30.0:
				return true
			st.acc = 0.0
			var caught: Array = m.enemies_in_radius(o.team, pos, TRIGGER_R * G.U, true)
			if caught.is_empty():
				return true
			self_ref._explode(pos, node, cast_hits)
			return false)

	func _explode(pos: Vector3, node: VfxNode, cast_hits: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		if is_instance_valid(node):
			var ring = node.get_meta("ring", null)
			if ring != null and is_instance_valid(ring):
				ring.stop()
			node.detach_and_fade()
		var root_t := dv("RootDuration", 1.5)
		for u in m.enemies_in_radius(o.team, pos, (TRIGGER_R + 40.0) * G.U, true):
			var rb: Buff = K.root(u, root_t, o, ORANGE)
			# League chomper bite on the rooted champion instead of the generic root aura
			if rb != null and not (rb.vfx is LolVfx):
				if rb.vfx != null and is_instance_valid(rb.vfx):
					rb.vfx.queue_free()
				rb.vfx = LolVfx.attach(u, "Jinx_Base_E_Mine_Debuff", {"loop": true})
		# chompers of the same throw don't stack their damage on one enemy
		var dmg := damage()
		for u in m.enemies_in_radius(o.team, pos, BLAST_R * G.U):
			if cast_hits.has(u):
				continue
			cast_hits[u] = true
			hit(u, dmg, G.DmgType.MAGIC, {"is_aoe": true, "tag": "e"})
		LolVfx.spawn(m, "Jinx_Base_E_Mine_Explosion", pos, {"height": 0.05})
		if m.camera_rig != null and (o == G.player):
			m.camera_rig.shake(0.15)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var rng := range_m()
		# combo onto immobilized champions (guaranteed chomp)
		for e in ctx.enemies:
			var d := G.flat_dist(o.global_position, e.global_position)
			if d <= rng + 0.5 and (e.cc & Buff.IMMOBILIZE) != 0:
				var rem := 0.0
				for b in e.buffs:
					if (b.cc & Buff.IMMOBILIZE) != 0:
						rem = maxf(rem, b.remaining)
				if rem > 0.6:
					return make_target(e.global_position, null)
		# peel: a diver is on top of us -> drop chompers at our feet / between us
		for e in ctx.enemies:
			if o.edge_dist(e) < 2.5 and (e.stats.attack_range < 300.0 or ctx.in_danger()):
				var mid: Vector3 = o.global_position.lerp(e.global_position, 0.6)
				return make_target(mid, null)
		# retreat: zone the chaser
		if ctx.mode == "retreat" and not ctx.enemies.is_empty():
			var e0: Unit = ctx.enemies[0]
			if G.flat_dist(o.global_position, e0.global_position) < rng:
				var p: Vector3 = o.global_position.lerp(e0.global_position, 0.5)
				return make_target(p, null)
		# fight: throw onto the predicted path of the focus target
		if ctx.mode == "fight" and ctx.focus != null:
			var f: Unit = ctx.focus
			var df := G.flat_dist(o.global_position, f.global_position)
			if df <= rng and (f.hp_ratio() < 0.5 or (f.cc & Buff.CC.ROOT) == 0 and f.stats.slow > 0.2 or df < o.attack_range_m() + 1.0):
				return ctx.aim_at(ctx.predict(f, 0.9), self)
		return skip()


# ===================================================================== R
class DeathRocket extends KitAbility:
	const V0 := 17.0
	const ACCEL := 8.0
	const VMAX := 25.0

	func _init() -> void:
		target_type = Target.DIRECTION
		indicator = Ind.LINE
		ind_width = 280.0
		cast_time = 0.6
		anim = "spell4"
		anim_lock = 0.9

	func max_damage() -> float:
		return dv("MaxDamage") + 1.2 * bonus_ad()

	## Damage vs a unit after `age` seconds of rocket flight (10% -> 100% over the first second).
	func damage_vs(u: Unit, age: float) -> float:
		var k := clampf(age, 0.1, 1.0)
		return max_damage() * k + dv("PercentDamage", 25.0) / 100.0 * maxf(0.0, u.stats.max_hp - u.hp)

	static func travel_time(d: float) -> float:
		var d_acc := (VMAX * VMAX - V0 * V0) / (2.0 * ACCEL)
		if d <= d_acc:
			return (-V0 + sqrt(V0 * V0 + 2.0 * ACCEL * d)) / ACCEL
		return (VMAX - V0) / ACCEL + (d - d_acc) / VMAX

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var from: Vector3 = K.cast_pos(o, 1.3)
		var dir: Vector3 = t.dir
		var self_ref := self
		# League: launch flash at the launcher, rocket (R_Mis) + exhaust / trails (R_Rocket_Child, R_Booster) following it
		LolVfx.spawn(m, "Jinx_Base_R_Cas", from, {"dir": dir})
		var mi := K.line_missile(self, from, dir, V0 * 100.0, 25000.0, {
			"width": 140.0, "minions": false, "lol": "Jinx_Base_R_Mis", "height": 1.3,
			"accel": ACCEL * 100.0, "max_speed": VMAX * 100.0,
			"on_hit": func(mm, u): self_ref._explode(u.global_position, u, mm.age),
		})
		mi.lifetime = 12.0
		mi.blockable = true
		for nm in ["Jinx_Base_R_Rocket_Child", "Jinx_Base_R_Booster"]:
			var fx := LolVfx.spawn(m, nm, from, {"dir": dir, "loop": true})
			if fx != null:
				fx.follow = mi   # follows the rocket, fades out when the missile is gone
		if m.camera_rig != null and o == G.player:
			m.camera_rig.shake(0.2)
		notify_cast(t)

	func _explode(pos: Vector3, primary: Unit, age: float) -> void:
		var o = owner
		if not is_instance_valid(o):
			return
		var m = o.match_ref
		var aoe_mult := dv("AoEDamageMult", 0.8)
		if is_instance_valid(primary) and not primary.dead:
			hit(primary, damage_vs(primary, age), G.DmgType.PHYSICAL, {"tag": "r"})
		for u in m.enemies_in_radius(o.team, pos, dv("AoERadius", 400.0) * G.U):
			if u == primary:
				continue
			hit(u, damage_vs(u, age) * aoe_mult, G.DmgType.PHYSICAL, {"tag": "r", "is_aoe": true})
		var gp := ground(pos)
		LolVfx.spawn(m, "Jinx_Base_R_Tar", gp, {"dir": G.flat_dir(o.global_position, gp), "height": 0.05})
		if m.camera_rig != null:
			var near_player: bool = G.player != null and G.flat_dist(G.player.global_position, gp) < 14.0
			m.camera_rig.shake(0.5 if near_player or o == G.player else 0.1)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var m = o.match_ref
		var from: Vector3 = o.global_position
		var best: Unit = null
		var best_s := -INF
		var best_aim := Vector3.ZERO
		for e in m.champions:
			if e.team == o.team or e.dead or not e.is_targetable_by(o.team):
				continue
			var d := G.flat_dist(from, e.global_position)
			if d > 160.0 or d < 2.0:
				continue
			var tt := cast_time + travel_time(d)
			var v: Vector3 = e.velocity if (e.cc & Buff.BLOCK_MOVE) == 0 else Vector3.ZERO
			var aim: Vector3 = e.global_position + v * minf(tt, 2.5) * 0.75
			var dmg := damage_vs(e, travel_time(G.flat_dist(from, aim))) * Combat.resist_multiplier(e.stats.armor, o, true)
			var ehp: float = e.hp + e.total_shield()
			if _blocked(from, aim, e):
				continue
			var s := -INF
			if dmg >= ehp * 1.05:
				# execute anywhere on the map; nearer shots are more reliable
				s = 100.0 - d * 0.2 + (5.0 if (e.cc & Buff.IMMOBILIZE) != 0 else 0.0)
				if d > 40.0 and (e.cc & Buff.IMMOBILIZE) == 0 and v.length() > 1.0:
					s -= 20.0
			elif ctx.mode == "fight" and d < 15.0:
				var n: int = ctx.count_enemies_near(aim, dv("AoERadius", 400.0) * G.U)
				if n >= 3 or (n >= 2 and e.hp_ratio() < 0.6) or (e.hp_ratio() < 0.35 and dmg >= ehp * 0.6):
					s = 20.0 + n * 5.0
			if s > best_s:
				best_s = s
				best = e
				best_aim = aim
		if best == null or best_s < 0.0:
			return skip()
		return ctx.aim_at(best_aim, self)

	## True if another enemy champion would catch the rocket before `target`.
	func _blocked(from: Vector3, to: Vector3, target: Unit) -> bool:
		var dmax := G.flat_dist(from, to)
		for e in owner.match_ref.champions:
			if e == target or e.team == owner.team or e.dead or not e.is_targetable_by(owner.team):
				continue
			if G.flat_dist(from, e.global_position) >= dmax:
				continue
			if NavGrid._dist_to_segment(e.global_position, from, to) <= 1.4 + e.radius:
				return true
		return false
