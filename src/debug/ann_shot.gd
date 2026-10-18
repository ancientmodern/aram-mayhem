extends Node
## [ui-polish] Screenshots of HUD announcements / kill feed: fires a kill callout, a multikill and a turret banner.
## Usage: tools/preview.sh 90 -- --champ=Ahri --harness=res://src/debug/ann_shot.gd --res=2560x1440 --novsync
var main = null
var match_ref = null


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	var d := "user://ann_shot"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(d))
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [d, n])
	print("ANNSHOT ", ProjectSettings.globalize_path("%s/%s.png" % [d, n]))


func _ready() -> void:
	_run()


func _run() -> void:
	await _wait(3.0)
	var me = G.player
	var enemy = null
	var ally = null
	for c in match_ref.champions:
		if c.team != me.team and enemy == null:
			enemy = c
		if c.team == me.team and c != me and ally == null:
			ally = c
	for i in 4:
		G.champion_killed.emit(enemy, me if i % 2 == 0 else ally, [ally])
		if i == 1:
			G.announcement.emit("Double Kill", "", Color(1, 0.85, 0.3))
		await _wait(0.1)
	G.champion_killed.emit(me, enemy, [])
	G.announcement.emit("An ally has been slain", "", Color(0.4, 0.7, 1))
	await _wait(0.7)
	await _shot("a1_kill_banner")
	await _wait(3.6)
	G.announcement.emit("Turret destroyed", "", Color(1, 0.85, 0.3))
	await _wait(0.7)
	await _shot("a2_turret_banner")
	get_tree().quit()
