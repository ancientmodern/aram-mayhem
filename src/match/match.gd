class_name Match
extends Node3D
## Owns and drives a single game on the Howling Abyss.

const GRID_CELL := 4.0
var _grid_min := Vector2i.ZERO
var _grid_max := Vector2i.ZERO

var time := 0.0
var paused := false
var over := false
var winner := -1
var nav: NavGrid = null
var layout := {}
var units: Array = []
var champions: Array = []
var missiles: Array = []
var structures: Array = []
var _uid := 0
var _grid := {}
var _timers: Array = []         ## [[time, Callable]]
var spawner = null
var relics: Array = []
var player_controller = null
var camera_rig = null
var hud = null
var overlay = null
var world_root: Node3D
var units_root: Node3D
var fx_root: Node3D
var missiles_root: Node3D
var kills := [0, 0]
var first_blood := false
var multikill := {}             ## champion -> [count, last_time]
var killing_spree := {}         ## champion -> streak
var fountain := [Vector3.ZERO, Vector3.ZERO]
var spawn_points := [Vector3.ZERO, Vector3.ZERO]
var lane_path: Array = []       ## order -> chaos lane waypoints (world)
var augment_levels := [1, 7, 11, 15]
var vision_timer := 0.0
var events: Array = []          ## kill feed entries
var game_speed := 1.0
var trace_from := INF          ## debug: print per-frame phases after this time
var tickers: Array = []         ## [{fn: Callable(dt) -> bool, until: float}] per-frame callbacks
var blockers: Array = []        ## projectile walls [{team, a: Vector3, b: Vector3, until: float}]


func _ready() -> void:
	G.match = self
	world_root = Node3D.new()
	world_root.name = "World"
	add_child(world_root)
	units_root = Node3D.new()
	units_root.name = "Units"
	add_child(units_root)
	missiles_root = Node3D.new()
	missiles_root.name = "Missiles"
	add_child(missiles_root)
	fx_root = Node3D.new()
	fx_root.name = "FX"
	add_child(fx_root)


# ===================================================================== loop
func _process(delta: float) -> void:
	if paused:
		return
	G.beat += 1
	var dt := minf(delta, 0.05) * game_speed
	time += dt
	G.ctx = "timers"
	_run_timers()
	G.ctx = "grid"
	_rebuild_grid()
	for u in units.duplicate():
		if is_instance_valid(u):
			G.ctx_unit = u.display_name
			u.tick(dt)
	G.ctx = "collide"
	_resolve_collisions(dt)
	G.ctx = "missiles"
	for mi in missiles.duplicate():
		if is_instance_valid(mi) and mi.alive:
			mi.tick(dt, self)
	G.ctx = "rest"
	missiles = missiles.filter(func(x): return is_instance_valid(x) and x.alive)
	if not tickers.is_empty():
		var keep := []
		for tk in tickers:
			if time <= tk.until and tk.fn.is_valid():
				var r = tk.fn.call(dt)
				if r != false:
					keep.append(tk)
		tickers = keep
	if not blockers.is_empty():
		blockers = blockers.filter(func(b): return time <= b.until)
	if spawner != null:
		spawner.tick(dt)
	for r in relics:
		r.tick(dt)
	vision_timer -= dt
	if vision_timer <= 0.0:
		vision_timer = 0.1
		_update_vision()


func after(seconds: float, fn: Callable) -> void:
	_timers.append([time + seconds, fn])


## Call fn(dt) every frame for `duration` seconds (return false from fn to stop early).
func add_ticker(duration: float, fn: Callable) -> void:
	tickers.append({"fn": fn, "until": time + duration})


## Add a wall that destroys enemy projectiles crossing segment a-b (e.g. Wind Wall).
func add_blocker(team: int, a: Vector3, b: Vector3, duration: float) -> Dictionary:
	var bl := {"team": team, "a": a, "b": b, "until": time + duration}
	blockers.append(bl)
	return bl


func projectile_blocked(team: int, p0: Vector3, p1: Vector3) -> bool:
	for b in blockers:
		if b.team == team:
			continue
		if Geometry2D.segment_intersects_segment(Vector2(p0.x, p0.z), Vector2(p1.x, p1.z), Vector2(b.a.x, b.a.z), Vector2(b.b.x, b.b.z)) != null:
			return true
	return false


func _run_timers() -> void:
	if _timers.is_empty():
		return
	var due := []
	var keep := []
	for t in _timers:
		if t[0] <= time:
			due.append(t)
		else:
			keep.append(t)
	_timers = keep
	for t in due:
		if t[1].is_valid():
			t[1].call()


