class_name Unit
extends Node3D
## Base class for every combat unit (champions, minions, turrets, structures, summons).
## Logic is driven by Match calling tick(dt) each frame.

enum Cmd { IDLE, MOVE, ATTACK, ATTACK_MOVE, HOLD }

signal died(unit, killer)

var match_ref = null
var team := 0
var kind := G.Kind.OTHER
var display_name := "Unit"
var uid := 0
var stats: Stats
var hp := 100.0
var mana := 0.0
var dead := false
var level := 1
var radius := 0.65            ## gameplay radius (m)
var path_radius := 0.35       ## collision/pathing radius (m)
var height := 1.8             ## health bar anchor height (m)
var selection_radius := 1.0   ## mouse pick radius (m)
var mass := 1.0               ## for soft collision (0 = immovable)
var effects: Array = []       ## Effect (includes buffs)
var buffs: Array = []         ## Buff subset
var shields: Array = []       ## [{amount,max,remaining,source,type,decay,id}]
var cc := 0                   ## active CC flags
var damage_log := {}          ## Unit -> time of last damage (assist credit)
var last_hit_by_champion_time := -100.0
var last_damaged_time := -100.0
var visible_to := [true, true, true]   ## per team vision
var in_brush := -1
var invulnerable_count := 0
var untargetable_count := 0
var is_bot := false
var damage_dealt_total := 0.0
var champion_damage_total := 0.0
var healing_done_total := 0.0
var healing_received_total := 0.0
var damage_taken_total := 0.0

# --- movement
var cmd := Cmd.IDLE
var path := PackedVector3Array()
var path_i := 0
var move_goal := Vector3.ZERO
var facing := Vector3.FORWARD
var moving := false
var _repath_timer := 0.0
var dash := {}                ## active dash state
var airborne_height := 0.0
var ground_y := 0.0
var display_scale := 1.0
var velocity := Vector3.ZERO
var _prev_pos := Vector3.INF

# --- attack
var attack_target: Unit = null
var attack_timer := 0.0       ## until next attack may start
var windup_timer := -1.0      ## >=0 while winding up
var windup_pct := 0.25
var windup_mod := 1.0         ## League mAttackDelayCastOffsetPercentAttackSpeedRatio (windup modifier)
var attack_missile_speed := 0.0   ## 0 = melee/instant
var attack_count := 0
var attack_move_goal := Vector3.ZERO
var acquisition_range := 7.0
var _pending_crit := false
var _windup_target: Unit = null

# --- casting
var casting := {}             ## {ability, target, t, total}
var channel := {}             ## {ability, t, total}
var pending_cast := {}        ## out-of-range cast waiting to approach
var queued_cast := {}         ## cast buffered during another cast/windup
var channel_disarm := false   ## can't attack while this channel runs

# --- visuals
var model: Node3D = null
var anim_player: AnimationPlayer = null
var anim_map := {}            ## logical -> [names]
var cur_anim := ""
var anim_lock := 0.0          ## seconds during which locomotion anims won't override
var hit_flash := 0.0
var materials: Array = []     ## ShaderMaterials for flash/outline params
var tint := Color(1, 1, 1, 1)
var fade := 1.0


var _stats_tick := 0.0
var _has_slow := false


func _init() -> void:
	stats = Stats.new(self)


# ===================================================================== setup
func setup_stats(data: Dictionary) -> void:
	stats.set_base(data)
	stats.level = level
	recompute_stats()
	hp = stats.max_hp
	mana = stats.max_mana


func recompute_stats() -> void:
	var old_max := stats.max_hp
	var old_max_mana := stats.max_mana
	stats.level = level
	stats.slow = _strongest_slow()
	stats.recompute(effects)
	if old_max > 0.0 and stats.max_hp > old_max and not dead:
		hp += stats.max_hp - old_max
	# League: gaining max mana (items, levels) grants the same amount of current mana
	if old_max_mana > 0.0 and stats.max_mana > old_max_mana:
		mana += stats.max_mana - old_max_mana
	hp = minf(hp, stats.max_hp)
	mana = minf(mana, stats.max_mana)
	var s := stats.size * display_scale
	if model != null:
		model.scale = Vector3.ONE * s


func _strongest_slow() -> float:
	var s := 0.0
	for b in buffs:
		if b.slow_amount > 0.0:
			s = maxf(s, b.current_slow())
	_has_slow = s > 0.0
	return s


# ===================================================================== effects
func add_effect(e: Effect) -> Effect:
	e.owner = self
	if e.source == null:
		e.source = self
	effects.append(e)
	e.on_attach(self)
	stats.mark_dirty()
	return e


func remove_effect(e: Effect) -> void:
	if e in effects:
		effects.erase(e)
		e.removed = true
		e.on_detach(self)
		stats.mark_dirty()


func find_effect(eid: String) -> Effect:
	for e in effects.duplicate():
		if e.id == eid:
			return e
	return null


func find_buff(bid: String, src = null) -> Buff:
	for b in buffs:
		if b.id == bid and (src == null or b.source == src):
			return b
	return null


func has_buff(bid: String) -> bool:
	return find_buff(bid) != null


## Apply a buff, honoring its stack mode. Returns the active buff instance.
func add_buff(b: Buff, src = null) -> Buff:
	if dead:
		return null
	if src != null:
		b.source = src
	if b.cc != 0:
		if has_cc_immunity() and (b.cc & Buff.HARD_CC) != 0:
			return null
		# [numbers] League: tenacity shortens crowd control by its percentage (negative tenacity lengthens it), never below
		# 0.3 s (wiki Tenacity); airborne, suppression, stasis, nearsight and drowsy ignore it.
		if (b.cc & Buff.TENACITY_AFFECTED) != 0 and stats.tenacity != 0.0:
			b.duration = maxf(b.duration * (1.0 - stats.tenacity), minf(b.duration, 0.3))
			b.remaining = b.duration
	if b.slow_amount > 0.0 and has_cc_immunity():
		return null
	if b.cc == 0 and b.slow_amount > 0.0 and stats.tenacity != 0.0 and not b.permanent:
		# [numbers] League: tenacity also shortens slows (Mercury's Treads: "stuns, slows, taunts, fears ...")
		b.duration = maxf(b.duration * (1.0 - stats.tenacity), minf(b.duration, 0.3))
		b.remaining = b.duration
	if b.stack_mode != Buff.Stack.INDEPENDENT:
		var existing := find_buff(b.id, b.source if b.stack_mode == Buff.Stack.ADD_STACK and false else null)
		if existing != null:
			match b.stack_mode:
				Buff.Stack.REFRESH:
					existing.remaining = maxf(existing.remaining, b.duration)
					existing.duration = maxf(existing.duration, b.duration)
					existing.stats = b.stats
					existing.slow_amount = maxf(existing.slow_amount, b.slow_amount)
				Buff.Stack.ADD_STACK:
					existing.stacks = mini(existing.stacks + b.stacks, existing.max_stacks)
					existing.remaining = b.duration
					existing.duration = b.duration
				Buff.Stack.KEEP_LONGEST:
					existing.remaining = maxf(existing.remaining, b.duration)
			stats.mark_dirty()
			_update_cc()
			return existing
	b.owner = self
	buffs.append(b)
	effects.append(b)
	b.on_attach(self)
	stats.mark_dirty()
	_update_cc()
	if b.cc != 0:
		_on_cc_received(b)
	if (b.cc != 0 or b.slow_amount > 0.0) and b.source != null and is_instance_valid(b.source) and b.source != self:
		for e in b.source.effects.duplicate():
			e.on_cc_applied(self, b)
	return b


func remove_buff(b: Buff) -> void:
	if b in buffs:
		buffs.erase(b)
		effects.erase(b)
		b.removed = true
		b.on_removed(self)
		b.on_detach(self)
		stats.mark_dirty()
		_update_cc()


func remove_buffs_by_id(bid: String) -> void:
	for b in buffs.duplicate():
		if b.id == bid:
			remove_buff(b)


func cleanse() -> void:
	for b in buffs.duplicate():
		if b.is_debuff and b.cleansable and (b.cc & ~Buff.CC.AIRBORNE != 0 or b.slow_amount > 0.0):
			if (b.cc & (Buff.CC.AIRBORNE | Buff.CC.SUPPRESS)) == 0:
				remove_buff(b)


func _update_cc() -> void:
	var f := 0
	for b in buffs:
		f |= b.cc
	cc = f


func _on_cc_received(_b: Buff) -> void:
	if (cc & (Buff.CC.STUN | Buff.CC.AIRBORNE | Buff.CC.SUPPRESS | Buff.CC.SLEEP | Buff.CC.CHARM | Buff.CC.FEAR | Buff.CC.TAUNT)) != 0:
		cancel_windup()
		# [cc-anim] League: these CCs drop the walk order (a stunned / knocked-up unit stands where it lands, like a
		# knock-back already did); a root keeps it and resumes when the root ends
		stop_moving()
		if cmd == Cmd.MOVE:
			cmd = Cmd.IDLE
		if not casting.is_empty() and casting.ability != null and not casting.ability.uninterruptible:
			casting = {}
		if not channel.is_empty():
			interrupt_channel()
	if (cc & Buff.CC.SILENCE) != 0 and not channel.is_empty():
		interrupt_channel()


func has_cc_immunity() -> bool:
	return (cc & Buff.CC.UNSTOPPABLE) != 0


func can_move() -> bool:
	return not dead and (cc & Buff.BLOCK_MOVE) == 0 and dash.is_empty() and (cc & Buff.FORCED_MOVE) == 0


## [cc-anim] League: stunned / airborne / suppressed / sleeping / stasis units cannot turn (roots, disarms, silences can).
func can_turn() -> bool:
	return (cc & (Buff.CC.STUN | Buff.CC.AIRBORNE | Buff.CC.SUPPRESS | Buff.CC.SLEEP | Buff.CC.STASIS)) == 0


func can_attack() -> bool:
	return not dead and (cc & Buff.BLOCK_ATTACK) == 0 and dash.is_empty() and not channel_disarm


func can_cast() -> bool:
	return not dead and (cc & Buff.BLOCK_CAST) == 0


func is_invulnerable() -> bool:
	return invulnerable_count > 0 or (cc & (Buff.CC.INVULNERABLE | Buff.CC.STASIS)) != 0


func is_targetable_by(other_team: int) -> bool:
	if dead or untargetable_count > 0 or (cc & (Buff.CC.UNTARGETABLE | Buff.CC.STASIS)) != 0:
		return false
	if other_team != team and other_team < 2 and not visible_to[other_team]:
		return false
	return true


