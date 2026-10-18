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
	stats.level = level
	stats.slow = _strongest_slow()
	stats.recompute(effects)
	if old_max > 0.0 and stats.max_hp > old_max and not dead:
		hp += stats.max_hp - old_max
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
	for e in effects:
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
		if (b.cc & Buff.TENACITY_AFFECTED) != 0 and stats.tenacity > 0.0:
			b.duration *= 1.0 - stats.tenacity
			b.remaining = b.duration
	if b.slow_amount > 0.0 and has_cc_immunity():
		return null
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
		for e in b.source.effects:
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
	for u in damage_log:
		if is_instance_valid(u) and t - damage_log[u] <= window:
			out.append(u)
	return out


func on_damaged(info: DamageInfo) -> void:
	if info.final > 0.0 or info.absorbed > 0.0:
		hit_flash = 1.0


# ===================================================================== tick
func tick(dt: float) -> void:
	if dead:
		tick_dead(dt)
		return
	_tick_buffs(dt)
	recompute_stats()
	_regen(dt)
	_tick_shields(dt)
	for e in effects:
		if not (e is Buff):
			e.on_tick(self, dt)
	if dead:
		return
	G.ctx = "think"
	think(dt)
	G.ctx = "cast"
	_update_cast(dt)
	G.ctx = "attack"
	_update_attack(dt)
	G.ctx = "move"
	_update_movement(dt)
	G.ctx = "visual"
	_update_visual(dt)
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
	for b in buffs:
		if not b.tick(self, dt):
			expired.append(b)
	for b in expired:
		remove_buff(b)


func _regen(dt: float) -> void:
	if hp < stats.max_hp:
		hp = minf(stats.max_hp, hp + stats.hp_regen * dt)
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
			_launch_attack(_windup_target)
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
				_start_attack(attack_target)
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
	windup_timer = period * windup_pct
	_windup_target = t
	_pending_crit = G.rng.randf() < stats.crit_chance
	attack_count += 1
	play_attack_anim(_pending_crit, period)


func _launch_attack(t: Unit) -> void:
	windup_timer = -1.0
	_windup_target = null
	var crit := _pending_crit
	for e in effects:
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
	if crit:
		dmg *= stats.crit_damage
	var info := Combat.deal(self, t, dmg, G.DmgType.PHYSICAL, {"is_attack": true, "is_crit": crit})
	for e in effects:
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
			ab.execute(c.target)
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
			pos += dir * step
			step = 0.0
			face_toward(pos + dir, dt)
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
	var dest := b.forced_dest
	if b.forced_target != null and is_instance_valid(b.forced_target):
		dest = b.forced_target.global_position
	var dir := G.flat_dir(global_position, dest)
	if (b.cc & Buff.CC.FEAR) != 0:
		dir = -dir
	if (b.cc & Buff.CC.TAUNT) != 0 and b.forced_target != null and is_instance_valid(b.forced_target):
		if in_attack_range(b.forced_target):
			if attack_timer <= 0.0 and windup_timer < 0.0:
				_start_attack(b.forced_target)
			return
	var speed := stats.move_speed * G.U
	var np := global_position + dir * speed * dt
	if match_ref != null and match_ref.nav != null and not match_ref.nav.is_walkable(np):
		return
	face_toward(np, dt)
	set_ground_pos(np)
	moving = true


## Start a dash/leap. opts: speed (m/s) or duration, height (arc), on_arrive(Callable),
## on_tick(Callable(unit, progress)), unstoppable(bool), forced(bool: displacement by enemy),
## can_cast(bool), stop_at_walls(bool), anim(String)
func start_dash(to: Vector3, opts: Dictionary = {}) -> void:
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
	if dist > 0.01:
		face_toward(dest, 100.0)
	if opts.has("anim"):
		play_anim(opts.anim, 1.0, 0.05, duration)
	if not opts.get("forced", false):
		for e in effects:
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


func face_toward(p: Vector3, dt: float) -> void:
	var d := Vector3(p.x - global_position.x, 0.0, p.z - global_position.z)
	if d.length_squared() < 0.0001:
		return
	d = d.normalized()
	facing = facing.slerp(d, clampf(dt * 18.0, 0.0, 1.0)).normalized() if dt < 50.0 else d
	if model != null:
		model.rotation.y = atan2(-facing.x, -facing.z)


