class_name WaveSpawner
extends RefCounted
## Spawns minion waves from both barracks.

var m = null
var next_wave := Rules.FIRST_WAVE_TIME
var wave_index := 0
var barracks := [Vector3.ZERO, Vector3.ZERO]
var lanes := [[], []]         ## per team waypoints toward enemy base
var queue: Array = []         ## [[time, team, type]]
var inhibitors := [null, null]


func _init(p_match) -> void:
	m = p_match


func setup(order_barracks: Vector3, chaos_barracks: Vector3, lane_order_to_chaos: Array, nexus: Array) -> void:
	barracks = [order_barracks, chaos_barracks]
	var l0: Array = lane_order_to_chaos.duplicate()
	# trim waypoints behind the barracks
	while l0.size() > 1 and G.flat_dist(l0[0], nexus[1]) > G.flat_dist(order_barracks, nexus[1]):
		l0.pop_front()
	l0.append(nexus[1])
	var l1: Array = lane_order_to_chaos.duplicate()
	l1.reverse()
	while l1.size() > 1 and G.flat_dist(l1[0], nexus[0]) > G.flat_dist(chaos_barracks, nexus[0]):
		l1.pop_front()
	l1.append(nexus[0])
	lanes = [l0, l1]


func tick(_dt: float) -> void:
	var t: float = m.time
	if t >= next_wave:
		_spawn_wave()
		next_wave += wave_interval(next_wave)
	while not queue.is_empty() and queue[0][0] <= t:
		var q = queue.pop_front()
		_spawn_minion(q[1], q[2])


func _spawn_wave() -> void:
	wave_index += 1
	var t: float = m.time
	var siege := false
	if t < 645.0:
		siege = wave_index % 3 == 0
	elif t < 1500.0:
		siege = wave_index % 2 == 0
	else:
		siege = true
	for team in 2:
		var order: Array = []
		var enemy_inhib = inhibitors[1 - team]
		# [numbers] wiki Inhibitor (HA): one super minion per wave while the inhibitor is down, but not for the last two waves
		# before it respawns
		if enemy_inhib != null and is_instance_valid(enemy_inhib) and enemy_inhib.dead 				and enemy_inhib.respawn_at - t > Rules.SUPER_STOP_WAVES_BEFORE_RESPAWN * wave_interval(t):
			order.append(Minion.Type.SUPER)
		order += [Minion.Type.MELEE, Minion.Type.MELEE, Minion.Type.MELEE]
		if siege:
			order.append(Minion.Type.SIEGE)
		order += [Minion.Type.CASTER, Minion.Type.CASTER, Minion.Type.CASTER]
		for i in order.size():
			queue.append([t + i * Rules.WAVE_SPAWN_GAP, team, order[i]])
	queue.sort_custom(func(a, b): return a[0] < b[0])


func _spawn_minion(team: int, type: int) -> void:
	var t: float = m.time
	var upgrades := int(maxf(0.0, t - Rules.FIRST_WAVE_TIME) / Rules.MINION_UPGRADE_INTERVAL)
	var ms := 325.0
	if t >= Rules.MINION_MS_START:
		ms += mini(Rules.MINION_MS_STEPS, int((t - Rules.MINION_MS_START) / Rules.MINION_MS_INTERVAL) + 1) * Rules.MINION_MS_STEP   # [numbers]
	var mn := Minion.new()
	mn.setup(team, type, upgrades, lanes[team], ms)
	var jitter := Vector3(G.rng.randf_range(-0.6, 0.6), 0, G.rng.randf_range(-0.6, 0.6))
	m.add_unit(mn, barracks[team] + jitter)
	mn.facing = G.flat_dir(barracks[team], lanes[team][0] if not lanes[team].is_empty() else barracks[team])


## League ARAM wave cadence: 25 s early, shortening with game time to 13 s late.
static func wave_interval(t: float) -> float:
	if Rules.MAYHEM_MODE:
		return Rules.WAVE_INTERVAL
	var k := clampf((t - 600.0) / 720.0, 0.0, 1.0)
	return lerpf(Rules.WAVE_INTERVAL, Rules.WAVE_INTERVAL_LATE, k)