func is_alive() -> bool:
	return not dead and is_instance_valid(self)


func grievous_wounds() -> float:
	var g := 0.0
	for b in buffs:
		if b.id == "grievous":
			g = maxf(g, b.stats.get("_gw", 0.4))
	return g


func lethality_flat() -> float:
	return stats.lethality


# ===================================================================== shields
func add_shield(amount: float, duration: float, src = null, type: int = -1, decay: bool = false, sid: String = "") -> Dictionary:
	if sid != "":
		for s in shields:
			if s.id == sid:
				s.amount = maxf(s.amount, amount)
				s.max = maxf(s.max, amount)
				s.remaining = maxf(s.remaining, duration)
				s.duration = s.remaining
				return s
	var s := {"amount": amount, "max": amount, "remaining": duration, "duration": duration,
			"source": src, "type": type, "decay": decay, "id": sid}
	shields.append(s)
	return s


func total_shield(type: int = -2) -> float:
	var t := 0.0
	for s in shields:
		if type == -2 or s.type == -1 or s.type == type:
			t += s.amount
	return t


## Absorb damage with shields. Returns damage left over.
func absorb_shields(dmg: float, type: int) -> float:
	var left := dmg
	if type == G.DmgType.TRUE:
		# true damage still hits general shields in League
		pass
	for s in shields:
		if left <= 0.0:
			break
		if s.type != -1 and s.type != type:
			continue
		var take := minf(s.amount, left)
		s.amount -= take
		left -= take
	shields = shields.filter(func(s): return s.amount > 0.5)
	return left


func _tick_shields(dt: float) -> void:
	if shields.is_empty():
		return
	var keep := []
	for s in shields:
		s.remaining -= dt
		if s.decay and s.duration > 0.0:
			s.amount = minf(s.amount, s.max * clampf(s.remaining / s.duration, 0.0, 1.0))
		if s.remaining > 0.0 and s.amount > 0.5:
			keep.append(s)
	shields = keep


# ===================================================================== damage bookkeeping
func record_damage(src, amount: float) -> void:
	if src == null:
		return
	var t: float = match_ref.time if match_ref != null else 0.0
	var owner_unit = src
	if src.kind == G.Kind.SUMMON and src.get("summoner") != null:
		owner_unit = src.summoner
	damage_log[owner_unit] = t
	if owner_unit.kind == G.Kind.CHAMPION:
		last_hit_by_champion_time = t
	last_damaged_time = t
	damage_taken_total += amount


func recent_attackers(window: float = Combat.ASSIST_WINDOW) -> Array:
	var out := []
	var t: float = match_ref.time if match_ref != null else 0.0
	# Iterate a key snapshot: once an attacker (e.g. a minion) is freed its key's hash changes, and
	# `for u in dict` then restarts from the first key forever (the long-match freeze, with runaway memory).
	var stale := false
	for u in damage_log.keys():
		if not is_instance_valid(u):
			stale = true
			continue
		if t - damage_log[u] <= window:
			out.append(u)
	if stale:
		_prune_damage_log()
	return out


## Rebuild without freed keys (erase() can't find a freed key once its hash changed).
func _prune_damage_log() -> void:
	var fresh := {}
	for u in damage_log.keys():
		if is_instance_valid(u):
			fresh[u] = damage_log[u]
	damage_log = fresh


func on_damaged(info: DamageInfo) -> void:
	# [motion3] League has no hit-flash on champions / structures (hit feedback is VFX + sound only); minions get
	# a very subtle, very brief tint. A dying unit never keeps a flash (a dead unit no longer runs _update_visual).
	if (info.final > 0.0 or info.absorbed > 0.0) and kind == G.Kind.MINION and not dead:
		hit_flash = 1.0


# ===================================================================== tick
func tick(dt: float) -> void:
	if dead:
		tick_dead(dt)
		_anim_advance(dt)
		_ev_tick(dt)
		return
	var pt := Prof.t0()
	_tick_buffs(dt)
	# stats rebuild only when something changed (effects/buffs call stats.mark_dirty()), while a slow is
	# decaying, or on a slow safety tick for effects whose modifiers drift over time
	_stats_tick -= dt
	if stats._dirty or _stats_tick <= 0.0 or _has_slow:
		_stats_tick = 0.25
		recompute_stats()
	_regen(dt)
	_tick_shields(dt)
	for e in effects.duplicate():
		if not (e is Buff):
			e.on_tick(self, dt)
	Prof.add("u.stats", pt)
	if dead:
		return
	G.ctx = "think"
	pt = Prof.t0()
	think(dt)
	Prof.add("u.think", pt)
	G.ctx = "cast"
	pt = Prof.t0()
	_update_cast(dt)
	G.ctx = "attack"
	_update_attack(dt)
	Prof.add("u.cast_atk", pt)
	G.ctx = "move"
	pt = Prof.t0()
	_update_movement(dt)
	Prof.add("u.move", pt)
	G.ctx = "visual"
	pt = Prof.t0()
	_update_visual(dt)
	Prof.add("u.visual", pt)
	pt = Prof.t0()
	_anim_advance(dt)
	_ev_tick(dt)
	Prof.add("u.anim", pt)
	var gp := global_position
	if _prev_pos != Vector3.INF and dt > 0.0:
		velocity = velocity.lerp(Vector3(gp.x - _prev_pos.x, 0.0, gp.z - _prev_pos.z) / dt, 0.5)
	_prev_pos = gp


func tick_dead(_dt: float) -> void:
	pass


func think(_dt: float) -> void:
	pass


func _tick_buffs(dt: float) -> void:
	if buffs.is_empty():
		return
	var expired := []
	for b in buffs.duplicate():
		if not b.tick(self, dt):
			expired.append(b)
	for b in expired:
		remove_buff(b)


func _regen(dt: float) -> void:
	if hp < stats.max_hp:
		hp = minf(stats.max_hp, hp + stats.hp_regen * dt * (1.0 - grievous_wounds()))   # [numbers] Grievous Wounds cuts health regeneration too
	if stats.uses_mana and mana < stats.max_mana:
		mana = minf(stats.max_mana, mana + stats.mana_regen * dt)


# ===================================================================== commands
func issue_move(pos: Vector3) -> void:
	if dead:
		return
	pending_cast = {}
	if not channel.is_empty() and not channel.ability.can_move_while_channeling:
		interrupt_channel()
	if windup_timer >= 0.0:
		cancel_windup()
	attack_target = null
	cmd = Cmd.MOVE
	_set_path_to(pos)


func issue_attack(target: Unit) -> void:
	if dead or target == null or not target.is_targetable_by(team) or target.team == team:
		return
	pending_cast = {}
	if attack_target != target and windup_timer >= 0.0:
		cancel_windup()
	attack_target = target
	cmd = Cmd.ATTACK
	_repath_timer = 0.0


func issue_attack_move(pos: Vector3) -> void:
	if dead:
		return
	pending_cast = {}
	attack_move_goal = pos
	cmd = Cmd.ATTACK_MOVE
	attack_target = null
	_set_path_to(pos)


func issue_stop() -> void:
	pending_cast = {}
	cancel_windup()
	attack_target = null
	path = PackedVector3Array()
	moving = false
	cmd = Cmd.IDLE


func issue_hold() -> void:
	issue_stop()
	cmd = Cmd.HOLD


func _set_path_to(pos: Vector3) -> void:
	move_goal = pos
	if match_ref != null and match_ref.nav != null:
		path = match_ref.nav.find_path(global_position, pos)
	else:
		path = PackedVector3Array([pos])
	path_i = 0
	moving = path.size() > 0


func stop_moving() -> void:
	path = PackedVector3Array()
	moving = false


# ===================================================================== attack
func attack_range_m() -> float:
	return stats.attack_range * G.U


func in_attack_range(t: Unit, extra: float = 0.0) -> bool:
	return G.flat_dist(global_position, t.global_position) <= attack_range_m() + radius + t.radius + extra


func edge_dist(t: Unit) -> float:
	return G.flat_dist(global_position, t.global_position) - radius - t.radius


func cancel_windup() -> void:
	if windup_timer >= 0.0:
		windup_timer = -1.0
		attack_timer = 0.0
		_windup_target = null
		anim_lock = 0.0


## Reset the basic attack timer (attack-reset abilities).
func reset_attack() -> void:
	attack_timer = 0.0
	if windup_timer >= 0.0:
		cancel_windup()


func attack_valid(t) -> bool:
	return t != null and is_instance_valid(t) and not t.dead and t.is_targetable_by(team)


func _update_attack(dt: float) -> void:
	attack_timer -= dt
	if windup_timer >= 0.0:
		if not attack_valid(_windup_target) or not can_attack():
			cancel_windup()
			return
		face_toward(_windup_target.global_position, dt * 3.0)
		windup_timer -= dt
		if windup_timer < 0.0:
			var pat := Prof.t0()
			_launch_attack(_windup_target)
			if Prof.enabled:
				Prof.slow("atk.launch", pat, display_name)
		return
	if not casting.is_empty() or not channel.is_empty() or not dash.is_empty():
		return
	if cmd == Cmd.ATTACK_MOVE and not attack_valid(attack_target):
		attack_target = find_auto_target(acquisition_range, attack_move_goal)
		if attack_target == null and not moving:
			_set_path_to(attack_move_goal)
			if path.is_empty() or G.flat_dist(global_position, attack_move_goal) < 0.5:
				cmd = Cmd.IDLE
	if cmd == Cmd.IDLE or cmd == Cmd.HOLD:
		# auto-acquire nearby enemies when idle (League behaviour)
		if not attack_valid(attack_target) and auto_attacks_when_idle():
			var t := find_auto_target(attack_range_m() + radius + (0.0 if cmd == Cmd.HOLD else 2.0))
			if t != null:
				attack_target = t
	if not attack_valid(attack_target):
		attack_target = null
		if cmd == Cmd.ATTACK:
			cmd = Cmd.IDLE
			stop_moving()
		return
	if in_attack_range(attack_target):
		if cmd != Cmd.MOVE:
			stop_moving()
			face_toward(attack_target.global_position, dt)
			if attack_timer <= 0.0 and can_attack():
				var pat := Prof.t0()
				_start_attack(attack_target)
				if Prof.enabled:
					Prof.slow("atk.start", pat, display_name)
	elif cmd == Cmd.ATTACK or cmd == Cmd.ATTACK_MOVE or (cmd == Cmd.IDLE and auto_attacks_when_idle() and is_bot):
		_repath_timer -= dt
		if _repath_timer <= 0.0 or not moving:
			_repath_timer = 0.2
			_set_path_to(attack_target.global_position)
	elif cmd == Cmd.IDLE or cmd == Cmd.HOLD:
		attack_target = null


