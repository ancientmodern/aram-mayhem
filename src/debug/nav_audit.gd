extends Node
## [path] Navigation audit (harness). Compares our walkability with League's raw navgrid, lists every static
## blocker, then walks the player champion between thousands of random point pairs (lane + every brush) through
## the real Unit movement code and flags detours / loops / blocked walks against League's own grid path.
##
## Usage: tools/check.sh 3000 -- --sim --harness=res://src/debug/nav_audit.gd --navaudit=800
##   (tools/check.sh runs headless; read the NAVAUDIT lines in tools/extracted/run.log)
##   --navaudit=N      pairs per class (default 400)
##   --navseed=S       rng seed
## Reference data: tools/extracted/navgrid_raw.bin (League's own navgrid, dumped by tools/lol/dump_navgrid_raw.py).
## Exit codes are not used; the report ends with "NAVAUDIT RESULT clean" or "NAVAUDIT RESULT <n> findings".

var main = null
var match_ref = null

const DT := 1.0 / 30.0
const DETOUR_RATIO := 1.15
const DETOUR_MIN_EXTRA := 0.75       ## m, ignore sub-cell noise on very short walks
const RAW_PATH := "res://tools/extracted/navgrid_raw.bin"

var n_pairs := 400
var rng := RandomNumberGenerator.new()
var m = null
var nav: NavGrid = null
var ref: NavGrid = null              ## League's raw walkability, no structure blocks
var live := false                    ## --navlive: walk into every brush inside a running match (bots, minions, fog) instead of the frozen static audit
var pick := false                    ## --navpick: screen_to_ground round trip over every brush cell
var unitblock := false               ## --navunit: a standing enemy champion parked in each brush; walk past / through it
var clickmode := false               ## --navclick: real mouse events (HUD hit areas, picking, controller) at every brush cell
var shotmode := false                ## --navshot: screenshots of the champion walking into brush 4 / 1 (before / after evidence)
var grassmode := false               ## --navgrass: every rendered grass (brush) mesh vs the nav brush flags under it
var respawnmode := false             ## --navrespawn: camera must return to the champion on respawn (free camera, spectating an ally)
var findings := 0
var out_lines: PackedStringArray = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var seed_v := 12345
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--navaudit="):
			n_pairs = int(a.substr(11))
		elif a == "--navrespawn":
			respawnmode = true
		elif a == "--navgrass":
			grassmode = true
		elif a == "--navshot":
			shotmode = true
		elif a == "--navclick":
			clickmode = true
		elif a == "--navunit":
			unitblock = true
		elif a == "--navpick":
			pick = true
		elif a == "--navlive":
			live = true
		elif a.begins_with("--navseed="):
			seed_v = int(a.substr(10))
	rng.seed = seed_v
	_run()


