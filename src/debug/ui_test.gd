class_name UITest
extends Node
## QA: drives menu -> champion select -> loading -> match -> pause -> end screen, screenshotting each step.
## Usage (windowed): godot --path . -- --uitest

var main = null
var shot_dir := "user://uitest"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--uidir="):
			shot_dir = "user://" + a.substr(8)   # [champ-select] own screenshot folder so parallel runs do not overwrite each other
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shot_dir))
	_run()


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var p := "%s/%s.png" % [shot_dir, name]
	img.save_png(p)
	print("UITEST SHOT ", ProjectSettings.globalize_path(p))


func _run() -> void:
	await _wait(2.0)
	await _shot("01_menu")
	main.screen.on_action("settings")
	await _wait(0.6)
	await _shot("02_settings")
	main.screen.on_action("settings_back")
	main.screen.on_action("play")
	await _wait(2.0)
	await _shot("03_champ_select")
	main.screen.on_action("reroll")
	main.screen.on_action("sum:1")
	await _wait(0.8)
	await _shot("04_summoner_popup")
	main.screen.on_action("pick_sum:Ghost")
	# [champ-select] custom lineup: pick every bot champion + a level per bot, then verify the match spawns exactly that
	var cs: ChampSelect = main.screen
	cs.on_action("slot:6")
	await _wait(0.8)
	await _shot("04b_champion_picker")
	# quick actions + trading with the player through the picker keep the lineup duplicate-free
	var before_me: String = cs.me()
	var before_ally: String = cs.slots[1].champion
	cs.on_action("slot:1")
	cs.on_action("pick:" + before_me)
	print("UITEST TRADE_OK ", cs.me() == before_ally and cs.slots[1].champion == before_me)
	cs.on_action("rand:enemy")
	cs.on_action("rand:ally")
	cs.on_action("all:2")
	var uniq := {}
	for e in cs.lineup():
		uniq[e.champion] = true
	print("UITEST RANDOMIZE_UNIQUE ", uniq.size() == 10, " all_level2=", cs.slots[3].difficulty == 2 and cs.slots[9].difficulty == 2)
	var want := {1: ["Garen", 3], 2: ["Lux", 2], 3: ["Sona", 1], 4: ["Veigar", 0],
			5: ["Yasuo", 0], 6: ["Darius", 1], 7: ["Leona", 2], 8: ["Jinx", 3], 9: ["Annie", 3]}
	cs._pick_slot = -1
	for i in want:
		cs.on_action("slot:%d" % i)
		cs.on_action("pick:" + want[i][0])
		cs.on_action("diff:%d:%d" % [i, want[i][1]])
	await _wait(1.2)
	await _shot("04c_custom_lineup")
	cs.hover_id = "diff:7:3"
	cs._mouse = Vector2(1760, 520)
	await _wait(0.5)
	await _shot("04d_hover_difficulty")
	cs.hover_id = "slot:3"
	cs._mouse = Vector2(300, 520)
	await _wait(0.5)
	await _shot("04e_hover_plate")
	cs.hover_id = ""
	var chosen: Array = cs.lineup()
	print("UITEST LINEUP ", JSON.stringify(chosen))
	var mine: String = chosen[0].champion
	var dup := {}
	for e in chosen:
		dup[e.champion] = true
	print("UITEST NO_DUPLICATES ", dup.size() == 10)
	cs.on_action("lock")
	await _wait(1.9)
	await _shot("05_loading")
	while main.current == null:
		await _wait(0.2)
	await _wait(5.0)
	await _shot("06_ingame")
	_check_lineup(chosen, want)
	var c = G.player
	if c.augments_pending > 0:
		main.current.get_offer(c)
		main.current.choose_augment(c, 0)
	main.current.hud.toggle_shop()
	await _wait(0.8)
	await _shot("06b_shop")
	main.current.hud.toggle_shop()
	Input.action_press("scoreboard")
	await _wait(0.5)
	await _shot("06c_scoreboard")
	Input.action_release("scoreboard")
	main.current.pause_menu.open()
	await _wait(0.5)
	await _shot("07_pause")
	main.current.pause_menu.close()
	await _wait(1.0)
	main.current.end_game(G.player.team)
	await _wait(4.0)
	await _shot("08_victory")
	main.current.end_screen.on_action("continue")
	await _wait(1.2)
	await _shot("09_stats")
	print("UITEST DONE")
	get_tree().quit()


## [champ-select] The match must have spawned exactly the chosen champions on each team, and each bot must carry its level.
func _check_lineup(chosen: Array, want: Dictionary) -> void:
	var ok := true
	var spawned := []
	for c in main.current.champions:
		var lvl := -1
		if not c.is_player and c.controller != null and "level" in c.controller:
			lvl = int(c.controller.level)
		spawned.append({"team": int(c.team), "champion": c.alias, "difficulty": -1 if c.is_player else lvl})
	print("UITEST SPAWNED ", JSON.stringify(spawned))
	print("UITEST G.lineup ", JSON.stringify(G.lineup))
	for e in chosen:
		var found := false
		for sp in spawned:
			if sp.team == e.team and sp.champion == e.champion:
				found = true
				if e.difficulty >= 0 and sp.difficulty != e.difficulty:
					print("UITEST FAIL level of ", e.champion, " is ", sp.difficulty, " expected ", e.difficulty)
					ok = false
		if not found:
			print("UITEST FAIL missing champion ", e.champion, " on team ", e.team)
			ok = false
	if spawned.size() != 10:
		print("UITEST FAIL spawned ", spawned.size())
		ok = false
	for i in want:
		var tm := 0 if i < 5 else 1
		var hit := false
		for sp in spawned:
			if sp.team == tm and sp.champion == want[i][0]:
				hit = true
		if not hit:
			print("UITEST FAIL wanted ", want[i][0], " on team ", tm)
			ok = false
	# remembered setup: levels of all 9 bots and the hand-picked champions come back in the next champion select
	var cs2 := ChampSelect.new()
	cs2._init_lineup()
	for i in range(1, 10):
		if cs2.slots[i].difficulty != want[i][1] or cs2.slots[i].champion != want[i][0]:
			print("UITEST FAIL prefs slot ", i, " ", cs2.slots[i].champion, " ", cs2.slots[i].difficulty)
			ok = false
	cs2.free()
	print("UITEST LINEUP_", "OK" if ok else "FAILED")
