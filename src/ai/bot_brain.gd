class_name BotBrain
extends RefCounted
## Champion AI: laning, teamfighting, retreating, sieging, ability usage.
## Also serves as the `ctx` object passed to Ability.ai_consider().

var c: Champion
var m = null
var think_timer := 0.0
var mode := "lane"
var focus: Unit = null
var enemies: Array = []          ## visible enemy champions nearby
var allies: Array = []           ## allied champions nearby (not self)
var enemy_minions: Array = []
var ally_minions: Array = []
var enemy_turret: Unit = null    ## enemy turret whose range we are near
var is_ranged := true
var aggression := 0.5
var reaction := 0.22
var aim_error := 0.35
var retreat_hp := 0.28
var _move_goal := Vector3.INF
var _move_timer := 0.0
var _ability_timer := 0.0
var _last_think_time := 0.0
var shop_timer := 0.0
var personal_offset := 0.0


func setup(champ: Champion, p_match) -> void:
	c = champ
	m = p_match
	is_ranged = c.stats.attack_range > 300.0
	aggression = clampf(0.45 + G.rng.randf_range(-0.15, 0.2) + (0.15 if not is_ranged else 0.0), 0.2, 0.9)
	personal_offset = G.rng.randf_range(-2.5, 2.5)
	var diff: int = G.settings.get("difficulty", 1)
	reaction = [0.4, 0.25, 0.16, 0.1][diff]
	aim_error = [1.0, 0.5, 0.25, 0.1][diff]
	retreat_hp = [0.2, 0.28, 0.3, 0.3][diff]
	if c.kit != null and c.kit.has_method("ai_tuning"):
		var t: Dictionary = c.kit.ai_tuning()
		aggression = t.get("aggression", aggression)


# ===================================================================== main loop
func think(dt: float) -> void:
	think_timer -= dt
	_move_timer -= dt
	_ability_timer -= dt
	if think_timer > 0.0:
		return
	think_timer = reaction * G.rng.randf_range(0.8, 1.2)
	_gather()
	if c.in_fountain:
		_shop_and_augments()
	if c.is_busy() and not c.casting.is_empty():
		return
	if not c.channel.is_empty() and not c.channel.ability.can_move_while_channeling:
		return
	if _ability_timer <= 0.0:
		if _try_abilities():
			_ability_timer = 0.25
	if _try_summoners():
		pass
	for it in c.items:
		if it.has_active() and it.active_left <= 0.0 and it.ai_should_activate(self):
			var tp: Vector3 = focus.global_position if focus != null and is_instance_valid(focus) else c.global_position + c.facing * 3.0
			it.activate(tp, focus)
	if _should_retreat():
		mode = "retreat"
		_retreat()
		return
	var t := _pick_fight_target()
	if t != null:
		mode = "fight"
		focus = t
		_fight(t)
		return
	focus = null
	mode = "lane"
	_lane()


func think_dead(_dt: float) -> void:
	shop_timer -= _dt
	if shop_timer <= 0.0:
		shop_timer = 1.0
		_shop_and_augments()


func _gather() -> void:
	var p := c.global_position
	enemies.clear()
	allies.clear()
	enemy_minions.clear()
	ally_minions.clear()
	enemy_turret = null
	for u in m.units_in_radius(p, 17.0, -1):
		if u == c or u.dead:
			continue
		if u.team == c.team:
			if u.kind == G.Kind.CHAMPION:
				allies.append(u)
			elif u.kind == G.Kind.MINION:
				ally_minions.append(u)
		else:
			if not u.is_targetable_by(c.team) and u.kind != G.Kind.TURRET:
				continue
			match u.kind:
				G.Kind.CHAMPION:
					enemies.append(u)
				G.Kind.MINION, G.Kind.SUMMON:
					enemy_minions.append(u)
				G.Kind.TURRET:
					if not u.dead and G.flat_dist(p, u.global_position) < u.attack_range_m() + 4.0:
						enemy_turret = u


# ===================================================================== evaluation
func power_of(u) -> float:
	var dps: float = u.stats.ad * u.stats.attack_speed * (1.0 + u.stats.crit_chance) + u.stats.ap * 0.8 + u.level * 25.0
	var ehp: float = u.hp * (1.0 + (u.stats.armor + u.stats.mr) * 0.005) + u.total_shield()
	return sqrt(maxf(dps, 1.0) * maxf(ehp, 1.0))


func team_power(list: Array, include_self: bool) -> float:
	var s := power_of(c) if include_self else 0.0
	for u in list:
		s += power_of(u)
	return s


func in_danger() -> bool:
	return not enemies.is_empty() and c.hp_ratio() < 0.5


