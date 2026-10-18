extends Node
## [world-ui] Visual QA harness: health bars, floating text, hover outline, indicators, turret range.
## tools/preview.sh 200 -- --champ=Ezreal --harness=res://src/ui/world/wui_harness.gd --shotdir=wui_h

var match_ref = null
var main = null
var shot_dir := "user://wui_h"
var pc: PlayerController


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			shot_dir = "user://" + a.substr(10)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shot_dir))
	_run()


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [shot_dir, n])
	print("WUI SHOT ", n, " cursor=", pc._cursor_state, " hovered=", pc.hovered.display_name if pc.hovered else "-")


func _mouse_to(p: Vector3) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = get_viewport().get_final_transform() * pc.rig.cam.unproject_position(p)
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	Input.warp_mouse(ev.position)


func _nearest(kind: int, enemy: bool) -> Unit:
	var best: Unit = null
	var bd := INF
	for u in match_ref.units:
		if u.dead or u.kind != kind or u == G.player or (u.team != G.player.team) != enemy:
			continue
		var d := G.flat_dist(u.global_position, G.player.global_position)
		if d < bd:
			bd = d
			best = u
	return best


func _run() -> void:
	await _wait(1.0)
	var c: Champion = G.player
	pc = match_ref.player_controller
	if c.augments_pending > 0:
		match_ref.get_offer(c)
		match_ref.choose_augment(c, 0)
	# clean outline check at the fountain: ally (blue) + an enemy pulled next to us (red)
	var al := _nearest(G.Kind.CHAMPION, false)
	var en := _nearest(G.Kind.CHAMPION, true)
	if al != null and en != null:
		en.teleport(match_ref.nav.nearest_walkable(c.global_position + Vector3(2.5, 0, -1.5)))
		al.teleport(match_ref.nav.nearest_walkable(c.global_position + Vector3(-2.5, 0, 1.0)))
		await _wait(0.1)
		PlayerController.set_unit_outline(en, pc._outline_enemy)
		PlayerController.set_unit_outline(al, pc._outline_ally)
		await _wait(0.1)
		await _shot("h_outlines")
		PlayerController.set_unit_outline(en, null)
		PlayerController.set_unit_outline(al, null)
	# let the lanes meet
	Engine.time_scale = 6.0
	await _wait(32.0)
	Engine.time_scale = 1.0
	# stand behind our minion wave, a little up the lane
	var e := _nearest(G.Kind.CHAMPION, true)
	var mn := _nearest(G.Kind.MINION, true)
	var tgt: Vector3 = (mn.global_position if mn != null else e.global_position)
	c.teleport(match_ref.nav.nearest_walkable(tgt + G.flat_dir(tgt, c.global_position) * 7.0))
	c.add_shield(250.0, 20.0)
	c.add_shield(120.0, 20.0, null, G.DmgType.MAGIC)
	c.level = 7
	await _wait(0.6)
	# floating text samples on the nearest enemy unit
	var victim: Unit = _nearest(G.Kind.MINION, true)
	if victim == null:
		victim = e
	var ov: WorldOverlay = match_ref.overlay
	var ap := ov._text_anchor(victim)
	ov.ft.spawn("PhysicalDamage", "87", victim, ap)
	await _wait(0.12)
	ov.ft.spawn("MagicalDamage", "142", victim, ap)
	await _wait(0.12)
	ov.ft.spawn("PhysicalDamageCritical", "311", victim, ap, "crit_physical")
	ov.ft.spawn("TrueDamage", "40", victim, ap)
	ov.ft.spawn("Heal", "+65", c, ov._text_anchor(c))
	ov.ft.spawn("Gold", "+21", victim, ap, "gold")
	ov.level_up_fx(c)
	# hover an enemy for the outline + cursor
	var h := _nearest(G.Kind.CHAMPION, true)
	if h == null or G.flat_dist(h.global_position, c.global_position) > 18.0:
		h = victim
	_mouse_to(h.global_position + Vector3(0, 1.0, 0))
	await _wait(0.15)
	PlayerController.set_unit_outline(h, pc._outline_enemy)
	var ally := _nearest(G.Kind.MINION, false)
	if ally != null:
		PlayerController.set_unit_outline(ally, pc._outline_ally)
	await _shot("a_bars_text_hover")
	await _wait(0.25)
	await _shot("a2_text_later")
	# line skillshot indicator (Ezreal Q)
	var away := G.flat_dir(c.global_position, h.global_position)
	_mouse_to(c.global_position + away * 6.0)
	for i in 3:
		c.ability(i).level = maxi(c.ability(i).level, 1)
		c.ability(i).cd = 0.0
	pc.aiming = 0
	await _wait(0.2)
	print("WUI line vis=", pc._ind_main.visible, " xf=", pc._ind_main.global_transform, " ind=", c.ability(0).indicator, " mouse=", pc.mouse_ground, " champ=", c.global_position)
	await _shot("b_line_indicator")
	# cone + circle (force the indicator type on Q for the check)
	var ab := c.ability(0)
	var old_ind := ab.indicator
	ab.indicator = Ability.Ind.CONE
	ab.ind_angle = 50.0
	await _wait(0.15)
	await _shot("c_cone_indicator")
	ab.indicator = Ability.Ind.CIRCLE
	ab.ind_radius = 250.0
	await _wait(0.15)
	await _shot("d_circle_indicator")
	ab.indicator = old_ind
	pc._cancel_aim()
	# attack range (A armed)
	pc.attack_move_armed = true
	_mouse_to(h.global_position + Vector3(0, 1.0, 0))
	await _wait(0.15)
	await _shot("e_attack_range")
	pc.attack_move_armed = false
	# turret range: just outside, then inside an enemy turret's range
	var tur: Unit = null
	for s in match_ref.structures:
		if s.kind == G.Kind.TURRET and not s.dead and s.team != c.team and s.tier == Turret.Tier.OUTER:
			tur = s
	if tur != null:
		var r: float = tur.attack_range_m() + tur.radius
		var dir := G.flat_dir(tur.global_position, match_ref.nexus_units[c.team].global_position)
		c.teleport(match_ref.nav.nearest_walkable(tur.global_position + dir * (r + 2.0)))
		match_ref.camera_rig.snap_to(c.global_position)
		await _wait(0.4)
		await _shot("f_turret_near")
		c.teleport(match_ref.nav.nearest_walkable(tur.global_position + dir * (r - 2.5)))
		match_ref.camera_rig.snap_to(c.global_position)
		await _wait(1.2)
		await _shot("g_turret_aggro")
	print("WUI DONE")
	get_tree().quit()