func auto_attacks_when_idle() -> bool:
	return true


## Nearest valid enemy within range (meters, center distance) of `around` (default self).
func find_auto_target(range_m: float, around = null) -> Unit:
	if match_ref == null:
		return null
	var c: Vector3 = global_position if around == null else around
	var best: Unit = null
	var best_score := INF
	for u in match_ref.units_in_radius(c, range_m + 1.5, G.enemy_team(team)):
		if not u.is_targetable_by(team):
			continue
		var d := G.flat_dist(global_position, u.global_position)
		var score := d
		if u.kind == G.Kind.CHAMPION:
			score += 1.0   # mild preference for minions when idle (League acquires nearest)
		if score < best_score:
			best_score = score
			best = u
	return best


func _start_attack(t: Unit) -> void:
	var period := stats.attack_period()
	attack_timer = period
	windup_timer = attack_windup(period)
	_windup_target = t
	_pending_crit = G.rng.randf() < stats.crit_chance
	attack_count += 1
	play_attack_anim(_pending_crit, period)
	if match_ref != null and match_ref.audio != null:
		match_ref.audio.attack_start(self, _pending_crit)


## League attack windup: base_windup + (period * windup% - base_windup) * windupModifier,
## where base_windup = windup% / base attack speed.
func attack_windup(period: float) -> float:
	var w := period * windup_pct
	if absf(windup_mod - 1.0) > 0.001:
		var base_as := float(stats.base.get("attack_speed", 0.0))
		if base_as > 0.0:
			var bw := windup_pct / base_as
			w = bw + (w - bw) * windup_mod
	return minf(w, period)


func _launch_attack(t: Unit) -> void:
	windup_timer = -1.0
	_windup_target = null
	var crit := _pending_crit
	for e in effects.duplicate():
		e.on_attack_launch(t)
	if attack_missile_speed > 0.0 and match_ref != null:
		match_ref.spawn_attack_missile(self, t, crit)
	else:
		attack_hit(t, crit)


## Apply a basic attack hit (on-hit). Called directly for melee or when a missile lands.
func attack_hit(t: Unit, crit: bool, mult: float = 1.0) -> DamageInfo:
	if t == null or not is_instance_valid(t) or t.dead:
		return null
	var dmg := stats.ad * mult
	var dtype := G.DmgType.PHYSICAL
	# [numbers] League (wiki Turret / Basic attack / Critical strike): a champion's basic attack against a structure deals
	# base AD + bonus AD + 60% AP, the whole hit being physical if bonus AD >= 60% AP and magic otherwise, and it cannot
	# critically strike structures.
	if kind == G.Kind.CHAMPION and (t.kind == G.Kind.TURRET or t.kind == G.Kind.INHIBITOR or t.kind == G.Kind.NEXUS):
		crit = false
		var ap_part := stats.ap * Rules.STRUCT_AP_RATIO
		dmg = (stats.ad + ap_part) * mult
		if ap_part > stats.bonus_ad:
			dtype = G.DmgType.MAGIC
	if crit:
		dmg *= stats.crit_damage
	var info := Combat.deal(self, t, dmg, dtype, {"is_attack": true, "is_crit": crit})
	if match_ref != null and match_ref.audio != null:
		match_ref.audio.attack_hit(self, t, crit)
	LolVfx.on_attack_hit(self, t, crit)
	for e in effects.duplicate():
		e.on_attack_hit(t, info)
	on_attack_landed(t, info)
	return info


func on_attack_landed(_t: Unit, _info: DamageInfo) -> void:
	pass


## Re-apply on-hit effects (Ethereal Weapon, Typhoon, Double Tap...). `except` is skipped.
func trigger_on_hit(t: Unit, info: DamageInfo, mult: float = 1.0, except = null) -> void:
	if t == null or not is_instance_valid(t) or t.dead:
		return
	var prev := 1.0
	if info != null:
		prev = info.on_hit_mult
		info.on_hit_mult = mult
	for e in effects.duplicate():
		if e != except:
			e.on_attack_hit(t, info)
	if info != null:
		info.on_hit_mult = prev


# ===================================================================== casting
func _update_cast(dt: float) -> void:
	if not casting.is_empty():
		var ab = casting.ability
		if ab.face_target and casting.target.has("pos"):
			face_toward(casting.target.pos, dt * 2.0)
		casting.t -= dt
		if casting.t <= 0.0:
			var c := casting
			casting = {}
			var pe := Prof.t0()
			ab.execute(c.target)
			Prof.add("cast.exec", pe)
			if not queued_cast.is_empty():
				var q := queued_cast
				queued_cast = {}
				q.ability.try_cast(q.target)
	if not channel.is_empty():
		var ch: Dictionary = channel
		ch.t -= dt
		ch.ability.channel_tick(dt, ch)
		# channel_tick may have interrupted / replaced the channel
		if channel == ch and ch.t <= 0.0:
			channel = {}
			ch.ability.channel_end(ch, false)
	if not pending_cast.is_empty():
		var ab2 = pending_cast.ability
		var tgt: Dictionary = pending_cast.target
		if not ab2.target_still_valid(tgt) or not can_cast():
			pending_cast = {}
			return
		if ab2.in_cast_range(tgt):
			pending_cast = {}
			stop_moving()
			ab2.begin_cast(tgt)
		else:
			_repath_timer -= dt
			if _repath_timer <= 0.0 or not moving:
				_repath_timer = 0.2
				_set_path_to(ab2.target_position(tgt))


func is_busy() -> bool:
	return not casting.is_empty() or not channel.is_empty() or not dash.is_empty() or windup_timer >= 0.0


func interrupt_channel(force: bool = false) -> void:
	if channel.is_empty():
		return
	if not force and channel.ability.uninterruptible and not dead:
		return
	var ch := channel
	channel = {}
	ch.ability.channel_end(ch, true)


# ===================================================================== movement
func _update_movement(dt: float) -> void:
	if not dash.is_empty():
		_update_dash(dt)
		return
	if (cc & Buff.FORCED_MOVE) != 0:
		_forced_move(dt)
		return
	if (cc & Buff.BLOCK_MOVE) != 0 or not casting.is_empty() and not casting.ability.can_move_while_casting:
		# [cc-anim] League: a rooted unit (only) still turns toward where it is told to go
		if (cc & Buff.BLOCK_MOVE) == Buff.CC.ROOT and moving and path_i < path.size() and casting.is_empty():
			face_toward(path[path_i], dt)
		return
	if not channel.is_empty() and not channel.ability.can_move_while_channeling:
		return
	if windup_timer >= 0.0:
		return
	if not moving or path_i >= path.size():
		moving = false
		if cmd == Cmd.MOVE:
			cmd = Cmd.IDLE
		return
	var step := stats.move_speed * G.U * dt
	var pos := global_position
	while step > 0.0 and path_i < path.size():
		var wp := path[path_i]
		var to := Vector3(wp.x - pos.x, 0.0, wp.z - pos.z)
		var d := to.length()
		if d <= step:
			pos.x = wp.x
			pos.z = wp.z
			step -= d
			path_i += 1
		else:
			var dir := to / d
			var sd := _steer_dir(pos, dir, path_i == path.size() - 1, d)
			if sd == Vector3.ZERO:
				# the goal is occupied by a unit that holds its ground: arrive here (League body block)
				path_i = path.size()
				break
			pos += sd * step
			step = 0.0
			face_toward(pos + sd, dt)
	set_ground_pos(pos)
	if path_i >= path.size():
		moving = false
		if cmd == Cmd.MOVE:
			cmd = Cmd.IDLE


func _forced_move(dt: float) -> void:
	var b: Buff = null
	for x in buffs:
		if (x.cc & Buff.FORCED_MOVE) != 0:
			b = x
			break
	if b == null:
		return
	# [cc-anim] League: charm / flee / taunt end the moment their source dies
	var ft = b.forced_target
	if ft != null and (not is_instance_valid(ft) or ft.dead):
		remove_buff(b)
		return
	var dest := b.forced_dest
	if ft != null:
		dest = ft.global_position
	var dir := G.flat_dir(global_position, dest)
	if (b.cc & Buff.CC.FEAR) != 0:
		dir = -dir
	if (b.cc & Buff.CC.TAUNT) != 0 and ft != null:
		if in_attack_range(ft):
			moving = false   # [cc-anim] standing and swinging at the taunter: no run clip
			if attack_timer <= 0.0 and windup_timer < 0.0:
				_start_attack(ft)
			return
	var speed := stats.move_speed * G.U
	var np := global_position + dir * speed * dt
	if match_ref != null and match_ref.nav != null and not match_ref.nav.is_walkable(np):
		moving = false   # [cc-anim] pinned against a wall while fleeing: idle, not a run on the spot
		return
	face_toward(np, dt)
	set_ground_pos(np)
	moving = true


## Start a dash/leap. opts: speed (m/s) or duration, height (arc), on_arrive(Callable),
## on_tick(Callable(unit, progress)), unstoppable(bool), forced(bool: displacement by enemy),
## can_cast(bool), stop_at_walls(bool), anim(String)
func start_dash(to: Vector3, opts: Dictionary = {}) -> void:
	if G.debug_sites: G.crumb("dash " + display_name)
	if not to.is_finite():
		G.bad_vector("start_dash", to)
		return
	var from := global_position
	var dest := to
	if match_ref != null and match_ref.nav != null:
		dest = match_ref.nav.clamp_walkable(from, to)
	var dist := G.flat_dist(from, dest)
	var duration: float = opts.get("duration", 0.0)
	if duration <= 0.0:
		var spd: float = opts.get("speed", 15.0)
		duration = dist / maxf(spd, 0.1)
	duration = maxf(duration, 0.05)
	cancel_windup()
	stop_moving()
	dash = {"from": from, "to": dest, "t": 0.0, "duration": duration, "height": opts.get("height", 0.0),
		"on_arrive": opts.get("on_arrive", Callable()), "on_tick": opts.get("on_tick", Callable()),
		"forced": opts.get("forced", false), "can_cast": opts.get("can_cast", false)}
	if dist > 0.01 and not opts.get("forced", false):
		face_toward(dest, 100.0)   # [cc-anim] (a knocked-back / pulled unit keeps its facing)
	if opts.has("anim"):
		play_anim(opts.anim, 1.0, 0.05, duration)
	if not opts.get("forced", false):
		for e in effects.duplicate():
			e.on_dash(from, dest)