# ===================================================================== registry
func add_unit(u: Unit, pos: Vector3) -> Unit:
	_uid += 1
	u.uid = _uid
	u.match_ref = self
	units_root.add_child(u)
	u.set_ground_pos(pos)
	units.append(u)
	if u.kind == G.Kind.CHAMPION:
		champions.append(u)
	if u.kind in [G.Kind.TURRET, G.Kind.INHIBITOR, G.Kind.NEXUS]:
		structures.append(u)
	G.unit_spawned.emit(u)
	return u


func remove_unit(u: Unit) -> void:
	units.erase(u)
	champions.erase(u)
	structures.erase(u)
	if is_instance_valid(u):
		u.queue_free()


func add_missile(mi: Missile, pos: Vector3) -> Missile:
	missiles_root.add_child(mi)
	mi.global_position = pos
	missiles.append(mi)
	return mi


func add_fx(n: Node3D, pos: Vector3 = Vector3.INF) -> Node3D:
	fx_root.add_child(n)
	if pos != Vector3.INF:
		n.global_position = pos
	return n


# ===================================================================== spatial queries
func _rebuild_grid() -> void:
	_grid.clear()
	_grid_min = Vector2i(1 << 30, 1 << 30)
	_grid_max = Vector2i(-(1 << 30), -(1 << 30))
	for u in units:
		if u.dead:
			continue
		var p: Vector3 = u.global_position
		var key := Vector2i(int(floor(p.x / GRID_CELL)), int(floor(p.z / GRID_CELL)))
		_grid_min = Vector2i(mini(_grid_min.x, key.x), mini(_grid_min.y, key.y))
		_grid_max = Vector2i(maxi(_grid_max.x, key.x), maxi(_grid_max.y, key.y))
		if _grid.has(key):
			_grid[key].append(u)
		else:
			_grid[key] = [u]


## Units (alive) whose center is within r (+ their radius) of center. team_filter -1 = all.
func units_in_radius(center: Vector3, r: float, team_filter: int = -1) -> Array:
	var out := []
	if not center.is_finite() or not is_finite(r) or r < 0.0:
		return out
	r = minf(r, 400.0)
	# clamp the scanned cells to the occupied grid bounds (huge radii stay cheap)
	var c0 := Vector2i(maxi(int(floor((center.x - r - 4.0) / GRID_CELL)), _grid_min.x), maxi(int(floor((center.z - r - 4.0) / GRID_CELL)), _grid_min.y))
	var c1 := Vector2i(mini(int(floor((center.x + r + 4.0) / GRID_CELL)), _grid_max.x), mini(int(floor((center.z + r + 4.0) / GRID_CELL)), _grid_max.y))
	for j in range(c0.y, c1.y + 1):
		for i in range(c0.x, c1.x + 1):
			var cell = _grid.get(Vector2i(i, j))
			if cell == null:
				continue
			for u in cell:
				if team_filter >= 0 and u.team != team_filter:
					continue
				if u.dead:
					continue
				var dx: float = u.global_position.x - center.x
				var dz: float = u.global_position.z - center.z
				var rr: float = r + u.radius
				if dx * dx + dz * dz <= rr * rr:
					out.append(u)
	return out


func enemies_in_radius(team: int, center: Vector3, r: float, champs_only: bool = false, include_structures: bool = false) -> Array:
	var out := []
	for u in units_in_radius(center, r, G.enemy_team(team)):
		if not u.is_targetable_by(team):
			continue
		if champs_only and u.kind != G.Kind.CHAMPION:
			continue
		if not include_structures and u.kind in [G.Kind.TURRET, G.Kind.INHIBITOR, G.Kind.NEXUS]:
			continue
		out.append(u)
	return out


func allies_in_radius(team: int, center: Vector3, r: float, champs_only: bool = true) -> Array:
	var out := []
	for u in units_in_radius(center, r, team):
		if champs_only and u.kind != G.Kind.CHAMPION:
			continue
		if u.kind in [G.Kind.TURRET, G.Kind.INHIBITOR, G.Kind.NEXUS]:
			continue
		out.append(u)
	return out


## Units hit by a rectangle from `a` toward `b` with half-width hw.
func units_in_line(team: int, a: Vector3, b: Vector3, hw: float, champs_only: bool = false) -> Array:
	var out := []
	var mid := (a + b) * 0.5
	var r := G.flat_dist(a, b) * 0.5 + hw + 1.0
	for u in enemies_in_radius(team, mid, r, champs_only):
		if NavGrid._dist_to_segment(u.global_position, a, b) <= hw + u.radius:
			out.append(u)
	return out


