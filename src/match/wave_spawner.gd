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
		next_wave += Rules.WAVE_INTERVAL
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
		if enemy_inhib != null and is_instance_valid(enemy_inhib) and enemy_inhib.dead:
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
	if t > Rules.MINION_MS_START:
		ms += mini(12, int((t - Rules.MINION_MS_START) / 60.0) + 1) * 10.0
	var mn := Minion.new()
	mn.setup(team, type, upgrades, lanes[team], ms)
	var jitter := Vector3(G.rng.randf_range(-0.6, 0.6), 0, G.rng.randf_range(-0.6, 0.6))
	m.add_unit(mn, barracks[team] + jitter)
	mn.facing = G.flat_dir(barracks[team], lanes[team][0] if not lanes[team].is_empty() else barracks[team])