func _say(s: String) -> void:
	print("NAVAUDIT ", s)
	out_lines.append(s)


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _run() -> void:
	await _wait(1.2)
	m = G.match
	nav = m.nav
	_build_ref()
	if respawnmode:
		await _respawn_check()
		get_tree().quit()
		return
	if grassmode:
		_grass_audit()
		get_tree().quit()
		return
	if shotmode:
		await _shot_audit()
		get_tree().quit()
		return
	if clickmode:
		await _click_audit()
		get_tree().quit()
		return
	if unitblock:
		await _unit_block_audit()
		get_tree().quit()
		return
	if pick:
		await _pick_audit()
		get_tree().quit()
		return
	if live:
		await _live_audit()
		get_tree().quit()
		return
	get_tree().paused = true   # freeze the live match: static world for a repeatable audit
	_walk_diff()
	_static_blockers()
	await _path_audit()
	_say("RESULT " + ("clean" if findings == 0 else "%d findings" % findings))
	var f := FileAccess.open("res://tools/extracted/nav_audit_report.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(out_lines) + "\n")
		f.close()
	get_tree().quit()


# ===================================================================== League reference grid
func _build_ref() -> void:
	ref = NavGrid.new()
	ref.origin = nav.origin
	ref.cell = nav.cell
	ref.w = nav.w
	ref.h = nav.h
	ref.heights = nav.heights
	ref.walk = FileAccess.get_file_as_bytes("res://data/map/navgrid_walk.bin")   # fallback
	if FileAccess.file_exists(RAW_PATH):
		var d := FileAccess.get_file_as_bytes(RAW_PATH)
		var n := nav.w * nav.h
		var base := 39 + 48 * n
		var raw := PackedByteArray()
		raw.resize(n)
		var cnt128 := 0
		var flag_hist := {}
		for j in nav.h:
			for i in nav.w:
				# League row z increases north; our row 0 = most negative Godot z = max League z
				var lj := nav.h - 1 - j
				var fl := d.decode_u16(base + 2 * (lj * nav.w + i))
				flag_hist[fl] = flag_hist.get(fl, 0) + 1
				raw[j * nav.w + i] = 1 if (fl & 2) == 0 else 0
		ref.walk = raw
		_say("raw League flags histogram: " + str(flag_hist))
	else:
		_say("WARNING raw navgrid missing (%s): comparing against data/map/navgrid_walk.bin only" % RAW_PATH)
	ref._build_astar()
	ref.floor_h = nav.floor_h
	ref.floor_w = nav.floor_w
	ref.floor_hh = nav.floor_hh
	ref.floor_origin = nav.floor_origin
	ref.floor_inv = nav.floor_inv


# ===================================================================== walkability compare
func _walk_diff() -> void:
	var bin := FileAccess.get_file_as_bytes("res://data/map/navgrid_walk.bin")
	var bad_bin := 0
	var extra_block := 0     # walkable in League, blocked in game
	var extra_open := 0      # blocked in League, walkable in game
	var cells: Array = []
	for k in nav.w * nav.h:
		if ref.walk[k] != bin[k]:
			bad_bin += 1
		if ref.walk[k] == 1 and nav.walk[k] == 0:
			extra_block += 1
			cells.append(k)
		elif ref.walk[k] == 0 and nav.walk[k] == 1:
			extra_open += 1
	_say("walk cells: League walkable=%d ours=%d | bin vs League mismatch=%d | blocked-by-us=%d | opened-by-us=%d" % [
		_count(ref.walk), _count(nav.walk), bad_bin, extra_block, extra_open])
	_say("  intentionally opened League slivers (invisible free-standing walls, NavGrid._open_islands): %d cells" % nav.opened_cells.size())
	if bad_bin > 0 or extra_open != nav.opened_cells.size():
		findings += 1
	# no free-standing unwalkable component may remain (an invisible obstacle in open ground)
	var wall_cells: Array = []
	for k in nav.w * nav.h:
		if nav.walk[k] == 0 and ref.walk[k] == 0:
			wall_cells.append(k)
	var left := 0
	for comp in _components(wall_cells):
		var border := false
		for k in comp:
			var x: int = k % nav.w
			var z: int = k / nav.w
			if x == 0 or z == 0 or x == nav.w - 1 or z == nav.h - 1:
				border = true
				break
		if not border and comp.size() < NavGrid.ISLAND_MAX:
			left += 1
			_say("  FREE-STANDING unwalkable component of %d cells remains" % comp.size())
	findings += left
	# connected components of the cells we blocked, matched to structure discs
	var comps := _components(cells)
	for c in comps:
		var cen := Vector3.ZERO
		for k in c:
			cen += nav.cell_center(Vector2i(k % nav.w, k / nav.w))
		cen /= float(c.size())
		var who := "UNEXPLAINED"
		for u in m.units:
			if u != null and is_instance_valid(u) and (u.kind == G.Kind.TURRET or u.kind == G.Kind.INHIBITOR or u.kind == G.Kind.NEXUS):
				if G.flat_dist(u.global_position, cen) < 6.0:
					who = "%s (team %d)" % [u.display_name, u.team]
		_say("  blocked cluster at (%.1f, %.1f) cells=%d by %s" % [cen.x, cen.z, c.size(), who])
		if who == "UNEXPLAINED":
			findings += 1


func _count(a: PackedByteArray) -> int:
	var n := 0
	for v in a:
		n += v
	return n


func _components(keys: Array) -> Array:
	var set := {}
	for k in keys:
		set[k] = true
	var comps: Array = []
	for k in keys:
		if not set.has(k):
			continue
		var comp: Array = []
		var stack: Array = [k]
		set.erase(k)
		while not stack.is_empty():
			var a: int = stack.pop_back()
			comp.append(a)
			var ax: int = a % nav.w
			var az: int = a / nav.w
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var nx := ax + dx
					var nz := az + dz
					if nx < 0 or nz < 0 or nx >= nav.w or nz >= nav.h:
						continue
					var b := nz * nav.w + nx
					if set.has(b):
						set.erase(b)
						stack.append(b)
		comps.append(comp)
	return comps


# ===================================================================== static blockers
func _static_blockers() -> void:
	_say("static blockers (everything that stops or deflects a walking champion):")
	var n_solid := 0
	for u in m.units:
		if u == null or not is_instance_valid(u):
			continue
		if u.kind == G.Kind.CHAMPION or u.kind == G.Kind.MINION:
			continue
		n_solid += 1
		_say("  unit %-22s kind=%d team=%d pos=(%.1f, %.1f) path_radius=%.2f mass=%.1f nav_disc=%.2f" % [
			u.display_name, u.kind, u.team, u.global_position.x, u.global_position.z, u.path_radius, u.mass, m._block_for(u)])
	# physics bodies / nav obstacles anywhere in the scene (must be none: movement is nav grid + unit pushes only)
	var bodies: Array = []
	_scan_bodies(get_tree().root, bodies)
	for b in bodies:
		_say("  physics/nav node %s (%s) at %s" % [b.get_path(), b.get_class(), str(b.global_position) if b is Node3D else "-"])
		findings += 1
	# other non-champion, non-minion units (wards, summons, relics) that are solid
	_say("  total non-lane solid units: %d, physics/nav nodes: %d" % [n_solid, bodies.size()])
	# League-vs-ours: structure discs (cells blocked beyond League) are listed above as clusters


func _scan_bodies(n: Node, out: Array) -> void:
	if n is CollisionObject3D or n is NavigationObstacle3D or n is NavigationRegion3D or n is CollisionShape3D:
		out.append(n)
	for c in n.get_children():
		_scan_bodies(c, out)


# ===================================================================== path audit
func _walkable_cells(pred: Callable) -> Array:
	var a: Array = []
	for j in nav.h:
		for i in nav.w:
			var k := j * nav.w + i
			if ref.walk[k] == 1 and nav.walk[k] == 1 and pred.call(k):
				a.append(k)
	return a


func _near_structure(p: Vector3) -> bool:
	# structures and the bots parked at the fountain: a goal inside a unit's body is stopped short by design
	for u in m.units:
		if u != null and is_instance_valid(u) and u != G.player and not u.dead:
			if G.flat_dist(u.global_position, p) < u.path_radius + 2.2:
				return true
	return false


func _cell_pt(k: int) -> Vector3:
	# random point inside the cell
	var i := k % nav.w
	var j := k / nav.w
	var x := nav.origin.x + (i + rng.randf()) * nav.cell
	var z := nav.origin.y + (j + rng.randf()) * nav.cell
	return Vector3(x, 0.0, z)


func _path_len(pts: PackedVector3Array, from: Vector3) -> float:
	var l := 0.0
	var p := from
	for q in pts:
		l += G.flat_dist(p, q)
		p = q
	return l


## Independent shortest-path reference: Dijkstra over League's raw grid with 16 neighbours (8 + knight moves), so it
## shares no code with the game's A* + string pulling. Distances in metres from the source cell centre.
const _NB := [[1, 0, 10], [-1, 0, 10], [0, 1, 10], [0, -1, 10], [1, 1, 14], [1, -1, 14], [-1, 1, 14], [-1, -1, 14],
	[2, 1, 22], [2, -1, 22], [-2, 1, 22], [-2, -1, 22], [1, 2, 22], [1, -2, 22], [-1, 2, 22], [-1, -2, 22]]


func _geodesic(src: Vector3) -> PackedFloat32Array:
	var n := ref.w * ref.h
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(1 << 30)
	var sc := ref.to_cell(ref.nearest_walkable(src))
	var s0 := sc.y * ref.w + sc.x
	dist[s0] = 0
	var buckets: Array = []
	buckets.resize(6000)
	buckets[0] = [s0]
	var w := ref.w
	var walk := ref.walk
	for bi in 6000:
		var bk = buckets[bi]
		if bk == null:
			continue
		var idx := 0
		while idx < bk.size():
			var k: int = bk[idx]
			idx += 1
			if dist[k] != bi:
				continue
			var kx := k % w
			var kz := k / w
			for nb in _NB:
				var nx: int = kx + nb[0]
				var nz: int = kz + nb[1]
				if nx < 0 or nz < 0 or nx >= w or nz >= ref.h or walk[nz * w + nx] == 0:
					continue
				if absi(nb[0]) == 2 or absi(nb[1]) == 2:
					# knight move: both cells it squeezes between must be open
					var mx: int = kx + (nb[0] / 2 if absi(nb[0]) == 2 else 0)
					var mz: int = kz + (nb[1] / 2 if absi(nb[1]) == 2 else 0)
					var ax: int = mx + (0 if absi(nb[0]) == 2 else nb[0])
					var az: int = mz + (0 if absi(nb[1]) == 2 else nb[1])
					if walk[mz * w + mx] == 0 or walk[az * w + ax] == 0:
						continue
				var nd: int = bi + nb[2]
				var nk := nz * w + nx
				if nd < dist[nk] and nd < 6000:
					dist[nk] = nd
					if buckets[nd] == null:
						buckets[nd] = []
					buckets[nd].append(nk)
	var out := PackedFloat32Array()
	out.resize(n)
	for k in n:
		out[k] = dist[k] * ref.cell * 0.1 if dist[k] < (1 << 30) else INF
	return out


## Walk length to the point we should stop at when the click `b` is on terrain: among the cells within 1.5 m of the
## click's closest reachable approach, the cheapest to get to.
func _best_reach_len(a: Vector3, b: Vector3, geo: PackedFloat32Array) -> float:
	var cb := ref.to_cell(b)
	var best_d := INF
	for dj in range(-14, 15):
		for di in range(-14, 15):
			var q := Vector2i(cb.x + di, cb.y + dj)
			if ref.in_bounds(q) and ref.walk[q.y * ref.w + q.x] == 1:
				best_d = minf(best_d, G.flat_dist(ref.cell_center(q), b))
	var best := INF
	for dj in range(-14, 15):
		for di in range(-14, 15):
			var q := Vector2i(cb.x + di, cb.y + dj)
			if ref.in_bounds(q) and ref.walk[q.y * ref.w + q.x] == 1 and G.flat_dist(ref.cell_center(q), b) <= best_d + 1.5:
				var gl: float = G.flat_dist(a, ref.cell_center(q)) if geo.is_empty() else geo[q.y * ref.w + q.x]
				best = minf(best, gl)
	return best if best < INF else G.flat_dist(a, b)


## League's path length a -> b: straight when the raw grid allows it, else the Dijkstra distance (sources are cached).
func _ref_len(a: Vector3, b: Vector3, geo: PackedFloat32Array) -> float:
	if ref.line_walkable(a, b) or geo.is_empty():
		return G.flat_dist(a, b)
	var cb := ref.to_cell(b)
	return maxf(geo[cb.y * ref.w + cb.x], G.flat_dist(a, b))


func _walk(c: Champion, a: Vector3, b: Vector3) -> Dictionary:
	c.teleport(a)
	c.issue_move(b)
	var prev := c.global_position
	var len := 0.0
	var t := 0.0
	var trace := PackedVector3Array([prev])
	var acc := 0.0
	while c.moving and t < 90.0:
		c._update_movement(DT)
		var p := c.global_position
		len += G.flat_dist(prev, p)
		acc += G.flat_dist(prev, p)
		prev = p
		t += DT
		if acc >= 0.5:
			acc = 0.0
			trace.append(p)
	var end := c.global_position
	return {"len": len, "t": t, "end": end, "timeout": c.moving, "trace": trace}


func _loops(trace: PackedVector3Array) -> bool:
	# revisit: two samples > 8 m apart along the path but < 1.2 m apart in space
	var n := trace.size()
	for i in n:
		for j in range(i + 16, n):
			if G.flat_dist(trace[i], trace[j]) < 1.2:
				return true
	return false


func _path_audit() -> void:
	var c: Champion = G.player
	c.cc &= ~Buff.CC.GHOSTED
	var all := _walkable_cells(func(k): return true)
	var brush_ids := {}
	for k in all:
		var b: int = nav.brush[k]
		if b != 0:
			if not brush_ids.has(b):
				brush_ids[b] = []
			brush_ids[b].append(k)
	var lane := _walkable_cells(func(k): return nav.brush[k] == 0)
	var classes: Array = []
	classes.append(["lane<->lane", func(): return [lane[rng.randi() % lane.size()], lane[rng.randi() % lane.size()]]])
	for id in brush_ids.keys():
		var bc: Array = brush_ids[id]
		classes.append(["lane->brush%d" % id, func(): return [lane[rng.randi() % lane.size()], bc[rng.randi() % bc.size()]]])
		classes.append(["brush%d->lane" % id, func(): return [bc[rng.randi() % bc.size()], lane[rng.randi() % lane.size()]]])
		classes.append(["brush%d<->brush%d" % [id, id], func(): return [bc[rng.randi() % bc.size()], bc[rng.randi() % bc.size()]]])
	# short local walks into / inside each brush (a click a few metres away): the player's usual case
	for id in brush_ids.keys():
		var bc2: Array = brush_ids[id]
		classes.append(["near->brush%d" % id, func():
			var kb: int = bc2[rng.randi() % bc2.size()]
			var pb := _cell_pt(kb)
			var ps := pb + Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 8))
			var ks := nav.to_cell(ps)
			if not nav.in_bounds(ks) or nav.walk[ks.y * nav.w + ks.x] == 0:
				return [kb, kb]
			return [ks.y * nav.w + ks.x, kb]])
	# clicks on terrain you cannot stand on (the grass sprites and ledges reach past the walkable brush cells):
	# the champion must walk to the closest point it can REACH, not to the nearest cell behind a wall
	var near_blocked := {}
	for k in all:
		if nav.brush[k] == 0:
			continue
		var ci: int = k % nav.w
		var cj: int = k / nav.w
		for dj in range(-7, 8):
			for di in range(-7, 8):
				var ni: int = ci + di
				var nj: int = cj + dj
				if ni < 0 or nj < 0 or ni >= nav.w or nj >= nav.h:
					continue
				if ref.walk[nj * nav.w + ni] == 0:
					near_blocked[nj * nav.w + ni] = true
	var nb_cells: Array = near_blocked.keys()
	classes.append(["click-wall near brush", func(): return [lane[rng.randi() % lane.size()], nb_cells[rng.randi() % nb_cells.size()]]])
	var total := 0
	var worst: Array = []
	for cl in classes:
		var name: String = cl[0]
		var gen: Callable = cl[1]
		var bad := 0
		var maxr := 1.0
		var done := 0
		var geo := PackedFloat32Array()
		var a := Vector3.ZERO
		for s in n_pairs:
			var pr: Array = gen.call()
			if s % 12 == 0 or name.begins_with("near"):
				a = _cell_pt(pr[0])
				geo = PackedFloat32Array()
			var b := _cell_pt(pr[1])
			if G.flat_dist(a, b) < 1.0 or _near_structure(a) or _near_structure(b):
				continue   # a goal inside a structure's body is stopped short by design (League body block)
			if geo.is_empty() and not ref.line_walkable(a, b):
				geo = _geodesic(a)
			var blocked_click: bool = ref.walk[pr[1]] == 0
			var rl := _ref_len(a, b, geo)
			if blocked_click:
				# best case: stand at the reachable walkable point closest to the click
				rl = _best_reach_len(a, b, geo)
			var r := _walk(c, a, b)
			done += 1
			var reason := ""
			var arrived := G.flat_dist(r.end, b)
			if blocked_click:
				arrived = 0.0   # standing short of an unwalkable click is expected
			if r.timeout:
				reason = "TIMEOUT"
			elif arrived > 1.0:
				reason = "BLOCKED (stopped %.1f m short)" % arrived
			elif r.len > rl * DETOUR_RATIO and r.len - rl > DETOUR_MIN_EXTRA:
				reason = "DETOUR x%.2f" % (r.len / maxf(rl, 0.01))
			if reason == "" and _loops(r.trace) and r.len > rl * 1.05:
				reason = "LOOP"
			if reason != "":
				bad += 1
				maxr = maxf(maxr, r.len / maxf(rl, 0.01))
				worst.append([r.len / maxf(rl, 0.01), "%s %s from (%.1f, %.1f) to (%.1f, %.1f): walked %.1f m, League path %.1f m" % [
					name, reason, a.x, a.z, b.x, b.z, r.len, rl]])
			if done % 12 == 0:
				await get_tree().process_frame
		total += done
		_say("class %-18s pairs=%4d flagged=%3d worst=x%.2f" % [name, done, bad, maxr])
		findings += bad
	worst.sort_custom(func(x, y): return x[0] > y[0])
	_say("pairs walked: %d; worst offenders:" % total)
	for i in mini(worst.size(), 40):
		_say("  " + worst[i][1])