func _update_dash(dt: float) -> void:
	dash.t += dt
	var k := clampf(dash.t / dash.duration, 0.0, 1.0)
	var p: Vector3 = dash.from.lerp(dash.to, k)
	set_ground_pos(p)
	airborne_height = dash.height * 4.0 * k * (1.0 - k)
	if dash.on_tick.is_valid():
		dash.on_tick.call(self, k)
	if k >= 1.0:
		var d := dash
		dash = {}
		airborne_height = 0.0
		if d.on_arrive.is_valid():
			d.on_arrive.call(self)
		if dash.is_empty() and not queued_cast.is_empty() and not dead:
			var q := queued_cast
			queued_cast = {}
			q.ability.try_cast(q.target)


## Knock this unit back (displacement) away from `from_pos` by distance (m).
func knockback(from_pos: Vector3, distance: float, duration: float, src = null) -> void:
	if has_cc_immunity() or dead:
		return
	var dir := G.flat_dir(from_pos, global_position)
	var b := Buff.new("knockback", duration)
	b.cc = Buff.CC.AIRBORNE
	b.is_debuff = true
	b.hidden = true
	add_buff(b, src)
	start_dash(global_position + dir * distance, {"duration": duration, "height": 0.6, "forced": true})


## Pull toward a point (displacement).
func pull_to(pos: Vector3, duration: float, src = null) -> void:
	if has_cc_immunity() or dead:
		return
	var b := Buff.new("pull", duration)
	b.cc = Buff.CC.AIRBORNE
	b.is_debuff = true
	b.hidden = true
	add_buff(b, src)
	start_dash(pos, {"duration": duration, "height": 0.3, "forced": true})


## Knock up in place.
func knockup(duration: float, src = null) -> Buff:
	if has_cc_immunity() or dead:
		return null
	var b := Buff.new("airborne", duration)
	b.cc = Buff.CC.AIRBORNE
	b.is_debuff = true
	b.display_name = "Airborne"
	return add_buff(b, src)


func set_ground_pos(p: Vector3) -> void:
	if not p.is_finite():
		G.bad_vector("set_ground_pos", p)
		return
	var y := 0.0
	if match_ref != null and match_ref.nav != null:
		y = match_ref.nav.height_at(p)
	ground_y = y
	global_position = Vector3(p.x, y, p.z)
	if match_ref != null and match_ref.nav != null:
		in_brush = match_ref.nav.brush_id(p)


## League turns units very quickly (no wide arcs): exponential approach plus a minimum angular
## speed so even 180 degree turns finish in ~0.15 s. dt >= 50 snaps.
const TURN_RATE := 22.0        ## 1/s exponential approach
const TURN_MIN_SPEED := 18.0   ## rad/s


func face_toward(p: Vector3, dt: float) -> void:
	var d := Vector3(p.x - global_position.x, 0.0, p.z - global_position.z)
	if d.length_squared() < 0.0001:
		return
	d = d.normalized()
	if dt < 50.0 and cc != 0 and not can_turn():
		return
	if dt >= 50.0:
		facing = d
	else:
		var cur := atan2(facing.x, facing.z)
		var diff := wrapf(atan2(d.x, d.z) - cur, -PI, PI)
		var stp := diff * (1.0 - exp(-dt * TURN_RATE))
		var mn := minf(absf(diff), TURN_MIN_SPEED * dt)
		if absf(stp) < mn:
			stp = signf(diff) * mn
		cur += stp
		facing = Vector3(sin(cur), 0.0, cos(cur))
	if model != null:
		model.rotation.y = atan2(-facing.x, -facing.z)


# ===================================================================== unit collision / steering
## Local steering around units that hold their ground (League pathing treats units as obstacles:
## champions route around minions, minion waves spread instead of stacking).
## Returns ZERO when the final waypoint is occupied and we are close enough to call it arrived.
func _steer_dir(pos: Vector3, dir: Vector3, last_leg: bool, dist_left: float) -> Vector3:
	if match_ref == null or (cc & Buff.CC.GHOSTED) != 0 or kind == G.Kind.TURRET:
		return dir
	var out := dir
	var my_spd := stats.move_speed * G.U
	# scan the 3x3 grid cells around pos directly (cells are 4 m; blockers are within ~2.5 m): no
	# per-call query array, distance test before any other property access
	var grid: Dictionary = match_ref._grid
	var cx := int(floor(pos.x / 4.0))
	var cz := int(floor(pos.z / 4.0))
	for gj in range(cz - 1, cz + 2):
		for gi in range(cx - 1, cx + 2):
			var cell = grid.get(Vector2i(gi, gj))
			if cell == null:
				continue
			for u in cell:
				if u == self:
					continue
				var up: Vector3 = u.global_position
				var to := Vector3(up.x - pos.x, 0.0, up.z - pos.z)
				var rr: float = path_radius + float(u.path_radius)
				var d2 := to.x * to.x + to.z * to.z
				if d2 > (rr + 0.45) * (rr + 0.45) or d2 < 0.000001:
					continue
				if u.dead or u.kind == G.Kind.INHIBITOR or u.kind == G.Kind.NEXUS or (u.cc & Buff.CC.GHOSTED) != 0 or not u.dash.is_empty():
					continue
				var st := _steer_one(u, to, sqrt(d2), rr, dir, my_spd, last_leg, dist_left)
				if st == Vector3.INF:
					return Vector3.ZERO
				out += st
	if out.length_squared() < 0.0001:
		return dir
	out = out.normalized()
	# never steer backwards
	if out.dot(dir) < 0.0:
		out = (out - dir * out.dot(dir)).normalized()
	return out


## Steering push away from one nearby unit (INF = the goal is occupied: arrive here).
func _steer_one(u, to: Vector3, dist: float, rr: float, dir: Vector3, my_spd: float, last_leg: bool, dist_left: float) -> Vector3:
	var fwd := to.dot(dir)
	if fwd <= 0.0:
		return Vector3.ZERO
	# only units that are not moving along with us block (a wave walking together does not weave)
	if u.moving and u.velocity.dot(dir) > my_spd * 0.6:
		return Vector3.ZERO
	var lat_v := to - dir * fwd
	var lat := lat_v.length()
	if lat >= rr:
		return Vector3.ZERO
	if last_leg and dist_left <= fwd + rr * 0.5:
		# the goal lies inside / just behind this unit
		if dist_left < rr + 0.6:
			return Vector3.INF
	var tangent: Vector3
	if lat > 0.01:
		tangent = -lat_v / lat
	else:
		tangent = dir.cross(Vector3.UP) * (1.0 if (uid + u.uid) % 2 == 0 else -1.0)
	var w: float = clampf(1.0 - (dist - rr) / 0.45, 0.0, 1.0) * (1.0 - lat / rr * 0.5)
	return tangent * w * 2.0


## Soft collision for every unit pair in neighbouring grid cells (Match._resolve_collisions).
## Solid units (alive, not dashing / ghosted) are gathered per cell once per frame, then each pair is
## visited exactly once (own cell + the 4 forward cells) with a cheap distance test first. Immovable
## units (mass 0: turrets, structures) push from every side.
static var _solid := {}
static var _solid_pool: Array = []


static func resolve_collisions(grid: Dictionary, nav) -> void:
	for k in _solid:
		var arr: Array = _solid[k]
		arr.clear()
		_solid_pool.append(arr)
	_solid.clear()
	for key in grid:
		var arr: Array = _solid_pool.pop_back() if not _solid_pool.is_empty() else []
		for u in grid[key]:
			if not u.dead and (u.cc & Buff.CC.GHOSTED) == 0 and u.dash.is_empty():
				arr.append(u)
		if arr.is_empty():
			_solid_pool.append(arr)
		else:
			_solid[key] = arr
	var empty: Array = []
	for key in _solid:
		var cell: Array = _solid[key]
		var n0: Array = _solid.get(Vector2i(key.x + 1, key.y), empty)
		var n1: Array = _solid.get(Vector2i(key.x - 1, key.y + 1), empty)
		var n2: Array = _solid.get(Vector2i(key.x, key.y + 1), empty)
		var n3: Array = _solid.get(Vector2i(key.x + 1, key.y + 1), empty)
		var cn := cell.size()
		for ia in cn:
			var a: Unit = cell[ia]
			for ib in range(ia + 1, cn):
				_collide(a, cell[ib], nav)
			for b in n0:
				_collide(a, b, nav)
			for b in n1:
				_collide(a, b, nav)
			for b in n2:
				_collide(a, b, nav)
			for b in n3:
				_collide(a, b, nav)


static func _collide(a: Unit, b: Unit, nav) -> void:
	var ap := a.global_position
	var bp := b.global_position
	var rr := a.path_radius + b.path_radius
	var dx := bp.x - ap.x
	var dz := bp.z - ap.z
	if dx * dx + dz * dz >= rr * rr or (a.mass <= 0.0 and b.mass <= 0.0):
		return
	# [bugfix] League spawns lane minions at the barracks = their own inhibitor and the nav grid (pathfindingCollisionRadius
	# 213.75 for the inhibitor, already blocked as a disc) is what routes them out. The soft push here (radius 2.2 + minion)
	# is larger than that disc and pinned the whole wave against its own inhibitor / nexus.
	if (a.kind == G.Kind.MINION and b.team == a.team and (b.kind == G.Kind.INHIBITOR or b.kind == G.Kind.NEXUS)) 			or (b.kind == G.Kind.MINION and a.team == b.team and (a.kind == G.Kind.INHIBITOR or a.kind == G.Kind.NEXUS)):
		return
	resolve_pair(a, b, nav)