## Units within a cone (angle in degrees, full width) from origin toward dir.
func units_in_cone(team: int, origin: Vector3, dir: Vector3, length: float, angle_deg: float, champs_only: bool = false) -> Array:
	var out := []
	var half := deg_to_rad(angle_deg * 0.5)
	for u in enemies_in_radius(team, origin, length, champs_only):
		var to := G.flat(u.global_position - origin)
		if to.length() < u.radius + 0.3:
			out.append(u)
			continue
		var ang := G.flat(dir).normalized().angle_to(to.normalized())
		var slack := atan2(u.radius, maxf(to.length(), 0.01))
		if ang <= half + slack:
			out.append(u)
	return out


func champions_of(team: int, alive_only: bool = true) -> Array:
	return champions.filter(func(c): return c.team == team and (not alive_only or not c.dead))


# ===================================================================== collisions
func _resolve_collisions(_dt: float) -> void:
	for key in _grid:
		var cell: Array = _grid[key]
		var neighbors := []
		for dj in range(0, 2):
			for di in range(-1, 2):
				if dj == 0 and di < 0:
					continue
				var n = _grid.get(Vector2i(key.x + di, key.y + dj))
				if n != null:
					neighbors.append(n)
		for a in cell:
			if a.mass <= 0.0 or a.dead or not a.dash.is_empty() or (a.cc & Buff.CC.GHOSTED) != 0:
				continue
			for n in neighbors:
				for b in n:
					if b == a or b.dead:
						continue
					if n == cell and b.uid < a.uid and b.mass > 0.0:
						continue
					if not b.dash.is_empty() or (b.cc & Buff.CC.GHOSTED) != 0:
						continue
					_push_pair(a, b)


func _push_pair(a: Unit, b: Unit) -> void:
	var ap := a.global_position
	var bp := b.global_position
	var dx := bp.x - ap.x
	var dz := bp.z - ap.z
	var rr := a.path_radius + b.path_radius
	var d2 := dx * dx + dz * dz
	if d2 >= rr * rr:
		return
	# champions slide past each other and minions more easily (League pathing radius is small)
	var d := sqrt(d2)
	if d < 0.001:
		dx = 0.01 * (1 if a.uid % 2 == 0 else -1)
		dz = 0.01
		d = 0.0141
	var overlap := rr - d
	var nx := dx / d
	var nz := dz / d
	var ma := a.mass if b.mass > 0.0 else 0.0
	var mb := b.mass if a.mass > 0.0 else 0.0
	# moving units yield to stationary attackers (minion waves look nicer)
	var wa := mb / maxf(ma + mb, 0.001) if b.mass > 0.0 else 1.0
	var wb := 1.0 - wa
	if b.mass <= 0.0:
		wa = 1.0
		wb = 0.0
	if a.moving and not b.moving and b.mass > 0.0:
		wa = 0.8
		wb = 0.2
	elif b.moving and not a.moving and b.mass > 0.0:
		wa = 0.2
		wb = 0.8
	var push := overlap * 0.5
	if wa > 0.0:
		var na := Vector3(ap.x - nx * push * wa * 2.0, ap.y, ap.z - nz * push * wa * 2.0)
		if nav == null or nav.is_walkable(na):
			a.set_ground_pos(na)
	if wb > 0.0 and b.mass > 0.0:
		var nb := Vector3(bp.x + nx * push * wb * 2.0, bp.y, bp.z + nz * push * wb * 2.0)
		if nav == null or nav.is_walkable(nb):
			b.set_ground_pos(nb)


# ===================================================================== vision
func _update_vision() -> void:
	# A unit is visible to a team if within sight range of any living unit of that team.
	for u in units:
		if u.dead:
			continue
		for t in 2:
			if u.team == t:
				u.visible_to[t] = true
				continue
			u.visible_to[t] = _seen_by(u, t)


func _seen_by(u: Unit, t: int) -> bool:
	if u.kind in [G.Kind.TURRET, G.Kind.INHIBITOR, G.Kind.NEXUS]:
		return true
	if u.has_method("is_revealed") and u.is_revealed():
		return true
	var ub := u.in_brush
	var stealthed := (u.cc & Buff.CC.CAMOUFLAGE) != 0
	for v in units_in_radius(u.global_position, 13.5, t):
		if v.dead:
			continue
		var sight: float = v.sight_range() if v.has_method("sight_range") else 12.0
		var d := G.flat_dist(v.global_position, u.global_position)
		if d > sight:
			continue
		if stealthed and d > 2.0:
			continue
		if ub > 0 and v.in_brush != ub and d > 1.5:
			continue
		return true
	return false