# ===================================================================== live audit (running match, real units)
## The probe is the player's champion; the match runs normally (bots fighting, minion waves, fog of war). Walks into
## every brush from random lane cells and reports every walk that detours, loops or stops short, with the units
## that touched it (and whether the player's team could see them: an unseen unit is an "invisible obstacle").
func _live_audit() -> void:
	var c: Champion = G.player
	m.game_speed = 8.0
	while m.time < 75.0:
		await get_tree().process_frame
	m.game_speed = 4.0
	c.invulnerable_count += 1   # bots keep fighting; the probe must not die mid-walk
	if c.dead:
		c.respawn()
	var brush_cells := {}
	var lane_cells: Array = []
	for j in nav.h:
		for i in nav.w:
			var k := j * nav.w + i
			if nav.walk[k] == 0:
				continue
			var id: int = nav.brush[k]
			if id != 0:
				if not brush_cells.has(id):
					brush_cells[id] = []
				brush_cells[id].append(Vector2i(i, j))
			else:
				lane_cells.append(Vector2i(i, j))
	var total := 0
	var flagged := 0
	for id in brush_cells.keys():
		var cells: Array = brush_cells[id]
		var bad := 0
		for n in n_pairs:
			var goal := nav.cell_center(cells[rng.randi() % cells.size()])
			var start := Vector3.INF
			for attempt in 400:
				var q: Vector2i = lane_cells[rng.randi() % lane_cells.size()]
				var d := G.flat_dist(nav.cell_center(q), goal)
				if d > 5.0 and d < 14.0:
					start = nav.cell_center(q)
					break
			if start == Vector3.INF:
				continue
			c.teleport(start)
			c.clear_all_cc() if c.has_method("clear_all_cc") else null
			c.issue_move(goal)
			var prev := c.global_position
			var len := 0.0
			var t0: float = m.time
			var trace := PackedVector3Array([prev])
			var acc := 0.0
			var seen := {}
			while m.time - t0 < 14.0 and c.moving:
				await get_tree().process_frame
				var p := c.global_position
				var step := G.flat_dist(prev, p)
				len += step
				acc += step
				prev = p
				if acc >= 0.5:
					acc = 0.0
					trace.append(p)
				for u in m.units:
					if u != c and is_instance_valid(u) and not u.dead and G.flat_dist(u.global_position, p) < u.path_radius + c.path_radius + 0.7:
						var vis: bool = u.team == c.team or bool(u.visible_to[c.team])
						seen["%s(team %d, %s, %s)" % [u.display_name, u.team, "moving" if u.moving else "standing", "visible" if vis else "UNSEEN"]] = true
			var direct := G.flat_dist(start, goal)
			var rl := ref.find_path(start, goal)
			var reflen := _path_len(rl, start)
			var short := G.flat_dist(c.global_position, goal)
			var reason := ""
			if c.moving:
				reason = "TIMEOUT"
			elif short > 1.0:
				reason = "STOPPED %.1f m short" % short
			elif len > reflen * 1.2 and len - reflen > 1.0:
				reason = "DETOUR x%.2f" % (len / maxf(reflen, 0.01))
			elif _loops(trace) and len > reflen * 1.05:
				reason = "LOOP"
			total += 1
			if reason != "":
				bad += 1
				flagged += 1
				_say("LIVE brush%d %s: (%.1f, %.1f) -> (%.1f, %.1f) walked %.1f m vs %.1f m, end dist %.1f, t=%.0f" % [
					id, reason, start.x, start.z, goal.x, goal.z, len, reflen, short, m.time])
				for k in seen.keys():
					_say("      touched " + k)
		_say("LIVE brush%d: %d walks, %d flagged" % [id, n_pairs, bad])
	findings += flagged
	_say("LIVE done at match time %.1f: %d walks, %d flagged" % [m.time, total, flagged])
	_say("RESULT " + ("clean" if findings == 0 else "%d findings" % findings))