func wants_speed() -> bool:
	return mode == "retreat" and in_danger() or (mode == "fight" and focus != null and focus.hp_ratio() < 0.3 and G.flat_dist(c.global_position, focus.global_position) > c.attack_range_m() + 2.0)


func _turret_targeting_me() -> bool:
	return enemy_turret != null and enemy_turret.attack_target == c


func _should_retreat() -> bool:
	if _turret_targeting_me():
		var tanked := false
		for mn in ally_minions:
			if G.flat_dist(mn.global_position, enemy_turret.global_position) < enemy_turret.attack_range_m() + 1.0:
				tanked = true
				break
		if not tanked or c.hp_ratio() < 0.6:
			return true
	if enemies.is_empty():
		return c.hp_ratio() < 0.15 and _nearest_relic() == null
	var hp := c.hp_ratio()
	if hp < retreat_hp * (1.2 - aggression * 0.4):
		var ally_p := team_power(allies.filter(func(a): return G.flat_dist(a.global_position, c.global_position) < 10.0), true)
		var enemy_p := team_power(enemies.filter(func(e): return G.flat_dist(e.global_position, c.global_position) < 11.0), false)
		if enemy_p > ally_p * 0.6 or hp < 0.12:
			return true
	return false


func _pick_fight_target() -> Unit:
	if enemies.is_empty():
		return null
	var p := c.global_position
	var engage := c.attack_range_m() + (5.0 if is_ranged else 7.0) + aggression * 4.0
	var near_allies := allies.filter(func(a): return G.flat_dist(a.global_position, p) < 12.0)
	var near_enemies := enemies.filter(func(e): return G.flat_dist(e.global_position, p) < 13.0)
	var ratio := team_power(near_allies, true) / maxf(team_power(near_enemies, false), 1.0)
	var best: Unit = null
	var best_s := -INF
	for e in enemies:
		var d := G.flat_dist(p, e.global_position)
		if d > engage:
			continue
		# don't chase deep into enemy turret range unless it's a kill
		var under_turret := _under_enemy_turret(e.global_position)
		if under_turret and e.hp_ratio() > 0.25 and ratio < 2.0:
			continue
		var s := -d * 0.15
		s += (1.0 - e.hp_ratio()) * 3.0
		s += 1.5 if (e.cc & Buff.IMMOBILIZE) != 0 else 0.0
		s += 1.0 if e == focus else 0.0
		s += 0.6 if e.stats.attack_range > 300.0 else 0.0   # carries
		if s > best_s:
			best_s = s
			best = e
	if best == null:
		return null
	if ratio < 0.55 - aggression * 0.3 and best.hp_ratio() > 0.3:
		return null
	return best


func _under_enemy_turret(pos: Vector3) -> bool:
	for s in m.structures:
		if s.team != c.team and s.kind == G.Kind.TURRET and not s.dead and not s.is_invulnerable() == false:
			pass
		if s.team != c.team and s.kind == G.Kind.TURRET and not s.dead:
			if G.flat_dist(pos, s.global_position) < s.attack_range_m() + s.radius:
				return true
	return false


# ===================================================================== actions
func _move(goal: Vector3, force: bool = false) -> void:
	if not force and _move_timer > 0.0 and _move_goal != Vector3.INF and G.flat_dist(goal, _move_goal) < 1.0:
		return
	_move_goal = goal
	_move_timer = 0.3
	c.issue_move(goal)


func _attack(u: Unit) -> void:
	if c.attack_target != u or c.cmd != Unit.Cmd.ATTACK:
		c.issue_attack(u)


func _retreat() -> void:
	var home: Vector3 = c.spawn_point
	var relic = _nearest_relic()
	var goal := home
	if relic != null and G.flat_dist(relic.global_position, c.global_position) < G.flat_dist(home, c.global_position) * 0.6:
		goal = relic.global_position
	# if we're safe enough (no enemies close) and not low, go back to the lane instead
	_move(goal)


func _nearest_relic():
	var best = null
	var bd := 40.0
	for r in m.relics:
		if r.active:
			var d := G.flat_dist(r.global_position, c.global_position)
			if d < bd and not _under_enemy_turret(r.global_position):
				bd = d
				best = r
	return best


func _fight(t: Unit) -> void:
	var p := c.global_position
	var d := c.edge_dist(t)
	if is_ranged:
		var t_melee: bool = t.stats.attack_range < 300.0
		# kite: after the attack has fired, step away from approaching melee threats
		if t_melee and d < 2.5 and c.windup_timer < 0.0 and c.attack_timer > c.stats.attack_period() * 0.35:
			var away := G.flat_dir(t.global_position, p)
			_move(p + away * 3.0, true)
			return
	_attack(t)