# ===================================================================== combat helpers
func spawn_attack_missile(src: Unit, tgt: Unit, crit: bool) -> Missile:
	var mi := Missile.new()
	var from := src.global_position + Vector3(0, src.height * 0.55, 0) + src.facing * src.radius
	mi.setup_homing(src, from, tgt, src.attack_missile_speed * G.U)
	mi.is_attack = true
	mi.height = src.height * 0.55
	mi.blockable = src.kind != G.Kind.TURRET
	var vis = null
	if src is Champion and src.kit != null and src.kit.has_method("attack_missile_visual"):
		vis = src.kit.attack_missile_visual(crit)
	mi.visual = vis if vis != null else Vfx.attack_missile(src, crit)
	mi.on_hit = func(_m, u):
		if is_instance_valid(src) and not src.is_queued_for_deletion():
			src.attack_hit(u, crit)
	add_missile(mi, from)
	return mi


# ===================================================================== death / economy
func on_unit_died(u: Unit, killer, info) -> void:
	G.unit_died.emit(u, killer)
	var killer_champ = _owner_champion(killer)
	match u.kind:
		G.Kind.MINION:
			_reward_minion(u, killer_champ)
		G.Kind.CHAMPION:
			_on_champion_killed(u, killer, killer_champ)
		G.Kind.TURRET, G.Kind.INHIBITOR, G.Kind.NEXUS:
			_on_structure_destroyed(u, killer_champ)


func _owner_champion(u):
	if u == null or not is_instance_valid(u):
		return null
	if u.kind == G.Kind.CHAMPION:
		return u
	if u.kind == G.Kind.SUMMON and u.get("summoner") != null and is_instance_valid(u.summoner):
		return u.summoner
	return null


func xp_share_champions(pos: Vector3, team: int, r: float = 16.0) -> Array:
	return champions.filter(func(c): return c.team == team and not c.dead and G.flat_dist(c.global_position, pos) <= r)


func _reward_minion(u: Unit, killer_champ) -> void:
	var team := G.enemy_team(u.team)
	var nearby := xp_share_champions(u.global_position, team)
	if not nearby.is_empty():
		var xp: float = u.xp_value
		# League: shared XP bonus when more champions are near
		var share := xp * (1.0 + 0.0 * (nearby.size() - 1)) / nearby.size()
		share *= [1.0, 1.0, 1.3, 1.35, 1.4, 1.45][mini(nearby.size(), 5)]
		for c in nearby:
			c.gain_xp(share)
	if killer_champ != null and killer_champ.team == team:
		killer_champ.cs += 1
		killer_champ.add_gold(u.gold_value, u)
	elif not nearby.is_empty():
		# ARAM shares gold of minions not last-hit by champions? (no) -> nothing
		pass


