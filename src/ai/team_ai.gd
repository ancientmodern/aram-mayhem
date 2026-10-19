class_name TeamAI
extends RefCounted
## Shared tactical picture for one team's bots: where the lane fight is, who is stronger,
## whether to engage / hold / fall back, and which enemy to focus. Refreshed a few times a second.

var team := 0
var m = null
var updated_at := -100.0
var lane_dir := Vector3.FORWARD     ## from our nexus toward theirs
var my_nexus := Vector3.ZERO
var enemy_nexus := Vector3.ZERO
var front := 0.0                    ## lane coordinate of our frontmost minion (or turret)
var enemy_front := 0.0
var contact := Vector3.ZERO         ## where the two sides meet
var allies: Array = []              ## alive allied champions
var enemies: Array = []             ## alive, visible enemy champions
var alive := 0
var enemy_alive := 0
var strength := 0.0                 ## near the contact point
var enemy_strength := 0.0
var stance := "hold"                ## "engage", "hold", "retreat"
var focus: Unit = null
var safe_point := Vector3.ZERO      ## where to regroup when retreating (our first standing turret)
var _noise_by_bot := {}             ## [bot-diff] BotBrain instance id -> judge_noise (the team misreads fights by the average)
var _team_judge := 0.0


func setup(p_team: int, p_match) -> void:
	team = p_team
	m = p_match


func set_bot_noise(bot_id: int, v: float) -> void:
	_noise_by_bot[bot_id] = v


func lane_coord(p: Vector3) -> float:
	return (p - my_nexus).dot(lane_dir)


func lane_point(coord: float) -> Vector3:
	return my_nexus + lane_dir * coord


func refresh() -> void:
	if m.time - updated_at < 0.35:
		return
	updated_at = m.time
	my_nexus = m.nexus_units[team].global_position
	enemy_nexus = m.nexus_units[1 - team].global_position
	lane_dir = G.flat_dir(my_nexus, enemy_nexus)
	var lane_len := G.flat_dist(my_nexus, enemy_nexus)
	# fronts
	front = -INF
	enemy_front = INF
	for u in m.units:
		if u.kind != G.Kind.MINION or u.dead:
			continue
		var k := lane_coord(u.global_position)
		if u.team == team:
			front = maxf(front, k)
		else:
			enemy_front = minf(enemy_front, k)
	var my_turret = _first_turret(team)
	var their_turret = _first_turret(1 - team)
	safe_point = my_turret.global_position - lane_dir * 2.0 if my_turret != null else my_nexus
	if front == -INF:
		front = lane_coord(my_turret.global_position) + 3.0 if my_turret != null else 8.0
	if enemy_front == INF:
		enemy_front = lane_coord(their_turret.global_position) - 3.0 if their_turret != null else lane_len - 8.0
	var mid := clampf((front + enemy_front) * 0.5, 0.0, lane_len)
	contact = lane_point(mid)
	# champions and strength around the contact point
	allies = m.champions_of(team, true)
	enemies = []
	for e in m.champions_of(1 - team, true):
		if e.is_targetable_by(team) or e.visible_to[team]:
			enemies.append(e)
	alive = allies.size()
	enemy_alive = m.champions_of(1 - team, true).size()
	# strength: everyone alive counts, those far from the fight count less (they can still arrive)
	strength = 0.0
	enemy_strength = 0.0
	for a in allies:
		strength += BotBrain.power_of(a) * _presence(a, mid)
	for e in m.champions_of(1 - team, true):
		enemy_strength += BotBrain.power_of(e) * _presence(e, mid)
	# stance with hysteresis so the team doesn't flip-flop every refresh
	var ratio := strength / maxf(enemy_strength, 1.0)
	if not _noise_by_bot.is_empty():   # [bot-diff] weaker teams misjudge who is stronger (slowly drifting error)
		var jn := 0.0
		for v in _noise_by_bot.values():
			jn += v
		jn /= _noise_by_bot.size()
		_team_judge = lerpf(_team_judge, G.rng.randf_range(-1.0, 1.0), 0.3)
		ratio *= 1.0 + jn * _team_judge
	var down := enemy_alive - alive
	match stance:
		"engage":
			if ratio < 1.05 or down >= 1:
				stance = "hold"
		"retreat":
			if ratio > 0.85 and down <= 1:
				stance = "hold"
		_:
			if down >= 2 or ratio < 0.6:
				stance = "retreat"
			elif ratio > 1.25 and down <= 0:
				stance = "engage"
	# focus target: squishy / low / disabled enemies near the fight
	var prev_focus = focus
	focus = null
	var best := -INF
	for e in enemies:
		var d := G.flat_dist(e.global_position, contact)
		if d > 18.0:
			continue
		var ehp: float = e.hp * (1.0 + (e.stats.armor + e.stats.mr) * 0.004) + e.total_shield()
		var s := -ehp / 400.0 - d * 0.1
		s += 2.0 if (e.cc & Buff.IMMOBILIZE) != 0 else 0.0
		s += 1.0 if e.stats.attack_range > 300.0 else 0.0
		s += 0.8 if prev_focus == e else 0.0
		if s > best:
			best = s
			focus = e


func _presence(u, mid: float) -> float:
	var d := absf(lane_coord(u.global_position) - mid)
	return clampf(1.3 - d / 40.0, 0.35, 1.0)


func _first_turret(t: int) -> Unit:
	for tu in [m.outer_turrets[t], m.inhib_turrets[t]]:
		if tu != null and not tu.dead:
			return tu
	for s in m.structures:
		if s.team == t and s.kind == G.Kind.TURRET and not s.dead and s.tier == Turret.Tier.NEXUS:
			return s
	return null
