class_name BotBrain
extends RefCounted
## Champion AI: laning, teamfighting, kiting, retreating, sieging, dodging and ability usage.
## Team-level decisions (engage / hold / retreat, focus target) come from a shared TeamAI.
## Also serves as the `ctx` object passed to Ability.ai_consider() (see docs/KIT_GUIDE.md).

var c: Champion
var m = null
var team_ai: TeamAI = null
var think_timer := 0.0
var mode := "lane"               ## "lane", "fight", "retreat" (read by kits)
var focus: Unit = null
var enemies: Array = []          ## visible enemy champions nearby
var allies: Array = []           ## allied champions nearby (not self)
var enemy_minions: Array = []
var ally_minions: Array = []
var enemy_turret: Unit = null    ## enemy turret whose range we are near
var is_ranged := true
var frontline := false           ## tanks / melee: lead the engage, stand in front
var aggression := 0.5
var reaction := 0.22
var aim_error := 0.35
var retreat_hp := 0.28
var dodge_chance := 0.3
var personal_offset := 0.0
var shop_timer := 0.0
var _move_goal := Vector3.INF
var _move_timer := 0.0
var _ability_timer := 0.0
var _dodge_until := -1.0
var _dodge_check := 0.0
var _dodged := {}                ## missile -> true (decided once per missile)
var _chase_since := -1.0
var _strafe_dir := 1.0
var _strafe_t := 0.0


func setup(champ: Champion, p_match) -> void:
	c = champ
	m = p_match
	is_ranged = c.stats.attack_range > 300.0
	var roles := ChampionDB.roles(c.alias)
	frontline = not is_ranged or "tank" in roles
	aggression = clampf(0.45 + G.rng.randf_range(-0.15, 0.2) + (0.15 if frontline else 0.0), 0.2, 0.9)
	personal_offset = G.rng.randf_range(-2.5, 2.5)
	var diff: int = G.settings.get("difficulty", 1)
	reaction = [0.4, 0.25, 0.16, 0.1][diff]
	aim_error = [1.0, 0.5, 0.25, 0.1][diff]
	retreat_hp = [0.2, 0.26, 0.3, 0.3][diff]
	dodge_chance = [0.0, 0.3, 0.6, 0.85][diff]
	if c.kit != null and c.kit.has_method("ai_tuning"):
		var t: Dictionary = c.kit.ai_tuning()
		aggression = t.get("aggression", aggression)
	team_ai = p_match.team_ai(c.team)


# ===================================================================== main loop
func think(dt: float) -> void:
	think_timer -= dt
	_move_timer -= dt
	_ability_timer -= dt
	_dodge_check -= dt
	if _dodge_check <= 0.0:
		_dodge_check = 0.05
		if _try_dodge():
			return
	if m.time < _dodge_until:
		return
	if think_timer > 0.0:
		return
	think_timer = reaction * G.rng.randf_range(0.8, 1.2)
	team_ai.refresh()
	_gather()
	if c.in_fountain:
		_shop_and_augments()
	if c.is_busy() and not c.casting.is_empty():
		return
	if not c.channel.is_empty() and not c.channel.ability.can_move_while_channeling:
		return
	# focus fire: adopt the team's target when it's within reach
	var tf := team_ai.focus
	if tf != null and is_instance_valid(tf) and not tf.dead and G.flat_dist(tf.global_position, c.global_position) < c.attack_range_m() + 6.0:
		focus = tf
	elif focus != null and (not is_instance_valid(focus) or focus.dead):
		focus = null
	if _ability_timer <= 0.0:
		if _try_abilities():
			_ability_timer = 0.25
	_try_summoners()
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
		if mode != "fight" or t != focus:
			_chase_since = m.time
		mode = "fight"
		focus = t
		_fight(t)
		return
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
static func power_of(u) -> float:
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


func _minions_tanking(tu: Unit) -> bool:
	for mn in ally_minions:
		if G.flat_dist(mn.global_position, tu.global_position) < tu.attack_range_m() + 0.5:
			return true
	return false