func _on_champion_killed(victim: Unit, killer, killer_champ) -> void:
	var team := G.enemy_team(victim.team)
	var assisters := []
	for a in victim.recent_attackers():
		var ac = _owner_champion(a)
		if ac != null and ac.team == team and ac != killer_champ and not (ac in assisters):
			assisters.append(ac)
	victim.deaths += 1
	kills[team] += 1
	var streak_bonus := 0
	var victim_streak: int = killing_spree.get(victim, 0)
	killing_spree[victim] = 0
	var bounty: float = 300.0
	if victim_streak >= 2:
		bounty += mini(victim_streak - 1, 5) * 100.0
	var announce_text := ""
	var announce_sub := ""
	if killer_champ != null:
		killer_champ.kills += 1
		var st: int = killing_spree.get(killer_champ, 0) + 1
		killing_spree[killer_champ] = st
		var mk: Array = multikill.get(killer_champ, [0, -100.0])
		if time - mk[1] <= 10.0:
			mk[0] += 1
		else:
			mk[0] = 1
		mk[1] = time
		multikill[killer_champ] = mk
		if not first_blood:
			first_blood = true
			bounty += 100.0
			announce_text = "First Blood!"
		match mk[0]:
			2: announce_text = "Double Kill!"
			3: announce_text = "Triple Kill!"
			4: announce_text = "Quadra Kill!"
			5: announce_text = "PENTAKILL!"
		if announce_text == "":
			if victim_streak >= 3:
				announce_text = "Shut Down!"
			elif st == 3:
				announce_text = "Killing Spree!"
			elif st == 4:
				announce_text = "Rampage!"
			elif st == 5:
				announce_text = "Unstoppable!"
			elif st == 6:
				announce_text = "Dominating!"
			elif st == 7:
				announce_text = "Godlike!"
			elif st >= 8:
				announce_text = "Legendary!"
		killer_champ.add_gold(bounty, victim)
		killer_champ.gain_xp(victim.xp_bounty())
		for e in killer_champ.effects.duplicate():
			e.on_takedown(victim)
	for a in assisters:
		a.assists += 1
		a.add_gold(bounty * 0.5 / maxf(1.0, assisters.size()) + 50.0, victim)
		a.gain_xp(victim.xp_bounty() * 0.5)
		for e in a.effects.duplicate():
			e.on_takedown(victim)
	var entry := {"killer": killer_champ if killer_champ != null else killer, "victim": victim,
			"assists": assisters, "time": time, "team": team}
	events.append(entry)
	G.champion_killed.emit(victim, killer_champ if killer_champ != null else killer, assisters)
	if announce_text == "":
		announce_text = ("An enemy has been slain" if victim.team != G.player.team else "An ally has been slain") if G.player != null else "Slain"
		if victim == G.player:
			announce_text = "You have been slain"
		elif killer_champ == G.player:
			announce_text = "You have slain an enemy"
	var col := G.COLOR_ALLY if team == (G.player.team if G.player else 0) else G.COLOR_ENEMY
	announce_sub = "%s  ⚔  %s" % [killer_champ.display_name if killer_champ != null else (killer.display_name if killer != null and is_instance_valid(killer) else "Executed"), victim.display_name]
	G.announce(announce_text, announce_sub, col)


func _on_structure_destroyed(s: Unit, killer_champ) -> void:
	var team := G.enemy_team(s.team)
	var gold := 0.0
	match s.kind:
		G.Kind.TURRET:
			gold = 150.0
			G.announce("Turret destroyed" if s.team != (G.player.team if G.player else 0) else "Your turret has been destroyed", "", G.COLOR_ALLY if team == G.player.team else G.COLOR_ENEMY)
		G.Kind.INHIBITOR:
			gold = 50.0
			G.announce("Inhibitor destroyed" if s.team != G.player.team else "Your inhibitor has been destroyed", "", G.COLOR_ALLY if team == G.player.team else G.COLOR_ENEMY)
	for c in champions_of(team, false):
		c.add_gold(gold, s)
	G.structure_destroyed.emit(s, killer_champ)
	if s.kind == G.Kind.NEXUS:
		end_game(team)


func end_game(winning_team: int) -> void:
	if over:
		return
	over = true
	winner = winning_team
	G.time_scale_target = 0.25
	after(1.2, func(): G.time_scale_target = 1.0)
	# camera flies to the destroyed nexus; the battlefield freezes once it has exploded
	var nx = nexus_units[1 - winning_team]
	if hud != null:
		hud.visible = false
	if overlay != null:
		overlay.visible = false
	if camera_rig != null and nx != null:
		camera_rig.target = nx
		camera_rig.locked = true
	after(3.0, func():
		for u in units:
			if not u.dead and u.kind == G.Kind.CHAMPION:
				u.stop_moving()
				u.play_anim("idle", 1.0, 0.3)
		paused = true)
	if menu_layer != null:
		end_screen = EndScreen.new()
		end_screen.match_ref = self
		end_screen.action.connect(func(id): G.flow_request.emit(id))
		menu_layer.add_child(end_screen)
	G.match_over.emit(winning_team)


# ===================================================================== floating text
func fx_damage(info: DamageInfo) -> void:
	if overlay != null:
		overlay.damage_number(info)


func fx_heal(u: Unit, amount: float) -> void:
	if overlay != null:
		overlay.heal_number(u, amount)


func fx_text(u: Unit, text: String, color: Color, _info = null) -> void:
	if overlay != null:
		overlay.float_text(u, text, color)


func fx_gold(u: Unit, amount: float) -> void:
	if overlay != null:
		overlay.gold_number(u, amount)


# ===================================================================== setup
var nexus_units := [null, null]
var inhibitor_units := [null, null]
var outer_turrets := [null, null]
var inhib_turrets := [null, null]
var hexgates: Array = []
var augment_round := 0
var augment_tiers: Array = []      ## rolled tier per screen (shared by everyone)
var augments_seen := {}            ## id -> true (never repeat in a game)
var snow: GPUParticles3D = null