# ===================================================================== picking round trip
## Cursor -> world point must land on the cell the cursor is over: project each brush cell to the screen with the
## camera centred on the player (and 8 m off-centre), cast it back with CameraRig.screen_to_ground.
func _pick_audit() -> void:
	var rig = m.camera_rig
	var c: Champion = G.player
	for id in range(1, 5):
		var errs := 0.0
		var worst := 0.0
		var n := 0
		var wrong_cells := 0
		var cells: Array = []
		for j in nav.h:
			for i in nav.w:
				if nav.brush[j * nav.w + i] == id:
					cells.append(Vector2i(i, j))
		if cells.is_empty():
			continue
		for q in cells:
			var wp := nav.cell_center(q)
			for off in [Vector3.ZERO, Vector3(0, 0, 8), Vector3(8, 0, 0), Vector3(-8, 0, -8)]:
				rig.snap_to(wp + off)
				await get_tree().process_frame
				var sp: Vector2 = rig.cam.unproject_position(wp)
				var back: Vector3 = rig.screen_to_ground(sp, nav)
				var e := G.flat_dist(back, wp)
				errs += e
				worst = maxf(worst, e)
				n += 1
				if nav.to_cell(back) != q:
					wrong_cells += 1
		_say("PICK brush%d cells=%d samples=%d mean err %.3f m worst %.3f m, landed in a different cell %d times" % [id, cells.size(), n, errs / n, worst, wrong_cells])