## Resolve overlap of two units (called by Match for neighbouring pairs).
## League: units that hold their ground (attacking/standing) are not shoved by units walking into
## them; walkers are deflected (champions are body-blocked by minions and vice versa).
static func resolve_pair(a: Unit, b: Unit, nav) -> void:
	var ap := a.global_position
	var bp := b.global_position
	var dx := bp.x - ap.x
	var dz := bp.z - ap.z
	var rr := a.path_radius + b.path_radius
	var d2 := dx * dx + dz * dz
	if d2 >= rr * rr:
		return
	var d := sqrt(d2)
	if d < 0.001:
		dx = 0.01 * (1 if a.uid % 2 == 0 else -1)
		dz = 0.01
		d = 0.0141
	var overlap := rr - d
	var nx := dx / d
	var nz := dz / d
	var wa := 0.5
	if b.mass <= 0.0:
		wa = 1.0
	elif a.mass <= 0.0:
		wa = 0.0
	elif a.moving and not b.moving:
		wa = 1.0
	elif b.moving and not a.moving:
		wa = 0.0
	else:
		wa = b.mass / maxf(a.mass + b.mass, 0.001)
	var wb := 1.0 - wa
	# soften so crowds settle over a few frames instead of popping
	var push := overlap * 0.85
	if wa > 0.0:
		var na := Vector3(ap.x - nx * push * wa, ap.y, ap.z - nz * push * wa)
		if nav == null or nav.is_walkable(na):
			a.set_ground_pos(na)
	if wb > 0.0:
		var nb := Vector3(bp.x + nx * push * wb, bp.y, bp.z + nz * push * wb)
		if nav == null or nav.is_walkable(nb):
			b.set_ground_pos(nb)


func teleport(p: Vector3) -> void:
	stop_moving()
	dash = {}
	set_ground_pos(p)


# ===================================================================== death
func die(killer, info = null) -> void:
	if dead:
		return
	if G.debug_sites: G.crumb("die " + display_name)
	dead = true
	hp = 0.0
	hit_flash = 0.0   # [motion3] corpses keep normal shading (no stuck white flash)
	if _flash_shown > 0.0:
		_flash_shown = 0.0
		for mi in _meshes:
			if is_instance_valid(mi):
				(mi as GeometryInstance3D).set_instance_shader_parameter("flash", 0.0)
	cancel_windup()
	casting = {}
	pending_cast = {}
	if not channel.is_empty():
		interrupt_channel(true)
	dash = {}
	airborne_height = 0.0
	stop_moving()
	attack_target = null
	shields.clear()
	var pd := Prof.t0()
	for b in buffs.duplicate():
		if not b.permanent:
			remove_buff(b)
	Prof.slow("death.buffs", pd, display_name)
	_kill_attached_fx()   # [vfx-leak]
	pd = Prof.t0()
	for e in effects.duplicate():
		e.on_death(killer)
	if killer != null and is_instance_valid(killer):
		for e in killer.effects.duplicate():
			e.on_kill(self)
	Prof.slow("death.effects", pd, display_name)
	pd = Prof.t0()
	play_anim("death", 1.0, -1.0 if graph != null else 0.1)
	Prof.slow("death.anim", pd, display_name)
	pd = Prof.t0()
	died.emit(self, killer)
	Prof.slow("death.died_signal", pd, display_name)
	pd = Prof.t0()
	if match_ref != null:
		match_ref.on_unit_died(self, killer, info)
	Prof.slow("death.on_unit_died", pd, display_name)
	pd = Prof.t0()
	on_died(killer)
	Prof.slow("death.on_died", pd, display_name)


func on_died(_killer) -> void:
	pass


## [vfx-leak] League removes every buff / ability particle attached to a unit when it dies. Kits keep their own
## references and timers for those effects (a Sona zone, Darius's R-ready glow, a Malphite speed trail ...), but a dead
## unit's timers may not run for seconds and a corpse keeps the node, so a looping effect would hang on the body.
## Looping effects owned by animation events (death-clip particles, skin idle particles) are exempt: AnimEvents
## ends those at their end frame / clip exit.
func _kill_attached_fx() -> void:
	for c in get_children():
		if c is LolVfx and c._loop and not c._stopped and not c.has_meta("anim_ev"):
			K.kill_fx(c, 0.15)


# ===================================================================== visuals
func set_model(m: Node3D) -> void:
	if model != null:
		model.queue_free()
	model = m
	add_child(m)
	for k in _sockets:
		var s = _sockets[k]
		if is_instance_valid(s) and s.get_parent() == self:
			s.queue_free()
	_sockets.clear()
	_raw_clips.clear()
	_index_bones()
	anim_player = _find_anim_player(m)
	materials.clear()
	_meshes.clear()
	_collect_materials(m)
	_alpha = -1.0
	_model_y = INF
	if anim_ev != null:
		anim_ev.reset()   # [anim-events]
	recompute_stats()


# ===================================================================== sockets (bone attachments)
var _sockets := {}            ## lower-case request -> Node3D
var _skel: Skeleton3D = null
var _bone_lc := {}            ## normalized bone name -> bone index
var attack_bone := ""         ## League mStartBoneName of the current basic attack (from data/anim)
var attack_bones := {}        ## attack clip/spell name (lower) -> start bone


static func _norm_bone(s: String) -> String:
	var t := s.to_lower().replace("bufbone", "buffbone").replace("ablility", "ability")
	var out := ""
	for ch in t:
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
	return out


func _index_bones() -> void:
	_bone_lc.clear()
	_skel = Assets.find_skeleton(model) if model != null else null
	if _skel == null:
		return
	for i in _skel.get_bone_count():
		var n := _norm_bone(_skel.get_bone_name(i))
		if not _bone_lc.has(n):
			_bone_lc[n] = i


## Bone index for a League bone name (case-insensitive, tolerant of C_/L_/R_ prefixes). -1 = none.
func _find_bone(name: String) -> int:
	if _skel == null:
		return -1
	var n := _norm_bone(name)
	if _bone_lc.has(n):
		return _bone_lc[n]
	# "C_BUFFBONE_GLB_CHEST_LOC" <-> "BUFFBONE_GLB_CHEST_LOC"
	for p in ["c", "l", "r"]:
		if n.begins_with(p + "buffbone") and _bone_lc.has(n.substr(1)):
			return _bone_lc[n.substr(1)]
		if n.begins_with("buffbone") and _bone_lc.has(p + n):
			return _bone_lc[p + n]
	# "Cstm_Buffbone_X" <-> "Buffbone_Cstm_X"
	if n.begins_with("cstmbuffbone"):
		var alt := "buffbonecstm" + n.substr(12)
		if _bone_lc.has(alt):
			return _bone_lc[alt]
	elif n.begins_with("buffbonecstm"):
		var alt2 := "cstmbuffbone" + n.substr(12)
		if _bone_lc.has(alt2):
			return _bone_lc[alt2]
	return -1


func _first_bone(cands: Array) -> int:
	for c in cands:
		var i := _find_bone(c)
		if i >= 0:
			return i
	return -1


## Fallback chain by bone category: weapon -> hand -> chest -> root.
func _fallback_bone(name: String) -> int:
	var n := _norm_bone(name)
	var side := "r"
	if n.begins_with("l") and not n.begins_with("layout"):
		side = "l"
	var weapon := ["buffbone_glb_weapon_1", "buffbone_cstm_weapon_1", "weapon", side + "_weapon", "sword", "staff",
			side + "_staff"]
	var hand := [side + "_buffbone_glb_hand_loc", side + "_hand", "r_buffbone_glb_hand_loc", "r_hand",
			"l_buffbone_glb_hand_loc", "l_hand"]
	var chest := ["c_buffbone_glb_chest_loc", "chest", "spine2", "spine1", "spine", "c_chest",
			"c_buffbone_glb_center_loc"]
	var overhead := ["c_buffbone_glb_overhead_loc", "buffbone_cstm_healthbar", "c_buffbone_glb_head_loc", "head"]
	var head := ["c_buffbone_glb_head_loc", "head", "c_head"]
	var center := ["c_buffbone_glb_center_loc", "c_buffbone_glb_chest_loc", "spine1", "spine"]
	var foot := [side + "_buffbone_glb_foot_loc", "buffbone_glb_ground_loc"]
	var root := ["root", "c_root", "root_minion"]
	var chain: Array = []
	if n.contains("weapon") or n.contains("wpn") or n.contains("sword") or n.contains("staff") or n.contains("gun") \
			or n.contains("barrel") or n.contains("missile") or n.contains("cannon") or n.contains("pistol"):
		chain = weapon + hand + chest + root
	elif n.contains("hand") or n.contains("ability") or n.contains("finger") or n.contains("wrist"):
		chain = hand + chest + root
	elif n.contains("overhead") or n.contains("healthbar"):
		chain = overhead + chest + root
	elif n.contains("head"):
		chain = head + chest + root
	elif n.contains("center") or n.contains("channel"):
		chain = center + chest + root
	elif n.contains("foot") or n.contains("ground") or n.contains("layout"):
		chain = foot + root
	else:
		chain = chest + root
	return _first_bone(chain)


## A Node3D that follows a League bone (BoneAttachment3D, created lazily and cached).
## Case-insensitive; falls back weapon -> hand -> chest -> root. "ground" = the unit's feet.
## Units without a skeleton get fixed-height markers.
func socket(bone: String) -> Node3D:
	var key := bone.to_lower()
	var cached = _sockets.get(key)
	if cached != null and is_instance_valid(cached):
		return cached
	var n: Node3D = null
	var nb := _norm_bone(bone)
	if key == "ground" or key == "feet" or key == "" or nb == "buffboneglbgroundloc" or nb == "buffboneglblayoutloc" \
			or nb == "cbuffboneglblayoutloc":
		n = Node3D.new()
		n.name = "Socket_ground"
		add_child(n)
	else:
		if _skel == null and model != null:
			_index_bones()
		var bi := _find_bone(bone)
		if bi < 0:
			bi = _fallback_bone(bone)
		if bi >= 0:
			var ba := BoneAttachment3D.new()
			ba.name = "Socket_" + nb
			_skel.add_child(ba)
			ba.bone_idx = bi
			n = ba
		else:
			n = Node3D.new()
			n.name = "Socket_" + nb
			var h := height * 0.55
			if nb.contains("overhead") or nb.contains("healthbar"):
				h = height
			elif nb.contains("head"):
				h = height * 0.85
			elif nb.contains("foot"):
				h = 0.0
			n.position = Vector3(0, h, 0)
			if model != null:
				model.add_child(n)
			else:
				add_child(n)
	_sockets[key] = n
	return n