## Build the whole game. cfg: player_champion, player_skin, ally_champions, enemy_champions
func start(cfg: Dictionary) -> void:
	layout = MapBuilder.load_layout()
	nav = NavGrid.new()
	if not nav.load_from("res://data/map"):
		nav.build_corridor(MapBuilder.lane_points(layout), 8.0, [])
	MapBuilder.build_environment(world_root)
	MapBuilder.build_terrain(world_root)
	spawn_points = MapBuilder.spawn_points(layout)
	fountain = spawn_points
	lane_path = MapBuilder.lane_points(layout)
	_build_structures()
	spawner = WaveSpawner.new(self)
	spawner.setup(inhibitor_units[0].global_position, inhibitor_units[1].global_position, lane_path,
			[nexus_units[0].global_position, nexus_units[1].global_position])
	spawner.inhibitors = inhibitor_units
	_build_relics()
	_build_props()
	_roll_augment_tiers()
	_spawn_champions(cfg)
	_setup_view()
	G.match_started.emit()


func _block_for(u: Unit) -> float:
	match u.kind:
		G.Kind.TURRET:
			return 1.35
		G.Kind.INHIBITOR:
			return 2.1
		G.Kind.NEXUS:
			return 3.6
	return 0.0


func _build_structures() -> void:
	var recs := MapBuilder.structures(layout)
	var nexus_turrets := [[], []]
	for r in recs:
		var team: int = r.team
		var u: Unit = null
		match r.kind:
			"outer":
				u = Turret.new()
				u.setup(team, Turret.Tier.OUTER)
				outer_turrets[team] = u
			"inhib_turret":
				u = Turret.new()
				u.setup(team, Turret.Tier.INHIBITOR)
				inhib_turrets[team] = u
			"nexus_turret":
				u = Turret.new()
				u.setup(team, Turret.Tier.NEXUS)
				nexus_turrets[team].append(u)
			"fountain":
				u = Turret.new()
				u.setup(team, Turret.Tier.FOUNTAIN)
			"inhibitor":
				u = Structure.new()
				u.setup(team, true)
				inhibitor_units[team] = u
			"nexus":
				u = Structure.new()
				u.setup(team, false)
				nexus_units[team] = u
		if u == null:
			continue
		add_unit(u, r.pos)
		if u.model != null:
			u.model.rotation.y = r.yaw
		var br := _block_for(u)
		if br > 0.0:
			nav.block_disc(r.pos, br)
	for team in 2:
		if inhib_turrets[team] != null:
			inhib_turrets[team].guards = [outer_turrets[team]]
		if inhibitor_units[team] != null:
			inhibitor_units[team].guards = [inhib_turrets[team]]
		for t in nexus_turrets[team]:
			t.guards = [inhibitor_units[team]]
		if nexus_units[team] != null:
			nexus_units[team].guards = nexus_turrets[team].duplicate()


func on_structure_fell(s: Unit) -> void:
	if s == outer_turrets[0] or s == outer_turrets[1]:
		var team: int = s.team
		if inhib_turrets[team] != null:
			inhib_turrets[team].backdoor_until = time + 70.0
	_update_hexgates()


func _build_relics() -> void:
	var center := Vector3.ZERO
	for p in lane_path:
		center += p
	center /= maxf(1.0, lane_path.size())
	for p in MapBuilder.relic_points(layout):
		var r := Relic.new()
		add_child(r)
		r.global_position = p
		var outer := G.flat_dist(p, center) < 22.0
		r.setup(self, Rules.RELIC_OUTER_FIRST if outer else Rules.RELIC_INNER_FIRST)
		relics.append(r)


func _build_props() -> void:
	for p in MapBuilder.props(layout):
		var nm: String = p.name
		if nm.begins_with("HA_Hexgate"):
			var g := Assets.unit_model(nm, 0)
			if g != null:
				world_root.add_child(g)
				g.global_position = p.pos
				g.rotation.y = p.yaw
				_play_idle(g)
			hexgates.append({"pos": p.pos, "exit": nm.ends_with("Exit"), "node": g,
					"team": G.Team.ORDER if p.pos.x - p.pos.z < 130.0 else G.Team.CHAOS})
		elif nm in ["HA_AP_Viking", "HA_AP_Hermit", "HA_AP_Poro"]:
			var mdl := Assets.unit_model(nm, 0)
			if mdl != null:
				world_root.add_child(mdl)
				mdl.global_position = p.pos
				mdl.rotation.y = p.yaw
				_play_idle(mdl)
	_update_hexgates()