# ===================================================================== standing unit in a brush
## An enemy that stands still in a brush (hidden by fog of war, so an "invisible obstacle") must only deflect a walk
## by its own radius, never trap or loop the champion.
func _unit_block_audit() -> void:
	get_tree().paused = true
	var c: Champion = G.player
	var blocker: Champion = null
	for ch in m.champions:
		if ch != c and ch.team != c.team:
			blocker = ch
			break
	for ch in m.champions:
		if ch != c and ch != blocker:
			ch.teleport(ch.spawn_point)
	var brush_cells := {}
	for j in nav.h:
		for i in nav.w:
			var id: int = nav.brush[j * nav.w + i]
			if id != 0 and nav.walk[j * nav.w + i] == 1:
				if not brush_cells.has(id):
					brush_cells[id] = []
				brush_cells[id].append(Vector2i(i, j))
	for id in brush_cells.keys():
		var cells: Array = brush_cells[id]
		var bad := 0
		var done := 0
		for n in n_pairs:
			var bq: Vector2i = cells[rng.randi() % cells.size()]
			var bp := nav.cell_center(bq)
			blocker.teleport(bp)
			blocker.issue_stop()
			m._rebuild_grid()
			# a walk that crosses the blocker: start 3-9 m on one side, goal 3-9 m on the other (both walkable)
			var ang := rng.randf() * TAU
			var dir := Vector3(cos(ang), 0, sin(ang))
			var a := bp - dir * rng.randf_range(3.0, 9.0)
			var b := bp + dir * rng.randf_range(3.0, 9.0)
			if not nav.is_walkable(a) or not nav.is_walkable(b):
				continue
			c.teleport(a)
			m._rebuild_grid()
			var r := _walk(c, a, b)
			var rl := _path_len(ref.find_path(a, b), a)
			done += 1
			var arrived := G.flat_dist(r.end, b)
			var reason := ""
			if r.timeout:
				reason = "TIMEOUT"
			elif arrived > 1.0:
				reason = "STOPPED %.1f m short" % arrived
			elif r.len > rl * 1.3 and r.len - rl > 1.5:
				reason = "DETOUR x%.2f" % (r.len / maxf(rl, 0.01))
			elif _loops(r.trace):
				reason = "LOOP"
			if reason != "":
				bad += 1
				_say("UNIT brush%d %s: (%.1f, %.1f) -> (%.1f, %.1f) blocker at (%.1f, %.1f) walked %.1f m vs %.1f m" % [
					id, reason, a.x, a.z, b.x, b.z, bp.x, bp.z, r.len, rl])
		findings += bad
		_say("UNIT brush%d: %d walks past a standing unit, %d flagged" % [id, done, bad])
	_say("RESULT " + ("clean" if findings == 0 else "%d findings" % findings))