## World position where this unit's basic-attack missile starts (League mStartBoneName of the
## attack spell's missile spec, e.g. Ezreal "L_hand"; falls back to the weapon/hand chain).
func missile_origin() -> Vector3:
	var b := attack_bone
	if b == "":
		b = "BUFFBONE_GLB_WEAPON_1"
	if model != null and (attack_bone != "" or _find_bone(b) >= 0):
		var s := socket(b)
		if s != null and s.is_inside_tree():
			var p := s.global_position
			if p.is_finite() and G.flat_dist(p, global_position) < 4.0 + radius and p.y - global_position.y > 0.2:
				return p
	return global_position + Vector3(0, height * 0.55, 0) + facing * radius


func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null


func _collect_materials(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		_meshes.append(mi)
		for i in mi.get_surface_override_material_count():
			var mat := mi.get_surface_override_material(i)
			if mat == null and mi.mesh != null:
				mat = mi.mesh.surface_get_material(i)
			if mat is ShaderMaterial:
				materials.append(mat)
	for c in n.get_children():
		_collect_materials(c)


func has_anim(logical: String) -> bool:
	if _graph_clip(logical) != "":
		return true
	return (anim_map.has(logical) and not anim_map[logical].is_empty()) or _raw_clip(logical) != ""


var _raw_clips := {}


## Case-insensitive lookup of a clip by its exported name (e.g. "spell3_north").
func _raw_clip(n: String) -> String:
	if anim_player == null:
		return ""
	if _raw_clips.is_empty():
		for an in anim_player.get_animation_list():
			_raw_clips[String(an).to_lower()] = String(an)
	return _raw_clips.get(n.to_lower(), "")


# ===================================================================== League animation graph driver
## Logical animation -> League AnimationGraph clip names (first existing wins).
const _LOGICAL_CLIPS := {
	"idle": ["Idle1", "Idle_Base", "Idle1_Base", "Idle"],
	"run": ["Run", "Run_Base", "Run1"],
	"run_fast": ["Run_Fast", "Run_Haste"],
	"death": ["Death", "Death_Base"],
	"respawn": ["Respawn"],
	"recall": ["Recall"],
	"dance": ["Dance"],
	"taunt": ["Taunt"],
	"laugh": ["Laugh"],
	"joke": ["Joke"],
	"channel": ["Channel"],
	"stunned": ["Stunned", "Stun"],
	"knockup": ["KnockUp"],
	"crit": ["Crit"],
	"attack": ["Attack1", "Attack"],
	"passive": ["Passive"],   # [anim-events] e.g. Master Yi's Double Strike clip (carries its own trail events)
}
## States that keep playing (re-resolving selectors) until something else is wanted.
const _CYCLIC := {"idle": true, "run": true, "run_fast": true, "channel": true, "stunned": true, "knockup": true,
		"recall": true, "dance": true}

var graph: AnimGraph = null
var _anim_base := {}          ## anim_map snapshot: a kit changing an entry overrides the graph for it
var _g_logical := ""
var _g_top := ""              ## League clip being played ("" = legacy clip playback)
var _g_steps: Array = []
var _g_i := 0
var _g_t := 0.0               ## clip time left in the current step (INF = looping)
var _g_atomic := ""
var _g_speed := 1.0
var _g_hold := false
var _g_recheck := 0.0
var _attack_anim := false     ## current anim is a basic attack (backswing is cancellable)
var _strides := {}            ## glb run clip -> skeleton-space ground speed (from foot bones)


## Attach the League animation graph (call after anim_map is built).
func set_anim_graph(g: AnimGraph) -> void:
	graph = g
	if g != null and anim_ev == null:
		setup_anim_events(g.alias, g)
	_anim_base = {}
	for k in anim_map:
		_anim_base[k] = anim_map[k].duplicate()
	_strides = {}
	if g != null and anim_player != null:
		Assets.merge_extra_clips(anim_player, g.alias)
	_setup_anim_lod()
	if g != null and anim_player != null and _skel != null:
		# the pose only evaluates inside the tree: measure once the unit has entered it
		if is_inside_tree():
			_calibrate_strides()
		elif not ready.is_connected(_calibrate_strides):
			ready.connect(_calibrate_strides, CONNECT_ONE_SHOT)
	var wp := g.windup_percent() if g != null else -1.0
	if wp > 0.0:
		windup_pct = clampf(wp, 0.05, 0.8)
		windup_mod = g.windup_modifier()
	if g != null:
		for a in g.attacks:
			if String(a.get("start_bone", "")) != "":
				attack_bone = String(a.start_bone)
				break


func _calibrate_strides() -> void:
	if anim_player != null and _skel != null:
		_strides = _cap_fast_strides(Assets.run_strides(anim_player, _skel))
		_setup_weapon_hold()
		cur_anim = ""


## [motion3] hand-held weapon bones per champion (lower case). The WeaponHold modifier keeps them in the hand
## wherever a cast clip keys them away (see core/weapon_hold.gd).
const _WEAPON_BONES := {
	"darius": ["weapon"], "garen": ["weapon"], "leona": ["weapon"], "lux": ["weapon"], "sona": ["weapon"],
	"veigar": ["weapon"], "missfortune": ["l_weapon", "r_weapon"],
	# (Yasuo / Master Yi sheathe their blades on the back in some clips: left to the clips' own keys)
}
const _WeaponHold := preload("res://src/core/weapon_hold.gd")
var _weapon_hold: Node = null
var _idle_t := 0.0            ## [motion3] time spent in the looping idle (fidget timer)
var _idle_next := 6.0
const SPELL_RECOVERY_MAX := 0.3   ## [motion3] longest a spell pose is held after its cast completes
const _WH_OFF := ["death", "dance", "taunt", "laugh", "joke", "respawn", "recall"]


func _setup_weapon_hold() -> void:
	if _weapon_hold != null or graph == null or _skel == null or not _WEAPON_BONES.has(graph.alias.to_lower()):
		return
	var items: Array = Assets.weapon_hold_calibrate(anim_player, _skel, _WEAPON_BONES[graph.alias.to_lower()])
	if items.is_empty():
		return
	var wh = _WeaponHold.new()
	wh.name = "WeaponHold"
	wh.skel = _skel
	wh.items = items
	_skel.add_child(wh)
	_weapon_hold = wh


## Faster run variants (League run_haste / run_fast / homeguard sprints) are authored as long bounding
## strides with a short stance; matched to the foot exactly they play in slow motion (Ezreal's haste
## run at 0.6x took 2.5 m per step). Cap their planted-foot speed at FAST_STRIDE_CAP x the base run's
## so their cadence stays at least as quick as the normal run's (brief stance = little visible slide).
const FAST_STRIDE_CAP := 1.5


func _cap_fast_strides(st: Dictionary) -> Dictionary:
	if graph == null or st.size() < 2:
		return st
	var top := _graph_clip("run")
	if top == "":
		return st
	var steps: Array = graph.resolve(top, {"MoveSpeed": 0.0, "IsMoving": true, "IsAlly": true})
	if steps.is_empty():
		return st
	var base: float = st.get(String(steps[-1].anim), 0.0)
	if base <= 0.0:
		return st
	var out := st
	for k in st:
		if float(st[k]) > base * FAST_STRIDE_CAP:
			if out == st:
				out = st.duplicate()
			out[k] = base * FAST_STRIDE_CAP
	return out


func _kit_override(logical: String) -> bool:
	return anim_map.has(logical) and _anim_base.has(logical) and anim_map[logical] != _anim_base[logical]


func _graph_clip(logical: String) -> String:
	if graph == null or anim_player == null or _kit_override(logical):
		return ""
	if logical.length() == 6 and logical.begins_with("spell"):
		var sd := graph.spell_for_slot(int(logical.substr(5)) - 1)
		return graph.find_clip([String(sd.get("clip", logical)), logical])
	var c = _LOGICAL_CLIPS.get(logical)
	if c == null:
		return ""
	return graph.find_clip(c)


var _ctx := {"MoveSpeed": 0.0, "IsMoving": false, "IsAlly": true, "IsHomeguard": false,
		"LookAtSpellTargetAngle": 0.0, "Facing": 0.0, "IsInTerrain": false}
var _g_branch := ""           ## AnimGraph.branch() of the run being played (MoveSpeed thresholds)


## League graph updater values (one dictionary reused: resolve() only reads it).
func _anim_ctx() -> Dictionary:
	var ang := 0.0
	if not casting.is_empty() and casting.get("target", {}).has("pos"):
		var to := G.flat(casting.target.pos - global_position)
		if to.length() > 0.01:
			ang = rad_to_deg(facing.signed_angle_to(to.normalized(), Vector3.UP))
	_ctx["MoveSpeed"] = stats.move_speed
	_ctx["IsMoving"] = moving
	_ctx["IsAlly"] = G.player == null or G.player.team == team
	_ctx["LookAtSpellTargetAngle"] = ang
	return _ctx


func _g_play(logical: String, top: String, speed: float, blend: float, duration: float = 0.0) -> bool:
	var ctx := _anim_ctx()
	var steps: Array = graph.resolve(top, ctx).filter(func(s): return anim_player.has_animation(s.anim))
	if logical == "run":
		_g_branch = graph.branch(top, ctx)
	if steps.is_empty():
		return false
	var b := blend
	if b < 0.0:
		var bb = graph.blend(_g_atomic, _g_top, steps[0].clip, top)
		if bb is String:
			# League TransitionClipBlendData: play the transition clip (e.g. Spell1_To_Run) first
			var tr: Array = graph.resolve(bb, {}).filter(func(s): return anim_player.has_animation(s.anim))
			# (any target state except timed ones: an attack / spell clip must hit its cast frame on time)
			var timed := logical == "attack" or logical == "crit" or logical.begins_with("spell")
			if not tr.is_empty() and not timed:
				steps = tr + steps
			b = 0.05 if not tr.is_empty() and not timed else AnimGraph.DEFAULT_BLEND
		else:
			b = float(bb)
	_g_logical = logical
	_g_top = top
	_g_steps = steps
	_g_i = 0
	_g_hold = false
	var spd := speed
	if duration > 0.0:
		var tot := 0.0
		for s in steps:
			tot += anim_player.get_animation(s.anim).length
		spd = maxf(tot / duration, 0.05)
	_g_speed = spd
	_g_start_step(b)
	cur_anim = logical
	return true


func _g_start_step(blend: float) -> void:
	var s: Dictionary = _g_steps[_g_i]
	var a := anim_player.get_animation(s.anim)
	var last := _g_i == _g_steps.size() - 1
	var cyc := _CYCLIC.has(_g_logical)
	var restart_seq := cyc and _g_steps.size() > 1 and graph.loops(_g_top)
	if last and cyc and not restart_seq:
		a.loop_mode = Animation.LOOP_LINEAR
		_g_t = INF
	else:
		a.loop_mode = Animation.LOOP_NONE
		_g_t = a.length
	var prev_atomic := _g_atomic
	_g_atomic = String(s.clip)
	if String(anim_player.current_animation) == String(s.anim) and anim_player.is_playing():
		anim_player.seek(0.0, true)   # replaying the same clip (idle cycles, attack chains)
	else:
		anim_player.play(s.anim, maxf(blend, 0.0), 1.0)
	anim_player.speed_scale = _safe_speed(_g_speed)
	if anim_ev != null:
		# [anim-events] the clip's League events run on this step's clock (a cyclic state replaying its clip = next pass)
		anim_ev.on_clip(_g_atomic, String(s.anim), a.length, _g_t == INF, cyc and prev_atomic == _g_atomic)


func _g_tick(dt: float) -> void:
	if _g_top == "" or _g_hold or _g_t == INF:
		return
	_g_t -= dt * _g_speed
	if _g_t > 0.004:   # the mixer reaches the clip end this frame too (avoid a stopped frame)
		return
	if _g_i < _g_steps.size() - 1:
		var prev := _g_atomic
		_g_i += 1
		var bb = graph.blend(prev, _g_top, String(_g_steps[_g_i].clip), _g_top, 0.1)
		_g_start_step(float(bb) if not (bb is String) else 0.1)
	elif _CYCLIC.has(_g_logical):
		_g_play(_g_logical, _g_top, _g_speed, -1.0)
	else:
		_g_hold = true


## Non-finite playback speed would put the mixer at a NaN time (unnormalized quaternions).
static func _safe_speed(v: float) -> float:
	return clampf(v, 0.01, 20.0) if is_finite(v) else 1.0


func _skel_scale() -> float:
	if _skel != null and _skel.is_inside_tree():
		return maxf(_skel.global_basis.get_scale().x, 0.001)
	return 1.0


## Run playback rate so the planted foot moves at exactly the unit's move speed (no foot sliding).
func _run_rate(anim: String) -> float:
	var st: float = _strides.get(anim, 0.0)
	if not is_finite(stats.move_speed):
		return 1.0
	var spd := stats.move_speed / base_run_speed()
	if st > 0.05:
		spd = stats.move_speed * G.U / (st * _skel_scale())
	return clampf(spd, 0.35, 3.0)


## Play a logical animation. duration > 0 scales playback to fit that time.
## blend < 0 = League blend table (graph) / 0.12 (legacy).
func play_anim(logical: String, speed: float = 1.0, blend: float = 0.12, duration: float = 0.0) -> void:
	if anim_player == null:
		return
	if G.debug_sites: G.crumb("anim %s %s" % [display_name, logical])
	var top := _graph_clip(logical)
	if top != "" and _g_play(logical, top, speed, blend, duration):
		return
	var names: Array = anim_map.get(logical, [])
	if names.is_empty():
		var raw := _raw_clip(logical)
		if raw == "":
			return
		names = [raw]
	var n: String = names[0] if names.size() == 1 else names[G.rng.randi() % names.size()]
	if not anim_player.has_animation(n):
		return
	var spd := speed
	if duration > 0.0:
		var length := anim_player.get_animation(n).length
		spd = maxf(length / duration, 0.05)
	anim_player.speed_scale = 1.0
	anim_player.play(n, blend if blend >= 0.0 else 0.12, _safe_speed(spd))
	cur_anim = logical
	_g_top = ""
	_g_atomic = ""
	if anim_ev != null:
		var la := anim_player.get_animation(n)
		anim_ev.on_clip("", n, la.length, la.loop_mode != Animation.LOOP_NONE)   # [anim-events]


func play_attack_anim(crit: bool, period: float) -> void:
	_attack_anim = false
	if anim_player == null:
		return
	var key := "crit" if crit and has_anim("crit") else "attack"
	if graph != null and not _kit_override("attack") and not (crit and _kit_override("crit")):
		var a: Dictionary = graph.pick_attack(crit)
		if attack_alternate and not crit and graph.attacks.size() > 1:
			a = graph.attacks[attack_count % graph.attacks.size()]   # [anim-events] scripted alternation (MF pistols)
		if String(a.get("start_bone", "")) != "":
			attack_bone = String(a.start_bone)
		var top := graph.attack_clip(a, crit)
		if top != "" and _g_play(key, top, 1.0, -1.0):
			var length := anim_player.get_animation(_g_steps[0].anim).length
			# League: the attack clip is time-scaled so its castFrame lands exactly on the windup end
			var cast_t := float(a.get("cast_frame", 0.0)) / AnimGraph.CAST_FPS
			var spd := maxf(1.0, length / maxf(period, 0.05))
			if cast_t > 0.0:
				spd = clampf(cast_t / maxf(windup_timer, 0.02), 0.2, 10.0)
			_g_speed = spd
			anim_player.speed_scale = _safe_speed(spd)
			_g_t = length
			anim_lock = minf(length / spd, period)
			_attack_anim = true
			return
	if not anim_map.has(key) or anim_map[key].is_empty():
		return
	var names: Array = anim_map[key]
	var n: String = names[attack_count % names.size()]
	if not anim_player.has_animation(n):
		return
	var length2 := anim_player.get_animation(n).length
	# League scales attack animations to the attack time when attack speed is high
	var spd2 := maxf(1.0, length2 / maxf(period, 0.05))
	anim_player.speed_scale = 1.0
	anim_player.play(n, 0.05, spd2)
	cur_anim = key
	_g_top = ""
	if anim_ev != null:
		anim_ev.on_clip("", n, length2, false)   # [anim-events]
	anim_lock = minf(length2 / spd2, period)
	_attack_anim = true


func play_spell_anim(logical: String, lock: float = 0.4, speed: float = 1.0) -> void:
	if not has_anim(logical):
		return
	var top := _graph_clip(logical)
	var spd := speed
	if top != "" and absf(speed - 1.0) < 0.001 and not casting.is_empty() and float(casting.get("total", 0.0)) > 0.05:
		# League: the cast animation's castFrame (30 fps) lands on the end of the cast time
		var sd: Dictionary = graph.spell_for_slot(int(logical.substr(5)) - 1) if logical.begins_with("spell") 				and logical.length() == 6 else graph.spell_for_clip(top)
		var cf := float(sd.get("cast_frame", 0.0))
		if cf > 0.0:
			spd = clampf(cf / AnimGraph.CAST_FPS / float(casting.total), 0.75, 2.0)
	play_anim(logical, spd, -1.0 if top != "" else 0.05)
	anim_lock = lock
	_attack_anim = false


func _update_visual(dt: float) -> void:
	if _weapon_hold != null:
		# [motion3] expressive clips (taunt / dance / death...) may legitimately drop or swing the weapon
		var wh_on := not dead and not (cur_anim in _WH_OFF)
		if _weapon_hold.active != wh_on:
			_weapon_hold.active = wh_on
	if model != null:
		# only touch the transform when it changes (a set re-propagates through every mesh / bone socket)
		# [cc-anim] a knock-up lift is published through airborne_height so health bars / overlays rise with the unit
		var off := _airborne_offset()
		if off > 0.0:
			airborne_height = off
			_knock_lifted = true
		elif _knock_lifted and dash.is_empty():
			_knock_lifted = false
			airborne_height = 0.0
		var my := airborne_height
		if my != _model_y:
			_model_y = my
			model.position.y = my
	if hit_flash > 0.0 or _flash_shown > 0.0:
		hit_flash = maxf(0.0, hit_flash - dt * 12.0)   # [motion3] ~80 ms
		# "flash" is a per-instance uniform: set it on the mesh instances, not the shared materials
		_flash_shown = hit_flash
		for mi in _meshes:
			if is_instance_valid(mi):
				(mi as GeometryInstance3D).set_instance_shader_parameter("flash", hit_flash * 0.12)   # [motion3] subtle (was 0.55 = bleached white)
	_update_transparency(dt)
	if anim_player == null:
		return
	_g_tick(dt)
	if anim_lock > 0.0:
		anim_lock -= dt
		# League: once the attack has launched, a move order cancels the backswing at once
		if _attack_anim and windup_timer < 0.0 and (_g_hold or moving and dash.is_empty()):
			anim_lock = 0.0
		else:
			# [motion3] League: a cast clip ends at its recovery frame and returns to idle / run (blend table);
			# once the cast itself is over a finished clip releases at once, a move order cancels the rest,
			# and the held recovery never outlasts SPELL_RECOVERY_MAX (kits set generous locks)
			if not _attack_anim and casting.is_empty() and channel.is_empty() and windup_timer < 0.0 and dash.is_empty() 					and _g_top != "":
				if _g_hold or (moving and (cc & Buff.BLOCK_MOVE) == 0):
					anim_lock = 0.0
				else:
					anim_lock = minf(anim_lock, SPELL_RECOVERY_MAX)
			if anim_lock > 0.0:
				return
	_attack_anim = false
	var want := "idle"
	var airborne := (cc & Buff.CC.AIRBORNE) != 0
	if not dash.is_empty() and not (airborne and dash.get("forced", false)):
		return   # [cc-anim] (a knock-back / pull is a forced dash: the unit plays its airborne clip while it flies)
	# [cc-anim] League plays a CC clip only where the champion's AnimationGraphData has one (Ahri: stunned + knockup,
	# Jinx / Master Yi / minions: stunned); everything else keeps its idle. A unit that cannot move never plays run.
	if airborne:
		want = "knockup" if has_anim("knockup") else ("stunned" if has_anim("stunned") else "idle")
	elif (cc & (Buff.CC.STUN | Buff.CC.SUPPRESS | Buff.CC.SLEEP)) != 0:
		want = "stunned" if has_anim("stunned") else "idle"
	elif moving and (cc & Buff.BLOCK_MOVE) == 0:
		want = "run"   # (charm / fear / taunt walks set `moving` only on the frames they actually step)
	elif not channel.is_empty() and has_anim("channel"):
		want = "channel"
	# [motion3] League idles on a looping Idle1 and now and then plays a one-shot fidget (Idle2/3/4), then returns
	if cur_anim == "idle_var" and want == "idle" and not _g_hold:
		return
	if want == "idle" and cur_anim == "idle" and _g_top != "" and not dead and (cc & Buff.IMMOBILIZE) == 0:
		_idle_t += dt
		if _idle_t >= _idle_next:
			_idle_t = 0.0
			_idle_next = 7.0 + G.rng.randf() * 7.0
			var fids := ["Idle2", "Idle3", "Idle4"]
			var fid := graph.find_clip([fids[G.rng.randi() % 3]] + fids)
			if fid != "" and _g_play("idle_var", fid, 1.0, -1.0):
				return
	elif want != "idle":
		_idle_t = 0.0
	if want != cur_anim or _g_hold or (_g_top == "" and not anim_player.is_playing()):
		play_anim(want, 1.0, -1.0)
		_g_recheck = 0.25
	if want != "run" or cur_anim != "run":
		return
	if _g_top != "":
		# League ConditionFloat(MoveSpeed) run/haste switch mid-play (intros are skipped when switching)
		_g_recheck -= dt
		if _g_recheck <= 0.0:
			_g_recheck = 0.25
			var ctx := _anim_ctx()
			var br := graph.branch(_g_top, ctx)
			if br != _g_branch:
				# only a MoveSpeed threshold crossing switches the loop (selector variants play out)
				_g_branch = br
				var steps: Array = graph.resolve(_g_top, ctx)
				if not steps.is_empty() and String(steps[-1].anim) != String(_g_steps[-1].anim) 						and anim_player.has_animation(steps[-1].anim):
					var prev := _g_atomic
					_g_steps = [steps[-1]]
					_g_i = 0
					var bb = graph.blend(prev, _g_top, String(steps[-1].clip), _g_top, 0.15)
					_g_start_step(float(bb) if not (bb is String) else 0.15)
		var rs := _run_rate(String(_g_steps[_g_i].anim))
		if absf(rs - _g_speed) > 0.005:
			_g_speed = rs
			anim_player.speed_scale = _safe_speed(rs)
	else:
		var spd2 := _run_rate(String(anim_player.current_animation))
		anim_player.speed_scale = 1.0
		if absf(anim_player.get_playing_speed() - spd2) > 0.05:
			anim_player.play(anim_player.current_animation, 0.0, spd2)


func base_run_speed() -> float:
	return 340.0


# ===================================================================== [anim-events] League animation events
## Clip events (particles at bones, sounds, submesh visibility, fades) and skin idle particles, run from data
## (core/anim_events.gd). Bound automatically with the animation graph; units without a graph (turrets, summons)
## call setup_anim_events(<data/anim file>) after their model is set.
var anim_ev: AnimEvents = null
var attack_alternate := false ## basic attacks cycle basic / extra attacks in order (League scripts, e.g. Miss Fortune)
var anim_fade := 0.0          ## extra transparency from League FadeEventData


func setup_anim_events(file: String, g: AnimGraph = null, idle_only: bool = false) -> void:
	if AnimEvents.disabled:
		return
	var t := AnimEvents.table(file, g)
	if t.clips.is_empty() and t.idle.is_empty() and t.hidden.is_empty():
		return
	anim_ev = AnimEvents.new(self, t)
	anim_ev.clip_events = not idle_only
	anim_ev.poll = g == null and graph == null and not idle_only   # legacy playback: also watch the AnimationPlayer


## True when one of this unit's animation events plays the sound event (GameAudio skips its own copy).
func anim_sound_bound(ev: String) -> bool:
	return anim_ev != null and anim_ev.has_sound(ev)


func _ev_tick(dt: float) -> void:
	if anim_ev == null:
		return
	var spd := 1.0
	if anim_player != null:
		spd = _g_speed if _g_top != "" else anim_player.get_playing_speed()
	anim_ev.tick(dt, spd, anim_player)


# ===================================================================== animation LOD (manual mixer advance)
## Champions and minions drive their AnimationPlayer by hand (callback mode MANUAL) from tick():
## animation follows game time (pause / game speed), and units the player can't see (off screen or
## hidden by fog of war) skip the mixer + skeleton update entirely, so they cost no pose evaluation
## and no GPU skinning. The skipped time is applied in one step when the unit becomes visible again.
var _model_y := INF
var _knock_lifted := false
var _manual_ap: AnimationPlayer = null
var _anim_acc := 0.0
var _on_screen := true
var _vis_notifier: VisibleOnScreenNotifier3D = null
var _anim_min_step := 0.0     ## minimum mixer step (minions: 60 Hz cap, champions: every frame)
static var _headless := -1
static var anim_lod := true    ## --animlod=0 disables the visibility skip / rate cap (A/B profiling)
static var anim_stats := [0, 0]   ## [mixer advances, skipped] since last read (profiling)
const ANIM_CATCHUP_MAX := 2.0
const MINION_ANIM_STEP := 1.0 / 60.0


func _setup_anim_lod() -> void:
	if anim_player == null or _manual_ap == anim_player:
		return
	anim_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_manual_ap = anim_player
	_anim_acc = 0.0
	if _headless < 0:
		_headless = 1 if DisplayServer.get_name() == "headless" else 0
		anim_lod = not ("--animlod=0" in OS.get_cmdline_user_args())
	# minions are many and small on screen: their pose updates at most 60 times a second
	_anim_min_step = MINION_ANIM_STEP if kind == G.Kind.MINION else 0.0
	if _headless == 1 or _vis_notifier != null:
		return
	_vis_notifier = VisibleOnScreenNotifier3D.new()
	var r := maxf(selection_radius, 1.0) * 1.6
	_vis_notifier.aabb = AABB(Vector3(-r, -0.5, -r), Vector3(2.0 * r, height * 1.6 + 1.5, 2.0 * r))
	_vis_notifier.screen_entered.connect(func(): _on_screen = true)
	_vis_notifier.screen_exited.connect(func(): _on_screen = false)
	add_child(_vis_notifier)
	_on_screen = false
	if is_inside_tree():
		_on_screen = _vis_notifier.is_on_screen()


func _anim_advance(dt: float) -> void:
	if _manual_ap == null:
		return
	if _manual_ap != anim_player:
		# the model was replaced: the new player runs on its own (idle callback) until re-setup
		_manual_ap = null
		return
	if not anim_player.is_playing():
		# a finished one-shot (held spell pose, death) keeps its last pose; advancing a stopped mixer
		# costs ~1 ms per call (it re-evaluates every track with nothing to blend)
		_anim_acc = 0.0
		return
	_anim_acc += dt
	if anim_lod and (not _on_screen or not visible or _anim_acc < _anim_min_step * 0.75):
		if _anim_acc > ANIM_CATCHUP_MAX:
			_anim_acc = ANIM_CATCHUP_MAX
		anim_stats[1] += 1
		return
	if _anim_acc > 0.1 and not dead and _g_top != "" and _g_t != INF and _g_t > 0.0:
		# catching up after being skipped: the graph driver kept the clip clock (_g_t = clip time
		# left), so jump the mixer there instead of overshooting past the end of a one-shot step
		var ln := anim_player.current_animation_length
		anim_player.seek(clampf(ln - _g_t, 0.0, ln), true)
	else:
		anim_player.advance(_anim_acc)
	_anim_acc = 0.0
	anim_stats[0] += 1


# ===================================================================== transparency (brush / stealth / corpse fade)
var _meshes: Array = []       ## MeshInstance3D of the model
var _flash_shown := 0.0
var _alpha := -1.0            ## current GeometryInstance3D.transparency (-1 = not applied yet)
var corpse_fade := 0.0        ## 0..1 extra transparency (minion corpse fade-out)
const BRUSH_TRANSPARENCY := 0.45


var _fow_hidden := false       ## the player's team can't see this unit (League fog of war / brush)
var _fow_kind := -1           ## 1 = champions / minions / summons hide in fog (lazy)
const FOW_FADE_RATE := 8.0     ## alpha / s: units fade out / in over ~0.12 s when vision changes


func _target_transparency() -> float:
	if _fow_hidden:
		return 1.0
	var want := maxf(corpse_fade, anim_fade)
	# League: a unit standing in brush is drawn semi-transparent for its own team
	if in_brush > 0 and _fow_kind == 1 and not dead and G.player != null and G.player.team == team:
		want = maxf(want, BRUSH_TRANSPARENCY)
	if (cc & Buff.CC.CAMOUFLAGE) != 0 and not _meshes.is_empty() and is_instance_valid(_meshes[0]):
		var st = (_meshes[0] as GeometryInstance3D).get_instance_shader_parameter("stealth")
		if st != null and float(st) > 0.0:
			want = maxf(want, float(st) * 0.7)
	return clampf(want, 0.0, 1.0)


func _update_transparency(dt: float) -> void:
	if _fow_kind < 0:
		_fow_kind = 1 if kind == G.Kind.CHAMPION or kind == G.Kind.MINION or kind == G.Kind.SUMMON else 0
	# League fog of war: enemies the player's team can't see (brush, out of sight range) are not drawn
	var pl = G.player
	if _fow_kind == 1 and not dead:
		_fow_hidden = pl != null and pl.team != team and pl.team < 2 and not visible_to[pl.team]
	if not _fow_hidden and not visible:
		visible = true
	var want := _target_transparency()
	if _alpha < 0.0:
		_alpha = want
		_apply_transparency(_alpha)
		if _fow_hidden:
			visible = false
		return
	if absf(_alpha - want) < 0.001:
		return
	var rate := FOW_FADE_RATE if _fow_hidden or _alpha > 0.75 else 3.0
	_alpha = move_toward(_alpha, want, dt * rate)
	_apply_transparency(_alpha)
	if _fow_hidden and _alpha >= 0.999:
		visible = false   # hides the model, attached VFX and bone sockets; skips skinning and drawing


func _apply_transparency(a: float) -> void:
	for mi in _meshes:
		if is_instance_valid(mi):
			var gi := mi as GeometryInstance3D
			gi.transparency = a
			# the ink hull would show through a see-through body
			gi.set_instance_shader_parameter("ink", 1.0 if a < 0.02 else 0.0)


func _airborne_offset() -> float:
	if (cc & Buff.CC.AIRBORNE) == 0:
		return 0.0
	for b in buffs:
		if (b.cc & Buff.CC.AIRBORNE) != 0 and b.id == "airborne":
			var k := 1.0 - clampf(b.remaining / maxf(b.duration, 0.01), 0.0, 1.0)
			return 4.0 * k * (1.0 - k) * minf(1.6, 0.9 + b.duration * 0.6)
	return 0.0


func hp_ratio() -> float:
	return clampf(hp / maxf(stats.max_hp, 1.0), 0.0, 1.0)


func is_enemy_of(u) -> bool:
	return u != null and u.team != team and team < 2 and u.team < 2