## Rough damage we can deal in a short trade (for kill decisions).
func _burst() -> float:
	var d: float = c.stats.ad * 2.5 + c.stats.ap * 1.2 + c.level * 40.0
	for ab in c.abilities:
		if ab != null and ab.level > 0 and ab.is_ready():
			d += 60.0 + 30.0 * ab.level + c.stats.ap * 0.4
	return d


func _should_retreat() -> bool:
	var hp := c.hp_ratio()
	if _turret_targeting_me() and (not _minions_tanking(enemy_turret) or hp < 0.6):
		return true
	if enemies.is_empty():
		return hp < 0.15 and _nearest_relic() == null
	var p := c.global_position
	var near_allies := allies.filter(func(a): return G.flat_dist(a.global_position, p) < 11.0)
	var near_enemies := enemies.filter(func(e): return G.flat_dist(e.global_position, p) < 12.0)
	var ally_p := team_power(near_allies, true)
	var enemy_p := team_power(near_enemies, false)
	# finishing a kill is worth staying for
	if focus != null and is_instance_valid(focus) and not focus.dead and focus.hp < _burst() * 0.8 and hp > 0.12 \
			and c.in_attack_range(focus, 1.5):
		return false
	var threshold := retreat_hp * (0.75 if frontline else 1.1) * (1.2 - aggression * 0.4)
	if hp < threshold and (enemy_p > ally_p * 0.55 or hp < 0.1):
		return true
	# outnumbered and alone
	if near_allies.is_empty() and near_enemies.size() >= 2 and enemy_p > ally_p * 1.3:
		return true
	# the team is falling back and the fight here is not winnable
	if team_ai.stance == "retreat" and not near_enemies.is_empty() and enemy_p > ally_p * 0.9:
		return true
	return false


func _pick_fight_target() -> Unit:
	if enemies.is_empty():
		return null
	var p := c.global_position
	var st := team_ai.stance
	var reach := c.attack_range_m() + c.radius
	var engage := reach + 1.0
	match st:
		"engage":
			engage = reach + (6.5 if frontline else 3.5) + aggression * 3.0
		"hold":
			engage = reach + (3.0 if frontline else 1.5) + aggression * 1.5
		"retreat":
			engage = reach + 0.5
	var burst := _burst()
	var best: Unit = null
	var best_s := -INF
	for e in enemies:
		var d := G.flat_dist(p, e.global_position)
		var killable: bool = e.hp < burst and d < reach + 4.0
		var attacking_me: bool = c.damage_log.has(e) and m.time - float(c.damage_log[e]) < 2.0
		if d > engage and not killable and not (attacking_me and d < reach + 2.0):
			continue
		# don't dive under their turret unless it's a sure thing
		if _under_enemy_turret(e.global_position) and not (killable and c.hp_ratio() > 0.5) \
				and not (st == "engage" and e.hp_ratio() < 0.3 and enemy_turret != null and _minions_tanking(enemy_turret)):
			continue
		var s := -d * 0.15
		s += (1.0 - e.hp_ratio()) * 3.0
		s += 4.0 if killable else 0.0
		s += 1.5 if (e.cc & Buff.IMMOBILIZE) != 0 else 0.0
		s += 2.0 if e == team_ai.focus else 0.0
		s += 1.0 if e == focus else 0.0
		s += 0.6 if e.stats.attack_range > 300.0 else 0.0
		s += 1.0 if attacking_me else 0.0
		if s > best_s:
			best_s = s
			best = e
	# melee: give up long chases of something we can't catch
	if best != null and best == focus and not is_ranged and _chase_since > 0.0 and m.time - _chase_since > 3.0 \
			and G.flat_dist(p, best.global_position) > reach + 2.5 and best.stats.move_speed >= c.stats.move_speed and best.hp_ratio() > 0.25:
		_chase_since = m.time + 2.0   # cool off
		return null
	return best


func _under_enemy_turret(pos: Vector3) -> bool:
	for s in m.structures:
		if s.team != c.team and s.kind == G.Kind.TURRET and not s.dead:
			if G.flat_dist(pos, s.global_position) < s.attack_range_m() + s.radius:
				return true
	return false