func _lane() -> void:
	var p := c.global_position
	var enemy_nexus: Vector3 = m.nexus_units[1 - c.team].global_position
	var my_nexus: Vector3 = m.nexus_units[c.team].global_position
	var lane_dir := G.flat_dir(my_nexus, enemy_nexus)
	# farthest allied minion along the lane
	var front: Unit = null
	var front_v := -INF
	for mn in m.units:
		if mn.kind == G.Kind.MINION and mn.team == c.team and not mn.dead:
			var v: float = (mn.global_position - my_nexus).dot(lane_dir)
			if v > front_v:
				front_v = v
				front = mn
	# last-hit / attack minions in range
	if not enemy_minions.is_empty():
		var best: Unit = null
		var best_s := INF
		for e in enemy_minions:
			if _under_enemy_turret(e.global_position) and front == null:
				continue
			var d := G.flat_dist(p, e.global_position)
			if d > c.attack_range_m() + 6.0:
				continue
			var s: float = e.hp + d * 15.0
			if e.hp <= c.stats.ad * 1.05:
				s -= 1000.0
			if s < best_s:
				best_s = s
				best = e
		if best != null:
			_attack(best)
			return
	# siege turret if our minions are tanking it
	if enemy_turret != null and not enemy_turret.is_invulnerable():
		var tanking := false
		for mn in ally_minions:
			if G.flat_dist(mn.global_position, enemy_turret.global_position) < enemy_turret.attack_range_m():
				tanking = true
				break
		if tanking and enemy_turret.attack_target != c:
			_attack(enemy_turret)
			return
	# attack inhibitor / nexus when exposed
	for s in m.structures:
		if s.team != c.team and (s.kind == G.Kind.INHIBITOR or s.kind == G.Kind.NEXUS) and not s.dead and not s.is_invulnerable():
			if G.flat_dist(p, s.global_position) < 12.0:
				_attack(s)
				return
	var goal: Vector3
	if front != null:
		var back := 4.5 if is_ranged else 1.5
		goal = front.global_position - lane_dir * back
	else:
		# no wave: hold near our first standing turret
		goal = _hold_position()
	var side := Vector3(-lane_dir.z, 0, lane_dir.x)
	goal += side * personal_offset
	if not m.nav.is_walkable(goal):
		goal = m.nav.nearest_walkable(goal)
	if G.flat_dist(p, goal) > 1.5:
		_move(goal)
	elif c.moving:
		pass


func _hold_position() -> Vector3:
	var t = m.outer_turrets[c.team]
	if t == null or t.dead:
		t = m.inhib_turrets[c.team]
	if t == null or t.dead:
		return m.nexus_units[c.team].global_position
	var enemy_nexus: Vector3 = m.nexus_units[1 - c.team].global_position
	return t.global_position + G.flat_dir(t.global_position, enemy_nexus) * 3.0


# ===================================================================== abilities
func _try_abilities() -> bool:
	if not c.can_cast():
		return false
	var order := [3, 0, 2, 1]
	for slot in order:
		var ab: Ability = c.abilities[slot]
		if ab == null or ab.cast_block_reason() != "":
			continue
		var t := ab.ai_consider(self)
		if t.get("_default", false):
			t = default_consider(ab)
		if not t.is_empty():
			if ab.try_cast(t):
				return true
	return false


func _try_summoners() -> bool:
	for sm in c.summoners:
		if sm == null or sm.cast_block_reason() != "":
			continue
		var t: Dictionary = sm.ai_consider(self)
		if not t.is_empty() and not t.get("_default", false):
			return sm.try_cast(t)
	return false


## Generic ability usage based on the ability's targeting metadata.
func default_consider(ab: Ability) -> Dictionary:
	var rng := ab.range_m()
	match ab.target_type:
		Ability.Target.UNIT:
			if ab.target_side == Ability.Side.ENEMY:
				var t := best_enemy_in_range(rng + 0.5)
				if t != null:
					return {"unit": t, "pos": t.global_position, "dir": G.flat_dir(c.global_position, t.global_position)}
			else:
				var a := lowest_ally(rng, 0.6)
				if a != null:
					return {"unit": a, "pos": a.global_position, "dir": G.flat_dir(c.global_position, a.global_position)}
		Ability.Target.DIRECTION:
			var t2 := best_enemy_in_range(rng * 0.92)
			if t2 != null:
				var aim := predict(t2, ab.cast_time + G.flat_dist(c.global_position, t2.global_position) / maxf(ab_speed(ab), 1.0))
				return aim_at(aim, ab)
		Ability.Target.POINT:
			var t3 := best_enemy_in_range(rng + ab.ind_radius * G.U * 0.6)
			if t3 != null:
				var aim2 := predict(t3, ab.cast_time + 0.25)
				return aim_at(aim2, ab)
		Ability.Target.NONE:
			var r := maxf(ab.ind_radius * G.U, c.attack_range_m() + 1.0)
			if count_enemies_near(c.global_position, r) > 0:
				return {"pos": c.global_position, "dir": c.facing}
	return {}


