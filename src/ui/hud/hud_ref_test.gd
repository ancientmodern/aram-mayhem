extends Node
## [hud-ref] HUD vs real-League-frames harness (--harness=res://src/ui/hud/hud_ref_test.gd, use --res=2000x1125):
## ally team frame row, dead allies, BACK IN widget + spectate click, tooltips, kill banner, status labels, damage numbers.
## Screenshots go to user://hudref (override with --shotdir=NAME).

var main = null
var match_ref = null
var shot_dir := "user://hudref"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			shot_dir = "user://" + a.substr(10)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shot_dir))
	_run()


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var p := "%s/%s.png" % [shot_dir, name]
	img.save_png(p)
	print("HUDREF SHOT ", ProjectSettings.globalize_path(p))


func _move(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = get_viewport().get_final_transform() * p
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame


func _click(p: Vector2) -> void:
	await _move(p)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = get_viewport().get_final_transform() * p
	ev.global_position = ev.position
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func _run() -> void:
	await _wait(2.5)
	var c: Champion = G.player
	var hud = match_ref.hud
	var enemy = null
	var allies := []
	for ch in match_ref.champions:
		if ch.team != c.team and enemy == null:
			enemy = ch
		elif ch.team == c.team and ch != c:
			allies.append(ch)
	for i in 3:
		c.gain_xp(400.0)
	await _wait(0.5)
	await _shot("a_alive")
	# a dead ally (silver ring, red seconds) next to living ones; ult state on another
	allies[0].die(enemy)
	await _wait(0.6)
	await _shot("b_ally_dead")
	# tooltips: ability (rich markup) + item
	c.gold = 4000.0
	ItemDB.buy(c, 1036)
	await _wait(0.3)
	await _move(hud.L.r("PlayerFrame:Ability1_BorderAvailable").get_center())
	await _wait(0.4)
	await _shot("c_tip_ability")
	await _move(hud.L.r("Inventory:InventoryItem0_Backdrop").get_center())
	await _wait(0.4)
	await _shot("d_tip_item")
	await _move(Vector2(300, 300))
	# kill banner + announcement
	G.champion_killed.emit(enemy, c, [allies[1]])
	G.announce("Enemy slain", "", G.COLOR_ALLY)
	await _wait(0.7)
	await _shot("e_banner")
	# damage numbers + status labels on an enemy standing next to the player
	await _wait(2.5)
	await _wait(3.0)
	for ch in match_ref.champions:
		if ch.team != c.team and not ch.dead:
			enemy = ch
			break
	print("HUDREF enemy ", enemy.alias, " dead=", enemy.dead, " pos=", enemy.global_position, " player=", c.global_position)
	hud.ann = {}
	hud.ann_queue.clear()
	c.global_position = Vector3(42.0, -1.5, -41.0)
	c.issue_move(c.global_position)
	match_ref.camera_rig.snap_to(c.global_position)
	enemy.global_position = c.global_position + Vector3(4.0, 0.0, -4.0)
	enemy.visible_to[c.team] = true
	enemy.hp = enemy.stats.max_hp
	var rt := Buff.new("test_root", 6.0)
	rt.cc = Buff.CC.ROOT
	rt.is_debuff = true
	enemy.add_buff(rt, c)
	await _wait(0.3)
	Combat.deal(c, enemy, 78.0, G.DmgType.PHYSICAL, {"is_attack": true})
	enemy.hp = enemy.stats.max_hp
	await _wait(0.12)
	Combat.deal(c, enemy, 130.0, G.DmgType.MAGIC, {"is_spell": true})
	enemy.hp = enemy.stats.max_hp
	await _wait(0.12)
	Combat.deal(c, enemy, 9.0, G.DmgType.TRUE, {"is_spell": true})
	enemy.hp = enemy.stats.max_hp
	await _wait(0.12)
	Combat.deal(c, enemy, 250.0, G.DmgType.PHYSICAL, {"is_attack": true, "is_crit": true})
	enemy.hp = enemy.stats.max_hp
	await _wait(0.3)
	print("HUDREF enemy after ", enemy.alias, " dead=", enemy.dead, " pos=", enemy.global_position, " vis=", enemy.visible, " hp=", enemy.hp)
	await _shot("h_nums_status")
	var st := Buff.new("test_stun", 3.0)
	st.cc = Buff.CC.STUN
	st.is_debuff = true
	enemy.add_buff(st, c)
	await _wait(0.4)
	await _shot("h_stun")
	enemy.remove_buffs_by_id("test_root")
	enemy.remove_buffs_by_id("test_stun")
	# player dead: grey world + BACK IN + portraits; click the first portrait to spectate
	c.die(enemy)
	await _wait(1.2)
	await _shot("f_dead")
	for h in hud.cv_dead.hits:
		if String(h[1]).begins_with("spec:"):
			await _click((h[0] as Rect2).get_center())
			break
	await _wait(0.8)
	print("HUDREF spectating=", hud.spectating != null, " rig=", match_ref.camera_rig.spectate != null)
	await _shot("g_spectate")
	print("HUDREF DONE")
	get_tree().quit()