func _play_idle(n: Node) -> void:
	var ap := Assets._find_anim(n)
	if ap == null:
		return
	var list := ap.get_animation_list()
	for an in list:
		if String(an).to_lower().begins_with("idle"):
			ap.play(an)
			return
	if list.size() > 0 and list[0] != "RESET":
		ap.play(list[0])


func _update_hexgates() -> void:
	pass


func _spawn_champions(cfg: Dictionary) -> void:
	var ally: Array = cfg.get("ally_champions", []).duplicate()
	var enemy: Array = cfg.get("enemy_champions", []).duplicate()
	cfg_summoners = cfg.get("player_summoners", [])
	var pool: Array = ChampionDB.ROSTER.duplicate()
	pool.shuffle()
	var used := {cfg.player_champion: true}
	for a in ally + enemy:
		used[a] = true
	var pick := func() -> String:
		for p in pool:
			if not used.has(p):
				used[p] = true
				return p
		return pool[G.rng.randi() % pool.size()]
	while ally.size() < 4:
		ally.append(pick.call())
	while enemy.size() < 5:
		enemy.append(pick.call())
	var order_list: Array = [cfg.player_champion] + ally
	for i in order_list.size():
		_spawn_champion(order_list[i], G.Team.ORDER, cfg.get("player_skin", 0) if i == 0 else 0, i == 0, i)
	for i in enemy.size():
		_spawn_champion(enemy[i], G.Team.CHAOS, 0, false, i)


func _spawn_champion(alias: String, team: int, skin: int, is_player: bool, idx: int) -> Champion:
	var c := Champion.new()
	c.is_player = is_player
	c.setup(alias, team, skin)
	c.spawn_point = spawn_points[team]
	var ang := TAU * idx / 5.0
	var pos: Vector3 = spawn_points[team] + Vector3(cos(ang), 0, sin(ang)) * 2.2
	add_unit(c, pos)
	c.facing = G.flat_dir(pos, nexus_units[1 - team].global_position)
	c.face_toward(c.global_position + c.facing, 1000.0)
	if is_player:
		var sums: Array = cfg_summoners if not cfg_summoners.is_empty() else ["Flash", "Mark"]
		Summoners.give_default(c, sums[0], sums[1])
	else:
		Summoners.give_default(c, "Flash", _bot_summoner(c))
	if is_player:
		G.player = c
	else:
		var b := BotBrain.new()
		b.setup(c, self)
		c.controller = b
		c.auto_level_abilities()
	c.add_effect(MayhemAura.new())
	c.play_anim("idle", 1.0, 0.0)
	c.augments_pending = 1   # game-start augment screen (level 3)
	return c


var cfg_summoners: Array = []
var menu_layer: CanvasLayer = null
var pause_menu: PauseMenu = null
var end_screen: EndScreen = null


## ARAM-ish second summoner for bots: mostly Mark, otherwise something fitting the champion.
func _bot_summoner(c: Champion) -> String:
	if G.rng.randf() < 0.55:
		return "Mark"
	var melee: bool = c.stats.attack_range < 300.0
	var opts := ["Ghost", "Ignite", "Barrier"] if melee else ["Heal", "Barrier", "Ignite", "Cleanse"]
	return opts[G.rng.randi() % opts.size()]


func _setup_view() -> void:
	camera_rig = CameraRig.new()
	add_child(camera_rig)
	camera_rig.target = G.player
	camera_rig.snap_to(G.player.global_position)
	player_controller = PlayerController.new()
	player_controller.match_ref = self
	player_controller.rig = camera_rig
	player_controller.champ = G.player
	G.player.controller = player_controller
	add_child(player_controller)
	snow = MapBuilder.build_snow(camera_rig)
	snow.position = Vector3(0, -6, -10)
	var layer := CanvasLayer.new()
	layer.name = "OverlayLayer"
	layer.layer = 1
	add_child(layer)
	overlay = WorldOverlay.new()
	overlay.match_ref = self
	overlay.rig = camera_rig
	layer.add_child(overlay)
	var hud_layer := CanvasLayer.new()
	hud_layer.name = "HudLayer"
	hud_layer.layer = 2
	add_child(hud_layer)
	hud = Hud.new()
	hud.match_ref = self
	hud_layer.add_child(hud)
	menu_layer = CanvasLayer.new()
	menu_layer.name = "MenuLayer"
	menu_layer.layer = 5
	add_child(menu_layer)
	pause_menu = PauseMenu.new()
	pause_menu.match_ref = self
	menu_layer.add_child(pause_menu)