# ===================================================================== actions
func _move(goal: Vector3, force: bool = false) -> void:
	if not force and _move_timer > 0.0 and _move_goal != Vector3.INF and G.flat_dist(goal, _move_goal) < 1.0:
		return
	if not m.nav.is_walkable(goal):
		goal = m.nav.nearest_walkable(goal)
	_move_goal = goal
	_move_timer = 0.3
	c.issue_move(goal)


func _attack(u: Unit) -> void:
	if c.attack_target != u or c.cmd != Unit.Cmd.ATTACK:
		c.issue_attack(u)


func _retreat() -> void:
	var goal := team_ai.safe_point
	var relic = _nearest_relic()
	if relic != null and G.flat_dist(relic.global_position, c.global_position) < G.flat_dist(goal, c.global_position) * 0.7:
		goal = relic.global_position
	# never retreat past our own fountain line
	if G.flat_dist(c.global_position, c.spawn_point) < G.flat_dist(goal, c.spawn_point):
		goal = c.spawn_point
	_move(goal)


func _nearest_relic():
	var best = null
	var bd := 22.0
	for r in m.relics:
		if r.active:
			var d := G.flat_dist(r.global_position, c.global_position)
			if d < bd and not _under_enemy_turret(r.global_position):
				bd = d
				best = r
	return best


func _fight(t: Unit) -> void:
	var p := c.global_position
	if not is_ranged:
		_attack(t)
		return
	# ranged: orb-walk at max range — attack when ready, otherwise keep spacing and strafe
	var in_range := c.in_attack_range(t)
	if c.windup_timer >= 0.0:
		return
	if not in_range or c.attack_timer <= 0.05:
		_attack(t)
		return
	var threat: Unit = null
	var td := INF
	for e in enemies:
		var d := G.flat_dist(e.global_position, p)
		var their_reach: float = e.attack_range_m() + e.radius + c.radius
		if d < their_reach + 1.2 and d < td:
			td = d
			threat = e
	var want := c.attack_range_m() + c.radius + t.radius - 0.5
	var away := G.flat_dir(t.global_position, p)
	var side := Vector3(-away.z, 0, away.x)
	_strafe_t -= reaction
	if _strafe_t <= 0.0:
		_strafe_t = G.rng.randf_range(0.5, 1.1)
		_strafe_dir = -_strafe_dir
	var goal := p
	if threat != null and td < want - 0.5:
		goal = p + G.flat_dir(threat.global_position, p) * 2.5 + side * _strafe_dir * 0.8
	else:
		var dist := G.flat_dist(t.global_position, p)
		goal = p + away * clampf(want - dist, -1.5, 1.5) + side * _strafe_dir * 1.2
	if _under_enemy_turret(goal) and not _under_enemy_turret(p):
		goal = p - team_ai.lane_dir * 1.5
	_move(goal, true)