func ab_speed(ab: Ability) -> float:
	return float(ab.get_meta("missile_speed", 18.0)) if ab.has_meta("missile_speed") else 18.0


func aim_at(pos: Vector3, ab: Ability) -> Dictionary:
	var err := Vector3(G.rng.randf_range(-1, 1), 0, G.rng.randf_range(-1, 1)) * aim_error
	var p := pos + err
	return ab.make_target(p, null)


## Predicted position of a unit after `t` seconds (linear).
func predict(u: Unit, t: float) -> Vector3:
	var v: Vector3 = u.velocity
	if (u.cc & Buff.BLOCK_MOVE) != 0:
		v = Vector3.ZERO
	return u.global_position + v * clampf(t, 0.0, 1.5)


func best_enemy_in_range(r: float, champs_only: bool = true) -> Unit:
	var p := c.global_position
	if focus != null and is_instance_valid(focus) and not focus.dead and focus.is_targetable_by(c.team) \
			and G.flat_dist(p, focus.global_position) <= r + focus.radius:
		return focus
	var best: Unit = null
	var best_s := INF
	for e in enemies:
		var d := G.flat_dist(p, e.global_position)
		if d > r + e.radius:
			continue
		var s: float = e.hp_ratio() * 10.0 + d * 0.3
		if s < best_s:
			best_s = s
			best = e
	return best


func lowest_ally(r: float, below: float) -> Unit:
	var best: Unit = null
	var br := below
	for a in allies + [c]:
		if a.dead:
			continue
		if G.flat_dist(c.global_position, a.global_position) > r + a.radius:
			continue
		if a.hp_ratio() < br:
			br = a.hp_ratio()
			best = a
	return best


func count_enemies_near(pos: Vector3, r: float, champs_only: bool = true) -> int:
	var n := 0
	for e in enemies:
		if G.flat_dist(pos, e.global_position) <= r + e.radius:
			n += 1
	if not champs_only:
		for e in enemy_minions:
			if G.flat_dist(pos, e.global_position) <= r + e.radius:
				n += 1
	return n


## Best point to hit the most enemy champions with a circle of radius r within range.
func best_cluster_point(rng: float, r: float, min_count: int = 1) -> Vector3:
	var best := Vector3.INF
	var best_n := min_count - 1
	for e in enemies:
		if G.flat_dist(c.global_position, e.global_position) > rng + r:
			continue
		var n := count_enemies_near(e.global_position, r)
		if n > best_n:
			best_n = n
			best = e.global_position
	return best


# ===================================================================== summoner decisions
func flash_decision(ab) -> Dictionary:
	if mode == "retreat" and c.hp_ratio() < 0.2 and in_danger():
		var away := G.flat_dir(enemies[0].global_position, c.global_position)
		return {"pos": c.global_position + away * 4.0, "dir": away}
	if mode == "fight" and focus != null and focus.hp_ratio() < 0.15 and c.hp_ratio() > 0.4:
		var d := G.flat_dist(c.global_position, focus.global_position)
		if d > c.attack_range_m() + 1.0 and d < c.attack_range_m() + 4.5:
			return {"pos": focus.global_position, "dir": G.flat_dir(c.global_position, focus.global_position)}
	return {}


func mark_decision(ab) -> Dictionary:
	if ab.recast_window > 0.0:
		var tgt = ab.marked
		if tgt != null and is_instance_valid(tgt) and tgt.kind == G.Kind.CHAMPION and mode == "fight" \
				and (tgt.hp_ratio() < 0.5 or aggression > 0.6) and c.hp_ratio() > 0.45 and not _under_enemy_turret(tgt.global_position):
			return {"pos": tgt.global_position, "dir": G.flat_dir(c.global_position, tgt.global_position)}
		return {}
	var t := best_enemy_in_range(ab.range_m() * 0.85)
	if t != null and mode != "retreat":
		var aim := predict(t, G.flat_dist(c.global_position, t.global_position) / 13.0)
		return aim_at(aim, ab)
	return {}


func ignite_decision(ab) -> Dictionary:
	var t := best_enemy_in_range(ab.range_m())
	if t != null and t.hp_ratio() < 0.35:
		return {"unit": t, "pos": t.global_position}
	return {}


# ===================================================================== shop / augments
func _shop_and_augments() -> void:
	if m.has_method("bot_shop"):
		m.bot_shop(c)
	if c.augments_pending > 0 and m.has_method("bot_choose_augment"):
		m.bot_choose_augment(c)
