class_name Missile
extends Node3D
## Projectile: linear skillshot, homing (targeted) or arcing to a point.
## Collision is a swept circle against enemy units on the XZ plane.

enum Mode { LINEAR, HOMING, ARC, FOLLOW }

var source = null             ## owner Unit
var team := 0
var ability = null
var mode := Mode.LINEAR
var speed := 15.0             ## m/s
var accel := 0.0
var max_speed := 1000.0
var min_speed := 0.0
var dir := Vector3.FORWARD
var start := Vector3.ZERO
var max_dist := 10.0          ## for LINEAR (m)
var traveled := 0.0
var width := 0.5              ## collision radius (m)
var height := 1.0             ## visual height above ground (m)
var target = null             ## homing target Unit
var target_pos := Vector3.ZERO
var arc_height := 3.0
var pierce := false
var max_hits := 1
var hit_count := 0
var hit_units := {}
var hits_champions := true
var hits_minions := true
var hits_summons := true
var hits_allies := false
var hit_structures := false
var collides := true          ## false = only on_end (e.g. arc to point)
var stop_on_champion := false ## pierce minions, stop on first champion
var on_hit := Callable()      ## (missile, unit) -> void
var on_end := Callable()      ## (missile, pos) -> void
var on_move := Callable()     ## (missile, dt) -> void
var lifetime := 8.0
var age := 0.0
var alive := true
var visual: Node3D = null
var end_fade := 0.12
var is_attack := false
var face_dir := true
var custom: Dictionary = {}   ## free storage for kits
var blockable := true         ## destroyed by enemy projectile walls


func _ready() -> void:
	if visual != null and visual.get_parent() == null:
		add_child(visual)


func setup_linear(src, from: Vector3, direction: Vector3, spd: float, dist: float, w: float) -> Missile:
	source = src
	team = src.team
	mode = Mode.LINEAR
	start = from
	dir = Vector3(direction.x, 0.0, direction.z).normalized()
	speed = spd
	max_dist = dist
	width = w
	return self


func setup_homing(src, from: Vector3, tgt, spd: float) -> Missile:
	source = src
	team = src.team
	mode = Mode.HOMING
	start = from
	target = tgt
	speed = spd
	collides = false
	return self


func setup_arc(src, from: Vector3, to: Vector3, flight_time: float, arc: float = 3.0) -> Missile:
	source = src
	team = src.team
	mode = Mode.ARC
	start = from
	target_pos = to
	speed = G.flat_dist(from, to) / maxf(flight_time, 0.05)
	arc_height = arc
	collides = false
	return self


func tick(dt: float, m) -> void:
	if not alive:
		return
	age += dt
	if age > lifetime:
		finish(global_position)
		return
	speed = clampf(speed + accel * dt, min_speed, max_speed)
	var prev := global_position
	var gp := Vector3(prev.x, 0.0, prev.z)
	match mode:
		Mode.LINEAR:
			var step := speed * dt
			if traveled + step >= max_dist:
				step = max_dist - traveled
			gp += dir * step
			traveled += step
			_place(m, gp, height)
			if collides:
				_collide(m, prev, global_position)
			if alive and traveled >= max_dist - 0.0001:
				finish(global_position)
		Mode.HOMING, Mode.FOLLOW:
			if target == null or not is_instance_valid(target) or (target.dead and mode == Mode.HOMING):
				if mode == Mode.HOMING and is_attack:
					finish(global_position)
					return
				if target != null and is_instance_valid(target):
					target_pos = target.global_position
				mode = Mode.ARC if mode == Mode.HOMING else mode
				finish(global_position)
				return
			var tp: Vector3 = target.global_position
			var to := Vector3(tp.x - gp.x, 0.0, tp.z - gp.z)
			var d := to.length()
			var step2 := speed * dt
			if d <= step2 + target.radius * 0.3:
				_place(m, Vector3(tp.x, 0.0, tp.z), height)
				if collides:
					_collide(m, prev, global_position)
				if alive:
					if on_hit.is_valid() and (not hit_units.has(target)):
						hit_units[target] = true
						on_hit.call(self, target)
					finish(global_position)
				return
			dir = to / d
			gp += dir * step2
			traveled += step2
			_place(m, gp, height)
			if collides:
				_collide(m, prev, global_position)
		Mode.ARC:
			var total := G.flat_dist(start, target_pos)
			var step3 := speed * dt
			traveled = minf(traveled + step3, total)
			var k := traveled / maxf(total, 0.001)
			var p := start.lerp(target_pos, k)
			dir = G.flat_dir(start, target_pos)
			_place(m, Vector3(p.x, 0.0, p.z), height + arc_height * 4.0 * k * (1.0 - k))
			if k >= 1.0:
				finish(Vector3(target_pos.x, global_position.y, target_pos.z))
	if blockable and alive and m != null and not m.blockers.is_empty() and m.projectile_blocked(team, prev, global_position):
		alive = true
		if visual != null and is_instance_valid(visual):
			Vfx.hit_spark(m, global_position, Color(0.8, 0.95, 1.0), 0.7)
		on_end = Callable()
		finish(global_position)
		return
	if on_move.is_valid() and alive:
		on_move.call(self, dt)


func _place(m, gp: Vector3, h: float) -> void:
	var y := 0.0
	if m != null and m.nav != null:
		y = m.nav.height_at(gp)
	global_position = Vector3(gp.x, y + h, gp.z)
	if face_dir and dir.length_squared() > 0.001:
		look_at(global_position + dir, Vector3.UP)


func _collide(m, a: Vector3, b: Vector3) -> void:
	if m == null:
		return
	var mid := (a + b) * 0.5
	var seg_len := G.flat_dist(a, b)
	var cands: Array = m.units_in_radius(mid, seg_len * 0.5 + width + 2.0, -1)
	var best_t := INF
	var order := []
	for u in cands:
		if hit_units.has(u) or u.dead:
			continue
		if u == source:
			continue
		if not hits_allies and u.team == team:
			continue
		if hits_allies and u.team != team and not _hits_enemy_kind(u):
			continue
		if not _hits_enemy_kind(u) and u.team != team:
			continue
		if u.team != team and not u.is_targetable_by(team):
			continue
		var d := NavGrid._dist_to_segment(u.global_position, a, b)
		if d <= width + u.radius:
			var t := Vector2(u.global_position.x - a.x, u.global_position.z - a.z).length()
			order.append([t, u])
	order.sort_custom(func(x, y): return x[0] < y[0])
	for pair in order:
		if not alive:
			break
		var u = pair[1]
		hit_units[u] = true
		hit_count += 1
		if on_hit.is_valid():
			on_hit.call(self, u)
		if stop_on_champion and u.kind == G.Kind.CHAMPION:
			finish(u.global_position)
			return
		if not pierce and hit_count >= max_hits:
			finish(u.global_position)
			return


func _hits_enemy_kind(u) -> bool:
	match u.kind:
		G.Kind.CHAMPION:
			return hits_champions
		G.Kind.MINION:
			return hits_minions
		G.Kind.SUMMON:
			return hits_summons
		G.Kind.TURRET, G.Kind.INHIBITOR, G.Kind.NEXUS:
			return hit_structures
	return false


func finish(pos: Vector3) -> void:
	if not alive:
		return
	alive = false
	if on_end.is_valid():
		on_end.call(self, pos)
	if visual != null and is_instance_valid(visual) and visual.has_method("detach_and_fade"):
		visual.detach_and_fade()
	queue_free()