# ===================================================================== augments
func _roll_augment_tiers() -> void:
	augment_tiers.clear()
	for i in Rules.TIER_WEIGHTS.size():
		var w: Array = Rules.TIER_WEIGHTS[i]
		var r := G.rng.randf()
		var tier := "Silver"
		if r < w[0]:
			tier = "Silver"
		elif r < w[0] + w[1]:
			tier = "Gold"
		else:
			tier = "Prismatic"
		if i == 1 and tier == "Silver" and augment_tiers[0] == "Silver":
			tier = "Gold"
		augment_tiers.append(tier)


## Queue an augment screen for a champion who reached an augment level.
func offer_augment(c: Champion) -> void:
	c.augments_pending += 1
	G.augment_offer_ready.emit(c)


# ===================================================================== augment screens
var offers := {}                   ## Champion -> {ids, rerolled, tier, round}
var seen_augments := {}            ## Champion -> {id: true}


func augment_tier_for(c: Champion) -> String:
	var r: int = clampi(c.augment_round, 0, augment_tiers.size() - 1)
	return augment_tiers[r]


func get_offer(c: Champion) -> Dictionary:
	if offers.has(c):
		return offers[c]
	var tier := augment_tier_for(c)
	var seen: Dictionary = seen_augments.get(c, {})
	seen_augments[c] = seen
	var ids := AugmentDB.roll(c, tier, Rules.AUGMENT_CHOICES, seen)
	if ids.size() < Rules.AUGMENT_CHOICES:
		# pool ran dry: allow already-seen augments
		ids = AugmentDB.roll(c, tier, Rules.AUGMENT_CHOICES, {})
	for aid in ids:
		seen[aid] = true
	var off := {"ids": ids, "rerolled": [false, false, false], "tier": tier, "round": c.augment_round}
	offers[c] = off
	return off


func reroll_offer(c: Champion, i: int) -> void:
	var off := get_offer(c)
	if i >= off.ids.size() or off.rerolled[i]:
		return
	var excl: Dictionary = seen_augments.get(c, {}).duplicate()
	for aid in off.ids:
		excl[aid] = true
	var pick := AugmentDB.roll(c, off.tier, 1, excl)
	if pick.is_empty():
		return
	off.ids[i] = pick[0]
	seen_augments[c][pick[0]] = true
	off.rerolled[i] = true


func choose_augment(c: Champion, i: int) -> void:
	var off := get_offer(c)
	if off.ids.is_empty():
		c.augments_pending = maxi(0, c.augments_pending - 1)
		offers.erase(c)
		return
	var aid: String = off.ids[clampi(i, 0, off.ids.size() - 1)]
	offers.erase(c)
	grant_augment(c, aid)
	c.augments_pending = maxi(0, c.augments_pending - 1)
	c.augment_round += 1


## Give an augment to a champion (also used by Transmute & co).
func grant_augment(c: Champion, aid: String) -> Augment:
	var a := AugmentDB.create(aid)
	if a == null:
		return null
	c.add_augment(a)
	a.on_acquire(c)
	if c == G.player:
		Vfx.rising(c, G.RARITY_COLORS.get(a.rarity, Color.WHITE), 0.8, 40, 0.8)
		Vfx.ring(self, c.global_position, G.RARITY_COLORS.get(a.rarity, Color.WHITE), 2.2, 0.6, 0.1, 0.2)
	return a


func bot_choose_augment(c: Champion) -> void:
	if c.augments_pending <= 0:
		return
	if not (c.dead or c.in_fountain):
		return
	var off := get_offer(c)
	# bots reroll offers that are a poor fit
	for i in off.ids.size():
		var probe := AugmentDB.create(off.ids[i])
		if probe != null:
			probe.owner = c
			if probe.power + probe.synergy(c) < 1.0 and G.rng.randf() < 0.7:
				reroll_offer(c, i)
	choose_augment(c, AugmentDB.bot_pick(c, off.ids))


# ===================================================================== shopping
func bot_shop(c: Champion) -> void:
	if not c.can_shop():
		return
	var guard := 0
	while guard < 8:
		guard += 1
		var nxt := ItemDB.bot_next_purchase(c)
		if nxt < 0 or not ItemDB.buy(c, nxt):
			break