# ===================================================================== real clicks through the whole input path
func _screen_of(p: Vector3) -> Vector2:
	return get_viewport().get_final_transform() * m.camera_rig.cam.unproject_position(p)


func _rclick(sp: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = sp
	ev.global_position = sp
	Input.parse_input_event(ev)
	await get_tree().process_frame
	var d := InputEventMouseButton.new()
	d.button_index = MOUSE_BUTTON_RIGHT
	d.position = sp
	d.global_position = sp
	d.pressed = true
	Input.parse_input_event(d)
	await get_tree().process_frame
	var u := d.duplicate()
	u.pressed = false
	Input.parse_input_event(u)


## Right-click every brush cell on screen exactly as the player does, with the camera locked on the champion that
## starts a few metres away, and compare where the champion ends up with the cell that was clicked.
func _click_audit() -> void:
	var c: Champion = G.player
	var rig = m.camera_rig
	c.invulnerable_count += 1
	m.game_speed = 2.0
	# empty arena: the walk itself (picking, HUD hit areas, controller, nav) is under test, not the bots
	m.spawner = null
	for u in m.units.duplicate():
		if u.kind == G.Kind.MINION:
			m.remove_unit(u)
	for ch in m.champions:
		if ch != c:
			ch.controller = null
			ch.teleport(ch.spawn_point)
	await _wait(0.5)
	var brush_cells := {}
	var lane_cells: Array = []
	for j in nav.h:
		for i in nav.w:
			var k := j * nav.w + i
			if nav.walk[k] == 0:
				continue
			var id: int = nav.brush[k]
			if id != 0:
				if not brush_cells.has(id):
					brush_cells[id] = []
				brush_cells[id].append(Vector2i(i, j))
			else:
				lane_cells.append(Vector2i(i, j))
	var vp := get_viewport().get_visible_rect().size
	_say("CLICK viewport %s locked=%s" % [str(vp), str(rig.locked)])
	var total := 0
	for id in brush_cells.keys():
		var cells: Array = brush_cells[id]
		var bad := 0
		for n in n_pairs:
			var goal := nav.cell_center(cells[rng.randi() % cells.size()])
			var start := Vector3.INF
			for attempt in 400:
				var q: Vector2i = lane_cells[rng.randi() % lane_cells.size()]
				var d := G.flat_dist(nav.cell_center(q), goal)
				if d > 4.0 and d < 11.0:
					start = nav.cell_center(q)
					break
			if start == Vector3.INF:
				continue
			c.teleport(start)
			c.issue_stop()
			rig.snap_to(start)
			await get_tree().process_frame
			var sp := _screen_of(goal)
			if sp.x < 0 or sp.y < 0 or sp.x > vp.x or sp.y > vp.y:
				continue
			await _rclick(sp)
			var picked: Vector3 = m.player_controller.mouse_ground
			var hov = m.player_controller.hovered
			var hov_name: String = ("%s(team %d)" % [hov.display_name, hov.team]) if hov != null and is_instance_valid(hov) else "-"
			var cmd0: int = c.cmd
			var prev := c.global_position
			var len := 0.0
			var t0: float = m.time
			var trace := PackedVector3Array([prev])
			var acc := 0.0
			await get_tree().process_frame
			while m.time - t0 < 10.0 and c.moving:
				await get_tree().process_frame
				var p := c.global_position
				var st := G.flat_dist(prev, p)
				len += st
				acc += st
				prev = p
				if acc >= 0.5:
					acc = 0.0
					trace.append(p)
			total += 1
			var reflen := _path_len(ref.find_path(start, goal), start)
			var short := G.flat_dist(c.global_position, goal)
			var reason := ""
			if G.flat_dist(picked, goal) > 0.9:
				reason = "PICKED %.1f m away from the clicked cell (cmd=%d)" % [G.flat_dist(picked, goal), c.cmd]
			elif short > 1.0:
				reason = "STOPPED %.1f m short" % short
			elif len > reflen * 1.2 and len - reflen > 1.0:
				reason = "DETOUR x%.2f" % (len / maxf(reflen, 0.01))
			elif _loops(trace) and len > reflen * 1.05:
				reason = "LOOP"
			if reason != "":
				bad += 1
				_say("CLICK brush%d %s: from (%.1f, %.1f) click cell (%.1f, %.1f) screen (%.0f, %.0f) walked %.1f m vs %.1f m, hovered %s, order %d" % [
					id, reason, start.x, start.z, goal.x, goal.z, sp.x, sp.y, len, reflen, hov_name, cmd0])
		findings += bad
		_say("CLICK brush%d: %d clicks, %d flagged" % [id, n_pairs, bad])
	_say("RESULT " + ("clean" if findings == 0 else "%d findings" % findings))


# ===================================================================== screenshots
func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var dir := "user://path_nav"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := "%s/%s.png" % [dir, name]
	get_viewport().get_texture().get_image().save_png(path)
	print("NAVAUDIT SHOT ", ProjectSettings.globalize_path(path))


## The player's champion starts in the lane beside each outer turret's brush and is sent to the brush centre.
func _shot_audit() -> void:
	var c: Champion = G.player
	var rig = m.camera_rig
	c.invulnerable_count += 1
	m.spawner = null
	for ch in m.champions:
		if ch != c:
			ch.teleport(ch.spawn_point)
	m.game_speed = 1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--navspot="):
			var xz := a.substr(10).split(",")
			var sp := nav.nearest_walkable(Vector3(float(xz[0]) + 4.0, 0, float(xz[1]) + 4.0))
			c.teleport(sp)
			rig.snap_to(Vector3(float(xz[0]), 0, float(xz[1])))
			rig.locked = false
			rig.target_distance = 12.0
			rig.distance = 12.0
			await _wait(1.0)
			await _shot("spot_%s_%s" % [xz[0], xz[1]])
			_draw_edges(nav.walk, Color(1, 0.1, 0.1), false)
			_draw_edges(nav.brush, Color(0.1, 1.0, 0.2), true)
			await _wait(0.3)
			await _shot("spot_%s_%s_nav" % [xz[0], xz[1]])
			return
	if "--navmid" in OS.get_cmdline_user_args():
		await _mid_shots(c, rig)
		return
	# right brush = the one near the Chaos outer turret (brush 4), left = Order outer turret (brush 1)
	for id in [4, 1]:
		var cells: Array = []
		var cen := Vector3.ZERO
		for j in nav.h:
			for i in nav.w:
				if nav.brush[j * nav.w + i] == id and nav.walk[j * nav.w + i] == 1:
					cells.append(Vector2i(i, j))
					cen += nav.cell_center(Vector2i(i, j))
		cen /= float(cells.size())
		var goal := nav.nearest_walkable(cen)
		var start := nav.nearest_walkable(goal + Vector3(7.0, 0, 6.0))
		if id == 1:
			start = nav.nearest_walkable(goal + Vector3(6.0, 0, 7.0))
		c.teleport(start)
		c.issue_stop()
		rig.snap_to(start)
		await _wait(0.6)
		await _shot("brush%d_00_before" % id)
		# the click, exactly as the player makes it: cursor over the brush centre, right button
		await _rclick(_screen_of(goal))
		for k in 5:
			await _wait(0.7)
			await _shot("brush%d_%02d" % [id, k + 1])
		print("NAVAUDIT SHOTWALK brush%d start (%.1f, %.1f) goal (%.1f, %.1f) end (%.1f, %.1f) cmd %d" % [id, start.x, start.z, goal.x, goal.z, c.global_position.x, c.global_position.z, c.cmd])


## Red / green line strips along every walkable / blocked (or brush) cell edge, as in env_harness `nav`.
func _draw_edges(grid: PackedByteArray, col: Color, nonzero: bool) -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for j in nav.h - 1:
		for i in nav.w - 1:
			var a: int = grid[j * nav.w + i]
			var b: int = grid[j * nav.w + i + 1]
			var c: int = grid[(j + 1) * nav.w + i]
			if nonzero:
				a = mini(a, 1)
				b = mini(b, 1)
				c = mini(c, 1)
			if a != b:
				var x := nav.origin.x + (i + 1) * nav.cell
				var z0 := nav.origin.y + j * nav.cell
				var y := nav._h(i, j) + 0.08
				im.surface_add_vertex(Vector3(x, y, z0))
				im.surface_add_vertex(Vector3(x, y, z0 + nav.cell))
			if a != c:
				var z := nav.origin.y + (j + 1) * nav.cell
				var x0 := nav.origin.x + i * nav.cell
				var y2 := nav._h(i, j) + 0.08
				im.surface_add_vertex(Vector3(x0, y2, z))
				im.surface_add_vertex(Vector3(x0 + nav.cell, y2, z))
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.no_depth_test = true
	mi.material_override = mat
	m.add_child(mi)


# ===================================================================== grass meshes vs nav brush
func _grass_audit() -> void:
	var list: Array = []
	_find_grass(get_tree().root, list)
	_say("GRASS %d mesh instances use the brush material" % list.size())
	var cover := {}   # cell index -> triangles of grass whose centroid lies in it
	for mi in list:
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		var xf: Transform3D = (mi as MeshInstance3D).global_transform
		for si in mesh.get_surface_count():
			if (mi as MeshInstance3D).get_surface_override_material(si) != MapBuilder.grass_material:
				continue
			var arr := mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx = arr[Mesh.ARRAY_INDEX]
			var ntri: int = (idx.size() if idx != null and idx.size() > 0 else v.size()) / 3
			for t in ntri:
				var a: Vector3
				var b: Vector3
				var c: Vector3
				if idx != null and idx.size() > 0:
					a = v[idx[t * 3]]
					b = v[idx[t * 3 + 1]]
					c = v[idx[t * 3 + 2]]
				else:
					a = v[t * 3]
					b = v[t * 3 + 1]
					c = v[t * 3 + 2]
				var g: Vector3 = xf * ((a + b + c) / 3.0)
				var q := nav.to_cell(g)
				if nav.in_bounds(q):
					cover[q.y * nav.w + q.x] = int(cover.get(q.y * nav.w + q.x, 0)) + 1
	var no_nav: Array = []
	var with_nav := 0
	var on_wall := 0
	for k in cover.keys():
		if ref.walk[k] == 0:
			on_wall += 1
		elif nav.brush[k] != 0:
			with_nav += 1
		else:
			no_nav.append(k)
	_say("GRASS cells covered by grass triangles: %d | on nav brush %d | on blocked terrain %d | on WALKABLE non-brush cells %d" % [cover.size(), with_nav, on_wall, no_nav.size()])
	for comp in _components(no_nav):
		var cen := Vector3.ZERO
		for k in comp:
			cen += nav.cell_center(Vector2i(k % nav.w, k / nav.w))
		cen /= float(comp.size())
		_say("  visual grass on walkable ground without nav brush: %d cells around (%.1f, %.1f)" % [comp.size(), cen.x, cen.z])


func _find_grass(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				if mi.get_surface_override_material(i) == MapBuilder.grass_material and MapBuilder.grass_material != null:
					out.append(mi)
					break
	for c in n.get_children():
		_find_grass(c, out)


## Walk across the middle grass patch (the League sliver at (66.5..69.5, -61..-58)); --navwall re-blocks the sliver
## to reproduce the old behaviour for before / after shots.
func _mid_shots(c: Champion, rig) -> void:
	var tag := "after"
	if "--navwall" in OS.get_cmdline_user_args():
		tag = "before"
		for k in nav.opened_cells:
			nav.walk[k] = 0
			nav.astar.set_point_solid(Vector2i(k % nav.w, k / nav.w), true)
	var start := Vector3(63.8, 0, -63.2)
	var goal := Vector3(71.2, 0, -56.0)
	start = nav.nearest_walkable(start)
	goal = nav.nearest_walkable(goal)
	rig.target_distance = 13.0
	rig.distance = 13.0
	c.teleport(start)
	c.issue_stop()
	rig.snap_to(start)
	await _wait(0.6)
	await _shot("mid_%s_00" % tag)
	await _rclick(_screen_of(goal))
	await get_tree().process_frame
	var wp := []
	for q in c.path:
		wp.append("(%.1f, %.1f)" % [q.x, q.z])
	print("NAVAUDIT MID %s: order %d move_goal (%.1f, %.1f) path waypoints %s" % [tag, c.cmd, c.move_goal.x, c.move_goal.z, ", ".join(wp)])
	var prev := c.global_position
	var len := 0.0
	var k := 1
	var next_shot := 0.0
	var t := 0.0
	while c.moving and t < 12.0:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		len += G.flat_dist(prev, c.global_position)
		prev = c.global_position
		if t >= next_shot:
			await _shot("mid_%s_%02d" % [tag, k])
			k += 1
			next_shot += 0.8
	print("NAVAUDIT MID %s: start (%.1f, %.1f) goal (%.1f, %.1f) direct %.1f m walked %.1f m in %.1f s, picked %s" % [
		tag, start.x, start.z, goal.x, goal.z, G.flat_dist(start, goal), len, t, str(m.player_controller.mouse_ground)])


# ===================================================================== respawn camera
func _respawn_check() -> void:
	var c: Champion = G.player
	var rig = m.camera_rig
	var allies: Array = []
	for ch in m.champions:
		if ch != c and ch.team == c.team:
			allies.append(ch)
	var fails := 0
	for variant in ["locked", "free", "free+spectate"]:
		rig.locked = variant == "locked"
		c.respawn_timer = 99.0
		c.die(null, null)
		await _wait(0.4)
		if variant == "free+spectate":
			m.hud._set_spectate(allies[0])
		else:
			rig.focus = c.global_position + Vector3(25.0, 0, -18.0)   # free camera panned away while dead
		await _wait(0.5)
		var away := G.flat_dist(rig.focus, c.global_position)
		c.respawn_timer = 0.1
		await _wait(0.6)
		await get_tree().process_frame
		var d := G.flat_dist(rig.focus, c.global_position)
		var ok: bool = not c.dead and d < 0.5 and rig.spectate == null and m.hud.spectating == null
		if not ok:
			fails += 1
		print("NAVAUDIT RESPAWN %-14s camera %.1f m off while dead -> %.2f m after respawn, spectate=%s hud.spectating=%s: %s" % [
			variant, away, d, str(rig.spectate), str(m.hud.spectating), "PASS" if ok else "FAIL"])
		await _shot("respawn_%s" % variant.replace("+", "_"))
	print("NAVAUDIT RESPAWN RESULT ", "PASS" if fails == 0 else "%d FAIL" % fails)