func _lane() -> void:
	var p := c.global_position
	var ta := team_ai
	var lane_dir := ta.lane_dir
	# health relic when hurt and it's on our side of the fight
	if c.hp_ratio() < 0.6:
		var relic = _nearest_relic()
		if relic != null and ta.lane_coord(relic.global_position) < ta.lane_coord(ta.contact) + 3.0:
			_move(relic.global_position)
			return
	var threat_close := false
	for e in enemies:
		if G.flat_dist(e.global_position, p) < e.attack_range_m() + e.radius + c.radius + 1.0:
			threat_close = true
			break
	# farm: last hits first, then push the wave if it's safe
	if not enemy_minions.is_empty() and ta.stance != "retreat":
		var best: Unit = null
		var best_s := INF
		var ad := c.stats.ad
		for e in enemy_minions:
			if _under_enemy_turret(e.global_position) and (enemy_turret == null or not _minions_tanking(enemy_turret) or _turret_targeting_me()):
				continue
			var d := G.flat_dist(p, e.global_position)
			if d > c.attack_range_m() + 6.0:
				continue
			# while enemy champions are close, only farm what's already in range
			if threat_close and not c.in_attack_range(e):
				continue
			var dmg: float = ad * Combat.resist_multiplier(e.stats.armor, c, true)
			var s: float = e.hp + d * 15.0
			if e.hp <= dmg * 1.05:
				s -= 1000.0
			if s < best_s:
				best_s = s
				best = e
		if best != null:
			_attack(best)
			return
	# siege the turret while our minions tank it
	if enemy_turret != null and not enemy_turret.is_invulnerable() and _minions_tanking(enemy_turret) and enemy_turret.attack_target != c \
			and ta.stance != "retreat":
		_attack(enemy_turret)
		return
	# hit exposed inhibitor / nexus
	for s in m.structures:
		if s.team != c.team and (s.kind == G.Kind.INHIBITOR or s.kind == G.Kind.NEXUS) and not s.dead and not s.is_invulnerable():
			if G.flat_dist(p, s.global_position) < 12.0 and (enemy_turret == null or _minions_tanking(enemy_turret)):
				_attack(s)
				return
	# position relative to our wave front
	var goal: Vector3
	if ta.stance == "retreat":
		goal = ta.safe_point
	else:
		var back := (1.5 if frontline else 4.5)
		if ta.stance == "hold" and not ta.enemies.is_empty():
			back += 1.0 if frontline else 2.0
		var k := minf(ta.front, ta.enemy_front + (1.0 if frontline else -2.0)) - back
		goal = ta.lane_point(k)
	var side := Vector3(-lane_dir.z, 0, lane_dir.x)
	goal += side * personal_offset
	if _under_enemy_turret(goal) and (enemy_turret == null or not _minions_tanking(enemy_turret)):
		goal -= lane_dir * 4.0
	if G.flat_dist(p, goal) > 1.5:
		_move(goal)


# ===================================================================== dodging
func _try_dodge() -> bool:
	if dodge_chance <= 0.0 or m.missiles.is_empty() or c.dead:
		return false
	if not c.casting.is_empty() or not c.channel.is_empty() or not c.dash.is_empty() or (c.cc & Buff.BLOCK_MOVE) != 0:
		return false
	var p := c.global_position
	for mi_v in m.missiles:
		if not is_instance_valid(mi_v):
			continue
		var mi: Missile = mi_v
		if not mi.alive or mi.team == c.team or mi.is_attack:
			continue
		if mi.mode != Missile.Mode.LINEAR or not mi.collides or not mi.hits_champions:
			continue
		if mi.age < reaction:
			continue
		var to := Vector3(p.x - mi.global_position.x, 0, p.z - mi.global_position.z)
		var along := to.dot(mi.dir)
		if along < -0.5 or along > maxf(mi.speed, 1.0) * 0.9 + 1.0 or along > mi.max_dist - mi.traveled + c.radius:
			continue
		var perp_v := to - mi.dir * along
		var perp := perp_v.length()
		var clear: float = mi.width + c.radius + 0.35
		if perp > clear:
			continue
		if _dodged.has(mi):
			continue
		_dodged[mi] = true
		if _dodged.size() > 64:
			_dodged.clear()
		if G.rng.randf() > dodge_chance:
			continue
		var side: Vector3 = Vector3(-mi.dir.z, 0, mi.dir.x)
		if perp_v.dot(side) < 0.0:
			side = -side
		var goal := p + side * (clear - perp + 0.5)
		if not m.nav.is_walkable(goal):
			goal = p - side * (clear + perp + 0.5)
			if not m.nav.is_walkable(goal):
				continue
		c.issue_move(goal)
		_dodge_until = m.time + (clear + 0.5) / maxf(c.stats.move_speed * G.U, 1.0) + 0.05
		return true
	return false


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
## Returns Vector3.INF when fewer than min_count enemies can be hit.
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
				and (tgt.hp_ratio() < 0.5 or (frontline and team_ai.stance == "engage")) and c.hp_ratio() > 0.45 \
				and not _under_enemy_turret(tgt.global_position):
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
