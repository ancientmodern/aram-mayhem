class_name UITest
extends Node
## QA: drives menu -> champion select -> loading -> match -> pause -> end screen, screenshotting each step.
## Usage (windowed): godot --path . -- --uitest

var main = null
var shot_dir := "user://uitest"


func _ready() -> void:
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
	main.screen.on_action("lock")
	await _wait(1.9)
	await _shot("05_loading")
	while main.current == null:
		await _wait(0.2)
	await _wait(5.0)
	await _shot("06_ingame")
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
