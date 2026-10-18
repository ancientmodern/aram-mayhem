extends Node
## [healthbar] Health-bar behaviour QA: frame sequences of League's fade / burst / flash / shake / heal / death on
## champion, minion and turret bars. Writes per-frame crops around the bar plus a log of bar state.
## tools/preview.sh 300 -- --champ=Ezreal --harness=res://src/ui/world/hb_harness.gd --shotdir=hb_seq

var match_ref = null
var main = null
var shot_dir := "user://hb_seq"
var ov: WorldOverlay
var cam: Camera3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			shot_dir = "user://" + a.substr(10)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shot_dir))
	_run()


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


## `n` frames of a crop around `u`'s bar; every frame logs the overlay clock and the unit's bar state.
func _seq(tag: String, u: Unit, n: int, every := 1) -> void:
	for i in n:
		await RenderingServer.frame_post_draw
		if i % every != 0:
			continue
		var img := get_viewport().get_texture().get_image()
		var k := Vector2(img.get_size()) / get_viewport().get_visible_rect().size
		var b = ov._bars.get(u.get_instance_id())
		var base: Vector3 = u.global_position
		var sp: Vector2 = ov._anchor(base, b.hbh if b != null else 100.0, b.full if b != null else false, u.stats.size) * k
		var r := Rect2i(Vector2i(sp) - Vector2i(150, 70), Vector2i(300, 110)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		if r.size.x <= 0 or r.size.y <= 0:
			continue
		img.get_region(r).save_png("%s/%s_%03d.png" % [shot_dir, tag, i])
		if b != null:
			print("HBSEQ %s %03d t=%.3f hp=%.0f/%.0f fade=%.0f burst=%.0f flash=%.2f shake=%.2f heal=%.2f" % [tag, i, ov._time,
					u.hp, u.stats.max_hp, b.fade_hp, b.burst_hp, b.flash_t, b.shake_t, b.heal_t])


func _full(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [shot_dir, n])


func _nearest(kind: int, enemy: bool, from: Vector3) -> Unit:
	var best: Unit = null
	var bd := INF
	for u in match_ref.units:
		if u.dead or u.kind != kind or u == G.player or (u.team != G.player.team) != enemy:
			continue
		var d := G.flat_dist(u.global_position, from)
		if d < bd:
			bd = d
			best = u
	return best


## Raw HP change (bypasses resistances / turret fortification so every step is an exact fraction of max HP).
func _hit(_src: Unit, t: Unit, frac: float) -> void:
	t.hp = maxf(t.hp - t.stats.max_hp * frac, 1.0)


func _run() -> void:
	await _wait(1.0)
	ov = match_ref.overlay
	cam = match_ref.player_controller.rig.cam
	var c: Champion = G.player
	if c.augments_pending > 0:
		match_ref.get_offer(c)
		match_ref.choose_augment(c, 0)
	for ch in match_ref.champions:
		if ch != c:
			ch.controller = null      # freeze bots so the bars stay put
	var mid := G.lol_pos(6400.0, 0.0, 6350.0)
	var en := _nearest(G.Kind.CHAMPION, true, c.global_position)
	var al := _nearest(G.Kind.CHAMPION, false, c.global_position)
	c.teleport(match_ref.nav.nearest_walkable(mid))
	# farther apart than champion acquisition range (8 m) so nobody auto-attacks during the sequences
	en.teleport(match_ref.nav.nearest_walkable(mid + Vector3(8.5, 0, -4.0)))
	al.teleport(match_ref.nav.nearest_walkable(mid + Vector3(-8.5, 0, 4.0)))
	c.level = 9
	en.level = 9
	await _wait(1.5)
	await _full("overview")
	# A: three 6% hits 0.45 s apart on an enemy champion (normal fade chunk, no burst)
	for i in 3:
		_hit(c, en, 0.06)
		await _seq("A%d" % i, en, 27)
	await _seq("A_end", en, 30, 3)
	# B: 40% burst on the enemy champion (burst chunk + flash + shake)
	_hit(c, en, 0.40)
	await _seq("B", en, 75)
	# C: 25% heal (burst heal glow)
	en.hp = minf(en.hp + en.stats.max_hp * 0.25, en.stats.max_hp)
	await _seq("C", en, 24)
	# D: self bar: shields, then hits (red chunk), then a 40% burst (red burst meter)
	c.add_shield(300.0, 20.0)
	c.add_shield(150.0, 20.0, null, G.DmgType.MAGIC)
	await _wait(0.3)
	_hit(en, c, 0.08)
	await _seq("D", c, 27)
	_hit(en, c, 0.40)
	await _seq("D_burst", c, 60)
	# E: enemy champion dies (bar death flipbook)
	Combat.deal(c, en, 99999.0, G.DmgType.TRUE, {"show_number": false})
	await _seq("E", en, 32)
	# F: lane minions meet; hit an enemy minion (instant drop, no chunk)
	c.hp = c.stats.max_hp
	c.invulnerable_count += 1      # keep the camera's champion alive through the waves and turret shots
	Engine.time_scale = 6.0
	await _wait(14.0)
	Engine.time_scale = 1.0
	var mn := _nearest(G.Kind.MINION, true, c.global_position)
	if mn != null:
		c.teleport(match_ref.nav.nearest_walkable(mn.global_position + G.flat_dir(mn.global_position, c.global_position) * 4.0))
		await _wait(0.5)
		await _full("minions")
		_hit(c, mn, 0.3)
		await _seq("F", mn, 12)
	# G: enemy outer turret: small hits (fade only) then a 15% hit (burst + flash + shake), then shatter
	var tu: Unit = null
	var bd := INF
	for s in match_ref.structures:
		if s.kind == G.Kind.TURRET and s.team != c.team and not s.dead:
			var d := G.flat_dist(s.global_position, c.global_position)
			if d < bd:
				bd = d
				tu = s
	if tu != null:
		c.teleport(match_ref.nav.nearest_walkable(tu.global_position + G.flat_dir(tu.global_position, mid) * 9.0))
		await _wait(0.8)
		await _full("turret")
		_hit(c, tu, 0.04)
		await _seq("G0", tu, 20)
		_hit(c, tu, 0.15)
		await _seq("G1", tu, 60)
		await _full("turret_after")
	print("HBSEQ DONE")
	get_tree().quit()