func teleport(p: Vector3) -> void:
	stop_moving()
	dash = {}
	set_ground_pos(p)


# ===================================================================== death
func die(killer, info = null) -> void:
	if dead:
		return
	dead = true
	hp = 0.0
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
	for b in buffs.duplicate():
		if not b.permanent:
			remove_buff(b)
	for e in effects.duplicate():
		e.on_death(killer)
	if killer != null and is_instance_valid(killer):
		for e in killer.effects.duplicate():
			e.on_kill(self)
	play_anim("death", 1.0, 0.1)
	died.emit(self, killer)
	if match_ref != null:
		match_ref.on_unit_died(self, killer, info)
	on_died(killer)


func on_died(_killer) -> void:
	pass


# ===================================================================== visuals
func set_model(m: Node3D) -> void:
	if model != null:
		model.queue_free()
	model = m
	add_child(m)
	anim_player = _find_anim_player(m)
	materials.clear()
	_collect_materials(m)
	recompute_stats()


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
		for i in mi.get_surface_override_material_count():
			var mat := mi.get_surface_override_material(i)
			if mat == null and mi.mesh != null:
				mat = mi.mesh.surface_get_material(i)
			if mat is ShaderMaterial:
				materials.append(mat)
	for c in n.get_children():
		_collect_materials(c)


func has_anim(logical: String) -> bool:
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


## Play a logical animation. duration > 0 scales playback to fit that time.
func play_anim(logical: String, speed: float = 1.0, blend: float = 0.12, duration: float = 0.0) -> void:
	if anim_player == null:
		return
	var names: Array = anim_map.get(logical, [])
	if names.is_empty():
		var raw := _raw_clip(logical)
		if raw == "":
			return
		names = [raw]
	if names.is_empty():
		return
	var n: String = names[0] if names.size() == 1 else names[G.rng.randi() % names.size()]
	if not anim_player.has_animation(n):
		return
	var spd := speed
	if duration > 0.0:
		var length := anim_player.get_animation(n).length
		spd = maxf(length / duration, 0.05)
	anim_player.play(n, blend, spd)
	cur_anim = logical


func play_attack_anim(crit: bool, period: float) -> void:
	var key := "crit" if crit and has_anim("crit") else "attack"
	if anim_player == null or not has_anim(key):
		return
	var names: Array = anim_map[key]
	var n: String = names[attack_count % names.size()]
	var length := anim_player.get_animation(n).length
	# League scales attack animations to the attack time when attack speed is high
	var spd := maxf(1.0, length / maxf(period, 0.05))
	anim_player.play(n, 0.05, spd)
	cur_anim = key
	anim_lock = minf(length / spd, period)


func play_spell_anim(logical: String, lock: float = 0.4, speed: float = 1.0) -> void:
	if has_anim(logical):
		play_anim(logical, speed, 0.05)
		anim_lock = lock


func _update_visual(dt: float) -> void:
	if model != null:
		model.position.y = airborne_height + _airborne_offset()
	if hit_flash > 0.0:
		hit_flash = maxf(0.0, hit_flash - dt * 6.0)
	for mat in materials:
		mat.set_shader_parameter("flash", hit_flash * 0.55)
	if anim_lock > 0.0:
		anim_lock -= dt
		return
	if anim_player == null:
		return
	var want := "idle"
	if not dash.is_empty():
		return
	if (cc & (Buff.CC.STUN | Buff.CC.SUPPRESS | Buff.CC.SLEEP)) != 0 and has_anim("stunned"):
		want = "stunned"
	elif (cc & Buff.CC.AIRBORNE) != 0 and has_anim("knockup"):
		want = "knockup"
	elif moving or (cc & Buff.FORCED_MOVE) != 0:
		want = "run"
	elif not channel.is_empty() and has_anim("channel"):
		want = "channel"
	if want != cur_anim or not anim_player.is_playing():
		var spd := 1.0
		if want == "run":
			spd = clampf(stats.move_speed / base_run_speed(), 0.6, 2.2)
		play_anim(want, spd, 0.15)
	elif want == "run":
		anim_player.speed_scale = 1.0
		var spd2 := clampf(stats.move_speed / base_run_speed(), 0.6, 2.2)
		if absf(anim_player.get_playing_speed() - spd2) > 0.05:
			anim_player.play(anim_player.current_animation, 0.0, spd2)


func base_run_speed() -> float:
	return 340.0


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
